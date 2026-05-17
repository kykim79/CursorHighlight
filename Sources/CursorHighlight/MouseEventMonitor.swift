import CoreGraphics
import Foundation
import AppKit

class MouseEventMonitor {
    var onMouseMove: ((CGPoint) -> Void)?
    var onLeftClick: ((CGPoint, Bool) -> Void)?   // (position, isDouble)
    var onRightClick: ((CGPoint) -> Void)?
    var onShake: ((CGPoint) -> Void)?
    var onScroll: ((CGPoint, Bool, Bool) -> Void)? // (position, isPositive, isVertical)
    var onDragStart: ((CGPoint) -> Void)?  // 시작 위치 (Quartz 좌표, AppDelegate가 Cocoa로 변환)
    var onDragAngle: ((Double, CGFloat) -> Void)?  // (angle in radians, velocity in pt/s)
    var onDragEnd: (() -> Void)?

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
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        let retained = Unmanaged.passRetained(self)
        selfPtr = retained.toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
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

                case .leftMouseUp:
                    if m.inDrag {
                        m.inDrag = false
                        DispatchQueue.main.async { m.onDragEnd?() }
                    }

                case .rightMouseDown:
                    DispatchQueue.main.async { m.onRightClick?(loc) }

                case .scrollWheel:
                    let deltaV = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                    let deltaH = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
                    let now = Date().timeIntervalSinceReferenceDate
                    let isVertical = abs(deltaV) >= abs(deltaH)
                    let delta = isVertical ? deltaV : deltaH
                    guard delta != 0 else { break }
                    // vertical: negative=up / horizontal: positive=right
                    let isPositive = isVertical ? (delta < 0) : (delta > 0)
                    let key = isVertical ? (isPositive ? "up" : "down") : (isPositive ? "right" : "left")
                    if key != m.lastScrollKey || now - m.lastScrollTime > 0.25 {
                        m.lastScrollTime = now
                        m.lastScrollKey = key
                        DispatchQueue.main.async { m.onScroll?(loc, isPositive, isVertical) }
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
