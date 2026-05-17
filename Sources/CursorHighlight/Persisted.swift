import Foundation
import Combine

// MARK: - @Persisted PropertyWrapper
//
// ObservableObject 안에서 UserDefaults에 자동 저장되는 프로퍼티.
// Swift의 _enclosingInstance subscript를 활용해 SwiftUI의 @Published와 같은
// 방식으로 enclosing instance의 objectWillChange를 호출한다.
//
// 사용:
//   @Persisted("ringOpacity", default: 1.0, debounce: 0.3)
//   var ringOpacity: Double
//
//   @Persisted("ringColor", default: RingColor.yellow)   // RawRepresentable enum
//   var ringColor: RingColor
//
// 미지원 타입(Color/NSColor 등 비-native)은 기존 @Published+didSet 패턴 유지.
@propertyWrapper
final class Persisted<Value> {
    private let debounceInterval: TimeInterval
    private let save: (Value) -> Void
    private var value: Value
    private var saveTask: DispatchWorkItem?

    /// Native UserDefaults 타입 (Bool, Int, Double, String, CGFloat, UInt16 등)
    init(_ key: String, default defaultValue: Value, debounce: TimeInterval = 0)
        where Value: PersistedValue
    {
        self.debounceInterval = debounce
        self.save = { Value.write($0, to: .standard, key: key) }
        self.value = Value.read(from: .standard, key: key) ?? defaultValue
    }

    /// RawRepresentable (enum) — rawValue로 직렬화
    init(_ key: String, default defaultValue: Value, debounce: TimeInterval = 0)
        where Value: RawRepresentable, Value.RawValue: PersistedValue
    {
        self.debounceInterval = debounce
        self.save = { Value.RawValue.write($0.rawValue, to: .standard, key: key) }
        let raw = Value.RawValue.read(from: .standard, key: key)
        self.value = raw.flatMap { Value(rawValue: $0) } ?? defaultValue
    }

    static subscript<Enclosing: ObservableObject>(
        _enclosingInstance instance: Enclosing,
        wrapped _: ReferenceWritableKeyPath<Enclosing, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Enclosing, Persisted>
    ) -> Value where Enclosing.ObjectWillChangePublisher == ObservableObjectPublisher {
        get { instance[keyPath: storageKeyPath].value }
        set {
            instance.objectWillChange.send()
            let wrapper = instance[keyPath: storageKeyPath]
            wrapper.value = newValue
            wrapper.persist(newValue)
        }
    }

    @available(*, unavailable, message: "@Persisted only works inside ObservableObject")
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    private func persist(_ newValue: Value) {
        guard debounceInterval > 0 else {
            save(newValue)
            return
        }
        saveTask?.cancel()
        let task = DispatchWorkItem { [save] in save(newValue) }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: task)
    }
}

// MARK: - PersistedValue (UserDefaults 직접 저장 가능 타입)

protocol PersistedValue {
    static func read(from defaults: UserDefaults, key: String) -> Self?
    static func write(_ value: Self, to defaults: UserDefaults, key: String)
}

extension Bool: PersistedValue {
    // bool(forKey:)는 기본 false 반환 → "저장된 값 없음"과 구분 위해 object(forKey:) 사용
    static func read(from defaults: UserDefaults, key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }
    static func write(_ value: Bool, to defaults: UserDefaults, key: String) {
        defaults.set(value, forKey: key)
    }
}

extension Int: PersistedValue {
    static func read(from defaults: UserDefaults, key: String) -> Int? {
        defaults.object(forKey: key) as? Int
    }
    static func write(_ value: Int, to defaults: UserDefaults, key: String) {
        defaults.set(value, forKey: key)
    }
}

extension Double: PersistedValue {
    static func read(from defaults: UserDefaults, key: String) -> Double? {
        defaults.object(forKey: key) as? Double
    }
    static func write(_ value: Double, to defaults: UserDefaults, key: String) {
        defaults.set(value, forKey: key)
    }
}

extension String: PersistedValue {
    static func read(from defaults: UserDefaults, key: String) -> String? {
        defaults.object(forKey: key) as? String
    }
    static func write(_ value: String, to defaults: UserDefaults, key: String) {
        defaults.set(value, forKey: key)
    }
}

extension CGFloat: PersistedValue {
    // CGFloat은 UserDefaults가 직접 지원하지 않아 Double로 brideging
    static func read(from defaults: UserDefaults, key: String) -> CGFloat? {
        (defaults.object(forKey: key) as? Double).map { CGFloat($0) }
    }
    static func write(_ value: CGFloat, to defaults: UserDefaults, key: String) {
        defaults.set(Double(value), forKey: key)
    }
}

extension UInt16: PersistedValue {
    // UInt16은 UserDefaults가 직접 지원하지 않아 Int로 bridging (단축키 keyCode용)
    static func read(from defaults: UserDefaults, key: String) -> UInt16? {
        (defaults.object(forKey: key) as? Int).map { UInt16($0) }
    }
    static func write(_ value: UInt16, to defaults: UserDefaults, key: String) {
        defaults.set(Int(value), forKey: key)
    }
}
