import SwiftUI
import CoreGraphics
import AppKit

// MARK: - DrawingState
//
// ⌃⌥D 그리기 모드 — 발표/스크린캐스트용 자유 펜·화살표·직선 annotation.
// 모드 활성 중: 좌클릭 드래그가 그리기. 모디파이어로 도구 결정 (drag start 시점).
// 도형 색은 현재 ringColor를 따름 (DESIGN.md Active = ringColor follow).
// ESC로 clear + exit. ⌃⌥D 토글은 도형 유지 — 그린 후 모드 끄고 발표, 다시 켜서 추가 패턴.
@MainActor
final class DrawingState: ObservableObject {

    enum Tool {
        case pen, arrow, line
    }

    struct Shape: Identifiable {
        let id = UUID()
        let tool: Tool
        let color: Color
        var points: [CGPoint]  // pen: 모든 샘플 / arrow·line: [start, end]
    }

    @Published var isDrawingModeActive: Bool = false
    @Published var shapes: [Shape] = []
    @Published var currentShape: Shape? = nil

    /// 드래그 시작 — 모디파이어로 도구 결정. Shift=직선, Opt=화살표, 그 외=펜.
    func startShape(at point: CGPoint, modifiers: NSEvent.ModifierFlags, color: Color) {
        let tool: Tool
        if modifiers.contains(.option) {
            tool = .arrow
        } else if modifiers.contains(.shift) {
            tool = .line
        } else {
            tool = .pen
        }
        currentShape = Shape(tool: tool, color: color, points: [point])
    }

    /// 드래그 중 — 펜은 점 추가, 직선·화살표는 끝점만 갱신.
    func updateShape(to point: CGPoint) {
        guard var s = currentShape else { return }
        switch s.tool {
        case .pen:
            s.points.append(point)
        case .arrow, .line:
            if s.points.count >= 2 {
                s.points[1] = point
            } else {
                s.points.append(point)
            }
        }
        currentShape = s
    }

    /// 드래그 종료 — 진행 중 도형을 shapes에 확정. 빈 점이면 폐기.
    func endShape() {
        if let s = currentShape, s.points.count >= 2 {
            shapes.append(s)
        }
        currentShape = nil
    }

    /// ESC — 모든 도형 clear + 모드 종료. clean slate.
    func clearAndExit() {
        shapes.removeAll()
        currentShape = nil
        isDrawingModeActive = false
    }

    /// ⌃⌥D — 모드만 전환. 도형은 유지 (발표 중 그리기→끄고 작업→다시 그리기 패턴).
    /// 진행 중 도형은 폐기 (모드 끄는 순간 미완 stroke 남기지 않음).
    func toggleMode() {
        isDrawingModeActive.toggle()
        currentShape = nil
    }
}
