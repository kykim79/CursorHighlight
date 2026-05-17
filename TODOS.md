# TODOS

`/plan-eng-review` 리뷰(2026-05-17)에서 발견된 개선점 중 보류한 항목들. 우선순위는 `P1`(구조/안전) → `P2`(성능/DRY) → `P3`(배포/테스트) 순.

위치는 함수·섹션 단위로 기록 (코드 변경에 강함). 정확한 라인은 `grep` 또는 Xcode `⇧⌘O`.

---

## P3 — 배포 / 테스트

### #12 Notarization (선택 — Homebrew로 사실상 해결됨)
- **상태**: **Homebrew Cask 배포로 우회 완료** (아래 완료 작업 참조). `brew install --cask kykim79/tap/cursorhighlight`로 사용자가 quarantine 우회 절차 없이 바로 설치 가능.
- **여전히 필요한 케이스**: Mac App Store 등록, Sparkle 자동 업데이트, GitHub Releases 직접 다운로드 사용자 경험 개선.
- **비용**: Apple Developer Program $99/년 + GitHub Actions notarization 자동화.

### #13 "업데이트 확인" 버튼 실제 동작
- **위치**: `PreferencesView.swift` `InfoTab` (`Section("업데이트")`)
- **문제**: 버튼을 누르면 무조건 "최신 버전입니다"만 출력. 실제 체크 없음.
- **방향 (택1)**:
  - **A.** [Sparkle](https://sparkle-project.org/) 통합 — 자동 업데이트
  - **B.** GitHub Releases API 폴링 — 최신 태그와 `CFBundleShortVersionString` 비교
  - **C.** 버튼 일시 숨김 (정직)

---

## 기능 아이디어 — 드래그 시각 효과 옵션

현재 드래그 시 ring이 jelly 스트레치(가로 1.35×, 세로 0.78× + rotation). 추가 옵션 brainstorm.
공통: `RingMotion` struct에 새 property + `OverlayContentView`에서 분기. `CursorSettings`에
`@Persisted` 토글 추가. 인프라 이미 잘 잡혀 있어 새 옵션 추가는 한 항목당 ~20-40줄.

### #18 Comet Tail — 드래그 잔상
- **목적**: 빠른 드래그 시 cursor 뒤에 streak. 화면 녹화에서 가시성 큼.
- **구현**: 기존 `TrailView` 응용 — 드래그 중에만 더 굵고 짧은 trail 생성. `EffectsState.updateTrail`을
  드래그 중일 때 다른 width/decay로.
- **난이도**: 中 (~40줄). 기존 trail 코드 재활용.

### 통합 디자인 (구현 시점에 결정)

```
환경설정 → 동작 → 드래그 스타일
  ⦿ Jelly (탄력 stretch — 현재)
  ◯ Anchored (시작점 연결)
  ◯ Comet (잔상)
☑ 속도에 따라 글로우 (#14)
☑ 종료 시 튕김 (#15)
☑ 속도에 비례한 stretch (#16)
```

스타일은 단일 선택, 향상 옵션은 토글 — 사용자가 조합 가능.

---

## 기타

### git author 글로벌 설정
- **현재 상태**: `ktoy <ktoy@ktoyui-Macmini.local>` / `ktoy@ktoyui-MacBookPro.local`로 자동 잡힘 → GitHub contribution 그래프에 안 잡힐 수 있음.
- **방향**:
  ```bash
  git config --global user.name "kykim79"
  git config --global user.email "kykim79@gmail.com"
  ```
- **참고**: 이전 두 커밋의 author 재작성은 `git filter-branch` 또는 `rebase` 필요한데 이미 push된 상태라 위험. 앞으로의 커밋만 정리하는 게 안전.

---

## 완료된 작업 (참고)

`aaa8dcb fix: 환경설정 닫을 때 view tree 해제로 CPU 폭주 수정`:

- ✅ **#1** Force cast 방어 — `KeyboardHotkeyHandler.isPasswordFieldFocused` (이전 AppDelegate)
- ✅ **#3** EventTap enum 분기 — `MouseEventMonitor.start` callback
- ✅ **Preferences view tree 누수 수정** — `AppDelegate.openPreferences` (CPU 60% → 0%)
- 📝 **#2** ScreenCaptureKit TODO 코멘트만 추가 (위 P1 #2 참조)

`1d39346 refactor: @Persisted PropertyWrapper로 UserDefaults boilerplate 제거`:

- ✅ **#6** @Persisted PropertyWrapper — `Persisted.swift` (138줄). ObservableObject 안에서
  enclosing subscript로 objectWillChange 자동 발행. CursorState.swift 460 → 349줄 (-24%).
  init/didSet boilerplate 25개 압축.

`efcb547 refactor: CursorState God Object를 4개 ObservableObject로 분할`:

- ✅ **#4** CursorState → 4분할:
  - `CursorSettings.swift` (188줄) — @Persisted + customRingColor + enums
  - `CursorRuntimeState.swift` (70줄) — cursor pos + motion + 돋보기 런타임
  - `EffectsState.swift` (91줄) — 효과 큐 + Effect structs
  - `KeystrokeOverlayState.swift` (40줄) — keystroke 알림
  - cursorPosition 60Hz 변경이 무관한 view를 더 이상 흔들지 않음 (Preferences 누수의 근본 원인 해결)

`9708297 refactor: AppDelegate God Object를 4개 서비스로 분할`:

- ✅ **#5** AppDelegate → 4서비스 + 코어:
  - `PermissionsManager.swift` (90줄) — 권한 요청·polling·설정 패널
  - `RecordingDetector.swift` (48줄) — 녹화 앱 감지 + 콜백
  - `MagnifierCaptureService.swift` (101줄) — 돋보기 20Hz 캡처
  - `KeyboardHotkeyHandler.swift` (176줄) — 전역 단축키 + 키스트로크
  - AppDelegate 543 → 297줄 (-45%)

`7d6edeb refactor: 돋보기 캡처를 ScreenCaptureKit(SCStream)으로 마이그레이션`:

- ✅ **#2** ScreenCaptureKit 마이그레이션 — 더 이상 `CGWindowListCreateImage`
  (deprecated) 참조 없음. SCStream push 모델 + CIImage cropping.
  이중 모니터 환경 완전 지원 — cursor가 다른 디스플레이로 옮기면 stream을
  그 디스플레이로 자동 재구성 (displayID 매칭 + screenContaining).
  `PermissionsManager.swift` 권한 polling이 false 감지 시 magnifier 강제
  off 처리 제거 (timing 회귀 방지). MagnifierCaptureService 101 → 226줄.

`a9fcbd4 perf: customRingColor 저장에 0.3초 debounce 추가`:

- ✅ **#10** `saveCustomColor`에 0.3초 debounce 추가 — ColorPicker 드래그 시
  매 변화마다 NSColor 변환+UserDefaults set 회피. 다른 @Persisted 슬라이더와 일관.

`3246935 refactor: CursorRingView 매개변수 16개 → RingAppearance/RingMotion struct`:

- ✅ **#7** `CursorRingView` 생성자 16개 → `RingAppearance` + `RingMotion` 두 struct.
  호출부 16줄 → 3줄. 옵션 추가는 struct에만 한 줄, 호출부 영향 0.

`effbdf2 perf: primaryScreenHeight 캐시`:

- ✅ **#8** `handleMouseMove` 60Hz hotpath에서 NSScreen 쿼리 제거.
  `screensChanged()`에서 한 번 캐시 → 모니터 구성 안 바뀌면 lookup 비용 0.

`da2be35 fix: addScrollEffect의 removeAll을 같은 화면으로 제한`:

- ✅ **#9** `EffectsState.addScrollEffect`의 multi-monitor race 해결.
  `NSScreen.frame.contains`로 point가 속한 화면을 찾아 그 화면 effect만 제거.

`3562071 test: 단위 테스트 인프라 + 24개 테스트 추가`:

- ✅ **#11** `project.yml`에 standalone test bundle 추가 + 24개 테스트 통과:
  - PersistedTests (11): native 타입·enum·debounce·objectWillChange
  - DragAngleTests (6): ±π wrapping, 한 바퀴 누적, endDrag 리셋
  - KeyFormatTests (7): 모디파이어 게이트, special keys, 순서
  - 실행: `xcodebuild test -project CursorHighlight.xcodeproj -scheme CursorHighlight -destination 'platform=macOS'`

`6487dfc refactor: 흔들기 감지 알고리즘 추출 + 축별 독립 검증 + 14 테스트`:

- ✅ **#11-followup** `ShakeState` 순수 struct로 알고리즘 추출 + 각 축(vx/vy)
  독립 추적 + 0.5초 dedup window. 이전 dominant-axis 방식의 비대칭(좌하↔우상
  대각선 과도 발화, 다른 방향 detect 실패) 해결. 임계값 300→150으로 손목 흔들기
  커버. ShakeDetectionTests 14개 추가. 전체 38 tests SUCCEEDED.

`fa5b8f0 feat: 드래그 속도 비례 glow (#14 Speed Glow)`:

- ✅ **#14 Speed Glow** — 드래그 속도(pt/s)에 비례해 ring glow 강화.
  EMA(0.3) smoothing + 1000pt/s에서 max +1.5 boost. 토글 없이 default on.

`a6287f2 feat: 드래그 종료 시 spring snap back (#15)`:

- ✅ **#15 Snap Back** — endDrag()에 ringClickScale 1.12 expand → spring back
  마이크로인터랙션 추가. "탁! 놓았다" 피드백.

`2b5d6da feat: 속도 비례 jelly stretch (#16 Velocity Stretch)`:

- ✅ **#16 Velocity Stretch** — scaleEffect를 dragVelocity에 비례화. 느린 드래그는
  거의 원형(1.05/0.95), 빠르면 max(1.5/0.7). #14의 dragVelocity 인프라 재사용.

`9e5bf4b feat: 드래그 앵커 라인 (#17)`:

- ✅ **#17 Anchored Line** — 드래그 시작점 dot + 점선 연결. 거리(100pt) OR 시간(1초)
  임계로 자동 fade in (짧은 드래그는 비표시). `isAnchoredLineEnabled` 토글로 ON/OFF.

`d772fec ci: GitHub Actions release workflow + Homebrew tap 자동 배포` 외 다수:

- ✅ **Homebrew Cask 배포 인프라** — `git tag vX.Y.Z + push` 한 줄로 자동 release:
  - `.github/workflows/release.yml` — macos-15 runner에서 xcodegen + xcodebuild
    Release + ditto zip + sha256 + GitHub Release create + tap repo cask 자동 commit
  - `project.yml` + `Info.plist` — `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` 동적 주입
  - `kykim79/homebrew-tap` repo의 `Casks/cursorhighlight.rb` 자동 갱신
  - README — `brew install --cask kykim79/tap/cursorhighlight` 안내
  - **#12 Notarization 사실상 대체** — Homebrew가 quarantine flag 자동 제거하므로
    Gatekeeper 우회 절차 없이 더블클릭 설치 동등 경험.
  - 첫 release: v0.1.1 (v0.1.0은 GitHub side asset routing inconsistency로 폐기).
