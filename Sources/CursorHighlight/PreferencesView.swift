import SwiftUI
import AppKit

// MARK: - Preferences Window Controller

class PreferencesWindowController: NSWindowController {
    init(settings: CursorSettings, runtime: CursorRuntimeState) {
        let view = PreferencesView(settings: settings, runtime: runtime)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 500)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CursorHighlight 환경설정"
        window.contentView = hosting
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Preferences View

struct PreferencesView: View {
    @ObservedObject var settings: CursorSettings
    @ObservedObject var runtime: CursorRuntimeState

    var body: some View {
        TabView {
            AppearanceTab(settings: settings)
                .tabItem { Label("모양", systemImage: "circle.dashed") }

            BehaviorTab(settings: settings)
                .tabItem { Label("동작", systemImage: "cursorarrow") }

            MagnifierTab(settings: settings, runtime: runtime)
                .tabItem { Label("돋보기", systemImage: "magnifyingglass.circle") }

            ShortcutsTab(settings: settings)
                .tabItem { Label("단축키", systemImage: "keyboard") }

            InfoTab()
                .tabItem { Label("정보", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 500)
    }
}

// MARK: - Appearance Tab

private struct AppearanceTab: View {
    @ObservedObject var settings: CursorSettings

    var body: some View {
        Form {
            Section("커서 링 색상") {
                // 7개 표준 색 + 커스텀 = 8슬롯, 4×2 grid 깔끔하게 채움.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    ForEach(CursorSettings.RingColor.allCases.filter { $0 != .custom }) { c in
                        ColorSwatch(
                            color: c.color,
                            label: c.label,
                            isSelected: settings.ringColor == c
                        ) { settings.ringColor = c }
                    }
                    // 커스텀 swatch — 다른 swatch와 동일한 시각, 현재 customRingColor 미리보기
                    ColorSwatch(
                        color: settings.customRingColor,
                        label: "커스텀",
                        isSelected: settings.ringColor == .custom
                    ) { settings.ringColor = .custom }
                }
                .padding(.vertical, 4)

                // 커스텀 선택 시만 ColorPicker 노출 — clutter 줄이고 의도 명확
                if settings.ringColor == .custom {
                    ColorPicker("커스텀 색상", selection: $settings.customRingColor)
                }
            }

            Section("링 모양") {
                Picker("모양", selection: $settings.ringShape) {
                    ForEach(CursorSettings.RingShape.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("링 크기") {
                Picker("크기", selection: $settings.ringSize) {
                    ForEach(CursorSettings.RingSize.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("링 투명도") {
                LabeledContent("투명도") {
                    HStack {
                        Slider(value: $settings.ringOpacity, in: 0.2...1.0, step: 0.05)
                        Text(String(format: "%.0f%%", settings.ringOpacity * 100))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("테두리 두께") {
                Picker("두께", selection: $settings.borderWeight) {
                    ForEach(CursorSettings.BorderWeight.allCases) { w in Text(w.label).tag(w) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            Section("테두리 스타일") {
                Picker("스타일", selection: $settings.borderStyle) {
                    ForEach(CursorSettings.BorderStyle.allCases) { s in Text(s.label).tag(s) }
                }
                .pickerStyle(.segmented).labelsHidden()

                Toggle("이중 링 (안쪽 반투명 선)", isOn: $settings.hasInnerRing)
                Toggle("링 채우기 (반투명 도넛)", isOn: $settings.isRingFillEnabled)
                Toggle("글로우 효과", isOn: $settings.isGlowEnabled)
                Toggle("원근 왜곡 (Perspective Warping)", isOn: $settings.isPerspectiveWarping)
            }

            Section("애니메이션 속도") {
                Picker("속도", selection: $settings.animationSpeed) {
                    ForEach(CursorSettings.AnimationSpeed.allCases) { s in Text(s.label).tag(s) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            Section("스포트라이트 반경") {
                LabeledContent("반경") {
                    HStack {
                        Slider(value: $settings.spotlightRadius, in: 60...250, step: 10)
                        Text("\(Int(settings.spotlightRadius))pt")
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
    }
}

private struct ColorSwatch: View {
    let color: Color
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.white, lineWidth: isSelected ? 3 : 0)
                        .shadow(color: .black.opacity(0.4), radius: 2))
                    .shadow(color: color.opacity(0.6), radius: 4)
                Text(label).font(.caption2).foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Behavior Tab

private struct BehaviorTab: View {
    @ObservedObject var settings: CursorSettings
    @State private var launchAtLogin: Bool = false
    @State private var externalMonitors: [ExternalMonitor] = []

    var body: some View {
        Form {
            Section("키스트로크") {
                LabeledContent("표시 시간") {
                    HStack {
                        Slider(value: $settings.keystrokeTimeout, in: 1...8, step: 0.5)
                        Text(String(format: "%.1f초", settings.keystrokeTimeout))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("낯선 모니터 자동 키스트로크") {
                Toggle("낯선 외장 모니터 연결 시 키스트로크 자동 표시", isOn: $settings.autoKeystrokeOnUnknownMonitor)
                Text("회의실·강의실처럼 처음 연결하는 외장 모니터에서 자동으로 키스트로크 표시가 켜집니다. 자주 쓰는 데스크탑 모니터는 아래에서 신뢰 등록해 제외하세요.")
                    .font(.caption2).foregroundColor(.secondary)

                if settings.autoKeystrokeOnUnknownMonitor {
                    if externalMonitors.isEmpty {
                        Text("연결된 외장 모니터 없음").font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(externalMonitors) { mon in
                            Toggle(isOn: Binding(
                                get: { settings.isTrustedMonitor(mon.uuid) },
                                set: { settings.setTrusted(mon.uuid, trusted: $0) }
                            )) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(mon.name)
                                    Text("신뢰 — 이 모니터에서는 자동 활성화 안 함").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section("기타") {
                LabeledContent("커서 숨김 대기") {
                    HStack {
                        Slider(value: $settings.idleTimeout, in: 1...10, step: 0.5)
                        Text(String(format: "%.1f초", settings.idleTimeout))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("정지 시 펄스 강조 (1.5초 멈추면 1회 확장 표시)", isOn: $settings.isIdlePulseEnabled)
                Toggle("스크롤 인디케이터", isOn: $settings.isScrollIndicatorEnabled)
                Toggle("커서 트레일", isOn: $settings.isTrailEnabled)
                Toggle("드래그 앵커 라인 (100pt 또는 1초 이상 드래그 시 자동 표시)", isOn: $settings.isAnchoredLineEnabled)
                Toggle("드래그 코멧 테일 (드래그 중 cursor 뒤 streak)", isOn: $settings.isCometTailEnabled)
                Toggle("드래그 각도 라벨 (도면·일러스트레이션용)", isOn: $settings.isDragAngleLabelEnabled)
                Toggle("우클릭에 링 색상 적용", isOn: $settings.rightClickUsesRingColor)
                Toggle("트랙패드 제스처 효과 (4핀치/3·4 스와이프 — 실험적)", isOn: $settings.isTrackpadGesturesEnabled)
                Toggle("녹화·발표·회의 앱 활성화 시 자동 활성화", isOn: $settings.autoEnableOnRecording)
                Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { v in settings.setLaunchAtLogin(v) }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
        .onAppear {
            launchAtLogin = settings.launchAtLoginEnabled
            externalMonitors = ExternalMonitor.current()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            externalMonitors = ExternalMonitor.current()
        }
    }
}

// MARK: - Magnifier Tab

private struct MagnifierTab: View {
    @ObservedObject var settings: CursorSettings
    @ObservedObject var runtime: CursorRuntimeState

    // zoomOptions 제거 — Slider로 대체 (단축키 ⌃⌥= / ⌃⌥-의 0.5 step과 일관)
    private let sizeOptions: [(CGFloat, String)] = [(160,"작게"), (200,"보통"), (260,"크게"), (320,"매우 크게")]

    var body: some View {
        Form {
            // 권한 안내 — 손쉬운 사용처럼 launch 시 자동 등록되므로 큰 배너 불필요.
            // 한 줄 hint + Settings 링크만.
            if !runtime.hasScreenRecordingPermission {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("화면 녹화 권한 필요 — 시스템 설정에서 활성화")
                            .font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Button("설정 열기") {
                            (NSApp.delegate as? AppDelegate)?.requestScreenRecordingPermission()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section("돋보기 설정") {
                Toggle("돋보기 활성화", isOn: Binding(
                    get: { runtime.isMagnifierActive },
                    set: { newValue in
                        if newValue && !runtime.hasScreenRecordingPermission {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        } else {
                            runtime.isMagnifierActive = newValue
                        }
                    }
                ))

                LabeledContent("배율") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.magnifierZoom, in: 1.5...4.0, step: 0.5)
                            .frame(width: 180)
                        Text(String(format: "%.1f×", settings.magnifierZoom))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                LabeledContent("렌즈 크기") {
                    Picker("크기", selection: $settings.magnifierSize) {
                        ForEach(sizeOptions, id: \.0) { size, label in
                            Text(label).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
            }

            Section {
                Text("단축키: ⌃⌥M으로 돋보기를 켜고 끕니다.\n돋보기는 커서 주변 화면을 실시간으로 확대합니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
    }
}

// MARK: - Shortcuts Tab

private struct ShortcutsTab: View {
    @ObservedObject var settings: CursorSettings

    /// 자기 자신 제외하고 다른 단축키와의 충돌, 또는 reserved 키와의 충돌을 한 줄로 반환. nil = 충돌 없음.
    private func conflictFor(name: String, code: UInt16) -> String? {
        let userConfigurable: [(String, UInt16)] = [
            ("스포트라이트", settings.spotlightKeyCode),
            ("키스트로크", settings.keystrokeShortcutKeyCode),
            ("돋보기", settings.magnifierShortcutKeyCode),
            ("Radial Menu", settings.radialMenuKeyCode),
            ("그리기 모드", settings.drawingKeyCode),
            ("좌표 인스펙터", settings.inspectorKeyCode),
        ]
        if let other = userConfigurable.first(where: { $0.0 != name && $0.1 == code }) {
            return "'\(other.0)' 단축키와 중복"
        }
        // 고정(재정의 불가) 단축키와도 비교 — 색상 1~7, ⌃⌥C(순환), ⌃⌥H(모양 순환), 줌
        let reserved: [(UInt16, String)] = [
            (18,"색상 1"), (19,"색상 2"), (20,"색상 3"), (21,"색상 4"), (23,"색상 5"), (22,"색상 6"), (26,"색상 7 흰"),
            (8,"색 순환"), (4,"모양 순환"), (24,"줌 in"), (27,"줌 out"),
        ]
        if let r = reserved.first(where: { $0.0 == code }) {
            return "고정 단축키 '\(r.1)'와 충돌"
        }
        return nil
    }

    var body: some View {
        Form {
            Section {
                Text("모든 단축키는 ⌃⌥(Control+Option) + 아래 키 조합입니다.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("스포트라이트") {
                KeyRecorder(keyCode: $settings.spotlightKeyCode,
                            conflictMessage: conflictFor(name: "스포트라이트", code: settings.spotlightKeyCode))
            }

            Section("키스트로크 표시") {
                KeyRecorder(keyCode: $settings.keystrokeShortcutKeyCode,
                            conflictMessage: conflictFor(name: "키스트로크", code: settings.keystrokeShortcutKeyCode))
            }

            Section("색상 즉시 변경") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⌃⌥1 노란색 · ⌃⌥2 빨간색 · ⌃⌥3 파란색 · ⌃⌥4 초록색")
                    Text("⌃⌥5 하늘색 · ⌃⌥6 보라색 · ⌃⌥7 흰색")
                    Text("⌃⌥C — 다음 색상으로 순환")
                }
                .font(.caption).foregroundColor(.secondary)
            }

            Section("모양 순환") {
                Text("⌃⌥H — 다음 모양으로 (원형 → 둥근 사각형 → 마름모)")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("화면 좌표 인스펙터") {
                KeyRecorder(keyCode: $settings.inspectorKeyCode,
                            conflictMessage: conflictFor(name: "좌표 인스펙터", code: settings.inspectorKeyCode))
                Text("cursor 옆 (x, y) Quartz 시스템 좌표 표시")
                    .font(.caption2).foregroundColor(.secondary)
            }

            Section("Radial Menu") {
                KeyRecorder(keyCode: $settings.radialMenuKeyCode,
                            conflictMessage: conflictFor(name: "Radial Menu", code: settings.radialMenuKeyCode))
                Text("좌클릭 길게 누름(0.5초)으로도 열림. 8 sector 메뉴, 클릭으로 효과/색/크기 등 즉시 토글, ESC 닫기")
                    .font(.caption2).foregroundColor(.secondary)
            }

            Section("그리기 모드") {
                KeyRecorder(keyCode: $settings.drawingKeyCode,
                            conflictMessage: conflictFor(name: "그리기 모드", code: settings.drawingKeyCode))
                Text("펜·직선·화살표·사각형·타원·형광펜·번호 뱃지 — 모디파이어 조합. 모드 활성 중 Cmd+Z 되돌리기, [/] 두께")
                    .font(.caption2).foregroundColor(.secondary)
            }


            Section("돋보기") {
                KeyRecorder(keyCode: $settings.magnifierShortcutKeyCode,
                            conflictMessage: conflictFor(name: "돋보기", code: settings.magnifierShortcutKeyCode))
                Text("돋보기 켜기/끄기. 줌은 ⌃⌥= / ⌃⌥- (고정)")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
    }
}

// MARK: - Info Tab

private struct InfoTab: View {
    @State private var updateMessage: String = ""
    @State private var checking: Bool = false
    @State private var newerVersion: String? = nil   // 최신 release tag (예: "0.1.2"). nil이면 업데이트 없음.
    // in-app silent upgrade 상태
    @State private var upgrading: Bool = false
    @State private var upgradeStage: String = ""
    @State private var upgradeError: String? = nil
    @State private var upgradeOutput: String = ""

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        Form {
            Section("앱 정보") {
                LabeledContent("버전", value: "v\(appVersion) (\(buildNumber))")
                LabeledContent("개발자", value: "ktoy")
                LabeledContent("최소 요구 사항", value: "macOS 13.0 이상")
            }

            Section("Motion Semantics") {
                VStack(alignment: .leading, spacing: 6) {
                    ShortcutRow(key: "Breathing", desc: "링이 맥박처럼 숨쉼 — 대기 중")
                    ShortcutRow(key: "수축+반동", desc: "클릭 확인됨")
                    ShortcutRow(key: "방향 늘어남", desc: "드래그 진행 중")
                    ShortcutRow(key: "Glow 강화", desc: "1.5초 이상 정지 — 주목 포인트")
                    ShortcutRow(key: "SOS 링", desc: "흔들기 — 커서 위치 알림")
                }
                .padding(.vertical, 2)
            }

            Section("업데이트") {
                if upgrading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(upgradeStage).font(.caption).foregroundColor(.secondary)
                    }
                } else if let error = upgradeError {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error).font(.caption).foregroundColor(.red)
                        if !upgradeOutput.isEmpty {
                            ScrollView {
                                Text(upgradeOutput)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 80)
                            .padding(6)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(4)
                        }
                        HStack(spacing: 8) {
                            Button("Terminal로 재시도") { runUpgradeInTerminal() }
                            Button("Release 페이지") {
                                if let url = URL(string: "https://github.com/kykim79/CursorHighlight/releases/latest") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            Button("닫기") {
                                upgradeError = nil
                                upgradeOutput = ""
                            }
                        }
                    }
                } else {
                    if !updateMessage.isEmpty {
                        Text(updateMessage).font(.caption).foregroundColor(.secondary)
                    }
                    HStack(spacing: 8) {
                        Button(checking ? "확인 중..." : "업데이트 확인") {
                            Task { await checkForUpdate() }
                        }
                        .disabled(checking)
                        if newerVersion != nil {
                            Button("지금 업데이트") { runHomebrewUpgrade() }
                                .buttonStyle(.borderedProminent)
                            Button("Release 페이지") {
                                if let url = URL(string: "https://github.com/kykim79/CursorHighlight/releases/latest") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
    }

    /// GitHub Releases API에서 latest tag 조회 후 appVersion과 비교.
    /// 비교는 numeric option (0.1.10 > 0.1.2 정확히 처리).
    private func checkForUpdate() async {
        checking = true
        newerVersion = nil
        defer { checking = false }
        let url = URL(string: "https://api.github.com/repos/kykim79/CursorHighlight/releases/latest")!
        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                updateMessage = "확인 실패: 서버 응답 \((response as? HTTPURLResponse)?.statusCode ?? -1)"
                return
            }
            struct Release: Decodable { let tag_name: String }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latestVersion = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            switch appVersion.compare(latestVersion, options: .numeric) {
            case .orderedSame:
                updateMessage = "✓ 최신 버전입니다 (v\(appVersion))"
            case .orderedAscending:
                newerVersion = latestVersion
                updateMessage = "📥 새 버전 v\(latestVersion) 사용 가능 (현재 v\(appVersion))"
            case .orderedDescending:
                updateMessage = "⚠️ 로컬 버전(v\(appVersion))이 최신 release(v\(latestVersion))보다 높습니다 — 개발 빌드"
            }
        } catch {
            updateMessage = "확인 실패: \(error.localizedDescription)"
        }
    }

    /// "지금 업데이트" 버튼 — silent in-app brew upgrade. 진행 spinner + stage label.
    /// 성공 시 자동 재시작. 실패 시 brew 출력 표시 + Terminal fallback 버튼 노출.
    private func runHomebrewUpgrade() {
        upgrading = true
        upgradeStage = "업데이트 시작..."
        upgradeError = nil
        upgradeOutput = ""
        Task {
            // LSUIElement 앱은 PATH가 최소라 brew 절대 경로 명시.
            // Apple Silicon: /opt/homebrew/bin/brew, Intel: /usr/local/bin/brew
            let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            guard let brewPath = brewPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                upgrading = false
                upgradeError = "Homebrew를 찾을 수 없습니다 (/opt/homebrew/bin/brew 또는 /usr/local/bin/brew). Release 페이지에서 zip을 직접 다운로드하세요."
                return
            }
            do {
                let result = try await runBrewUpgrade(brewPath: brewPath)
                upgrading = false
                if result.exitCode == 0 {
                    upgradeStage = "✓ v\(newerVersion ?? "") 설치 완료. 곧 재시작됩니다..."
                    // re-enable spinner 영역에 success 메시지 잠깐 표시
                    upgrading = true
                    try? await Task.sleep(for: .milliseconds(1500))
                    relaunchApp()
                } else {
                    upgradeError = "업데이트 실패 (exit \(result.exitCode))"
                    // brew 출력은 길 수 있어 마지막 부분만 잘라 표시
                    upgradeOutput = String(result.output.suffix(800))
                }
            } catch {
                upgrading = false
                upgradeError = "실행 실패: \(error.localizedDescription)"
            }
        }
    }

    private struct BrewResult { let exitCode: Int32; let output: String }

    /// brew upgrade를 Process로 실행, stdout/stderr 합쳐 capture.
    /// `process.waitUntilExit()`이 blocking이라 Task.detached로 분리.
    /// stage 업데이트는 출력 stream을 line 단위로 읽어 키워드 매칭.
    private func runBrewUpgrade(brewPath: String) async throws -> BrewResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = ["upgrade", "--cask", "kykim79/tap/cursorhighlight"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        // HOMEBREW_AUTO_UPDATE_SECS=0 — brew의 auto-update 24시간 interval을 0으로 강제,
        // 매 호출마다 tap을 fetch. v0.2.5~0.2.7은 interval 안에 들면 tap 못 받아 "이미 latest"
        // 잘못 판단하는 회귀. 5-10초 추가되지만 silent UX에서 한 번이라 trade-off 받아들임.
        // NO_ANALYTICS + NO_ENV_HINTS는 출력 노이즈만 줄이는 무해 옵션.
        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_AUTO_UPDATE_SECS"] = "0"
        env["HOMEBREW_NO_ANALYTICS"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        process.environment = env

        // 출력 stream 읽기 — readabilityHandler로 line별 stage 업데이트
        var collectedOutput = ""
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            collectedOutput += chunk
            // 메인 스레드에서 stage 추정
            let stage = Self.inferStage(from: chunk)
            if let stage {
                Task { @MainActor in self.upgradeStage = stage }
            }
        }

        try process.run()
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                handle.readabilityHandler = nil
                continuation.resume(returning: BrewResult(exitCode: proc.terminationStatus, output: collectedOutput))
            }
        }
    }

    /// brew 출력에서 진행 stage 추정 — 한국어 사용자용 친화 라벨.
    private static func inferStage(from chunk: String) -> String? {
        if chunk.contains("Auto-updating Homebrew") || chunk.contains("Updated") && chunk.contains("tap") { return "Homebrew 갱신 중..." }
        if chunk.contains("Fetching") { return "다운로드 중..." }
        if chunk.contains("Verified") { return "검증 중..." }
        if chunk.contains("Uninstalling") || chunk.contains("Removing") { return "이전 버전 제거 중..." }
        if chunk.contains("Moving") || chunk.contains("Installing") { return "설치 중..." }
        if chunk.contains("successfully upgraded") || chunk.contains("successfully installed") { return "마무리 중..." }
        return nil
    }

    /// 업데이트 완료 후 자기 자신 재시작 — open -n 으로 새 instance 띄우고 현재 process 종료.
    /// /Applications에 이미 brew가 새 .app을 cp한 상태.
    private func relaunchApp() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-n", "/Applications/CursorHighlight.app"]
        do {
            try proc.run()
            // open이 새 instance를 띄울 시간을 잠깐 주고 종료
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.terminate(nil)
            }
        } catch {
            upgrading = false
            upgradeError = "재시작 실패: \(error.localizedDescription)"
        }
    }

    /// in-app upgrade 실패 시 fallback — 기존 Terminal script 흐름.
    /// brew가 stuck/대화형 prompt 요구 같은 edge case에 사용자가 직접 진행 가능.
    private func runUpgradeInTerminal() {
        upgradeError = nil
        upgradeOutput = ""
        let scriptPath = NSTemporaryDirectory() + "cursorhighlight-upgrade.sh"
        let script = """
        #!/bin/zsh
        echo "▶ CursorHighlight 업데이트 (Terminal fallback)"
        echo "  명령: brew upgrade --cask kykim79/tap/cursorhighlight"
        echo
        if brew upgrade --cask kykim79/tap/cursorhighlight; then
            echo
            echo "✓ 업데이트 완료. CursorHighlight를 재시작합니다..."
            pkill -x CursorHighlight 2>/dev/null
            sleep 0.5
            open -a CursorHighlight
            echo "  재시작됨."
        else
            echo
            echo "✗ 업데이트 실패. 위 출력을 확인하세요."
        fi
        echo
        read "?[Enter를 눌러 이 창을 닫기] "
        """
        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", "Terminal", scriptPath]
            try proc.run()
        } catch {
            upgradeError = "Terminal 실행 실패: \(error.localizedDescription)"
        }
    }
}

private struct ShortcutRow: View {
    let key: String
    let desc: String
    var body: some View {
        HStack {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 90, alignment: .leading)
            Text(desc).font(.caption).foregroundColor(.secondary)
        }
    }
}

// MARK: - 단축키 자유 입력 (Key Recorder)

/// 클릭 후 키 누르면 keyCode를 binding에 저장. ESC = cancel.
/// 모디파이어(⌃⌥)는 implicit — main key만 캡처. 환경설정 윈도우 안에서만 동작 (NSEvent local monitor).
struct KeyRecorder: View {
    @Binding var keyCode: UInt16
    let conflictMessage: String?
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Text(isRecording ? "키 누르세요..." : "⌃⌥ \(KeyCodeMap.label(for: keyCode))")
                        .font(.system(.body, design: .monospaced))
                    if isRecording {
                        Text("ESC 취소").font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minWidth: 180, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            if let conflictMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(conflictMessage)
                }
                .font(.caption2)
                .foregroundColor(.orange)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggle() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 {  // ESC
                stopRecording()
                return nil
            }
            keyCode = event.keyCode
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}

/// macOS Virtual Keycode → 표시 라벨. kVK_ANSI 표준 매핑.
enum KeyCodeMap {
    static func label(for code: UInt16) -> String {
        let map: [UInt16: String] = [
            0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
            11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T",
            18:"1", 19:"2", 20:"3", 21:"4", 22:"6", 23:"5", 25:"9", 26:"7", 28:"8", 29:"0",
            24:"=", 27:"-", 30:"]", 33:"[",
            31:"O", 32:"U", 34:"I", 35:"P", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M",
            39:"'", 41:";", 43:",", 44:"/", 47:".", 50:"`",
            36:"⏎", 48:"⇥", 49:"Space", 51:"⌫", 53:"⎋", 76:"↩",
        ]
        return map[code] ?? "0x\(String(code, radix: 16, uppercase: true))"
    }
}
