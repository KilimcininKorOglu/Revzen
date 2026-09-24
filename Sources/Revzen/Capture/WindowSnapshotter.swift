import AppKit
import RevzenCore

/// Keeps the last image of each window. ScreenCaptureKit cannot capture a
/// minimized window, so its preview shows the image taken before the
/// minimize. Images are taken:
/// - whenever a preview captures live windows,
/// - right before Revzen minimizes an app's windows,
/// - when an app stops being the active app,
/// - every `refreshInterval` for the active app, which covers a minimize
///   through the window's own button.
@MainActor
final class WindowSnapshotter {
    static let capacity = 48
    static let refreshInterval: Duration = .seconds(10)

    private let capture = CaptureService()
    private let directory: AppDirectory
    private var cache = LRUCache<CGWindowID, CGImage>(capacity: capacity)
    private var refreshTask: Task<Void, Never>?
    private var deactivationToken: NSObjectProtocol?

    init(directory: AppDirectory) {
        self.directory = directory
    }

    func start() {
        deactivationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            Task { @MainActor in await self?.snapshot(pid: pid) }
        }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.refreshInterval)
                } catch {
                    return // cancelled by stop()
                }
                guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { continue }
                await self?.snapshot(pid: pid)
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        if let deactivationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(deactivationToken)
        }
        deactivationToken = nil
    }

    /// Cached images for the given windows.
    func cachedImages(for ids: [CGWindowID]) -> [CGWindowID: CGImage] {
        var images: [CGWindowID: CGImage] = [:]
        for id in ids {
            images[id] = cache.value(for: id)
        }
        return images
    }

    /// Captures the windows that are not minimized and stores the images.
    func captureLive(_ windows: [PreviewWindow], scale: CGFloat) async -> [CGWindowID: CGImage] {
        let ids = windows.filter { !$0.window.isMinimized }.compactMap(\.windowID)
        let images = await capture.capture(ids, maxPointSize: PreviewLayout.maxImageSize, scale: scale)
        for (id, image) in images {
            cache.insert(image, for: id)
        }
        return images
    }

    /// Captures every visible window of the app. Excluded apps, apps without
    /// a Dock icon and Revzen itself are skipped.
    func snapshot(pid: pid_t) async {
        guard pid != ProcessInfo.processInfo.processIdentifier, !isSkipped(pid) else { return }
        let windows = await Task.detached { WindowService.previewWindows(of: pid) }.value
        _ = await captureLive(windows, scale: NSScreen.screens.first?.backingScaleFactor ?? 1)
    }

    func forget(_ id: CGWindowID) {
        cache.removeValue(for: id)
    }

    private func isSkipped(_ pid: pid_t) -> Bool {
        guard let url = NSRunningApplication(processIdentifier: pid)?.bundleURL,
              let app = directory.app(forBundleURL: url) else { return true }
        return directory.isExcluded(app)
    }
}
