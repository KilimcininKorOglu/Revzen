import AppKit
import RevzenCore

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

    init(excludedBundleIDs: Set<String>, settings: @escaping @MainActor () -> RevzenSettings) {
        directory.setExcluded(excludedBundleIDs)
        snapshots = WindowSnapshotter(directory: directory)
        preview = PreviewController(dock: dock, directory: directory, snapshots: snapshots, settings: settings)
    }

    func setExcluded(_ bundleIDs: Set<String>) {
        directory.setExcluded(bundleIDs)
    }

    func start() throws {
        workspaceObserver = WorkspaceObserver(directory: directory, dock: dock, onDockRelaunch: preview.dockRelaunched)
        preview.start()
        snapshots.start()
        let snapshots = snapshots
        let preview = preview
        let clicks = DockClickHandler(
            dock: dock,
            directory: directory,
            beforeMinimize: { pid in await snapshots.snapshot(pid: pid) },
            onMenuClick: { Task { @MainActor in preview.dockMenuOpened() } }
        )
        let scrolls = DockScrollHandler(dock: dock, directory: directory)
        let pointer = preview.pointer
        let events: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .mouseMoved, .scrollWheel]
        let tap = EventTap(events: events) { type, event in
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
        DebugLog.event(.app, "Dock services started")
    }

    func stop() {
        DebugLog.event(.app, "Dock services stopped")
        eventTap?.stop()
        eventTap = nil
        preview.stop()
        snapshots.stop()
        workspaceObserver?.invalidate()
        workspaceObserver = nil
    }
}
