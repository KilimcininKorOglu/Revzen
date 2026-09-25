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
    // MARK: - Window queries

    /// Windows of the app with the data the preview needs. Blocks on AX, so
    /// call it off the main actor. The preview does not run on the tap
    /// thread, so it waits as long as a window action for a busy app.
    /// The windows are in alphabetical order of their titles.
    static func previewWindows(of pid: pid_t, includeOtherSpaces: Bool = false) -> [PreviewWindow] {
        var found = windows(of: pid, timeout: AXElement.actionTimeout).map(previewWindow)
        if includeOtherSpaces {
            let known = Set(found.compactMap(\.windowID))
            found += SpaceWindows.windows(of: pid, known: known).map(previewWindow)
        }
        return WindowOrder.alphabetical(found, title: \.title, windowID: \.windowID)
    }

    /// The focused window of the app as the preview shows it. Nil when
    /// `focusedWindow(of:)` finds none.
    static func focusedPreviewWindow(of pid: pid_t) -> PreviewWindow? {
        focusedWindow(of: pid).map { previewWindow(AppWindow(element: $0, pid: pid, isMinimized: false)) }
    }

    static func previewWindow(_ window: AppWindow) -> PreviewWindow {
        PreviewWindow(
            window: window,
            windowID: window.element.windowID(),
            title: window.element.string(kAXTitleAttribute) ?? ""
        )
    }

    /// Standard windows of the app on the current Space, plus its minimized
    /// windows. Dialogs, panels and other subroles are left out. A minimized
    /// window reports the AXDialog subrole on macOS 27, so the minimized state
    /// decides for those windows, not the subrole.
    static func windows(of pid: pid_t, timeout: Float = AXElement.readTimeout) -> [AppWindow] {
        AXElement.application(pid, timeout: timeout).elements(kAXWindowsAttribute).compactMap { element in
            guard let minimized = element.bool(kAXMinimizedAttribute),
                minimized || element.string(kAXSubroleAttribute) == kAXStandardWindowSubrole
            else { return nil }
            return AppWindow(element: element, pid: pid, isMinimized: minimized)
        }
    }

    /// The focused window of the app when it is a standard window that is not
    /// minimized, so the Dock click can minimize it. Nil for a focused panel
    /// or dialog, and when the app has no focused window.
    static func focusedWindow(of pid: pid_t) -> AXElement? {
        guard let window = AXElement.application(pid).element(kAXFocusedWindowAttribute),
            window.bool(kAXMinimizedAttribute) == false,
            window.string(kAXSubroleAttribute) == kAXStandardWindowSubrole
        else { return nil }
        return window
    }
}

// MARK: - Window actions

extension WindowService {
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

    /// Brings the window `step` positions after the focused one to the front.
    /// The order is the window creation order (CGWindowID), not the AX
    /// z-order, which every raise changes.
    static func cycle(_ pid: pid_t, step: Int) {
        let windows = previewWindows(of: pid)
            .filter { $0.windowID != nil }
            .sorted { ($0.windowID ?? 0) < ($1.windowID ?? 0) }
        let app = AXElement.application(pid, timeout: AXElement.actionTimeout)
        let focused = app.element(kAXFocusedWindowAttribute)
        let current = windows.firstIndex { $0.window.element == focused }
        guard let next = WindowCycler.next(count: windows.count, current: current, step: step) else {
            DebugLog.event(.window, "cycle pid \(pid): no window to switch to (\(windows.count) windows)")
            return
        }
        DebugLog.event(
            .window,
            "cycle pid \(pid): \(current.map(String.init) ?? "none") -> \(next) "
                + "of \(windows.count), \(windows[next].logName)")
        focus(windows[next].window)
    }

    /// Closes a window by pressing its close button, as a user click would.
    /// The app may still ask to save changes.
    static func close(_ window: AppWindow) {
        let element = window.element.withTimeout(AXElement.actionTimeout)
        guard let button = element.element(kAXCloseButtonAttribute) else {
            DebugLog.error(.window, "window of pid \(window.pid) has no close button")
            return
        }
        report(button.perform(kAXPressAction), "close", window.pid)
    }

    static func minimize(_ window: AXElement, pid: pid_t) {
        report(window.withTimeout(AXElement.actionTimeout).set(kAXMinimizedAttribute, true), "minimize", pid)
    }

    private static func report(_ result: AXError, _ action: String, _ pid: pid_t) {
        guard result == .success else {
            DebugLog.error(.window, "AX \(action) failed for pid \(pid): AXError \(result.rawValue)")
            return
        }
        DebugLog.event(.window, "AX \(action) pid \(pid): ok")
    }
}
