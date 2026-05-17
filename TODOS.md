# TODOS

`/plan-eng-review` 리뷰(2026-05-17)에서 발견된 개선점 중 보류한 항목들. 우선순위는 `P1`(구조/안전) → `P2`(성능/DRY) → `P3`(배포/테스트) 순.

위치는 함수·섹션 단위로 기록 (코드 변경에 강함). 정확한 라인은 `grep` 또는 Xcode `⇧⌘O`.

---

## P2 — DRY / 성능

### #7 CursorRingView 매개변수 15개 → RingStyle struct
- **위치**: `OverlayContentView.swift` `CursorRingView`
- **문제**: 생성자 매개변수 16개 (position 포함). 옵션 추가 시 호출부도 매번 수정.
- **방향**: 설정 14개를 `RingStyle` struct로 묶기.

### #8 NSScreen.screens.first?.frame.height 캐시
- **위치**: `AppDelegate.swift` `handleMouseMove`, `MagnifierCaptureService.swift` `start()`
- **문제**: 60Hz throttle 후에도 매 호출마다 `NSScreen.screens` 배열 쿼리. 20Hz 돋보기 timer에서도 동일.
- **방향**: AppDelegate가 `screensChanged()`에서 `primaryScreenHeight` 캐시 + MagnifierCaptureService에 주입.

### #9 addScrollEffect의 removeAll 다중 모니터 race
- **위치**: `EffectsState.swift` `addScrollEffect`
- **문제**: 한 화면에서 스크롤하면 모든 화면의 효과를 다 지움. 다중 모니터에서 다른 화면 효과가 살아 있을 때 같이 꺼짐.

### #10 saveCustomColor만 debounce 없음
- **위치**: `CursorSettings.swift` `customRingColor` `didSet` → `saveCustomColor()`
- **문제**: ColorPicker 슬라이더 드래그하는 동안 매 변경마다 NSColor 변환 + UserDefaults 호출. 다른 슬라이더는 @Persisted(debounce: 0.3)인데 customRingColor만 빠짐. @Persisted가 Color 타입 미지원이라 별도 처리됨.

---

## P3 — 배포 / 테스트

### #11 테스트 인프라 (순수 함수만이라도)
- **위치**: 프로젝트 전체에 테스트 0개
- **문제**: 흔들기 감지 같은 알고리즘은 회귀 위험이 큰데 매번 직접 흔들어보며 검증해야 함.
- **방향**: GUI 이벤트 핸들링은 어렵지만 순수 함수는 충분히 테스트 가능:
  - `MouseEventMonitor.processMove` — 흔들기 감지 (시뮬레이션 데이터)
  - `KeyboardHotkeyHandler.formatKey` — 키 포맷팅 (NSEvent mock)
  - `CursorRuntimeState.updateDragAngle` — atan2 wrapping (±π 경계)
  - `Persisted` — read/write/debounce 동작, enum/CGFloat/UInt16 bridging
  - 좌표계 변환 (Quartz top-left ↔ Cocoa bottom-left)
- **시작**: `Tests/CursorHighlightTests/` 디렉토리 + `project.yml`에 test target 추가.

### #12 Notarization (Gatekeeper 마찰 제거)
- **위치**: 배포 절차, README
- **문제**: 사용자가 `xattr -dr com.apple.quarantine` 직접 실행해야 함. 큰 마찰.
- **방향**: Apple Developer Program 가입 ($99/년) + GitHub Actions에 notarization 자동화. 더블클릭으로 설치 가능해짐.
- **트레이드오프**: 비용 + 매년 갱신 vs 사용자 경험.

### #13 "업데이트 확인" 버튼 실제 동작
- **위치**: `PreferencesView.swift` `InfoTab` (`Section("업데이트")`)
- **문제**: 버튼을 누르면 무조건 "최신 버전입니다"만 출력. 실제 체크 없음.
- **방향 (택1)**:
  - **A.** [Sparkle](https://sparkle-project.org/) 통합 — 자동 업데이트
  - **B.** GitHub Releases API 폴링 — 최신 태그와 `CFBundleShortVersionString` 비교
  - **C.** 버튼 일시 숨김 (정직)

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
