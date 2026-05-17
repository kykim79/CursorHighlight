import Foundation
import AppKit
import CoreGraphics

// MARK: - EffectsState
//
// 일시적 효과 큐 (클릭/더블클릭/흔들기/스크롤/트레일/클립보드).
// 각 효과는 Task로 일정 시간 후 자동 제거된다.
// animationSpeed는 호출 측에서 인자로 전달 — settings와 결합 회피.
@MainActor
final class EffectsState: ObservableObject {
    @Published var clickEffects: [ClickEffect] = []
    @Published var doubleClickEffects: [DoubleClickEffect] = []
    @Published var middleClickEffects: [MiddleClickEffect] = []
    @Published var shakeEffects: [ShakeEffect] = []
    @Published var scrollEffects: [ScrollEffect] = []
    @Published var trailPoints: [TrailPoint] = []
    @Published var clipboardEffects: [ClipboardEffect] = []

    // MARK: - Effect Structs
    struct ClickEffect: Identifiable {
        let id = UUID(); let position: CGPoint; let isRight: Bool; let isDouble: Bool
    }
    struct DoubleClickEffect: Identifiable {
        let id = UUID(); let position: CGPoint
    }
    struct MiddleClickEffect: Identifiable {
        let id = UUID(); let position: CGPoint
    }
    struct ShakeEffect: Identifiable {
        let id = UUID(); let position: CGPoint
    }
    /// magnitude: 스크롤 양 (트랙패드 1지손 ~5, 휠 ~10, 강한 swipe ~50+). 화살표 크기 비례용.
    struct ScrollEffect: Identifiable {
        let id = UUID(); let position: CGPoint; let isPositive: Bool; let isVertical: Bool; let magnitude: CGFloat
    }
    struct TrailPoint: Identifiable {
        let id = UUID(); let position: CGPoint
    }
    struct ClipboardEffect: Identifiable {
        let id = UUID(); let position: CGPoint; let emoji: String
    }

    // MARK: - Add Effects

    func addClickEffect(at point: CGPoint, isRight: Bool, isDouble: Bool = false, animationSpeed: Double) {
        let effect = ClickEffect(position: point, isRight: isRight, isDouble: isDouble)
        clickEffects.append(effect)
        if isDouble {
            let de = DoubleClickEffect(position: point)
            doubleClickEffects.append(de)
            Task {
                try? await Task.sleep(for: .seconds(0.9 * animationSpeed))
                doubleClickEffects.removeAll { $0.id == de.id }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(0.7 * animationSpeed))
            clickEffects.removeAll { $0.id == effect.id }
        }
    }

    func triggerShake(at point: CGPoint, animationSpeed: Double) {
        let effect = ShakeEffect(position: point)
        shakeEffects.append(effect)
        Task {
            try? await Task.sleep(for: .seconds(max(1.5, 1.8 * animationSpeed)))
            shakeEffects.removeAll { $0.id == effect.id }
        }
    }

    func addScrollEffect(at point: CGPoint, isPositive: Bool, isVertical: Bool, magnitude: CGFloat, animationSpeed: Double) {
        // 같은 화면의 이전 스크롤 효과만 제거 — 다중 모니터에서 다른 화면 효과는 유지.
        // 스크롤은 0.25초 디바운스(MouseEventMonitor)라 NSScreen 쿼리 빈도 낮음.
        if let currentScreen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            scrollEffects.removeAll { currentScreen.frame.contains($0.position) }
        }
        let effect = ScrollEffect(position: point, isPositive: isPositive, isVertical: isVertical, magnitude: magnitude)
        scrollEffects.append(effect)
        Task {
            try? await Task.sleep(for: .seconds(0.65 * animationSpeed))
            scrollEffects.removeAll { $0.id == effect.id }
        }
    }

    /// 휠 클릭 (button 2) — 회전 파동 효과. 0.7초 후 자동 제거.
    func addMiddleClickEffect(at point: CGPoint, animationSpeed: Double) {
        let effect = MiddleClickEffect(position: point)
        middleClickEffects.append(effect)
        Task {
            try? await Task.sleep(for: .seconds(0.7 * animationSpeed))
            middleClickEffects.removeAll { $0.id == effect.id }
        }
    }

    func addClipboardEffect(at point: CGPoint, emoji: String) {
        let effect = ClipboardEffect(position: point, emoji: emoji)
        clipboardEffects.append(effect)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            clipboardEffects.removeAll { $0.id == effect.id }
        }
    }

    // MARK: - Trail
    func updateTrail(_ point: CGPoint) {
        trailPoints.append(TrailPoint(position: point))
        if trailPoints.count > 26 { trailPoints.removeFirst() }
    }
    func clearTrail() { trailPoints.removeAll() }

    // MARK: - Drag Trail (#18 Comet Tail — 드래그 중에만 sample, 더 짧고 굵게)
    @Published var dragTrailPoints: [TrailPoint] = []

    func updateDragTrail(_ point: CGPoint) {
        dragTrailPoints.append(TrailPoint(position: point))
        if dragTrailPoints.count > 14 { dragTrailPoints.removeFirst() }  // 일반 trail보다 짧은 streak
    }

    /// 드래그 종료 시 즉시 비우지 않고 점진 fade out — 매 frame 앞 point 1개씩 제거.
    /// SwiftUI animation으로 부드럽게 사라지는 효과.
    func fadeDragTrail() {
        guard !dragTrailPoints.isEmpty else { return }
        let initial = dragTrailPoints.count
        Task { @MainActor [weak self] in
            for _ in 0..<initial {
                try? await Task.sleep(for: .milliseconds(40))
                guard let self, !self.dragTrailPoints.isEmpty else { return }
                self.dragTrailPoints.removeFirst()
            }
        }
    }
}
