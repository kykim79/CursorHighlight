import CoreGraphics
import Darwin    // dlopen / dlsym
import Foundation

// MARK: - MultitouchSupport private framework bridge
//
// macOS는 4손가락 핀치/스와이프, 3·4손가락 스와이프 같은 시스템 내비게이션 제스처를
// 컴포지터 레벨에서 직접 처리해 일반 앱에 NSEvent/CGEvent로 전달하지 않는다.
// 이 제스처를 잡으려면 비공식 `MultitouchSupport.framework`로 raw 터치 frame을
// 직접 읽는 수밖에 없다 — BetterTouchTool/MiddleClick 등 이 분야 표준 우회로.
//
// 위험 인지:
//   * 비공식 API라 macOS 업데이트마다 깨질 가능성 — symbol 누락 시 graceful no-op.
//   * App Store 제출 불가 (이 프로젝트는 Homebrew 배포라 무관).
//   * 손가락 frame은 시스템 스레드에서 콜백 — main으로 dispatch.

// MARK: - 외부 ABI 선언

/// 트랙패드 좌표 — 정규화 0..1. (0,0)=좌하단, (1,1)=우상단 (Apple 관례; 실측에서 다르면 invertY로 보정).
struct MTPoint {
    var x: Float
    var y: Float
}

struct MTReadout {
    var pos: MTPoint
    var vel: MTPoint
}

/// MTTouch struct layout — community reverse engineering 기반. 96 bytes 총합.
/// 우리는 identifier·state·normalized.pos만 사용 — 다른 필드 layout이 살짝 달라져도 위험 적음.
struct MTTouch {
    var frame: Int32                // 0
    var _pad0: Int32 = 0            // 4 (double 8byte 정렬용 padding)
    var timestamp: Double           // 8
    var identifier: Int32           // 16
    var state: Int32                // 20
    var fingerID: Int32             // 24
    var handID: Int32               // 28
    var normalized: MTReadout       // 32 (16 bytes)
    var zTotal: Float               // 48
    var _field9: Int32              // 52
    var angle: Float                // 56
    var majorAxis: Float            // 60
    var minorAxis: Float            // 64
    var absoluteVector: MTReadout   // 68
    var _field14: Int32             // 84
    var _field15: Int32             // 88
    var zDensity: Float             // 92
}

// @convention(c) 시그니처는 모든 인자가 ObjC-representable해야 함 — 제네릭 포인터
// (UnsafeMutablePointer<MTTouch>) 는 불가라 OpaquePointer로 받아서 콜백 안에서 cast.
private typealias MTContactCallbackFunction = @convention(c) (
    _ device: OpaquePointer?,
    _ data: OpaquePointer?,
    _ nFingers: Int32,
    _ timestamp: Double,
    _ frame: Int32
) -> Int32

private typealias MTDeviceCreateListFn = @convention(c) () -> Unmanaged<CFArray>?
private typealias MTRegisterContactFrameCallbackFn = @convention(c) (OpaquePointer, MTContactCallbackFunction) -> Void
private typealias MTUnregisterContactFrameCallbackFn = @convention(c) (OpaquePointer, MTContactCallbackFunction) -> Void
private typealias MTDeviceStartFn = @convention(c) (OpaquePointer, Int32) -> Void
private typealias MTDeviceStopFn = @convention(c) (OpaquePointer) -> Void

// MARK: - Service

/// 싱글톤 — C 콜백이 self를 capture할 수 없어 module-level reference 필요.
final class MultitouchService {
    static let shared = MultitouchService()

    private let lib: UnsafeMutableRawPointer?
    private let mtDeviceCreateList: MTDeviceCreateListFn?
    private let mtRegisterContactFrameCallback: MTRegisterContactFrameCallbackFn?
    private let mtUnregisterContactFrameCallback: MTUnregisterContactFrameCallbackFn?
    private let mtDeviceStart: MTDeviceStartFn?
    private let mtDeviceStop: MTDeviceStopFn?

    private var devices: [OpaquePointer] = []
    private var isRunning = false

    // 동시 콜백 보호 (여러 트랙패드가 동시 fire 가능).
    private let stateLock = NSLock()
    private var session: TouchSession?

    /// 외부에서 설정 — 제스처 인식되면 main에서 호출.
    /// AppDelegate에서 EffectsState로 연결.
    var onGesture: ((TrackpadGesture) -> Void)?

    /// 시스템 콜백 frequency 추정: ~100Hz. 콜백 마지막 발화 시각 trace해서 stuck 감지(optional).
    /// 일단은 단순 패턴으로 시작.

    private init() {
        // dlopen private framework. 실패하면 모든 fn이 nil → 모든 메서드 no-op.
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        let handle = dlopen(path, RTLD_NOW)

        // sym은 self.lib 대신 local handle을 capture — init 중 self 접근 회피.
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let handle else { return nil }
            guard let p = dlsym(handle, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }

        self.lib = handle
        self.mtDeviceCreateList = sym("MTDeviceCreateList", MTDeviceCreateListFn.self)
        self.mtRegisterContactFrameCallback = sym("MTRegisterContactFrameCallback", MTRegisterContactFrameCallbackFn.self)
        self.mtUnregisterContactFrameCallback = sym("MTUnregisterContactFrameCallback", MTUnregisterContactFrameCallbackFn.self)
        self.mtDeviceStart = sym("MTDeviceStart", MTDeviceStartFn.self)
        self.mtDeviceStop = sym("MTDeviceStop", MTDeviceStopFn.self)
    }

    /// 사용 가능 여부 — 모든 심볼 로드 성공.
    var isAvailable: Bool {
        return mtDeviceCreateList != nil && mtRegisterContactFrameCallback != nil
            && mtDeviceStart != nil && mtDeviceStop != nil
    }

    func start() {
        guard !isRunning, isAvailable,
              let create = mtDeviceCreateList,
              let register = mtRegisterContactFrameCallback,
              let startFn = mtDeviceStart else { return }

        guard let deviceList = create()?.takeRetainedValue() else { return }
        let count = CFArrayGetCount(deviceList)
        for i in 0..<count {
            guard let dev = CFArrayGetValueAtIndex(deviceList, i) else { continue }
            let devPtr = OpaquePointer(dev)
            register(devPtr, mtCallback)
            startFn(devPtr, 0)
            devices.append(devPtr)
        }
        isRunning = !devices.isEmpty
    }

    func stop() {
        guard isRunning,
              let stopFn = mtDeviceStop,
              let unregister = mtUnregisterContactFrameCallback else { return }
        for dev in devices {
            stopFn(dev)
            unregister(dev, mtCallback)
        }
        devices.removeAll()
        isRunning = false
    }

    // MARK: - Session tracking

    private struct TouchSession {
        var startTimestamp: Double
        var peakActiveCount: Int
        var fingers: [Int32: FingerTrace] = [:]   // by MTTouch.identifier
        var lastFireTimestamp: Double = 0          // 0 = 아직 미발사. 쿨다운 + 재앵커 기반 재발사용.
    }

    /// 미리 발사 후 다음 발사까지 최소 간격 (초). 한 swipe motion은 보통 0.15–0.3초 안에
    /// 끝나므로 0.18초 cooldown은 단일 swipe의 중복 발사를 막으면서 반복 swipe는 매번 잡음.
    private static let refireCooldown: Double = 0.18

    /// 콜백(시스템 스레드)에서 호출 — touch frame을 세션에 누적, 세션 종료 시 classify+emit.
    /// "active" 상태는 state == 3(Make) 또는 4(Touching) — 실제 접촉 중.
    fileprivate func processFrame(rawFingers: [(id: Int32, pos: CGPoint, state: Int32)], timestamp: Double) {
        stateLock.lock()
        defer { stateLock.unlock() }

        let active = rawFingers.filter { $0.state == 3 || $0.state == 4 }
        let activeCount = active.count

        if session == nil {
            // 새 세션 시작 조건: 갑자기 3+ 손가락 active.
            if activeCount >= 3 {
                var s = TouchSession(startTimestamp: timestamp, peakActiveCount: activeCount)
                for f in active {
                    s.fingers[f.id] = FingerTrace(startPos: f.pos, lastPos: f.pos)
                }
                session = s
            }
            return
        }

        // 세션 진행 중
        session!.peakActiveCount = max(session!.peakActiveCount, activeCount)
        for f in active {
            if var trace = session!.fingers[f.id] {
                trace.lastPos = f.pos
                session!.fingers[f.id] = trace
            } else {
                // 세션 도중 새 손가락 등장 (예: 3→4로 추가) — start = 현재 위치.
                session!.fingers[f.id] = FingerTrace(startPos: f.pos, lastPos: f.pos)
            }
        }

        // 미리 발사 + 재발사 — motion이 분류 임계 넘으면 즉시 emit.
        // 한 세션 안에서도 cooldown(0.18s) 지나면 다시 발사 가능 — 손가락 안 떼고
        // 반복 swipe 하는 경우(좌·좌·좌 또는 좌·우·좌)에도 매번 잡힘.
        // 재발사 시 활성 손가락의 startPos를 현재 위치로 리셋해 다음 motion을 fresh anchor에서 측정.
        // 분류는 peakActiveCount 대신 현재 activeCount로 — 한 손가락 떨어진 뒤 3·4 finger
        // gesture가 섞이는 경우에도 정확히 식별.
        let timeSinceFire = timestamp - session!.lastFireTimestamp
        let canFire = session!.lastFireTimestamp == 0 || timeSinceFire > Self.refireCooldown
        if canFire && activeCount >= 3 {
            let activeIDs = Set(active.map { $0.id })
            let activeTraces = session!.fingers.compactMap { activeIDs.contains($0.key) ? $0.value : nil }
            if let gesture = TrackpadGestureClassifier.classify(peakFingers: activeCount, traces: activeTraces) {
                session!.lastFireTimestamp = timestamp
                for f in active {
                    session!.fingers[f.id]?.startPos = f.pos
                }
                let cb = onGesture
                DispatchQueue.main.async { cb?(gesture) }
            }
        }

        // 모든 손가락 lift → 세션 종료. 한 번이라도 발사됐으면 skip, 아니면 마지막 시도.
        if activeCount == 0 {
            let peak = session!.peakActiveCount
            let traces = Array(session!.fingers.values)
            let everFired = session!.lastFireTimestamp != 0
            session = nil

            if !everFired, let gesture = TrackpadGestureClassifier.classify(peakFingers: peak, traces: traces) {
                let cb = onGesture
                DispatchQueue.main.async { cb?(gesture) }
            }
        }
    }
}

// MARK: - C 콜백 (top-level, @convention(c))

private let mtCallback: MTContactCallbackFunction = { _, dataOpaque, nFingers, timestamp, _ in
    guard let dataOpaque else { return 0 }
    let dataPtr = UnsafeMutablePointer<MTTouch>(dataOpaque)
    var fingers: [(Int32, CGPoint, Int32)] = []
    fingers.reserveCapacity(Int(nFingers))
    for i in 0..<Int(nFingers) {
        let t = dataPtr[i]
        let pos = CGPoint(x: CGFloat(t.normalized.pos.x), y: CGFloat(t.normalized.pos.y))
        fingers.append((t.identifier, pos, t.state))
    }
    MultitouchService.shared.processFrame(rawFingers: fingers, timestamp: timestamp)
    return 0
}
