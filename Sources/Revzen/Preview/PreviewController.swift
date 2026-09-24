import AppKit
import RevzenCore

/// Shows the window preview for the hovered Dock icon and hides it when the
/// pointer leaves both the icon and the panel.
@MainActor
final class PreviewController {
    private let dock: DockAX
    private let directory: AppDirectory
    private let snapshots: WindowSnapshotter
    private let settings: @MainActor () -> RevzenSettings
    private let model = PreviewModel()
    private lazy var panel = PreviewPanel(model: model)
    private lazy var hover = DockHoverObserver(dock: dock) { [weak self] item in self?.hoverChanged(item) }

    /// Receives pointer moves from the event tap while a preview is pending or shown.
    private(set) lazy var pointer = PointerTracker { [weak self] point in self?.pointerMoved(to: point) }

    /// The icon the pending or shown preview belongs to.
    private var anchor: DockItem?
    private var hoverState = HoverState<DockItem>()
    private var pending: Task<Void, Never>?

    init(
        dock: DockAX,
        directory: AppDirectory,
        snapshots: WindowSnapshotter,
        settings: @escaping @MainActor () -> RevzenSettings
    ) {
        self.dock = dock
        self.directory = directory
        self.snapshots = snapshots
        self.settings = settings
        model.onSelect = { [weak self] window in self?.select(window) }
        model.onClose = { [weak self] window in self?.close(window) }
    }

    func start() {
        hover.start()
    }

    /// Re-registers the hover observer with a relaunched Dock.
    func dockRelaunched() {
        hide(reason: "the Dock relaunched")
        hover.start()
    }

    func stop() {
        hover.stop()
        hide(reason: "services stopped")
    }

    /// The Dock menu of an icon opened. The preview hides and stays hidden
    /// for that icon, as on Windows.
    func dockMenuOpened() {
        hoverState.menuOpened()
        hide(reason: "the Dock menu opened")
    }

    private func hoverChanged(_ item: DockItem?) {
        pending?.cancel()
        let inside = item.map { Self.pointerIsOver($0.frame) } ?? false
        // Without a target the pointer may be on its way into the panel.
        // pointerMoved decides.
        let target = hoverState.dockNotified(item, pointerInside: inside)
        DebugLog.event(.hover, "\(item?.logName ?? "none") pointerInside=\(inside) -> "
            + (target.map { "preview \($0.logName)" } ?? "no preview, the pointer decides"))
        if let target {
            schedule(target)
        }
        updateTracking()
    }

    private func schedule(_ item: DockItem) {
        guard let app = directory.app(forBundleURL: item.appURL), !directory.isExcluded(app) else {
            DebugLog.event(.preview, "\(item.logName): not running or excluded, no preview")
            return
        }
        guard item != anchor || !panel.isVisible else {
            DebugLog.event(.preview, "\(item.logName): preview already shown")
            return
        }
        // Moving between icons with the panel open switches at once, as on Windows.
        let delay: Duration = panel.isVisible ? .zero : .milliseconds(settings().hoverDelayMs)
        DebugLog.event(.preview, "\(app.logName): preview in \(delay)")
        anchor = item
        updateTracking()
        pending = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return // cancelled by a newer hover
            }
            await self?.show(app, for: item)
        }
    }

    private func show(_ app: RunningApp, for item: DockItem) async {
        let pid = app.pid
        let includeOtherSpaces = settings().showOtherSpaces
        let windows = await Task.detached {
            WindowService.previewWindows(of: pid, includeOtherSpaces: includeOtherSpaces)
        }.value
        guard !Task.isCancelled else {
            DebugLog.event(.preview, "\(app.logName): preview cancelled while listing windows")
            return
        }
        guard !windows.isEmpty, let screen = Self.screen(containing: item.frame) else {
            hide(reason: windows.isEmpty ? "\(app.logName) has no windows" : "no screen holds the icon")
            return
        }
        DebugLog.event(.preview, "\(app.logName): show \(windows.count) windows: "
            + windows.map(\.logName).joined(separator: ", "))
        let edge = dock.iconList()?.frame().map { DockEdge.detect(listFrame: $0, screen: screen.cgFrame) } ?? .bottom
        let layout = PreviewLayout(
            count: windows.count,
            edge: edge,
            available: edge.isVertical ? screen.cgFrame.height : screen.cgFrame.width
        )
        // Cached images show at once: the last live image of a minimized
        // window, and the previous image of a live window until the new
        // capture arrives.
        model.images = snapshots.cachedImages(for: windows.compactMap(\.windowID))
        DebugLog.event(.preview, "cached images for \(model.images.count) of \(windows.count) windows")
        model.windows = windows
        model.edge = edge
        model.layout = layout
        model.appIcon = NSWorkspace.shared.icon(forFile: app.bundleURL.path)
        place(layout.panelSize, anchor: item, edge: edge, screen: screen)
        panel.orderFrontRegardless()
        await loadImages(for: windows, scale: screen.backingScaleFactor)
    }

    private func loadImages(for windows: [PreviewWindow], scale: CGFloat) async {
        let images = await snapshots.captureLive(windows, scale: scale)
        guard !Task.isCancelled, model.windows == windows else { return }
        model.images.merge(images) { _, new in new }
    }

    private func place(_ size: CGSize, anchor: DockItem, edge: DockEdge, screen: NSScreen) {
        let frame = PanelPlacement.frame(panelSize: size, anchor: anchor.frame, edge: edge, screen: screen.cgFrame)
        panel.setFrame(PanelPlacement.flipped(frame, primaryScreenHeight: NSScreen.primaryHeight), display: true)
    }

    private func select(_ window: PreviewWindow) {
        hide(reason: "window selected: \(window.logName)")
        Task.detached { WindowService.focus(window.window) }
    }

    /// Closes the window, then lists the app's windows again. The list is
    /// read back instead of edited, because the app can refuse the close,
    /// for example with a save dialog.
    private func close(_ window: PreviewWindow) {
        guard let anchor, let app = directory.app(forBundleURL: anchor.appURL) else {
            DebugLog.event(.preview, "close of \(window.logName) ignored: the app is gone")
            return
        }
        DebugLog.event(.preview, "closing \(window.logName), then listing \(app.logName) again")
        pending?.cancel()
        if let id = window.windowID {
            snapshots.forget(id)
        }
        pending = Task { [weak self] in
            await Task.detached { WindowService.close(window.window) }.value
            do {
                // The app removes the window from its AX list shortly after the press.
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            await self?.show(app, for: anchor)
        }
    }

    /// `point` is in top-left global coordinates, as the event tap reports it.
    private func pointerMoved(to point: CGPoint) {
        guard let anchor else {
            // The Dock posts nothing for a return from the gap below or
            // beside the icon, so the pointer position decides.
            if let item = hoverState.pointerReturned(), Self.hitArea(item.frame).contains(point) {
                DebugLog.event(.pointer, "returned to \(item.logName) at \(point.logText)")
                schedule(item)
            }
            return
        }
        let panelFrame = PanelPlacement.flipped(panel.frame, primaryScreenHeight: NSScreen.primaryHeight)
        // The union also covers the gap between the icon and the panel.
        let region = panel.isVisible ? anchor.frame.union(panelFrame) : anchor.frame
        if !Self.hitArea(region).contains(point) {
            hide(reason: "the pointer left \(anchor.logName)\(panel.isVisible ? " and the panel" : "") "
                + "at \(point.logText)")
        }
    }

    private func hide(reason: String) {
        if anchor != nil || panel.isVisible {
            DebugLog.event(.preview, "hide: \(reason)")
        }
        pending?.cancel()
        pending = nil
        anchor = nil
        updateTracking()
        panel.orderOut(nil)
    }

    /// Pointer moves matter while a preview is pending or shown, and while
    /// the pointer is inside the Dock and may return to the hovered icon.
    private func updateTracking() {
        pointer.setActive(anchor != nil || hoverState.hovered != nil)
    }

    private static func hitArea(_ rect: CGRect) -> CGRect {
        rect.insetBy(dx: -2, dy: -2)
    }

    private static func pointerIsOver(_ rect: CGRect) -> Bool {
        let point = PanelPlacement.flipped(
            CGRect(origin: NSEvent.mouseLocation, size: .zero),
            primaryScreenHeight: NSScreen.primaryHeight
        ).origin
        return hitArea(rect).contains(point)
    }

    private static func screen(containing rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.cgFrame.contains(center) }
    }
}

extension NSScreen {
    /// Height of the screen that holds the menu bar, the origin of both
    /// coordinate spaces.
    static var primaryHeight: CGFloat {
        screens.first?.frame.height ?? 0
    }

    /// The screen frame in top-left global coordinates.
    var cgFrame: CGRect {
        PanelPlacement.flipped(frame, primaryScreenHeight: Self.primaryHeight)
    }
}
