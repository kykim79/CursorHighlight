# Changelog

[Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 형식 + [Semantic Versioning](https://semver.org/lang/ko/) 따름.

## [Unreleased]

## [0.6.0] — 2026-05-31

### Added

- **그리기 모드 (⌃⌥D)** — 발표·스크린캐스트용 화면 annotation. ⌃⌥D 토글로 모드 ON, 좌클릭 드래그로 그리기. 모드 OFF 시에도 도형은 유지 — 그린 후 모드 끄고 마우스로 발표 진행, 다시 켜서 추가 가능.
  - **도구 (모디파이어 기반):** 그냥 드래그 = 펜(free stroke) · Shift+드래그 = 직선 · Opt+드래그 = 화살표(끝에 ±30° arrowhead). Sketch/Figma 컨벤션.
  - **색:** 현재 ringColor follow (DESIGN.md Active = ringColor follow 일관성).
  - **ESC:** 모든 도형 clear + 모드 종료.
  - **시각 단서:** 모드 활성 시 cursor 옆 `+` 인디케이터.
  - 그리기 모드 활성 중 좌클릭 down·drag·up 모두 underlying app에 전달 안 함 (overlay 캡처 전용).
- **Radial menu SF Symbols 통일** — 메인 sector(🔦→`flashlight.on.fill` 등 8종)와 효과/좌표 sub(💡→`lightbulb.fill` 등 6종) 아이콘이 emoji → SF Symbol로 전환. 일관 선화 두께·macOS HIG 정렬. PreferencesView 탭은 이미 SF Symbols 사용 중. 알림(keystroke overlay) emoji는 transient text라 유지.

### Changed

- `RadialMenuItem.subLabels: [String]` → `subItems: [SubItem]` 구조로 변경. SubItem은 optional SF Symbol icon + label 조합. 값 선택형 sub(반경/줌/색/시간 등)는 icon=nil 텍스트만, 카테고리형 sub(효과·좌표/각도)는 icon 노출.
- `RadialMenuItem`에 `icon: String`(SF Symbol)과 `label: String` property 추가 — 메인 sector 단일 source.
- `MouseEventMonitor`에 `isDrawingModeActive` 플래그 + `onDrawingDrag`/`onDrawingRelease` 콜백 추가. 그리기 활성 중 leftMouseDragged·leftMouseUp을 그리기 콜백으로 라우팅 + underlying 차단.

## [0.5.11] — 2026-05-30

### Added

- **Radial Menu (⌃⌥,)** — 마우스 커서 위치에 8 sector ring 메뉴. 메뉴 활성 중 sub 클릭으로 여러 효과/설정을 연속 토글 가능. 닫기: ⌃⌥, 다시 / ESC / dead zone(✕) 클릭. 메뉴 영역(subOuter 230pt) 바깥에선 모든 강조 해제 — 실수 클릭 보호.
  - 8 sector: 🔦 스포트라이트 / 🔍 돋보기 / ✨ 효과 / 🔘 링크기 / 🎨 링색 / ⭕ 링모양 / 📐 좌표/각도 / ⌨ 키 입력
  - ✨ 효과 sub 4종 (글로우·트레일·정지펄스·코멧)
  - 📐 좌표/각도 sub 2종 (좌표 표시·드래그각도) — 위치/방향 라벨 카테고리로 묶음
  - 거리 토큰: dead 50 / mainOuter 150 / subOuter 230 / edgeClamp 240
  - 현재 active 상태를 **wedge 바탕색**으로 표시 (accent 40%) + 중앙 컨텍스트에 "n/m 켜짐" / 현재값 동시 노출
  - 화면 가장자리 clamp — cursor가 모서리 가까이여도 메뉴가 잘리지 않음
- **인스펙터 (⌃⌥I)** — cursor 옆에 시스템 좌표(Quartz top-left) 라벨. 디자인/개발 디버깅용. radial menu 📐 sub로도 접근.
- **드래그 거리 라벨** — 드래그 각도 라벨에 거리(pt) 동시 표시.
- **DESIGN.md + DesignTokens.swift** — 색/spacing/corner radius/모션/radial 거리/notification 포맷을 토큰화. RadialMenuView·SpotlightView·KeystrokeDisplayView·InspectorView가 하드코딩 대신 `Tokens.*` 참조. 새 효과 추가 시 일관성 baseline.

### Changed

- **MouseEventMonitor** `.listenOnly` → `.defaultTap`. 평소엔 통과시키되 radial menu 활성 중에만 좌클릭 소비 → underlying app으로 누수 방지.
- **드래그 컴맷 테일 → 드래그 코멧 테일** — 환경설정 라벨 오타 수정 + Localizable.xcstrings 동기화.

## [0.5.10] — 2026-05-30

### Fixed

- **v0.5.9 빌드 실패 fix → 통합 릴리스** — v0.5.9 커밋에서 레이저 포인터 코드 제거할 때 정지 펄스 트리거 조건의 `!runtime.isLaserPointerActive` 참조를 놓쳐 CI 컴파일이 실패해 v0.5.9 릴리스가 만들어지지 못했다(v0.5.2/v0.5.3와 동일 패턴). 그 참조 제거 + 같은 변경 사항(레이저 포인터 폐기)을 v0.5.10으로 통합 릴리스.

## [0.5.9] — 2026-05-30 *(빌드 실패로 미배포 — v0.5.10에서 통합)*

### Removed

- **레이저 포인터 기능 폐기** — v0.5.8에 추가한 레이저 포인터(오른쪽 ⌥ hold, 시스템 cursor를 빨간 점으로 전환)는 평소엔 깜빡임 없이 잘 동작하는 듯 보였으나, **클릭하면 active context가 다른 앱으로 옮겨가면서 cursor가 즉시 그 앱의 cursor로 덮여 빨간 점이 깜빡거리는** 본질적 한계가 확인됐다. `NSCursor.set` cross-app, `CGDisplayHideCursor`, hold 방식 어느 우회로도 macOS의 cross-app cursor 모델을 안정적으로 우회 불가 → 기능 자체 제거. 모양 cycle(⌃⌥7)·정지 펄스는 그대로 유지.

## [0.5.8] — 2026-05-30

### Added

- **링 모양 순환 단축키 (⌃⌥7)** — 누를 때마다 원형 → 둥근 사각형 → 마름모로 순환. 색 단축키(⌃⌥1~6, ⌃⌥0 cycle)와 같은 그룹.
- **정지 펄스** — 마우스가 1.5초 멈춰 있으면 현재 ring shape·색으로 1회 외곽 확장 fade. "여기 보세요" 자연스러운 강조 동작. 환경설정 → 동작 → "정지 시 펄스 강조"로 OFF 가능 (default ON).
- **레이저 포인터 (오른쪽 ⌥ hold)** — 오른쪽 Option 키를 단독으로 누르고 있는 동안 시스템 cursor가 빨간 점으로 바뀌고, 떼면 즉시 원래 cursor로 복귀. 발표·녹화 중 한 손으로 호출 가능, 다른 ⌃⌥ 단축키와 충돌 없음.
  - 구현: `NSCursor.set()` cross-app + 매 mouseMove 재 set + `didResignActiveNotification`에서 재 activate 조합으로, macOS 26.x에서 cursor 모양만 변경(visibility 토글 없음)이라 클릭 시 깜빡임도 없고 `flagsChanged` 이벤트 기반이라 auto-repeat 소리도 없음.

## [0.5.7] — 2026-05-29

### Fixed

- **낯선 모니터가 아닌데도 키스트로크가 계속 표시되던 버그** — 자동 키스트로크 상태(`autoKeystrokeActive`·`keystrokeStateBeforeAuto`)가 메모리 변수라, 앱 재시작 시 "우리가 자동으로 켰다"는 사실이 유실됐다. 그 결과 낯선 모니터로 자동 ON된 키스트로크가 재시작 후엔 모니터를 분리하거나 신뢰 등록해도 복원(꺼짐)되지 않고 `isKeystrokeEnabled`(영구 저장)가 ON으로 남았다. 두 상태를 `UserDefaults`에 persist해 재시작 후에도 올바르게 복원되도록 수정. 또 신뢰 모니터 등록·기능 토글 등 설정 변화를 구독해 `evaluateAutoKeystroke`를 즉시 재평가 — 같은 세션에서도 바로 반영된다.

## [0.5.6] — 2026-05-29

### Added

- **업데이트로 깨진 권한 자동 초기화** — ad-hoc 빌드는 업데이트마다 cdhash가 바뀌어 TCC 권한이 깨지는데(시스템 설정엔 체크돼 보이지만 실제로는 작동 안 함), 그동안 사용자가 권한을 직접 껐다 켜야 했다. 이제 **버전이 바뀐 실행에서 권한이 실제로 깨진(missing) 경우에만** 해당 권한의 TCC 엔트리를 `tccutil reset`으로 초기화하고 시스템 목록에 재등록한다 — 사용자는 시스템 설정에서 켜기만 하면 된다. 정상 유지된 권한과 신규 설치 첫 실행은 건드리지 않는다. (버전 기록은 이 버전부터 시작하므로 **v0.5.6 이후의 업데이트**부터 동작한다.)

### Internal

- `PermissionsManager.isUpdateLaunch(previous:current:)`·`resetTCCEntries(for:)`, `PermissionType.tccServiceName` 추가. 업데이트 감지는 `UserDefaults`의 `lastRunVersion` 비교. 권한 reset 시 `os.Logger`로 진단 로그 1줄. 순수 로직 단위 테스트 5개 추가(총 72개). PostEvent는 앱이 이벤트를 inject하지 않아 대상에서 제외.

## [0.5.5] — 2026-05-29

### Added

- **스포트라이트·돋보기가 ring shape를 따라감 (실제 구현)** — v0.5.3 CHANGELOG가 이 기능을 주장했지만, 실제 v0.5.3 커밋은 `CHANGELOG.md`·`project.yml`만 바꾼 빈 커밋이라 코드가 전혀 없었다(언급된 `SpotlightMask`·`MagnifierLensView` struct도 부재). 이번에 실제로 구현: 스포트라이트의 밝게 뚫리는 cutout과 돋보기 렌즈의 clip·외곽선이 선택한 ring shape(원형/둥근 사각형/마름모)를 따른다. gradient는 radial 유지(중심→가장자리 fade). `RingShape.anyShape`(v0.5.2 인프라) 재사용 — 원형은 기존과 동일 렌더.

## [0.5.4] — 2026-05-29

### Fixed

- **클릭 리플 효과 빌드 실패 수정 — v0.5.2·v0.5.3 미배포 복구** — v0.5.2에서 좌·우클릭·더블클릭·흔들기 효과 호출부에 `ringShape` 인자를 추가했으나 `ClickRippleView`·`LeftClickRippleView`·`RightClickRippleView`·`DoubleClickBurstView`·`ShakeEffectView`·`ExpandingRing` 정의에는 `ringShape` 프로퍼티가 빠져 컴파일이 실패했다. 이 때문에 v0.5.2·v0.5.3 릴리스 빌드가 CI에서 실패해 배포되지 못했다(공개 최신은 v0.5.1에 머묾). 누락된 정의를 채워 좌클릭(1중)·우클릭(2중+회전)·더블클릭(채움+외곽선)·흔들기(3중 확장)가 모두 선택한 ring shape를 따르도록 완성 — v0.5.2 CHANGELOG의 의도대로 동작.
- **Xcode 26.5 `ForEach` 타입 추론 회귀 대응** — 효과 배열을 도는 `ForEach`가 `Binding<C>` 오버로드로 잘못 해소돼 컴파일이 깨지던 문제를 `id: \.id` 명시로 해결(7곳). 구버전 Xcode와도 호환.

## [0.5.3] — 2026-05-29

### Changed

- **스포트라이트·돋보기도 ring shape를 따라감** — v0.5.2에서 클릭 효과를 ring shape에 맞췄는데, 스포트라이트 밝은 영역과 돋보기 렌즈는 여전히 원형 고정이었다. 이제 둘 다 선택한 ring shape(원형/둥근 사각형/마름모)와 같은 모양으로:
  - **스포트라이트** — 어두운 오버레이에서 밝게 뚫리는 영역이 ring shape를 따름 (마스크 cutout).
  - **돋보기** — 확대 렌즈 외형(clip + 외곽선)이 ring shape를 따름.

### Internal

- `SpotlightMask`·`SpotlightOverlayView`·`MagnifierLensView`에 `ringShape` 전달. cutout/clip을 `RingShape.anyShape.path(in:)`로 통일 — v0.5.2의 효과 shape 인프라 재사용. 원형은 기존과 동일 렌더.

## [0.5.2] — 2026-05-28

### Changed

- **클릭·효과가 ring shape를 따라감** — 기존엔 ring을 둥근 사각형·마름모로 바꿔도 클릭 파동·버스트·흔들기·휠클릭이 항상 원형(우클릭만 마름모)이라 안 어울렸다. 이제 모든 효과가 선택한 ring shape(원형/둥근 사각형/마름모)와 같은 모양으로:
  - **좌클릭** — ring shape 1중 파동 (흰색)
  - **우클릭** — ring shape 2중 파동 + 회전 (색·2중·회전으로 좌클릭과 차별)
  - **더블클릭** — ring shape 버스트 (채움 + 외곽선)
  - **휠클릭** — ring shape 2개가 반대 방향 회전하며 확장 (회전 의미 유지)
  - **흔들기 SOS** — ring shape 3중 확장
  - 스크롤 화살표·키스트로크·클립보드 이모지는 모양 무관이라 그대로.

### Internal

- `CursorSettings.RingShape.anyShape` (AnyShape) — 모든 효과가 재사용하는 type-erased shape. `SquircleShape` struct 분리 (cornerRadius = 28% 비율). 효과별 `Circle()`/`RhombusShape()` 하드코딩 제거. 미사용 `Arc` shape 삭제.

## [0.5.1] — 2026-05-28

### Fixed

- **v0.5.0 빌드의 트랙패드 기능 누락 회귀** — v0.5.0 tag가 트랙패드 제스처(v0.4.2~v0.4.4)가 merge되기 전 commit을 가리킨 채 release돼, 트랙패드 swipe·핀치 효과와 전역 단축키 consume 수정이 빠진 빌드가 나갔다. 코드는 이미 main에 올바르게 merge돼 있어 버전만 범프해 재배포. 트랙패드 제스처 + 낯선 모니터 자동 키스트로크 둘 다 포함.

## [0.5.0] — 2026-05-18

### Added

- **낯선 모니터 자동 키스트로크** — 신뢰 목록에 없는 외장 모니터(회의실·강의실 등)에 연결되면 키스트로크 표시가 자동으로 켜짐. 발표 상황을 모니터로 감지. 모니터 분리 시 원래 상태로 복원 (자동 ON 전 이미 켜둔 상태였으면 유지).
  - **신뢰 모니터 등록** — 환경설정 > 동작 탭에 현재 연결된 외장 모니터 목록 + 신뢰 체크박스. 자주 쓰는 데스크탑 모니터는 신뢰 등록해 자동 활성화에서 제외.
  - **안정적 식별** — `CGDisplayCreateUUIDFromDisplayID`로 물리 디스플레이 UUID. 재연결해도 같은 모니터 인식 (EDID 있는 경우). default OFF.

### Internal

- `MonitorIdentity.swift` — NSScreen 확장 (displayID/stableUUID/isBuiltin/friendlyName) + `ExternalMonitor` 스냅샷.
- `CursorSettings`: `autoKeystrokeOnUnknownMonitor` (@Persisted) + `trustedMonitorUUIDs` ([String], UserDefaults 직접).
- `AppDelegate.evaluateAutoKeystroke()` — `screensChanged()` + launch 시 호출. 자동 ON/OFF 상태 추적 (autoKeystrokeActive + keystrokeStateBeforeAuto로 복원).

## [0.4.4] — 2026-05-27

### Fixed

- **트랙패드 좌·우 스와이프 효과 가시성 / 중복** — Space 전환 중 컴포지터 스냅샷에 effect가 묻혀 슬라이드 종료 후에야 보이던 문제, 연속 swipe 시 이전 화면 effect와 새 화면 effect가 겹쳐 보이던 문제를 해결. boundary(끝단)에서는 즉시 softReveal로 발사하고, 중간 화면에서는 `CGSManagedDisplayGetCurrentSpace`로 Space commit을 50ms 간격 polling해 슬라이드 종료 시점에 자연스럽게 합류시킴. 가장 최근 swipe의 firedAt만 살리는 stale 보호로 빠른 연속 swipe 시 항상 마지막 swipe의 effect만 표시.

### Added

- **입력 모니터링 권한 자동 등록** — 앱 실행 시 `CGRequestListenEventAccess`로 silent 등록 호출. macOS Sonoma+에서 `IOHIDRequestAccess`가 prompt를 안 띄우는 회귀가 있어 CoreGraphics 쪽 private API로 우회. 첫 실행 시 macOS 표준 prompt 한 번 뜨고 시스템 설정 → 입력 모니터링 목록에 앱이 자동 등장.
- **권한 안내 UI 정리** — 환경설정 → 돋보기 탭의 화면 녹화 권한 배너를 작은 info 아이콘 + caption + 작은 "설정 열기" 버튼으로 축소. ad-hoc 사이닝 앱이 자동 등록되지 않는 경우 시스템 설정에서 "+" 버튼으로 직접 추가하는 가이드 추가.

### Internal

- Space commit 타이밍 차이(외장 ~580ms, 내장 600~1000ms+)는 OS 동작이라 polling deadline 1.6s로 양쪽 흡수. NSWorkspace의 `activeSpaceDidChangeNotification`이 내장 모니터에서 안 오는 케이스 대비해 `CGSManagedDisplayGetCurrentSpace` 디스플레이별 query로 fallback.

## [0.4.3] — 2026-05-26

### Added

- **트랙패드 시스템 제스처 효과** (실험적, 기본 OFF) — 4·5손가락 핀치(Launchpad / Show Desktop), 3·4손가락 위·아래 스와이프(Mission Control / App Exposé), 3·4손가락 좌·우 스와이프(Space 전환)에 시각 피드백. 환경설정 → 동작 → 기타 → "트랙패드 제스처 효과"에서 켬.

### Internal

- macOS는 멀티터치 시스템 제스처를 컴포지터 레벨에서 처리해 `NSEvent`/`CGEventTap` 같은 공식 API로 안 보임. 비공식 `MultitouchSupport.framework`를 `dlopen`해서 raw 터치 frame을 직접 읽음 (BetterTouchTool/MiddleClick 등이 쓰는 이 분야 표준 우회로). macOS 업데이트로 깨질 수 있어 `isAvailable` 가드로 graceful no-op 처리. 토글 OFF 시 service 시작 자체 안 함 → CPU 0.
- `TrackpadGestureClassifier`를 순수 함수로 분리해 18개 단위 테스트로 검증 — swipe threshold 0.08(정규화), pinch threshold 0.05, 일관성 검사 tolerance 0.02. 수평 swipe는 시스템 Space slide 애니메이션과 시각 경쟁 회피 위해 0.2초 지연 fade-in.

## [0.4.2] — 2026-05-24

### Fixed

- **전역 단축키가 포커스된 앱으로 새던 버그** — `⌃⌥` 단축키를 `NSEvent.addGlobalMonitorForEvents`(수동 모니터)로 받아, 우리 핸들러가 처리하면서도 같은 키가 포커스 앱에도 그대로 전달됐다. 예: 돋보기 토글 `⌃⌥M`이 YouTube 쇼츠의 `M`(음소거)로 새고, `⌃⌥0~6`이 YouTube 숫자 탐색으로 샜다. 키보드 핸들링을 마우스와 동일한 CGEventTap(`.defaultTap`)으로 바꿔, 우리가 처리하는 `⌃⌥` 단축키는 이벤트를 삼킨다(consume). 일반 타이핑·`⌘⇧3/4/5`·`⌘V`는 그대로 통과해 키스트로크 표시 등 기능 유지.

## [0.4.1] — 2026-05-18

### Added

- **README.en.md** — 영어 README. 한국어 README 상단에서 링크. 다국어 앱에 어울리는 docs.
- **단위 테스트 9개 추가** — `DragAngleLabelTests` (atan2 라디안 → 시계방향 12시 기준 0~359° 변환 + 8방향 화살표 매핑). 총 47 tests.

### Changed

- **환경설정 윈도우 다국어 점진** — 5개 탭 이름, 9개 섹션 헤더, 11개 토글 라벨, 5개 LabeledContent 라벨, InfoTab 9개 항목 (앱 정보/버전/개발자/업데이트 등). SwiftUI Text/Toggle/Section/Label은 자동 LocalizedStringKey라 코드 변경 없이 `Localizable.xcstrings`에 key + en 번역만 추가.

### Internal

- `DragAngleLabel.displayDegrees`와 `directionArrow`를 `static func`으로 분리 — Tests 접근 가능. View 본문에서는 같은 함수를 호출.

## [0.4.0] — 2026-05-18

### Added

- **영어 다국어 지원 (English localization)** — `Localizable.xcstrings` String Catalog 도입. macOS 시스템 언어가 영어인 사용자에게 영어로 표시. 한국어 사용자는 그대로.

### Localized

- 메뉴바: 환경설정, 스포트라이트, 돋보기, 키스트로크, 스크린샷 모드, 비활성화/활성화, 종료
- 권한 alert: 제목 + 본문 단계별 안내 + 4개 권한 이름 (손쉬운 사용/화면 녹화/입력 모니터링/입력 보내기) + 버튼 (시스템 설정 열기/모든 패널 열기/나중에)
- 상태 알림 toast: 스포트라이트/키스트로크/스크린샷 모드 켜짐·꺼짐, 돋보기 줌 level

### Internal

- `project.yml`에 `developmentLanguage: ko` + `LOCALIZATION_PREFERS_STRING_CATALOGS: YES` 설정.
- `String(localized:)` API 사용 (macOS 12+). 코드의 한국어 literal이 그대로 xcstrings 키로 동작.
- 빌드 시 `en.lproj` + `ko.lproj` 자동 생성, 시스템 언어 따라 자동 선택.

### Not yet localized (v0.4.x 점진)

- 환경설정 윈도우 전체 (탭 이름, 옵션 라벨, 설명문, 정보 탭의 Motion Semantics 등)
- 색상 이름 (노란색/빨간색/...) — RingColor.label
- 색상 cycle toast (🎨 ColorName)
- README, 설치/권한 안내문

## [0.3.1] — 2026-05-18

### Added

- **⌃⌥0 링 색상 순환** — 발표 중 빠른 색 변경용. 한 키로 다음 색 (1~6 개별 키 누르기 귀찮을 때).
- **드래그 각도 라벨** — 드래그 중 cursor 우상단에 "↗ 45°" 라벨 (8방향 화살표 + degrees). 도면·일러스트레이션에서 각도 확인. 환경설정 동작 탭에서 토글, default OFF.

### Changed

- **환경설정 돋보기 배율 Picker → Slider** — 1.5/2/3/4 4단 segmented picker를 0.5 step slider + "2.5×" 값 라벨로. 단축키 ⌃⌥= / ⌃⌥-의 0.5 step과 일관 + 2.5x, 3.5x 같은 중간 값도 선택 가능.

## [0.3.0] — 2026-05-17

### Added

- **휠 클릭 (middle click) 효과** — 마우스 button 2 누르면 두 개의 호(arc)가 반대 방향으로 회전하며 확장 fade out. 좌/우 클릭의 단순 파동과 차별 — "휠 클릭"의 회전 의미가 시각적으로 전달.
- **Scroll 진폭 비례 화살표 크기** — 기존엔 모든 스크롤이 같은 크기. 이제 deltaY/deltaX에 비례 (트랙패드 1지손 ~17pt, 휠 한 칸 ~20pt, 강한 swipe 30+pt). 작은 정밀 스크롤과 큰 page 스크롤을 한눈에 구분.
- **돋보기 줌 ⌃⌥= / ⌃⌥- 단축키** — 돋보기 켜진 상태에서 빠른 줌 in/out. 환경설정 안 열고 0.5x step 조정. clamp 1.5x ~ 4.0x.
- **줌 변경 toast** — 줌 단축키 누르면 "🔍 돋보기 줌 2.5x" 짧은 알림. 현재 줌 level을 즉시 확인.

## [0.2.10] — 2026-05-17

### Changed

- **권한 alert 본문 강화** — ① 시스템 설정 열기 ② 항목 클릭 후 「-」 버튼으로 제거 ③ 앱 다시 실행 단계별 안내. cdhash 변경으로 토글 ON 상태인데도 stuck인 경우 제거 후 재부여만 동작한다는 점 명시.
- **앱 이름 자동 클립보드 복사** — alert 띄울 때 "CursorHighlight" 문자열을 클립보드에 복사 → 시스템 설정 검색창에 ⌘V로 바로 붙여넣기.
- **「모든 패널 열기」 버튼** — missing 권한이 2개 이상이면 표시. 0.5초 간격으로 각 권한 패널 순차 오픈 → 사용자가 한 번에 다 처리 가능.

## [0.2.9] — 2026-05-17

### Fixed

- **Launch 시 권한 체크 false negative** — v0.2.6은 launch 1초 후 단발 체크라 TCC 권한 동기화가 안 끝난 상태에서 false 반환 → 이미 부여된 권한도 missing이라 안내하던 문제. 1초 간격으로 5번 retry, 모든 시도에서 일관되게 missing인 권한만 진짜 missing 판단. 총 대기 약 6초. 한 번이라도 부여 검출되면 그 권한은 OK 처리.

## [0.2.8] — 2026-05-17

### Fixed

- **Silent 업데이트가 tap 24시간 캐시 때문에 "이미 latest" 잘못 판단** — v0.2.7은 `HOMEBREW_NO_AUTO_UPDATE` 제거만으로 부족. brew의 auto-update가 기본 24시간 interval(`HOMEBREW_AUTO_UPDATE_SECS=86400`)로 일정 시간 안에는 tap fetch를 skip. 새 release 직후 사용자가 click하면 local tap이 옛 cask file에 멈춰 또 no-op. `HOMEBREW_AUTO_UPDATE_SECS=0`로 매 호출마다 강제 update — 5-10초 추가되지만 silent UX에서 한 번이라 trade-off 받아들임.

## [0.2.7] — 2026-05-17

### Fixed

- **Silent 업데이트가 "이미 latest" 잘못 판단** — v0.2.5에서 추가한 `HOMEBREW_NO_AUTO_UPDATE=1` 환경 변수가 tap fetch도 막아 local cask file이 옛 버전에 멈춰 "이미 latest 설치됨" 메시지로 no-op 종료하던 회귀. 환경 변수 제거 → brew가 자동으로 tap 갱신 후 upgrade. 진행 stage에 "Homebrew 갱신 중..." 라벨 추가.

## [0.2.6] — 2026-05-17

### Added

- **Launch 시 권한 자동 체크 + 안내** — 손쉬운 사용 / 화면 녹화 / 입력 모니터링 / 입력 보내기 4개 권한을 launch 1초 후 자동 확인. 일부라도 missing 시 NSAlert로 어느 권한이 부여 안 됐는지 명시 + 「시스템 설정 열기」 버튼으로 첫 missing 패널 직접 오픈. brew upgrade (cdhash 변경)로 권한이 reset되는 macOS 동작에 대비.

### Internal

- `PermissionsManager.PermissionType` enum 추가 (4개 권한 + 각 settingsURL).
- `IOHIDCheckAccess`로 ListenEvent/PostEvent 권한 상태 prompt 없이 조회.
- 기존 단발 `requestAccessibility()` 호출 제거 — 새 통합 alert로 대체.

## [0.2.5] — 2026-05-17

### Changed

- **Silent in-app 업데이트** — "지금 업데이트" 클릭 시 Terminal.app을 띄우지 않고 환경설정 안에서 spinner + 진행 stage(다운로드 중/검증 중/설치 중...) 표시. 성공 시 자동 재시작.
- **실패 시 Terminal fallback** — brew 실패하면 마지막 출력 일부를 monospace로 표시 + 「Terminal로 재시도」 버튼. brew stuck 같은 edge case에 사용자가 직접 대응 가능.

### Internal

- `Process()`로 `/opt/homebrew/bin/brew` 직접 호출 (Apple Silicon) — Intel `/usr/local/bin/brew` fallback.
- LSUIElement는 PATH 최소라 brew 절대 경로 명시.
- `HOMEBREW_NO_AUTO_UPDATE=1` + `HOMEBREW_NO_ANALYTICS=1` + `HOMEBREW_NO_ENV_HINTS=1` 으로 출력 깔끔 + 속도 빠르게.

## [0.2.4] — 2026-05-17

### Changed

- **"지금 업데이트" 자동 재시작** — brew upgrade 성공 후 `pkill -x CursorHighlight && open -a CursorHighlight`를 안내만 출력하던 것을 자동 실행으로 변경. 사용자가 별도 액션 없이 새 버전이 메뉴바에 바로 표시.

## [0.2.3] — 2026-05-17

### Fixed

- **"지금 업데이트" 스크립트의 zsh 호환** — `status=$?`가 zsh에서 read-only built-in 충돌로 실패하던 문제. `if cmd; then ... else ... fi` 직접 구조로 단순화 — 변수 없이 exit 분기. "Enter를 눌러 닫기" 프롬프트도 정상 표시.

## [0.2.2] — 2026-05-17

### Added

- **"지금 업데이트" 버튼** — 환경설정 > 정보 > 업데이트 섹션. 새 버전 감지 시 표시. 클릭하면 임시 shell script 생성 후 Terminal.app으로 자동 실행 (`brew upgrade --cask kykim79/tap/cursorhighlight`). 사용자가 명령어 복사·붙여넣기 안 해도 됨. Homebrew 미설치 사용자는 기존 「Release 페이지」 버튼으로 zip 직접 다운로드.

## [0.2.1] — 2026-05-17

### Added

- **스크린샷 모드 토글** — 메뉴바에 추가. 평소 overlay window의 `sharingType = .none` (자체 돋보기가 자기 overlay 재캡처 방지)이라 외부 `screencapture`/OBS에 잡히지 않던 제약을, 토글 ON 시 `.readOnly`로 일시 해제. 발표 자료/데모 GIF 만들 때 사용. 앱 재시작 시 자동 OFF.
- **README 스크린샷 2장** — hero (스포트라이트 + 보라색 ring), 환경설정 모양 탭.

### Changed

- **README 프로젝트 구조** — God Object 분할 후 새 파일 구조 반영 (State/Services/Views 그룹). 옛 `CursorState.swift` 단일 파일 표기를 4개 store + 6개 service로 갱신.
- **아키텍처 노트** — 돋보기 캡처 `CGWindowListCreateImage` → `ScreenCaptureKit SCStream` 표기. Overlay `sharingType` 동작 설명 추가.

## [0.2.0] — 2026-05-17

사용자에게 의미 있는 첫 release. 드래그 효과 5종 + 자동 모드 + 업데이트 확인 + 안정화.

### Added

- **드래그 속도 비례 glow** — 빠르게 끌수록 ring이 더 환하게 빛남 (발표·녹화에서 가속이 시각적으로 강조).
- **드래그 종료 시 spring snap back** — "탁! 놓았다" 마이크로인터랙션.
- **속도 비례 jelly stretch** — 느린 드래그는 거의 원형, 빠른 드래그는 더 길쭉.
- **드래그 앵커 라인** — 시작점에 작은 dot + 시작점→현재 위치 점선 연결. 의도적 긴 드래그(100pt 또는 1초 이상)에만 자동 fade in. 환경설정에서 토글.
- **드래그 컴맷 테일** — 드래그 중 cursor 뒤에 굵은 streak (발표·녹화 가시성용, default OFF).
- **업데이트 확인** — 환경설정 > 정보 탭에서 GitHub Releases 비교, 새 버전 있으면 안내 + Release 페이지 링크 + `brew upgrade` 명령.
- **메뉴바 빠른 토글** — 메뉴바 아이콘 클릭 시 스포트라이트/돋보기/키스트로크 표시 직접 토글 (✓ state + 단축키 표시).
- **앱별 자동 모드 확장** — Keynote/PowerPoint/Zoom/Teams/WebEx/Discord/Slack/QuickTime/OBS/Loom/CleanShot 등 12개 앱 활성화 시 자동으로 ring 활성. event-driven (즉시 반응).
- **Homebrew Cask 배포** — `brew install --cask kykim79/tap/cursorhighlight` 한 줄로 설치. quarantine 우회 불필요.

### Changed

- **환경설정 색상 섹션 UI 정리** — 8슬롯 4×2 grid (커스텀 swatch 포함, 빈 자리 없음). 커스텀 선택 시만 ColorPicker 노출.
- **돋보기 캡처 backend** — deprecated `CGWindowListCreateImage` → `ScreenCaptureKit (SCStream)` 마이그레이션.
  - 이중 모니터 완전 지원: cursor가 다른 디스플레이로 옮기면 stream 자동 재구성.
- **앱별 자동 모드 동작** — 5초 polling → event-driven (`NSWorkspace.didActivateApplicationNotification`).

### Fixed

- **환경설정 윈도우 누수 — CPU 60% 폭주 수정** — 닫혀도 view tree가 메모리에 살아 매 cursorPosition 60Hz 변경 시 layout 재계산. `windowWillClose`에서 controller 해제로 0%로.
- **비밀번호 필드 force cast 잠재 크래시** — 키스트로크 표시 핫패스의 `AXUIElement` 가드.
- **다중 모니터 스크롤 race** — 한 화면 스크롤 시 다른 화면 스크롤 인디케이터까지 사라지던 문제.
- **흔들기 감지 비대칭** — 수평 흔들기 detect 안 되고 좌하-우상 대각선만 과도 trigger되던 알고리즘 문제. 각 축 독립 추적 + dedup window로 모든 방향 일관.
- **돋보기 1초 후 자동 off** — 권한 polling이 false 일시 감지 시 magnifier 강제 off하던 회귀 제거.

### Internal

- **God Object 분할 (2개)** — `CursorState` (460줄, @Published 44개) → 4개 ObservableObject로. `AppDelegate` (543줄) → 297줄 + 4개 서비스 (`PermissionsManager`, `AppActivationDetector`, `MagnifierCaptureService`, `KeyboardHotkeyHandler`).
- **`@Persisted` PropertyWrapper** — UserDefaults boilerplate 25개 → 한 줄. enum/CGFloat/UInt16 bridging + debounce 옵션.
- **단위 테스트 인프라 + 38개 테스트** — standalone test bundle (test host 없이), `xcodebuild test`로 실행. PersistedTests (11) / DragAngleTests (6) / KeyFormatTests (7) / ShakeDetectionTests (14).
- **GitHub Actions release 자동화** — `git tag vX.Y.Z && git push --tags` 두 줄로 빌드 + zip + GitHub Release + tap repo cask 자동 갱신.
- **xcode-build-server** — SourceKit-LSP가 .xcodeproj 모듈을 정확히 인식하게 BSP 설정. 외부 에디터 (VS Code/Cursor) 진단 깨끗.
- **성능 마이크로** — `primaryScreenHeight` 캐시 (60Hz hotpath의 NSScreen 쿼리 제거), `saveCustomColor` debounce 일관성, `addScrollEffect` 화면별 분리.
- **CursorRingView API 정리** — 매개변수 16개 → `RingAppearance` + `RingMotion` struct (호출부 3줄).

## [0.1.x] — 2026-05-17

초기 release 인프라 검증용. v0.2.0이 사용자에게 의미 있는 첫 release.
