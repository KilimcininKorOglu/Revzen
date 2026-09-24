import ApplicationServices
import RevzenCore

/// A top-level window of an app, read through the Accessibility API.
struct AppWindow: Sendable, Equatable {
    let element: AXElement
    let pid: pid_t
    let isMinimized: Bool
}

/// A window as the preview shows it.
struct PreviewWindow: Sendable, Identifiable, Equatable {
    let window: AppWindow
    /// Nil when the private AX to CGWindowID mapping fails.
    let windowID: CGWindowID?
    let title: String

    /// AX element identity is stable for the life of the window.
    var id: AXElement { window.element }
}

/// Window queries and window actions through the Accessibility API.
enum WindowService {
    /// Windows of the app with the data the preview needs. Blocks on AX, so
    /// call it off the main actor. The preview does not run on the tap
    /// thread, so it waits as long as a window action for a busy app.
    static func previewWindows(of pid: pid_t) -> [PreviewWindow] {
        windows(of: pid, timeout: AXElement.actionTimeout).map { window in
            PreviewWindow(
                window: window,
                windowID: window.element.windowID(),
                title: window.element.string(kAXTitleAttribute) ?? ""
            )
        }
    }

    /// Brings one window to the front, restoring it first when minimized.
    static func focus(_ window: AppWindow) {
        let element = window.element.withTimeout(AXElement.actionTimeout)
        let app = AXElement.application(window.pid, timeout: AXElement.actionTimeout)
        // Revzen is an accessory app. NSRunningApplication.activate() is
        // refused under cooperative activation, AX activation is not.
        report(app.set(kAXFrontmostAttribute, true), "activate", window.pid)
        if window.isMinimized {
            report(element.set(kAXMinimizedAttribute, false), "restore", window.pid)
        }
        report(element.set(kAXMainAttribute, true), "make main", window.pid)
        report(element.perform(kAXRaiseAction), "raise", window.pid)
    }

    /// Standard windows of the app on the current Space, plus its minimized
    /// windows. Dialogs, panels and other subroles are left out. A minimized
    /// window reports the AXDialog subrole on macOS 27, so the minimized state
    /// decides for those windows, not the subrole.
    static func windows(of pid: pid_t, timeout: Float = AXElement.readTimeout) -> [AppWindow] {
        AXElement.application(pid, timeout: timeout).elements(kAXWindowsAttribute).compactMap { element in
            guard let minimized = element.bool(kAXMinimizedAttribute),
                  minimized || element.string(kAXSubroleAttribute) == kAXStandardWindowSubrole else { return nil }
            return AppWindow(element: element, pid: pid, isMinimized: minimized)
        }
    }

    static func state(of pid: pid_t, isFrontmost: Bool) -> AppWindowState {
        let windows = windows(of: pid)
        let minimized = windows.filter(\.isMinimized).count
        return AppWindowState(
            isFrontmost: isFrontmost,
            visibleCount: windows.count - minimized,
            minimizedCount: minimized
        )
    }

    /// Minimizes (`true`) or restores (`false`) every window of the app that
    /// is not in that state yet. Activation is left to the caller.
    static func setAllMinimized(_ minimized: Bool, of pid: pid_t) {
        for window in windows(of: pid, timeout: AXElement.actionTimeout) where window.isMinimized != minimized {
            report(window.element.set(kAXMinimizedAttribute, minimized), "set minimized=\(minimized)", pid)
        }
    }

    private static func report(_ result: AXError, _ action: String, _ pid: pid_t) {
        if result != .success {
            log.error("AX \(action, privacy: .public) failed for pid \(pid): \(result.rawValue)")
        }
    }
}
