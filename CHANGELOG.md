# Changelog

[Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 형식 + [Semantic Versioning](https://semver.org/lang/ko/) 따름.

## [Unreleased]

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
