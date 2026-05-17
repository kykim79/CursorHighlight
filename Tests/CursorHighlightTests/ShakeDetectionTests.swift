import XCTest
import CoreGraphics

// ShakeState.record(x:y:at:) — 마우스 흔들기 감지 알고리즘 검증.
//
// 감지 조건:
//   - 인접 샘플의 우세축 속도(max(|vx|,|vy|)) > 300 pt/s
//   - 이전 속도의 |값| > 300 + 부호 반대 (방향 전환)
//   - 0.5초 안에 방향 전환 3회 누적 → detected
//
// 우세축 방식 — 좌우/위아래/대각선 모두 같은 방식으로 detect.
// 모든 테스트는 시간을 명시적으로 주입해 wall clock 의존성 없음.

final class ShakeDetectionTests: XCTestCase {

    // MARK: - 경계 케이스

    func test_emptyStateNoDetection() {
        var state = ShakeState()
        XCTAssertFalse(state.record(x: 100, y: 0, at: 0))
    }

    func test_firstSampleNeverDetects() {
        var state = ShakeState()
        XCTAssertFalse(state.record(x: 0, y: 0, at: 0))
    }

    func test_singleFastMoveDoesNotDetect() {
        var state = ShakeState()
        XCTAssertFalse(state.record(x: 0, y: 0, at: 0))
        XCTAssertFalse(state.record(x: 100, y: 0, at: 0.05))   // vx=+2000, lastV=0 → lastV 설정만
        XCTAssertFalse(state.record(x: 0, y: 0, at: 0.10))     // vx=-2000 → dirChanges=1
    }

    // MARK: - 수평 흔들기 (좌우)

    func test_horizontalShakeDetects() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt
        XCTAssertFalse(state.record(x: 100, y: 0, at: t)); t += dt   // lastV=+2000
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt     // dirChanges=1
        XCTAssertFalse(state.record(x: 100, y: 0, at: t)); t += dt   // dirChanges=2
        XCTAssertTrue(state.record(x: 0, y: 0, at: t),
                      "좌우 빠른 진동 3회 → detect")
    }

    // MARK: - 수직 흔들기 (위아래) — 우세축이 y로 잡혀야 함

    func test_verticalShakeDetects() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt
        XCTAssertFalse(state.record(x: 0, y: 100, at: t)); t += dt   // vy=+2000, lastV=0 → set lastV=+2000
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt     // vy=-2000, dirChanges=1
        XCTAssertFalse(state.record(x: 0, y: 100, at: t)); t += dt   // dirChanges=2
        XCTAssertTrue(state.record(x: 0, y: 0, at: t),
                      "위아래 빠른 진동 3회 → detect (우세축이 y로 잡힘)")
    }

    // MARK: - 대각선 흔들기 — 더 큰 축이 우세축

    func test_diagonalShakeDetects() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        // x=100, y=200 → dominant axis = y
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt
        XCTAssertFalse(state.record(x: 100, y: 200, at: t)); t += dt   // vy=+4000 dominant
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt       // dirChanges=1
        XCTAssertFalse(state.record(x: 100, y: 200, at: t)); t += dt   // dirChanges=2
        XCTAssertTrue(state.record(x: 0, y: 0, at: t),
                      "대각선 빠른 진동 — 우세축 기반 detect")
    }

    // MARK: - 음수 부호도 정상 처리

    func test_verticalShakeNegativeY() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt
        XCTAssertFalse(state.record(x: 0, y: -100, at: t)); t += dt    // vy=-2000
        XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt       // vy=+2000, dirChanges=1
        XCTAssertFalse(state.record(x: 0, y: -100, at: t)); t += dt    // dirChanges=2
        XCTAssertTrue(state.record(x: 0, y: 0, at: t),
                      "수직 음수 방향에서도 detect")
    }

    // MARK: - 카운터 리셋 (detect 후) — dedup window(0.5초) 통과 후 추가 진동 필요

    func test_counterResetsAfterDetection() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        XCTAssertTrue(state.record(x: 0, y: 0, at: t), "5번째에서 detect")
        // dedup window 통과 + 다음 진동 시퀀스
        t += 0.6
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        XCTAssertTrue(state.record(x: 100, y: 0, at: t),
                      "dedup window 후 새 진동에서 다시 detect")
    }

    // MARK: - Dedup window — detect 직후 0.5초 안엔 추가 detect 없음

    func test_dedupWithinHalfSecond() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        // 첫 detect
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        XCTAssertTrue(state.record(x: 0, y: 0, at: t), "첫 detect"); t += dt
        // 즉시 다음 진동 3회 — dedup window 안이라 detect 안 됨
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        XCTAssertFalse(state.record(x: 0, y: 0, at: t),
                       "dedup window(0.5초) 안엔 추가 detect 차단")
    }

    // MARK: - 대각선 흔들기에서 한 진동당 한 번만 detect (양 축 동시 trigger 회피)

    func test_diagonalDetectsOnlyOncePerShake() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        var detectionCount = 0
        // 좌하↔우상 동조형 대각선 — 양 축 동시 trigger되지만 dedup으로 한 번만
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 100, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 100, at: t); t += dt
        if state.record(x: 0, y: 0, at: t) { detectionCount += 1 }; t += dt
        // 같은 진동 계속 — dedup window 안이라 더 detect 안 되어야
        _ = state.record(x: 100, y: 100, at: t); t += dt
        if state.record(x: 0, y: 0, at: t) { detectionCount += 1 }; t += dt
        XCTAssertEqual(detectionCount, 1,
                       "대각선 동조 진동에서도 한 번만 detect (양 축 dedup)")
    }

    // MARK: - 느린 움직임 / 가만히

    func test_slowMovementNoDetection() {
        var state = ShakeState()
        let dt = 0.05
        let small: CGFloat = 5     // |v| = 100 — 임계 150 미만
        var t = 0.0
        for _ in 0..<10 {
            XCTAssertFalse(state.record(x: 0, y: 0, at: t)); t += dt
            XCTAssertFalse(state.record(x: small, y: small, at: t)); t += dt
        }
    }

    // MARK: - 긴 갭 후 카운터 리셋

    func test_gapDuringShakePreventsDetection() {
        var state = ShakeState()
        let dt = 0.05
        var t = 0.0
        _ = state.record(x: 0, y: 0, at: t); t += dt
        _ = state.record(x: 100, y: 0, at: t); t += dt
        _ = state.record(x: 0, y: 0, at: t); t += dt              // dirChanges=1
        _ = state.record(x: 100, y: 0, at: t); t += dt            // dirChanges=2
        t += 0.6                                                    // 긴 갭
        XCTAssertFalse(state.record(x: 0, y: 0, at: t),
                       "긴 갭 직후 한 record로는 detect 불가 (recent 만료)")
    }

    // MARK: - Window expiration

    func test_oldRecordsExpired() {
        var state = ShakeState()
        XCTAssertFalse(state.record(x: 0, y: 0, at: 0))
        XCTAssertFalse(state.record(x: 1000, y: 0, at: 0.05))
        XCTAssertFalse(state.record(x: 0, y: 0, at: 1.05),
                       "1초 갭 후엔 이전 샘플 모두 제거되어 detect 불가")
    }

    // MARK: - Zero / tiny dt 안전

    func test_zeroTimeStepIsSafe() {
        var state = ShakeState()
        XCTAssertFalse(state.record(x: 0, y: 0, at: 0))
        XCTAssertFalse(state.record(x: 100, y: 0, at: 0))            // dt=0 → skip
        XCTAssertFalse(state.record(x: 200, y: 0, at: 0.0005))       // dt<0.001 → skip
    }
}
