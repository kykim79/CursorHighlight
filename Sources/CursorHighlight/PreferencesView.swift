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

            Section("기타") {
                LabeledContent("커서 숨김 대기") {
                    HStack {
                        Slider(value: $settings.idleTimeout, in: 1...10, step: 0.5)
                        Text(String(format: "%.1f초", settings.idleTimeout))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("스크롤 인디케이터", isOn: $settings.isScrollIndicatorEnabled)
                Toggle("커서 트레일", isOn: $settings.isTrailEnabled)
                Toggle("드래그 앵커 라인 (100pt 또는 1초 이상 드래그 시 자동 표시)", isOn: $settings.isAnchoredLineEnabled)
                Toggle("드래그 컴맷 테일 (드래그 중 cursor 뒤 streak)", isOn: $settings.isCometTailEnabled)
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
        .onAppear { launchAtLogin = settings.launchAtLoginEnabled }
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

    private let spotlightOptions: [(UInt16, String)] = [(1,"S"), (3,"F"), (18,"1"), (5,"G")]
    private let keystrokeOptions: [(UInt16, String)] = [(40,"K"), (37,"L"), (19,"2"), (32,"U")]

    var body: some View {
        Form {
            Section {
                Text("모든 단축키는 ⌃⌥(Control+Option) + 아래 키 조합입니다.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("스포트라이트") {
                Picker("키", selection: $settings.spotlightKeyCode) {
                    ForEach(spotlightOptions, id: \.0) { code, key in
                        Text("⌃⌥\(key)").tag(code)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            Section("키스트로크 표시") {
                Picker("키", selection: $settings.keystrokeShortcutKeyCode) {
                    ForEach(keystrokeOptions, id: \.0) { code, key in
                        Text("⌃⌥\(key)").tag(code)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            Section("색상 즉시 변경") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("⌃⌥1 노란색 · ⌃⌥2 빨간색 · ⌃⌥3 파란색")
                    Text("⌃⌥4 초록색 · ⌃⌥5 하늘색 · ⌃⌥6 보라색")
                }
                .font(.caption).foregroundColor(.secondary)
            }

            Section("돋보기") {
                Text("⌃⌥M — 돋보기 켜기/끄기")
                    .font(.caption).foregroundColor(.secondary)
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
