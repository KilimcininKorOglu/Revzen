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

    private let dock = Mutex<AXElement?>(nil)

    /// Binds to the running Dock process. Call again when the Dock relaunches.
    @MainActor
    func attach() {
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first?.processIdentifier
        let element = pid.map { AXElement.application($0) }
        dock.withLock { $0 = element }
        if element == nil {
            log.error("the Dock process is not running")
        }
    }

    /// The app icon under `point`, or nil for any other location.
    func appItem(at point: CGPoint) -> DockItem? {
        guard let dock = dock.withLock({ $0 }), let hit = dock.element(at: point) else { return nil }
        return Self.appItem(from: hit)
    }

    static func appItem(from element: AXElement) -> DockItem? {
        guard element.string(kAXSubroleAttribute) == appItemSubrole,
              let url = element.url(kAXURLAttribute),
              let frame = element.frame() else { return nil }
        return DockItem(element: element, appURL: url.standardizedFileURL, frame: frame)
    }
}
