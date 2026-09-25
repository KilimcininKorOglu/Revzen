import AppKit
import RevzenCore
import Synchronization

/// An app icon in the Dock.
struct DockItem: Sendable, Equatable {
    let element: AXElement
    let appURL: URL
    /// Top-left origin, global display coordinates (same space as `CGEvent.location`).
    let frame: CGRect
}

/// Reads the Dock through the Accessibility API. Safe to call from any thread.
final class DockAX: Sendable {
    static let bundleID = "com.apple.dock"
    static let appItemSubrole = "AXApplicationDockItem"

    private struct Process {
        let pid: pid_t
        let element: AXElement
    }

    private let process = Mutex<Process?>(nil)
    /// The screen strip that can hold a Dock icon. Clicks and scrolls
    /// outside it skip the AX hit test, which blocks the event tap while the
    /// Dock is slow. Nil until the first refresh: then every point is tested.
    private let band = Mutex<CGRect?>(nil)

    /// Binds to the running Dock process. Call again when the Dock relaunches.
    @MainActor
    func attach() {
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first?.processIdentifier
        let bound = pid.map { Process(pid: $0, element: AXElement.application($0)) }
        process.withLock { $0 = bound }
        refreshBand()
        if let pid {
            DebugLog.event(.app, "attached to the Dock, pid \(pid)")
        } else {
            DebugLog.error(.app, "the Dock process is not running")
        }
    }

    var pid: pid_t? {
        process.withLock { $0?.pid }
    }

    /// Reads the icon list frame again. Called on attach and on every Dock
    /// hover notification, which the Dock posts before any click or scroll
    /// can reach an icon, so the band follows a moved or resized Dock.
    @MainActor
    func refreshBand() {
        let frame = iconList()?.frame()
        let center = frame.map { CGPoint(x: $0.midX, y: $0.midY) }
        let screen = center.flatMap { center in NSScreen.screens.map(\.cgFrame).first { $0.contains(center) } }
        let updated = frame.flatMap { frame in screen.map { DockEdge.band(listFrame: frame, screen: $0) } }
        let previous = band.withLock { band in
            defer { band = updated }
            return band
        }
        if previous != updated {
            DebugLog.event(.app, "Dock band \(updated.map { "\($0)" } ?? "unknown, every point is tested")")
        }
    }

    /// The app icon under `point`, or nil for any other location.
    func appItem(at point: CGPoint) -> DockItem? {
        if let band = band.withLock({ $0 }), !band.contains(point) { return nil }
        guard let dock = process.withLock({ $0?.element }), let hit = dock.element(at: point) else { return nil }
        return Self.appItem(from: hit)
    }

    /// The Dock's list of icons. Its selected child is the hovered icon.
    func iconList() -> AXElement? {
        process.withLock { $0?.element }?
            .elements(kAXChildrenAttribute)
            .first { $0.string(kAXRoleAttribute) == kAXListRole }
    }

    /// The running copy that an icon belongs to. An app launched more than
    /// once has one icon per copy with the same URL, so the icon's position
    /// among those icons picks the copy. The Dock list is read only then.
    func runningApp(for item: DockItem, in directory: AppDirectory) -> RunningApp? {
        let copies = directory.apps(forBundleURL: item.appURL)
        guard copies.count > 1 else { return copies.first }
        let icons = iconList()?.elements(kAXChildrenAttribute) ?? []
        let urls = icons.map { $0.url(kAXURLAttribute)?.standardizedFileURL }
        let index = icons.firstIndex(of: item.element).flatMap { DockInstances.index(of: $0, in: urls) }
        guard let copy = DockInstances.copy(copies, index: index) else {
            DebugLog.error(
                .app, "no running copy for icon \(index.map(String.init) ?? "unknown") of \(item.logName), \(copies.count) copies")
            return nil
        }
        return copy
    }

    static func appItem(from element: AXElement) -> DockItem? {
        guard element.string(kAXSubroleAttribute) == appItemSubrole,
            let url = element.url(kAXURLAttribute),
            let frame = element.frame()
        else { return nil }
        return DockItem(element: element, appURL: url.standardizedFileURL, frame: frame)
    }
}
