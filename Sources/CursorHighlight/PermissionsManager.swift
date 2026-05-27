import AppKit
import ApplicationServices
import ScreenCaptureKit
import IOKit.hid

// CGRequestListenEventAccess — private CoreGraphics API. CGRequestScreenCaptureAccess의 키보드 버전:
// 입력 모니터링 TCC 목록 등록 + 첫 호출 시 prompt. macOS Sonoma+에서 IOHIDRequestAccess가
// preflight 조회만 하고 prompt 안 띄우는 회귀가 있어 이쪽으로 우회 (BetterTouchTool 등 다수 앱이 사용).
@_silgen_name("CGRequestListenEventAccess")
private func CGRequestListenEventAccess() -> Bool

// MARK: - PermissionsManager
//
// 손쉬운 사용 / 화면 녹화 / 입력 모니터링 권한 요청·polling·설정 패널 오픈.
// 화면 녹화 권한 상태는 runtime.hasScreenRecordingPermission으로 publish.
// PostEvent(입력 보내기)는 우리 앱이 이벤트 inject 안 하므로 필요 없음 — 체크 안 함.
@MainActor
final class PermissionsManager {
    // MARK: - 권한 타입 — launch 시 사용자에게 missing 안내할 때 사용
    enum PermissionType: String, CaseIterable {
        case accessibility = "손쉬운 사용"
        case screenRecording = "화면 녹화"
        case listenEvent = "입력 모니터링"

        /// 현재 locale에서 표시할 이름. rawValue를 Localizable.xcstrings 키로 사용.
        var localizedName: String { String(localized: String.LocalizationValue(rawValue)) }

        /// 시스템 설정 → 개인정보 보호 각 항목 URL
        var settingsURL: URL {
            let key: String
            switch self {
            case .accessibility:    key = "Privacy_Accessibility"
            case .screenRecording:  key = "Privacy_ScreenCapture"
            case .listenEvent:      key = "Privacy_ListenEvent"
            }
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(key)")!
        }
    }

    private weak var runtime: CursorRuntimeState?
    private var permissionCheckTimer: Timer?

    init(runtime: CursorRuntimeState) {
        self.runtime = runtime
    }

    deinit {
        permissionCheckTimer?.invalidate()
    }

    // MARK: - Accessibility (손쉬운 사용)

    /// 현재 손쉬운 사용 권한 보유 여부. CGEventTap이 동작하려면 true 필요.
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// 권한 요청 다이얼로그 표시 (한 번 부여하면 시스템에 등록됨).
    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Screen Recording (화면 녹화 — 돋보기용)

    /// 시스템 권한 다이얼로그 표시 + 설정 목록 자동 추가 + 설정 패널 열기.
    /// "권한 요청" 버튼 클릭 시 사용 — 사용자가 명시적으로 요청한 흐름.
    func requestScreenRecordingPermission() {
        registerForScreenRecordingPrompt()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    /// 시스템 권한 목록에 우리 앱을 silent 등록 — 설정 패널은 안 염.
    /// 앱 launch 직후 한 번 호출하면 손쉬운 사용처럼 앱이 화면 녹화 목록에 자동 등장.
    /// 사용자는 시스템 설정에서 그냥 토글만 하면 됨 (in-app 배너 거치지 않음).
    /// 첫 호출 시 macOS 표준 프롬프트가 한 번 뜨는 건 손쉬운 사용 첫 사용 때와 동일.
    func registerForScreenRecordingPrompt() {
        if #available(macOS 14.0, *) {
            CGRequestScreenCaptureAccess()
        } else {
            // macOS 13: SCShareableContent 조회로 프롬프트 유도 (deprecated API 없이)
            Task { _ = try? await SCShareableContent.current }
        }
    }

    static func hasScreenRecordingPermission() -> Bool {
        if #available(macOS 14.0, *) {
            // 프로세스 캐시 없이 TCC 데이터베이스를 직접 조회 — 프롬프트 없음
            return CGPreflightScreenCaptureAccess()
        }
        // macOS 13: kCGWindowName 유무로 확인 (CGWindowListCopyWindowInfo는 아직 supported)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { $0[kCGWindowName as String] != nil }
    }

    // MARK: - Polling

    /// 권한 부여 전까지 2초 간격으로 polling, 부여되면 자동 중지.
    func startPolling() {
        runtime?.hasScreenRecordingPermission = Self.hasScreenRecordingPermission()
        // 이미 권한 부여된 상태면 polling 불필요 (사용자가 회수하기 전까지 변하지 않음)
        if runtime?.hasScreenRecordingPermission == true { return }
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = Self.hasScreenRecordingPermission()
            guard granted != self.runtime?.hasScreenRecordingPermission else { return }
            DispatchQueue.main.async {
                self.runtime?.hasScreenRecordingPermission = granted
                if granted {
                    // 권한 부여됨 → 더 이상 polling 불필요
                    self.permissionCheckTimer?.invalidate()
                    self.permissionCheckTimer = nil
                }
                // 권한이 사라진 경우 isMagnifierActive를 강제 false로 끄지 않는다 —
                // SCStream start가 권한 부족이면 catch에서 처리하고, 이미 동작 중이면 자체 종료.
                // 여기서 강제 false 하면 권한 부여 직후 timing 이슈로 stream이 1초만에 stop되는 회귀 발생.
            }
        }
    }

    // MARK: - 입력 모니터링 — IOHIDCheckAccess (prompt 없는 상태 조회)

    /// 키보드 CGEventTap(.keyDown)은 macOS 10.15+에서 Input Monitoring 요구.
    /// KeyboardHotkeyHandler가 사용.
    static func hasListenEventPermission() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// 입력 모니터링 목록에 silent 등록 + 첫 호출 시 prompt.
    /// macOS Sonoma+ 에서 IOHIDRequestAccess는 preflight 조회만 하고 prompt 안 띄움(로그 검증됨).
    /// CGRequestListenEventAccess가 CGRequestScreenCaptureAccess의 키보드 버전 — 이게 진짜 prompt를 띄움.
    /// private CoreGraphics API라 @_silgen_name으로 직접 link (BetterTouchTool 등 다수 앱이 같은 패턴 사용).
    func registerForInputMonitoringPrompt() {
        _ = CGRequestListenEventAccess()
    }

    /// 3개 권한 중 현재 부여되지 않은 것 — launch 시 사용자에게 alert.
    /// 모두 부여 시 빈 배열.
    static func missingPermissions() -> [PermissionType] {
        var missing: [PermissionType] = []
        if !isAccessibilityTrusted { missing.append(.accessibility) }
        if !hasScreenRecordingPermission() { missing.append(.screenRecording) }
        if !hasListenEventPermission() { missing.append(.listenEvent) }
        return missing
    }

    // MARK: - 설정 패널 열기

    func openInputMonitoringSettings() {
        NSWorkspace.shared.open(PermissionType.listenEvent.settingsURL)
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(PermissionType.accessibility.settingsURL)
    }
}
