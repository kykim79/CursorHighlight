import SwiftUI

// MARK: - DesignTokens
//
// DESIGN.md의 토큰을 Swift 상수로 노출한다. UI에서 색·opacity·spacing·corner radius·motion·radial 거리를
// 하드코딩하지 말 것 — 시스템 일관성이 깨진다. 새 값이 필요하면 DESIGN.md에 토큰 먼저 추가하고 여기 반영.
//
// ringColor는 사용자가 PreferencesView에서 고르는 값이라 토큰화하지 않는다.
// 효과 view들은 `effectiveColor`를 inject받아 사용. (DESIGN.md "Color Rule — Active vs Passive")
enum Tokens {

    // MARK: Surface — 오버레이/패널 배경 (모두 검정 기반 반투명)

    enum Surface {
        /// 스포트라이트 dim 영역
        static let dim = Color.black.opacity(0.78)
        /// radial menu wedge 비활성 배경, 키스트로크 알림 배경 등 일반 panel
        static let panel = Color.black.opacity(0.72)
        /// radial menu 중앙 컨텍스트 capsule / wedge 외 약한 veil
        static let veil = Color.black.opacity(0.55)
        /// 서브 wedge 비활성 배경 (메인보다 한 단계 더 진함 — 레이어 위계)
        static let subtle = Color.black.opacity(0.65)
        /// 메인 wedge 비활성 배경 (메뉴 안 카드)
        static let mainIdle = Color.black.opacity(0.55)
    }

    // MARK: Stroke — 윤곽선/가이드

    enum Stroke {
        /// 비활성 wedge/arc 가이드선 — 존재만 알린다
        static let guideStrong = Color.white.opacity(0.30)
        static let guideMedium = Color.white.opacity(0.18)
        static let guideWeak   = Color.white.opacity(0.12)
        /// radial menu 동안 cursor 위치 표시 ring
        static let cursor      = Color.white.opacity(0.70)
        /// 텍스트 — 활성/비활성
        static let textActive  = Color.white.opacity(0.95)
        static let textMuted   = Color.white.opacity(0.60)
    }

    // MARK: Motion — DESIGN.md 모션 토큰의 Swift Animation 매핑

    enum Motion {
        // Spring (물리 이벤트)
        /// 클릭 펄스 ring 축소
        static let snap     = Animation.spring(response: 0.10, dampingFraction: 0.40)
        /// snap-back (드래그 종료 ring expand 직전)
        static let bounce   = Animation.spring(response: 0.15, dampingFraction: 0.60)
        /// 클릭/snap-back 복귀
        static let returnTo = Animation.spring(response: 0.50, dampingFraction: 0.45)
        /// 드래그 시작 — ring 살짝 적응
        static let drag     = Animation.spring(response: 0.25, dampingFraction: 0.70)
        /// 드래그 종료 ring 복귀
        static let dragEnd  = Animation.spring(response: 0.45, dampingFraction: 0.55)
        /// radial 메뉴 wedge select / ringSize 즉시 반영
        static let select   = Animation.spring(response: 0.18, dampingFraction: 0.75)
        /// 일반 spring (legacy 0.3/0.7 호출부)
        static let shrink   = Animation.spring(response: 0.30, dampingFraction: 0.70)

        // Ease (페이드/상태 전이)
        /// radial menu marking-mode reveal
        static let easeMicro  = Animation.easeOut(duration: 0.12)
        /// arc 활성 강조 전환, 중앙 컨텍스트 변경
        static let easeShort  = Animation.easeOut(duration: 0.15)
        /// anchored line·키스트로크 페이드, dragVelocity 복귀
        static let easeMedium = Animation.easeOut(duration: 0.30)
        /// 스포트라이트·돋보기 ON/OFF 토글 (이 앱의 모션 상한)
        static let easeLong   = Animation.easeInOut(duration: 0.35)

        // Pure values — withAnimation 외 stateful onAppear에서 직접 duration이 필요할 때
        static let easeMicroDuration: Double = 0.12
        static let easeShortDuration: Double = 0.15
        static let easeMediumDuration: Double = 0.30
        static let easeLongDuration: Double = 0.35
    }

    // MARK: Radial — radial menu 거리 스케일

    enum Radial {
        /// dead zone — 안쪽이면 nil (cancel)
        static let deadRadius: CGFloat = 50
        /// 메인 영역 바깥 경계 — 여기까지 sector 자유 회전
        static let mainOuter: CGFloat = 150
        /// 서브 영역 바깥 경계 — sector lock 활성
        static let subOuter: CGFloat = 230
        /// 떼었을 때 이 이상 끌어야 액션 발화 (오발 방지)
        static let releaseSafety: CGFloat = 80
        /// 화면 가장자리에서 중심까지 최소 거리 (메뉴 잘림 방지)
        static let edgeClamp: CGFloat = 240
        /// 캔버스 전체 크기 (subOuter*2 + padding)
        static var canvasSize: CGFloat { subOuter * 2 + 40 }
    }

    // MARK: Radius — corner radius 스케일

    enum Radius {
        /// inline pill (드래그 각도/거리)
        static let sm: CGFloat = 4
        /// 작은 panel (인스펙터)
        static let md: CGFloat = 8
        /// 키스트로크 / 카드 (Capsule 대체)
        static let lg: CGFloat = 12
        /// 키스트로크 큰 카드 (현 기본값)
        static let xl: CGFloat = 16
    }

    // MARK: Spacing — base unit 4pt

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Text — 시스템 폰트 역할별 토큰

    enum Text {
        /// radial menu 메인 sector 라벨용 큰 icon glyph
        static let icon       = Font.system(size: 28)
        /// 중앙 컨텍스트 icon (sector 활성 시)
        static let iconCenter = Font.system(size: 22)
        /// radial menu 메인 라벨, 키스트로크 메인
        static let label      = Font.system(size: 13, weight: .semibold)
        /// 중앙 컨텍스트 sector 라벨
        static let labelTiny  = Font.system(size: 9, weight: .semibold)
        /// radial menu sub item, 중앙 컨텍스트 현재값
        static let caption    = Font.system(size: 11, weight: .medium)
        /// radial menu 메인 wedge 안 라벨 (icon 아래)
        static let captionSmall = Font.system(size: 10, weight: .semibold)
        /// 헬프 텍스트
        static let hint       = Font.system(size: 10, weight: .medium)
        /// 인스펙터 좌표
        static let mono       = Font.system(size: 11, weight: .semibold, design: .monospaced)
    }
}
