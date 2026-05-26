import AppKit
import Combine
import SwiftUI

// MARK: - AppDelegate
//
// 책임: 메뉴바 + 4개 상태 객체 + 4개 서비스 owning + 마우스 라우팅 + 오버레이 lifecycle.
// 다른 책임(권한·녹화 감지·돋보기 캡처·키보드)은 전용 서비스로 위임.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - State (4 ObservableObject)
    let settings = CursorSettings()
    let runtime = CursorRuntimeState()
    let effects = EffectsState()
    let keystrokeOverlay = KeystrokeOverlayState()

    // MARK: - Services
    private var permissionsManager: PermissionsManager?
    private var appActivationDetector: AppActivationDetector?
    private var magnifierCaptureService: MagnifierCaptureService?
    private var keyboardHotkeyHandler: KeyboardHotkeyHandler?

    // MARK: - UI
    private var statusItem: NSStatusItem?
    private var enableMenuItem: NSMenuItem?
    private var spotlightMenuItem: NSMenuItem?
    private var magnifierMenuItem: NSMenuItem?
    private var keystrokeMenuItem: NSMenuItem?
    private var screenshotModeMenuItem: NSMenuItem?
    private var preferencesController: PreferencesWindowController?
    private var overlays: [OverlayWindowController] = []

    // MARK: - Mouse routing
    private var monitor: MouseEventMonitor?
    private var lastMousePos: CGPoint = .zero
    private var lastMoveTime: Date = .init()
    private var idleHideWorkItem: DispatchWorkItem?
    private var glowEnhanceWorkItem: DispatchWorkItem?
    private var lastPosUpdateTime: TimeInterval = 0
    private var lastTrailSampleTime: TimeInterval = 0

    // Quartz↔Cocoa 좌표 변환용 (handleMouseMove가 60Hz hotpath라 매번 NSScreen 쿼리 회피)
    // screensChanged()에서 갱신 — 모니터 구성 바뀔 때만.
    private var primaryScreenHeight: CGFloat = 0

    private var isEnabled = true

    // 트랙패드 제스처 (실험적, 비공식 API) — 토글 변화 구독.
    private var trackpadGestureCancellable: AnyCancellable?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()
        setupOverlays()
        setupServices()
        startEventMonitoring()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // UI 안정화 후 권한 4개 체크 — 일부라도 missing 시 alert.
        // brew upgrade 같은 cdhash 변경으로 권한이 reset된 경우 사용자에게 즉시 안내.
        Task { [weak self] in
            await self?.checkPermissionsAndAlertIfMissing()
        }
    }

    /// launch 시 권한 4개 (손쉬운 사용 / 화면 녹화 / 입력 모니터링 / 입력 보내기) 체크.
    /// TCC 권한 동기화가 launch 직후 1-2초 false negative 반환하는 경우 있어 1초 간격으로
    /// 5번 retry — 5번 모두 missing인 권한만 진짜 missing 판단. 일부라도 missing 시 NSAlert.
    /// 총 대기 약 6초.
    private func checkPermissionsAndAlertIfMissing() async {
        try? await Task.sleep(for: .seconds(1))
        var attempts: [Set<PermissionsManager.PermissionType>] = []
        for _ in 0..<5 {
            attempts.append(Set(PermissionsManager.missingPermissions()))
            try? await Task.sleep(for: .seconds(1))
        }
        // 모든 시도에서 일관되게 missing이었던 권한만 진짜 missing — 한 번이라도 부여 검출되면 제외.
        let alwaysMissing = attempts.dropFirst().reduce(attempts.first ?? []) { $0.intersection($1) }
        guard !alwaysMissing.isEmpty else { return }

        // 안내 순서를 enum 순서대로 안정화 (PermissionType.allCases 기준)
        let missingOrdered = PermissionsManager.PermissionType.allCases.filter { alwaysMissing.contains($0) }

        let alert = NSAlert()
        alert.messageText = String(localized: "권한 일부 재부여 필요")
        // permission_alert_body는 %@ 자리에 missing 권한 bullet list 삽입
        let bulletList = missingOrdered.map { "• \($0.localizedName)" }.joined(separator: "\n")
        alert.informativeText = String(format: String(localized: "permission_alert_body"), bulletList)
        alert.alertStyle = .warning
        if missingOrdered.count > 1 {
            alert.addButton(withTitle: String(localized: "모든 패널 열기"))
        }
        alert.addButton(withTitle: String(localized: "시스템 설정 열기"))
        alert.addButton(withTitle: String(localized: "나중에"))

        // 사용자가 시스템 설정 검색창에서 빠르게 찾을 수 있게 클립보드에 앱 이름 복사
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("CursorHighlight", forType: .string)

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        switch (missingOrdered.count > 1, response) {
        case (true, .alertFirstButtonReturn):
            // "모든 패널 열기" — 각 missing 권한 패널 0.5초 간격으로 순차 오픈 (시스템 설정 안 깜빡거리게)
            Task { @MainActor in
                for (i, p) in missingOrdered.enumerated() {
                    NSWorkspace.shared.open(p.settingsURL)
                    if i < missingOrdered.count - 1 {
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
            }
        case (true, .alertSecondButtonReturn), (false, .alertFirstButtonReturn):
            // 첫 missing 권한 패널 하나만 — 가장 흔한 경우
            if let first = missingOrdered.first {
                NSWorkspace.shared.open(first.settingsURL)
            }
        default:
            break  // "나중에"
        }
    }

    private func setupServices() {
        permissionsManager = PermissionsManager(runtime: runtime)
        permissionsManager?.startPolling()

        appActivationDetector = AppActivationDetector(settings: settings) { [weak self] in
            self?.handleTriggerAppActivated()
        }
        appActivationDetector?.start()

        // runtime.isMagnifierActive를 구독해 켜질 때만 캡처 Timer 시작 — 꺼져있을 때 CPU 0
        magnifierCaptureService = MagnifierCaptureService(runtime: runtime, settings: settings)

        keyboardHotkeyHandler = KeyboardHotkeyHandler(
            settings: settings,
            runtime: runtime,
            effects: effects,
            keystrokeOverlay: keystrokeOverlay,
            onScreenshotShortcut: { [weak self] in self?.handleScreenshotShortcut() },
            onMagnifierWithoutPermission: { [weak self] in self?.permissionsManager?.requestScreenRecordingPermission() }
        )
        keyboardHotkeyHandler?.start()

        // 트랙패드 시스템 제스처 — 비공식 MultitouchSupport. 토글 ON일 때만 활성.
        MultitouchService.shared.onGesture = { [weak self] gesture in
            guard let self else { return }
            // 토글 OFF 사이의 in-flight 콜백 안전 가드 (start/stop은 idempotent이지만
            // stop 직전에 콜백이 enqueue됐을 수 있음).
            guard self.settings.isTrackpadGesturesEnabled else { return }
            self.effects.addTrackpadGesture(
                gesture,
                at: self.runtime.cursorPosition,
                animationSpeed: self.settings.animationSpeed.multiplier
            )
        }
        // 초기 상태 반영 + 토글 변화에 따라 start/stop.
        if settings.isTrackpadGesturesEnabled, MultitouchService.shared.isAvailable {
            MultitouchService.shared.start()
        }
        trackpadGestureCancellable = settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                if self.settings.isTrackpadGesturesEnabled, MultitouchService.shared.isAvailable {
                    MultitouchService.shared.start()
                } else {
                    MultitouchService.shared.stop()
                }
            }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 종료 시 시스템 multitouch 콜백 정리 — 안 풀면 잠재적으로 freed memory에 fire 가능.
        MultitouchService.shared.stop()
    }

    // MARK: - 메뉴바

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: nil)

        let menu = NSMenu()
        menu.delegate = self   // menuWillOpen에서 토글 항목 ✓ state 갱신

        let prefItem = NSMenuItem(title: String(localized: "환경설정..."), action: #selector(openPreferences), keyEquivalent: "")
        prefItem.target = self
        menu.addItem(prefItem)

        menu.addItem(.separator())

        // 빠른 토글 — 환경설정 안 열고 메뉴바에서 바로. 단축키도 함께 표시(metadata).
        let spotlight = NSMenuItem(title: String(localized: "스포트라이트  ⌃⌥S"), action: #selector(toggleSpotlight), keyEquivalent: "")
        spotlight.target = self
        menu.addItem(spotlight)
        spotlightMenuItem = spotlight

        let magnifier = NSMenuItem(title: String(localized: "돋보기  ⌃⌥M"), action: #selector(toggleMagnifier), keyEquivalent: "")
        magnifier.target = self
        menu.addItem(magnifier)
        magnifierMenuItem = magnifier

        let keystroke = NSMenuItem(title: String(localized: "키스트로크 표시  ⌃⌥K"), action: #selector(toggleKeystroke), keyEquivalent: "")
        keystroke.target = self
        menu.addItem(keystroke)
        keystrokeMenuItem = keystroke

        // 발표/녹화용 일시 토글 — overlay window를 외부 screencapture/OBS가 잡을 수 있게 풀어줌.
        // 평소 .none이라 자체 돋보기가 자기 overlay 재캡처 안 함. 앱 재시작 시 자동 OFF.
        let screenshotMode = NSMenuItem(title: String(localized: "스크린샷 모드 (캡처 허용)"), action: #selector(toggleScreenshotMode), keyEquivalent: "")
        screenshotMode.target = self
        menu.addItem(screenshotMode)
        screenshotModeMenuItem = screenshotMode

        menu.addItem(.separator())

        let ei = NSMenuItem(title: String(localized: "비활성화"), action: #selector(toggleEnabled), keyEquivalent: "")
        ei.target = self
        menu.addItem(ei)
        enableMenuItem = ei

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: String(localized: "종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - 메뉴 빠른 토글 actions

    @objc private func toggleSpotlight() {
        withAnimation(.easeInOut(duration: 0.35)) { runtime.isSpotlightActive.toggle() }
        keystrokeOverlay.showStatusNotification(String(localized: runtime.isSpotlightActive ? "🔦 스포트라이트 켜짐" : "🔦 스포트라이트 꺼짐"))
    }

    @objc private func toggleMagnifier() {
        if !runtime.hasScreenRecordingPermission {
            permissionsManager?.requestScreenRecordingPermission()
            return
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            runtime.isMagnifierActive.toggle()
        }
    }

    @objc private func toggleKeystroke() {
        settings.isKeystrokeEnabled.toggle()
        keystrokeOverlay.showStatusNotification(String(localized: settings.isKeystrokeEnabled ? "⌨ 키스트로크 켜짐" : "⌨ 키스트로크 꺼짐"))
    }

    @objc private func toggleScreenshotMode() {
        settings.isScreenshotMode.toggle()
        keystrokeOverlay.showStatusNotification(String(localized: settings.isScreenshotMode ? "📸 스크린샷 모드 켜짐 (외부 캡처 허용)" : "📸 스크린샷 모드 꺼짐"))
    }

    @objc private func openPreferences() {
        if preferencesController == nil {
            let controller = PreferencesWindowController(settings: settings, runtime: runtime)
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
        enableMenuItem?.title = String(localized: isEnabled ? "비활성화" : "✓ 활성화")
    }

    // MARK: - Service callbacks

    private func handleTriggerAppActivated() {
        guard !isEnabled else { return }
        isEnabled = true
        updateIcon()
        startEventMonitoring()
        overlays.forEach { $0.show() }
    }

    private func handleScreenshotShortcut() {
        overlays.forEach { $0.hide() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.isEnabled else { return }
            self.overlays.forEach { $0.show() }
        }
    }

    // PreferencesView의 "권한 요청" 버튼이 (NSApp.delegate as? AppDelegate)?.requestScreenRecordingPermission() 호출.
    // PermissionsManager로 위임만 함.
    func requestScreenRecordingPermission() {
        permissionsManager?.requestScreenRecordingPermission()
    }

    // MARK: - 커서 위치 추적 (이벤트 기반)
    // CGEventTap의 mouseMoved 이벤트로 cursorPosition 업데이트.
    // 폴링 Timer 없음 → 마우스 정지 시 CPU 0. throttle로 SwiftUI 재렌더는 60Hz로 제한.

    private func handleMouseMove(_ cgPos: CGPoint) {
        // CGEvent.location은 Quartz 좌표(top-left origin) → cursorPosition 소비처는
        // Cocoa 좌표(bottom-left, NSEvent.mouseLocation과 동일) 가정. 여기서 변환.
        let pos = CGPoint(x: cgPos.x, y: primaryScreenHeight - cgPos.y)

        lastMousePos = pos
        lastMoveTime = Date()

        if !runtime.isCursorVisible { runtime.isCursorVisible = true }
        if runtime.glowMultiplier > 1.0 { runtime.glowMultiplier = 1.0 }

        let now = Date().timeIntervalSinceReferenceDate

        // cursorPosition 업데이트는 60Hz throttle (고DPI 마우스 1000Hz 대비)
        if now - lastPosUpdateTime >= 1.0 / 60.0 {
            lastPosUpdateTime = now
            runtime.cursorPosition = pos
        }

        // 트레일 샘플링 (~15Hz throttle)
        if now - lastTrailSampleTime > 0.066 {
            lastTrailSampleTime = now
            if settings.isTrailEnabled {
                effects.updateTrail(pos)
            } else if !effects.trailPoints.isEmpty {
                effects.clearTrail()
            }
            // #18 Comet Tail — 드래그 중에만 별도 streak sample
            if runtime.isDragging && settings.isCometTailEnabled {
                effects.updateDragTrail(pos)
            }
        }

        // #17 Anchored Line — 드래그 중 거리 임계 체크 (시간 임계는 startDrag의 Task)
        if runtime.isDragging {
            runtime.checkAnchoredLineDistance(currentPos: pos)
        }

        scheduleIdleAndGlow()
    }

    private func scheduleIdleAndGlow() {
        idleHideWorkItem?.cancel()
        glowEnhanceWorkItem?.cancel()

        let hide = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // 보정: 마지막 throttled 위치가 빠졌을 수 있어 다시 commit
            if self.runtime.cursorPosition != self.lastMousePos {
                self.runtime.cursorPosition = self.lastMousePos
            }
            if self.runtime.isCursorVisible { self.runtime.isCursorVisible = false }
        }
        idleHideWorkItem = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.idleTimeout, execute: hide)

        let glow = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.runtime.glowMultiplier < 1.7 { self.runtime.glowMultiplier = 1.7 }
        }
        glowEnhanceWorkItem = glow
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: glow)
    }

    // MARK: - 마우스·드래그·스크롤 이벤트 라우팅

    private func startEventMonitoring() {
        if monitor == nil {
            monitor = MouseEventMonitor()

            monitor?.onMouseMove = { [weak self] pos in
                self?.handleMouseMove(pos)
            }
            monitor?.onLeftClick = { [weak self] _, isDouble in
                guard let self else { return }
                self.lastMoveTime = Date()
                self.runtime.isCursorVisible = true
                let pos = self.runtime.cursorPosition
                self.effects.addClickEffect(at: pos, isRight: false, isDouble: isDouble, animationSpeed: self.settings.animationSpeed.multiplier)
                self.runtime.triggerClickPulse(isDouble: isDouble)
            }
            monitor?.onRightClick = { [weak self] _ in
                guard let self else { return }
                self.lastMoveTime = Date()
                self.runtime.isCursorVisible = true
                let pos = self.runtime.cursorPosition
                self.effects.addClickEffect(at: pos, isRight: true, animationSpeed: self.settings.animationSpeed.multiplier)
                self.runtime.triggerClickPulse()
            }
            monitor?.onMiddleClick = { [weak self] _ in
                guard let self else { return }
                self.lastMoveTime = Date()
                self.runtime.isCursorVisible = true
                let pos = self.runtime.cursorPosition
                self.effects.addMiddleClickEffect(at: pos, animationSpeed: self.settings.animationSpeed.multiplier)
                self.runtime.triggerClickPulse()
            }
            monitor?.onShake = { [weak self] _ in
                guard let self else { return }
                self.lastMoveTime = Date()
                self.runtime.isCursorVisible = true
                self.effects.triggerShake(at: self.runtime.cursorPosition, animationSpeed: self.settings.animationSpeed.multiplier)
            }
            monitor?.onScroll = { [weak self] _, isPositive, isVertical, magnitude in
                guard let self else { return }
                self.lastMoveTime = Date()
                self.runtime.isCursorVisible = true
                self.effects.addScrollEffect(at: self.runtime.cursorPosition, isPositive: isPositive, isVertical: isVertical, magnitude: magnitude, animationSpeed: self.settings.animationSpeed.multiplier)
            }
            monitor?.onDragStart = { [weak self] cgPos in
                guard let self else { return }
                // Quartz(top-left) → Cocoa(bottom-left)
                let cocoaPos = CGPoint(x: cgPos.x, y: self.primaryScreenHeight - cgPos.y)
                self.runtime.startDrag(at: cocoaPos)
            }
            monitor?.onDragAngle = { [weak self] angle, velocity in
                guard let self else { return }
                self.runtime.updateDragAngle(angle)
                self.runtime.updateDragVelocity(velocity)
            }
            monitor?.onDragEnd = { [weak self] in
                guard let self else { return }
                self.runtime.endDrag()
                self.effects.fadeDragTrail()   // #18 — 종료 시 streak fade out
            }
        }
        monitor?.start()
    }

    // MARK: - 오버레이 윈도우

    private func setupOverlays() {
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map {
            OverlayWindowController(screen: $0, settings: settings, runtime: runtime, effects: effects, keystroke: keystrokeOverlay)
        }
        primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
    }

    @objc private func screensChanged() { setupOverlays() }
}

// MARK: - 메뉴 열릴 때마다 토글 항목 ✓ state 동기화
extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        spotlightMenuItem?.state = runtime.isSpotlightActive ? .on : .off
        magnifierMenuItem?.state = runtime.isMagnifierActive ? .on : .off
        keystrokeMenuItem?.state = settings.isKeystrokeEnabled ? .on : .off
        screenshotModeMenuItem?.state = settings.isScreenshotMode ? .on : .off
    }
}
