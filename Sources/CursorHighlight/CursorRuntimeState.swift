import Foundation
import CoreGraphics
import SwiftUI

// MARK: - CursorRuntimeState
//
// 마우스 위치, 가시성, 모션 시멘틱(클릭 펄스/드래그/글로우), 돋보기 런타임 상태.
// cursorPosition은 60Hz로 갱신되므로 이 객체를 보는 view만 그 빈도로 재평가됨.
// 설정(CursorSettings)이나 효과(EffectsState)와 분리되어 무관한 view 재계산을 피한다.
@MainActor
final class CursorRuntimeState: ObservableObject {
    // MARK: - Cursor Position & Visibility
    @Published var cursorPosition: CGPoint = .zero
    @Published var isCursorVisible: Bool = true

    // MARK: - Spotlight / Magnifier
    @Published var isSpotlightActive: Bool = false
    @Published var isMagnifierActive: Bool = false
    @Published var isLaserPointerActive: Bool = false  // ⌃⌥P 토글 — 활성 시 일반 링 숨기고 빨간 점만 표시 (발표·녹화용)
    @Published var magnifierImage: CGImage?
    @Published var hasScreenRecordingPermission: Bool = false

    // MARK: - Motion Semantics
    @Published var ringClickScale: CGFloat = 1.0
    @Published var ringClickTilt: Double = 0
    @Published var isDragging: Bool = false
    @Published var dragAngle: Double = 0
    @Published var dragVelocity: CGFloat = 0   // pt/s, EMA smoothed (#14 Speed Glow)
    @Published var dragOrigin: CGPoint? = nil  // 드래그 시작 위치 (Cocoa 글로벌, #17 Anchored Line)
    @Published var anchoredLineVisible: Bool = false  // #17 — 거리/시간 임계 만족 시만 true
    @Published var glowMultiplier: Double = 1.0

    // #17 — 거리/시간 임계로 자동 활성. 짧은 드래그(스크롤바 등)는 line 안 보임,
    // 의도적 긴 드래그(영역 강조)는 자연스럽게 표시.
    private static let anchoredLineDistanceThreshold: CGFloat = 100  // pt
    private static let anchoredLineTimeThreshold: TimeInterval = 1.0 // seconds
    private var anchoredLineTimer: Task<Void, Never>?

    // MARK: - Drag

    func startDrag(at origin: CGPoint) {
        dragAngle = 0
        dragOrigin = origin
        anchoredLineVisible = false
        // 시간 임계 — 1초 동안 드래그 계속되면 자동 fade in
        anchoredLineTimer?.cancel()
        anchoredLineTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.anchoredLineTimeThreshold))
            guard let self, self.isDragging else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.anchoredLineVisible = true
            }
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isDragging = true }
    }

    /// 거리 임계 — handleMouseMove에서 매 update 시 호출. 100pt 초과 시 즉시 fade in.
    func checkAnchoredLineDistance(currentPos: CGPoint) {
        guard let origin = dragOrigin, !anchoredLineVisible else { return }
        let dx = currentPos.x - origin.x
        let dy = currentPos.y - origin.y
        if dx * dx + dy * dy > Self.anchoredLineDistanceThreshold * Self.anchoredLineDistanceThreshold {
            withAnimation(.easeOut(duration: 0.3)) {
                anchoredLineVisible = true
            }
        }
    }

    func updateDragAngle(_ newAngle: Double) {
        // 이전 각도의 wrapped 값과 비교해 차이를 (-π, π] 로 정규화한 뒤 누적
        // → atan2의 ±π 불연속점이 사라져 애니메이션이 항상 짧은 방향으로 이동
        let lastWrapped = atan2(sin(dragAngle), cos(dragAngle))
        var diff = newAngle - lastWrapped
        if diff > .pi  { diff -= 2 * .pi }
        if diff < -.pi { diff += 2 * .pi }
        dragAngle += diff
    }

    /// 새 raw velocity(pt/s)를 받아 EMA로 부드럽게 누적. 매 frame jitter 회피.
    func updateDragVelocity(_ rawVelocity: CGFloat) {
        // alpha=0.3 — 새 값 30%, 이전 값 70%. 빠른 변화는 흡수, 일정 속도엔 빠르게 수렴.
        dragVelocity = dragVelocity * 0.7 + rawVelocity * 0.3
    }

    func endDrag() {
        // 다음 드래그를 위해 (-π, π]로 정규화 후 0으로 리셋
        dragAngle = atan2(sin(dragAngle), cos(dragAngle))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { isDragging = false }
        dragAngle = 0
        withAnimation(.easeOut(duration: 0.3)) { dragVelocity = 0 }
        // anchored line fade out + timer 정리
        anchoredLineTimer?.cancel()
        anchoredLineTimer = nil
        withAnimation(.easeOut(duration: 0.3)) { anchoredLineVisible = false }
        // 0.3초 fade out 후 dragOrigin 클리어 (line fade out 시간과 일치)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.dragOrigin = nil
        }

        // #15 Snap Back — 드래그 종료 순간 ring이 잠깐 expand 후 spring back.
        // 만족스러운 마이크로인터랙션 ("탁! 놓았다" 피드백). ringClickScale 재사용 (click과 겹치는
        // edge case는 드물고 동시 발생해도 visual 이상 X).
        withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
            ringClickScale = 1.12
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.4)) {
                self?.ringClickScale = 1.0
            }
        }
    }

    // MARK: - Click Pulse

    func triggerClickPulse(isDouble: Bool = false) {
        let scaleTarget: CGFloat = isDouble ? 0.6 : 0.75
        let tiltTarget: Double = isDouble ? 28 : 18
        withAnimation(.spring(response: 0.1, dampingFraction: 0.4)) {
            ringClickScale = scaleTarget
            ringClickTilt = tiltTarget
        }
        Task {
            try? await Task.sleep(for: .milliseconds(isDouble ? 160 : 130))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.45)) {
                ringClickScale = 1.0
                ringClickTilt = 0
            }
        }
    }
}
