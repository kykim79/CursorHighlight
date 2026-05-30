import AppKit
import Combine
import SwiftUI
import os

// private CoreGraphics API — Space 전환 polling. NSWorkspace.activeSpaceDidChangeNotification이
// 내장 모니터에서 안 오는 케이스 backup. CGSManagedDisplayGetCurrentSpace로 디스플레이별 active
// space를 직접 조회 (CGSCopyActiveSpaces는 macOS 26에서 제거됨).
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ cid: Int32) -> UInt64
@_silgen_name("CGSManagedDisplayGetCurrentSpace")
private func CGSManagedDisplayGetCurrentSpace(_ cid: Int32, _ displayUUID: CFString) -> UInt64
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> Unmanaged<CFArray>?

/// 현재 모든 디스플레이의 active Space ID를 String snapshot으로 반환.
/// 디스플레이마다 UUID로 query, 그리고 main display의 active space도 같이 잡음.
private func currentSpacesSignature() -> String {
    let cid = CGSMainConnectionID()
    var parts: [String] = []
    for screen in NSScreen.screens {
        guard let dispID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuidRef = CGDisplayCreateUUIDFromDisplayID(dispID)?.takeRetainedValue(),
              let uuidStr = CFUUIDCreateString(nil, uuidRef) as String? else { continue }
        let spaceID = CGSManagedDisplayGetCurrentSpace(cid, uuidStr as CFString)
        parts.append("\(dispID):\(spaceID)")
    }
    parts.append("MAIN:\(CGSGetActiveSpace(cid))")
    return parts.joined(separator: "|")
}

/// 특정 디스플레이의 현재 Space 인덱스와 총 개수 — boundary 감지용.
/// CGSCopyManagedDisplaySpaces dict 파싱으로 ManagedSpaceID 기반 index 계산.
private func spaceIndexForDisplay(_ displayID: CGDirectDisplayID) -> (current: Int, total: Int)? {
    let cid = CGSMainConnectionID()
    guard let cf = CGSCopyManagedDisplaySpaces(cid)?.takeRetainedValue() else { return nil }
    guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
          let targetUUID = CFUUIDCreateString(nil, uuidRef) as String? else { return nil }
    for item in (cf as NSArray) {
        guard let dict = item as? [String: Any],
              (dict["Display Identifier"] as? String) == targetUUID else { continue }
        guard let spaces = dict["Spaces"] as? [[String: Any]],
              let current = dict["Current Space"] as? [String: Any],
              let currentID = (current["ManagedSpaceID"] as? NSNumber)?.int64Value else { return nil }
        let allIDs = spaces.compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.int64Value }
        guard let idx = allIDs.firstIndex(of: currentID) else { return nil }
        return (idx, allIDs.count)
    }
    return nil
}

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

    /// 마지막 실행 버전 — 업데이트(버전 변경) 감지용. 업데이트로 권한이 깨졌을 때만 TCC reset.
    private static let lastRunVersionKey = "lastRunVersion"

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
    private var idlePulseWorkItem: DispatchWorkItem?
    private var lastPosUpdateTime: TimeInterval = 0
    private var lastTrailSampleTime: TimeInterval = 0

    // Quartz↔Cocoa 좌표 변환용 (handleMouseMove가 60Hz hotpath라 매번 NSScreen 쿼리 회피)
    // screensChanged()에서 갱신 — 모니터 구성 바뀔 때만.
    private var primaryScreenHeight: CGFloat = 0

    private var isEnabled = true

    // 낯선 외장 모니터 자동 키스트로크 상태 추적.
    // autoKeystrokeActive: 우리가 자동으로 켰는지. keystrokeStateBeforeAuto: 자동 켜기 직전 사용자 상태(복원용).
    // 앱 재시작을 넘어 유지돼야 한다 — 메모리 변수면 재시작 시 "자동으로 켰다"는 사실을 잊어,
    // isKeystrokeEnabled(영구 저장)가 복원되지 않고 영구 ON으로 남는 버그가 생긴다. 그래서 UserDefaults에 persist.
    private var autoKeystrokeActive: Bool {
        get { UserDefaults.standard.bool(forKey: "autoKeystrokeActive") }
        set { UserDefaults.standard.set(newValue, forKey: "autoKeystrokeActive") }
    }
    private var keystrokeStateBeforeAuto: Bool {
        get { UserDefaults.standard.bool(forKey: "keystrokeStateBeforeAuto") }
        set { UserDefaults.standard.set(newValue, forKey: "keystrokeStateBeforeAuto") }
    }

    // 트랙패드 제스처 (실험적, 비공식 API) — 토글 변화 구독.
    private var trackpadGestureCancellable: AnyCancellable?
    private var autoKeystrokeCancellable: AnyCancellable?

    // 가장 최근 트랙패드 swipe 발생 시점 (gesture detect 시점, fire 시점 아님).
    // polling이 자기 firedAt < latestSwipeFiredAt이면 stale (=더 새 swipe 이미 있음) → skip.
    // 매 swipe마다 갱신하므로 두 swipe 연속 시 newer가 살아남고 older의 polling은 skip.
    private var latestSwipeFiredAt: Date = .distantPast

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

        // 시작 시 이미 낯선 외장 모니터 연결돼 있으면 자동 키스트로크 평가
        evaluateAutoKeystroke()

        // UI 안정화 후 권한 4개 체크 — 일부라도 missing 시 alert.
        // brew upgrade 같은 cdhash 변경으로 권한이 reset된 경우 사용자에게 즉시 안내.
        Task { [weak self] in
            await self?.checkPermissionsAndAlertIfMissing()
        }
    }

    /// launch 시 권한 3개 (손쉬운 사용 / 화면 녹화 / 입력 모니터링) 체크.
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

        // 안내 순서를 enum 순서대로 안정화 (PermissionType.allCases 기준)
        let missingOrdered = PermissionsManager.PermissionType.allCases.filter { alwaysMissing.contains($0) }

        // 업데이트(버전 변경)로 권한이 깨진 경우에만 깨진 권한의 stale TCC 엔트리를 초기화하고 목록에 재등록한다.
        // ad-hoc 빌드는 cdhash 변경으로 권한이 깨져도 설정엔 체크돼 보여 사용자가 off→on 토글을 강제당하는데,
        // stale 엔트리를 지우면 켜기만 하면 됨. 정상 유지된 권한·신규 설치 첫 실행은 건드리지 않음.
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let previousVersion = UserDefaults.standard.string(forKey: Self.lastRunVersionKey)
        let isUpdate = PermissionsManager.isUpdateLaunch(previous: previousVersion, current: currentVersion)
        UserDefaults.standard.set(currentVersion, forKey: Self.lastRunVersionKey)
        if isUpdate && !missingOrdered.isEmpty {
            let names = missingOrdered.map(\.rawValue).joined(separator: ", ")
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "CursorHighlight", category: "permissions")
                .notice("업데이트(\(previousVersion ?? "?", privacy: .public)→\(currentVersion, privacy: .public))로 깨진 권한 초기화: \(names, privacy: .public)")
            PermissionsManager.resetTCCEntries(for: missingOrdered)
            permissionsManager?.registerForScreenRecordingPrompt()
            permissionsManager?.registerForInputMonitoringPrompt()
        }

        guard !missingOrdered.isEmpty else { return }

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

        // 클립보드에 앱 경로 복사 — 시스템 설정의 「+」 버튼으로 추가 시 ⌘V로 바로 붙여넣기.
        // (특히 ad-hoc 사이닝된 빌드에선 입력 모니터링은 자동 등재 안 돼 「+」가 유일한 길)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("/Applications/CursorHighlight.app", forType: .string)

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
        // 시스템 화면 녹화 + 입력 모니터링 권한 목록에 우리 앱을 silent 등록 —
        // 손쉬운 사용처럼 자동 등장. 첫 launch 시 macOS 표준 프롬프트 1회, 이후엔 캐시된 결정 사용.
        // 사용자가 in-app "권한 요청" 버튼 거치지 않고 시스템 설정에서 직접 토글 가능.
        permissionsManager?.registerForScreenRecordingPrompt()
        permissionsManager?.registerForInputMonitoringPrompt()

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
        //
        // 수평 swipe는 IMMEDIATE 안 띄움 — boundary 케이스는 즉시 softReveal, middle 케이스는
        // polling으로 Space 변경 commit 시점에 softReveal. 두 단계 "tail + restart" 시각 제거.
        // 수직 swipe·핀치는 IMMEDIATE 유지 (Space 전환 아니라 compositor 차단 없음).
        MultitouchService.shared.onGesture = { [weak self] gesture in
            guard let self else { return }
            guard self.settings.isTrackpadGesturesEnabled else { return }
            let pos = self.runtime.cursorPosition
            let speed = self.settings.animationSpeed.multiplier

            // 매 horizontal swipe마다 latestSwipeFiredAt 갱신 — 이후 polling이 stale 여부 판단.
            let swipeFiredAt = Date()
            if Self.isHorizontalSwipe(gesture) {
                self.latestSwipeFiredAt = swipeFiredAt
                let boundary = self.isAtBoundaryFor(gesture: gesture, position: pos)
                if boundary {
                    // boundary: Space 전환 안 일어남 → 즉시 softReveal로 발사.
                    self.effects.addTrackpadGesture(gesture, at: pos, animationSpeed: speed, softReveal: true)
                } else {
                    // middle: Space 전환 commit 시점에 softReveal — polling.
                    let sigBefore = currentSpacesSignature()
                    self.pollForMiddleSpaceChange(
                        gesture: gesture, position: pos,
                        sigBefore: sigBefore, firedAt: swipeFiredAt,
                        deadline: swipeFiredAt.addingTimeInterval(1.6)
                    )
                }
            } else {
                // 수직·핀치: 즉시 발사 (Space 전환 안 일어남, latestSwipeFiredAt 관여 안 함).
                self.effects.addTrackpadGesture(gesture, at: pos, animationSpeed: speed)
            }
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

        // 설정 변화(신뢰 모니터 등록·기능 토글 등) 시 자동 키스트로크 재평가 — 같은 세션에서도 즉시 반영.
        autoKeystrokeCancellable = settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.evaluateAutoKeystroke() }

        // 레이저 포인터 활성 시 시스템 cursor 숨김 — 빨간 점만 보이게(자연스러운 레이저 느낌).
        // CGDisplayHideCursor는 "active context"를 가진 앱이 호출해야 시스템이 적용한다(Apple docs).
        // LSUIElement 앱은 평소 active가 아니므로 NSApp.activate로 context를 강제 확보한다.
        // CGDisplayHideCursor/ShowCursor는 reference count라 ON/OFF 짝 맞아야 한다.
        // dropFirst로 초기 emission(false) 무시, 실제 토글에서만 호출.
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 종료 시 시스템 multitouch 콜백 정리 — 안 풀면 잠재적으로 freed memory에 fire 가능.
        MultitouchService.shared.stop()
    }

    /// middle 케이스용 polling — IMMEDIATE 없이 Space 변경 commit 시점에 softReveal 한 번 발사.
    /// 변경 감지 못 한 채 timeout이면(boundary 감지 실패 등) softReveal로 fallback 발사.
    /// closure 캡처 방식이라 다음 swipe로 중단 안 됨, 각 swipe 독립적으로 처리.
    private func pollForMiddleSpaceChange(
        gesture: TrackpadGesture, position: CGPoint,
        sigBefore: String, firedAt: Date, deadline: Date
    ) {
        // Stale 보호: 자기 firedAt이 마지막 swipe firedAt보다 오래됐다 = 더 새 swipe가 이미 발생.
        // 그쪽이 fire(boundary) 또는 자기 polling으로 처리 — 이 polling은 skip하여 중복 회피.
        if firedAt < self.latestSwipeFiredAt {
            return
        }
        if Date() > deadline {
            // timeout: boundary 감지 실패 등 — softReveal로 fallback 발사.
            self.effects.addTrackpadGesture(
                gesture, at: position,
                animationSpeed: self.settings.animationSpeed.multiplier,
                softReveal: true
            )
            return
        }
        let sigNow = currentSpacesSignature()
        if sigNow != sigBefore {
            // Space 전환 commit 감지 → softReveal로 슬라이드 끝과 합류.
            self.effects.addTrackpadGesture(
                gesture, at: position,
                animationSpeed: self.settings.animationSpeed.multiplier,
                softReveal: true
            )
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.pollForMiddleSpaceChange(
                gesture: gesture, position: position,
                sigBefore: sigBefore, firedAt: firedAt, deadline: deadline
            )
        }
    }

    /// 수평 swipe의 boundary 여부 — cursor 위치 디스플레이의 현재 Space가 swipe 방향 끝에 있으면 true.
    /// macOS: swipe LEFT(fingers) → 우측 Space로 이동 → 우측 끝이면 boundary
    /// swipe RIGHT(fingers) → 좌측 Space로 이동 → 좌측 끝이면 boundary
    private func isAtBoundaryFor(gesture: TrackpadGesture, position: CGPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(position) }),
              let dispID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let info = spaceIndexForDisplay(dispID) else {
            return false  // 정보 못 얻으면 middle로 가정 (안전한 default — polling이 처리)
        }
        switch gesture {
        case .threeFingerSwipeLeft, .fourFingerSwipeLeft:
            return info.current >= info.total - 1
        case .threeFingerSwipeRight, .fourFingerSwipeRight:
            return info.current <= 0
        default:
            return false
        }
    }

    /// 수평 swipe 여부 — Space 전환 발생 가능한 4종.
    private static func isHorizontalSwipe(_ g: TrackpadGesture) -> Bool {
        switch g {
        case .threeFingerSwipeLeft, .threeFingerSwipeRight,
             .fourFingerSwipeLeft, .fourFingerSwipeRight:
            return true
        default:
            return false
        }
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

        // Radial Menu 활성 중 — cursor 위치로 sector + subItem 강조 갱신.
        // dead zone(<50pt)=cancel · 메인 wedge(50~150pt)=sector 자유 변경 · 서브 wedge(≥150pt)=현재 sector 잠금.
        // 잠금 이유: subSpan이 45° 넘으면 옆 sector 영역까지 침범하는데, sector를 매번 재계산하면 다른 메뉴로 새버려서
        //   사용자가 가장 가장자리 sub 항목을 못 누르는 실수가 잦았음. 서브 진입 후엔 활성 sector 유지 + sub만 가장 가까운 데로 clamp.
        if runtime.isRadialMenuActive {
            let dx = pos.x - runtime.radialMenuCenter.x
            let dy = pos.y - runtime.radialMenuCenter.y
            let dist = sqrt(dx*dx + dy*dy)
            let newSector: Int?
            var newSubItem: Int? = nil
            if dist < Tokens.Radial.deadRadius {
                newSector = nil
            } else if dist > Tokens.Radial.subOuter {
                // 메뉴 바깥(서브 ring 너머) — 어떤 sub도 선택되지 않은 상태. 그 자리 클릭은 무효.
                newSector = nil
            } else {
                let atan2Deg = atan2(dy, dx) * 180 / .pi
                let cwFromTop = (90 - atan2Deg + 720).truncatingRemainder(dividingBy: 360)
                if dist < Tokens.Radial.mainOuter {
                    // 메인 영역 — sector를 angle로 자유 결정 (옆으로 가면 그쪽 sector로 전환).
                    newSector = Int((cwFromTop + 22.5) / 45) % 8
                } else {
                    // 서브 영역 — 활성 sector "잠금". 이미 sector가 선택돼 있으면 그대로, 첫 진입이면 angle로.
                    let lockedSec = runtime.radialMenuSelectedSector ?? Int((cwFromTop + 22.5) / 45) % 8
                    newSector = lockedSec
                    if let item = CursorSettings.RadialMenuItem(rawValue: lockedSec), item.subCount > 0 {
                        let mainAngle = Double(lockedSec) * 45
                        let subSpan = item.subSpan
                        let step = subSpan / Double(item.subCount)
                        // cwFromTop이 활성 sector 중심에서 벗어난 정도 (-180~+180으로 wrap)
                        var diff = cwFromTop - mainAngle
                        if diff > 180  { diff -= 360 }
                        if diff < -180 { diff += 360 }
                        let relAngle = diff + subSpan/2  // 0~subSpan 정규화
                        let clamped = max(0, min(subSpan - 0.001, relAngle))
                        newSubItem = Int(clamped / step)
                    }
                }
            }
            if runtime.radialMenuSelectedSector != newSector {
                runtime.radialMenuSelectedSector = newSector
            }
            if runtime.radialMenuSelectedSubItem != newSubItem {
                runtime.radialMenuSelectedSubItem = newSubItem
            }
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
        idlePulseWorkItem?.cancel()

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

        // 정지 펄스 — glow와 동시(1.5초) 트리거. 1회만 발생 (반복 없음).
        let pulse = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.settings.isIdlePulseEnabled, self.runtime.isCursorVisible,
                  !self.runtime.isDragging else { return }
            self.effects.addIdlePulseEffect(at: self.runtime.cursorPosition)
        }
        idlePulseWorkItem = pulse
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: pulse)
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
                // Radial menu 활성 중 클릭은 sub 실행 / dead zone close — 일반 클릭 효과 표시 안 함 (메뉴 위 ripple 부적절).
                if self.runtime.isRadialMenuActive {
                    self.keyboardHotkeyHandler?.handleRadialMenuClick()
                    return
                }
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
        keyboardHotkeyHandler?.mouseMonitor = monitor  // radial menu 활성 동안 좌클릭 소비 제어
    }

    // MARK: - 오버레이 윈도우

    private func setupOverlays() {
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map {
            OverlayWindowController(screen: $0, settings: settings, runtime: runtime, effects: effects, keystroke: keystrokeOverlay)
        }
        primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
    }

    @objc private func screensChanged() {
        setupOverlays()
        evaluateAutoKeystroke()
    }

    /// 낯선 외장 모니터(신뢰 목록에 없는) 연결 시 키스트로크 표시 자동 ON, 분리 시 원래대로.
    /// 자동 ON 전 사용자가 이미 켜둔 상태였으면 분리해도 그 상태(true) 유지.
    private func evaluateAutoKeystroke() {
        guard settings.autoKeystrokeOnUnknownMonitor else {
            // 기능 OFF — 자동으로 켜둔 게 있으면 직전 상태로 복원
            if autoKeystrokeActive {
                settings.isKeystrokeEnabled = keystrokeStateBeforeAuto
                autoKeystrokeActive = false
            }
            return
        }
        let externals = ExternalMonitor.current()
        let hasUnknown = externals.contains { !settings.isTrustedMonitor($0.uuid) }
        if hasUnknown {
            if !autoKeystrokeActive {
                keystrokeStateBeforeAuto = settings.isKeystrokeEnabled
                autoKeystrokeActive = true
                if !settings.isKeystrokeEnabled {
                    settings.isKeystrokeEnabled = true
                    keystrokeOverlay.showStatusNotification(String(localized: "⌨ 낯선 모니터 감지 — 키스트로크 표시 켜짐"))
                }
            }
        } else {
            if autoKeystrokeActive {
                settings.isKeystrokeEnabled = keystrokeStateBeforeAuto
                autoKeystrokeActive = false
            }
        }
    }
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
