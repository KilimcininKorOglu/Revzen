import AppKit

/// The services that act on the Dock: running app tracking, the event tap
/// and the preview. They need the Accessibility permission to start.
@MainActor
final class DockServices {
    private let directory = AppDirectory()
    private let dock = DockAX()
    private let preview: PreviewController
    private var workspaceObserver: WorkspaceObserver?
    private var eventTap: EventTap?

    init(excludedBundleIDs: Set<String>, hoverDelay: @escaping @MainActor () -> Duration) {
        directory.setExcluded(excludedBundleIDs)
        preview = PreviewController(dock: dock, directory: directory, hoverDelay: hoverDelay)
    }

    func setExcluded(_ bundleIDs: Set<String>) {
        directory.setExcluded(bundleIDs)
    }

    func start() throws {
        workspaceObserver = WorkspaceObserver(directory: directory, dock: dock, onDockRelaunch: preview.dockRelaunched)
        preview.start()
        let clicks = DockClickHandler(dock: dock, directory: directory)
        let pointer = preview.pointer
        let tap = EventTap(events: [.leftMouseDown, .leftMouseUp, .mouseMoved]) { type, event in
            if type == .mouseMoved {
                pointer.moved(to: event.location)
                return false
            }
            return clicks.handle(type, event)
        }
        try tap.start()
        eventTap = tap
    }

    func stop() {
        eventTap?.stop()
        eventTap = nil
        preview.stop()
        workspaceObserver?.invalidate()
        workspaceObserver = nil
    }
}
