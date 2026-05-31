import SwiftUI

struct OverlayContentView: View {
    @ObservedObject var settings: CursorSettings
    @ObservedObject var runtime: CursorRuntimeState
    @ObservedObject var effects: EffectsState
    @ObservedObject var keystroke: KeystrokeOverlayState
    @ObservedObject var drawing: DrawingState
    let screenFrame: CGRect

    private var localPos: CGPoint { toLocal(runtime.cursorPosition) }
    private var cursorOnScreen: Bool { screenFrame.contains(runtime.cursorPosition) }
    private var speed: Double { settings.animationSpeed.multiplier }
    private var effectiveColor: Color { settings.effectiveRingColor }

    var body: some View {
        ZStack {
            // 스포트라이트
            if runtime.isSpotlightActive {
                if cursorOnScreen { SpotlightView(position: localPos, radius: settings.spotlightRadius, ringShape: settings.ringShape) }
                else              { Tokens.Surface.dim }
            }

            // 커서 트레일 — 좌표 변환은 TrailView 내부에서 (body 재계산 시 매번 filter+map 회피)
            if settings.isTrailEnabled && !effects.trailPoints.isEmpty {
                TrailView(trailPoints: effects.trailPoints, screenFrame: screenFrame, color: effectiveColor)
            }

            // #18 Comet Tail — 드래그 중 streak (별도 더 굵고 진한 trail)
            if settings.isCometTailEnabled && !effects.dragTrailPoints.isEmpty {
                CometTailView(points: effects.dragTrailPoints, screenFrame: screenFrame, color: effectiveColor)
            }

            // #17 Anchored Line — settings 토글 + 거리/시간 임계 만족 시만 표시.
            // 짧은 드래그(스크롤바)는 line 안 보임, 의도적 긴 드래그(영역 강조)에 자동 fade in.
            if settings.isAnchoredLineEnabled, let origin = runtime.dragOrigin {
                AnchoredLineView(
                    origin: toLocal(origin),
                    current: localPos,
                    color: effectiveColor,
                    visible: runtime.anchoredLineVisible
                )
            }

            // 커서 링
            if cursorOnScreen && runtime.isCursorVisible {
                CursorRingView(
                    position: localPos,
                    appearance: RingAppearance(settings: settings, effectiveColor: effectiveColor),
                    motion: RingMotion(runtime: runtime)
                )
            }

            // 정지 펄스 — 1.5초 정지 시 1회 ring shape 확장 fade
            ForEach(effects.idlePulseEffects, id: \.id) { effect in
                if screenFrame.contains(effect.position) {
                    IdlePulseView(position: toLocal(effect.position), color: effectiveColor, ringShape: settings.ringShape, speed: speed)
                }
            }

            // 드래그 각도 라벨 — 도면/일러스트레이션용. cursor 우상단 작은 라벨.
            if settings.isDragAngleLabelEnabled && runtime.isDragging && cursorOnScreen {
                let dragDistance: CGFloat = {
                    guard let origin = runtime.dragOrigin else { return 0 }
                    let dx = runtime.cursorPosition.x - origin.x
                    let dy = runtime.cursorPosition.y - origin.y
                    return sqrt(dx*dx + dy*dy)
                }()
                DragAngleLabel(position: localPos, angleRadians: runtime.dragAngle, distance: dragDistance)
            }
            // Radial Menu (⌃⌥Space hold) — 메인 8개 sector + 서브 fan (해당 sector 활성 시).
            // Radial Menu는 effects/돋보기보다 위 z-order로 렌더 — 아래 magnifier 블록 뒤로 이동 (v0.7.0)

            // 화면 좌표 인스펙터 (⌃⌥I 토글) — cursor 우하단에 Quartz(top-left) 시스템 좌표.
            if runtime.isInspectorActive && cursorOnScreen {
                let quartzY = (NSScreen.main?.frame.height ?? 0) - runtime.cursorPosition.y
                InspectorView(position: localPos, quartzGlobal: CGPoint(x: runtime.cursorPosition.x, y: quartzY))
            }

            // 클릭 파동
            ForEach(effects.clickEffects, id: \.id) { effect in
                if screenFrame.contains(effect.position) {
                    ClickRippleView(
                        position: toLocal(effect.position),
                        isRight: effect.isRight,
                        isDouble: effect.isDouble,
                        color: effectiveColor,
                        rightClickUsesRingColor: settings.rightClickUsesRingColor,
                        ringShape: settings.ringShape,
                        speed: speed
                    )
                }
            }

            // 더블클릭 버스트
            ForEach(effects.doubleClickEffects, id: \.id) { effect in
                if screenFrame.contains(effect.position) {
                    DoubleClickBurstView(position: toLocal(effect.position), color: effectiveColor, ringShape: settings.ringShape, speed: speed)
                }
            }

            // 휠 클릭 (button 2) — 회전 파동
            ForEach(effects.middleClickEffects, id: \.id) { effect in
                if screenFrame.contains(effect.position) {
                    MiddleClickEffectView(position: toLocal(effect.position), color: effectiveColor, ringShape: settings.ringShape, speed: speed)
                }
            }

            // 흔들기
            ForEach(effects.shakeEffects, id: \.id) { effect in
                if screenFrame.contains(effect.position) {
                    ShakeEffectView(position: toLocal(effect.position), color: effectiveColor, ringShape: settings.ringShape, speed: speed)
                }
            }

            // 스크롤 인디케이터
            if settings.isScrollIndicatorEnabled {
                ForEach(effects.scrollEffects, id: \.id) { effect in
                    if screenFrame.contains(effect.position) {
                        ScrollIndicatorView(
                            position: toLocal(effect.position),
                            isPositive: effect.isPositive,
                            isVertical: effect.isVertical,
                            magnitude: effect.magnitude,
                            speed: speed
                        )
                    }
                }
            }

            // 클립보드 인디케이터
            ForEach(effects.clipboardEffects, id: \.id) { effect in
                if screenFrame.contains(effect.position) {
                    ClipboardIndicatorView(position: toLocal(effect.position), emoji: effect.emoji)
                }
            }

            // 트랙패드 시스템 제스처 (4핀치 / 3·4 swipe) — MultitouchService 감지
            ForEach(effects.trackpadGestureEffects, id: \.id) { effect in
                if screenFrame.contains(effect.position) {
                    TrackpadGestureVisualView(
                        position: toLocal(effect.position),
                        gesture: effect.gesture,
                        softReveal: effect.softReveal,
                        color: effectiveColor,
                        speed: speed
                    )
                }
            }

            // 돋보기
            if runtime.isMagnifierActive && cursorOnScreen {
                MagnifierView(
                    position: localPos,
                    image: runtime.magnifierImage,
                    size: settings.magnifierSize,
                    color: effectiveColor,
                    ringShape: settings.ringShape
                )
            }

            // Radial Menu (⌃⌥, toggle) — effects/돋보기 위에 표시. 사용자가 메뉴 활성 중 돋보기 토글해도 메뉴 가려지지 않음.
            if runtime.isRadialMenuActive && runtime.isRadialMenuVisible && screenFrame.contains(runtime.radialMenuCenter) {
                let currentValues: [String] = (0..<8).map { i in
                    CursorSettings.RadialMenuItem(rawValue: i)?.currentValue(settings: settings, runtime: runtime) ?? ""
                }
                let subActiveStates: [Bool]? = runtime.radialMenuSelectedSector.flatMap { sec in
                    CursorSettings.RadialMenuItem(rawValue: sec).map { item in
                        (0..<item.subCount).map { item.isSubCurrent(at: $0, settings: settings, runtime: runtime) }
                    }
                }
                RadialMenuView(
                    center: toLocal(runtime.radialMenuCenter),
                    selectedSector: runtime.radialMenuSelectedSector,
                    selectedSubItem: runtime.radialMenuSelectedSubItem,
                    currentValues: currentValues,
                    subActiveStates: subActiveStates,
                    showHelp: runtime.radialMenuShowHelp,
                    accentColor: effectiveColor
                )
                // 메뉴 활성 동안 cursor 위치에 작은 흰 ring — 사용자가 자기 cursor 위치 인지 단서
                if cursorOnScreen {
                    Circle()
                        .stroke(Tokens.Stroke.cursor, lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                        .position(localPos)
                        .allowsHitTesting(false)
                }
            }

            // 그리기 (⌃⌥D) — 도형 + 진행 중 stroke. radial menu·spotlight·magnifier 위에 그려짐.
            ForEach(drawing.shapes) { shape in
                DrawnShapeView(shape: shape, screenFrame: screenFrame)
            }
            if let current = drawing.currentShape {
                DrawnShapeView(shape: current, screenFrame: screenFrame)
            }
            // 그리기 모드 활성 시 cursor 위치에 작은 + 인디케이터 (펜 모드 시각 단서)
            if drawing.isDrawingModeActive && cursorOnScreen {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .position(localPos)
                    .allowsHitTesting(false)
            }

            // 좌측 하단 toolbar — 그리기 모드 활성 중. Cursor 있는 screen에만 표시 (multi-monitor 시 따라옴).
            // 위치는 settings.drawingToolbar(Leading/Bottom)으로 persist — 사용자가 drag handle로 이동.
            // Modern Option B: 라벨/cheat 제거. 모디파이어/단축키는 onboarding capsule + 도구 클릭 알림으로 전달.
            if drawing.isDrawingModeActive && screenFrame.contains(runtime.cursorPosition) {
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            // First-time onboarding capsule — 첫 5회만, 6초간. 모디파이어 + 단축키 전체 cheat.
                            if drawing.showOnboarding {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("⇧ 직선 · ⌥ 화살표 · ⌘ 사각형 · ⌘⇧ 타원 · ⌘⌥ 형광펜 · ⇧⌥+클릭 뱃지")
                                    Text("[ / ] 두께 · ⌃⌥1~7 색 · ⌃⌥C 순환 · ⌘Z 되돌리기 · ESC 닫기")
                                        .foregroundColor(.white.opacity(0.75))
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
                                .environment(\.colorScheme, .dark)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(effectiveColor.opacity(0.6), lineWidth: 1))
                                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                            DrawingToolbarView(drawing: drawing, settings: settings, accentColor: effectiveColor)
                        }
                        .animation(.easeOut(duration: 0.2), value: drawing.showOnboarding)
                        .padding(.leading, settings.drawingToolbarLeading)
                        .padding(.bottom, settings.drawingToolbarBottom)
                        Spacer()
                    }
                }
                .onPreferenceChange(ToolFramePreference.self) { frames in
                    drawing.toolbarFrames = frames.mapValues { swiftUIToCocoa($0) }
                }
                .onPreferenceChange(ThicknessFramePreference.self) { frames in
                    drawing.thicknessFrames = frames.mapValues { swiftUIToCocoa($0) }
                }
                .onPreferenceChange(ColorFramePreference.self) { frames in
                    drawing.colorFrames = frames.mapValues { swiftUIToCocoa($0) }
                }
                .onPreferenceChange(DragHandleFramePreference.self) { frame in
                    drawing.dragHandleFrame = swiftUIToCocoa(frame)
                }
                .onPreferenceChange(ToolbarSizePreference.self) { size in
                    drawing.toolbarSize = size
                }
            }

            // 키스트로크 / 상태 알림 (항상 트리에 포함 - 비활성 시 알림도 표시되어야 함)
            KeystrokeDisplayView(
                text: keystroke.keystrokeText,
                isVisible: keystroke.isKeystrokeVisible,
                position: CGPoint(x: screenFrame.width / 2, y: screenFrame.height - 80)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private func toLocal(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - screenFrame.minX, y: screenFrame.maxY - p.y)
    }

    /// SwiftUI .global frame(top-left origin within overlay window) → Cocoa global rect(bottom-left).
    /// Overlay window는 screenFrame과 일치하므로 변환식: cocoaY = screenFrame.maxY - swiftuiMaxY.
    private func swiftUIToCocoa(_ f: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + f.minX,
            y: screenFrame.maxY - f.maxY,
            width: f.width,
            height: f.height
        )
    }
}

// MARK: - 스포트라이트

struct SpotlightView: View {
    let position: CGPoint
    let radius: CGFloat
    let ringShape: CursorSettings.RingShape

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Tokens.Surface.dim))
            context.blendMode = .clear
            // 밝게 뚫리는 cutout이 ring shape를 따름. gradient는 radial 유지(중심→가장자리 fade).
            let cutout = CGRect(x: position.x - radius, y: position.y - radius,
                                width: radius * 2, height: radius * 2)
            context.fill(
                ringShape.anyShape.path(in: cutout),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.6),
                        .init(color: .clear, location: 1.0)
                    ]),
                    center: position, startRadius: 0, endRadius: radius
                )
            )
        }
        .animation(.none, value: position)
        .transition(.opacity)
    }
}

// MARK: - 컴맷 테일 (#18)

/// 드래그 중에만 cursor 뒤에 streak. 기존 TrailView 베이스 + 더 굵고 진함.
/// 14개 sample 슬라이딩 윈도우 (TrailView 26개보다 짧음 — 빠른 streak 느낌).
struct CometTailView: View {
    let points: [EffectsState.TrailPoint]
    let screenFrame: CGRect
    let color: Color

    var body: some View {
        Canvas { context, _ in
            let positions: [CGPoint] = points.compactMap { tp in
                guard screenFrame.contains(tp.position) else { return nil }
                return CGPoint(x: tp.position.x - screenFrame.minX,
                               y: screenFrame.maxY - tp.position.y)
            }
            let count = positions.count
            guard count >= 2 else { return }
            for i in 0..<(count - 1) {
                let t = Double(i + 1) / Double(count)
                let alpha = t * t   // 꼬리는 빨리 사라짐
                let coreW = CGFloat(3.0 + t * 7.0)  // 일반 trail보다 굵음 (3~10)
                var seg = Path()
                seg.move(to: positions[i])
                seg.addLine(to: positions[i + 1])
                // 강한 glow 단계 (일반 trail보다 더 진함)
                context.stroke(seg, with: .color(color.opacity(alpha * 0.08)),
                               style: StrokeStyle(lineWidth: coreW + 28, lineCap: .round))
                context.stroke(seg, with: .color(color.opacity(alpha * 0.20)),
                               style: StrokeStyle(lineWidth: coreW + 14, lineCap: .round))
                context.stroke(seg, with: .color(color.opacity(alpha * 0.55)),
                               style: StrokeStyle(lineWidth: coreW + 6, lineCap: .round))
                context.stroke(seg, with: .color(color.opacity(min(1.0, alpha + 0.25))),
                               style: StrokeStyle(lineWidth: coreW, lineCap: .round))
            }
        }
    }
}

// MARK: - 앵커 라인 (#17)

/// 드래그 시작점에 작은 dot + 시작점→현재 위치 점선. 디자인·CAD 툴 느낌.
/// 드래그 종료 시 0.3초 fade out (CursorRuntimeState.endDrag가 dragOrigin nil 처리).
struct AnchoredLineView: View {
    let origin: CGPoint
    let current: CGPoint
    let color: Color
    let visible: Bool   // CursorRuntimeState.anchoredLineVisible — 거리/시간 임계 통과 시만 true

    var body: some View {
        ZStack {
            // 점선 라인
            Path { p in
                p.move(to: origin)
                p.addLine(to: current)
            }
            .stroke(
                color.opacity(visible ? 0.65 : 0),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4])
            )
            // 시작점 dot — 작은 원 + glow
            Circle()
                .fill(color.opacity(visible ? 0.85 : 0))
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(visible ? 0.6 : 0), radius: 4)
                .position(origin)
        }
        .animation(.easeOut(duration: 0.3), value: visible)
        .allowsHitTesting(false)
    }
}

// MARK: - 커서 트레일

struct TrailView: View {
    let trailPoints: [EffectsState.TrailPoint]
    let screenFrame: CGRect
    let color: Color

    // SwiftUI input(trailPoints/screenFrame)이 변경될 때만 body 호출됨.
    // cursorPosition 등 다른 @Published 변경 시는 재계산되지 않아 비용 절감.
    var body: some View {
        Canvas { context, _ in
            let positions: [CGPoint] = trailPoints.compactMap { tp in
                guard screenFrame.contains(tp.position) else { return nil }
                return CGPoint(x: tp.position.x - screenFrame.minX,
                               y: screenFrame.maxY - tp.position.y)
            }
            let count = positions.count
            guard count >= 2 else { return }
            for i in 0..<(count - 1) {
                let t = Double(i + 1) / Double(count)  // 0=꼬리, 1=머리
                let alpha = t * t                       // 2차 감쇠 — 꼬리 쪽 빠르게 사라짐
                let coreW = CGFloat(1.5 + t * 4.5)
                var seg = Path()
                seg.move(to: positions[i])
                seg.addLine(to: positions[i + 1])
                // 외곽 글로우 → 중간 글로우 → 이너 글로우 → 코어
                context.stroke(seg, with: .color(color.opacity(alpha * 0.05)),
                               style: StrokeStyle(lineWidth: coreW + 22, lineCap: .round))
                context.stroke(seg, with: .color(color.opacity(alpha * 0.13)),
                               style: StrokeStyle(lineWidth: coreW + 11, lineCap: .round))
                context.stroke(seg, with: .color(color.opacity(alpha * 0.38)),
                               style: StrokeStyle(lineWidth: coreW + 4, lineCap: .round))
                context.stroke(seg, with: .color(color.opacity(min(1.0, alpha + 0.12))),
                               style: StrokeStyle(lineWidth: coreW, lineCap: .round))
            }
        }
    }
}

// MARK: - 커서 링

// MARK: - 도넛 채우기 Shape (even-odd rule로 안쪽 잘라냄)

struct DonutFillShape: Shape {
    let innerDiameter: CGFloat
    let ringShape: CursorSettings.RingShape

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = (rect.width - innerDiameter) / 2
        let innerRect = rect.insetBy(dx: inset, dy: inset)
        switch ringShape {
        case .circle:
            path.addEllipse(in: rect)
            path.addEllipse(in: innerRect)
        case .squircle:
            path.addPath(RoundedRectangle(cornerRadius: rect.width * 0.28, style: .continuous).path(in: rect))
            path.addPath(RoundedRectangle(cornerRadius: innerRect.width * 0.28, style: .continuous).path(in: innerRect))
        case .rhombus:
            path.addPath(RhombusShape().path(in: rect))
            path.addPath(RhombusShape().path(in: innerRect))
        }
        return path
    }
}

struct RhombusShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// 둥근 사각형 — cornerRadius를 frame 크기 비율(28%)로 잡아 ring과 동일 외형. 효과에 재사용.
struct SquircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: rect.width * 0.28, style: .continuous).path(in: rect)
    }
}

extension CursorSettings.RingShape {
    /// 클릭·버스트·흔들기·휠클릭 등 모든 효과가 ring shape를 따라가도록 재사용하는 type-erased Shape.
    var anyShape: AnyShape {
        switch self {
        case .circle:   return AnyShape(Circle())
        case .squircle: return AnyShape(SquircleShape())
        case .rhombus:  return AnyShape(RhombusShape())
        }
    }
}

/// 링의 정적 외형 (settings에서 파생). 옵션 추가 시 호출부 영향 없이 여기에만 한 줄 추가.
struct RingAppearance {
    let color: Color
    let size: CGFloat
    let shape: CursorSettings.RingShape
    let opacity: Double
    let borderWeight: CursorSettings.BorderWeight
    let borderStyle: CursorSettings.BorderStyle
    let isPerspectiveWarping: Bool
    let hasInnerRing: Bool
    let isRingFillEnabled: Bool
    let isGlowEnabled: Bool

    @MainActor
    init(settings: CursorSettings, effectiveColor: Color) {
        self.color = effectiveColor
        self.size = settings.ringSize.diameter
        self.shape = settings.ringShape
        self.opacity = settings.ringOpacity
        self.borderWeight = settings.borderWeight
        self.borderStyle = settings.borderStyle
        self.isPerspectiveWarping = settings.isPerspectiveWarping
        self.hasInnerRing = settings.hasInnerRing
        self.isRingFillEnabled = settings.isRingFillEnabled
        self.isGlowEnabled = settings.isGlowEnabled
    }
}

/// 링의 동적 모션 (runtime에서 파생). 클릭/드래그/glow 등 매 frame 변하는 값.
struct RingMotion {
    let clickScale: CGFloat
    let clickTilt: Double
    let isDragging: Bool
    let dragAngle: Double
    let dragVelocity: CGFloat  // pt/s, #14 Speed Glow용
    let glowMultiplier: Double

    @MainActor
    init(runtime: CursorRuntimeState) {
        self.clickScale = runtime.ringClickScale
        self.clickTilt = runtime.ringClickTilt
        self.isDragging = runtime.isDragging
        self.dragAngle = runtime.dragAngle
        self.dragVelocity = runtime.dragVelocity
        self.glowMultiplier = runtime.glowMultiplier
    }
}

struct CursorRingView: View {
    let position: CGPoint
    let appearance: RingAppearance
    let motion: RingMotion

    @State private var breathingScale: CGFloat = 0.94

    private var strokeStyle: StrokeStyle {
        let lw = appearance.borderWeight.lineWidth
        return StrokeStyle(
            lineWidth: lw,
            lineCap: .round,
            dash: appearance.borderStyle == .dashed ? [lw * 2.2, lw * 1.4] : []
        )
    }

    private var innerStrokeStyle: StrokeStyle {
        let lw = appearance.borderWeight.lineWidth * 0.55
        return StrokeStyle(lineWidth: lw, lineCap: .round)
    }

    private var innerSize: CGFloat { appearance.size * 0.76 }

    @ViewBuilder
    private func ringShape(diameter: CGFloat, style: StrokeStyle, ringOpacity: Double) -> some View {
        switch appearance.shape {
        case .circle:
            Circle()
                .stroke(appearance.color.opacity(ringOpacity), style: style)
                .frame(width: diameter, height: diameter)
        case .squircle:
            RoundedRectangle(cornerRadius: diameter * 0.28, style: .continuous)
                .stroke(appearance.color.opacity(ringOpacity), style: style)
                .frame(width: diameter, height: diameter)
        case .rhombus:
            RhombusShape()
                .stroke(appearance.color.opacity(ringOpacity), style: style)
                .frame(width: diameter, height: diameter)
        }
    }

    var body: some View {
        // #14 Speed Glow — 드래그 속도(pt/s)를 0~1 정규화해 glow에 추가 boost.
        // 1000pt/s에서 +1.5 boost (총 glow multiplier가 약 2배). clamping으로 over-boost 회피.
        let velocityRatio: CGFloat = min(1.0, motion.dragVelocity / 1000.0)
        let speedBoost: Double = motion.isDragging ? Double(velocityRatio) * 1.5 : 0
        let glowM = motion.glowMultiplier + speedBoost

        // #16 Velocity Stretch — jelly stretch가 속도에 비례. 느리면 거의 원형, 빠르면 더 길게.
        // 0pt/s: x=1.05, y=0.95 (약한 hint). 1000pt/s+: x=1.5, y=0.7 (max stretch).
        let xStretch: CGFloat = motion.isDragging ? 1.05 + 0.45 * velocityRatio : 1.0
        let yStretch: CGFloat = motion.isDragging ? 0.95 - 0.25 * velocityRatio : 1.0

        let g = CGFloat(glowM)
        let glowBase = appearance.borderWeight.lineWidth * 0.8 + 4
        let staticTilt: Double = appearance.isPerspectiveWarping ? 32 : 0
        let totalTilt = staticTilt + motion.clickTilt
        let glowEnabled = appearance.isGlowEnabled
        ZStack {
            // 도넛 채우기 (inner~outer 사이 반투명 fill)
            if appearance.isRingFillEnabled {
                DonutFillShape(innerDiameter: innerSize, ringShape: appearance.shape)
                    .fill(appearance.color.opacity(appearance.opacity * 0.18), style: FillStyle(eoFill: true))
                    .frame(width: appearance.size, height: appearance.size)
            }
            // 안쪽 링 (반투명)
            if appearance.hasInnerRing {
                ringShape(diameter: innerSize, style: innerStrokeStyle, ringOpacity: appearance.opacity * 0.32)
            }
            // 바깥 링 (불투명)
            ringShape(diameter: appearance.size, style: strokeStyle, ringOpacity: appearance.opacity)
        }
        .shadow(color: glowEnabled ? appearance.color.opacity(min(1, 0.9 * appearance.opacity * glowM)) : .clear, radius: glowEnabled ? glowBase * 0.9 * g : 0)
        .shadow(color: glowEnabled ? appearance.color.opacity(min(1, 0.5 * appearance.opacity * glowM)) : .clear, radius: glowEnabled ? glowBase * 2.2 * g : 0)
        .shadow(color: glowEnabled ? appearance.color.opacity(min(1, 0.2 * appearance.opacity * glowM)) : .clear, radius: glowEnabled ? glowBase * 4.0 * g : 0)
        .scaleEffect(x: xStretch, y: yStretch)
        .rotationEffect(motion.isDragging ? Angle(radians: motion.dragAngle) : .zero)
        .scaleEffect(motion.clickScale)
        .scaleEffect(motion.isDragging ? 1.0 : breathingScale)
        .rotation3DEffect(
            .degrees(totalTilt),
            axis: (x: 1, y: 0, z: 0),
            perspective: totalTilt > 0 ? 0.3 : 1.0
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: motion.isDragging)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: motion.dragAngle)
        .animation(.easeInOut(duration: 0.2), value: motion.dragVelocity)  // #14 speed glow 반응성
        .animation(.easeInOut(duration: 0.7), value: motion.glowMultiplier)
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: appearance.isPerspectiveWarping)
        .animation(.spring(response: 0.45, dampingFraction: 0.5), value: motion.clickTilt)
        .animation(.easeInOut(duration: 0.3), value: appearance.hasInnerRing)
        .animation(.none, value: position)
        .position(position)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                breathingScale = 1.08
            }
        }
    }
}

// MARK: - 돋보기

struct MagnifierView: View {
    let position: CGPoint
    let image: CGImage?
    let size: CGFloat
    let color: Color
    let ringShape: CursorSettings.RingShape

    var body: some View {
        ZStack {
            if let image {
                let scale = NSScreen.main?.backingScaleFactor ?? 1.0
                Image(decorative: image, scale: scale)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(ringShape.anyShape)
            } else {
                ringShape.anyShape
                    .fill(Color.black.opacity(0.6))
                    .frame(width: size, height: size)
            }
            ringShape.anyShape
                .stroke(color, lineWidth: 3)
                .frame(width: size, height: size)
        }
        .shadow(color: .black.opacity(0.5), radius: 24)
        .position(position)
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
    }
}

// MARK: - 클릭 파동

struct ClickRippleView: View {
    let position: CGPoint
    let isRight: Bool
    let isDouble: Bool
    let color: Color
    let rightClickUsesRingColor: Bool
    let ringShape: CursorSettings.RingShape
    let speed: Double

    var rippleColor: Color {
        if isRight { return rightClickUsesRingColor ? color : .orange }
        return isDouble ? color : .white
    }

    var body: some View {
        if isRight {
            RightClickRippleView(position: position, color: rippleColor, ringShape: ringShape, speed: speed)
        } else {
            LeftClickRippleView(position: position, color: rippleColor, isDouble: isDouble, ringShape: ringShape, speed: speed)
        }
    }
}

// 좌클릭: 원형 파동
struct LeftClickRippleView: View {
    let position: CGPoint
    let color: Color
    let isDouble: Bool
    let ringShape: CursorSettings.RingShape
    let speed: Double
    @State private var scale: CGFloat = 0.4
    @State private var opacity: Double = 0.9

    var body: some View {
        ringShape.anyShape
            .stroke(color.opacity(opacity), lineWidth: isDouble ? 3 : 2.5)
            .frame(width: 52, height: 52)
            .scaleEffect(scale)
            .position(position)
            .onAppear {
                withAnimation(.easeOut(duration: 0.55 * speed)) {
                    scale = isDouble ? 2.0 : 1.6
                    opacity = 0
                }
            }
    }
}

// 우클릭: 마름모 2중 파동
struct RightClickRippleView: View {
    let position: CGPoint
    let color: Color
    let ringShape: CursorSettings.RingShape
    let speed: Double
    @State private var scale1: CGFloat = 0.3
    @State private var scale2: CGFloat = 0.3
    @State private var opacity1: Double = 0.95
    @State private var opacity2: Double = 0.7
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            ringShape.anyShape
                .stroke(color.opacity(opacity1), lineWidth: 2.5)
                .frame(width: 52, height: 52)
                .scaleEffect(scale1)
                .rotationEffect(.degrees(rotation))
            ringShape.anyShape
                .stroke(color.opacity(opacity2), lineWidth: 1.5)
                .frame(width: 52, height: 52)
                .scaleEffect(scale2)
                .rotationEffect(.degrees(rotation + 45))
        }
        .position(position)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5 * speed)) {
                scale1 = 1.8
                opacity1 = 0
                rotation = 30
            }
            withAnimation(.easeOut(duration: 0.7 * speed).delay(0.08)) {
                scale2 = 2.3
                opacity2 = 0
            }
        }
    }
}

// MARK: - 더블클릭 버스트

struct DoubleClickBurstView: View {
    let position: CGPoint
    let color: Color
    let ringShape: CursorSettings.RingShape
    let speed: Double
    @State private var scale: CGFloat = 0.2
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            ringShape.anyShape.fill(color.opacity(0.25)).frame(width: 65, height: 65)
            ringShape.anyShape.stroke(color, lineWidth: 2.5).frame(width: 85, height: 85)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .position(position)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45 * speed)) { scale = 1.7; opacity = 0 }
        }
    }
}

// MARK: - 키스트로크 표시

struct KeystrokeDisplayView: View {
    let text: String
    let isVisible: Bool
    let position: CGPoint

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: 30, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.xl)
                    .fill(Tokens.Surface.panel)
                    .shadow(color: .black.opacity(0.4), radius: 12)
            )
            .opacity(isVisible ? 1 : 0)
            .position(position)
            .animation(.easeInOut(duration: 0.2), value: isVisible)
    }
}

// MARK: - 스크롤 인디케이터

struct ScrollIndicatorView: View {
    let position: CGPoint
    let isPositive: Bool
    let isVertical: Bool
    let magnitude: CGFloat   // 스크롤 양 — 화살표 크기 비례
    let speed: Double
    // 시작: 커서 위 36pt baseline. onAppear에서 스크롤 방향으로 ±dist 추가 이동.
    @State private var opacity: Double = 0.9
    @State private var offset: CGSize = CGSize(width: 0, height: -36)

    private var arrow: String {
        if isVertical { return isPositive ? "↑" : "↓" }
        else          { return isPositive ? "→" : "←" }
    }

    /// magnitude→폰트 사이즈 매핑. 트랙패드 1지손(~5) = 18pt(기본), 휠 한 칸(~10) = 22pt, 강한 swipe(50+) = 36pt.
    private var fontSize: CGFloat {
        let clamped = min(max(magnitude, 3), 60)
        return 16 + clamped * 0.36   // 3→17.1, 10→19.6, 30→26.8, 60→37.6
    }

    var body: some View {
        Text(arrow)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.6)))
            .opacity(opacity)
            .offset(offset)
            .position(position)
            .onAppear {
                let dist: CGFloat = 14
                let baselineY: CGFloat = -36
                withAnimation(.easeOut(duration: 0.5 * speed)) {
                    if isVertical {
                        // 위 스크롤이면 더 위로, 아래 스크롤이면 baseline에서 아래로
                        offset = CGSize(width: 0, height: baselineY + (isPositive ? -dist : dist))
                    } else {
                        // 가로 스크롤은 baseline 유지하며 좌/우로 이동
                        offset = CGSize(width: isPositive ? dist : -dist, height: baselineY)
                    }
                    opacity = 0
                }
            }
    }
}

// MARK: - 휠 클릭 (button 2) — 회전 파동
//
// 두 개의 짧은 호(arc)가 반대 방향으로 회전하며 확장 fade out — 좌/우 클릭의 단순 파동과 차별.
// "휠 클릭"의 회전 의미가 시각적으로 전달됨.
struct MiddleClickEffectView: View {
    let position: CGPoint
    let color: Color
    let ringShape: CursorSettings.RingShape
    let speed: Double
    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 1.0
    @State private var rotation: Double = 0

    var body: some View {
        // ring shape 2개가 반대 방향으로 회전하며 확장 — "휠 클릭"의 회전 의미.
        // 원형은 회전이 안 보이지만 2중 확장으로 구별, 둥근 사각형·마름모는 회전이 뚜렷.
        ZStack {
            ringShape.anyShape
                .stroke(color, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(rotation))
            ringShape.anyShape
                .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(-rotation))
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .position(position)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7 * speed)) {
                scale = 1.6
                opacity = 0
                rotation = 90
            }
        }
    }
}

// MARK: - 드래그 각도 라벨
//
// 드래그 중 cursor 우상단에 작은 라벨 "↗ 45°". 도면/일러스트레이션에서 각도 확인용.
// CGEvent y축이 top-left이라 atan2(dy, dx)는 -π~+π. 우리는 +y가 아래로 향하는 화면 좌표라
// "양수 각도 = 시계방향". 사용자 직관에 맞게 시계 12시=0°, 3시=90°로 표기 (CW positive).
struct DragAngleLabel: View {
    let position: CGPoint
    let angleRadians: Double
    let distance: CGFloat

    var body: some View {
        let degrees = Self.clockwiseDegrees(fromAtan2: angleRadians)
        Text("\(Self.directionArrow(forCWDegrees: degrees)) \(degrees)° · \(Int(distance))px")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.72)))
            .offset(x: 36, y: -28)
            .position(position)
            .allowsHitTesting(false)
    }

    // MARK: - 순수 함수 (Tests/DragAngleTests.swift에서 검증)

    /// atan2(dy, dx) 결과(라디안)를 시계방향 12시=0° 기준 0~359° 정수로 변환.
    /// CGEvent y축이 top-left이라 dy 양수=아래. atan2 표준은 -π~+π → +90° 회전 후 mod 360.
    /// 예: dx=0,dy=-1 (위) → atan2=-π/2 → -90° + 90° = 0°. dx=1,dy=0 (오른쪽) → atan2=0 → 0+90 = 90°.
    static func clockwiseDegrees(fromAtan2 angleRadians: Double) -> Int {
        let raw = angleRadians * 180 / .pi
        let cw = raw + 90
        return ((Int(cw.rounded()) % 360) + 360) % 360
    }

    /// CW degrees → 8방향 화살표. 각 방향 ±22.5° 범위.
    static func directionArrow(forCWDegrees degrees: Int) -> String {
        switch degrees {
        case 338...360, 0..<23:   return "↑"
        case 23..<68:             return "↗"
        case 68..<113:            return "→"
        case 113..<158:           return "↘"
        case 158..<203:           return "↓"
        case 203..<248:           return "↙"
        case 248..<293:           return "←"
        case 293..<338:           return "↖"
        default:                  return "•"
        }
    }
}

// MARK: - Radial Menu (⌃⌥Space hold)

/// 메인 8개 sector. 12시=0, 시계방향 45°씩. 카테고리 분리:
///   위쪽 4(7·0·1·6) = 모드/표시 토글류, 아래쪽 4(5·4·3·2) = 외형 cycle류.
/// 강조된 sector는 현재 ring color(accentColor)로 액센트 + 살짝 확대.
/// dead zone 40pt — 중심 근처에서 떼면 cancel (sector=nil).
struct RadialMenuView: View {
    let center: CGPoint           // overlay 내 위치(toLocal 변환됨)
    let selectedSector: Int?
    let selectedSubItem: Int?
    let currentValues: [String]   // 각 sector의 현재 값 (8개) — 중심 컨텍스트에 표시
    let subActiveStates: [Bool]?  // 활성 sector sub들의 현재 활성 상태 — sub 라벨 강조
    let showHelp: Bool            // 처음 5회 동안만 하단에 사용법 한 줄 표시 (학습성)
    let accentColor: Color

    // 메인 sector 8종 — RadialMenuItem이 icon(SF Symbol)/label 단일 source.
    private var items: [(icon: String, label: String)] {
        CursorSettings.RadialMenuItem.allCases.map { ($0.icon, $0.label) }
    }
    // DESIGN.md "Radial" 토큰
    private let deadRadius = Tokens.Radial.deadRadius
    private let mainOuter = Tokens.Radial.mainOuter
    private let subOuter = Tokens.Radial.subOuter

    private var canvasSize: CGFloat { Tokens.Radial.canvasSize }

    var body: some View {
        ZStack {
            // 시각 가이드 ring — 메인/서브 경계와 외곽 경계를 옅게 표시 (사용자가 영역 인지)
            Circle()
                .stroke(Tokens.Stroke.guideMedium, lineWidth: 1)
                .frame(width: mainOuter * 2, height: mainOuter * 2)
            Circle()
                .stroke(Tokens.Stroke.guideWeak, lineWidth: 1)
                .frame(width: subOuter * 2, height: subOuter * 2)

            // 8개 메인 wedge (pie slice)
            ForEach(0..<8, id: \.self) { i in
                let centerAngleDeg = Double(i) * 45 - 90  // SwiftUI: 0°=오른쪽, +y=아래
                let start = Angle.degrees(centerAngleDeg - 22.5)
                let end = Angle.degrees(centerAngleDeg + 22.5)
                let isActiveSector = selectedSector == i
                let isMainSelected = isActiveSector && selectedSubItem == nil
                let fill: Color = isMainSelected
                    ? accentColor.opacity(0.9)
                    : (isActiveSector ? accentColor.opacity(0.35) : Tokens.Surface.mainIdle)
                PieWedge(startAngle: start, endAngle: end, innerRadius: deadRadius, outerRadius: mainOuter)
                    .fill(fill)
                    .overlay(
                        PieWedge(startAngle: start, endAngle: end, innerRadius: deadRadius, outerRadius: mainOuter)
                            .stroke(Tokens.Stroke.guideMedium, lineWidth: 1)
                    )
                    .animation(Tokens.Motion.select, value: isMainSelected)
            }

            // 메인 wedge 위에 아이콘 + 라벨 (SF Symbol)
            ForEach(0..<8, id: \.self) { i in
                let centerAngleDeg = Double(i) * 45 - 90
                let r = (deadRadius + mainOuter) / 2
                let rad = centerAngleDeg * .pi / 180
                VStack(spacing: 4) {
                    Image(systemName: items[i].icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white)
                    Text(items[i].label)
                        .font(Tokens.Text.captionSmall)
                        .foregroundColor(.white)
                }
                .offset(x: cos(rad) * r, y: sin(rad) * r)
            }

            // 서브 있는 sector의 외곽 호(arc) — 활성 sector는 진한 accent로, 비활성은 옅은 흰색으로 위계 차이.
            ForEach(0..<8, id: \.self) { i in
                let hasSub = (CursorSettings.RadialMenuItem(rawValue: i)?.subCount ?? 0) > 0
                if hasSub {
                    let centerAngleDeg = Double(i) * 45 - 90
                    let start = Angle.degrees(centerAngleDeg - 22.5)
                    let end = Angle.degrees(centerAngleDeg + 22.5)
                    let isActive = selectedSector == i
                    ArcStroke(startAngle: start, endAngle: end, radius: mainOuter - 1.5)
                        .stroke(isActive ? accentColor.opacity(0.95) : Tokens.Stroke.guideStrong,
                                lineWidth: isActive ? 3.0 : 1.5)
                        .animation(Tokens.Motion.easeShort, value: isActive)
                }
            }

            // 서브 wedge들 — 활성 sector에 서브가 있을 때 메인 sector 안에 균등 분할로 외부 확장
            if let sec = selectedSector,
               let item = CursorSettings.RadialMenuItem(rawValue: sec),
               item.subCount > 0 {
                let subItems = item.subItems
                let mainCenterDeg = Double(sec) * 45 - 90
                let subSpan = item.subSpan  // 항목 많을수록 확장(최대 120°) — 라벨 겹침 방지
                let step = subSpan / Double(item.subCount)
                let subStart = mainCenterDeg - subSpan/2
                ForEach(0..<item.subCount, id: \.self) { i in
                    let s = Angle.degrees(subStart + step * Double(i))
                    let e = Angle.degrees(subStart + step * Double(i + 1))
                    let isSubSelected = selectedSubItem == i
                    let isCurrentSub = subActiveStates?[i] ?? false
                    // 바탕색 3단계로 상태 표시:
                    //   hover(곧 실행) → accent 0.9 (강조)
                    //   current(현재 설정값/켜짐) → accent 0.40 (옅은 액센트)
                    //   inactive → surface.subtle (어둠)
                    let fill: Color = isSubSelected
                        ? accentColor.opacity(0.9)
                        : (isCurrentSub ? accentColor.opacity(0.40) : Tokens.Surface.subtle)
                    PieWedge(startAngle: s, endAngle: e, innerRadius: mainOuter, outerRadius: subOuter)
                        .fill(fill)
                        .overlay(
                            PieWedge(startAngle: s, endAngle: e, innerRadius: mainOuter, outerRadius: subOuter)
                                .stroke(Tokens.Stroke.guideMedium, lineWidth: 1)
                        )
                        .animation(Tokens.Motion.select, value: isSubSelected)
                        .animation(Tokens.Motion.easeShort, value: isCurrentSub)
                    let subCenterDeg = subStart + step * (Double(i) + 0.5)
                    let rSub = (mainOuter + subOuter) / 2
                    let radSub = subCenterDeg * .pi / 180
                    let subItem = subItems[i]
                    HStack(spacing: 4) {
                        if let iconName = subItem.icon {
                            Image(systemName: iconName)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        Text(subItem.label)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .offset(x: cos(radSub) * rSub, y: sin(radSub) * rSub)
                }
            }

            // 중심(dead zone) 컨텍스트 — sector hover 시: 라벨+현재값 / dead zone 진입 시: ✕ 취소 affordance.
            // dead zone release는 원래도 cancel(80pt 안전선 미달)이지만, 명시 표시 없으면 사용자가 알기 어려움.
            // ESC/modifier release와 별개의 시각적 cancel 단서.
            if let sec = selectedSector {
                VStack(spacing: 3) {
                    Image(systemName: items[sec].icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Tokens.Stroke.textActive)
                    Text(items[sec].label)
                        .font(Tokens.Text.labelTiny)
                        .foregroundColor(Tokens.Stroke.textActive)
                        .lineLimit(1)
                    Text(currentValues[sec])
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Tokens.Stroke.textMuted)
                        .lineLimit(1)
                }
                .transition(.opacity)
                .animation(Tokens.Motion.easeMicro, value: selectedSector)
            } else {
                VStack(spacing: 1) {
                    Text("✕")
                        .font(.system(size: 24, weight: .light))
                        .foregroundColor(Tokens.Stroke.textActive)
                    Text("닫기")
                        .font(Tokens.Text.labelTiny)
                        .foregroundColor(Tokens.Stroke.textMuted)
                }
                .transition(.opacity)
            }

            // 헬프 텍스트 — 처음 5회 동안만 메뉴 외곽 아래에 사용법 한 줄 (학습성 보조).
            if showHelp {
                Text("방향 이동 · 클릭 실행 · ⌃⌥, 또는 ESC 닫기")
                    .font(Tokens.Text.hint)
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Tokens.Surface.veil))
                    .offset(y: subOuter + 18)
            }
        }
        .frame(width: canvasSize, height: canvasSize)
        .position(center)
        .allowsHitTesting(false)
        .transition(.opacity)  // cursor 위치에서 그 자리 페이드인 (scale은 frame 중심 anchor 때문에 화면 가운데에서 이동하는 느낌)
    }
}

/// 호(arc) stroke — 서브 있는 sector의 외곽 강조선용.
struct ArcStroke: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: c, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return p
    }
}

/// 도넛 부채꼴 — 두 동심원 사이의 sector 영역. radial menu pie wedge용.
struct PieWedge: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: c, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: c, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - 화면 좌표 인스펙터

/// ⌃⌥I 토글로 활성. cursor 우하단에 Quartz(top-left) 시스템 좌표 라벨.
/// 화면 캡처 좌표·디자인 도구 좌표계와 일치 — 디자이너·개발자 디버깅용.
struct InspectorView: View {
    let position: CGPoint
    let quartzGlobal: CGPoint

    var body: some View {
        Text("(\(Int(quartzGlobal.x)), \(Int(quartzGlobal.y)))")
            .font(Tokens.Text.mono)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Tokens.Surface.panel))
            .offset(x: 36, y: 28)  // cursor 우하단 — 드래그 각도 라벨(우상단)과 충돌 회피
            .position(position)
            .allowsHitTesting(false)
    }
}

// MARK: - 흔들기 효과

struct ShakeEffectView: View {
    let position: CGPoint
    let color: Color
    let ringShape: CursorSettings.RingShape
    let speed: Double

    var body: some View {
        ZStack {
            ExpandingRing(delay: 0.00, color: color, ringShape: ringShape, speed: speed)
            ExpandingRing(delay: 0.12, color: color, ringShape: ringShape, speed: speed)
            ExpandingRing(delay: 0.24, color: color, ringShape: ringShape, speed: speed)
        }
        .position(position)
    }
}

struct ExpandingRing: View {
    let delay: Double
    let color: Color
    let ringShape: CursorSettings.RingShape
    let speed: Double
    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 1.0

    var body: some View {
        ringShape.anyShape
            .stroke(color, lineWidth: 3)
            .frame(width: 110, height: 110)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.7 * speed).delay(delay)) { scale = 1.8 }
                withAnimation(.easeIn(duration: 0.5 * speed).delay(delay + 0.35 * speed)) { opacity = 0 }
            }
    }
}

// MARK: - 정지 펄스

/// 정지 펄스 — 1.5초 정지 시 1회 확장 fade. 현재 ring 색·모양을 따라 자연스럽게.
struct IdlePulseView: View {
    let position: CGPoint
    let color: Color
    let ringShape: CursorSettings.RingShape
    let speed: Double
    @State private var scale: CGFloat = 0.85
    @State private var opacity: Double = 0.7

    var body: some View {
        ringShape.anyShape
            .stroke(color, lineWidth: 2.5)
            .frame(width: 70, height: 70)
            .scaleEffect(scale)
            .opacity(opacity)
            .position(position)
            .onAppear {
                withAnimation(.easeOut(duration: 0.8 * speed)) {
                    scale = 1.7
                    opacity = 0
                }
            }
    }
}

// MARK: - 클립보드 인디케이터

struct ClipboardIndicatorView: View {
    let position: CGPoint
    let emoji: String
    @State private var opacity: Double = 0
    @State private var yOffset: CGFloat = 0

    var body: some View {
        Text(emoji)
            .font(.system(size: 40))
            .opacity(opacity)
            .offset(y: yOffset)
            .position(position)
            .onAppear {
                withAnimation(.easeOut(duration: 0.2)) { opacity = 1.0 }
                withAnimation(.easeOut(duration: 0.6)) { yOffset = -28 }
                withAnimation(.easeIn(duration: 0.3).delay(0.75)) { opacity = 0 }
            }
    }
}

// MARK: - 트랙패드 시스템 제스처 (4핀치 / 3·4손가락 swipe)

/// 디스패처 — gesture 종류에 맞는 시각 뷰 선택. softReveal은 swipe에만 의미 있음
/// (Space 전환 종료 후 부드러운 합류). pinch는 시스템 애니가 다른 종류라 무관.
struct TrackpadGestureVisualView: View {
    let position: CGPoint
    let gesture: TrackpadGesture
    let softReveal: Bool
    let color: Color
    let speed: Double

    var body: some View {
        switch gesture {
        case .fourFingerPinchIn:
            PinchVisualView(position: position, dotCount: 4, isPinchIn: true,  color: color, speed: speed)
        case .fourFingerPinchOut:
            PinchVisualView(position: position, dotCount: 4, isPinchIn: false, color: color, speed: speed)
        case .fiveFingerPinchIn:
            PinchVisualView(position: position, dotCount: 5, isPinchIn: true,  color: color, speed: speed)
        case .fiveFingerPinchOut:
            PinchVisualView(position: position, dotCount: 5, isPinchIn: false, color: color, speed: speed)
        default:
            if let dir = swipeDirection(for: gesture) {
                SwipeVisualView(
                    position: position,
                    direction: dir,
                    fingerCount: gesture.fingerCount,
                    softReveal: softReveal,
                    color: color,
                    speed: speed
                )
            }
        }
    }

    /// SwiftUI 화면 좌표 단위 벡터 — y는 위가 음수.
    private func swipeDirection(for g: TrackpadGesture) -> CGPoint? {
        switch g {
        case .threeFingerSwipeUp, .fourFingerSwipeUp:       return CGPoint(x: 0,  y: -1)
        case .threeFingerSwipeDown, .fourFingerSwipeDown:   return CGPoint(x: 0,  y: 1)
        case .threeFingerSwipeLeft, .fourFingerSwipeLeft:   return CGPoint(x: -1, y: 0)
        case .threeFingerSwipeRight, .fourFingerSwipeRight: return CGPoint(x: 1,  y: 0)
        default: return nil
        }
    }
}

/// 4·5손가락 핀치 — N개 dot이 중심으로 수축(In=Launchpad) 또는 바깥으로 확산(Out=Show Desktop).
/// dot 개수가 실제 손가락 수와 일치 — 4핀치는 4개, 5핀치는 5개.
struct PinchVisualView: View {
    let position: CGPoint
    let dotCount: Int       // 4 또는 5
    let isPinchIn: Bool
    let color: Color
    let speed: Double
    @State private var scale: CGFloat
    @State private var opacity: Double = 0.9

    private let outerRadius: CGFloat = 42

    init(position: CGPoint, dotCount: Int, isPinchIn: Bool, color: Color, speed: Double) {
        self.position = position
        self.dotCount = dotCount
        self.isPinchIn = isPinchIn
        self.color = color
        self.speed = speed
        _scale = State(initialValue: isPinchIn ? 1.0 : 0.1)
    }

    /// dot 개수에 따라 원주 균등 분포한 offset 계산 (SwiftUI 좌표: -y가 위).
    /// 시작 각도는 위(12시)로 — 시각적으로 안정적.
    private func offset(for i: Int) -> CGSize {
        let angle = -.pi / 2 + (2 * .pi * Double(i)) / Double(dotCount)
        return CGSize(width: cos(angle) * Double(outerRadius), height: sin(angle) * Double(outerRadius))
    }

    var body: some View {
        ZStack {
            ForEach(0..<dotCount, id: \.self) { i in
                let off = offset(for: i)
                Circle()
                    .fill(color.opacity(opacity))
                    .frame(width: 11, height: 11)
                    .offset(x: off.width * scale, y: off.height * scale)
            }
        }
        .position(position)
        .onAppear {
            withAnimation(.easeOut(duration: 0.58 * speed)) {
                scale = isPinchIn ? 0.1 : 1.35
                opacity = 0
            }
        }
    }
}

/// 3·4손가락 스와이프 — N개 평행 capsule이 direction으로 이동하며 페이드 + cursor anchor pulse.
///
/// 진단 로그 검증 (log show ... Multitouch): mid-fire가 gesture 시작 t+0.06~0.13s에
/// 즉시 발사됨. 시스템 슬라이드 시작 전에 effect는 이미 화면에 있음. 사용자가 "느리게
/// 나타난다"고 체감하는 건 slide 동안 시선이 슬라이드 따라가서 cursor 위치 effect를 놓치다가
/// slide 끝(~t=0.4)에 시선 돌아오면 그제야 보이기 때문.
///
/// 대응: effect를 slide(~0.4s) 동안은 bright 유지 → slide 끝난 뒤에도 peak 상태로 시선 catch
/// → 부드러운 페이드. fade-in 빠르게, hold 길게, fade-out 부드럽게.
struct SwipeVisualView: View {
    let position: CGPoint
    let direction: CGPoint    // 단위 벡터 (SwiftUI 좌표; -y가 위)
    let fingerCount: Int      // 3 또는 4
    let softReveal: Bool      // true면 슬라이드 종료 후 합류용 느린 fade-in
    let color: Color
    let speed: Double
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 0.0
    @State private var anchorScale: CGFloat = 0.5
    @State private var anchorOpacity: Double = 0.65

    private let travelDistance: CGFloat = 44
    private let lateralSpacing: CGFloat = 15

    var body: some View {
        let perpX = -direction.y
        let perpY = direction.x
        let angle = atan2(direction.y, direction.x) + .pi / 2

        ZStack {
            Circle()
                .fill(color.opacity(anchorOpacity))
                .frame(width: 56, height: 56)
                .scaleEffect(anchorScale)
                .blur(radius: 7)

            ForEach(0..<fingerCount, id: \.self) { i in
                let lateral = (CGFloat(i) - CGFloat(fingerCount - 1) / 2) * lateralSpacing
                Capsule()
                    .fill(color.opacity(opacity))
                    .frame(width: 10, height: 36)
                    .rotationEffect(.radians(Double(angle)))
                    .offset(
                        x: perpX * lateral + direction.x * offset,
                        y: perpY * lateral + direction.y * offset
                    )
            }
        }
        .position(position)
        .onAppear {
            // softReveal: 슬라이드 종료 후 재발사 — 느린 fade-in으로 갑작스러움 회피.
            // 0.50s fade-in → 슬라이드 마무리 시점에 천천히 emerge, 사용자가 fade-in 전체 다 봄.
            // 일반: 즉시 punchy 등장 (양끝단·수직·핀치).
            let fadeInDuration = softReveal ? 0.50 : 0.10
            let anchorOpacityStart = softReveal ? 0.45 : 0.65
            let anchorDuration = softReveal ? 1.00 : 0.70

            // anchor pulse 초기값 보정 (softReveal면 낮은 시작)
            if softReveal {
                anchorOpacity = 0.45
            }

            withAnimation(.easeInOut(duration: fadeInDuration * speed)) {
                opacity = 1.0
            }
            // softReveal면 이동도 천천히 + 페이드 아웃 더 늦게 (fade-in이 끝난 뒤 peak hold가 있어야 또렷이 인지)
            let travelDuration = softReveal ? 1.10 : 0.85
            let fadeOutDelay = softReveal ? 0.80 : 0.55
            let fadeOutDuration = softReveal ? 0.65 : 0.60
            withAnimation(.easeOut(duration: travelDuration * speed)) {
                offset = travelDistance
            }
            withAnimation(.easeIn(duration: fadeOutDuration * speed).delay(fadeOutDelay * speed)) {
                opacity = 0
            }
            // anchor pulse — softReveal면 더 천천히 확산, peak도 부드럽게.
            withAnimation(.easeOut(duration: anchorDuration * speed)) {
                anchorScale = 1.9
                anchorOpacity = 0
            }
            _ = anchorOpacityStart  // (placeholder — 향후 더 미세 조정시 사용)
        }
    }
}

// MARK: - 그리기 도형 (#19, ⌃⌥D)

/// Quartz 좌표(원점 top-left) → overlay 로컬 좌표(원점 top-left, screenFrame 기준) 변환 후 Canvas로 stroke.
/// 도구 7종: 펜·직선·화살표·사각형·타원·형광펜·뱃지 — 각각 다른 렌더 분기.
struct DrawnShapeView: View {
    let shape: DrawingState.Shape
    let screenFrame: CGRect

    private let headLen = Tokens.Drawing.arrowHeadLength
    private let headAngle = Tokens.Drawing.arrowHeadAngle

    var body: some View {
        Canvas { context, _ in
            // Cocoa→overlay 변환 (overlay window는 NSWindow contentRect = screenFrame, y-flip은 SwiftUI가 처리)
            let pts = shape.points.map { p in
                CGPoint(x: p.x - screenFrame.minX, y: screenFrame.maxY - p.y)
            }
            guard pts.count >= 1 else { return }
            let lw = shape.lineWidth
            let stroke = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)

            switch shape.tool {
            case .pen:
                var path = Path()
                path.move(to: pts[0])
                for p in pts.dropFirst() { path.addLine(to: p) }
                context.stroke(path, with: .color(shape.color), style: stroke)
            case .line:
                guard pts.count >= 2 else { return }
                var path = Path()
                path.move(to: pts[0])
                path.addLine(to: pts[1])
                context.stroke(path, with: .color(shape.color), style: stroke)
            case .arrow:
                guard pts.count >= 2 else { return }
                let start = pts[0]
                let end = pts[1]
                var shaft = Path()
                shaft.move(to: start)
                shaft.addLine(to: end)
                context.stroke(shaft, with: .color(shape.color), style: stroke)
                let dx = end.x - start.x
                let dy = end.y - start.y
                let angle = atan2(dy, dx)
                let p1 = CGPoint(x: end.x - headLen * cos(angle - headAngle),
                                 y: end.y - headLen * sin(angle - headAngle))
                let p2 = CGPoint(x: end.x - headLen * cos(angle + headAngle),
                                 y: end.y - headLen * sin(angle + headAngle))
                var head = Path()
                head.move(to: p1)
                head.addLine(to: end)
                head.addLine(to: p2)
                context.stroke(head, with: .color(shape.color), style: stroke)
            case .rectangle:
                guard pts.count >= 2 else { return }
                let r = CGRect(x: min(pts[0].x, pts[1].x), y: min(pts[0].y, pts[1].y),
                               width: abs(pts[1].x - pts[0].x), height: abs(pts[1].y - pts[0].y))
                context.stroke(Path(r), with: .color(shape.color), style: stroke)
            case .ellipse:
                guard pts.count >= 2 else { return }
                let r = CGRect(x: min(pts[0].x, pts[1].x), y: min(pts[0].y, pts[1].y),
                               width: abs(pts[1].x - pts[0].x), height: abs(pts[1].y - pts[0].y))
                context.stroke(Path(ellipseIn: r), with: .color(shape.color), style: stroke)
            case .highlighter:
                // pen과 같은 path지만 굵고 반투명 — "이 영역 보세요"
                var path = Path()
                path.move(to: pts[0])
                for p in pts.dropFirst() { path.addLine(to: p) }
                let hStroke = StrokeStyle(lineWidth: Tokens.Drawing.highlighterWidth, lineCap: .round, lineJoin: .round)
                context.stroke(path, with: .color(shape.color.opacity(Tokens.Drawing.highlighterOpacity)), style: hStroke)
            case .badge:
                // 번호 뱃지 — 채워진 원 + 외곽선 + 가운데 숫자. 휘도 기준으로 contrast 자동 (밝은 색 = 검정 텍스트).
                guard let number = shape.badgeNumber else { return }
                let center = pts[0]
                let radius = Tokens.Drawing.badgeRadius
                let rect = CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(shape.color))
                let darkText = shape.color.needsDarkText
                let strokeColor: Color = darkText ? .black.opacity(0.55) : .white.opacity(0.85)
                context.stroke(Path(ellipseIn: rect),
                               with: .color(strokeColor),
                               style: StrokeStyle(lineWidth: Tokens.Drawing.badgeBorderWidth))
                let text = Text("\(number)")
                    .font(.system(size: Tokens.Drawing.badgeFontSize, weight: .bold))
                    .foregroundColor(darkText ? .black : .white)
                context.draw(text, at: center, anchor: .center)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 그리기 모드 toolbar (v0.7.0)

/// 도구 버튼 영역(SwiftUI .global 좌표) 측정용. OverlayContentView가 Cocoa global로 변환해 drawing.toolbarFrames에 저장.
struct ToolFramePreference: PreferenceKey {
    static var defaultValue: [DrawingState.Tool: CGRect] = [:]
    static func reduce(value: inout [DrawingState.Tool: CGRect], nextValue: () -> [DrawingState.Tool: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// 두께 dot 영역 측정.
struct ThicknessFramePreference: PreferenceKey {
    static var defaultValue: [CGFloat: CGRect] = [:]
    static func reduce(value: inout [CGFloat: CGRect], nextValue: () -> [CGFloat: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// 색 dot 영역 측정. 키는 RingColor.rawValue.
struct ColorFramePreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Drag handle 영역 측정 — 단일 frame.
struct DragHandleFramePreference: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let n = nextValue()
        if n != .zero { value = n }
    }
}

/// Toolbar 전체 크기 측정 — clamp 계산에 사용 (실제 너비 알아야 정확한 한계).
struct ToolbarSizePreference: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let n = nextValue()
        if n != .zero { value = n }
    }
}

/// 좌측 하단 modern floating panel — 도구 7 + 두께 5 + 색 7. Modifier에 따라 active 도구 실시간 강조.
/// 라벨/cheat sheet 제거 (Apple Notes·Figma·Linear 패턴). 모디파이어/단축키는 onboarding capsule 5회 + 도구 클릭 알림으로 전달.
/// Vibrancy material + 통일된 selection ring으로 modern feel.
struct DrawingToolbarView: View {
    @ObservedObject var drawing: DrawingState
    @ObservedObject var settings: CursorSettings
    let accentColor: Color

    private struct ToolSpec {
        let tool: DrawingState.Tool
        let icon: String
    }

    private let specs: [ToolSpec] = [
        .init(tool: .pen,         icon: "scribble.variable"),
        .init(tool: .line,        icon: "line.diagonal"),
        .init(tool: .arrow,       icon: "arrow.up.right"),
        .init(tool: .rectangle,   icon: "rectangle"),
        .init(tool: .ellipse,     icon: "circle"),
        .init(tool: .highlighter, icon: "highlighter"),
        .init(tool: .badge,       icon: "1.circle.fill"),
    ]

    var body: some View {
        let active = drawing.previewTool
        HStack(spacing: Tokens.Drawing.Toolbar.groupSpacing) {
            // Drag handle (좌측, 작게) — 클릭+드래그로 toolbar 이동
            dragHandle
            // 7 도구 — primary 영역, 라벨/모디파이어 hint 제거
            HStack(spacing: 6) {
                ForEach(specs.indices, id: \.self) { i in
                    toolButton(specs[i], isActive: specs[i].tool == active)
                }
            }
            // 두께 5단계 — section 라벨 제거, dot만
            HStack(spacing: 4) {
                ForEach(Tokens.Drawing.lineWidthSteps, id: \.self) { w in
                    thicknessButton(width: w)
                }
            }
            // 색 7가지 — section 라벨 제거, dot만. 각 dot에 단축키 번호 overlay (a11y).
            HStack(spacing: 4) {
                ForEach(CursorSettings.RingColor.allCases.filter { $0 != .custom }) { c in
                    colorButton(color: c)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // Vibrancy material — modern macOS Sonoma+ floating panel 컨벤션. Dark mode 강제로 발표 콘텐츠와 색 충돌 회피.
        .background(.regularMaterial)
        .environment(\.colorScheme, .dark)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Drawing.Toolbar.cornerRadius)
                .stroke(Color.white.opacity(Tokens.Drawing.Toolbar.borderOpacity), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Drawing.Toolbar.cornerRadius))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        // 전체 size 측정 — clamp 계산용
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: ToolbarSizePreference.self, value: geo.size)
            }
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func toolButton(_ spec: ToolSpec, isActive: Bool) -> some View {
        let isSelected = drawing.selectedTool == spec.tool
        // 색은 외곽 ring(작은 면적)에만 들어가고 배경/glyph는 ringColor 무관 고정.
        // → ringColor 변경 시 luminance contrast 문제 발생 안 함.
        ZStack {
            Circle()
                .fill(isActive ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                .frame(width: Tokens.Drawing.Toolbar.toolCircle, height: Tokens.Drawing.Toolbar.toolCircle)
            // active(preview) = 진한 ringColor ring / sticky-only = 옅은 ring (modifier 떼면 복귀할 곳)
            if isActive {
                Circle()
                    .stroke(accentColor, lineWidth: Tokens.Drawing.Toolbar.selectionRingWidth)
                    .frame(width: Tokens.Drawing.Toolbar.toolCircle, height: Tokens.Drawing.Toolbar.toolCircle)
            } else if isSelected {
                Circle()
                    .stroke(accentColor.opacity(0.45), lineWidth: 1)
                    .frame(width: Tokens.Drawing.Toolbar.toolCircle, height: Tokens.Drawing.Toolbar.toolCircle)
            }
            Image(systemName: spec.icon)
                .font(.system(size: Tokens.Drawing.Toolbar.toolGlyph, weight: .semibold))
                .foregroundColor(.white)
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ToolFramePreference.self,
                    value: [spec.tool: geo.frame(in: .global)]
                )
            }
        )
        .animation(.easeOut(duration: 0.12), value: isActive)
    }

    @ViewBuilder
    private func thicknessButton(width w: CGFloat) -> some View {
        let isSelected = abs(w - drawing.lineWidth) < 0.01
        // 두께 dot은 "두께"를 시각화 — 색은 무관(고정 grayscale). selection은 외곽 ringColor ring.
        ZStack {
            // hit-test 영역 — 작은 dot이라도 클릭 area 넓게
            Color.clear.frame(width: Tokens.Drawing.Toolbar.thicknessHitArea, height: Tokens.Drawing.Toolbar.thicknessHitArea)
            Circle()
                .fill(Color.white.opacity(isSelected ? 0.85 : 0.30))
                .frame(width: w * 0.6 + 4, height: w * 0.6 + 4)  // 두께 비례
            if isSelected {
                Circle()
                    .stroke(accentColor, lineWidth: Tokens.Drawing.Toolbar.selectionRingWidth)
                    .frame(width: w * 0.6 + 8, height: w * 0.6 + 8)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ThicknessFramePreference.self,
                    value: [w: geo.frame(in: .global)]
                )
            }
        )
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    /// Compact drag grip (좌측). 4 dot (2x2)으로 6 dot 대비 시각 노이즈 ↓ — modern minimal.
    /// 클릭 + 드래그로 toolbar 이동.
    private var dragHandle: some View {
        VStack(spacing: Tokens.Drawing.Toolbar.dragHandleDotSpacing) {
            ForEach(0..<2) { _ in
                HStack(spacing: Tokens.Drawing.Toolbar.dragHandleDotSpacing) {
                    Circle().fill(Color.white.opacity(drawing.isDraggingToolbar ? 0.95 : 0.4))
                        .frame(width: Tokens.Drawing.Toolbar.dragHandleDot, height: Tokens.Drawing.Toolbar.dragHandleDot)
                    Circle().fill(Color.white.opacity(drawing.isDraggingToolbar ? 0.95 : 0.4))
                        .frame(width: Tokens.Drawing.Toolbar.dragHandleDot, height: Tokens.Drawing.Toolbar.dragHandleDot)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: DragHandleFramePreference.self,
                    value: geo.frame(in: .global)
                )
            }
        )
        .animation(.easeOut(duration: 0.12), value: drawing.isDraggingToolbar)
    }

    /// 색 → 단축키 번호 매핑 (a11y secondary 채널 — 색맹 사용자도 식별 가능).
    /// ⌃⌥1~7 색 직접, ⌃⌥C 색 순환. 숫자는 색 전용 (확장 안전).
    private func keyHint(for color: CursorSettings.RingColor) -> String? {
        switch color {
        case .yellow: return "1"
        case .red:    return "2"
        case .blue:   return "3"
        case .green:  return "4"
        case .cyan:   return "5"
        case .purple: return "6"
        case .white:  return "7"
        case .custom: return nil
        }
    }

    @ViewBuilder
    private func colorButton(color: CursorSettings.RingColor) -> some View {
        let isSelected = settings.ringColor == color
        let hint = keyHint(for: color)
        ZStack {
            Color.clear.frame(width: Tokens.Drawing.Toolbar.colorHitArea, height: Tokens.Drawing.Toolbar.colorHitArea)
            Circle()
                .fill(color.color)
                .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                .frame(width: Tokens.Drawing.Toolbar.colorDot, height: Tokens.Drawing.Toolbar.colorDot)
            if isSelected {
                // 짝수 hit area(24) - 2 = 22 짝수 → ZStack 중심선 픽셀 정렬 (sub-pixel 어긋남 X)
                // 밝은 dot(흰·노란·하늘)은 흰 ring이 본체와 union되므로 검정으로 반전
                Circle()
                    .stroke(color.needsDarkText ? Color.black.opacity(0.85) : Color.white.opacity(0.95),
                            lineWidth: Tokens.Drawing.Toolbar.selectionRingWidth)
                    .frame(width: Tokens.Drawing.Toolbar.colorHitArea - 2, height: Tokens.Drawing.Toolbar.colorHitArea - 2)
            }
            // 단축키 번호 overlay — 색 외 두번째 식별 채널.
            // 휘도 기준 contrast: 밝은 색(yellow/white/green/cyan)엔 검정, 어두운 색(red/blue/purple)엔 흰. 양쪽 다 반대 색 그림자로 대비 강화.
            if let hint {
                let darkText = color.needsDarkText
                Text(hint)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(darkText ? .black.opacity(0.85) : .white.opacity(0.95))
                    .shadow(color: (darkText ? Color.white : Color.black).opacity(0.4), radius: 0.5)
                    .frame(width: Tokens.Drawing.Toolbar.colorDot, height: Tokens.Drawing.Toolbar.colorDot, alignment: .center)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ColorFramePreference.self,
                    value: [color.rawValue: geo.frame(in: .global)]
                )
            }
        )
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}
