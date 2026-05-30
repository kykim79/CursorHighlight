import AppKit
import Combine
import CoreGraphics
import SwiftUI

// MARK: - KeyboardHotkeyHandler
//
// 전역 키보드 단축키 핸들링:
//   ⌃⌥{S/M/K/1~6/0/=/-}  스포트라이트·돋보기·키스트로크·색상·줌 토글
//   ⌘⇧{3/4/5}            스크린샷 — 오버레이 일시 숨김 (관찰만, 통과시킴)
//   ⌘V                   클립보드 인디케이터 (관찰만, 통과시킴)
//   기타 ⌃·⌥·⌘ 조합        키스트로크 표시 (비밀번호 필드 제외, 관찰만, 통과시킴)
//
// 구현: NSEvent.addGlobalMonitorForEvents는 수동(passive) 모니터라 이벤트를
// 가로채지 못한다 → 예전엔 ⌃⌥M이 우리 핸들러와 동시에 포커스 앱에도 전달돼
// YouTube의 M(음소거)·숫자키(탐색) 등으로 새는 버그가 있었다.
// 그래서 마우스(MouseEventMonitor)와 같은 CGEventTap을 쓰되 .listenOnly가 아닌
// .defaultTap으로 만들어, 우리가 처리하는 ⌃⌥ 단축키는 nil을 반환해 삼킨다(consume).
// 나머지 키는 그대로 통과시켜 정상 타이핑/시스템 단축키에 영향 없음.
@MainActor
final class KeyboardHotkeyHandler {
    private weak var settings: CursorSettings?
    private weak var runtime: CursorRuntimeState?
    private weak var effects: EffectsState?
    private weak var keystrokeOverlay: KeystrokeOverlayState?
    private let onScreenshotShortcut: () -> Void
    private let onMagnifierWithoutPermission: () -> Void

    // 백그라운드 tap 스레드 (마우스 tap과 동일한 격리 패턴)
    private nonisolated(unsafe) var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var selfPtr: UnsafeMutableRawPointer?
    private var tapThread: Thread?
    private var cancellables = Set<AnyCancellable>()

    // ⌃⌥ 조합일 때 "삼킬" keyCode 스냅샷. tap 콜백(백그라운드)이 동기로 읽어야 해서
    // nonisolated. 쓰기는 main(updateConsumableCodes)에서만, 키코드 변경은
    // 환경설정에서 드물게 발생 → 양호한 race.
    private nonisolated(unsafe) var consumableCodes: Set<Int64> = []

    init(settings: CursorSettings,
         runtime: CursorRuntimeState,
         effects: EffectsState,
         keystrokeOverlay: KeystrokeOverlayState,
         onScreenshotShortcut: @escaping () -> Void,
         onMagnifierWithoutPermission: @escaping () -> Void)
    {
        self.settings = settings
        self.runtime = runtime
        self.effects = effects
        self.keystrokeOverlay = keystrokeOverlay
        self.onScreenshotShortcut = onScreenshotShortcut
        self.onMagnifierWithoutPermission = onMagnifierWithoutPermission

        updateConsumableCodes()
        // 환경설정에서 단축키 keyCode 바뀌면 소비 집합 갱신.
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateConsumableCodes() }
            .store(in: &cancellables)
    }

    deinit {
        // deinit은 nonisolated — CF 객체만 정리 (main-actor 상태 미접근).
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let ptr = selfPtr {
            Unmanaged<KeyboardHotkeyHandler>.fromOpaque(ptr).release()
        }
    }

    /// ⌃⌥ 단축키로 우리가 처리(=삼킬) keyCode 집합. 고정 키 + 환경설정 가변 키.
    private func updateConsumableCodes() {
        guard let settings else { return }
        // 고정: 줌(24,27), 색상 1~6(18,19,20,21,23,22), 색상순환(29)
        var codes: Set<Int64> = [24, 27, 18, 19, 20, 21, 23, 22, 29]
        // 가변: 스포트라이트 / 키스트로크 / 돋보기 토글
        codes.insert(Int64(settings.spotlightKeyCode))
        codes.insert(Int64(settings.keystrokeShortcutKeyCode))
        codes.insert(Int64(settings.magnifierShortcutKeyCode))
        consumableCodes = codes
    }

    func start() {
        guard AXIsProcessTrusted() else { return }
        guard eventTap == nil else { return }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        let retained = Unmanaged.passRetained(self)
        selfPtr = retained.toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,   // .listenOnly가 아니라야 nil 반환으로 이벤트 소비 가능
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let h = Unmanaged<KeyboardHotkeyHandler>.fromOpaque(refcon).takeUnretainedValue()

                switch type {
                case .tapDisabledByTimeout, .tapDisabledByUserInput:
                    // 시스템이 tap을 비활성화하면 즉시 재활성화 (마우스 tap과 동일)
                    if let tap = h.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)

                case .keyDown:
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let f = event.flags
                    // ⌃·⌥ 둘 다 있고 ⌘·⇧는 없을 때만 우리 단축키 후보. (OptionSet == 대신 contains로 견고하게)
                    let isCtrlOptOnly = f.contains(.maskControl) && f.contains(.maskAlternate)
                        && !f.contains(.maskCommand) && !f.contains(.maskShift)
                    let consume = isCtrlOptOnly && h.consumableCodes.contains(keyCode)

                    // 실제 처리는 main에서. CGEvent는 async 동안 무효화될 수 있어 copy 후 전달.
                    if let snapshot = event.copy() {
                        DispatchQueue.main.async {
                            if let ns = NSEvent(cgEvent: snapshot) { h.handle(ns) }
                        }
                    }
                    // 우리 단축키면 삼켜서(nil) 포커스 앱(브라우저 등)으로 새지 않게 함.
                    return consume ? nil : Unmanaged.passUnretained(event)

                case .flagsChanged:
                    // 레이저 포인터 hold — Right Option 단독 hold 시 활성. 한 손으로 가능, auto-repeat 없어 소리 안 남.
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    if keyCode == 61 {  // Right Option (Left Option은 58)
                        let flagsRaw = event.flags.rawValue
                        let rightAltDown = (flagsRaw & 0x40) != 0   // NX_DEVICERALTKEYMASK
                        let leftAltDown  = (flagsRaw & 0x20) != 0   // NX_DEVICELALTKEYMASK — 다른 modifier 검사용
                        let hasOtherMods = leftAltDown
                            || event.flags.contains(.maskCommand)
                            || event.flags.contains(.maskShift)
                            || event.flags.contains(.maskControl)
                        let isPressed = rightAltDown && !hasOtherMods
                        DispatchQueue.main.async { h.setLaserActive(isPressed) }
                    }
                    return Unmanaged.passUnretained(event)

                default:
                    return Unmanaged.passUnretained(event)
                }
            },
            userInfo: selfPtr
        )

        guard let tap else {
            retained.release()
            selfPtr = nil
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source

        // 메인 RunLoop과 격리된 전용 스레드 (마우스 tap과 동일 패턴)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "CursorHighlight.KeyEventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let ptr = selfPtr {
            Unmanaged<KeyboardHotkeyHandler>.fromOpaque(ptr).release()
            selfPtr = nil
        }
        eventTap = nil
        runLoopSource = nil
        tapThread = nil
    }

    /// Right Option hold 상태 변화 — flagsChanged callback에서 호출.
    private func setLaserActive(_ active: Bool) {
        guard let runtime else { return }
        if active != runtime.isLaserPointerActive {
            runtime.isLaserPointerActive = active
        }
    }

    private func handle(_ event: NSEvent) {
        guard let settings, let runtime, let effects, let keystrokeOverlay else { return }
        let flags = event.modifierFlags.intersection([.control, .option, .command, .shift])

        // ⌃⌥ 단축키
        if flags == [.control, .option] {
            // 스포트라이트 토글
            if event.keyCode == settings.spotlightKeyCode {
                withAnimation(.easeInOut(duration: 0.35)) { runtime.isSpotlightActive.toggle() }
                keystrokeOverlay.showStatusNotification(String(localized: runtime.isSpotlightActive ? "🔦 스포트라이트 켜짐" : "🔦 스포트라이트 꺼짐"))
                return
            }
            // 키스트로크 표시 토글
            if event.keyCode == settings.keystrokeShortcutKeyCode {
                settings.isKeystrokeEnabled.toggle()
                keystrokeOverlay.showStatusNotification(String(localized: settings.isKeystrokeEnabled ? "⌨ 키스트로크 켜짐" : "⌨ 키스트로크 꺼짐"))
                return
            }
            // 돋보기 토글
            if event.keyCode == settings.magnifierShortcutKeyCode {
                if !runtime.hasScreenRecordingPermission {
                    onMagnifierWithoutPermission()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        runtime.isMagnifierActive.toggle()
                    }
                }
                return
            }
            // 돋보기 줌 in/out — ⌃⌥= (24, "=") / ⌃⌥- (27, "-"). 0.5 step, clamp 1.5~4.0.
            // 돋보기 켜진 상태에서만 의미 있지만, 꺼진 상태에서 미리 조정도 허용.
            if event.keyCode == 24 || event.keyCode == 27 {
                let delta: Double = event.keyCode == 24 ? 0.5 : -0.5
                let newZoom = max(1.5, min(4.0, settings.magnifierZoom + delta))
                settings.magnifierZoom = newZoom
                keystrokeOverlay.showStatusNotification(String(format: String(localized: "magnifier_zoom_toast"), newZoom))
                return
            }
            // ⌃⌥1~6 색상 즉시 변경
            // keyCode: 1=18, 2=19, 3=20, 4=21, 5=23, 6=22
            let colorMap: [UInt16: CursorSettings.RingColor] = [
                18: .yellow, 19: .red, 20: .blue, 21: .green, 23: .cyan, 22: .purple
            ]
            if let color = colorMap[event.keyCode] {
                settings.ringColor = color
                return
            }
            // ⌃⌥0 다음 색상으로 순환 — 발표 중 빠른 색 변경용
            // (1~6 개별 키 누르기 귀찮을 때, 한 키로 다음 색)
            if event.keyCode == 29 {  // "0" key
                let cases = CursorSettings.RingColor.allCases
                let currentIndex = cases.firstIndex(of: settings.ringColor) ?? 0
                let next = cases[(currentIndex + 1) % cases.count]
                settings.ringColor = next
                keystrokeOverlay.showStatusNotification("🎨 \(next.label)")
                return
            }
            // ⌃⌥7 모양 순환 — 원형 → 둥근 사각형 → 마름모
            if event.keyCode == 26 {  // "7" key
                let cases = CursorSettings.RingShape.allCases
                let currentIndex = cases.firstIndex(of: settings.ringShape) ?? 0
                let next = cases[(currentIndex + 1) % cases.count]
                settings.ringShape = next
                let icon: String
                switch next {
                case .circle:   icon = "⭕"
                case .squircle: icon = "🟦"
                case .rhombus:  icon = "🔶"
                }
                keystrokeOverlay.showStatusNotification("\(icon) \(next.label)")
                return
            }
        }

        // ⌘⇧3/4/5 스크린샷 — 오버레이 일시 숨김 (시스템이 캡처해야 하므로 통과시킴)
        if flags == [.command, .shift] && [20, 21, 23].contains(event.keyCode) {
            onScreenshotShortcut()
        }

        // ⌘V 클립보드 인디케이터 (붙여넣기는 통과시킴)
        if flags == [.command] && event.keyCode == 9 {
            let pb = NSPasteboard.general
            let types = pb.types ?? []
            let emoji: String
            if types.contains(.tiff) || types.contains(.png)
                || types.contains(NSPasteboard.PasteboardType(rawValue: "public.image")) {
                emoji = "🖼"
            } else if types.contains(NSPasteboard.PasteboardType(rawValue: "public.file-url")) {
                emoji = "📁"
            } else if types.contains(NSPasteboard.PasteboardType(rawValue: "public.url")) {
                emoji = "🔗"
            } else if types.contains(.string) {
                emoji = "📝"
            } else {
                emoji = "📋"
            }
            effects.addClipboardEffect(at: runtime.cursorPosition, emoji: emoji)
        }

        // 키스트로크 표시 (단순 타이핑·패스워드 노출 방지를 위해 ⌃·⌥·⌘ 모디파이어 있을 때만)
        if settings.isKeystrokeEnabled && !Self.isPasswordFieldFocused() {
            let text = Self.formatKey(event)
            if !text.isEmpty {
                let timeout = settings.keystrokeTimeout
                keystrokeOverlay.showKeystroke(text, timeout: timeout)
            }
        }
    }

    // MARK: - Helpers

    private static func isPasswordFieldFocused() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef,
              CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return false
        }
        let element = focused as! AXUIElement
        var subroleRef: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
              let subrole = subroleRef as? String else { return false }
        return subrole == "AXSecureTextField"
    }

    // internal access — Tests/KeyFormatTests.swift에서 검증
    static func formatKey(_ event: NSEvent) -> String {
        let flags = event.modifierFlags.intersection([.control, .option, .command, .shift])

        // ⌃·⌥·⌘ 없으면 표시 안 함 — 단순 타이핑·패스워드 노출 방지
        guard !flags.intersection([.control, .option, .command]).isEmpty else { return "" }

        var parts = ""
        if flags.contains(.control) { parts += "⌃" }
        if flags.contains(.option)  { parts += "⌥" }
        if flags.contains(.shift)   { parts += "⇧" }
        if flags.contains(.command) { parts += "⌘" }

        let special: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
            115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12"
        ]

        let key = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        return key.isEmpty ? "" : parts + key
    }
}
