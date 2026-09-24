/// A fixed-capacity cache that drops the least recently used entry first.
///
/// Revzen keeps the last image of each window here, because ScreenCaptureKit
/// cannot capture a window after it is minimized.
public struct LRUCache<Key: Hashable, Value> {
    public let capacity: Int
    private var values: [Key: Value] = [:]
    /// Keys from least to most recently used. The capacity is small, so a
    /// linear search stays cheap.
    private var order: [Key] = []

    public init(capacity: Int) {
        precondition(capacity > 0, "an LRU cache needs room for one entry")
        self.capacity = capacity
    }

    public var count: Int { values.count }

    public mutating func insert(_ value: Value, for key: Key) {
        values[key] = value
        touch(key)
        if order.count > capacity {
            values.removeValue(forKey: order.removeFirst())
        }
    }

    /// Returns the value and marks it as the most recently used.
    public mutating func value(for key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    public mutating func removeValue(for key: Key) {
        values.removeValue(forKey: key)
        order.removeAll { $0 == key }
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
