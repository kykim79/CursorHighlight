import AppKit
import CoreGraphics

// MARK: - 모니터 식별
//
// 외장 모니터를 재연결해도 안정적으로 식별하기 위한 NSScreen 확장.
// CGDisplayCreateUUIDFromDisplayID — EDID 있는 모니터는 같은 물리 디스플레이에 항상 같은 UUID.
// (EDID 없는 저가 HDMI 어댑터는 generated UUID라 재연결 시 변할 수 있음 — 그 경우 "낯선 모니터"로
//  취급돼 키스트로크가 켜지는 쪽이라 발표 안전 측면에선 무해.)
extension NSScreen {
    /// CGDirectDisplayID — deviceDescription의 NSScreenNumber.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// 물리 디스플레이의 안정적 UUID 문자열. 식별 불가 시 nil.
    var stableUUID: String? {
        guard let id = displayID,
              let cfUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, cfUUID) as String
    }

    /// 노트북 내장 디스플레이 여부. 내장은 자동 활성화 대상에서 제외.
    var isBuiltin: Bool {
        guard let id = displayID else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }

    /// 사용자에게 보여줄 모니터 이름 (예: "DELL U2720Q"). macOS 14+는 localizedName.
    var friendlyName: String {
        if #available(macOS 14.0, *) { return localizedName }
        return "디스플레이 \(displayID.map(String.init) ?? "?")"
    }
}

// MARK: - 외장 모니터 스냅샷
//
// 현재 연결된 외장(non-builtin) 모니터 목록 — UUID + 이름.
struct ExternalMonitor: Identifiable, Hashable {
    let uuid: String
    let name: String
    var id: String { uuid }

    /// 현재 연결된 외장 모니터 — UUID 식별 가능한 것만.
    static func current() -> [ExternalMonitor] {
        NSScreen.screens.compactMap { screen in
            guard !screen.isBuiltin, let uuid = screen.stableUUID else { return nil }
            return ExternalMonitor(uuid: uuid, name: screen.friendlyName)
        }
    }
}
