import SwiftUI

struct OverlayContentView: View {
    @ObservedObject var settings: CursorSettings
    @ObservedObject var runtime: CursorRuntimeState
    @ObservedObject var effects: EffectsState
    @ObservedObject var keystroke: KeystrokeOverlayState
    let screenFrame: CGRect

    private var localPos: CGPoint { toLocal(runtime.cursorPosition) }
    private var cursorOnScreen: Bool { screenFrame.contains(runtime.cursorPosition) }
    private var speed: Double { settings.animationSpeed.multiplier }
    private var effectiveColor: Color {
        settings.ringColor == .custom ? settings.customRingColor : settings.ringColor.color
    }

    var body: some View {
        ZStack {
            // 스포트라이트
            if runtime.isSpotlightActive {
                if cursorOnScreen { SpotlightView(position: localPos, radius: settings.spotlightRadius) }
                else              { Color.black.opacity(0.78) }
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

            // 클릭 파동
            ForEach(effects.clickEffects) { effect in
                if screenFrame.contains(effect.position) {
                    ClickRippleView(
                        position: toLocal(effect.position),
                        isRight: effect.isRight,
                        isDouble: effect.isDouble,
                        color: effectiveColor,
                        rightClickUsesRingColor: settings.rightClickUsesRingColor,
                        speed: speed
                    )
                }
            }

            // 더블클릭 버스트
            ForEach(effects.doubleClickEffects) { effect in
                if screenFrame.contains(effect.position) {
                    DoubleClickBurstView(position: toLocal(effect.position), color: effectiveColor, speed: speed)
                }
            }

            // 휠 클릭 (button 2) — 회전 파동
            ForEach(effects.middleClickEffects) { effect in
                if screenFrame.contains(effect.position) {
                    MiddleClickEffectView(position: toLocal(effect.position), color: effectiveColor, speed: speed)
                }
            }

            // 흔들기
            ForEach(effects.shakeEffects) { effect in
                if screenFrame.contains(effect.position) {
                    ShakeEffectView(position: toLocal(effect.position), color: effectiveColor, speed: speed)
                }
            }

            // 스크롤 인디케이터
            if settings.isScrollIndicatorEnabled {
                ForEach(effects.scrollEffects) { effect in
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
            ForEach(effects.clipboardEffects) { effect in
                if screenFrame.contains(effect.position) {
                    ClipboardIndicatorView(position: toLocal(effect.position), emoji: effect.emoji)
                }
            }

            // 돋보기
            if runtime.isMagnifierActive && cursorOnScreen {
                MagnifierView(
                    position: localPos,
                    image: runtime.magnifierImage,
                    size: settings.magnifierSize,
                    color: effectiveColor
                )
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
}

// MARK: - 스포트라이트

struct SpotlightView: View {
    let position: CGPoint
    let radius: CGFloat

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.78)))
            context.blendMode = .clear
            context.fill(
                Path(ellipseIn: CGRect(x: position.x - radius, y: position.y - radius,
                                       width: radius * 2, height: radius * 2)),
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

    var body: some View {
        ZStack {
            if let image {
                let scale = NSScreen.main?.backingScaleFactor ?? 1.0
                Image(decorative: image, scale: scale)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: size, height: size)
            }
            Circle()
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
    let speed: Double

    var rippleColor: Color {
        if isRight { return rightClickUsesRingColor ? color : .orange }
        return isDouble ? color : .white
    }

    var body: some View {
        if isRight {
            RightClickRippleView(position: position, color: rippleColor, speed: speed)
        } else {
            LeftClickRippleView(position: position, color: rippleColor, isDouble: isDouble, speed: speed)
        }
    }
}

// 좌클릭: 원형 파동
struct LeftClickRippleView: View {
    let position: CGPoint
    let color: Color
    let isDouble: Bool
    let speed: Double
    @State private var scale: CGFloat = 0.4
    @State private var opacity: Double = 0.9

    var body: some View {
        Circle()
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
    let speed: Double
    @State private var scale1: CGFloat = 0.3
    @State private var scale2: CGFloat = 0.3
    @State private var opacity1: Double = 0.95
    @State private var opacity2: Double = 0.7
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            RhombusShape()
                .stroke(color.opacity(opacity1), lineWidth: 2.5)
                .frame(width: 52, height: 52)
                .scaleEffect(scale1)
                .rotationEffect(.degrees(rotation))
            RhombusShape()
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
    let speed: Double
    @State private var scale: CGFloat = 0.2
    @State private var opacity: Double = 1.0

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.25)).frame(width: 65, height: 65)
            Circle().stroke(color, lineWidth: 2.5).frame(width: 85, height: 85)
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
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.72))
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
    let speed: Double
    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 1.0
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // 시계방향 호 (위쪽 1/4)
            Arc(startAngle: .degrees(-45), endAngle: .degrees(45))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 70, height: 70)
                .rotationEffect(.degrees(rotation))
            // 반시계 호 (아래쪽 1/4)
            Arc(startAngle: .degrees(135), endAngle: .degrees(225))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 70, height: 70)
                .rotationEffect(.degrees(-rotation))
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .position(position)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7 * speed)) {
                scale = 1.6
                opacity = 0
                rotation = 180
            }
        }
    }
}

/// 단순 호 Shape — startAngle ~ endAngle 사이 호만 그림.
private struct Arc: Shape {
    let startAngle: Angle
    let endAngle: Angle
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }
}

// MARK: - 흔들기 효과

struct ShakeEffectView: View {
    let position: CGPoint
    let color: Color
    let speed: Double

    var body: some View {
        ZStack {
            ExpandingRing(delay: 0.00, color: color, speed: speed)
            ExpandingRing(delay: 0.12, color: color, speed: speed)
            ExpandingRing(delay: 0.24, color: color, speed: speed)
        }
        .position(position)
    }
}

struct ExpandingRing: View {
    let delay: Double
    let color: Color
    let speed: Double
    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
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
