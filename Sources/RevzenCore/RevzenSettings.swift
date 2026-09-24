import Foundation

/// User preferences. Launch at login is not stored here, because
/// `SMAppService` owns that state.
public struct RevzenSettings: Codable, Sendable, Equatable {
    public static let hoverDelayRange: ClosedRange<Int> = 0...2000
    public static let defaultHoverDelayMs = 300

    /// Delay between hovering a Dock icon and showing the preview.
    public var hoverDelayMs: Int {
        didSet { hoverDelayMs = Self.clampedDelay(hoverDelayMs) }
    }
    /// Apps that Revzen leaves alone: no click handling, preview or scroll.
    public var excludedBundleIDs: Set<String>
    /// Show windows that are on another Space in the preview.
    public var showOtherSpaces: Bool

    public init(
        hoverDelayMs: Int = RevzenSettings.defaultHoverDelayMs,
        excludedBundleIDs: Set<String> = [],
        showOtherSpaces: Bool = false
    ) {
        self.hoverDelayMs = Self.clampedDelay(hoverDelayMs)
        self.excludedBundleIDs = excludedBundleIDs
        self.showOtherSpaces = showOtherSpaces
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            hoverDelayMs: try container.decode(Int.self, forKey: .hoverDelayMs),
            excludedBundleIDs: try container.decode(Set<String>.self, forKey: .excludedBundleIDs),
            showOtherSpaces: try container.decode(Bool.self, forKey: .showOtherSpaces)
        )
    }

    public func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.contains(bundleID)
    }

    private static func clampedDelay(_ value: Int) -> Int {
        min(max(value, hoverDelayRange.lowerBound), hoverDelayRange.upperBound)
    }
}

/// Persists `RevzenSettings` as one JSON value in `UserDefaults`.
public struct SettingsStore {
    public static let key = "settings.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns the stored settings, or the defaults when nothing is stored yet.
    /// Throws when a stored value exists but does not decode.
    public func load() throws -> RevzenSettings {
        guard let data = defaults.data(forKey: Self.key) else {
            return RevzenSettings()
        }
        return try JSONDecoder().decode(RevzenSettings.self, from: data)
    }

    public func save(_ settings: RevzenSettings) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
    }
}
