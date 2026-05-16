import SwiftUI

struct OverlayContentView: View {
    @ObservedObject var state: CursorState
    let screenFrame: CGRect

    private var localPos: CGPoint { toLocal(state.cursorPosition) }
    private var cursorOnScreen: Bool { screenFrame.contains(state.cursorPosition) }
    private var speed: Double { state.animationSpeed.multiplier }
    private var effectiveColor: Color {
        state.ringColor == .custom ? state.customRingColor : state.ringColor.color
    }

    var body: some View {
        ZStack {
            // 스포트라이트
            if state.isSpotlightActive {
                if cursorOnScreen { SpotlightView(position: localPos, radius: state.spotlightRadius) }
                else              { Color.black.opacity(0.78) }
            }

            // 커서 트레일 — 좌표 변환은 TrailView 내부에서 (body 재계산 시 매번 filter+map 회피)
            if state.isTrailEnabled && !state.trailPoints.isEmpty {
                TrailView(trailPoints: state.trailPoints, screenFrame: screenFrame, color: effectiveColor)
            }

            // 커서 링
            if cursorOnScreen && state.isCursorVisible {
                CursorRingView(
                    position: localPos,
                    color: effectiveColor,
                    size: state.ringSize.diameter,
                    shape: state.ringShape,
                    opacity: state.ringOpacity,
                    clickScale: state.ringClickScale,
                    clickTilt: state.ringClickTilt,
                    isDragging: state.isDragging,
                    dragAngle: state.dragAngle,
                    glowMultiplier: state.glowMultiplier,
                    borderWeight: state.borderWeight,
                    borderStyle: state.borderStyle,
                    isPerspectiveWarping: state.isPerspectiveWarping,
                    hasInnerRing: state.hasInnerRing,
                    isRingFillEnabled: state.isRingFillEnabled,
                    isGlowEnabled: state.isGlowEnabled
                )
            }

            // 클릭 파동
            ForEach(state.clickEffects) { effect in
                if screenFrame.contains(effect.position) {
                    ClickRippleView(
                        position: toLocal(effect.position),
                        isRight: effect.isRight,
                        isDouble: effect.isDouble,
                        color: effectiveColor,
                        rightClickUsesRingColor: state.rightClickUsesRingColor,
                        speed: speed
                    )
                }
            }

            // 더블클릭 버스트
            ForEach(state.doubleClickEffects) { effect in
                if screenFrame.contains(effect.position) {
                    DoubleClickBurstView(position: toLocal(effect.position), color: effectiveColor, speed: speed)
                }
            }

            // 흔들기
            ForEach(state.shakeEffects) { effect in
                if screenFrame.contains(effect.position) {
                    ShakeEffectView(position: toLocal(effect.position), color: effectiveColor, speed: speed)
                }
            }

            // 스크롤 인디케이터
            if state.isScrollIndicatorEnabled {
                ForEach(state.scrollEffects) { effect in
                    if screenFrame.contains(effect.position) {
                        ScrollIndicatorView(
                            position: toLocal(effect.position),
                            isPositive: effect.isPositive,
                            isVertical: effect.isVertical,
                            speed: speed
                        )
                    }
                }
            }

            // 클립보드 인디케이터
            ForEach(state.clipboardEffects) { effect in
                if screenFrame.contains(effect.position) {
                    ClipboardIndicatorView(position: toLocal(effect.position), emoji: effect.emoji)
                }
            }

            // 돋보기
            if state.isMagnifierActive && cursorOnScreen {
                MagnifierView(
                    position: localPos,
                    image: state.magnifierImage,
                    size: state.magnifierSize,
                    color: effectiveColor
                )
            }

            // 키스트로크 / 상태 알림 (항상 트리에 포함 - 비활성 시 알림도 표시되어야 함)
            KeystrokeDisplayView(
                text: state.keystrokeText,
                isVisible: state.isKeystrokeVisible,
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

// MARK: - 커서 트레일

struct TrailView: View {
    let trailPoints: [CursorState.TrailPoint]
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
    let ringShape: CursorState.RingShape

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

struct CursorRingView: View {
    let position: CGPoint
    let color: Color
    let size: CGFloat
    let shape: CursorState.RingShape
    let opacity: Double
    let clickScale: CGFloat
    let clickTilt: Double
    let isDragging: Bool
    let dragAngle: Double
    let glowMultiplier: Double
    let borderWeight: CursorState.BorderWeight
    let borderStyle: CursorState.BorderStyle
    let isPerspectiveWarping: Bool
    let hasInnerRing: Bool
    let isRingFillEnabled: Bool
    let isGlowEnabled: Bool

    @State private var breathingScale: CGFloat = 0.94

    private var strokeStyle: StrokeStyle {
        let lw = borderWeight.lineWidth
        return StrokeStyle(
            lineWidth: lw,
            lineCap: .round,
            dash: borderStyle == .dashed ? [lw * 2.2, lw * 1.4] : []
        )
    }

    private var innerStrokeStyle: StrokeStyle {
        let lw = borderWeight.lineWidth * 0.55
        return StrokeStyle(lineWidth: lw, lineCap: .round)
    }

    private var innerSize: CGFloat { size * 0.76 }

    @ViewBuilder
    private func ringShape(diameter: CGFloat, style: StrokeStyle, ringOpacity: Double) -> some View {
        switch shape {
        case .circle:
            Circle()
                .stroke(color.opacity(ringOpacity), style: style)
                .frame(width: diameter, height: diameter)
        case .squircle:
            RoundedRectangle(cornerRadius: diameter * 0.28, style: .continuous)
                .stroke(color.opacity(ringOpacity), style: style)
                .frame(width: diameter, height: diameter)
        case .rhombus:
            RhombusShape()
                .stroke(color.opacity(ringOpacity), style: style)
                .frame(width: diameter, height: diameter)
        }
    }

    var body: some View {
        let g = CGFloat(glowMultiplier)
        let glowBase = borderWeight.lineWidth * 0.8 + 4
        let staticTilt: Double = isPerspectiveWarping ? 32 : 0
        let totalTilt = staticTilt + clickTilt
        ZStack {
            // 도넛 채우기 (inner~outer 사이 반투명 fill)
            if isRingFillEnabled {
                DonutFillShape(innerDiameter: innerSize, ringShape: shape)
                    .fill(color.opacity(opacity * 0.18), style: FillStyle(eoFill: true))
                    .frame(width: size, height: size)
            }
            // 안쪽 링 (반투명)
            if hasInnerRing {
                ringShape(diameter: innerSize, style: innerStrokeStyle, ringOpacity: opacity * 0.32)
            }
            // 바깥 링 (불투명)
            ringShape(diameter: size, style: strokeStyle, ringOpacity: opacity)
        }
        .shadow(color: isGlowEnabled ? color.opacity(min(1, 0.9 * opacity * glowMultiplier)) : .clear, radius: isGlowEnabled ? glowBase * 0.9 * g : 0)
        .shadow(color: isGlowEnabled ? color.opacity(min(1, 0.5 * opacity * glowMultiplier)) : .clear, radius: isGlowEnabled ? glowBase * 2.2 * g : 0)
        .shadow(color: isGlowEnabled ? color.opacity(min(1, 0.2 * opacity * glowMultiplier)) : .clear, radius: isGlowEnabled ? glowBase * 4.0 * g : 0)
        .scaleEffect(x: isDragging ? 1.35 : 1.0, y: isDragging ? 0.78 : 1.0)
        .rotationEffect(isDragging ? Angle(radians: dragAngle) : .zero)
        .scaleEffect(clickScale)
        .scaleEffect(isDragging ? 1.0 : breathingScale)
        .rotation3DEffect(
            .degrees(totalTilt),
            axis: (x: 1, y: 0, z: 0),
            perspective: totalTilt > 0 ? 0.3 : 1.0
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isDragging)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: dragAngle)
        .animation(.easeInOut(duration: 0.7), value: glowMultiplier)
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: isPerspectiveWarping)
        .animation(.spring(response: 0.45, dampingFraction: 0.5), value: clickTilt)
        .animation(.easeInOut(duration: 0.3), value: hasInnerRing)
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
    let speed: Double
    // 시작: 커서 위 36pt baseline. onAppear에서 스크롤 방향으로 ±dist 추가 이동.
    @State private var opacity: Double = 0.9
    @State private var offset: CGSize = CGSize(width: 0, height: -36)

    private var arrow: String {
        if isVertical { return isPositive ? "↑" : "↓" }
        else          { return isPositive ? "→" : "←" }
    }

    var body: some View {
        Text(arrow)
            .font(.system(size: 20, weight: .bold))
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
