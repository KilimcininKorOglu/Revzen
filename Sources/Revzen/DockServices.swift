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
    /// Pointer moves, enabled only while the preview tracks the pointer.
    private var moveTap: EventTap?

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
        let events: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .scrollWheel]
        let tap = EventTap(events: events) { type, event in
            type == .scrollWheel ? scrolls.handle(event) : clicks.handle(type, event)
        }
        try tap.start()
        eventTap = tap
        let pointer = preview.pointer
        let moves = EventTap(events: [.mouseMoved], enabled: false) { _, event in
            pointer.moved(to: event.location)
            return pointer.keepsOverPanel(event)
        }
        try moves.start()
        moveTap = moves
        pointer.attach(moves)
        DebugLog.event(.app, "Dock services started")
    }

    func stop() {
        DebugLog.event(.app, "Dock services stopped")
        eventTap?.stop()
        eventTap = nil
        preview.pointer.attach(nil)
        moveTap?.stop()
        moveTap = nil
        preview.stop()
        snapshots.stop()
        workspaceObserver?.invalidate()
        workspaceObserver = nil
    }
}
