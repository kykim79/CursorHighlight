import CoreGraphics
import Foundation
import AppKit

class MouseEventMonitor {
    var onMouseMove: ((CGPoint) -> Void)?
    var onLeftClick: ((CGPoint, Bool) -> Void)?   // (position, isDouble)
    /// Background thread에서 호출 — radial menu 활성 중에만 true 리턴해 좌클릭을 소비.
    /// main에서 갱신 (한 워드 Bool read), 단일 Bool라 race tolerated.
    nonisolated(unsafe) var shouldConsumeLeftClick: Bool = false
    /// ⌃⌥D 그리기 모드 — leftMouseDown/Dragged/Up 전부 소비 + 그리기 콜백으로 라우팅.
    nonisolated(unsafe) var isDrawingModeActive: Bool = false
    var onDrawingDrag: ((CGPoint) -> Void)?      // leftMouseDragged in drawing mode (Quartz 좌표)
    var onDrawingRelease: ((CGPoint) -> Void)?   // leftMouseUp in drawing mode
    var onRightClick: ((CGPoint) -> Void)?
    var onMiddleClick: ((CGPoint) -> Void)?       // 휠 클릭 (button 2)
    var onShake: ((CGPoint) -> Void)?
    var onScroll: ((CGPoint, Bool, Bool, CGFloat) -> Void)? // (position, isPositive, isVertical, magnitude)
    var onDragStart: ((CGPoint) -> Void)?  // 시작 위치 (Quartz 좌표, AppDelegate가 Cocoa로 변환)
    var onDragAngle: ((Double, CGFloat) -> Void)?  // (angle in radians, velocity in pt/s)
    var onDragEnd: (() -> Void)?

    /// 좌클릭 hold (Tokens.Radial.longPressDuration) 시 fire — 라디얼 메뉴 트리거.
    /// 마우스 hold / 트랙패드 long touch 모두 같은 left mouse 이벤트라 단일 메커니즘으로 처리.
    var onLongPress: ((CGPoint) -> Void)?

    // long press 추적 — mouseDown 시 timer 시작, deadband 초과 이동 또는 mouseUp 시 cancel.
    private var longPressWorkItem: DispatchWorkItem?
    private var longPressStartPos: CGPoint = .zero
    /// 상위 코드에서 라디얼 메뉴 / 그리기 모드 활성 여부 (background에서 읽음, main에서 갱신).
    /// 활성 시 long press timer 시작 안 함 (중복 트리거/모드 충돌 방지).
    private var canStartLongPress: Bool { !shouldConsumeLeftClick && !isDrawingModeActive }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var selfPtr: UnsafeMutableRawPointer?
    private var tapThread: Thread?

    // 흔들기 감지 — 알고리즘은 ShakeState.swift에 추출(테스트 가능).
    private var shakeState = ShakeState()

    // 스크롤 디바운스
    private var lastScrollTime: TimeInterval = 0
    private var lastScrollKey: String = ""

    // 드래그 상태
    private var inDrag: Bool = false
    private var lastDragPos: CGPoint = .zero
    private var lastDragTime: TimeInterval = 0


    func start() {
        guard AXIsProcessTrusted() else { return }
        guard eventTap == nil else { return }

        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |  // 휠 클릭(button 2) 및 나머지
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        let retained = Unmanaged.passRetained(self)
        selfPtr = retained.toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,  // 평소 consume 안 함. radial menu 활성 중 leftMouseDown만 소비.
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let m = Unmanaged<MouseEventMonitor>.fromOpaque(refcon).takeUnretainedValue()

                let loc = event.location
                switch type {
                case .tapDisabledByTimeout, .tapDisabledByUserInput:
                    // 시스템이 메인 스레드 과부하로 tap을 비활성화하면 즉시 재활성화
                    if let tap = m.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passRetained(event)

                case .mouseMoved:
                    m.processMove(loc)
                    DispatchQueue.main.async { m.onMouseMove?(loc) }

                case .leftMouseDragged:
                    m.processMove(loc)
                    DispatchQueue.main.async { m.onMouseMove?(loc) }
                    // Long-press deadband 초과 이동 → 드래그로 간주, timer cancel (라디얼 트리거 안 함)
                    if let work = m.longPressWorkItem {
                        let dx = loc.x - m.longPressStartPos.x
                        let dy = loc.y - m.longPressStartPos.y
                        if (dx * dx + dy * dy) > (Tokens.Radial.longPressDeadband * Tokens.Radial.longPressDeadband) {
                            work.cancel()
                            m.longPressWorkItem = nil
                        }
                    }
                    // 그리기 모드 — 드래그 위치를 그리기 콜백으로 라우팅 + underlying 차단
                    if m.isDrawingModeActive {
                        DispatchQueue.main.async { m.onDrawingDrag?(loc) }
                        return nil
                    }
                    let now = Date().timeIntervalSinceReferenceDate
                    if !m.inDrag {
                        m.inDrag = true
                        m.lastDragPos = loc
                        m.lastDragTime = now
                        DispatchQueue.main.async { m.onDragStart?(loc) }
                    } else {
                        let dx = loc.x - m.lastDragPos.x
                        let dy = loc.y - m.lastDragPos.y
                        if abs(dx) > 2 || abs(dy) > 2 {
                            let dt = now - m.lastDragTime
                            let dist = sqrt(dx * dx + dy * dy)
                            let velocity: CGFloat = dt > 0.001 ? dist / CGFloat(dt) : 0
                            let angle = atan2(dy, dx)
                            m.lastDragPos = loc
                            m.lastDragTime = now
                            DispatchQueue.main.async { m.onDragAngle?(angle, velocity) }
                        }
                    }

                case .leftMouseDown:
                    m.inDrag = false
                    let clickState = event.getIntegerValueField(.mouseEventClickState)
                    let isDouble = clickState >= 2
                    DispatchQueue.main.async { m.onLeftClick?(loc, isDouble) }
                    // Long-press 트리거 — 라디얼 메뉴 미활성 + 그리기 미활성일 때만 timer 시작
                    if m.canStartLongPress {
                        m.longPressStartPos = loc
                        let work = DispatchWorkItem { [weak m] in
                            guard let m else { return }
                            m.longPressWorkItem = nil
                            // canStartLongPress는 main에서 갱신되므로 fire 시점에 다시 확인 (race 안전망)
                            if m.canStartLongPress {
                                m.onLongPress?(m.longPressStartPos)
                            }
                        }
                        m.longPressWorkItem = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + Tokens.Radial.longPressDuration, execute: work)
                    }
                    // Radial menu 또는 그리기 모드 활성 중에는 underlying app으로 click 전달 안 함
                    if m.shouldConsumeLeftClick || m.isDrawingModeActive {
                        return nil
                    }

                case .leftMouseUp:
                    // Long-press timer 살아있으면 cancel — 사용자가 threshold 전에 손 뗌 = 짧은 클릭
                    if let work = m.longPressWorkItem {
                        work.cancel()
                        m.longPressWorkItem = nil
                    }
                    if m.isDrawingModeActive {
                        DispatchQueue.main.async { m.onDrawingRelease?(loc) }
                        m.inDrag = false
                        return nil
                    }
                    if m.inDrag {
                        m.inDrag = false
                        DispatchQueue.main.async { m.onDragEnd?() }
                    }

                case .rightMouseDown:
                    DispatchQueue.main.async { m.onRightClick?(loc) }

                case .otherMouseDown:
                    // mouseEventButtonNumber: 0=left, 1=right, 2=middle, 3+=extra
                    let button = event.getIntegerValueField(.mouseEventButtonNumber)
                    if button == 2 {
                        DispatchQueue.main.async { m.onMiddleClick?(loc) }
                    }

                case .scrollWheel:
                    let deltaV = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                    let deltaH = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
                    let now = Date().timeIntervalSinceReferenceDate
                    let isVertical = abs(deltaV) >= abs(deltaH)
                    let delta = isVertical ? deltaV : deltaH
                    guard delta != 0 else { break }
                    // vertical: negative=up / horizontal: positive=right
                    let isPositive = isVertical ? (delta < 0) : (delta > 0)
                    // magnitude (absolute pt delta) — 트랙패드 1지손 ~5, 휠 한 칸 ~10, 강한 swipe ~50+
                    let magnitude = CGFloat(abs(delta))
                    let key = isVertical ? (isPositive ? "up" : "down") : (isPositive ? "right" : "left")
                    if key != m.lastScrollKey || now - m.lastScrollTime > 0.25 {
                        m.lastScrollTime = now
                        m.lastScrollKey = key
                        DispatchQueue.main.async { m.onScroll?(loc, isPositive, isVertical, magnitude) }
                    }

                default:
                    break
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr
        )

        guard let tap else {
            retained.release()
            selfPtr = nil
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source

        // 메인 스레드 RunLoop과 완전히 격리된 전용 스레드에서 실행
        // NSMenu 트래킹, NSApp.activate 등 메인 스레드 상태 변화의 영향을 받지 않음
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "CursorHighlight.EventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // 포트 무효화 → 백그라운드 스레드의 CFRunLoopRun()이 자동 종료됨
            CFMachPortInvalidate(tap)
        }
        if let ptr = selfPtr {
            Unmanaged<MouseEventMonitor>.fromOpaque(ptr).release()
            selfPtr = nil
        }
        eventTap = nil
        runLoopSource = nil
        tapThread = nil
        inDrag = false
    }

    private func processMove(_ point: CGPoint) {
        let now = Date().timeIntervalSinceReferenceDate
        if shakeState.record(x: point.x, y: point.y, at: now) {
            let capturedPoint = point
            DispatchQueue.main.async { [weak self] in self?.onShake?(capturedPoint) }
        }
    }

    deinit { stop() }
}
