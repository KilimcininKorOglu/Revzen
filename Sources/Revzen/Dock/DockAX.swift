import AppKit
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

    /// Binds to the running Dock process. Call again when the Dock relaunches.
    @MainActor
    func attach() {
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first?.processIdentifier
        let bound = pid.map { Process(pid: $0, element: AXElement.application($0)) }
        process.withLock { $0 = bound }
        if let pid {
            DebugLog.event(.app, "attached to the Dock, pid \(pid)")
        } else {
            DebugLog.error(.app, "the Dock process is not running")
        }
    }

    var pid: pid_t? {
        process.withLock { $0?.pid }
    }

    /// The app icon under `point`, or nil for any other location.
    func appItem(at point: CGPoint) -> DockItem? {
        guard let dock = process.withLock({ $0?.element }), let hit = dock.element(at: point) else { return nil }
        return Self.appItem(from: hit)
    }

    /// The Dock's list of icons. Its selected child is the hovered icon.
    func iconList() -> AXElement? {
        process.withLock { $0?.element }?
            .elements(kAXChildrenAttribute)
            .first { $0.string(kAXRoleAttribute) == kAXListRole }
    }

    static func appItem(from element: AXElement) -> DockItem? {
        guard element.string(kAXSubroleAttribute) == appItemSubrole,
            let url = element.url(kAXURLAttribute),
            let frame = element.frame()
        else { return nil }
        return DockItem(element: element, appURL: url.standardizedFileURL, frame: frame)
    }
}
