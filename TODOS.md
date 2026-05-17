# TODOS

`/plan-eng-review` 리뷰(2026-05-17)에서 발견된 개선점 중 보류한 항목들. 우선순위는 `P1`(구조/안전) → `P2`(성능/DRY) → `P3`(배포/테스트) 순.

위치는 함수·섹션 단위로 기록 (코드 변경에 강함). 정확한 라인은 `grep` 또는 Xcode `⇧⌘O`.

---

## P3 — 배포 / 테스트

### #11-followup MouseEventMonitor 흔들기 감지 테스트
- **위치**: `MouseEventMonitor.processMove`
- **상태**: #11에서 인프라 + 3개 영역(Persisted, DragAngle, KeyFormat) 커버됨.
  흔들기 감지는 알고리즘 추출 refactor 필요해서 보류.
- **방향**: `private func processMove`를 pure function으로 추출 — `ShakeState` struct +
  `static func detectShake(state: inout ShakeState, point: CGPoint, now: TimeInterval) -> Bool`.
  시간을 인자로 받게 해 테스트에서 시뮬레이션 데이터로 검증 가능.

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
  - 흔들기 감지는 알고리즘 추출 refactor 필요해 보류 (P3 #11-followup).
