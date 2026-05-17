import AppKit
import Combine
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var monitor: MouseEventMonitor?
    private var overlays: [OverlayWindowController] = []
    private var keyboardMonitor: Any?
    private var recordingCheckTimer: Timer?
    private var magnifierTimer: Timer?
    private var permissionCheckTimer: Timer?
    private var isCheckingMagnifierCapture = false
    private var lastMousePos: CGPoint = .zero
    private var lastMoveTime: Date = .init()
    private var idleHideWorkItem: DispatchWorkItem?
    private var glowEnhanceWorkItem: DispatchWorkItem?
    private var lastPosUpdateTime: TimeInterval = 0
    private var lastTrailSampleTime: TimeInterval = 0
    private var preferencesController: PreferencesWindowController?
    private var cancellables = Set<AnyCancellable>()
    let cursorState = CursorState()
    private var isEnabled = true
    private var enableMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()
        setupOverlays()
        startRecordingDetection()
        startPermissionPolling()
        observeMagnifierToggle()  // 돋보기 켤 때만 캡처 Timer 시작

        startEventMonitoring()
        if !AXIsProcessTrusted() {
            requestAccessibility()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - 메뉴바

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: nil)

        let menu = NSMenu()

        let prefItem = NSMenuItem(title: "환경설정...", action: #selector(openPreferences), keyEquivalent: "")
        prefItem.target = self
        menu.addItem(prefItem)

        menu.addItem(.separator())

        let ei = NSMenuItem(title: "비활성화", action: #selector(toggleEnabled), keyEquivalent: "")
        ei.target = self
        menu.addItem(ei)
        enableMenuItem = ei

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }


    @objc private func openPreferences() {
        if preferencesController == nil {
            let controller = PreferencesWindowController(state: cursorState)
            // 윈도우를 닫으면 controller를 풀어줘 SwiftUI view tree 전체를 해제한다.
            // 살려두면 보이지 않아도 @Published(cursorPosition 60Hz) 변경마다 layout이 재계산됨.
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: controller.window,
                queue: .main
            ) { [weak self] _ in
                self?.preferencesController = nil
            }
            preferencesController = controller
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesController?.showWindow(nil)
        // NSApp.activate가 오버레이 순서를 흐트러뜨리므로 즉시 복원
        overlays.forEach { $0.show() }
    }

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

    private static func formatKey(_ event: NSEvent) -> String {
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

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        updateIcon()
        if isEnabled {
            startEventMonitoring()
            overlays.forEach { $0.show() }
        } else {
            idleHideWorkItem?.cancel()
            glowEnhanceWorkItem?.cancel()
            monitor?.stop()
            overlays.forEach { $0.hide() }
        }
    }

    private func updateIcon() {
        let name = isEnabled ? "cursorarrow.rays" : "cursorarrow"
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        enableMenuItem?.title = isEnabled ? "비활성화" : "✓ 활성화"
    }

    // MARK: - 커서 위치 추적 (이벤트 기반)
    // CGEventTap의 mouseMoved 이벤트로 cursorPosition 업데이트.
    // 폴링 Timer 없음 → 마우스 정지 시 CPU 0. throttle로 SwiftUI 재렌더는 60Hz로 제한.

    private func handleMouseMove(_ cgPos: CGPoint) {
        // CGEvent.location은 Quartz 좌표(top-left origin) → cursorPosition 소비처는
        // Cocoa 좌표(bottom-left, NSEvent.mouseLocation과 동일) 가정. 여기서 변환.
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let pos = CGPoint(x: cgPos.x, y: primaryH - cgPos.y)

        lastMousePos = pos
        lastMoveTime = Date()

        if !cursorState.isCursorVisible { cursorState.isCursorVisible = true }
        if cursorState.glowMultiplier > 1.0 { cursorState.glowMultiplier = 1.0 }

        let now = Date().timeIntervalSinceReferenceDate

        // cursorPosition 업데이트는 60Hz throttle (고DPI 마우스 1000Hz 대비)
        if now - lastPosUpdateTime >= 1.0 / 60.0 {
            lastPosUpdateTime = now
            cursorState.cursorPosition = pos
        }

        // 트레일 샘플링 (~15Hz throttle)
        if now - lastTrailSampleTime > 0.066 {
            lastTrailSampleTime = now
            if cursorState.isTrailEnabled {
                cursorState.updateTrail(pos)
            } else if !cursorState.trailPoints.isEmpty {
                cursorState.clearTrail()
            }
        }

        scheduleIdleAndGlow()
    }

    private func scheduleIdleAndGlow() {
        idleHideWorkItem?.cancel()
        glowEnhanceWorkItem?.cancel()

        let hide = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // 보정: 마지막 throttled 위치가 빠졌을 수 있어 다시 commit
            if self.cursorState.cursorPosition != self.lastMousePos {
                self.cursorState.cursorPosition = self.lastMousePos
            }
            if self.cursorState.isCursorVisible { self.cursorState.isCursorVisible = false }
        }
        idleHideWorkItem = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + cursorState.idleTimeout, execute: hide)

        let glow = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.cursorState.glowMultiplier < 1.7 { self.cursorState.glowMultiplier = 1.7 }
        }
        glowEnhanceWorkItem = glow
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: glow)
    }

    // MARK: - 클릭·흔들기·스크롤 이벤트

    private func startEventMonitoring() {
        if monitor == nil {
            monitor = MouseEventMonitor()

            monitor?.onMouseMove = { [weak self] pos in
                self?.handleMouseMove(pos)
            }
            monitor?.onLeftClick = { [weak self] _, isDouble in
                guard let self else { return }
                self.lastMoveTime = Date()
                self.cursorState.isCursorVisible = true
                let pos = self.cursorState.cursorPosition
                self.cursorState.addClickEffect(at: pos, isRight: false, isDouble: isDouble)
                self.cursorState.triggerClickPulse(isDouble: isDouble)
            }
            monitor?.onRightClick = { [weak self] _ in
                guard let self else { return }
                self.lastMoveTime = Date()
                self.cursorState.isCursorVisible = true
                let pos = self.cursorState.cursorPosition
                self.cursorState.addClickEffect(at: pos, isRight: true)
                self.cursorState.triggerClickPulse()
            }
            monitor?.onShake = { [weak self] _ in
                guard let self else { return }
                self.lastMoveTime = Date()
                self.cursorState.isCursorVisible = true
                self.cursorState.triggerShake(at: self.cursorState.cursorPosition)
            }
            monitor?.onScroll = { [weak self] _, isPositive, isVertical in
                guard let self else { return }
                self.lastMoveTime = Date()
                self.cursorState.isCursorVisible = true
                self.cursorState.addScrollEffect(at: self.cursorState.cursorPosition, isPositive: isPositive, isVertical: isVertical)
            }
            monitor?.onDragStart = { [weak self] in
                self?.cursorState.startDrag()
            }
            monitor?.onDragAngle = { [weak self] angle in
                self?.cursorState.updateDragAngle(angle)
            }
            monitor?.onDragEnd = { [weak self] in
                self?.cursorState.endDrag()
            }
        }
        monitor?.start()

        // 전역 단축키 + 키스트로크 캡처
        if keyboardMonitor == nil {
            keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return }
                let flags = event.modifierFlags.intersection([.control, .option, .command, .shift])

                // ⌃⌥ 단축키 처리
                if flags == [.control, .option] {
                    // 스포트라이트 토글
                    if event.keyCode == self.cursorState.spotlightKeyCode {
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.35)) { self.cursorState.isSpotlightActive.toggle() }
                            self.cursorState.showStatusNotification(self.cursorState.isSpotlightActive ? "🔦 스포트라이트 켜짐" : "🔦 스포트라이트 꺼짐")
                        }
                        return
                    }
                    // 키스트로크 표시 토글
                    if event.keyCode == self.cursorState.keystrokeShortcutKeyCode {
                        DispatchQueue.main.async {
                            self.cursorState.isKeystrokeEnabled.toggle()
                            self.cursorState.showStatusNotification(self.cursorState.isKeystrokeEnabled ? "⌨ 키스트로크 켜짐" : "⌨ 키스트로크 꺼짐")
                        }
                        return
                    }
                    // ⌃⌥M 돋보기 토글
                    if event.keyCode == self.cursorState.magnifierShortcutKeyCode {
                        DispatchQueue.main.async {
                            if !self.cursorState.hasScreenRecordingPermission {
                                self.requestScreenRecordingPermission()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    self.cursorState.isMagnifierActive.toggle()
                                }
                            }
                        }
                        return
                    }

                    // ⌃⌥1~6 색상 즉시 변경
                    // keyCode: 1=18, 2=19, 3=20, 4=21, 5=23, 6=22
                    let colorMap: [UInt16: CursorState.RingColor] = [
                        18: .yellow, 19: .red, 20: .blue, 21: .green, 23: .cyan, 22: .purple
                    ]
                    if let color = colorMap[event.keyCode] {
                        DispatchQueue.main.async { self.cursorState.ringColor = color }
                        return
                    }
                }

                // ⌘⇧3/4/5 스크린샷 — 오버레이 일시 숨김
                if flags == [.command, .shift] && [20, 21, 23].contains(event.keyCode) {
                    DispatchQueue.main.async {
                        self.overlays.forEach { $0.hide() }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            if self.isEnabled { self.overlays.forEach { $0.show() } }
                        }
                    }
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
                        self.cursorState.addClipboardEffect(at: self.cursorState.cursorPosition, emoji: emoji)
                    }
                }

                // 키스트로크 표시
                if self.cursorState.isKeystrokeEnabled && !Self.isPasswordFieldFocused() {
                    let text = Self.formatKey(event)
                    if !text.isEmpty {
                        DispatchQueue.main.async { self.cursorState.showKeystroke(text) }
                    }
                }
            }
        }
    }

    // MARK: - 화면 녹화 감지

    private func startRecordingDetection() {
        recordingCheckTimer?.invalidate()
        recordingCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, self.cursorState.autoEnableOnRecording else { return }
            if Self.isScreenBeingRecorded() && !self.isEnabled {
                DispatchQueue.main.async {
                    self.isEnabled = true
                    self.updateIcon()
                    self.startEventMonitoring()
                    self.overlays.forEach { $0.show() }
                }
            }
        }
    }

    // MARK: - 돋보기 캡처
    // TODO: CGWindowListCreateImage는 macOS 14+에서 deprecated. 향후 ScreenCaptureKit(SCStream) 마이그레이션 필요.

    // isMagnifierActive=true일 때만 캡처 Timer 시작 — 꺼져있을 때 CPU 0
    private func observeMagnifierToggle() {
        cursorState.$isMagnifierActive
            .removeDuplicates()
            .sink { [weak self] active in
                if active { self?.startMagnifierCapture() }
                else      { self?.stopMagnifierCapture() }
            }
            .store(in: &cancellables)
    }

    private func stopMagnifierCapture() {
        magnifierTimer?.invalidate()
        magnifierTimer = nil
        cursorState.magnifierImage = nil
    }

    private func startMagnifierCapture() {
        magnifierTimer?.invalidate()
        magnifierTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self, self.cursorState.isMagnifierActive else { return }
            guard self.cursorState.hasScreenRecordingPermission else {
                DispatchQueue.main.async { self.cursorState.isMagnifierActive = false }
                return
            }
            // 첫 프레임에서 캡처 실패 시(프로세스 캐시 문제) 재시작 안내
            if self.cursorState.magnifierImage == nil && !self.isCheckingMagnifierCapture {
                self.isCheckingMagnifierCapture = true
                self.promptRelaunchIfNeeded()
            }
            let pos = self.cursorState.cursorPosition
            let zoom = self.cursorState.magnifierZoom
            let capturePts = self.cursorState.magnifierSize / zoom
            let primaryH = NSScreen.screens.first?.frame.height ?? 1080
            let quartzY = primaryH - pos.y
            let rect = CGRect(
                x: pos.x - capturePts / 2,
                y: quartzY - capturePts / 2,
                width: capturePts,
                height: capturePts
            )
            // 메인 스레드 부하를 줄이기 위해 백그라운드에서 캡처
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                let image = CGWindowListCreateImage(rect, [.optionOnScreenOnly], kCGNullWindowID, [.bestResolution])
                DispatchQueue.main.async { self?.cursorState.magnifierImage = image }
            }
        }
    }

    // 시스템 권한 다이얼로그를 띄워 설정 목록에 앱 자동 추가
    func requestScreenRecordingPermission() {
        if #available(macOS 14.0, *) {
            // 시스템 다이얼로그 표시 + 설정 목록 자동 추가
            CGRequestScreenCaptureAccess()
        } else {
            // macOS 13: 직접 캡처 시도로 프롬프트 유도
            _ = CGWindowListCreateImage(.null, .optionOnScreenOnly, kCGNullWindowID, .bestResolution)
        }
        // 시스템 설정도 함께 열어서 사용자가 바로 활성화할 수 있게
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    static func hasScreenRecordingPermission() -> Bool {
        if #available(macOS 14.0, *) {
            // 프로세스 캐시 없이 TCC 데이터베이스를 직접 조회 — 프롬프트 없음
            return CGPreflightScreenCaptureAccess()
        }
        // macOS 13: kCGWindowName 유무로 확인
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { $0[kCGWindowName as String] != nil }
    }

    // MARK: - Screen Recording 권한 실시간 감지

    private func startPermissionPolling() {
        cursorState.hasScreenRecordingPermission = Self.hasScreenRecordingPermission()
        // 이미 권한 부여된 상태면 polling 불필요 (사용자가 회수하기 전까지 변하지 않음)
        if cursorState.hasScreenRecordingPermission { return }
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = Self.hasScreenRecordingPermission()
            guard granted != self.cursorState.hasScreenRecordingPermission else { return }
            DispatchQueue.main.async {
                self.cursorState.hasScreenRecordingPermission = granted
                if granted {
                    // 권한 부여됨 → 더 이상 polling 불필요
                    self.permissionCheckTimer?.invalidate()
                    self.permissionCheckTimer = nil
                } else {
                    self.cursorState.isMagnifierActive = false
                }
            }
        }
    }

    // 돋보기를 켤 때 캡처가 실제로 동작하는지 확인 후 재시작 안내
    func promptRelaunchIfNeeded() {
        DispatchQueue.global(qos: .userInitiated).async {
            let testRect = CGRect(x: 0, y: 0, width: 10, height: 10)
            let img = CGWindowListCreateImage(testRect, [.optionOnScreenOnly], kCGNullWindowID, [.bestResolution])
            let needsRestart = img == nil
            DispatchQueue.main.async {
                self.isCheckingMagnifierCapture = false
                guard needsRestart else { return } // 캡처 정상 — 재시작 불필요
                self.cursorState.isMagnifierActive = false
                let alert = NSAlert()
                alert.messageText = "돋보기를 사용하려면 재시작이 필요합니다"
                alert.informativeText = "화면 녹화 권한이 이 세션에 아직 적용되지 않았습니다."
                alert.addButton(withTitle: "지금 재시작")
                alert.addButton(withTitle: "나중에")
                if alert.runModal() == .alertFirstButtonReturn {
                    let url = URL(fileURLWithPath: "/Applications/CursorHighlight.app")
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private static func isScreenBeingRecorded() -> Bool {
        let recordingBundles: Set<String> = [
            "com.apple.QuickTimePlayerX",
            "us.zoom.xos",
            "com.obsproject.obs-studio",
            "com.cleanshot.mac",
            "com.loom.desktop",
            "com.microsoft.teams2",
            "com.cisco.webexmeetingsapp",
            "com.webex.meetingmanager",
        ]
        return NSWorkspace.shared.runningApplications.contains {
            guard let bundleId = $0.bundleIdentifier else { return false }
            return recordingBundles.contains(bundleId)
        }
    }

    // MARK: - 오버레이 윈도우

    private func setupOverlays() {
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map { OverlayWindowController(screen: $0, state: cursorState) }
    }

    @objc private func screensChanged() { setupOverlays() }

    // MARK: - 손쉬운 사용 권한

    private func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    @objc private func openInputMonitoringSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
