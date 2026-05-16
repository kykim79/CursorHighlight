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
    @Published var isKeystrokeEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isKeystrokeEnabled, forKey: "isKeystrokeEnabled") }
    }
    @Published var keystrokeText: String = ""
    @Published var isKeystrokeVisible: Bool = false
    @Published var isTrailEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isTrailEnabled, forKey: "isTrailEnabled") }
    }
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

    // MARK: - Settings (UserDefaults 저장)
    @Published var ringColor: RingColor = .yellow {
        didSet { UserDefaults.standard.set(ringColor.rawValue, forKey: "ringColor") }
    }
    @Published var ringShape: RingShape = .circle {
        didSet { UserDefaults.standard.set(ringShape.rawValue, forKey: "ringShape") }
    }
    @Published var ringSize: RingSize = .medium {
        didSet { UserDefaults.standard.set(ringSize.rawValue, forKey: "ringSize") }
    }
    @Published var ringOpacity: Double = 1.0 {
        didSet { debouncedSet(ringOpacity, forKey: "ringOpacity") }
    }
    @Published var animationSpeed: AnimationSpeed = .normal {
        didSet { UserDefaults.standard.set(animationSpeed.rawValue, forKey: "animationSpeed") }
    }
    @Published var customRingColor: Color = Color(red: 1, green: 0.5, blue: 0) {
        didSet { saveCustomColor() }
    }
    @Published var keystrokeTimeout: Double = 3.0 {
        didSet { debouncedSet(keystrokeTimeout, forKey: "keystrokeTimeout") }
    }
    @Published var spotlightKeyCode: UInt16 = 1 {
        didSet { UserDefaults.standard.set(Int(spotlightKeyCode), forKey: "spotlightKeyCode") }
    }
    @Published var keystrokeShortcutKeyCode: UInt16 = 40 {
        didSet { UserDefaults.standard.set(Int(keystrokeShortcutKeyCode), forKey: "keystrokeKeyCode") }
    }
    @Published var spotlightRadius: CGFloat = 130 {
        didSet { debouncedSet(Double(spotlightRadius), forKey: "spotlightRadius") }
    }
    @Published var idleTimeout: TimeInterval = 3.0 {
        didSet { debouncedSet(idleTimeout, forKey: "idleTimeout") }
    }
    @Published var isScrollIndicatorEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isScrollIndicatorEnabled, forKey: "scrollIndicator") }
    }
    @Published var rightClickUsesRingColor: Bool = false {
        didSet { UserDefaults.standard.set(rightClickUsesRingColor, forKey: "rightClickUsesRingColor") }
    }
    @Published var autoEnableOnRecording: Bool = false {
        didSet { UserDefaults.standard.set(autoEnableOnRecording, forKey: "autoEnableOnRecording") }
    }
    @Published var magnifierZoom: Double = 2.0 {
        didSet { debouncedSet(magnifierZoom, forKey: "magnifierZoom") }
    }
    @Published var magnifierSize: CGFloat = 200 {
        didSet { debouncedSet(Double(magnifierSize), forKey: "magnifierSize") }
    }
    @Published var magnifierShortcutKeyCode: UInt16 = 46 {  // M key
        didSet { UserDefaults.standard.set(Int(magnifierShortcutKeyCode), forKey: "magnifierKeyCode") }
    }
    @Published var borderWeight: BorderWeight = .normal {
        didSet { UserDefaults.standard.set(borderWeight.rawValue, forKey: "borderWeight") }
    }
    @Published var borderStyle: BorderStyle = .solid {
        didSet { UserDefaults.standard.set(borderStyle.rawValue, forKey: "borderStyle") }
    }
    @Published var isPerspectiveWarping: Bool = false {
        didSet { UserDefaults.standard.set(isPerspectiveWarping, forKey: "perspectiveWarping") }
    }
    @Published var hasInnerRing: Bool = false {
        didSet { UserDefaults.standard.set(hasInnerRing, forKey: "hasInnerRing") }
    }
    @Published var isRingFillEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isRingFillEnabled, forKey: "isRingFillEnabled") }
    }
    @Published var isGlowEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isGlowEnabled, forKey: "isGlowEnabled") }
    }

    private var keystrokeHideTask: Task<Void, Never>?

    // 슬라이더 드래그 중 매 60Hz UserDefaults set 호출 회피 (lock + KVO 비용)
    private var pendingDefaults: [String: Any] = [:]
    private var defaultsSaveTask: DispatchWorkItem?

    private func debouncedSet(_ value: Any, forKey key: String) {
        pendingDefaults[key] = value
        defaultsSaveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            for (k, v) in self.pendingDefaults {
                UserDefaults.standard.set(v, forKey: k)
            }
            self.pendingDefaults.removeAll()
        }
        defaultsSaveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    // MARK: - Init
    init() {
        if let raw = UserDefaults.standard.string(forKey: "ringColor"),
           let c = RingColor(rawValue: raw) { ringColor = c }
        if let raw = UserDefaults.standard.string(forKey: "ringShape"),
           let s = RingShape(rawValue: raw) { ringShape = s }
        if let raw = UserDefaults.standard.string(forKey: "ringSize"),
           let s = RingSize(rawValue: raw) { ringSize = s }
        let ro = UserDefaults.standard.double(forKey: "ringOpacity")
        if ro > 0 { ringOpacity = ro }
        if let raw = UserDefaults.standard.string(forKey: "animationSpeed"),
           let s = AnimationSpeed(rawValue: raw) { animationSpeed = s }
        if let rgba = UserDefaults.standard.array(forKey: "customRingColor") as? [Double], rgba.count >= 3 {
            customRingColor = Color(red: rgba[0], green: rgba[1], blue: rgba[2],
                                    opacity: rgba.count > 3 ? rgba[3] : 1.0)
        }
        let t = UserDefaults.standard.double(forKey: "keystrokeTimeout")
        if t > 0 { keystrokeTimeout = t }
        let sk = UserDefaults.standard.integer(forKey: "spotlightKeyCode")
        if sk > 0 { spotlightKeyCode = UInt16(sk) }
        let kk = UserDefaults.standard.integer(forKey: "keystrokeKeyCode")
        if kk > 0 { keystrokeShortcutKeyCode = UInt16(kk) }
        let sr = UserDefaults.standard.double(forKey: "spotlightRadius")
        if sr > 0 { spotlightRadius = CGFloat(sr) }
        let it = UserDefaults.standard.double(forKey: "idleTimeout")
        if it > 0 { idleTimeout = it }
        if UserDefaults.standard.object(forKey: "scrollIndicator") != nil {
            isScrollIndicatorEnabled = UserDefaults.standard.bool(forKey: "scrollIndicator")
        }
        rightClickUsesRingColor = UserDefaults.standard.bool(forKey: "rightClickUsesRingColor")
        autoEnableOnRecording = UserDefaults.standard.bool(forKey: "autoEnableOnRecording")
        let mz = UserDefaults.standard.double(forKey: "magnifierZoom")
        if mz > 0 { magnifierZoom = mz }
        let ms = UserDefaults.standard.double(forKey: "magnifierSize")
        if ms > 0 { magnifierSize = CGFloat(ms) }
        let mk = UserDefaults.standard.integer(forKey: "magnifierKeyCode")
        if mk > 0 { magnifierShortcutKeyCode = UInt16(mk) }
        if let raw = UserDefaults.standard.string(forKey: "borderWeight"),
           let w = BorderWeight(rawValue: raw) { borderWeight = w }
        if let raw = UserDefaults.standard.string(forKey: "borderStyle"),
           let s = BorderStyle(rawValue: raw) { borderStyle = s }
        isPerspectiveWarping = UserDefaults.standard.bool(forKey: "perspectiveWarping")
        hasInnerRing = UserDefaults.standard.bool(forKey: "hasInnerRing")
        isRingFillEnabled = UserDefaults.standard.bool(forKey: "isRingFillEnabled")
        if UserDefaults.standard.object(forKey: "isGlowEnabled") != nil {
            isGlowEnabled = UserDefaults.standard.bool(forKey: "isGlowEnabled")
        }
        if UserDefaults.standard.object(forKey: "isKeystrokeEnabled") != nil {
            isKeystrokeEnabled = UserDefaults.standard.bool(forKey: "isKeystrokeEnabled")
        }
        if UserDefaults.standard.object(forKey: "isTrailEnabled") != nil {
            isTrailEnabled = UserDefaults.standard.bool(forKey: "isTrailEnabled")
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
