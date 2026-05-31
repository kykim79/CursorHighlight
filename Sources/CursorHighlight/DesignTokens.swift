import SwiftUI
import AppKit

extension Color {
    /// WCAG 휘도 기준 — 밝은 색이면 검정 텍스트가 더 잘 보임.
    /// L = 0.299R + 0.587G + 0.114B (sRGB linear approx). > 0.6 = 밝은 색.
    /// 뱃지 숫자, toolbar 색 단축키 hint 등 색 위에 텍스트 얹는 모든 곳에서 사용.
    var needsDarkText: Bool {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        let l = 0.299 * ns.redComponent + 0.587 * ns.greenComponent + 0.114 * ns.blueComponent
        return l > 0.6
    }
}

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
        /// 좌클릭 hold로 라디얼 메뉴 열리는 시간 임계 — 일반 클릭과 구분되는 최소 시간
        static let longPressDuration: TimeInterval = 0.5
        /// hold 중 허용되는 cursor 이동 거리 — 초과 시 드래그로 간주, long-press cancel
        static let longPressDeadband: CGFloat = 5
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

    // MARK: Drawing — ⌃⌥D 그리기 도형 (펜·직선·화살표)

    enum Drawing {
        /// 기본 stroke 두께 — 발표 시 시청자 가시성 + 너무 굵지 않은 균형. [/] 키 조절 baseline.
        static let lineWidth: CGFloat = 4
        /// 두께 조절 단계 — [ ] 키로 순환. 5단계로 충분.
        static let lineWidthSteps: [CGFloat] = [2, 4, 6, 10, 14]
        /// 화살표 머리(arrowhead) 양 변 길이
        static let arrowHeadLength: CGFloat = 16
        /// 화살표 머리 양 변이 shaft에서 벌어지는 각도 (라디안). 30° = 일반적인 가독성 균형
        static let arrowHeadAngle: CGFloat = .pi / 6
        /// 형광펜 stroke 두께 — 영역 강조용. 일반 stroke의 6~7배.
        static let highlighterWidth: CGFloat = 25
        /// 형광펜 alpha — 본문이 비치는 투명도. accent color * 0.35.
        static let highlighterOpacity: Double = 0.35
        /// 번호 뱃지 원 반지름 (직경 32pt).
        static let badgeRadius: CGFloat = 16
        /// 번호 뱃지 외곽선 두께
        static let badgeBorderWidth: CGFloat = 2
        /// 번호 뱃지 텍스트 크기
        static let badgeFontSize: CGFloat = 14

        // MARK: Toolbar — 그리기 모드 좌측 하단 도구바 (v0.7.0)
        enum Toolbar {
            /// 외곽 padding (좌우/상하)
            static let padding: CGFloat = 16
            /// 모서리 radius
            static let cornerRadius: CGFloat = 14
            /// Divider 두께 / opacity
            static let dividerHeight: CGFloat = 48
            static let dividerOpacity: Double = 0.2
            /// 외곽 border opacity
            static let borderOpacity: Double = 0.18
            /// 도구 icon 원 지름 + glyph 크기 (primary visual weight)
            static let toolCircle: CGFloat = 36
            static let toolGlyph: CGFloat = 17
            /// 도구 라벨 / modifier hint 크기
            static let toolLabelSize: CGFloat = 12
            static let toolModifierSize: CGFloat = 10
            /// 두께/색 섹션 라벨 크기 (secondary)
            static let sectionLabelSize: CGFloat = 11
            static let sectionHintSize: CGFloat = 9
            /// Cheat sheet 크기 (tertiary)
            static let cheatSize: CGFloat = 9
            /// 색 dot 지름 + 클릭 영역 (둘 다 짝수 → selection ring 중심선 픽셀 정렬)
            static let colorDot: CGFloat = 16
            static let colorHitArea: CGFloat = 24
            /// 두께 dot 클릭 영역 (실제 dot 크기는 width 비례 4~12pt)
            static let thicknessHitArea: CGFloat = 24
            /// Drag handle dot 크기 / 간격
            static let dragHandleDot: CGFloat = 3
            static let dragHandleDotSpacing: CGFloat = 4
            /// 반응형 임계 — screen 너비 미만이면 cheat sheet 숨김
            static let cheatSheetHideBelow: CGFloat = 1200
            /// 첫 N회 drawing mode 켤 때 onboarding capsule 표시 (B redesign 후 정보량 늘어 5회)
            static let onboardingShowCount: Int = 5
            /// Onboarding capsule 표시 지속 시간 (초). 정보량 늘어 6초.
            static let onboardingDuration: TimeInterval = 6.0
            /// 선택 표시 ring 두께 — 도구/색/두께 모두 통일 (modern consistency).
            static let selectionRingWidth: CGFloat = 2.0
            /// 도구 그룹과 두께/색 그룹 사이 간격 — divider 대신 spacing으로 group 분리 (Sketch/Figma 패턴).
            static let groupSpacing: CGFloat = 18
        }
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
