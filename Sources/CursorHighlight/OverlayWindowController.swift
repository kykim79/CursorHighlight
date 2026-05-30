import AppKit
import SwiftUI
import Combine

@MainActor
class OverlayWindowController {
    private var window: NSWindow?
    private var screenshotModeCancellable: AnyCancellable?

    init(screen: NSScreen,
         settings: CursorSettings,
         runtime: CursorRuntimeState,
         effects: EffectsState,
         keystroke: KeystrokeOverlayState,
         drawing: DrawingState)
    {
        // screen: 파라미터를 넘기면 contentRect가 해당 스크린 로컬 좌표로 해석됨 → 제거
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
        win.backgroundColor = .clear
        win.isOpaque = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        win.isReleasedWhenClosed = false
        win.hasShadow = false
        // sharingType: 평소 .none이라야 자체 돋보기가 자기 overlay를 다시 capture하지 않음.
        // settings.isScreenshotMode가 ON이면 .readOnly로 풀어 외부 screencapture/OBS가 잡을 수 있게.
        win.sharingType = settings.isScreenshotMode ? .readOnly : .none

        let content = OverlayContentView(
            settings: settings,
            runtime: runtime,
            effects: effects,
            keystroke: keystroke,
            drawing: drawing,
            screenFrame: screen.frame
        )
        win.contentView = NSHostingView(rootView: content)
        win.orderFrontRegardless()

        self.window = win

        screenshotModeCancellable = settings.$isScreenshotMode.sink { [weak win] enabled in
            win?.sharingType = enabled ? .readOnly : .none
        }
    }

    func show() { window?.orderFrontRegardless() }
    func hide() { window?.orderOut(nil) }

    func close() {
        window?.close()
        window = nil
    }
}
