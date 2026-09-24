import AppKit
import Synchronization

/// A running app as the event tap thread sees it.
struct RunningApp: Sendable, Equatable {
    let pid: pid_t
    let bundleID: String?
    let bundleURL: URL
}

/// Running apps, the frontmost app and the excluded bundle IDs, readable from
/// any thread. The main actor keeps it current from `NSWorkspace`
/// notifications, so the event tap never touches AppKit.
final class AppDirectory: Sendable {
    private struct State {
        var appsByURL: [URL: RunningApp] = [:]
        var frontmostPID: pid_t?
        var excludedBundleIDs: Set<String> = []
        /// Counts app activations, so a click can tell whether the app
        /// stayed frontmost since an earlier click.
        var activationGeneration = 0
    }

    private let state = Mutex(State())

    func app(forBundleURL url: URL) -> RunningApp? {
        let key = url.standardizedFileURL
        return state.withLock { $0.appsByURL[key] }
    }

    func isFrontmost(_ pid: pid_t) -> Bool {
        state.withLock { $0.frontmostPID == pid }
    }

    var activationGeneration: Int {
        state.withLock { $0.activationGeneration }
    }

    func isExcluded(_ app: RunningApp) -> Bool {
        guard let bundleID = app.bundleID else { return false }
        return state.withLock { $0.excludedBundleIDs.contains(bundleID) }
    }

    func setExcluded(_ bundleIDs: Set<String>) {
        state.withLock { $0.excludedBundleIDs = bundleIDs }
    }

    @MainActor
    func reload(from workspace: NSWorkspace) {
        let apps = workspace.runningApplications.compactMap(Self.record)
        let frontmost = workspace.frontmostApplication?.processIdentifier
        state.withLock {
            $0.appsByURL = Dictionary(apps.map { ($0.bundleURL, $0) }, uniquingKeysWith: { first, _ in first })
            $0.frontmostPID = frontmost
            $0.activationGeneration += 1
        }
    }

    @MainActor
    func didLaunch(_ app: NSRunningApplication) {
        guard let record = Self.record(app) else { return }
        state.withLock { $0.appsByURL[record.bundleURL] = record }
    }

    @MainActor
    func didTerminate(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        state.withLock { state in
            state.appsByURL = state.appsByURL.filter { $0.value.pid != pid }
            if state.frontmostPID == pid { state.frontmostPID = nil }
        }
    }

    @MainActor
    func didActivate(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        state.withLock {
            $0.frontmostPID = pid
            $0.activationGeneration += 1
        }
    }

    @MainActor
    private static func record(_ app: NSRunningApplication) -> RunningApp? {
        guard app.activationPolicy == .regular, let url = app.bundleURL else { return nil }
        return RunningApp(pid: app.processIdentifier, bundleID: app.bundleIdentifier, bundleURL: url.standardizedFileURL)
    }
}

/// Feeds `NSWorkspace` notifications into an `AppDirectory`.
@MainActor
final class WorkspaceObserver {
    private var tokens: [NSObjectProtocol] = []

    init(directory: AppDirectory, dock: DockAX, onDockRelaunch: @escaping @MainActor () -> Void) {
        let workspace = NSWorkspace.shared
        directory.reload(from: workspace)
        dock.attach()
        let center = workspace.notificationCenter
        let didLaunch: @MainActor (NSRunningApplication) -> Void = { app in
            DebugLog.event(.workspace, "launched \(app.logName)")
            if app.bundleIdentifier == DockAX.bundleID {
                DebugLog.event(.workspace, "the Dock relaunched")
                dock.attach()
                onDockRelaunch()
            }
            directory.didLaunch(app)
        }
        let didTerminate: @MainActor (NSRunningApplication) -> Void = { app in
            DebugLog.event(.workspace, "terminated \(app.logName)")
            directory.didTerminate(app)
        }
        let didActivate: @MainActor (NSRunningApplication) -> Void = { app in
            DebugLog.event(.workspace, "activated \(app.logName)")
            directory.didActivate(app)
        }
        let handlers: [(Notification.Name, @MainActor (NSRunningApplication) -> Void)] = [
            (NSWorkspace.didLaunchApplicationNotification, didLaunch),
            (NSWorkspace.didTerminateApplicationNotification, didTerminate),
            (NSWorkspace.didActivateApplicationNotification, didActivate)
        ]
        tokens = handlers.map { name, handler in
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                    return
                }
                MainActor.assumeIsolated { handler(app) }
            }
        }
    }

    func invalidate() {
        tokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        tokens = []
    }
}
