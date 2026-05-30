import Foundation
import CoreGraphics
import SwiftUI
import ServiceManagement

// MARK: - CursorSettings
//
// UserDefaults에 영구 저장되는 모든 사용자 설정.
// @Persisted PropertyWrapper로 init/didSet boilerplate 없음.
// customRingColor만 Color→RGBA 변환이 필요해 별도 처리.
@MainActor
final class CursorSettings: ObservableObject {
    // MARK: - Persisted Settings
    @Persisted("ringColor", default: RingColor.yellow) var ringColor: RingColor
    @Persisted("ringShape", default: RingShape.circle) var ringShape: RingShape
    @Persisted("ringSize", default: RingSize.medium) var ringSize: RingSize
    @Persisted("ringOpacity", default: 1.0, debounce: 0.3) var ringOpacity: Double
    @Persisted("animationSpeed", default: AnimationSpeed.normal) var animationSpeed: AnimationSpeed
    @Persisted("keystrokeTimeout", default: 3.0, debounce: 0.3) var keystrokeTimeout: Double
    @Persisted("spotlightKeyCode", default: UInt16(1)) var spotlightKeyCode: UInt16
    @Persisted("keystrokeKeyCode", default: UInt16(40)) var keystrokeShortcutKeyCode: UInt16
    @Persisted("spotlightRadius", default: CGFloat(130), debounce: 0.3) var spotlightRadius: CGFloat
    @Persisted("idleTimeout", default: 3.0, debounce: 0.3) var idleTimeout: TimeInterval
    @Persisted("scrollIndicator", default: true) var isScrollIndicatorEnabled: Bool
    @Persisted("rightClickUsesRingColor", default: false) var rightClickUsesRingColor: Bool
    @Persisted("autoEnableOnRecording", default: false) var autoEnableOnRecording: Bool
    @Persisted("magnifierZoom", default: 2.0, debounce: 0.3) var magnifierZoom: Double
    @Persisted("magnifierSize", default: CGFloat(200), debounce: 0.3) var magnifierSize: CGFloat
    @Persisted("magnifierKeyCode", default: UInt16(46)) var magnifierShortcutKeyCode: UInt16  // M key
    @Persisted("borderWeight", default: BorderWeight.normal) var borderWeight: BorderWeight
    @Persisted("borderStyle", default: BorderStyle.solid) var borderStyle: BorderStyle
    @Persisted("perspectiveWarping", default: false) var isPerspectiveWarping: Bool
    @Persisted("hasInnerRing", default: false) var hasInnerRing: Bool
    @Persisted("isRingFillEnabled", default: false) var isRingFillEnabled: Bool
    @Persisted("isGlowEnabled", default: true) var isGlowEnabled: Bool
    @Persisted("isKeystrokeEnabled", default: false) var isKeystrokeEnabled: Bool
    @Persisted("isTrailEnabled", default: false) var isTrailEnabled: Bool
    @Persisted("isAnchoredLineEnabled", default: true) var isAnchoredLineEnabled: Bool  // #17 — 자동 임계 기반, 평소 비-intrusive
    @Persisted("isCometTailEnabled", default: false) var isCometTailEnabled: Bool  // #18 — 드래그 streak, 임팩트 커서 default off
    @Persisted("isDragAngleLabelEnabled", default: false) var isDragAngleLabelEnabled: Bool  // 드래그 중 각도 표시 (도면용 — default off)
    @Persisted("isIdlePulseEnabled", default: true) var isIdlePulseEnabled: Bool  // 1.5초 정지 시 1회 펄스 — "여기 보세요" 자연스러운 강조
    @Persisted("isTrackpadGesturesEnabled", default: false) var isTrackpadGesturesEnabled: Bool  // 4핀치/3·4 swipe 효과 — 비공식 API(MultitouchSupport), default off

    // 낯선 외장 모니터(신뢰 목록에 없는) 연결 시 키스트로크 표시 자동 ON — 발표·회의 상황 감지.
    // 자주 쓰는 데스크탑 모니터는 trustedMonitorUUIDs에 등록해 제외.
    @Persisted("autoKeystrokeOnUnknownMonitor", default: false) var autoKeystrokeOnUnknownMonitor: Bool

    // 발표/녹화용 일시 토글 — overlay window의 sharingType을 .readOnly로 풀어 외부 screencapture/OBS가 잡을 수 있게.
    // 평소 .none이라야 CursorHighlight 자체 돋보기가 자기 overlay를 다시 capture하지 않음. 앱 재시작 시 항상 false.
    @Published var isScreenshotMode: Bool = false

    // 신뢰 모니터 UUID 목록 — 자동 키스트로크 활성화에서 제외할 모니터. [String]이라 @Persisted 미지원, 별도 처리.
    @Published var trustedMonitorUUIDs: [String] = [] {
        didSet { UserDefaults.standard.set(trustedMonitorUUIDs, forKey: "trustedMonitorUUIDs") }
    }

    func isTrustedMonitor(_ uuid: String) -> Bool { trustedMonitorUUIDs.contains(uuid) }

    func setTrusted(_ uuid: String, trusted: Bool) {
        if trusted {
            if !trustedMonitorUUIDs.contains(uuid) { trustedMonitorUUIDs.append(uuid) }
        } else {
            trustedMonitorUUIDs.removeAll { $0 == uuid }
        }
    }

    // customRingColor는 Color → NSColor → [Double] RGBA 변환 필요해서 @Persisted 미지원, 별도 처리
    @Published var customRingColor: Color = Color(red: 1, green: 0.5, blue: 0) {
        didSet { scheduleCustomColorSave() }
    }

    // ColorPicker 드래그 중 매 변화마다 NSColor 변환+UserDefaults set 회피 (@Persisted와 동일한 0.3초 debounce)
    private var saveCustomColorTask: DispatchWorkItem?

    init() {
        if let rgba = UserDefaults.standard.array(forKey: "customRingColor") as? [Double], rgba.count >= 3 {
            customRingColor = Color(red: rgba[0], green: rgba[1], blue: rgba[2],
                                    opacity: rgba.count > 3 ? rgba[3] : 1.0)
        }
        if let uuids = UserDefaults.standard.array(forKey: "trustedMonitorUUIDs") as? [String] {
            trustedMonitorUUIDs = uuids
        }
    }

    private func scheduleCustomColorSave() {
        saveCustomColorTask?.cancel()
        let color = customRingColor
        let task = DispatchWorkItem {
            let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .orange
            UserDefaults.standard.set([
                Double(ns.redComponent), Double(ns.greenComponent),
                Double(ns.blueComponent), Double(ns.alphaComponent)
            ], forKey: "customRingColor")
        }
        saveCustomColorTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    // MARK: - Launch at Login
    var launchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else       { try SMAppService.mainApp.unregister() }
        } catch { print("LaunchAtLogin: \(error)") }
    }

    // MARK: - Enums
    enum RingColor: String, CaseIterable, Identifiable {
        case yellow, red, blue, green, white, cyan, purple, custom
        var id: String { rawValue }

        var color: Color {
            switch self {
            case .yellow: return .yellow
            case .red:    return Color(red: 1, green: 0.3, blue: 0.3)
            case .blue:   return Color(red: 0.3, green: 0.6, blue: 1)
            case .green:  return Color(red: 0.3, green: 1, blue: 0.5)
            case .white:  return .white
            case .cyan:   return Color(red: 0, green: 0.9, blue: 1)
            case .purple: return Color(red: 0.8, green: 0.3, blue: 1)
            case .custom: return .orange  // placeholder; actual via customRingColor
            }
        }
        var label: String {
            switch self {
            case .yellow: return "노란색"
            case .red:    return "빨간색"
            case .blue:   return "파란색"
            case .green:  return "초록색"
            case .white:  return "흰색"
            case .cyan:   return "하늘색"
            case .purple: return "보라색"
            case .custom: return "커스텀"
            }
        }
    }

    /// Radial Menu (⌃⌥Space) 8개 메인 sector — rawValue = sector index (12시=0, 시계방향 45°).
    /// 서브 라벨은 marking menu fan에 표시되고, 없으면 메인 액션(토글/cycle)만 실행.
    enum RadialMenuItem: Int, CaseIterable {
        case spotlight = 0   // 12시
        case magnifier       // 1:30
        case glow            // 3시
        case ringSize        // 4:30
        case color           // 6시
        case ringShape       // 7:30
        case inspector       // 9시
        case keystroke       // 10:30

        var subCount: Int { subLabels.count }

        /// 현재 설정/상태값을 짧게 표현 (radial menu 중심에 "라벨 / 값"으로 표시).
        @MainActor
        func currentValue(settings: CursorSettings, runtime: CursorRuntimeState) -> String {
            switch self {
            case .spotlight: return runtime.isSpotlightActive ? "켜짐 · \(Int(settings.spotlightRadius))pt" : "꺼짐"
            case .magnifier: return runtime.isMagnifierActive ? "켜짐 · \(String(format: "%.1f", settings.magnifierZoom))×" : "꺼짐"
            case .glow:
                // ✨ 효과는 독립 토글 묶음이라 단일 ON/OFF 부정확 — 켜진 개수 노출
                let on = [settings.isGlowEnabled, settings.isTrailEnabled,
                          settings.isIdlePulseEnabled, settings.isCometTailEnabled].filter { $0 }.count
                return "\(on)/4 켜짐"
            case .ringSize:  return settings.ringSize.label
            case .color:     return settings.ringColor.label
            case .ringShape: return settings.ringShape.label
            case .inspector:
                // 📐 좌표/각도는 2개 독립 토글 묶음
                let on = [runtime.isInspectorActive, settings.isDragAngleLabelEnabled].filter { $0 }.count
                return "\(on)/2 켜짐"
            case .keystroke: return settings.isKeystrokeEnabled ? "켜짐 · \(Int(settings.keystrokeTimeout))초" : "꺼짐"
            }
        }

        /// 서브 항목 i가 현재 설정/상태와 일치하는가 — radial menu에서 "지금 어떤 게 활성인지" 시각 강조용.
        /// 토글류(spotlight/magnifier/keystroke의 sub 0, glow의 모든 sub)는 isEnabled 직접 반영,
        /// 값 선택류는 현재 값과 sub i의 값이 일치할 때 true.
        @MainActor
        func isSubCurrent(at i: Int, settings: CursorSettings, runtime: CursorRuntimeState) -> Bool {
            switch self {
            case .spotlight:
                if i == 0 { return runtime.isSpotlightActive }
                let radii: [CGFloat] = [60, 100, 140, 180, 220]
                guard i - 1 < radii.count else { return false }
                return abs(settings.spotlightRadius - radii[i - 1]) < 0.5
            case .magnifier:
                if i == 0 { return runtime.isMagnifierActive }
                let zooms: [Double] = [1.5, 2, 2.5, 3, 4]
                guard i - 1 < zooms.count else { return false }
                return abs(settings.magnifierZoom - zooms[i - 1]) < 0.05
            case .glow:
                switch i {
                case 0: return settings.isGlowEnabled
                case 1: return settings.isTrailEnabled
                case 2: return settings.isIdlePulseEnabled
                case 3: return settings.isCometTailEnabled
                default: return false
                }
            case .ringSize:
                let cases = RingSize.allCases
                return i < cases.count && cases[i] == settings.ringSize
            case .color:
                let cases = RingColor.allCases.filter { $0 != .custom }
                return i < cases.count && cases[i] == settings.ringColor
            case .ringShape:
                let cases = RingShape.allCases
                return i < cases.count && cases[i] == settings.ringShape
            case .keystroke:
                if i == 0 { return settings.isKeystrokeEnabled }
                let times: [Double] = [1, 2, 4, 8]
                guard i - 1 < times.count else { return false }
                return abs(settings.keystrokeTimeout - times[i - 1]) < 0.05
            case .inspector:
                switch i {
                case 0: return runtime.isInspectorActive
                case 1: return settings.isDragAngleLabelEnabled
                default: return false
                }
            }
        }

        /// 서브 fan이 차지하는 각도(°). 4개 이하면 메인 sector 영역(45°) 그대로,
        /// 5개부터는 항목당 +12° 확장(최대 120°)해 라벨 겹침 방지 — 옆 sector 침범하지만
        /// 활성 sector만 서브 표시라 시각 충돌 없음.
        var subSpan: Double {
            let n = subCount
            return n <= 4 ? 45.0 : min(120.0, 45.0 + Double(n - 4) * 12.0)
        }

        var subLabels: [String] {
            switch self {
            case .spotlight: return ["토글", "60pt", "100pt", "140pt", "180pt", "220pt"]
            case .magnifier: return ["토글", "1.5×", "2×", "2.5×", "3×", "4×"]
            case .glow:      return ["💡 글로우", "💨 트레일", "💫 정지펄스", "☄️ 코멧"]
            case .ringSize:  return RingSize.allCases.map(\.label)
            case .color:     return RingColor.allCases.filter { $0 != .custom }.map(\.label)
            case .ringShape: return RingShape.allCases.map(\.label)
            case .inspector: return ["📐 좌표", "🧭 드래그각도"]
            case .keystroke: return ["토글", "1초", "2초", "4초", "8초"]
            }
        }
    }

    enum RingShape: String, CaseIterable, Identifiable {
        case circle, squircle, rhombus
        var id: String { rawValue }
        var label: String {
            switch self {
            case .circle:   return "원형"
            case .squircle: return "둥근 사각형"
            case .rhombus:  return "마름모"
            }
        }
    }

    enum RingSize: String, CaseIterable, Identifiable {
        case small, medium, large, xlarge
        var id: String { rawValue }

        var diameter: CGFloat {
            switch self {
            case .small:  return 36
            case .medium: return 54
            case .large:  return 72
            case .xlarge: return 96
            }
        }
        var label: String {
            switch self {
            case .small:  return "작게 (36pt)"
            case .medium: return "보통 (54pt)"
            case .large:  return "크게 (72pt)"
            case .xlarge: return "매우 크게 (96pt)"
            }
        }
    }

    enum AnimationSpeed: String, CaseIterable, Identifiable {
        case slow, normal, fast
        var id: String { rawValue }

        var multiplier: Double {
            switch self {
            case .slow:   return 1.7
            case .normal: return 1.0
            case .fast:   return 0.5
            }
        }
        var label: String {
            switch self {
            case .slow:   return "느리게"
            case .normal: return "보통"
            case .fast:   return "빠르게"
            }
        }
    }

    enum BorderWeight: String, CaseIterable, Identifiable {
        case thin, normal, bold, heavy
        var id: String { rawValue }
        var lineWidth: CGFloat {
            switch self {
            case .thin:   return 1.5
            case .normal: return 3.0
            case .bold:   return 5.5
            case .heavy:  return 9.0
            }
        }
        var label: String {
            switch self {
            case .thin:   return "얇게"
            case .normal: return "보통"
            case .bold:   return "굵게"
            case .heavy:  return "두껍게"
            }
        }
    }

    enum BorderStyle: String, CaseIterable, Identifiable {
        case solid, dashed
        var id: String { rawValue }
        var label: String {
            switch self {
            case .solid:  return "실선"
            case .dashed: return "대시"
            }
        }
    }
}
