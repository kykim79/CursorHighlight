# CursorHighlight

macOS 메뉴바 앱. 마우스 커서를 시각적으로 강조해 화면 녹화, 발표, 페어 프로그래밍 시 커서 위치를 명확하게 보여줍니다.

![스포트라이트 + 보라색 커서 링](docs/screenshots/01-hero.png)

## 기능

- **커서 링** — 마우스 주위에 색상 링 표시 (원형/둥근 사각형/마름모, 4단계 크기, 글로우, 호흡 애니메이션)
- **클릭 효과** — 좌클릭(원형 파동), 우클릭(마름모 2중 파동), 더블클릭(버스트)
- **드래그 인디케이터** — 드래그 시 링이 방향대로 늘어남
- **스크롤 인디케이터** — 스크롤 방향 화살표 (↑↓←→) 표시
- **커서 트레일** — 잔상 효과 (글로우 코멧 테일)
- **돋보기** — 커서 주변 화면 1.5×–4× 실시간 확대
- **스포트라이트** — 커서 주변만 밝게, 나머지 어둡게
- **키스트로크 표시** — 누른 단축키를 화면 하단에 오버레이
- **흔들기 감지** — 마우스 흔들면 SOS 링으로 위치 알림
- **스크린샷 모드** — 메뉴바 토글. 평소엔 자체 돋보기가 자기 overlay를 재캡처하지 않게 외부 캡처에서 제외되지만, 발표 자료/데모 GIF 만들 땐 이 토글로 외부 `screencapture`/OBS에 잡히게 풀어줌. 앱 재시작 시 자동 OFF.

## 단축키

모든 단축키는 `⌃⌥` (Control + Option) 조합:

| 키 | 동작 |
|---|------|
| `⌃⌥S` | 스포트라이트 켜기/끄기 |
| `⌃⌥M` | 돋보기 켜기/끄기 |
| `⌃⌥K` | 키스트로크 표시 켜기/끄기 |
| `⌃⌥1` | 노란색 링 |
| `⌃⌥2` | 빨간색 링 |
| `⌃⌥3` | 파란색 링 |
| `⌃⌥4` | 초록색 링 |
| `⌃⌥5` | 하늘색 링 |
| `⌃⌥6` | 보라색 링 |

환경설정에서 일부 단축키는 변경 가능 (메뉴바 아이콘 → 환경설정).

## 환경설정

색상 8슬롯 (커스텀 포함), 모양 3종, 크기 4단계, 투명도/속도/효과 토글까지 한 곳에서 조정.

![환경설정 - 모양 탭](docs/screenshots/02-preferences.png)

## 시스템 요구사항

- macOS 13.0 이상
- Apple Silicon (현재 빌드 기준; Intel은 Universal 빌드 필요)

## 사용자 설치

### Homebrew (추천)

```bash
brew install --cask kykim79/tap/cursorhighlight
```

Homebrew가 다운로드 시 quarantine flag를 자동으로 제거해주므로 Gatekeeper 우회 절차 없이 바로 동작. 업데이트도 `brew upgrade --cask cursorhighlight` 한 줄.

### 수동 설치

[Releases](https://github.com/kykim79/CursorHighlight/releases)에서 `CursorHighlight.zip` 다운로드 후:

1. 압축 해제 → `CursorHighlight.app`을 `/Applications`로 이동
2. **첫 실행**: Finder에서 우클릭 → 열기 → "열기" 확인 (Gatekeeper 우회, 한 번만)

우클릭→열기도 안 되면:
```bash
xattr -dr com.apple.quarantine /Applications/CursorHighlight.app
```

### 권한 부여 (설치 방식과 무관 — 공통)

시스템 설정 → 개인정보 보호 및 보안에서:
- **손쉬운 사용** (필수): 마우스/키보드 이벤트 캡처
- **입력 모니터링** (필수): 단축키 감지
- **화면 녹화** (선택): 돋보기 사용 시

권한 부여 후 앱 재시작 → 메뉴바에 `cursorarrow.rays` 아이콘 표시되면 정상.

## 개발 환경 구축

다른 Mac에서 처음 받았을 때:

```bash
# 사전 도구 설치
brew install xcodegen

# 클론
gh repo clone kykim79/CursorHighlight
cd CursorHighlight

# .xcodeproj 생성 (git에는 없음, project.yml에서 재생성)
xcodegen

# Xcode 열기
open CursorHighlight.xcodeproj
```

### SourceKit-LSP 인식 (VS Code/Cursor 등 외부 에디터 사용 시)

Xcode 외부 에디터에서 SourceKit-LSP가 모듈을 정확히 인식하게 하려면 build server 설정:

```bash
brew install xcode-build-server
xcode-build-server config -project CursorHighlight.xcodeproj -scheme CursorHighlight
```

→ `buildServer.json` 생성 (gitignore됨, user-specific path 포함). 한 번 실행하면 이후 LSP가 cross-file 타입을 정확히 인식.

이후 Xcode에서 `⌘R`로 빌드/실행 가능.

### CLI 빌드 + 설치

```bash
# Release 빌드
xcodebuild -project CursorHighlight.xcodeproj \
  -scheme CursorHighlight \
  -configuration Release \
  build

# /Applications에 설치
pkill -x CursorHighlight 2>/dev/null
rm -rf /Applications/CursorHighlight.app
cp -R "$HOME/Library/Developer/Xcode/DerivedData/CursorHighlight-"*"/Build/Products/Release/CursorHighlight.app" /Applications/
open /Applications/CursorHighlight.app
```

### 권한 초기화 (재배포 시 깨끗하게 시작)

```bash
tccutil reset Accessibility com.ktoy.CursorHighlight
tccutil reset ScreenCapture com.ktoy.CursorHighlight
tccutil reset ListenEvent com.ktoy.CursorHighlight
tccutil reset PostEvent com.ktoy.CursorHighlight
```

## 프로젝트 구조

```
CursorHighlight/
├── project.yml                          # XcodeGen 설정 (소스 of truth)
├── Sources/CursorHighlight/
│   ├── main.swift                       # 앱 진입점
│   ├── AppDelegate.swift                # 메뉴바, 권한, 이벤트 라우팅
│   ├── CursorState.swift                # @Published 상태 + 설정 (UserDefaults)
│   ├── MouseEventMonitor.swift          # CGEventTap (백그라운드 스레드)
│   ├── OverlayWindowController.swift    # 전체화면 투명 오버레이 NSWindow
│   ├── OverlayContentView.swift         # SwiftUI 뷰 (링, 효과, 트레일)
│   ├── PreferencesView.swift            # 환경설정 윈도우
│   ├── Info.plist                       # LSUIElement, 권한 설명
│   ├── CursorHighlight.entitlements
│   └── Assets.xcassets/AppIcon.appiconset/
└── README.md
```

`.xcodeproj`는 `xcodegen`이 매번 생성하므로 git ignore. `project.yml`이 진짜 프로젝트 정의.

## 아키텍처 노트

- **LSUIElement = true**: Dock 아이콘 없는 메뉴바 전용 앱
- **CGEventTap (백그라운드 스레드)**: 메인 RunLoop와 격리되어 NSMenu 트래킹, 앱 활성화 변화에 영향받지 않음
- **이벤트 기반 커서 추적**: 폴링 Timer 없음. `onMouseMove`로 push, idle 감지는 `DispatchWorkItem`
- **좌표계 변환**: CGEvent의 Quartz 좌표(top-left)를 Cocoa 좌표(bottom-left)로 변환 후 `cursorPosition` 저장
- **멀티 모니터**: 각 `NSScreen`마다 별도 오버레이 윈도우. `screenFrame.contains(point)` 필터로 같은 효과가 다른 화면에 중복 렌더링 안 됨
- **돋보기 캡처**: `CGWindowListCreateImage`를 백그라운드 큐에서 실행, 20Hz. `isMagnifierActive=false`일 때 Timer 자체 정지 (Combine sink)

## 라이선스

개인 프로젝트.
