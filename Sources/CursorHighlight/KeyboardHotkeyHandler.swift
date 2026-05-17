import AppKit
import SwiftUI

// MARK: - KeyboardHotkeyHandler
//
// 전역 키보드 단축키 핸들링:
//   ⌃⌥{S/M/K/1~6}  스포트라이트·돋보기·키스트로크·색상 토글
//   ⌘⇧{3/4/5}      스크린샷 — 오버레이 일시 숨김
//   ⌘V             클립보드 인디케이터
//   기타 ⌃·⌥·⌘ 조합 키스트로크 표시 (비밀번호 필드는 제외)
@MainActor
final class KeyboardHotkeyHandler {
    private weak var settings: CursorSettings?
    private weak var runtime: CursorRuntimeState?
    private weak var effects: EffectsState?
    private weak var keystrokeOverlay: KeystrokeOverlayState?
    private let onScreenshotShortcut: () -> Void
    private let onMagnifierWithoutPermission: () -> Void
    private var monitor: Any?

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
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard let settings, let runtime, let effects, let keystrokeOverlay else { return }
        let flags = event.modifierFlags.intersection([.control, .option, .command, .shift])

        // ⌃⌥ 단축키
        if flags == [.control, .option] {
            // 스포트라이트 토글
            if event.keyCode == settings.spotlightKeyCode {
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.35)) { runtime.isSpotlightActive.toggle() }
                    keystrokeOverlay.showStatusNotification(runtime.isSpotlightActive ? "🔦 스포트라이트 켜짐" : "🔦 스포트라이트 꺼짐")
                }
                return
            }
            // 키스트로크 표시 토글
            if event.keyCode == settings.keystrokeShortcutKeyCode {
                DispatchQueue.main.async {
                    settings.isKeystrokeEnabled.toggle()
                    keystrokeOverlay.showStatusNotification(settings.isKeystrokeEnabled ? "⌨ 키스트로크 켜짐" : "⌨ 키스트로크 꺼짐")
                }
                return
            }
            // 돋보기 토글
            if event.keyCode == settings.magnifierShortcutKeyCode {
                DispatchQueue.main.async { [onMagnifierWithoutPermission] in
                    if !runtime.hasScreenRecordingPermission {
                        onMagnifierWithoutPermission()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            runtime.isMagnifierActive.toggle()
                        }
                    }
                }
                return
            }
            // 돋보기 줌 in/out — ⌃⌥= (24, "=") / ⌃⌥- (27, "-"). 0.5 step, clamp 1.5~4.0.
            // 돋보기 켜진 상태에서만 의미 있지만, 꺼진 상태에서 미리 조정도 허용.
            if event.keyCode == 24 || event.keyCode == 27 {
                let delta: Double = event.keyCode == 24 ? 0.5 : -0.5
                DispatchQueue.main.async {
                    let newZoom = max(1.5, min(4.0, settings.magnifierZoom + delta))
                    settings.magnifierZoom = newZoom
                    keystrokeOverlay.showStatusNotification(String(format: "🔍 돋보기 줌 %.1fx", newZoom))
                }
                return
            }
            // ⌃⌥1~6 색상 즉시 변경
            // keyCode: 1=18, 2=19, 3=20, 4=21, 5=23, 6=22
            let colorMap: [UInt16: CursorSettings.RingColor] = [
                18: .yellow, 19: .red, 20: .blue, 21: .green, 23: .cyan, 22: .purple
            ]
            if let color = colorMap[event.keyCode] {
                DispatchQueue.main.async { settings.ringColor = color }
                return
            }
        }

        // ⌘⇧3/4/5 스크린샷 — 오버레이 일시 숨김
        if flags == [.command, .shift] && [20, 21, 23].contains(event.keyCode) {
            DispatchQueue.main.async { [onScreenshotShortcut] in onScreenshotShortcut() }
        }

        // ⌘V 클립보드 인디케이터
        if flags == [.command] && event.keyCode == 9 {
            DispatchQueue.main.async {
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
        }

        // 키스트로크 표시 (단순 타이핑·패스워드 노출 방지를 위해 ⌃·⌥·⌘ 모디파이어 있을 때만)
        if settings.isKeystrokeEnabled && !Self.isPasswordFieldFocused() {
            let text = Self.formatKey(event)
            if !text.isEmpty {
                let timeout = settings.keystrokeTimeout
                DispatchQueue.main.async { keystrokeOverlay.showKeystroke(text, timeout: timeout) }
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
