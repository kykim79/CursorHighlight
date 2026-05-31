import SwiftUI
import CoreGraphics
import AppKit

// MARK: - DrawingState
//
// ⌃⌥D 그리기 모드 — 발표/스크린캐스트용 annotation.
// 모드 활성 중: 좌클릭 드래그가 그리기. 모디파이어 조합으로 도구 결정 (drag start 시점).
// 도형 색은 현재 ringColor를 따름 (DESIGN.md Active = ringColor follow).
// ESC로 clear + exit. ⌃⌥D 토글은 도형 유지 — 그린 후 모드 끄고 발표, 다시 켜서 추가 패턴.
//
// v0.7.0: 사각형/타원/형광펜/번호 뱃지 4종 추가. Cmd+Z 마지막 도형 제거. [/] 두께 조절.
@MainActor
final class DrawingState: ObservableObject {

    enum Tool {
        case pen, arrow, line
        case rectangle, ellipse
        case highlighter  // 반투명 굵은 stroke ("이 영역 보세요")
        case badge        // 클릭 즉시 commit, 자동 번호 1·2·3...

        /// 사용자 노출용 한글 이름 — 도구 선택 알림에 사용.
        var displayName: String {
            switch self {
            case .pen:         return "펜"
            case .line:        return "직선"
            case .arrow:       return "화살표"
            case .rectangle:   return "사각형"
            case .ellipse:     return "타원"
            case .highlighter: return "형광펜"
            case .badge:       return "뱃지"
            }
        }
    }

    struct Shape: Identifiable {
        let id = UUID()
        let tool: Tool
        let color: Color
        let lineWidth: CGFloat        // startShape 시점 캡처 — 변경해도 진행 중 도형엔 영향 없음
        var points: [CGPoint]         // pen·highlighter: 모든 샘플 / 그 외: [start, end] (badge는 [point])
        let badgeNumber: Int?         // badge tool만 set, 그 외 nil
    }

    @Published var isDrawingModeActive: Bool = false
    @Published var shapes: [Shape] = []
    @Published var currentShape: Shape? = nil

    /// 현재 stroke 두께 — [/] 키로 조절. startShape 시점에 도형에 캡처.
    @Published var lineWidth: CGFloat = Tokens.Drawing.lineWidth

    /// 번호 뱃지 카운터 — 1부터 자동 증가, ESC 또는 모드 OFF 시 리셋.
    @Published var badgeCounter: Int = 1

    /// 현재 사용자가 누르고 있는 모디파이어 — toolbar에서 어떤 도구가 활성될지 실시간 표시용.
    /// flagsChanged 이벤트와 mouseMoved 시점에 갱신.
    @Published var currentModifiers: NSEvent.ModifierFlags = []

    /// Toolbar에서 sticky 선택한 도구. 모디파이어 없을 때 startShape이 이걸 사용.
    /// 모디파이어(Shift/Opt/Cmd)가 눌리면 그 modifier-derived tool이 우선 (Sketch 패턴).
    @Published var selectedTool: Tool = .pen

    /// Toolbar 도구별 버튼 영역(Cocoa global 좌표) — 좌클릭 hit-test로 도구 변경에 사용.
    /// OverlayContentView가 GeometryReader/PreferenceKey로 측정해 갱신.
    @Published var toolbarFrames: [Tool: CGRect] = [:]

    /// 두께 5 dot 영역 (Cocoa global) — 클릭 시 해당 step으로 lineWidth 변경.
    @Published var thicknessFrames: [CGFloat: CGRect] = [:]

    /// 색 7 dot 영역 (Cocoa global). 키는 RingColor.rawValue. 색은 settings에 있어 caller가 적용.
    @Published var colorFrames: [String: CGRect] = [:]

    /// Toolbar drag handle 영역 (Cocoa global) — 클릭으로 toolbar 이동 시작.
    @Published var dragHandleFrame: CGRect = .zero

    /// Toolbar 전체 크기 — clamp 계산용 (실제 너비로 화면 밖 방지).
    @Published var toolbarSize: CGSize = .zero

    /// 첫 N회 그리기 모드 켤 때 onboarding capsule 표시.
    @Published var showOnboarding: Bool = false

    /// Toolbar 이동 드래그 진행 여부 — true 동안엔 도구/두께/색 hit-test와 shape 시작 모두 skip.
    @Published var isDraggingToolbar: Bool = false

    // drag 시작 시점의 cursor + toolbar 위치 — 이후 cursor 이동량을 더해서 새 위치 계산.
    private var dragStartCursor: CGPoint = .zero
    private var dragStartLeading: CGFloat = 0
    private var dragStartBottom: CGFloat = 0

    /// 지금 드래그 시작하면 그려질 도구.
    /// 모디파이어 있으면 modifier-derived (Sketch 임시 override),
    /// 없으면 selectedTool (toolbar sticky default).
    var previewTool: Tool {
        let hasMods = currentModifiers.contains(.command)
            || currentModifiers.contains(.shift)
            || currentModifiers.contains(.option)
        return hasMods ? Self.tool(for: currentModifiers) : selectedTool
    }

    /// Toolbar 도구 영역 hit-test. 적중 시 selectedTool 갱신, true 반환.
    @discardableResult
    func hitToolbarAndSelect(at cocoaPoint: CGPoint) -> Bool {
        for (tool, rect) in toolbarFrames where rect.contains(cocoaPoint) {
            selectedTool = tool
            return true
        }
        return false
    }

    /// 두께 dot hit-test. 적중 시 lineWidth 갱신, true 반환.
    @discardableResult
    func hitThicknessAndSelect(at cocoaPoint: CGPoint) -> Bool {
        for (width, rect) in thicknessFrames where rect.contains(cocoaPoint) {
            lineWidth = width
            return true
        }
        return false
    }

    /// 색 dot hit-test. 적중 시 색 이름(RingColor.rawValue) 반환. caller가 settings.ringColor에 적용.
    func colorAt(_ cocoaPoint: CGPoint) -> String? {
        for (name, rect) in colorFrames where rect.contains(cocoaPoint) {
            return name
        }
        return nil
    }

    /// Toolbar drag 시작 — drag handle 클릭 시점에 호출.
    func beginToolbarDrag(cursor: CGPoint, leading: CGFloat, bottom: CGFloat) {
        isDraggingToolbar = true
        dragStartCursor = cursor
        dragStartLeading = leading
        dragStartBottom = bottom
    }

    /// 드래그 중 새 위치 계산. caller가 settings에 적용 (clamp 등 처리).
    /// Cocoa 좌표는 y 증가 = 위. bottom padding 증가 = 위로 이동 = dy 그대로 더함.
    func toolbarDragDelta(to cursor: CGPoint) -> (leading: CGFloat, bottom: CGFloat)? {
        guard isDraggingToolbar else { return nil }
        let dx = cursor.x - dragStartCursor.x
        let dy = cursor.y - dragStartCursor.y
        return (leading: dragStartLeading + dx, bottom: dragStartBottom + dy)
    }

    /// 드래그 종료.
    func endToolbarDrag() {
        isDraggingToolbar = false
    }

    /// 모디파이어 → 도구 매핑. 우선순위는 specific(combo) → general(single):
    ///   Shift+Opt = badge, Cmd+Opt = highlighter, Cmd+Shift = ellipse,
    ///   Cmd = rectangle, Opt = arrow, Shift = line, 그 외 = pen.
    static func tool(for modifiers: NSEvent.ModifierFlags) -> Tool {
        let cmd = modifiers.contains(.command)
        let shift = modifiers.contains(.shift)
        let opt = modifiers.contains(.option)
        if shift && opt && !cmd { return .badge }
        if cmd && opt { return .highlighter }
        if cmd && shift { return .ellipse }
        if cmd { return .rectangle }
        if opt { return .arrow }
        if shift { return .line }
        return .pen
    }

    /// 드래그 시작 — badge는 즉시 commit, 그 외는 currentShape 설정.
    /// 모디파이어 있으면 modifier-derived, 없으면 selectedTool (toolbar sticky).
    func startShape(at point: CGPoint, modifiers: NSEvent.ModifierFlags, color: Color) {
        let hasMods = modifiers.contains(.command) || modifiers.contains(.shift) || modifiers.contains(.option)
        let chosen: Tool = hasMods ? Self.tool(for: modifiers) : selectedTool
        if chosen == .badge {
            // 클릭만으로 commit, drag 무시
            shapes.append(Shape(tool: .badge, color: color, lineWidth: lineWidth, points: [point], badgeNumber: badgeCounter))
            badgeCounter += 1
            currentShape = nil
        } else {
            currentShape = Shape(tool: chosen, color: color, lineWidth: lineWidth, points: [point], badgeNumber: nil)
        }
    }

    /// 드래그 중 — pen·highlighter는 점 누적, rect·ellipse·line·arrow는 끝점만 갱신, badge는 무시.
    func updateShape(to point: CGPoint) {
        guard var s = currentShape else { return }
        switch s.tool {
        case .pen, .highlighter:
            s.points.append(point)
        case .arrow, .line, .rectangle, .ellipse:
            if s.points.count >= 2 {
                s.points[1] = point
            } else {
                s.points.append(point)
            }
        case .badge:
            return  // badge는 startShape에서 이미 commit, currentShape 없어야 함
        }
        currentShape = s
    }

    /// 드래그 종료 — 진행 중 도형 commit. 1점만 있으면 폐기 (badge는 startShape에서 이미 처리).
    func endShape() {
        if let s = currentShape, s.points.count >= 2 {
            shapes.append(s)
        }
        currentShape = nil
    }

    /// Cmd+Z — 마지막 도형 1개 제거 (badge 포함). undo stack 없음, 1 step만.
    func undoLastShape() {
        if !shapes.isEmpty {
            let removed = shapes.removeLast()
            // badge가 제거되면 counter 1 감소 — 다음에 그릴 때 같은 번호로 재사용
            if removed.tool == .badge {
                badgeCounter = max(1, badgeCounter - 1)
            }
        }
    }

    /// [ — 두께 한 단계 감소. 토큰의 lineWidthSteps 기준, 최소값 clamp.
    /// 반환: 변경 후 두께 (알림 표시용).
    @discardableResult
    func decreaseLineWidth() -> CGFloat {
        let steps = Tokens.Drawing.lineWidthSteps
        if let idx = steps.firstIndex(where: { abs($0 - lineWidth) < 0.01 }), idx > 0 {
            lineWidth = steps[idx - 1]
        } else if let smaller = steps.last(where: { $0 < lineWidth }) {
            // 현재 값이 step 사이에 있으면 가장 가까운 작은 step으로
            lineWidth = smaller
        }
        return lineWidth
    }

    /// ] — 두께 한 단계 증가.
    @discardableResult
    func increaseLineWidth() -> CGFloat {
        let steps = Tokens.Drawing.lineWidthSteps
        if let idx = steps.firstIndex(where: { abs($0 - lineWidth) < 0.01 }), idx < steps.count - 1 {
            lineWidth = steps[idx + 1]
        } else if let larger = steps.first(where: { $0 > lineWidth }) {
            lineWidth = larger
        }
        return lineWidth
    }

    /// ESC — 모든 도형 clear + 모드 종료 + 카운터/두께/도구 리셋. clean slate.
    func clearAndExit() {
        shapes.removeAll()
        currentShape = nil
        isDrawingModeActive = false
        badgeCounter = 1
        lineWidth = Tokens.Drawing.lineWidth
        selectedTool = .pen
    }

    /// ⌃⌥D — 모드만 전환. 도형은 유지 (발표 중 그리기→끄고 작업→다시 그리기 패턴).
    /// 진행 중 도형은 폐기 (모드 끄는 순간 미완 stroke 남기지 않음).
    /// 첫 N회 ON 시 onboarding capsule 표시.
    func toggleMode() {
        let wasActive = isDrawingModeActive
        isDrawingModeActive.toggle()
        currentShape = nil
        // OFF → ON 전환 시 onboarding 카운터 확인
        if !wasActive && isDrawingModeActive {
            let shown = UserDefaults.standard.integer(forKey: "drawingHelpShownCount")
            if shown < Tokens.Drawing.Toolbar.onboardingShowCount {
                UserDefaults.standard.set(shown + 1, forKey: "drawingHelpShownCount")
                showOnboarding = true
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(Tokens.Drawing.Toolbar.onboardingDuration))
                    self?.showOnboarding = false
                }
            }
        }
    }
}
