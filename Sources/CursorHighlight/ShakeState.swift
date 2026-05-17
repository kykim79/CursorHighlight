import Foundation
import CoreGraphics

// MARK: - ShakeState
//
// 마우스 흔들기(SOS) 감지를 위한 순수 상태 + 알고리즘.
// `Date()` 대신 시간을 인자로 받아 테스트에서 시뮬레이션 가능하게 함.
//
// 감지 방식 — 각 축 독립 추적 + dedup:
//   - vx와 vy를 별도 카운터로 추적 (lastVx/lastVy, dirChangesX/dirChangesY)
//   - 각 축에서: |v| > 150 + 이전 |v| > 150 + 부호 반대일 때 방향 전환 카운트
//   - 0.5초 안에 한 축에서 방향 전환 3회 누적되면 detect 후보
//   - dedup: 직전 detect로부터 0.5초 안에는 다시 발화 X (같은 흔들기에서 두 축 동시 trigger 회피)
//
// 이전 dominant-axis 방식의 비대칭 문제 해결:
//   - 좌상↔우하 대각선처럼 vx와 vy 부호가 반대일 때 dominant axis가 toggle하면
//     부호 전환이 비일관 → 사용자가 흔들어도 detect 안 됨
//   - 좌하↔우상 대각선처럼 vx와 vy 부호가 같으면 두 축 모두 잡혀서 과도 trigger
//   - 각 축 독립 추적 + dedup으로 모든 방향에서 일관된 동작
struct ShakeState {
    struct PosRecord {
        let x: CGFloat
        let y: CGFloat
        let t: TimeInterval
    }

    /// 한 축(x 또는 y)의 진동 추적 상태. 별도 struct로 묶어 Swift exclusivity 우회.
    struct AxisState {
        var lastV: CGFloat = 0
        var dirChanges: Int = 0
        var lastChangeTime: TimeInterval = 0

        /// 새 속도를 기록. 3회 방향 전환 누적 시 true 반환.
        mutating func update(v: CGFloat, now: TimeInterval) -> Bool {
            var detected = false
            if abs(v) > ShakeState.velocityThreshold,
               abs(lastV) > ShakeState.velocityThreshold,
               v.signValue != lastV.signValue
            {
                if now - lastChangeTime < 0.5 { dirChanges += 1 } else { dirChanges = 1 }
                lastChangeTime = now
                if dirChanges >= 3 {
                    detected = true
                }
            }
            if abs(v) > ShakeState.lastVThreshold { lastV = v }
            return detected
        }
    }

    var recent: [PosRecord] = []
    var axisX = AxisState()
    var axisY = AxisState()
    var lastDetectionTime: TimeInterval = -1  // dedup용 (-1 = 아직 detect 없음)

    fileprivate static let velocityThreshold: CGFloat = 150  // 손목 흔들기 (60Hz 기준 5pt/sample = 167pt/s) 커버
    fileprivate static let lastVThreshold: CGFloat = 50      // lastV 업데이트 임계 (잡음 무시)
    fileprivate static let dedupWindow: TimeInterval = 0.5   // detect 후 다음 detect까지 최소 간격

    /// 새 좌표·시각을 기록하고 흔들기 감지 여부를 반환.
    /// 감지 시 두 축 모두 카운터 리셋 + dedup 타임스탬프 갱신.
    mutating func record(x: CGFloat, y: CGFloat, at now: TimeInterval) -> Bool {
        recent.append(PosRecord(x: x, y: y, t: now))
        while let first = recent.first, now - first.t >= 0.5 {
            recent.removeFirst()
        }
        guard recent.count >= 2 else { return false }

        let prev = recent[recent.count - 2]
        let curr = recent[recent.count - 1]
        let dt = curr.t - prev.t
        guard dt > 0.001 else { return false }

        let vx = (curr.x - prev.x) / dt
        let vy = (curr.y - prev.y) / dt

        // 각 축 독립 detect — 한 축이라도 3회 방향 전환이면 후보
        let xDetected = axisX.update(v: vx, now: now)
        let yDetected = axisY.update(v: vy, now: now)

        guard xDetected || yDetected else { return false }

        // dedup — 직전 detect 후 0.5초 안엔 무시 (같은 흔들기에서 두 축이 동시 trigger되는 케이스)
        if lastDetectionTime >= 0, now - lastDetectionTime < Self.dedupWindow {
            return false
        }
        lastDetectionTime = now
        // 다음 흔들기는 처음부터 누적해야 함 → 두 축 모두 카운터 리셋
        axisX.dirChanges = 0
        axisY.dirChanges = 0
        return true
    }
}

private extension FloatingPoint {
    /// 0 또는 양수면 +1, 음수면 -1 (Swift 표준 .sign과 다른 의미라 별도 이름)
    var signValue: Int { self >= 0 ? 1 : -1 }
}
