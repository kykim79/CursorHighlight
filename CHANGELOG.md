# Changelog

[Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 형식 + [Semantic Versioning](https://semver.org/lang/ko/) 따름.

## [Unreleased]

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
