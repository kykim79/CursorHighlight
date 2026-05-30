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
    weak var mouseMonitor: MouseEventMonitor?  // radial menu 활성 동안 좌클릭 소비 제어
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
    // nonisolated mirror — CGEventTap이 backgroud thread에서 "menu 활성 중인가" 판단해 Space/ESC 소비.
    // main(open/commit/cancel)에서만 갱신. Bool 단일 read는 사실상 atomic이라 race tolerated.
    private nonisolated(unsafe) var radialMenuActiveFlag: Bool = false

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
        // 고정: 줌(24,27), 색상 1~6(18,19,20,21,23,22), 색상순환(29),
        //       모양순환(26=7), 인스펙터(34=I), Radial Menu(43=콤마 — ⌘, 설정 컨벤션과 의미 일치)
        var codes: Set<Int64> = [24, 27, 18, 19, 20, 21, 23, 22, 29, 26, 34, 43]
        // 가변: 스포트라이트 / 키스트로크 / 돋보기 토글
        codes.insert(Int64(settings.spotlightKeyCode))
        codes.insert(Int64(settings.keystrokeShortcutKeyCode))
        codes.insert(Int64(settings.magnifierShortcutKeyCode))
        consumableCodes = codes
    }

    func start() {
        guard AXIsProcessTrusted() else { return }
        guard eventTap == nil else { return }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

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
                    // ESC — Radial Menu 활성 중이면 cancel (modifier 무관)
                    if keyCode == 53 {
                        DispatchQueue.main.async { h.cancelRadialMenuIfActive() }
                    }
                    let f = event.flags
                    // ⌃·⌥ 둘 다 있고 ⌘·⇧는 없을 때만 우리 단축키 후보. (OptionSet == 대신 contains로 견고하게)
                    let isCtrlOptOnly = f.contains(.maskControl) && f.contains(.maskAlternate)
                        && !f.contains(.maskCommand) && !f.contains(.maskShift)
                    // Toggle 모드 — 메뉴 활성 중에는 ESC만 항상 소비 (modifier 무관 close).
                    let menuActiveConsume = h.radialMenuActiveFlag && keyCode == 53
                    let consume = (isCtrlOptOnly && h.consumableCodes.contains(keyCode)) || menuActiveConsume

                    // 실제 처리는 main에서. CGEvent는 async 동안 무효화될 수 있어 copy 후 전달.
                    if let snapshot = event.copy() {
                        DispatchQueue.main.async {
                            if let ns = NSEvent(cgEvent: snapshot) { h.handle(ns) }
                        }
                    }
                    // 우리 단축키면 삼켜서(nil) 포커스 앱(브라우저 등)으로 새지 않게 함.
                    return consume ? nil : Unmanaged.passUnretained(event)

                case .keyUp:
                    // Toggle 모드 — Space 떼는 시점엔 아무 작업 없음. commit은 다음 Space 누를 때.
                    return Unmanaged.passUnretained(event)

                case .flagsChanged:
                    // Toggle 모드 — ⌃/⌥ 떼도 메뉴 유지. 사용자가 모디파이어 떼고 천천히 선택 가능.
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

    /// Radial Menu cancel — ESC keyDown 또는 ⌃⌥M 토글 close 시 호출. 액션 실행 X.
    func cancelRadialMenuIfActive() {
        guard let runtime, runtime.isRadialMenuActive else { return }
        runtime.isRadialMenuActive = false
        runtime.isRadialMenuVisible = false
        runtime.radialMenuShowHelp = false
        runtime.radialMenuSelectedSector = nil
        runtime.radialMenuSelectedSubItem = nil
        radialMenuActiveFlag = false
        mouseMonitor?.shouldConsumeLeftClick = false
    }

    /// Radial Menu 좌클릭 — sub 위에서 클릭 시 실행, dead zone에서 클릭 시 close.
    /// 일반 sub 실행은 메뉴 유지 (사용자가 여러 효과 연속 토글 가능).
    func handleRadialMenuClick() {
        guard let runtime, runtime.isRadialMenuActive else { return }
        let dx = runtime.cursorPosition.x - runtime.radialMenuCenter.x
        let dy = runtime.cursorPosition.y - runtime.radialMenuCenter.y
        let dist = sqrt(dx*dx + dy*dy)
        // dead zone(✕ 닫기) 클릭 → close
        if dist < Tokens.Radial.deadRadius {
            cancelRadialMenuIfActive()
            return
        }
        // sub 위 클릭 → 실행, 메뉴 유지
        guard let sector = runtime.radialMenuSelectedSector else { return }
        if let sub = runtime.radialMenuSelectedSubItem {
            executeRadialSubAction(sector: sector, sub: sub)
        } else if let item = CursorSettings.RadialMenuItem(rawValue: sector), item.subCount == 0 {
            // 서브 없는 sector (현재 없음)만 메인 클릭으로 실행
            executeRadialMenuAction(sector)
        }
        // 메뉴는 유지 — 다음 sub 토글을 위해
    }


    /// 서브 ring에서 떼면 호출 — 메인 액션 대신 sub 값으로 직접 설정. 알림 형식 통일: `[아이콘] [라벨] · [값/상태]`.
    /// 스포트라이트/돋보기/키 입력은 sub 0이 "토글" — 메인 release가 cancel이라 메뉴 안에서 켤 길 보장.
    private func executeRadialSubAction(sector: Int, sub: Int) {
        guard let runtime, let settings, let keystrokeOverlay else { return }
        switch sector {
        case 0:
            if sub == 0 {
                withAnimation(.easeInOut(duration: 0.35)) { runtime.isSpotlightActive.toggle() }
                keystrokeOverlay.showStatusNotification("🔦 스포트라이트 · \(runtime.isSpotlightActive ? "켜짐" : "꺼짐")")
            } else {
                let radii: [CGFloat] = [60, 100, 140, 180, 220]
                let idx = sub - 1
                guard idx < radii.count else { return }
                settings.spotlightRadius = radii[idx]
                keystrokeOverlay.showStatusNotification("🔦 스포트라이트 반경 · \(Int(radii[idx]))pt")
            }
        case 1:
            if sub == 0 {
                runtime.isMagnifierActive.toggle()
                keystrokeOverlay.showStatusNotification("🔍 돋보기 · \(runtime.isMagnifierActive ? "켜짐" : "꺼짐")")
            } else {
                let zooms: [Double] = [1.5, 2.0, 2.5, 3.0, 4.0]
                let idx = sub - 1
                guard idx < zooms.count else { return }
                settings.magnifierZoom = zooms[idx]
                keystrokeOverlay.showStatusNotification("🔍 돋보기 줌 · \(String(format: "%.1f", zooms[idx]))×")
            }
        case 3:
            let sizes = CursorSettings.RingSize.allCases
            guard sub < sizes.count else { return }
            settings.ringSize = sizes[sub]
            keystrokeOverlay.showStatusNotification("🔘 링 크기 · \(sizes[sub].label)")
        case 4:
            let colors = CursorSettings.RingColor.allCases.filter { $0 != .custom }
            guard sub < colors.count else { return }
            settings.ringColor = colors[sub]
            keystrokeOverlay.showStatusNotification("🎨 링 색 · \(colors[sub].label)")
        case 5:
            let shapes = CursorSettings.RingShape.allCases
            guard sub < shapes.count else { return }
            settings.ringShape = shapes[sub]
            keystrokeOverlay.showStatusNotification("⭕ 링 모양 · \(shapes[sub].label)")
        case 7:
            if sub == 0 {
                settings.isKeystrokeEnabled.toggle()
                keystrokeOverlay.showStatusNotification("⌨ 키 입력 · \(settings.isKeystrokeEnabled ? "켜짐" : "꺼짐")")
            } else {
                let times: [Double] = [1, 2, 4, 8]
                let idx = sub - 1
                guard idx < times.count else { return }
                settings.keystrokeTimeout = times[idx]
                keystrokeOverlay.showStatusNotification("⌨ 키 입력 시간 · \(Int(times[idx]))초")
            }
        case 2:  // 효과 그룹 — 4개 독립 토글. sub 라벨과 알림 이름/이모지 일치
            switch sub {
            case 0:
                settings.isGlowEnabled.toggle()
                keystrokeOverlay.showStatusNotification("💡 글로우 · \(settings.isGlowEnabled ? "켜짐" : "꺼짐")")
            case 1:
                settings.isTrailEnabled.toggle()
                keystrokeOverlay.showStatusNotification("💨 트레일 · \(settings.isTrailEnabled ? "켜짐" : "꺼짐")")
            case 2:
                settings.isIdlePulseEnabled.toggle()
                keystrokeOverlay.showStatusNotification("💫 정지펄스 · \(settings.isIdlePulseEnabled ? "켜짐" : "꺼짐")")
            case 3:
                settings.isCometTailEnabled.toggle()
                keystrokeOverlay.showStatusNotification("☄️ 코멧 · \(settings.isCometTailEnabled ? "켜짐" : "꺼짐")")
            default: break
            }
        case 6:  // 좌표/각도 묶음 — 위치/방향 라벨 2종
            switch sub {
            case 0:
                runtime.isInspectorActive.toggle()
                keystrokeOverlay.showStatusNotification("📐 좌표 · \(runtime.isInspectorActive ? "켜짐" : "꺼짐")")
            case 1:
                settings.isDragAngleLabelEnabled.toggle()
                keystrokeOverlay.showStatusNotification("🧭 드래그각도 · \(settings.isDragAngleLabelEnabled ? "켜짐" : "꺼짐")")
            default: break
            }
        default: break
        }
    }

    /// sector index → action. 12시(0) → 시계방향 45°씩. 알림 형식 통일: `[아이콘] [라벨] · [값/상태]`.
    private func executeRadialMenuAction(_ sector: Int) {
        guard let runtime, let settings, let keystrokeOverlay else { return }
        switch sector {
        case 0:
            withAnimation(.easeInOut(duration: 0.35)) { runtime.isSpotlightActive.toggle() }
            keystrokeOverlay.showStatusNotification("🔦 스포트라이트 · \(runtime.isSpotlightActive ? "켜짐" : "꺼짐")")
        case 1:
            runtime.isMagnifierActive.toggle()
            keystrokeOverlay.showStatusNotification("🔍 돋보기 · \(runtime.isMagnifierActive ? "켜짐" : "꺼짐")")
        case 2:
            settings.isGlowEnabled.toggle()
            keystrokeOverlay.showStatusNotification("✨ 빛 효과 · \(settings.isGlowEnabled ? "켜짐" : "꺼짐")")
        case 3:
            let cases = CursorSettings.RingSize.allCases
            let i = cases.firstIndex(of: settings.ringSize) ?? 0
            let next = cases[(i + 1) % cases.count]
            settings.ringSize = next
            keystrokeOverlay.showStatusNotification("🔘 링 크기 · \(next.label)")
        case 4:
            let cases = CursorSettings.RingColor.allCases
            let i = cases.firstIndex(of: settings.ringColor) ?? 0
            let next = cases[(i + 1) % cases.count]
            settings.ringColor = next
            keystrokeOverlay.showStatusNotification("🎨 링 색 · \(next.label)")
        case 5:
            let cases = CursorSettings.RingShape.allCases
            let i = cases.firstIndex(of: settings.ringShape) ?? 0
            let next = cases[(i + 1) % cases.count]
            settings.ringShape = next
            keystrokeOverlay.showStatusNotification("⭕ 링 모양 · \(next.label)")
        case 6:
            runtime.isInspectorActive.toggle()
            keystrokeOverlay.showStatusNotification("📐 좌표 표시 · \(runtime.isInspectorActive ? "켜짐" : "꺼짐")")
        case 7:
            settings.isKeystrokeEnabled.toggle()
            keystrokeOverlay.showStatusNotification("⌨ 키 입력 · \(settings.isKeystrokeEnabled ? "켜짐" : "꺼짐")")
        default: break
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
            // ⌃⌥, — Radial Menu 토글. 열기: 메뉴 등장 (메뉴 유지, 모디파이어 떼도 OK).
            // 실행: sub 위에서 좌클릭 (메뉴 유지 — 여러 효과 연속 토글 가능).
            // 닫기: ⌃⌥, 다시, 또는 ESC, 또는 dead zone(✕) 클릭.
            // 화면 가장자리 clamp — cursor가 모서리 가까이여서 메뉴가 잘리지 않도록 중심을 안쪽으로 보정.
            if event.keyCode == 43 {
                if runtime.isRadialMenuActive {
                    cancelRadialMenuIfActive()
                } else {
                    let raw = runtime.cursorPosition
                    let safe = Tokens.Radial.edgeClamp
                    let screen = NSScreen.screens.first(where: { $0.frame.contains(raw) }) ?? NSScreen.main
                    let center: CGPoint
                    if let frame = screen?.frame {
                        center = CGPoint(
                            x: max(frame.minX + safe, min(frame.maxX - safe, raw.x)),
                            y: max(frame.minY + safe, min(frame.maxY - safe, raw.y))
                        )
                    } else {
                        center = raw
                    }
                    runtime.isRadialMenuActive = true
                    runtime.radialMenuCenter = center
                    runtime.radialMenuSelectedSector = nil
                    runtime.radialMenuSelectedSubItem = nil
                    radialMenuActiveFlag = true
                    mouseMonitor?.shouldConsumeLeftClick = true  // 메뉴 영역 좌클릭을 underlying app으로 보내지 않게
                    withAnimation(Tokens.Motion.easeMicro) { runtime.isRadialMenuVisible = true }
                    let helpShown = UserDefaults.standard.integer(forKey: "radialMenuHelpShownCount")
                    runtime.radialMenuShowHelp = helpShown < 5
                    UserDefaults.standard.set(helpShown + 1, forKey: "radialMenuHelpShownCount")
                }
                return
            }
            // ⌃⌥I 화면 좌표 인스펙터 토글 — cursor 옆 (x, y) Quartz 좌표 라벨.
            if event.keyCode == 34 {  // "I" key
                runtime.isInspectorActive.toggle()
                keystrokeOverlay.showStatusNotification(String(localized: runtime.isInspectorActive ? "📐 좌표 인스펙터 켜짐" : "📐 좌표 인스펙터 꺼짐"))
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
