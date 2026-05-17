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
    private var recordingDetector: RecordingDetector?
    private var magnifierCaptureService: MagnifierCaptureService?
    private var keyboardHotkeyHandler: KeyboardHotkeyHandler?

    // MARK: - UI
    private var statusItem: NSStatusItem?
    private var enableMenuItem: NSMenuItem?
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

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()
        setupOverlays()
        setupServices()
        startEventMonitoring()

        if !PermissionsManager.isAccessibilityTrusted {
            permissionsManager?.requestAccessibility()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func setupServices() {
        permissionsManager = PermissionsManager(runtime: runtime)
        permissionsManager?.startPolling()

        recordingDetector = RecordingDetector(settings: settings) { [weak self] in
            self?.handleRecordingDetected()
        }
        recordingDetector?.start()

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
        enableMenuItem?.title = isEnabled ? "비활성화" : "✓ 활성화"
    }

    // MARK: - Service callbacks

    private func handleRecordingDetected() {
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
            monitor?.onShake = { [weak self] _ in
                guard let self else { return }
                self.lastMoveTime = Date()
                self.runtime.isCursorVisible = true
                self.effects.triggerShake(at: self.runtime.cursorPosition, animationSpeed: self.settings.animationSpeed.multiplier)
            }
            monitor?.onScroll = { [weak self] _, isPositive, isVertical in
                guard let self else { return }
                self.lastMoveTime = Date()
                self.runtime.isCursorVisible = true
                self.effects.addScrollEffect(at: self.runtime.cursorPosition, isPositive: isPositive, isVertical: isVertical, animationSpeed: self.settings.animationSpeed.multiplier)
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
                self?.runtime.endDrag()
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
