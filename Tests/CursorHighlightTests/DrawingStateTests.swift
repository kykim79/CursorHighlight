import XCTest
import SwiftUI
import AppKit

// DrawingState — ⌃⌥D 그리기 모드 상태 머신 검증.
//
// 도메인 규칙:
//   - startShape(modifiers:): 모디파이어로 도구 결정 (Opt=arrow > Shift=line > 그 외 pen)
//   - updateShape: pen은 점 누적, line/arrow는 끝점만 갱신
//   - endShape: points.count >= 2 일 때만 shapes에 commit (단일 점 클릭 폐기)
//   - clearAndExit: 모든 도형 삭제 + 모드 OFF
//   - toggleMode: 모드만 전환, 도형 유지, 진행 중 stroke만 폐기
//
// View는 standalone bundle에서 테스트 불가 — 순수 상태 전이만 검증.

@MainActor
final class DrawingStateTests: XCTestCase {

    // MARK: - 모디파이어 → 도구 매핑

    func test_dragWithoutModifiers_picksPen() {
        let state = DrawingState()
        state.startShape(at: .zero, modifiers: [], color: .red)
        XCTAssertEqual(state.currentShape?.tool, .pen)
    }

    func test_shiftDrag_picksLine() {
        let state = DrawingState()
        state.startShape(at: .zero, modifiers: [.shift], color: .red)
        XCTAssertEqual(state.currentShape?.tool, .line)
    }

    func test_optionDrag_picksArrow() {
        let state = DrawingState()
        state.startShape(at: .zero, modifiers: [.option], color: .red)
        XCTAssertEqual(state.currentShape?.tool, .arrow)
    }

    // Opt + Shift 동시 누를 때 — 화살표 우선 (option 먼저 검사하는 분기 순서)
    func test_optionPlusShift_arrowWins() {
        let state = DrawingState()
        state.startShape(at: .zero, modifiers: [.option, .shift], color: .red)
        XCTAssertEqual(state.currentShape?.tool, .arrow)
    }

    // 무관한 모디파이어(cmd, control)는 펜으로 떨어짐
    func test_unrelatedModifiers_stillPicksPen() {
        let state = DrawingState()
        state.startShape(at: .zero, modifiers: [.command, .control], color: .red)
        XCTAssertEqual(state.currentShape?.tool, .pen)
    }

    // MARK: - updateShape 분기

    func test_updatePen_appendsAllPoints() {
        let state = DrawingState()
        state.startShape(at: CGPoint(x: 0, y: 0), modifiers: [], color: .red)
        state.updateShape(to: CGPoint(x: 10, y: 10))
        state.updateShape(to: CGPoint(x: 20, y: 20))
        state.updateShape(to: CGPoint(x: 30, y: 30))
        XCTAssertEqual(state.currentShape?.points.count, 4)  // 시작 + 3 update
        XCTAssertEqual(state.currentShape?.points.last, CGPoint(x: 30, y: 30))
    }

    func test_updateLine_replacesEndpointOnly() {
        let state = DrawingState()
        state.startShape(at: CGPoint(x: 0, y: 0), modifiers: [.shift], color: .red)
        state.updateShape(to: CGPoint(x: 10, y: 10))
        state.updateShape(to: CGPoint(x: 20, y: 20))
        state.updateShape(to: CGPoint(x: 30, y: 30))
        XCTAssertEqual(state.currentShape?.points.count, 2)
        XCTAssertEqual(state.currentShape?.points[0], CGPoint(x: 0, y: 0))
        XCTAssertEqual(state.currentShape?.points[1], CGPoint(x: 30, y: 30))  // 끝점만 갱신
    }

    func test_updateArrow_replacesEndpointOnly() {
        let state = DrawingState()
        state.startShape(at: CGPoint(x: 5, y: 5), modifiers: [.option], color: .red)
        state.updateShape(to: CGPoint(x: 100, y: 50))
        state.updateShape(to: CGPoint(x: 200, y: 100))
        XCTAssertEqual(state.currentShape?.points.count, 2)
        XCTAssertEqual(state.currentShape?.points[0], CGPoint(x: 5, y: 5))
        XCTAssertEqual(state.currentShape?.points[1], CGPoint(x: 200, y: 100))
    }

    // MARK: - endShape 가드

    func test_endShape_singlePoint_discarded() {
        // 클릭만 하고 드래그 안 한 경우 — currentShape는 1 point만, commit 안 됨
        let state = DrawingState()
        state.startShape(at: .zero, modifiers: [], color: .red)
        XCTAssertEqual(state.currentShape?.points.count, 1)
        state.endShape()
        XCTAssertEqual(state.shapes.count, 0)
        XCTAssertNil(state.currentShape)
    }

    func test_endShape_twoPoints_committed() {
        let state = DrawingState()
        state.startShape(at: .zero, modifiers: [], color: .red)
        state.updateShape(to: CGPoint(x: 1, y: 1))
        state.endShape()
        XCTAssertEqual(state.shapes.count, 1)
        XCTAssertNil(state.currentShape)
    }

    func test_endShape_withoutStart_noop() {
        let state = DrawingState()
        state.endShape()
        XCTAssertEqual(state.shapes.count, 0)
        XCTAssertNil(state.currentShape)
    }

    // MARK: - clearAndExit / toggleMode

    func test_clearAndExit_removesAllAndDisablesMode() {
        let state = DrawingState()
        state.isDrawingModeActive = true
        state.startShape(at: .zero, modifiers: [], color: .red)
        state.updateShape(to: CGPoint(x: 1, y: 1))
        state.endShape()
        state.startShape(at: .zero, modifiers: [], color: .red)  // 진행 중 도형도

        state.clearAndExit()

        XCTAssertEqual(state.shapes.count, 0)
        XCTAssertNil(state.currentShape)
        XCTAssertFalse(state.isDrawingModeActive)
    }

    func test_toggleMode_keepsShapes_dropsCurrentStroke() {
        // 그리기 모드 OFF로 토글 — 도형은 유지 (발표 중 그리고 끄고 마우스 작업 패턴), 진행 중 stroke만 폐기
        let state = DrawingState()
        state.isDrawingModeActive = true
        state.startShape(at: .zero, modifiers: [], color: .red)
        state.updateShape(to: CGPoint(x: 1, y: 1))
        state.endShape()  // 1 committed shape
        state.startShape(at: .zero, modifiers: [], color: .red)  // 진행 중 stroke

        state.toggleMode()

        XCTAssertFalse(state.isDrawingModeActive)
        XCTAssertEqual(state.shapes.count, 1)  // 완성 도형 유지
        XCTAssertNil(state.currentShape)       // 진행 중 stroke만 폐기
    }

    func test_toggleMode_twice_returnsToActive() {
        let state = DrawingState()
        state.toggleMode()  // OFF → ON
        XCTAssertTrue(state.isDrawingModeActive)
        state.toggleMode()  // ON → OFF
        XCTAssertFalse(state.isDrawingModeActive)
    }
}
