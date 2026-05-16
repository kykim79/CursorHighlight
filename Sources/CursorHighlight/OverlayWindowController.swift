import AppKit
import SwiftUI

@MainActor
class OverlayWindowController {
    private var window: NSWindow?

    init(screen: NSScreen, state: CursorState) {
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
        win.sharingType = .none  // 돋보기 캡처에 오버레이가 포함되지 않도록

        let content = OverlayContentView(state: state, screenFrame: screen.frame)
        win.contentView = NSHostingView(rootView: content)
        win.orderFrontRegardless()

        self.window = win
    }

    func show() { window?.orderFrontRegardless() }
    func hide() { window?.orderOut(nil) }

    func close() {
        window?.close()
        window = nil
    }
}
