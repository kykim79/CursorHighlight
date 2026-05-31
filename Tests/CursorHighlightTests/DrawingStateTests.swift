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

    // Opt + Shift 동시 누를 때 — v0.7.0부터 badge (즉시 commit, currentShape는 nil)
    func test_optionPlusShift_picksBadge() {
        let state = DrawingState()
        state.startShape(at: .zero, modifiers: [.option, .shift], color: .red)
        XCTAssertNil(state.currentShape)  // badge는 즉시 commit
        XCTAssertEqual(state.shapes.first?.tool, .badge)
    }

    // Control만 단독은 무관 modifier — 펜으로 떨어짐
    func test_controlOnly_stillPicksPen() {
        let state = DrawingState()
        state.startShape(at: .zero, modifiers: [.control], color: .red)
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

    // MARK: - v0.7.0 신규 도구 (사각형/타원/형광펜/뱃지)

    func test_cmdDrag_picksRectangle() {
        let state = DrawingState()
        state.startShape(at: .zero, modifiers: [.command], color: .red)
        XCTAssertEqual(state.currentShape?.tool, .rectangle)
    }

    func test_cmdShiftDrag_picksEllipse() {
        let state = DrawingState()
        state.startShape(at: .zero, modifiers: [.command, .shift], color: .red)
        XCTAssertEqual(state.currentShape?.tool, .ellipse)
    }

    func test_cmdOptDrag_picksHighlighter() {
        let state = DrawingState()
        state.startShape(at: .zero, modifiers: [.command, .option], color: .red)
        XCTAssertEqual(state.currentShape?.tool, .highlighter)
    }

    func test_highlighter_accumulatesPointsLikePen() {
        let state = DrawingState()
        state.startShape(at: CGPoint(x: 0, y: 0), modifiers: [.command, .option], color: .red)
        state.updateShape(to: CGPoint(x: 10, y: 10))
        state.updateShape(to: CGPoint(x: 20, y: 20))
        XCTAssertEqual(state.currentShape?.points.count, 3)
    }

    func test_rectangle_replacesEndpointOnly() {
        let state = DrawingState()
        state.startShape(at: CGPoint(x: 0, y: 0), modifiers: [.command], color: .red)
        state.updateShape(to: CGPoint(x: 10, y: 10))
        state.updateShape(to: CGPoint(x: 100, y: 50))
        XCTAssertEqual(state.currentShape?.points.count, 2)
        XCTAssertEqual(state.currentShape?.points[1], CGPoint(x: 100, y: 50))
    }

    // MARK: - 번호 뱃지

    func test_shiftOptClick_immediatelyCommitsBadge() {
        // badge는 startShape에서 즉시 shapes에 들어가고 currentShape는 nil
        let state = DrawingState()
        state.startShape(at: CGPoint(x: 50, y: 50), modifiers: [.shift, .option], color: .red)
        XCTAssertEqual(state.shapes.count, 1)
        XCTAssertEqual(state.shapes.first?.tool, .badge)
        XCTAssertEqual(state.shapes.first?.badgeNumber, 1)
        XCTAssertNil(state.currentShape)
    }

    func test_badge_counterIncrements() {
        let state = DrawingState()
        state.startShape(at: .zero, modifiers: [.shift, .option], color: .red)
        state.startShape(at: CGPoint(x: 10, y: 10), modifiers: [.shift, .option], color: .red)
        state.startShape(at: CGPoint(x: 20, y: 20), modifiers: [.shift, .option], color: .red)
        XCTAssertEqual(state.shapes.map(\.badgeNumber), [1, 2, 3])
        XCTAssertEqual(state.badgeCounter, 4)
    }

    func test_badge_updateShape_noEffect() {
        let state = DrawingState()
        state.startShape(at: CGPoint(x: 100, y: 100), modifiers: [.shift, .option], color: .red)
        state.updateShape(to: CGPoint(x: 200, y: 200))  // badge는 update 무시
        XCTAssertEqual(state.shapes.first?.points, [CGPoint(x: 100, y: 100)])
    }

    // MARK: - Undo

    func test_undoLastShape_removesOne() {
        let state = DrawingState()
        state.startShape(at: .zero, modifiers: [], color: .red)
        state.updateShape(to: CGPoint(x: 10, y: 10))
        state.endShape()  // 1 pen
        state.startShape(at: .zero, modifiers: [.shift], color: .red)
        state.updateShape(to: CGPoint(x: 20, y: 20))
        state.endShape()  // 2 line
        XCTAssertEqual(state.shapes.count, 2)
        state.undoLastShape()
        XCTAssertEqual(state.shapes.count, 1)
        XCTAssertEqual(state.shapes.first?.tool, .pen)
    }

    func test_undoLastShape_empty_noop() {
        let state = DrawingState()
        state.undoLastShape()  // 빈 상태에서 호출
        XCTAssertEqual(state.shapes.count, 0)
    }

    func test_undoBadge_decrementsCounter() {
        // 뱃지 3, 4 그리고 마지막 undo → counter는 4로 복귀 (다음에 4번 재사용)
        let state = DrawingState()
        state.startShape(at: .zero, modifiers: [.shift, .option], color: .red)  // 1
        state.startShape(at: .zero, modifiers: [.shift, .option], color: .red)  // 2
        state.startShape(at: .zero, modifiers: [.shift, .option], color: .red)  // 3
        XCTAssertEqual(state.badgeCounter, 4)
        state.undoLastShape()
        XCTAssertEqual(state.badgeCounter, 3)
        XCTAssertEqual(state.shapes.count, 2)
    }

    // MARK: - 두께 조절

    func test_increaseLineWidth_movesUpByStep() {
        let state = DrawingState()
        XCTAssertEqual(state.lineWidth, 4)
        let after = state.increaseLineWidth()
        XCTAssertEqual(after, 6)
        XCTAssertEqual(state.lineWidth, 6)
    }

    func test_decreaseLineWidth_movesDownByStep() {
        let state = DrawingState()
        XCTAssertEqual(state.lineWidth, 4)
        let after = state.decreaseLineWidth()
        XCTAssertEqual(after, 2)
        XCTAssertEqual(state.lineWidth, 2)
    }

    func test_decreaseLineWidth_clampsAtMin() {
        let state = DrawingState()
        state.lineWidth = 2  // 최소 단계
        let after = state.decreaseLineWidth()
        XCTAssertEqual(after, 2)
    }

    func test_increaseLineWidth_clampsAtMax() {
        let state = DrawingState()
        state.lineWidth = 14  // 최대 단계
        let after = state.increaseLineWidth()
        XCTAssertEqual(after, 14)
    }

    func test_shape_capturesLineWidthAtStart() {
        // 도형이 startShape 시점의 두께를 보존 — 이후 lineWidth 바꿔도 영향 없음
        let state = DrawingState()
        state.lineWidth = 10
        state.startShape(at: .zero, modifiers: [], color: .red)
        state.updateShape(to: CGPoint(x: 5, y: 5))
        state.endShape()
        state.lineWidth = 14  // 새 두께 — 이미 그린 도형 영향 X
        XCTAssertEqual(state.shapes.first?.lineWidth, 10)
    }

    // MARK: - clearAndExit 확장

    func test_clearAndExit_resetsCounterAndWidth() {
        let state = DrawingState()
        state.isDrawingModeActive = true
        state.lineWidth = 14
        state.startShape(at: .zero, modifiers: [.shift, .option], color: .red)
        state.startShape(at: .zero, modifiers: [.shift, .option], color: .red)
        XCTAssertEqual(state.badgeCounter, 3)
        state.clearAndExit()
        XCTAssertEqual(state.badgeCounter, 1)
        XCTAssertEqual(state.lineWidth, Tokens.Drawing.lineWidth)
        XCTAssertEqual(state.shapes.count, 0)
        XCTAssertFalse(state.isDrawingModeActive)
    }

    // MARK: - selectedTool (toolbar sticky 선택) — v0.7.0 part 2

    func test_selectedTool_default_pen() {
        let state = DrawingState()
        XCTAssertEqual(state.selectedTool, .pen)
    }

    func test_dragWithoutMods_usesSelectedTool() {
        let state = DrawingState()
        state.selectedTool = .rectangle
        state.startShape(at: .zero, modifiers: [], color: .red)
        XCTAssertEqual(state.currentShape?.tool, .rectangle)  // toolbar 선택 따름
    }

    func test_modifierOverridesSelectedTool() {
        let state = DrawingState()
        state.selectedTool = .rectangle
        state.startShape(at: .zero, modifiers: [.shift], color: .red)
        XCTAssertEqual(state.currentShape?.tool, .line)  // Shift는 sticky보다 우선
    }

    func test_previewTool_noMods_returnsSelected() {
        let state = DrawingState()
        state.selectedTool = .ellipse
        state.currentModifiers = []
        XCTAssertEqual(state.previewTool, .ellipse)
    }

    func test_previewTool_withMods_returnsModifierTool() {
        let state = DrawingState()
        state.selectedTool = .ellipse
        state.currentModifiers = [.option]
        XCTAssertEqual(state.previewTool, .arrow)  // 모디파이어 우선
    }

    func test_clearAndExit_resetsSelectedTool() {
        let state = DrawingState()
        state.selectedTool = .arrow
        state.clearAndExit()
        XCTAssertEqual(state.selectedTool, .pen)
    }

    // MARK: - toolbar hit-test

    func test_hitToolbarAndSelect_inside_changesTool() {
        let state = DrawingState()
        state.toolbarFrames = [.rectangle: CGRect(x: 100, y: 200, width: 50, height: 50)]
        let hit = state.hitToolbarAndSelect(at: CGPoint(x: 120, y: 220))
        XCTAssertTrue(hit)
        XCTAssertEqual(state.selectedTool, .rectangle)
    }

    func test_hitToolbarAndSelect_outside_noChange() {
        let state = DrawingState()
        state.toolbarFrames = [.rectangle: CGRect(x: 100, y: 200, width: 50, height: 50)]
        let hit = state.hitToolbarAndSelect(at: CGPoint(x: 300, y: 300))
        XCTAssertFalse(hit)
        XCTAssertEqual(state.selectedTool, .pen)  // default 유지
    }

    func test_hitToolbarAndSelect_badge_selectsBadge() {
        // badge 도구도 sticky 선택 가능 — 다음 클릭이 badge 모드로 작동
        let state = DrawingState()
        state.toolbarFrames = [.badge: CGRect(x: 100, y: 200, width: 50, height: 50)]
        state.hitToolbarAndSelect(at: CGPoint(x: 120, y: 220))
        XCTAssertEqual(state.selectedTool, .badge)
        // 다음 클릭 (modifiers 없음) → badge 즉시 commit
        state.startShape(at: CGPoint(x: 500, y: 500), modifiers: [], color: .red)
        XCTAssertEqual(state.shapes.first?.tool, .badge)
        XCTAssertEqual(state.shapes.first?.badgeNumber, 1)
    }

    // MARK: - 두께/색 toolbar hit-test (v0.7.0 part 2)

    func test_hitThicknessAndSelect_inside_changesLineWidth() {
        let state = DrawingState()
        state.thicknessFrames = [10.0: CGRect(x: 50, y: 50, width: 24, height: 24)]
        let hit = state.hitThicknessAndSelect(at: CGPoint(x: 60, y: 60))
        XCTAssertTrue(hit)
        XCTAssertEqual(state.lineWidth, 10)
    }

    func test_hitThicknessAndSelect_outside_noChange() {
        let state = DrawingState()
        state.thicknessFrames = [10.0: CGRect(x: 50, y: 50, width: 24, height: 24)]
        let hit = state.hitThicknessAndSelect(at: CGPoint(x: 200, y: 200))
        XCTAssertFalse(hit)
        XCTAssertEqual(state.lineWidth, Tokens.Drawing.lineWidth)  // default 4
    }

    func test_colorAt_inside_returnsName() {
        let state = DrawingState()
        state.colorFrames = ["red": CGRect(x: 100, y: 100, width: 22, height: 22)]
        XCTAssertEqual(state.colorAt(CGPoint(x: 110, y: 110)), "red")
    }

    func test_colorAt_outside_returnsNil() {
        let state = DrawingState()
        state.colorFrames = ["red": CGRect(x: 100, y: 100, width: 22, height: 22)]
        XCTAssertNil(state.colorAt(CGPoint(x: 300, y: 300)))
    }

    // MARK: - Toolbar 위치 드래그

    func test_beginToolbarDrag_setsDraggingFlag() {
        let state = DrawingState()
        XCTAssertFalse(state.isDraggingToolbar)
        state.beginToolbarDrag(cursor: CGPoint(x: 100, y: 200), leading: 28, bottom: 110)
        XCTAssertTrue(state.isDraggingToolbar)
    }

    func test_toolbarDragDelta_returnsCumulativeOffset() {
        let state = DrawingState()
        state.beginToolbarDrag(cursor: CGPoint(x: 100, y: 200), leading: 28, bottom: 110)
        let delta = state.toolbarDragDelta(to: CGPoint(x: 150, y: 240))
        XCTAssertNotNil(delta)
        XCTAssertEqual(delta?.leading, 78)   // 28 + (150-100)
        XCTAssertEqual(delta?.bottom, 150)   // 110 + (240-200)  ← Cocoa y up = bottom 증가
    }

    func test_toolbarDragDelta_returnsNil_whenNotDragging() {
        let state = DrawingState()
        XCTAssertNil(state.toolbarDragDelta(to: CGPoint(x: 100, y: 100)))
    }

    func test_endToolbarDrag_clearsDraggingFlag() {
        let state = DrawingState()
        state.beginToolbarDrag(cursor: .zero, leading: 0, bottom: 0)
        state.endToolbarDrag()
        XCTAssertFalse(state.isDraggingToolbar)
        XCTAssertNil(state.toolbarDragDelta(to: CGPoint(x: 50, y: 50)))
    }
}
