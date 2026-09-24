import AppKit

// Short, stable names for the debug log lines.

extension DockItem {
    var logName: String {
        appURL.deletingPathExtension().lastPathComponent
    }
}

extension RunningApp {
    var logName: String {
        "\(bundleURL.deletingPathExtension().lastPathComponent) (pid \(pid))"
    }
}

extension NSRunningApplication {
    var logName: String {
        "\(localizedName ?? bundleIdentifier ?? "unknown") (pid \(processIdentifier))"
    }
}

extension PreviewWindow {
    var logName: String {
        let id = windowID.map(String.init) ?? "none"
        return "'\(title)' id=\(id)\(window.isMinimized ? " minimized" : "")"
    }
}

extension CGPoint {
    var logText: String {
        "(\(Int(x.rounded())), \(Int(y.rounded())))"
    }
}
