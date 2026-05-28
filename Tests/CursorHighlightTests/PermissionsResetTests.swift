import XCTest

// PermissionsManager의 업데이트 감지·TCC 서비스명 매핑 순수 로직 검증.
// 실제 tccutil 실행은 GUI/시스템 의존이라 제외 — 분기 판정과 매핑만 검증한다.

@MainActor
final class PermissionsResetTests: XCTestCase {

    // MARK: - isUpdateLaunch

    func test_isUpdateLaunch_firstInstall_isFalse() {
        // 이전 버전 기록 없음(신규 설치 첫 실행) → 업데이트 아님 → reset 안 함
        XCTAssertFalse(PermissionsManager.isUpdateLaunch(previous: nil, current: "0.5.6"))
    }

    func test_isUpdateLaunch_sameVersion_isFalse() {
        XCTAssertFalse(PermissionsManager.isUpdateLaunch(previous: "0.5.6", current: "0.5.6"))
    }

    func test_isUpdateLaunch_versionChanged_isTrue() {
        XCTAssertTrue(PermissionsManager.isUpdateLaunch(previous: "0.5.5", current: "0.5.6"))
    }

    func test_isUpdateLaunch_downgrade_isTrue() {
        // 다운그레이드도 버전 변경이므로 업데이트로 간주 (깨진 권한 있으면 reset 대상)
        XCTAssertTrue(PermissionsManager.isUpdateLaunch(previous: "0.6.0", current: "0.5.6"))
    }

    // MARK: - tccServiceName 매핑

    func test_tccServiceName_mapping() {
        XCTAssertEqual(PermissionsManager.PermissionType.accessibility.tccServiceName, "Accessibility")
        XCTAssertEqual(PermissionsManager.PermissionType.screenRecording.tccServiceName, "ScreenCapture")
        XCTAssertEqual(PermissionsManager.PermissionType.listenEvent.tccServiceName, "ListenEvent")
    }
}
