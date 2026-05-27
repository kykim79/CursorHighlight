import XCTest
import CoreGraphics

// TrackpadGestureClassifier — 손가락 trace 배열을 받아 제스처 종류를 추론하는 순수 함수.
// MultitouchService의 raw callback과 분리해 의존성 없이 검증.
// 좌표계: MTPoint 정규화 0..1, (0,0)=좌하단 ~ (1,1)=우상단 (Y가 위로 증가).

final class TrackpadGestureTests: XCTestCase {

    // MARK: - Helpers

    /// 모든 손가락이 동일 변위로 움직이는 균일 swipe trace 생성.
    private func uniformSwipe(count: Int, startCenter: CGPoint, delta: CGPoint, spread: Double = 0.04) -> [FingerTrace] {
        // 손가락은 startCenter 주변에 가로로 spread만큼 분산.
        var traces: [FingerTrace] = []
        for i in 0..<count {
            let lateral = (Double(i) - Double(count - 1) / 2) * spread
            let start = CGPoint(x: startCenter.x + lateral, y: startCenter.y)
            let end = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
            traces.append(FingerTrace(startPos: start, lastPos: end))
        }
        return traces
    }

    /// 4손가락 핀치: 4 코너에서 중심으로 모이거나(in), 중심에서 4 코너로 흩어짐(out).
    private func pinch(in: Bool, center: CGPoint = CGPoint(x: 0.5, y: 0.5), radius: Double) -> [FingerTrace] {
        // 4개 finger를 ±radius로 NE/SE/SW/NW에 배치.
        let r = radius
        let corners: [CGPoint] = [
            CGPoint(x: center.x + r, y: center.y + r),  // NE
            CGPoint(x: center.x + r, y: center.y - r),  // SE
            CGPoint(x: center.x - r, y: center.y - r),  // SW
            CGPoint(x: center.x - r, y: center.y + r)   // NW
        ]
        if `in` {
            // 시작: 코너, 끝: 중심에 가깝게
            return corners.map { FingerTrace(startPos: $0, lastPos: center) }
        } else {
            // 시작: 중심, 끝: 코너
            return corners.map { FingerTrace(startPos: center, lastPos: $0) }
        }
    }

    // MARK: - Swipes (3 finger)

    func test_3finger_swipe_up() {
        let traces = uniformSwipe(count: 3, startCenter: CGPoint(x: 0.5, y: 0.3), delta: CGPoint(x: 0, y: 0.2))
        XCTAssertEqual(TrackpadGestureClassifier.classify(peakFingers: 3, traces: traces), .threeFingerSwipeUp)
    }

    func test_3finger_swipe_down() {
        let traces = uniformSwipe(count: 3, startCenter: CGPoint(x: 0.5, y: 0.7), delta: CGPoint(x: 0, y: -0.2))
        XCTAssertEqual(TrackpadGestureClassifier.classify(peakFingers: 3, traces: traces), .threeFingerSwipeDown)
    }

    func test_3finger_swipe_left() {
        let traces = uniformSwipe(count: 3, startCenter: CGPoint(x: 0.7, y: 0.5), delta: CGPoint(x: -0.2, y: 0))
        XCTAssertEqual(TrackpadGestureClassifier.classify(peakFingers: 3, traces: traces), .threeFingerSwipeLeft)
    }

    func test_3finger_swipe_right() {
        let traces = uniformSwipe(count: 3, startCenter: CGPoint(x: 0.3, y: 0.5), delta: CGPoint(x: 0.2, y: 0))
        XCTAssertEqual(TrackpadGestureClassifier.classify(peakFingers: 3, traces: traces), .threeFingerSwipeRight)
    }

    // MARK: - Swipes (4 finger)

    func test_4finger_swipe_up() {
        let traces = uniformSwipe(count: 4, startCenter: CGPoint(x: 0.5, y: 0.3), delta: CGPoint(x: 0, y: 0.25))
        XCTAssertEqual(TrackpadGestureClassifier.classify(peakFingers: 4, traces: traces), .fourFingerSwipeUp)
    }

    func test_4finger_swipe_left() {
        let traces = uniformSwipe(count: 4, startCenter: CGPoint(x: 0.7, y: 0.5), delta: CGPoint(x: -0.2, y: 0))
        XCTAssertEqual(TrackpadGestureClassifier.classify(peakFingers: 4, traces: traces), .fourFingerSwipeLeft)
    }

    func test_4finger_swipe_right() {
        let traces = uniformSwipe(count: 4, startCenter: CGPoint(x: 0.3, y: 0.5), delta: CGPoint(x: 0.2, y: 0))
        XCTAssertEqual(TrackpadGestureClassifier.classify(peakFingers: 4, traces: traces), .fourFingerSwipeRight)
    }

    // MARK: - Pinches (4 finger only)

    func test_4finger_pinch_in() {
        let traces = pinch(in: true, radius: 0.20)
        XCTAssertEqual(TrackpadGestureClassifier.classify(peakFingers: 4, traces: traces), .fourFingerPinchIn)
    }

    func test_4finger_pinch_out() {
        let traces = pinch(in: false, radius: 0.20)
        XCTAssertEqual(TrackpadGestureClassifier.classify(peakFingers: 4, traces: traces), .fourFingerPinchOut)
    }

    func test_3finger_pinch_not_classified() {
        // 3손가락 핀치는 시스템 제스처 매핑이 없어 분류 안 함.
        // 3 손가락이 중심으로 모이는 모션을 만들어도 swipe도 아니고 pinch도 아니어야 함.
        let traces = [
            FingerTrace(startPos: CGPoint(x: 0.7, y: 0.5),  lastPos: CGPoint(x: 0.55, y: 0.5)),
            FingerTrace(startPos: CGPoint(x: 0.3, y: 0.5),  lastPos: CGPoint(x: 0.45, y: 0.5)),
            FingerTrace(startPos: CGPoint(x: 0.5, y: 0.65), lastPos: CGPoint(x: 0.5,  y: 0.55))
        ]
        // 평균 변위가 거의 0(서로 상쇄)이라 swipe도 아님 + 3손가락이라 pinch 분류도 안 함.
        XCTAssertNil(TrackpadGestureClassifier.classify(peakFingers: 3, traces: traces))
    }

    // MARK: - 경계 / 가드

    func test_2finger_returns_nil() {
        let traces = uniformSwipe(count: 2, startCenter: CGPoint(x: 0.5, y: 0.5), delta: CGPoint(x: 0.3, y: 0))
        XCTAssertNil(TrackpadGestureClassifier.classify(peakFingers: 2, traces: traces))
    }

    func test_5finger_returns_nil() {
        let traces = uniformSwipe(count: 5, startCenter: CGPoint(x: 0.5, y: 0.5), delta: CGPoint(x: 0.3, y: 0))
        XCTAssertNil(TrackpadGestureClassifier.classify(peakFingers: 5, traces: traces))
    }

    func test_below_swipe_threshold_returns_nil() {
        // 0.03 변위 = swipeThreshold(0.05) 미만 → swipe 아님. 3 finger라 pinch도 안 봄.
        let traces = uniformSwipe(count: 3, startCenter: CGPoint(x: 0.5, y: 0.5), delta: CGPoint(x: 0.03, y: 0))
        XCTAssertNil(TrackpadGestureClassifier.classify(peakFingers: 3, traces: traces))
    }

    func test_too_few_traces_returns_nil() {
        // peakFingers=4지만 trace 1개만 잡힌 경우 → 신뢰 못 함.
        let traces = [FingerTrace(startPos: CGPoint(x: 0.3, y: 0.5), lastPos: CGPoint(x: 0.6, y: 0.5))]
        XCTAssertNil(TrackpadGestureClassifier.classify(peakFingers: 4, traces: traces))
    }

    func test_invertY_flips_up_down() {
        // 같은 trace를 invertY=true로 부르면 up이 down으로.
        let upTraces = uniformSwipe(count: 3, startCenter: CGPoint(x: 0.5, y: 0.3), delta: CGPoint(x: 0, y: 0.2))
        XCTAssertEqual(TrackpadGestureClassifier.classify(peakFingers: 3, traces: upTraces), .threeFingerSwipeUp)
        XCTAssertEqual(TrackpadGestureClassifier.classify(peakFingers: 3, traces: upTraces, invertY: true), .threeFingerSwipeDown)
    }

    func test_inconsistent_direction_returns_nil() {
        // 한 손가락이 우세 축에서 명확히 반대로 움직임 (-0.2) → tolerance(0.02) 초과 → swipe 아님.
        // 다른 둘은 강하게 위로 → 평균 dy = 0.217 > swipeThreshold(0.08), 수직 dominant.
        let traces = [
            FingerTrace(startPos: CGPoint(x: 0.3, y: 0.5),  lastPos: CGPoint(x: 0.3, y: 0.3)),   // DOWN (dy=-0.2)
            FingerTrace(startPos: CGPoint(x: 0.5, y: 0.3),  lastPos: CGPoint(x: 0.5, y: 0.65)),  // strong up
            FingerTrace(startPos: CGPoint(x: 0.7, y: 0.3),  lastPos: CGPoint(x: 0.7, y: 0.65))   // strong up
        ]
        XCTAssertNil(TrackpadGestureClassifier.classify(peakFingers: 3, traces: traces))
    }

    // MARK: - 5 손가락 핀치 (Launchpad / Show Desktop)

    private func pinch5(in inward: Bool, radius: Double) -> [FingerTrace] {
        // 5 손가락: 4 코너 + 가운데 (또는 정오각형 — 어느 쪽이든 분류는 평균 반경으로 결정).
        let c = CGPoint(x: 0.5, y: 0.5)
        let corners: [CGPoint] = (0..<5).map { i in
            let a = -Double.pi / 2 + 2 * .pi * Double(i) / 5
            return CGPoint(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius)
        }
        return inward
            ? corners.map { FingerTrace(startPos: $0, lastPos: c) }
            : corners.map { FingerTrace(startPos: c, lastPos: $0) }
    }

    func test_5finger_pinch_in() {
        let traces = pinch5(in: true, radius: 0.20)
        XCTAssertEqual(TrackpadGestureClassifier.classify(peakFingers: 5, traces: traces), .fiveFingerPinchIn)
    }

    func test_5finger_pinch_out() {
        let traces = pinch5(in: false, radius: 0.20)
        XCTAssertEqual(TrackpadGestureClassifier.classify(peakFingers: 5, traces: traces), .fiveFingerPinchOut)
    }
}
