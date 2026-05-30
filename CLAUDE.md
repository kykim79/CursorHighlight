# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

CursorHighlight는 마우스 커서를 시각적으로 강조하는 macOS 메뉴바 전용 앱(LSUIElement). 화면 녹화·발표·페어 프로그래밍 시 커서 위치를 명확히 보여준다. 코드 주석·UI 소스 언어는 한국어이며 영어는 번역으로 제공된다 — 새 주석/UI 문자열도 한국어로 작성한다.

## 빌드 / 테스트 / 실행

`.xcodeproj`는 git에 없다. `project.yml`이 프로젝트 정의의 source of truth이며 `xcodegen`이 매번 생성한다. **`project.yml`을 수정하면 반드시 `xcodegen`을 다시 실행**해야 변경이 반영된다. `.xcodeproj`를 직접 편집하지 말 것.

```bash
# 최초/project.yml 변경 후 — Xcode 프로젝트 생성
xcodegen

# Release 빌드
xcodebuild -project CursorHighlight.xcodeproj -scheme CursorHighlight -configuration Release build

# 전체 테스트 (Debug)
xcodebuild -project CursorHighlight.xcodeproj -scheme CursorHighlight -configuration Debug test

# 단일 테스트 클래스 / 단일 메서드
xcodebuild ... test -only-testing:CursorHighlightTests/ShakeDetectionTests
xcodebuild ... test -only-testing:CursorHighlightTests/ShakeDetectionTests/test_horizontalShakeDetects
```

빌드 후 `/Applications` 설치는 `pkill -x CursorHighlight` → 기존 앱 삭제 → DerivedData의 `Release/CursorHighlight.app` 복사 → `open` 순서 (정확한 명령은 README "CLI 빌드 + 설치" 참고).

권한 변경 테스트 시 초기화: `tccutil reset {Accessibility|ScreenCapture|ListenEvent|PostEvent} com.ktoy.CursorHighlight`.

## 테스트 구조 (중요)

테스트 타깃 `CursorHighlightTests`는 **test host 없는 standalone bundle**이며, `Sources/CursorHighlight`를 직접 포함한다(`main.swift`/`Info.plist`/`entitlements`/`Assets.xcassets` 제외). 따라서 GUI를 띄우지 않고 **순수 함수만** 검증한다.

- 테스트 대상 로직은 `static func`으로 분리해 둔다 (예: `DragAngleLabel.displayDegrees`/`directionArrow`). View 본문은 같은 static 함수를 호출만 한다 — 테스트 가능성을 위한 핵심 패턴.
- 시간 의존 로직(`ShakeState`)은 wall clock을 쓰지 않고 `at:` 인자로 시간을 주입받는다.

## 아키텍처

`@MainActor AppDelegate`(`AppDelegate.swift`)가 중앙 코디네이터: 4개 상태 객체 + 4개 서비스를 owning하고, 마우스 이벤트를 라우팅하며 오버레이 lifecycle을 관리한다. 원래의 God object를 책임별로 분할한 구조다.

**상태 (4 ObservableObject)** — `CursorSettings`(영구 설정), `CursorRuntimeState`(커서 위치·motion·드래그), `EffectsState`(클릭/스크롤/트레일/흔들기 효과 큐), `KeystrokeOverlayState`(키스트로크 알림 큐).

**서비스** — `PermissionsManager`(TCC 권한 4종), `AppActivationDetector`(NSWorkspace로 발표·녹화 앱 감지), `MagnifierCaptureService`(ScreenCaptureKit SCStream 돋보기), `KeyboardHotkeyHandler`(전역 단축키 + 키스트로크), `MouseEventMonitor`(CGEventTap).

**뷰** — `OverlayWindowController`(전체화면 투명 NSWindow), `OverlayContentView`(SwiftUI 링·효과·트레일), `PreferencesView`(환경설정).

핵심 설계 결정:
- **CGEventTap은 백그라운드 스레드**에서 돈다 — 메인 RunLoop와 격리되어 NSMenu 트래킹/앱 활성화 변화에 영향받지 않음.
- **이벤트 기반 커서 추적** — 폴링 Timer 없음. `onMouseMove` push, idle 감지는 `DispatchWorkItem`. `handleMouseMove`는 ~60Hz hotpath라 매번 NSScreen 쿼리를 피하고 `primaryScreenHeight`를 캐싱 (`screensChanged()`에서만 갱신).
- **좌표계 변환** — CGEvent의 Quartz 좌표(top-left) → Cocoa 좌표(bottom-left)로 변환 후 저장.
- **멀티 모니터** — `NSScreen`마다 별도 오버레이 윈도우. `screenFrame.contains(point)` 필터로 효과 중복 렌더링 방지.
- **돋보기 + 스크린샷 모드** — 오버레이의 `sharingType`이 평소 `.none`이라야 자체 돋보기가 자기 overlay를 재캡처하지 않는다. 메뉴바 "스크린샷 모드" ON 시 `.readOnly`로 풀어 외부 `screencapture`/OBS가 잡게 함 (앱 재시작 시 자동 OFF).

## @Persisted PropertyWrapper

`CursorSettings`의 영구 설정은 `@Persisted("key", default:, debounce:)`로 선언한다(`Persisted.swift`). `_enclosingInstance` subscript로 enclosing ObservableObject의 `objectWillChange`를 호출 — `@Published`+`didSet`+UserDefaults 보일러플레이트를 제거한 자체 구현. native UserDefaults 타입과 `RawRepresentable` enum을 지원. **`Color`/`NSColor` 등 비-native 타입은 미지원** → `customRingColor`처럼 기존 `@Published`+`didSet` 패턴을 유지한다. 슬라이더처럼 잦은 쓰기는 `debounce`로 throttle.

## 다국어 (i18n)

`Localizable.xcstrings` String Catalog 사용. `sourceLanguage: ko` — 코드의 hardcoded 한국어가 source key, `en`은 번역. SwiftUI의 `Text`/`Toggle`/`Section`/`Label`은 `LocalizedStringKey`를 자동으로 받으므로, 새 UI 문자열 번역은 **코드 변경 없이** `Localizable.xcstrings`에 key + en 번역만 추가하면 된다. `project.yml`의 `LOCALIZATION_PREFERS_STRING_CATALOGS: YES`로 번역 누락 시 base(ko)로 fallback.

## 릴리스

`v*.*.*` (또는 `v*.*`) 태그 push → `.github/workflows/release.yml`이 macOS runner에서 `xcodegen` + `xcodebuild Release`(ad-hoc 사이닝) → `ditto`로 zip → GitHub Release 업로드 → `kykim79/homebrew-tap`의 Cask에 version + sha256 자동 commit. 버전은 태그에서 추출해 `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`으로 주입(로컬 빌드는 `project.yml`의 기본값). 릴리스 시 `CHANGELOG.md`(Keep a Changelog 형식)와 `project.yml`의 `MARKETING_VERSION`을 함께 갱신한다.

## Design System

UI 효과·오버레이 시각 결정은 항상 `DESIGN.md`를 먼저 읽고 따른다. 색·spacing·corner radius·motion duration·spring 파라미터·radial menu 거리·notification 포맷이 거기에 토큰화되어 있다. 새 효과 추가 시 토큰 외 값을 하드코딩하지 말 것 — 시스템 일관성이 깨진다. 이탈이 필요하면 명시적으로 사용자 승인 + Decisions Log 갱신.
