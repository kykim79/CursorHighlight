import SwiftUI
import AppKit

// MARK: - Preferences Window Controller

/// 현재 선택된 탭 — NSToolbar(AppKit)와 SwiftUI 본문이 같은 source 공유.
@MainActor
final class PrefSelection: ObservableObject {
    @Published var tab: PrefTab = .appearance
}

class PreferencesWindowController: NSWindowController, NSToolbarDelegate {
    let selection = PrefSelection()

    init(settings: CursorSettings, runtime: CursorRuntimeState) {
        let view = PreferencesView(settings: settings, runtime: runtime, selection: selection)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 520, height: 580)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Cluxo 환경설정"
        window.contentView = hosting
        window.center()
        window.isReleasedWhenClosed = false
        // macOS System Settings 표준 toolbar — 큰 SF Symbol + 작은 라벨, 선택 시 accent 강조.
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .preference
        }

        super.init(window: window)

        let toolbar = NSToolbar(identifier: "ClixPrefToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier(PrefTab.appearance.rawValue)
        window.toolbar = toolbar
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        PrefTab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = PrefTab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.label
        item.paletteLabel = tab.label
        item.image = NSImage(systemSymbolName: tab.icon, accessibilityDescription: tab.label)
        item.target = self
        item.action = #selector(selectTab(_:))
        return item
    }

    @objc private func selectTab(_ sender: NSToolbarItem) {
        guard let tab = PrefTab(rawValue: sender.itemIdentifier.rawValue) else { return }
        selection.tab = tab
    }
}

// MARK: - Preferences View

/// 환경설정 탭. SwiftUI TabView가 macOS에서 자동으로 NSToolbar를 만들지 않아
/// reference(MonitorControl 환경설정)처럼 큰 SF Symbol + 라벨이 안 보임 →
/// 자체 segmented tab bar로 직접 구현.
enum PrefTab: String, CaseIterable, Identifiable {
    case appearance, behavior, magnifier, shortcuts, info
    var id: String { rawValue }
    var label: String {
        switch self {
        case .appearance: return "모양"
        case .behavior:   return "동작"
        case .magnifier:  return "돋보기"
        case .shortcuts:  return "단축키"
        case .info:       return "정보"
        }
    }
    var icon: String {
        switch self {
        case .appearance: return "paintpalette.fill"
        case .behavior:   return "cursorarrow.motionlines"
        case .magnifier:  return "plus.magnifyingglass"
        case .shortcuts:  return "keyboard.fill"
        case .info:       return "info.circle.fill"
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var settings: CursorSettings
    @ObservedObject var runtime: CursorRuntimeState
    @ObservedObject var selection: PrefSelection

    var body: some View {
        // 상단 toolbar는 NSToolbar(PreferencesWindowController)가 처리. SwiftUI는 본문만.
        Group {
            switch selection.tab {
            case .appearance: AppearanceTab(settings: settings)
            case .behavior:   BehaviorTab(settings: settings)
            case .magnifier:  MagnifierTab(settings: settings, runtime: runtime)
            case .shortcuts:  ShortcutsTab(settings: settings)
            case .info:       InfoTab(settings: settings)
            }
        }
        .frame(width: 520, height: 580)
    }
}

// MARK: - Appearance Tab

/// Tailscale 패턴 — 좌측 라벨 + 우측 옵션 그룹. 카드 박스 없이 깔끔.
private struct PrefSection<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(verbatim: "\(label):")
                .frame(width: 100, alignment: .trailing)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            Spacer(minLength: 0)
        }
    }
}

/// 설명 텍스트 — 옵션 아래 secondary, callout(12pt). verbatim으로 markdown 회피.
private func desc(_ text: String) -> some View {
    Text(verbatim: text)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
}

private struct AppearanceTab: View {
    @ObservedObject var settings: CursorSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PrefSection(label: "색상") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 10) {
                        ForEach(CursorSettings.RingColor.allCases.filter { $0 != .custom }) { c in
                            ColorSwatch(color: c.color, label: c.label, isSelected: settings.ringColor == c) {
                                settings.ringColor = c
                            }
                        }
                        ColorSwatch(color: settings.customRingColor, label: "커스텀", isSelected: settings.ringColor == .custom) {
                            settings.ringColor = .custom
                        }
                    }
                    if settings.ringColor == .custom {
                        ColorPicker("커스텀 색상", selection: $settings.customRingColor)
                    }
                    desc("마우스 커서 주변 링의 기본 색. ⌃⌥1~6 단축키 또는 라디얼 메뉴(⌃⌥,)로 빠르게 전환. 클릭/드래그/그리기 등 모든 강조 효과가 이 색을 따릅니다.")
                }

                PrefSection(label: "모양") {
                    Picker("모양", selection: $settings.ringShape) {
                        ForEach(CursorSettings.RingShape.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    desc("원형이 가장 자연스럽습니다. 둥근 사각형은 코드 영역 강조, 마름모는 시선 집중도가 가장 높습니다.")
                }

                PrefSection(label: "크기") {
                    Picker("크기", selection: $settings.ringSize) {
                        ForEach(CursorSettings.RingSize.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    desc("발표 화면 크기와 시청자 거리에 맞춰 선택. 4K·대형 디스플레이일수록 큰 크기 권장.")
                }

                PrefSection(label: "투명도") {
                    HStack {
                        Slider(value: $settings.ringOpacity, in: 0.2...1.0, step: 0.05)
                        Text(String(format: "%.0f%%", settings.ringOpacity * 100))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                    desc("100%는 명확하지만 아래 콘텐츠를 가립니다. 80~90% 정도면 콘텐츠도 보이면서 강조 효과 유지.")
                }

                PrefSection(label: "테두리 두께") {
                    Picker("두께", selection: $settings.borderWeight) {
                        ForEach(CursorSettings.BorderWeight.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    desc("얇은 테두리는 미니멀한 인상, 굵은 테두리는 멀리서도 잘 보입니다.")
                }

                PrefSection(label: "테두리 스타일") {
                    Picker("스타일", selection: $settings.borderStyle) {
                        ForEach(CursorSettings.BorderStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()

                    Toggle("이중 링", isOn: $settings.hasInnerRing)
                    desc("메인 링 안쪽에 반투명 보조 선을 추가해 두께감 보강.")

                    Toggle("링 채우기 (반투명 도넛)", isOn: $settings.isRingFillEnabled)
                    desc("링 안쪽을 반투명 링 색으로 채워 도넛 형태로. 흰 배경에서도 잘 보입니다.")

                    Toggle("글로우 효과", isOn: $settings.isGlowEnabled)
                    desc("링 주변에 부드러운 빛 번짐. 시각 무게 ↑, 멀리서도 인지 쉬움.")

                    Toggle("원근 왜곡", isOn: $settings.isPerspectiveWarping)
                    desc("드래그 방향에 따라 링이 살짝 기울어지는 입체감 효과.")
                }

                PrefSection(label: "애니메이션 속도") {
                    Picker("속도", selection: $settings.animationSpeed) {
                        ForEach(CursorSettings.AnimationSpeed.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    desc("클릭·드래그·정지 펄스 등 모든 모션 재생 속도. 발표 중엔 보통, 빠른 시연엔 빠름.")
                }

                PrefSection(label: "스포트라이트 반경") {
                    HStack {
                        Slider(value: $settings.spotlightRadius, in: 60...250, step: 10)
                        Text("\(Int(settings.spotlightRadius))pt")
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                    desc("⌃⌥S 스포트라이트가 비추는 원의 반지름. 코드 한 줄엔 작게(60~100), UI 영역엔 크게(180~220).")
                }
            }
            .padding(24)
        }
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
                    // 항상 얇은 회색 외곽선 — 흰색 swatch도 배경(흰색 환경설정)과 구분되게.
                    .overlay(Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 1))
                    // 선택 시 더 두꺼운 accent 외곽선으로 강조
                    .overlay(
                        Circle()
                            .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                    )
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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PrefSection(label: "키스트로크") {
                    HStack {
                        Text(verbatim: "표시 시간").frame(width: 70, alignment: .leading)
                        Slider(value: $settings.keystrokeTimeout, in: 1...8, step: 0.5)
                        Text(String(format: "%.1f초", settings.keystrokeTimeout))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                    desc("키 입력 후 화면 하단 오버레이에 표시되는 시간. 빠른 시연엔 1~2초, 천천히 보여주는 발표엔 3~5초 권장.")
                }

                PrefSection(label: "자동 키스트로크") {
                    Toggle("낯선 외장 모니터 연결 시 자동 표시", isOn: $settings.autoKeystrokeOnUnknownMonitor)
                    desc("회의실·강의실처럼 처음 연결하는 외장 모니터에서 자동으로 키스트로크 표시가 켜집니다. 자주 쓰는 데스크탑 모니터는 아래에서 신뢰 등록해 제외하세요.")

                    if settings.autoKeystrokeOnUnknownMonitor {
                        if externalMonitors.isEmpty {
                            Text(verbatim: "연결된 외장 모니터 없음")
                                .font(.callout).foregroundColor(.secondary)
                        } else {
                            ForEach(externalMonitors) { mon in
                                Toggle(isOn: Binding(
                                    get: { settings.isTrustedMonitor(mon.uuid) },
                                    set: { settings.setTrusted(mon.uuid, trusted: $0) }
                                )) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(verbatim: mon.name)
                                        Text(verbatim: "신뢰 — 이 모니터에서는 자동 활성화 안 함")
                                            .font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                PrefSection(label: "커서 숨김") {
                    HStack {
                        Text(verbatim: "대기 시간").frame(width: 70, alignment: .leading)
                        Slider(value: $settings.idleTimeout, in: 1...10, step: 0.5)
                        Text(String(format: "%.1f초", settings.idleTimeout))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                    desc("마우스를 안 움직인 후 링이 페이드 아웃되기까지 대기 시간. 발표 중엔 길게(5초+) 권장.")
                }

                PrefSection(label: "드래그 효과") {
                    Toggle("드래그 앵커 라인", isOn: $settings.isAnchoredLineEnabled)
                    desc("100pt 또는 1초 이상 드래그 시 시작점에서 cursor까지 점선 표시. 영역 선택 시연에 유용.")

                    Toggle("코멧 테일", isOn: $settings.isCometTailEnabled)
                    desc("드래그 중 cursor 뒤로 streak. 빠른 드래그 방향이 시각적으로 잘 보임.")

                    Toggle("각도 라벨", isOn: $settings.isDragAngleLabelEnabled)
                    desc("드래그 중 cursor 옆에 회전 각도(°) 표시. 도면·일러스트레이션 작업용.")

                    Toggle("우클릭에 링 색상 적용", isOn: $settings.rightClickUsesRingColor)
                    desc("기본 오렌지 우클릭 ripple을 링 색으로 통일.")
                }

                PrefSection(label: "기타 효과") {
                    Toggle("정지 시 펄스 강조", isOn: $settings.isIdlePulseEnabled)
                    desc("1.5초 멈추면 1회 확장 표시. \"여기 보세요\" 자연스러운 강조.")

                    Toggle("스크롤 인디케이터", isOn: $settings.isScrollIndicatorEnabled)
                    desc("스크롤 방향 화살표(↑↓←→) + 진폭 비례 크기 표시.")

                    Toggle("커서 트레일", isOn: $settings.isTrailEnabled)
                    desc("커서 이동 자취를 잔상으로 남김. 빠른 움직임 인식 ↑.")

                    Toggle("트랙패드 제스처 효과 (실험적)", isOn: $settings.isTrackpadGesturesEnabled)
                    desc("4핀치·3/4 스와이프 등 시스템 제스처에 시각 피드백. 비공식 API라 실험적.")
                }

                PrefSection(label: "시스템") {
                    Toggle("녹화·발표·회의 앱 활성화 시 자동 활성화", isOn: $settings.autoEnableOnRecording)
                    desc("OBS·Zoom·Keynote 등을 켤 때 Cluxo가 자동으로 활성화됩니다.")

                    Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { v in settings.setLaunchAtLogin(v) }
                    desc("Mac 로그인 후 Cluxo가 자동으로 시작됩니다.")
                }
            }
            .padding(24)
        }
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

    private let sizeOptions: [(CGFloat, String)] = [(160,"작게"), (200,"보통"), (260,"크게"), (320,"매우 크게")]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !runtime.hasScreenRecordingPermission {
                    PrefSection(label: "권한") {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle").foregroundColor(.orange)
                            Text(verbatim: "화면 녹화 권한 필요")
                            Spacer()
                            Button("설정 열기") {
                                (NSApp.delegate as? AppDelegate)?.requestScreenRecordingPermission()
                            }
                            .controlSize(.small)
                        }
                        desc("돋보기 기능이 커서 주변 화면을 캡처하려면 화면 녹화 권한이 필요합니다. 시스템 설정 → 개인정보 보호 및 보안 → 화면 녹화에서 Cluxo 활성화.")
                    }
                }

                PrefSection(label: "활성화") {
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
                    desc("⌃⌥M 단축키 또는 라디얼 메뉴(⌃⌥,)로도 토글 가능. 돋보기는 커서 주변 화면을 실시간 확대합니다.")
                }

                PrefSection(label: "배율") {
                    HStack(spacing: 8) {
                        Slider(value: $settings.magnifierZoom, in: 1.5...4.0, step: 0.5)
                        Text(String(format: "%.1f×", settings.magnifierZoom))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 44, alignment: .trailing)
                    }
                    desc("확대 배율 (1.5× ~ 4.0×). 발표 중 ⌃⌥= / ⌃⌥- 단축키로 0.5 step 빠르게 조절 가능.")
                }

                PrefSection(label: "렌즈 크기") {
                    Picker("크기", selection: $settings.magnifierSize) {
                        ForEach(sizeOptions, id: \.0) { size, label in
                            Text(label).tag(size)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    desc("렌즈(원/링)의 직경. 코드 한 줄 강조엔 작게, 영역 강조엔 크게 권장.")
                }
            }
            .padding(24)
        }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PrefSection(label: "안내") {
                    desc("모든 단축키는 ⌃⌥ (Control+Option) + 아래 키 조합입니다. 클릭하고 원하는 키를 누르세요. ESC로 캡처 취소.")
                }

                PrefSection(label: "스포트라이트") {
                    KeyRecorder(keyCode: $settings.spotlightKeyCode,
                                conflictMessage: conflictFor(name: "스포트라이트", code: settings.spotlightKeyCode))
                    desc("커서 주변만 밝게, 나머지는 어둡게 처리해 시선을 모읍니다.")
                }

                PrefSection(label: "돋보기") {
                    KeyRecorder(keyCode: $settings.magnifierShortcutKeyCode,
                                conflictMessage: conflictFor(name: "돋보기", code: settings.magnifierShortcutKeyCode))
                    desc("커서 주변 화면을 실시간 확대. 줌 조절은 ⌃⌥= / ⌃⌥- 고정 단축키.")
                }

                PrefSection(label: "키스트로크 표시") {
                    KeyRecorder(keyCode: $settings.keystrokeShortcutKeyCode,
                                conflictMessage: conflictFor(name: "키스트로크", code: settings.keystrokeShortcutKeyCode))
                    desc("누른 키를 화면 하단에 오버레이로 표시. 발표·녹화 중 단축키 시연용.")
                }

                PrefSection(label: "좌표 인스펙터") {
                    KeyRecorder(keyCode: $settings.inspectorKeyCode,
                                conflictMessage: conflictFor(name: "좌표 인스펙터", code: settings.inspectorKeyCode))
                    desc("cursor 옆에 (x, y) Quartz 시스템 좌표 표시. UI 디자인·디버깅용.")
                }

                PrefSection(label: "라디얼 메뉴") {
                    KeyRecorder(keyCode: $settings.radialMenuKeyCode,
                                conflictMessage: conflictFor(name: "Radial Menu", code: settings.radialMenuKeyCode))
                    desc("8 sector 마우스 메뉴. 좌클릭 길게 누름(0.5초)으로도 열림. 클릭으로 효과/색/크기 즉시 토글, ESC 닫기.")
                }

                PrefSection(label: "그리기 모드") {
                    KeyRecorder(keyCode: $settings.drawingKeyCode,
                                conflictMessage: conflictFor(name: "그리기 모드", code: settings.drawingKeyCode))
                    desc("펜·직선·화살표·사각형·타원·형광펜·번호 뱃지 — 모디파이어 조합. 모드 활성 중 Cmd+Z 되돌리기, [/] 두께 조절.")
                }

                PrefSection(label: "고정 단축키") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "⌃⌥1~7 — 색상 즉시 변경 (노란/빨간/파란/초록/하늘/보라/흰)")
                        Text(verbatim: "⌃⌥C — 다음 색상으로 순환")
                        Text(verbatim: "⌃⌥H — 다음 모양으로 순환 (원형 → 둥근 사각형 → 마름모)")
                        Text(verbatim: "⌃⌥= / ⌃⌥- — 돋보기 줌 in/out (0.5 step)")
                    }
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Info Tab

private struct InfoTab: View {
    @ObservedObject var settings: CursorSettings
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
            Section("표시 언어") {
                Picker(selection: $settings.preferredLanguage) {
                    ForEach(CursorSettings.PreferredLanguage.allCases) { lang in
                        Text(verbatim: lang.label).tag(lang)
                    }
                } label: {
                    Text("UI 언어")
                }
                .pickerStyle(.menu)

                Text("앱 UI에 표시할 언어. 변경 후 Cluxo를 재시작해야 적용됩니다. ‘시스템 기본’은 macOS 시스템 언어를 따릅니다.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onChange(of: settings.preferredLanguage) { _ in
                promptRestartForLanguageChange()
            }

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
                                if let url = URL(string: "https://github.com/kykim79/Cluxo/releases/latest") {
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
                                if let url = URL(string: "https://github.com/kykim79/Cluxo/releases/latest") {
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
        let url = URL(string: "https://api.github.com/repos/kykim79/Cluxo/releases/latest")!
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
        proc.arguments = ["-n", "/Applications/Cluxo.app"]
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
        echo "▶ Cluxo 업데이트 (Terminal fallback)"
        echo "  명령: brew upgrade --cask kykim79/tap/cursorhighlight"
        echo
        if brew upgrade --cask kykim79/tap/cursorhighlight; then
            echo
            echo "✓ 업데이트 완료. Cluxo를 재시작합니다..."
            pkill -x Cluxo 2>/dev/null
            sleep 0.5
            open -a Cluxo
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

    /// 언어 변경 후 재시작 안내. "지금 재시작" 선택 시 새 인스턴스 띄우고 종료.
    /// AppDelegate.selectLanguage(_:)와 동일 로직 — 상태바 메뉴/환경설정 양쪽에서 동일 UX.
    private func promptRestartForLanguageChange() {
        let alert = NSAlert()
        alert.messageText = String(localized: "언어 변경 적용")
        alert.informativeText = String(localized: "변경된 언어를 적용하려면 Cluxo를 재시작해야 합니다.")
        alert.addButton(withTitle: String(localized: "지금 재시작"))
        alert.addButton(withTitle: String(localized: "나중에"))
        if alert.runModal() == .alertFirstButtonReturn {
            let url = Bundle.main.bundleURL
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-n", url.path]
            try? task.run()
            NSApp.terminate(nil)
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
