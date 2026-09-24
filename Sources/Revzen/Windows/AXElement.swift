import ApplicationServices

/// A Sendable wrapper for `AXUIElement`. The AX client API is safe to call
/// from any thread, and the event tap thread needs these elements.
///
/// The messaging timeout is state of the shared `AXUIElement` object, and
/// wrappers on two threads can hold the same object with different timeouts.
/// So every AX call sets this wrapper's timeout right before it runs, and
/// every element read from this one gets the same timeout.
struct AXElement: @unchecked Sendable, Hashable {
    /// Timeout for reads on the event tap thread. A hung app must not stall
    /// the tap, which macOS disables after about one second.
    static let readTimeout: Float = 0.25
    /// Timeout for window actions off the tap thread. An app that animates a
    /// restore can take longer than `readTimeout` to answer.
    static let actionTimeout: Float = 1.5

    let raw: AXUIElement
    let timeout: Float

    init(_ raw: AXUIElement, timeout: Float = readTimeout) {
        self.raw = raw
        self.timeout = timeout
    }

    static func application(_ pid: pid_t, timeout: Float = readTimeout) -> AXElement {
        AXElement(AXUIElementCreateApplication(pid), timeout: timeout)
    }

    static func == (lhs: AXElement, rhs: AXElement) -> Bool {
        lhs.raw == rhs.raw
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(raw)
    }

    /// The same element with another messaging timeout for its own calls.
    func withTimeout(_ timeout: Float) -> AXElement {
        AXElement(raw, timeout: timeout)
    }

    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        applyTimeout()
        let result = AXUIElementCopyAttributeValue(raw, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    /// Sets this wrapper's timeout on the shared object. Call it before
    /// every AX call on `raw`.
    func applyTimeout() {
        AXUIElementSetMessagingTimeout(raw, timeout)
    }
}

// MARK: - Typed reads and actions

extension AXElement {
    func string(_ attribute: String) -> String? {
        value(attribute) as? String
    }

    func bool(_ attribute: String) -> Bool? {
        (value(attribute) as? NSNumber)?.boolValue
    }

    func url(_ attribute: String) -> URL? {
        value(attribute, typeID: CFURLGetTypeID(), as: CFURL.self).map { $0 as URL }
    }

    func element(_ attribute: String) -> AXElement? {
        value(attribute, typeID: AXUIElementGetTypeID(), as: AXUIElement.self).map { AXElement($0, timeout: timeout) }
    }

    func elements(_ attribute: String) -> [AXElement] {
        guard let array = value(attribute) as? [AXUIElement] else { return [] }
        return array.map { AXElement($0, timeout: timeout) }
    }

    func frame() -> CGRect? {
        guard let value = value("AXFrame", typeID: AXValueGetTypeID(), as: AXValue.self) else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value, .cgRect, &rect) ? rect : nil
    }

    /// The attribute value when its CoreFoundation type ID is `typeID`.
    /// CoreFoundation types do not support `as?`, and the type ID check makes
    /// the bit cast safe.
    private func value<T>(_ attribute: String, typeID: CFTypeID, as type: T.Type) -> T? {
        guard let value = value(attribute), CFGetTypeID(value) == typeID else { return nil }
        return unsafeBitCast(value, to: type)
    }

    @discardableResult
    func set(_ attribute: String, _ value: Bool) -> AXError {
        applyTimeout()
        return AXUIElementSetAttributeValue(raw, attribute as CFString, value as CFBoolean)
    }

    @discardableResult
    func perform(_ action: String) -> AXError {
        applyTimeout()
        return AXUIElementPerformAction(raw, action as CFString)
    }

    func element(at point: CGPoint) -> AXElement? {
        var hit: AXUIElement?
        applyTimeout()
        guard AXUIElementCopyElementAtPosition(raw, Float(point.x), Float(point.y), &hit) == .success,
            let hit
        else { return nil }
        return AXElement(hit, timeout: timeout)
    }
}
