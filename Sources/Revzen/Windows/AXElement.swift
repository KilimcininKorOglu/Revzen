import ApplicationServices

/// A Sendable wrapper for `AXUIElement`. The AX client API is safe to call
/// from any thread, and the event tap thread needs these elements.
///
/// A messaging timeout applies to one element only, so every element read
/// from this one gets the same timeout.
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
        AXUIElementSetMessagingTimeout(raw, timeout)
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

    /// The same element with another messaging timeout.
    func withTimeout(_ timeout: Float) -> AXElement {
        AXElement(raw, timeout: timeout)
    }

    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(raw, attribute as CFString, &value)
        return result == .success ? value : nil
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
        guard let value = value(attribute), CFGetTypeID(value) == CFURLGetTypeID() else { return nil }
        // The type ID check above makes this cast safe.
        return (value as! CFURL) as URL // swiftlint:disable:this force_cast
    }

    func elements(_ attribute: String) -> [AXElement] {
        guard let array = value(attribute) as? [AXUIElement] else { return [] }
        return array.map { AXElement($0, timeout: timeout) }
    }

    func frame() -> CGRect? {
        guard let value = value("AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        // The type ID check above makes this cast safe.
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil } // swiftlint:disable:this force_cast
        return rect
    }

    @discardableResult
    func set(_ attribute: String, _ value: Bool) -> AXError {
        AXUIElementSetAttributeValue(raw, attribute as CFString, value as CFBoolean)
    }

    @discardableResult
    func perform(_ action: String) -> AXError {
        AXUIElementPerformAction(raw, action as CFString)
    }

    func element(at point: CGPoint) -> AXElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(raw, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        return AXElement(hit, timeout: timeout)
    }
}
