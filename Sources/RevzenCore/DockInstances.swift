/// Matches Dock icons to running copies of one app. The Dock shows one icon
/// per running copy of an app that is launched more than once, all with the
/// same bundle URL and no process ID. It lists them in launch order, the
/// order `NSWorkspace.runningApplications` reports, so the n-th icon of an
/// app belongs to its n-th running copy.
public enum DockInstances {
    /// The position of the icon at `position` among the icons with the same
    /// key, or nil when `position` is outside `keys` or has no key.
    public static func index<Key: Equatable>(of position: Int, in keys: [Key?]) -> Int? {
        guard keys.indices.contains(position), let key = keys[position] else { return nil }
        return keys[..<position].count { $0 == key }
    }

    /// The running copy for an icon. A single copy needs no index. With
    /// several copies, the icon's index picks one; nil when the index is
    /// unknown or the Dock shows more icons than there are copies.
    public static func copy<App>(_ copies: [App], index: Int?) -> App? {
        if copies.count == 1 { return copies[0] }
        guard let index, copies.indices.contains(index) else { return nil }
        return copies[index]
    }
}
