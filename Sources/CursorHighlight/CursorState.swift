import Foundation
import CoreGraphics
import SwiftUI
import ServiceManagement

@MainActor
class CursorState: ObservableObject {
    // MARK: - Runtime State
    @Published var cursorPosition: CGPoint = .zero
    @Published var isCursorVisible: Bool = true
    @Published var isSpotlightActive: Bool = false
    @Persisted("isKeystrokeEnabled", default: false) var isKeystrokeEnabled: Bool
    @Published var keystrokeText: String = ""
    @Published var isKeystrokeVisible: Bool = false
    @Persisted("isTrailEnabled", default: false) var isTrailEnabled: Bool
    @Published var isMagnifierActive: Bool = false
    @Published var magnifierImage: CGImage?
    @Published var hasScreenRecordingPermission: Bool = false

    // MARK: - Motion Semantics State
    @Published var ringClickScale: CGFloat = 1.0
    @Published var ringClickTilt: Double = 0
    @Published var isDragging: Bool = false
    @Published var dragAngle: Double = 0
    @Published var glowMultiplier: Double = 1.0

    // MARK: - Effects
    @Published var clickEffects: [ClickEffect] = []
    @Published var doubleClickEffects: [DoubleClickEffect] = []
    @Published var shakeEffects: [ShakeEffect] = []
    @Published var scrollEffects: [ScrollEffect] = []
    @Published var trailPoints: [TrailPoint] = []
    @Published var clipboardEffects: [ClipboardEffect] = []

    // MARK: - Settings (UserDefaults 자동 저장 via @Persisted)
    @Persisted("ringColor", default: RingColor.yellow) var ringColor: RingColor
    @Persisted("ringShape", default: RingShape.circle) var ringShape: RingShape
    @Persisted("ringSize", default: RingSize.medium) var ringSize: RingSize
    @Persisted("ringOpacity", default: 1.0, debounce: 0.3) var ringOpacity: Double
    @Persisted("animationSpeed", default: AnimationSpeed.normal) var animationSpeed: AnimationSpeed
    // customRingColor는 Color → NSColor → [Double] RGBA 변환 필요해서 @Persisted 미지원, 별도 처리
    @Published var customRingColor: Color = Color(red: 1, green: 0.5, blue: 0) {
        didSet { saveCustomColor() }
    }
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

    private var keystrokeHideTask: Task<Void, Never>?

    // MARK: - Init
    // @Persisted가 모든 설정을 자동 로드한다. customRingColor만 Color→RGBA 변환이 필요해 수동 로드.
    init() {
        if let rgba = UserDefaults.standard.array(forKey: "customRingColor") as? [Double], rgba.count >= 3 {
            customRingColor = Color(red: rgba[0], green: rgba[1], blue: rgba[2],
                                    opacity: rgba.count > 3 ? rgba[3] : 1.0)
        }
    }

    private func saveCustomColor() {
        let ns = NSColor(customRingColor).usingColorSpace(.deviceRGB) ?? .orange
        UserDefaults.standard.set([
            Double(ns.redComponent), Double(ns.greenComponent),
            Double(ns.blueComponent), Double(ns.alphaComponent)
        ], forKey: "customRingColor")
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

    // MARK: - Effect Structs
    struct ClickEffect: Identifiable {
        let id = UUID(); let position: CGPoint; let isRight: Bool; let isDouble: Bool
    }
    struct DoubleClickEffect: Identifiable {
        let id = UUID(); let position: CGPoint
    }
    struct ShakeEffect: Identifiable {
        let id = UUID(); let position: CGPoint
    }
    struct ScrollEffect: Identifiable {
        let id = UUID(); let position: CGPoint; let isPositive: Bool; let isVertical: Bool
    }
    struct TrailPoint: Identifiable {
        let id = UUID(); let position: CGPoint
    }
    struct ClipboardEffect: Identifiable {
        let id = UUID(); let position: CGPoint; let emoji: String
    }

    // MARK: - Motion Semantics
    func startDrag() {
        dragAngle = 0
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isDragging = true }
    }

    func updateDragAngle(_ newAngle: Double) {
        // 이전 각도의 wrapped 값과 비교해 차이를 (-π, π] 로 정규화한 뒤 누적
        // → atan2의 ±π 불연속점이 사라져 애니메이션이 항상 짧은 방향으로 이동
        let lastWrapped = atan2(sin(dragAngle), cos(dragAngle))
        var diff = newAngle - lastWrapped
        if diff > .pi  { diff -= 2 * .pi }
        if diff < -.pi { diff += 2 * .pi }
        dragAngle += diff
    }

    func endDrag() {
        // 다음 드래그를 위해 (-π, π]로 정규화 후 0으로 리셋
        dragAngle = atan2(sin(dragAngle), cos(dragAngle))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { isDragging = false }
        dragAngle = 0
    }

    func triggerClickPulse(isDouble: Bool = false) {
        let scaleTarget: CGFloat = isDouble ? 0.6 : 0.75
        let tiltTarget: Double = isDouble ? 28 : 18
        withAnimation(.spring(response: 0.1, dampingFraction: 0.4)) {
            ringClickScale = scaleTarget
            ringClickTilt = tiltTarget
        }
        Task {
            try? await Task.sleep(for: .milliseconds(isDouble ? 160 : 130))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.45)) {
                ringClickScale = 1.0
                ringClickTilt = 0
            }
        }
    }

    // MARK: - Actions
    func showKeystroke(_ text: String) {
        keystrokeText = text
        isKeystrokeVisible = true
        keystrokeHideTask?.cancel()
        keystrokeHideTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(keystrokeTimeout))
                withAnimation(.easeOut(duration: 0.3)) { self.isKeystrokeVisible = false }
            } catch {}
        }
    }

    func showStatusNotification(_ text: String) {
        keystrokeText = text
        isKeystrokeVisible = true
        keystrokeHideTask?.cancel()
        keystrokeHideTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.5))
                withAnimation(.easeOut(duration: 0.3)) { self.isKeystrokeVisible = false }
            } catch {}
        }
    }

    func addClickEffect(at point: CGPoint, isRight: Bool, isDouble: Bool = false) {
        let effect = ClickEffect(position: point, isRight: isRight, isDouble: isDouble)
        let speed = animationSpeed.multiplier
        clickEffects.append(effect)
        if isDouble {
            let de = DoubleClickEffect(position: point)
            doubleClickEffects.append(de)
            Task {
                try? await Task.sleep(for: .seconds(0.9 * speed))
                doubleClickEffects.removeAll { $0.id == de.id }
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(0.7 * speed))
            clickEffects.removeAll { $0.id == effect.id }
        }
    }

    func triggerShake(at point: CGPoint) {
        let effect = ShakeEffect(position: point)
        let speed = animationSpeed.multiplier
        shakeEffects.append(effect)
        Task {
            try? await Task.sleep(for: .seconds(max(1.5, 1.8 * speed)))
            shakeEffects.removeAll { $0.id == effect.id }
        }
    }

    func addScrollEffect(at point: CGPoint, isPositive: Bool, isVertical: Bool) {
        scrollEffects.removeAll()
        let effect = ScrollEffect(position: point, isPositive: isPositive, isVertical: isVertical)
        let speed = animationSpeed.multiplier
        scrollEffects.append(effect)
        Task {
            try? await Task.sleep(for: .seconds(0.65 * speed))
            scrollEffects.removeAll { $0.id == effect.id }
        }
    }

    func addClipboardEffect(at point: CGPoint, emoji: String) {
        let effect = ClipboardEffect(position: point, emoji: emoji)
        clipboardEffects.append(effect)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            clipboardEffects.removeAll { $0.id == effect.id }
        }
    }

    func updateTrail(_ point: CGPoint) {
        trailPoints.append(TrailPoint(position: point))
        if trailPoints.count > 26 { trailPoints.removeFirst() }
    }
    func clearTrail() { trailPoints.removeAll() }

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
}
