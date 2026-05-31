# Design System — CursorHighlight

화면 위에서 커서를 강조하는 macOS 오버레이의 시각·모션 토큰. 모든 UI 효과(링·클릭·드래그·스포트라이트·돋보기·radial menu·키스트로크·드래그 각도/거리·인스펙터)는 이 문서의 토큰을 따른다. 토큰 외 값을 하드코딩하지 말 것 — 시각 일관성을 깨뜨린다.

## Product Context
- **What this is:** 화면 위 커서 위치를 시각적으로 강조하는 macOS 메뉴바 전용 오버레이 앱(LSUIElement).
- **Who it's for:** 화면 녹화·발표·페어 프로그래밍·스크린캐스트 제작자. 시청자가 "지금 어디 보고 있어야 하는지" 한 번에 알게 해주는 게 본질.
- **Space:** Cursorcerer, Mousecape, Highlightr 류의 cursor highlight 카테고리. 대부분 단순 노란 원으로 끝남.
- **Project type:** macOS 시스템 유틸리티 / 오버레이.

## 기억해야 할 한 가지 (Memorable Thing)

> **"잃어버릴 수 없는 커서, 흩어지지 않는 강조."**

모든 효과는 이 한 줄을 위해 존재한다 — 발표자가 "여기" 가리키면 시청자가 "거기"를 본다. 효과는 **이벤트를 구두점처럼 찍어주는 역할**이며, 산만하면 본질이 깨진다. 화려한 것보다 **확신 있는 한 박자**가 핵심.

## Aesthetic Direction
- **Direction:** Confident Highlighter — 무대 조명처럼 단호하게 비춘다. 장식 X, 트랜지션 짧고 명료.
- **Decoration level:** minimal — 그라데이션·블러 장식 금지. 강조는 색의 채도와 명료한 모션으로만.
- **Mood:** 도구처럼 단정 · 인터랙션 순간엔 확실한 피드백 · 그 외엔 시각적으로 거의 없는 듯.
- **Anti-pattern:**
  - 보라색 그라데이션·rainbow shimmer·sparkle particle 금지
  - 효과가 1초 넘게 머무르면 안 됨 (radial menu·anchored line·spotlight·magnifier 제외 — 사용자 호출형)
  - 동시 표시 효과 3개 초과 금지 (시각 혼잡)

## Color

### Ring Palette (사용자 선택)
링 색상은 7종 + custom. 모두 채도 높고 어두운 배경(스포트라이트 0.78 알파)에서도 살아남는다.

| Token | Hex / RGB | Swift |
|---|---|---|
| `ring.yellow` | `Color.yellow` | `.yellow` |
| `ring.red` | `(1.0, 0.3, 0.3)` | `Color(red: 1, green: 0.3, blue: 0.3)` |
| `ring.blue` | `(0.3, 0.6, 1.0)` | `Color(red: 0.3, green: 0.6, blue: 1)` |
| `ring.green` | `(0.3, 1.0, 0.5)` | `Color(red: 0.3, green: 1, blue: 0.5)` |
| `ring.white` | `Color.white` | `.white` |
| `ring.cyan` | `(0.0, 0.9, 1.0)` | `Color(red: 0, green: 0.9, blue: 1)` |
| `ring.purple` | `(0.8, 0.3, 1.0)` | `Color(red: 0.8, green: 0.3, blue: 1)` |
| `ring.custom` | 사용자 정의 | `settings.customRingColor` |

**Color Rule — Active vs Passive:**
- **Active/Intentional 효과** (드래그 glow, 더블 클릭, radial menu accent, idle pulse, magnifier border, trail, anchored line) → **ringColor follow**. 사용자가 색을 정하면 의도적 효과는 모두 그 색.
- **Passive/Frequent 효과** (좌클릭 single ripple) → 흰색(neutral). 가장 빈번한 액션이므로 ringColor와 시각적으로 경쟁하면 안 된다.
- **Semantic 효과** (우클릭 ripple) → 오렌지 기본. 사용자가 `rightClickUsesRingColor` ON 시 ringColor로 전환.

효과 추가 시 이 분류부터 결정. "이 효과는 사용자 의도의 강조인가, 백그라운드 피드백인가?"

### Surface (오버레이 배경)
| Token | Value | 용도 |
|---|---|---|
| `surface.dim` | `Color.black.opacity(0.78)` | 스포트라이트 dim 영역 |
| `surface.veil` | `Color.black.opacity(0.55)` | radial menu 중앙 컨텍스트 capsule 배경 |
| `surface.subtle` | `Color.black.opacity(0.40)` | radial menu wedge 비활성 배경 |
| `surface.glass` | `.regularMaterial` | 키스트로크 알림 배경 (NSVisualEffectView 사용) |

### Sub Wedge State (radial menu)
사용자 의도(hover)와 현재 상태(active)를 같은 채널(바탕색 fill)로 표현 — 텍스트 weight/opacity는 위계가 약하고 hover와 분리됨.

| State | Fill | 의미 |
|---|---|---|
| `sub.hover` | `accentColor.opacity(0.90)` | 지금 떼면 실행 — 사용자 의도 |
| `sub.current` | `accentColor.opacity(0.40)` | 현재 설정값 / 활성 토글 |
| `sub.inactive` | `Tokens.Surface.subtle` (0.65 black) | 기본 |

**Rule:** 텍스트는 일관 `.semibold + 흰색`. 상태는 바탕색만 변경. hover가 current보다 우선 (둘 다 해당하면 hover fill 적용).

### Outline / Stroke
| Token | Value | 용도 |
|---|---|---|
| `stroke.guide` | `Color.white.opacity(0.30)` | 비활성 wedge/arc 윤곽선 — 존재만 알린다 |
| `stroke.cursor` | `Color.white.opacity(0.70)` | radial menu 중 커서 위치 ring (14pt) |
| `stroke.accent` | `accentColor.opacity(0.95)` | 활성 sector·선택된 sub item — accentColor는 현재 ringColor |
| `stroke.highlight` | `Color.white.opacity(0.85)` | 활성 sub item 텍스트 |
| `stroke.muted` | `Color.white.opacity(0.55)` | 비활성 sub item 텍스트 |

## Typography

macOS 시스템 폰트(SF Pro Text/Display)만 사용 — 외부 폰트 금지. 모든 텍스트는 오버레이 위에서 1초 미만으로 표시되므로 가독성이 절대적.

| Token | Swift | 용도 |
|---|---|---|
| `text.label` | `.system(size: 13, weight: .semibold)` | radial menu 메인 라벨, 키스트로크 |
| `text.body` | `.system(size: 12, weight: .medium)` | 중앙 컨텍스트, 인스펙터 좌표 |
| `text.caption` | `.system(size: 11, weight: .medium)` | radial sub item 라벨 |
| `text.hint` | `.system(size: 10, weight: .medium)` | radial menu help line |
| `text.mono` | `.system(size: 12, weight: .medium, design: .monospaced)` | 드래그 각도/거리/속도 — 숫자가 떨림 없이 갱신돼야 함 |

**Rule:** 숫자 표시는 무조건 `.monospacedDigit()` 또는 `design: .monospaced`. 60Hz로 갱신되는 좌표·각도·거리에서 글자가 흔들리면 산만함.

## Spacing

base unit 4pt — macOS HIG와 정렬.

| Token | Value |
|---|---|
| `space.xs` | 4 |
| `space.sm` | 8 |
| `space.md` | 12 |
| `space.lg` | 16 |
| `space.xl` | 24 |
| `space.2xl` | 32 |

### Radial Menu 전용 거리
radial menu는 거리(distance)로 의도를 표현하는 컴포넌트라 별도 스케일 사용.

| Token | Value | 의미 |
|---|---|---|
| `radial.deadRadius` | 50 | dead zone — 안쪽이면 nil (cancel) |
| `radial.mainOuter` | 150 | 메인 영역 바깥 경계 — 여기까지가 sector 자유 회전 |
| `radial.subOuter` | 230 | 서브 영역 바깥 경계 — sector lock 활성 |
| `radial.releaseSafety` | 80 | 떼었을 때 이 이상 끌어야 액션 발화 (오발 방지) |
| `radial.edgeClamp` | 240 | 화면 가장자리에서 중심까지 최소 거리 |

## Layout

- **Cursor ring (Active):** `frame(width: ringSize, height: ringSize)`, `stroke.accent` lineWidth는 ringSize에 비례 (보통 ringSize × 0.06)
- **Cursor ring (radial menu hover):** `14pt`, `stroke.cursor`, lineWidth 1.5
- **Radial wedge:** PieWedge donut shape, inner=`deadRadius`, outer=`mainOuter`
- **Radial arc (가이드):** outer edge에 1.5pt stroke (비활성) / 3.0pt stroke (활성)
- **Sub item:** wedge 끝단 너머 80pt offset, 텍스트만 (배경 없음)
- **Keystroke overlay:** 화면 하단 중앙, `.regularMaterial` 배경, cornerRadius 12, padding 16
- **Inspector label:** 커서 우측 12pt offset, `.regularMaterial`, cornerRadius 6, padding 6×8

### Corner Radius
| Token | Value | 용도 |
|---|---|---|
| `radius.sm` | 4 | inline pill (드래그 각도/거리 capsule) |
| `radius.md` | 8 | 작은 panel (인스펙터) |
| `radius.lg` | 12 | 키스트로크·중앙 컨텍스트 (Capsule 사용 시 fully rounded) |

## Drawing (⌃⌥D, v0.6.0)

발표·스크린캐스트용 화면 annotation. ⌃⌥D 토글로 모드 ON, 마우스 드래그로 stroke. 모디파이어로 도구 결정 (drag start 시점, Sketch/Figma 컨벤션 차용).

### 도구 (7종, v0.7.0 확장)

| 도구 | 활성화 | shape data |
|---|---|---|
| 펜 | 드래그 (모디파이어 없음) | 모든 샘플 점 line join |
| 직선 | Shift+드래그 | [start, end] 두 점 |
| 화살표 | Opt+드래그 | [start, end] + ±30° head |
| 사각형 | **Cmd+드래그** | [start, end] outline rect |
| 타원 | **Cmd+Shift+드래그** | [start, end] outline ellipse |
| 형광펜 | **Cmd+Opt+드래그** | pen path × 25pt × opacity 0.35 |
| 번호 뱃지 | **Shift+Opt+클릭** | [point] + 자동 번호 (1,2,3...) |

**모디파이어 우선순위:** Shift+Opt = badge > Cmd+Opt = highlighter > Cmd+Shift = ellipse > Cmd = rectangle > Opt = arrow > Shift = line > 그 외 = pen.

### 토큰 (`Tokens.Drawing`)

| Token | Value | 의미 |
|---|---|---|
| `lineWidth` | 4pt | 기본 stroke 두께 — `[` `]` 키 조절 baseline |
| `lineWidthSteps` | [2, 4, 6, 10, 14] | `[` / `]` 두께 단계 (모드 활성 중) |
| `arrowHeadLength` | 16pt | 화살촉 양 변 길이 |
| `arrowHeadAngle` | π/6 (30°) | 화살촉 양 변 벌어짐 |
| `highlighterWidth` | 25pt | 형광펜 굵기 (일반 stroke의 6~7배) |
| `highlighterOpacity` | 0.35 | 형광펜 alpha — 본문 비치는 정도 |
| `badgeRadius` | 16pt | 번호 뱃지 원 반지름 (직경 32pt) |
| `badgeBorderWidth` | 2pt | 뱃지 외곽선 두께 (흰색 0.85) |
| `badgeFontSize` | 14pt | 뱃지 숫자 (`.bold`, 흰색) |

### 색

stroke 색은 `CursorSettings.effectiveRingColor` (사용자 선택 ringColor) — startShape 시점에 캡처. 사용자가 stroke 도중 색 바꿔도 진행 중 도형은 원래 색 유지 (DESIGN.md "Active = ringColor follow" 일관성).

### Cursor 인디케이터

그리기 모드 활성 시 cursor 옆에 `Image(systemName: "plus")` (size 14pt, weight .semibold, opacity 0.85, drop shadow). 사용자가 "지금 그리기 모드"임을 인지.

### Toolbar (좌측 하단 floating pill, v0.7.0)

그리기 모드 활성 중 cursor가 있는 screen의 좌측 하단에 vibrancy material (`.regularMaterial` + force dark) pill로 표시. 도구 7종 + 두께 + 색 + cheat sheet 통합 컨트롤.

**구조 (좌→우):**
1. Drag handle (2x2 dot grip) — 클릭+드래그로 toolbar 위치 이동 (persist)
2. 도구 7종 — modifier-driven preview + sticky 선택 (Sketch 패턴)
3. 두께 5단계 — 클릭 / 키보드 `[ / ]`
4. 색 7가지 — 클릭 / 키보드 ⌃⌥1~7 + ⌃⌥C 순환
5. Cheat sheet — `[ / ] 두께 · ⌃⌥1~7 색 · ⌃⌥C 순환 · ⌘Z 되돌리기 · ESC 닫기` (좁은 화면에선 숨김)

**Tokens (`Tokens.Drawing.Toolbar`):**

| Token | Value | 의미 |
|---|---|---|
| `padding` | 16pt | 외곽 padding |
| `cornerRadius` | 14pt | 모서리 |
| `dividerHeight` | 48pt · opacity 0.2 | 섹션 구분선 |
| `toolCircle` | 36pt · glyph 17pt | 도구 icon 원/SF Symbol (primary visual weight) |
| `colorDot` / `colorHitArea` | 16pt / 24pt | 색 dot / 클릭 영역 (짝수 → 중심선 픽셀 정렬) |
| `thicknessHitArea` | 24pt | 두께 dot 클릭 영역 (실제 dot은 두께 비례 4~12pt) |
| `dragHandleDot` / `Spacing` | 3pt / 4pt | 2x2 grip dot |
| `selectionRingWidth` | 2pt | active 도구·두께·색 외곽 ring 두께 |
| `cheatSheetHideBelow` | 1200pt | 반응형 임계 — screen 너비 미만이면 cheat sheet 숨김 |
| `onboardingShowCount` / `Duration` | 5회 / 6초 | First-time hint capsule |

**상태 표시 (도구) — Selection vs 색 채널 분리 (v0.7.0):**

| State | Visual | 의미 |
|---|---|---|
| Preview (active) | `white.opacity(0.18)` fill + `ringColor` 2pt 외곽 ring | 지금 드래그 시작하면 그려질 도구 (modifier 기반) |
| Sticky-only (selected ≠ active) | `white.opacity(0.08)` fill + `ringColor.opacity(0.45)` 1pt 옅은 ring | 모디파이어 떼면 복귀할 sticky 도구 |
| 비선택 | `white.opacity(0.08)` fill, ring 없음 | 클릭 가능 area 인지 위한 약한 fill만 |
| Glyph | 항상 `white` (ringColor 무관 고정) | luminance contrast 계산 불필요 |

**원칙:** 색은 외곽 ring(작은 면적)에만 적용. 배경·glyph는 ringColor 무관 고정 → 어떤 색을 골라도 도구 식별성·selection 명확성 동일 유지. ringColor가 흰색일 때 vibrancy material 위 흰 2pt ring + 0.18 fill 충분히 contrast.

**상태 표시 (두께):**
- dot fill: 비선택 `white.opacity(0.30)`, 선택 `white.opacity(0.85)` (grayscale 고정 — 두께 시각화 전용)
- 선택 시 외곽 `ringColor` 2pt ring (selection 표시 = 색 채널)

**상태 표시 (색·a11y):**

색 dot 7개에 단축키 번호 (1~7) overlay — 색맹 사용자가 색만으로 구분 못 해도 숫자로 식별 가능. 텍스트 색은 `Color.needsDarkText` (WCAG luminance `L = 0.299R + 0.587G + 0.114B > 0.6`) 기준: 밝은 dot(yellow/cyan/white)은 검정, 어두운 dot은 흰색.

**상태 표시 (선택 — 색 dot):**
- 선택된 색 dot: 외곽 2pt ring. `needsDarkText` 분기 — 밝은 dot에선 검정 ring, 어두운 dot에선 흰색 ring (vibrancy material 위 union 회피)

**Position:**
- 기본: 좌측 하단 (`drawingToolbarLeading: 28pt`, `Bottom: 110pt`)
- Persist via `@Persisted` settings — 사용자가 drag handle로 이동 시 저장
- Clamp: 측정한 `toolbarSize` 기준 `screen.width - tbWidth - 8pt margin` (화면 밖 방지)

**Multi-monitor:**
- Cursor가 있는 screen에만 표시 (`screenFrame.contains(runtime.cursorPosition)`)
- 좌표 hit-test도 그 screen 기준 → 단일 source

**Onboarding:**
- 첫 5회 그리기 모드 ON 시 toolbar 위 capsule "드래그=펜 · 모디파이어로 도구 변경 · 도구바 클릭으로 직접 선택" 6초 fade
- UserDefaults `drawingHelpShownCount` counter
- 6초 후 자동 fade out

### 키보드 단축키 (모드 활성 중)

| 키 | 동작 |
|---|---|
| `Cmd+Z` | 마지막 도형 1개 제거 (badge면 counter도 감소) |
| `[` | 두께 한 단계 ↓ (clamp at 2) |
| `]` | 두께 한 단계 ↑ (clamp at 14) |
| `ESC` | 전체 clear + 모드 OFF + counter/두께 reset |

### 라이프사이클

- ⌃⌥D 토글 OFF: 도형 유지 (발표 중 그리고 → 끄고 마우스 작업 → 다시 켜서 추가 패턴)
- ESC: 모든 도형 clear + 모드 OFF + `badgeCounter` 1 / `lineWidth` 4 reset (clean slate)
- 진행 중 stroke (drag 중 토글 OFF) → 폐기

### Rule

- 새 도형 종류 추가 시 색은 `effectiveRingColor` 통과 필수
- 두께/화살촉 변경 시 `Tokens.Drawing.*`만 수정 (call site 분산 금지)
- 그리기는 **Active 효과** — Passive(좌클릭 ripple .white) 규칙 적용 안 됨

## Motion

이 앱의 모션은 **이벤트 구두점**. spring은 클릭/드래그 같은 "물리적 사건"에, easeOut은 페이드/등장/소멸에 쓴다.

### Spring (물리적 피드백)
| Token | Swift | 용도 |
|---|---|---|
| `spring.snap` | `.spring(response: 0.1, dampingFraction: 0.4)` | 클릭 펄스 ring 축소 |
| `spring.bounce` | `.spring(response: 0.15, dampingFraction: 0.6)` | snap-back (드래그 종료 ring expand) |
| `spring.return` | `.spring(response: 0.5, dampingFraction: 0.45)` | 클릭/snap-back 복귀 |
| `spring.drag` | `.spring(response: 0.25, dampingFraction: 0.7)` | 드래그 시작 ring 적응 |
| `spring.dragEnd` | `.spring(response: 0.45, dampingFraction: 0.55)` | 드래그 종료 ring 복귀 |
| `spring.shrink` | `.spring(response: 0.3, dampingFraction: 0.7)` | radial 메뉴 ringSize 즉시 반영 |

### Ease (페이드/등장/숨김)
| Token | Swift | 용도 |
|---|---|---|
| `ease.micro` | `.easeOut(duration: 0.12)` | radial menu 등장 (marking mode 후) |
| `ease.short` | `.easeOut(duration: 0.15)` | arc 활성 강조 전환 |
| `ease.medium` | `.easeOut(duration: 0.3)` | anchored line·키스트로크 페이드, dragVelocity 복귀 |
| `ease.long` | `.easeInOut(duration: 0.35)` | 스포트라이트·돋보기 ON/OFF 토글 |

### Rule
- **모션은 한 번에 하나만 강조**: 동시에 spring 두 개 이상 동작하면 정리 필요
- **0.5초 초과 금지** — `ease.long`이 상한선. 더 길면 사용자 의도와 어긋남
- **반복 모션 금지** — idle pulse 제외. 깜박이는 효과는 추가하지 말 것

## Iconography

**Rule (v0.6.0 갱신):** UI 영구 표시 영역(Radial menu, PreferencesView)은 **SF Symbols 전용**. emoji는 transient 텍스트(키스트로크 알림)에만. SF Symbols는 일관 선화 두께·macOS HIG 정렬·다크모드 자동 대응.

### Radial Menu 메인 sector (8종 — SF Symbol)

| Sector | SF Symbol | 의미 |
|---|---|---|
| 0 (12시) | `flashlight.on.fill` | Spotlight |
| 1 (1:30) | `plus.magnifyingglass` | Magnifier |
| 2 (3시) | `sparkles` | Effects (효과 묶음) |
| 3 (4:30) | `circle.dashed` | Ring size |
| 4 (6시) | `paintpalette.fill` | Color |
| 5 (7:30) | `square.on.circle` | Ring shape |
| 6 (9시) | `ruler.fill` | 좌표/각도 묶음 |
| 7 (10:30) | `keyboard.fill` | Keystroke |

### Radial Menu sub items (카테고리형만 — 값 선택형은 텍스트)

| Sector | Sub | SF Symbol |
|---|---|---|
| 효과 | 글로우 | `lightbulb.fill` |
| 효과 | 트레일 | `wind` |
| 효과 | 정지펄스 | `target` |
| 효과 | 코멧 | `sparkle` |
| 좌표/각도 | 좌표 | `viewfinder` |
| 좌표/각도 | 드래그각도 | `arrow.up.right` |

값 선택형 sub(반경/줌/색/시간/링크기/모양)는 icon=nil 텍스트 단독.

### 알림(Keystroke Overlay) — emoji 유지

알림은 1초 미만 transient text 오버레이. SF Symbol 인라인 합성보다 emoji가 한 단계 가벼움. 단, **알림 emoji와 radial menu icon은 같은 의미를 가리킴** (✏️ 그리기·🔦 스포트라이트 등).

## Notification Format

radial menu 등 사용자 액션의 알림은 단일 포맷:

```
[icon] [label] · [value-or-state]
```

예: `🔦 스포트라이트 · 켜짐`, `🔍 돋보기 · 2×`, `🎨 색상 · 파란색`

**Rule:** "·" (중점) 구분자 사용. 콜론·하이픈 X. value 없는 액션(인스펙터)은 `[icon] [label]`만.

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-05-30 | DESIGN.md 최초 작성 | radial menu 디자인 리뷰 deferred 작업. 클릭 ripple·드래그·radial accent가 ringColor 따라가게 통합 |
| 2026-05-30 | Spring vs ease 명확 분리 | Spring=물리 이벤트(클릭/드래그), ease=상태전이(페이드/토글). 혼용하면 모션이 일관되지 않음 |
| 2026-05-30 | 모든 강조 색은 ringColor follow | 사용자가 색을 정하면 시스템 전체가 그 색이어야 한다 — 효과별 색 분기 금지 |
| 2026-05-30 | 모션 상한 0.5초 | 발표 시 화면 위 효과가 1초 가까이 머물면 시청자 attention drift |
| 2026-05-31 | UI 영구 표시 영역 SF Symbols 전용 (v0.6.0) | radial menu emoji는 폰트별 렌더 차이·다크모드 부적합. SF Symbols는 macOS HIG 일관. 알림은 transient라 emoji 유지 |
| 2026-05-31 | 그리기 도구 모디파이어 매핑 (Shift=직선, Opt=화살표) | Sketch/Figma 컨벤션. 별도 도구 선택 UI 없이 즉시 전환 — 발표 중 thought interruption 최소화 |
| 2026-05-31 | 그리기 stroke 색 startShape 캡처 후 고정 | 진행 중 색 변경 따라가면 그라데이션 발생 — 의도 없는 시각 결과. 한 stroke = 한 색이 직관적 |
| 2026-05-31 | `effectiveRingColor` 단일 source (DRY) | 색 따르는 효과 3+곳(클릭·radial·그리기) 추가하며 logic 중복 위험. `CursorSettings.effectiveRingColor` 통과 의무화 |
| 2026-05-31 | 그리기 토큰화 (`Tokens.Drawing`) | DESIGN.md "토큰 외 하드코딩 금지" 정책 일관 적용. lineWidth/arrowHead 등 향후 조정 단일 지점 |
| 2026-05-31 | v0.7.0 그리기 도구 7종 확장 | 발표 시연 패턴 보강 — 사각형/타원(코드/UI 박스), 형광펜(영역 강조), 번호 뱃지(step 설명). 모디파이어 우선순위는 specific(combo) > general(single) |
| 2026-05-31 | 두께를 shape per-capture (lineWidth) | 두께 조절 후에도 이전 도형 영향 없음. 색 캡처 정책(2026-05-31)과 동일 패턴 |
| 2026-05-31 | Undo는 1 step만 (stack 없음) | 발표 중 직전 실수 정정이 주 용도. redo/multi-step undo는 과한 복잡도, 잘못되면 ESC clear |
| 2026-05-31 | 그리기 도구박스 영구 표시 (v0.7.0) | 모디파이어를 외워야만 도구 전환 가능했던 v0.6.0 문제 해소. 클릭 선택 + drag 위치 이동 + 단축키 hint = 입문자·고급자 양립. UI 한 곳에서 도구·두께·색 통합 |
| 2026-05-31 | 단축키 숫자 1~7 = 색 전용 예약 (⌃⌥C / ⌃⌥H로 cycle 이동) | 색이 늘어날 때마다 cycle 키를 옮기는 brittleness 제거. 숫자=색, 알파벳=cycle convention 확립. ⌃⌥0=색순환·⌃⌥7=모양순환 → ⌃⌥C(Color)·⌃⌥H(sHape)으로 마이그레이션, ⌃⌥7은 흰색에 할당 |
| 2026-05-31 | 도구박스 selection vs 색 채널 분리 (Option B) | 기존 `accent.opacity(0.9)` fill 배경 → 색이 큰 면적 차지하므로 ringColor 변경 시마다 glyph/ring luminance 매칭 필요. 색은 외곽 ring(작은 면적)에만 두고 selection은 고정 `white.opacity(0.18)` surface tint로 표시 → ringColor 무관하게 가독성 안정. `needsDarkText` 분기 toolButton/thicknessButton에서 제거 (colorButton은 본질이 색 표시라 유지) |
| 2026-05-31 | `Color.needsDarkText` 헬퍼 (WCAG luminance) | yellow/cyan/white 위 흰 텍스트 invisible 패치를 위해 `L = 0.299R + 0.587G + 0.114B > 0.6` 단일 source. 도구박스 colorButton hint·DrawnShapeView badge 텍스트가 공유. 새 밝은 색 추가 시 분기 자동 적용 |
