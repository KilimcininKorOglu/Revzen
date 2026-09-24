import AppKit

/// The services that act on the Dock: running app tracking, the event tap
/// and the preview. They need the Accessibility permission to start.
@MainActor
final class DockServices {
    private let directory = AppDirectory()
    private let dock = DockAX()
    private let snapshots: WindowSnapshotter
    private let preview: PreviewController
    private var workspaceObserver: WorkspaceObserver?
    private var eventTap: EventTap?

    init(excludedBundleIDs: Set<String>, hoverDelay: @escaping @MainActor () -> Duration) {
        directory.setExcluded(excludedBundleIDs)
        snapshots = WindowSnapshotter(directory: directory)
        preview = PreviewController(dock: dock, directory: directory, snapshots: snapshots, hoverDelay: hoverDelay)
    }

    func setExcluded(_ bundleIDs: Set<String>) {
        directory.setExcluded(bundleIDs)
    }

    func start() throws {
        workspaceObserver = WorkspaceObserver(directory: directory, dock: dock, onDockRelaunch: preview.dockRelaunched)
        preview.start()
        snapshots.start()
        let snapshots = snapshots
        let clicks = DockClickHandler(dock: dock, directory: directory) { pid in
            await snapshots.snapshot(pid: pid)
        }
        let scrolls = DockScrollHandler(dock: dock, directory: directory)
        let pointer = preview.pointer
        let tap = EventTap(events: [.leftMouseDown, .leftMouseUp, .mouseMoved, .scrollWheel]) { type, event in
            switch type {
            case .mouseMoved:
                pointer.moved(to: event.location)
                return false
            case .scrollWheel:
                return scrolls.handle(event)
            default:
                return clicks.handle(type, event)
            }
        }
        try tap.start()
        eventTap = tap
    }

    func stop() {
        eventTap?.stop()
        eventTap = nil
        preview.stop()
        snapshots.stop()
        workspaceObserver?.invalidate()
        workspaceObserver = nil
    }
}
