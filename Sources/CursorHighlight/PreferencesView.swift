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
                Toggle("우클릭에 링 색상 적용", isOn: $settings.rightClickUsesRingColor)
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

    private let zoomOptions: [(Double, String)] = [(1.5,"1.5×"), (2.0,"2×"), (3.0,"3×"), (4.0,"4×")]
    private let sizeOptions: [(CGFloat, String)] = [(160,"작게"), (200,"보통"), (260,"크게"), (320,"매우 크게")]

    var body: some View {
        Form {
            if !runtime.hasScreenRecordingPermission {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("화면 녹화 권한이 필요합니다.")
                                .font(.callout).fontWeight(.medium)
                            Text("시스템 설정 → 개인 정보 보호 → 화면 녹화에서 허용 후 앱을 재시작하세요.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("권한 요청") {
                            (NSApp.delegate as? AppDelegate)?.requestScreenRecordingPermission()
                        }
                    }
                    .padding(.vertical, 2)
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
                    Picker("배율", selection: $settings.magnifierZoom) {
                        ForEach(zoomOptions, id: \.0) { zoom, label in
                            Text(label).tag(zoom)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
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
                if newerVersion != nil {
                    Text("「지금 업데이트」는 Terminal에서 `brew upgrade --cask kykim79/tap/cursorhighlight`를 실행합니다. Homebrew 미사용 시 Release 페이지에서 zip 다운로드.")
                        .font(.caption2).foregroundColor(.secondary)
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

    /// "지금 업데이트" 버튼 — 임시 shell script 만든 후 Terminal.app으로 명시적으로 열어 실행.
    /// `/usr/bin/open -a Terminal` 사용 — .sh default handler가 다른 앱(VS Code 등)으로 바뀌어도 안정.
    /// 사용자 zsh 환경(PATH, brew 위치)을 그대로 받아 Apple Silicon/Intel 모두 동작.
    private func runHomebrewUpgrade() {
        let scriptPath = NSTemporaryDirectory() + "cursorhighlight-upgrade.sh"
        let script = """
        #!/bin/zsh
        echo "▶ CursorHighlight 업데이트"
        echo "  명령: brew upgrade --cask kykim79/tap/cursorhighlight"
        echo
        brew upgrade --cask kykim79/tap/cursorhighlight
        status=$?
        echo
        if [ $status -eq 0 ]; then
            echo "✓ 업데이트 완료. CursorHighlight를 종료 후 다시 실행하세요."
            echo "  pkill -x CursorHighlight && open -a CursorHighlight"
        else
            echo "✗ 업데이트 실패 (exit $status). 위 출력을 확인하세요."
        fi
        echo
        read "?[Enter를 눌러 이 창을 닫기] "
        """
        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
        } catch {
            updateMessage = "스크립트 생성 실패: \(error.localizedDescription)"
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", "Terminal", scriptPath]
        do {
            try proc.run()
        } catch {
            updateMessage = "Terminal 실행 실패: \(error.localizedDescription)"
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
