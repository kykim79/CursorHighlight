import CoreGraphics
import Foundation

// MARK: - TrackpadGesture
//
// MultitouchSupport에서 받은 정규화 0..1 트랙패드 좌표 trace를 분류.
// 좌표계 약속: MTPoint 좌표는 (0,0)=좌하단, (1,1)=우상단 — Y가 위로 증가.
// (MultitouchSupport 표준; 만약 실측에서 Y가 반대로 나오면 invertY를 true로.)
//
// 순수 함수 — unit test로 검증 (`TrackpadGestureTests`).
// 실제 MTDevice·callback은 MultitouchService가 처리, 결과 trace를 이 분류기에 통과.
enum TrackpadGesture: String, Equatable, CaseIterable {
    case threeFingerSwipeUp
    case threeFingerSwipeDown
    case threeFingerSwipeLeft
    case threeFingerSwipeRight
    case fourFingerSwipeUp        // 보통 Mission Control
    case fourFingerSwipeDown      // 보통 App Exposé (또는 Mission Control)
    case fourFingerSwipeLeft      // Space 전환
    case fourFingerSwipeRight     // Space 전환
    case fourFingerPinchIn        // Launchpad (4손가락)
    case fourFingerPinchOut       // Show Desktop (4손가락)
    case fiveFingerPinchIn        // Launchpad (5손가락 = 엄지+4)
    case fiveFingerPinchOut       // Show Desktop (5손가락)

    var fingerCount: Int {
        switch self {
        case .threeFingerSwipeUp, .threeFingerSwipeDown,
             .threeFingerSwipeLeft, .threeFingerSwipeRight:
            return 3
        case .fiveFingerPinchIn, .fiveFingerPinchOut:
            return 5
        default:
            return 4
        }
    }

    /// 사람이 읽기 좋은 설명 (디버그·툴팁용)
    var label: String {
        switch self {
        case .threeFingerSwipeUp:    return "3손가락 ↑"
        case .threeFingerSwipeDown:  return "3손가락 ↓"
        case .threeFingerSwipeLeft:  return "3손가락 ←"
        case .threeFingerSwipeRight: return "3손가락 →"
        case .fourFingerSwipeUp:     return "4손가락 ↑"
        case .fourFingerSwipeDown:   return "4손가락 ↓"
        case .fourFingerSwipeLeft:   return "4손가락 ←"
        case .fourFingerSwipeRight:  return "4손가락 →"
        case .fourFingerPinchIn:     return "4손가락 핀치 인"
        case .fourFingerPinchOut:    return "4손가락 핀치 아웃"
        case .fiveFingerPinchIn:     return "5손가락 핀치 인"
        case .fiveFingerPinchOut:    return "5손가락 핀치 아웃"
        }
    }
}

// MARK: - FingerTrace

/// 한 손가락이 트랙패드에 접촉한 동안의 시작·끝 위치 (정규화 0..1).
struct FingerTrace: Equatable {
    let startPos: CGPoint
    var lastPos: CGPoint
}

// MARK: - Classifier

enum TrackpadGestureClassifier {
    /// 스와이프로 분류하는 평균 변위 임계 (정규화 단위; 트랙패드 폭 = 1).
    /// 트랙패드가 가로 > 세로라 수평 swipe는 정규화 변위가 작게 잡힘 → 0.08로 낮춤
    /// (~1cm 물리 이동에 해당). 0.12였을 땐 수평 누락 잦았음.
    static let swipeThreshold: Double = 0.08

    /// 일관성 검사 tolerance — 한 손가락이 우세축에서 약간 반대로 움직여도 OK.
    /// 사람 손가락은 완벽히 평행 안 움직임 — 0.02pt(~1.5mm)는 허용.
    static let consistencyTolerance: Double = 0.02

    /// 핀치로 분류하는 평균 (현재 - 시작) 중심 거리 변화 임계.
    /// 0.05 = ~5% 변화. 너무 작으면 단순 손 떨림.
    static let pinchThreshold: Double = 0.05

    /// peakFingerCount: 세션 중 동시에 인식된 손가락 최댓값 (사이 순간 1개 떨어진 경우 보정).
    /// traces: 세션 동안 등장한 모든 손가락(ID 별)의 startPos/lastPos.
    /// invertY: MTPoint Y가 (실측 결과) "아래로 증가"하면 true로 호출.
    static func classify(peakFingers: Int, traces: [FingerTrace], invertY: Bool = false) -> TrackpadGesture? {
        // 3, 4, 5 손가락 세션만 분류. (3 = swipe만, 4·5 = swipe+pinch)
        guard peakFingers == 3 || peakFingers == 4 || peakFingers == 5 else { return nil }
        // trace가 적게 잡혔으면 신뢰 못 함 (예: 빠르게 lift된 손가락이 sample 못 받음)
        guard traces.count >= 3 else { return nil }

        // 평균 변위 (모든 손가락 displacement의 평균)
        let dxs = traces.map { $0.lastPos.x - $0.startPos.x }
        let dysRaw = traces.map { $0.lastPos.y - $0.startPos.y }
        let dys = invertY ? dysRaw.map { -$0 } : dysRaw

        let avgDx = dxs.reduce(0, +) / Double(dxs.count)
        let avgDy = dys.reduce(0, +) / Double(dys.count)
        let magnitude = (avgDx * avgDx + avgDy * avgDy).squareRoot()

        // 1. 스와이프 후보 — 평균 변위가 임계 이상 + 우세 축에서 모든 손가락 같은 방향
        if magnitude > swipeThreshold {
            let horizontal = abs(avgDx) > abs(avgDy)
            // 우세 축 기준 sign agreement (tolerance 포함) — cosine > 0 보다 엄격하지만
            // 작은 반대 방향 drift는 허용. 손가락은 완벽히 평행 안 움직임.
            let consistent: Bool = {
                let tol = consistencyTolerance
                if horizontal {
                    // avgDx 방향과 반대로 tol 이상 움직인 손가락이 있으면 inconsistent
                    return avgDx > 0
                        ? dxs.allSatisfy { $0 > -tol }
                        : dxs.allSatisfy { $0 <  tol }
                } else {
                    return avgDy > 0
                        ? dys.allSatisfy { $0 > -tol }
                        : dys.allSatisfy { $0 <  tol }
                }
            }()
            if consistent {
                return swipeFor(peakFingers: peakFingers, horizontal: horizontal, dx: avgDx, dy: avgDy)
            }
        }

        // 2. 핀치 후보 — 4 또는 5 손가락. 중심점 기준 평균 반경 변화.
        if peakFingers == 4 || peakFingers == 5 {
            let startCx = traces.map { $0.startPos.x }.reduce(0, +) / Double(traces.count)
            let startCy = traces.map { $0.startPos.y }.reduce(0, +) / Double(traces.count)
            let endCx = traces.map { $0.lastPos.x }.reduce(0, +) / Double(traces.count)
            let endCy = traces.map { $0.lastPos.y }.reduce(0, +) / Double(traces.count)

            let avgStartRadius = traces.map {
                ($0.startPos.x - startCx) * ($0.startPos.x - startCx)
                    + ($0.startPos.y - startCy) * ($0.startPos.y - startCy)
            }.reduce(0, +) / Double(traces.count)
            let avgEndRadius = traces.map {
                ($0.lastPos.x - endCx) * ($0.lastPos.x - endCx)
                    + ($0.lastPos.y - endCy) * ($0.lastPos.y - endCy)
            }.reduce(0, +) / Double(traces.count)

            // sqrt로 normalized 단위로 환산
            let pinchDelta = avgEndRadius.squareRoot() - avgStartRadius.squareRoot()
            if pinchDelta > pinchThreshold {
                return peakFingers == 5 ? .fiveFingerPinchOut : .fourFingerPinchOut
            }
            if pinchDelta < -pinchThreshold {
                return peakFingers == 5 ? .fiveFingerPinchIn : .fourFingerPinchIn
            }
        }

        return nil
    }

    private static func swipeFor(peakFingers: Int, horizontal: Bool, dx: Double, dy: Double) -> TrackpadGesture? {
        switch (peakFingers, horizontal) {
        case (3, true):  return dx > 0 ? .threeFingerSwipeRight : .threeFingerSwipeLeft
        case (3, false): return dy > 0 ? .threeFingerSwipeUp    : .threeFingerSwipeDown
        case (4, true):  return dx > 0 ? .fourFingerSwipeRight  : .fourFingerSwipeLeft
        case (4, false): return dy > 0 ? .fourFingerSwipeUp     : .fourFingerSwipeDown
        default:         return nil
        }
    }
}
