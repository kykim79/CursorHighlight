import XCTest
import Foundation

// CursorRuntimeState.updateDragAngle 의 ±π wrapping 검증.
// 핵심: atan2의 ±π 불연속을 정규화해 항상 최단 방향으로 누적되어야 함.
//   예) lastAngle=170°, newAngle=-170° → 시각적으로 20° 더 회전, 340° 회전 X.

@MainActor
final class DragAngleTests: XCTestCase {

    
    
    
    func test_initialAngleIsZero() {
        let state = CursorRuntimeState()
        XCTAssertEqual(state.dragAngle, 0)
    }

    func test_smallIncrement() {
        let state = CursorRuntimeState()
        state.dragAngle = 0
        state.updateDragAngle(0.5)  // ~28.6°
        XCTAssertEqual(state.dragAngle, 0.5, accuracy: 1e-9)
    }

    // 가장 중요한 케이스 — atan2 불연속 (+π → -π)
    func test_wrapAcrossPositivePiToNegativePi() {
        let state = CursorRuntimeState()
        state.dragAngle = .pi - 0.1   // +π에 가까움
        state.updateDragAngle(-.pi + 0.1)   // -π에 가까움 (시각적으로 0.2 rad 차이)
        // 시각적 회전: +0.2 (앞으로 살짝). -2π + 0.2 회전이 아님.
        XCTAssertEqual(state.dragAngle, .pi + 0.1, accuracy: 1e-9,
                       "+π→-π wrap은 최단 경로(+0.2)로 누적되어야 함")
    }

    func test_wrapAcrossNegativePiToPositivePi() {
        let state = CursorRuntimeState()
        state.dragAngle = -.pi + 0.1   // -π에 가까움
        state.updateDragAngle(.pi - 0.1)   // +π에 가까움 (시각적으로 -0.2 rad)
        XCTAssertEqual(state.dragAngle, -.pi - 0.1, accuracy: 1e-9,
                       "-π→+π wrap도 최단 경로(-0.2)로 누적되어야 함")
    }

    // 연속 회전 누적 — 한 바퀴 이상 돌면 2π 이상 값 유지
    func test_accumulatesAcrossMultipleRotations() {
        let state = CursorRuntimeState()
        state.dragAngle = 0
        // 한 바퀴를 atan2가 반환하는 형식대로 8단계로 회전
        let steps = stride(from: 0.0, through: 2 * .pi, by: .pi / 4).map {
            atan2(sin($0), cos($0))
        }
        for newAngle in steps.dropFirst() {
            state.updateDragAngle(newAngle)
        }
        XCTAssertEqual(state.dragAngle, 2 * .pi, accuracy: 1e-9,
                       "한 바퀴 누적 후 dragAngle은 2π 부근이어야 함 (wrapped로 0 회귀 X)")
    }

    // endDrag는 정규화 + 0 리셋
    func test_endDragNormalizesAndResets() {
        let state = CursorRuntimeState()
        state.dragAngle = 5 * .pi  // 임의의 큰 값
        state.endDrag()
        XCTAssertEqual(state.dragAngle, 0, "endDrag 후 dragAngle=0")
    }
}
