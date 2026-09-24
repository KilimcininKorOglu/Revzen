import ApplicationServices
import RevzenCore

/// A top-level window of an app, read through the Accessibility API.
struct AppWindow: Sendable, Equatable {
    let element: AXElement
    let pid: pid_t
    let isMinimized: Bool
}

/// Window queries and window actions through the Accessibility API.
enum WindowService {
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
            let result = window.element.set(kAXMinimizedAttribute, minimized)
            if result != .success {
                log.error("AX set minimized=\(minimized) failed for pid \(pid): \(result.rawValue)")
            }
        }
    }
}
