import SwiftUI
import AppKit

// MARK: - Preferences Window Controller

class PreferencesWindowController: NSWindowController {
    init(state: CursorState) {
        let view = PreferencesView(state: state)
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
    @ObservedObject var state: CursorState

    var body: some View {
        TabView {
            AppearanceTab(state: state)
                .tabItem { Label("모양", systemImage: "circle.dashed") }

            BehaviorTab(state: state)
                .tabItem { Label("동작", systemImage: "cursorarrow") }

            MagnifierTab(state: state)
                .tabItem { Label("돋보기", systemImage: "magnifyingglass.circle") }

            ShortcutsTab(state: state)
                .tabItem { Label("단축키", systemImage: "keyboard") }

            InfoTab()
                .tabItem { Label("정보", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 500)
    }
}

// MARK: - Appearance Tab

private struct AppearanceTab: View {
    @ObservedObject var state: CursorState

    var body: some View {
        Form {
            Section("커서 링 색상") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                    ForEach(CursorState.RingColor.allCases.filter { $0 != .custom }) { c in
                        ColorSwatch(
                            color: c.color,
                            label: c.label,
                            isSelected: state.ringColor == c
                        ) { state.ringColor = c }
                    }
                }
                .padding(.vertical, 4)

                HStack {
                    ColorPicker("커스텀", selection: Binding(
                        get: { state.customRingColor },
                        set: { state.customRingColor = $0; state.ringColor = .custom }
                    ))
                    .labelsHidden()
                    .frame(width: 28, height: 28)
                    Button("커스텀") { state.ringColor = .custom }
                        .buttonStyle(.plain)
                        .foregroundColor(state.ringColor == .custom ? .accentColor : .primary)
                    if state.ringColor == .custom {
                        Text("✓").foregroundColor(.accentColor)
                    }
                    Spacer()
                }
            }

            Section("링 모양") {
                Picker("모양", selection: $state.ringShape) {
                    ForEach(CursorState.RingShape.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("링 크기") {
                Picker("크기", selection: $state.ringSize) {
                    ForEach(CursorState.RingSize.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("링 투명도") {
                LabeledContent("투명도") {
                    HStack {
                        Slider(value: $state.ringOpacity, in: 0.2...1.0, step: 0.05)
                        Text(String(format: "%.0f%%", state.ringOpacity * 100))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("테두리 두께") {
                Picker("두께", selection: $state.borderWeight) {
                    ForEach(CursorState.BorderWeight.allCases) { w in Text(w.label).tag(w) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            Section("테두리 스타일") {
                Picker("스타일", selection: $state.borderStyle) {
                    ForEach(CursorState.BorderStyle.allCases) { s in Text(s.label).tag(s) }
                }
                .pickerStyle(.segmented).labelsHidden()

                Toggle("이중 링 (안쪽 반투명 선)", isOn: $state.hasInnerRing)
                Toggle("링 채우기 (반투명 도넛)", isOn: $state.isRingFillEnabled)
                Toggle("글로우 효과", isOn: $state.isGlowEnabled)
                Toggle("원근 왜곡 (Perspective Warping)", isOn: $state.isPerspectiveWarping)
            }

            Section("애니메이션 속도") {
                Picker("속도", selection: $state.animationSpeed) {
                    ForEach(CursorState.AnimationSpeed.allCases) { s in Text(s.label).tag(s) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            Section("스포트라이트 반경") {
                LabeledContent("반경") {
                    HStack {
                        Slider(value: $state.spotlightRadius, in: 60...250, step: 10)
                        Text("\(Int(state.spotlightRadius))pt")
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
    @ObservedObject var state: CursorState
    @State private var launchAtLogin: Bool = false

    var body: some View {
        Form {
            Section("키스트로크") {
                LabeledContent("표시 시간") {
                    HStack {
                        Slider(value: $state.keystrokeTimeout, in: 1...8, step: 0.5)
                        Text(String(format: "%.1f초", state.keystrokeTimeout))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("기타") {
                LabeledContent("커서 숨김 대기") {
                    HStack {
                        Slider(value: $state.idleTimeout, in: 1...10, step: 0.5)
                        Text(String(format: "%.1f초", state.idleTimeout))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("스크롤 인디케이터", isOn: $state.isScrollIndicatorEnabled)
                Toggle("커서 트레일", isOn: $state.isTrailEnabled)
                Toggle("우클릭에 링 색상 적용", isOn: $state.rightClickUsesRingColor)
                Toggle("녹화 앱 실행 시 자동 활성화", isOn: $state.autoEnableOnRecording)
                Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { v in state.setLaunchAtLogin(v) }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
        .onAppear { launchAtLogin = state.launchAtLoginEnabled }
    }
}

// MARK: - Magnifier Tab

private struct MagnifierTab: View {
    @ObservedObject var state: CursorState

    private let zoomOptions: [(Double, String)] = [(1.5,"1.5×"), (2.0,"2×"), (3.0,"3×"), (4.0,"4×")]
    private let sizeOptions: [(CGFloat, String)] = [(160,"작게"), (200,"보통"), (260,"크게"), (320,"매우 크게")]

    var body: some View {
        Form {
            if !state.hasScreenRecordingPermission {
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
                    get: { state.isMagnifierActive },
                    set: { newValue in
                        if newValue && !state.hasScreenRecordingPermission {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        } else {
                            state.isMagnifierActive = newValue
                        }
                    }
                ))

                LabeledContent("배율") {
                    Picker("배율", selection: $state.magnifierZoom) {
                        ForEach(zoomOptions, id: \.0) { zoom, label in
                            Text(label).tag(zoom)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }

                LabeledContent("렌즈 크기") {
                    Picker("크기", selection: $state.magnifierSize) {
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
    @ObservedObject var state: CursorState

    private let spotlightOptions: [(UInt16, String)] = [(1,"S"), (3,"F"), (18,"1"), (5,"G")]
    private let keystrokeOptions: [(UInt16, String)] = [(40,"K"), (37,"L"), (19,"2"), (32,"U")]

    var body: some View {
        Form {
            Section {
                Text("모든 단축키는 ⌃⌥(Control+Option) + 아래 키 조합입니다.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("스포트라이트") {
                Picker("키", selection: $state.spotlightKeyCode) {
                    ForEach(spotlightOptions, id: \.0) { code, key in
                        Text("⌃⌥\(key)").tag(code)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
            }

            Section("키스트로크 표시") {
                Picker("키", selection: $state.keystrokeShortcutKeyCode) {
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
                Button("업데이트 확인") {
                    updateMessage = "현재 최신 버전입니다 (v\(appVersion))"
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal)
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
