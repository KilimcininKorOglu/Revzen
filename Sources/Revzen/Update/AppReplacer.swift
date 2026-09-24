import AppKit
import Foundation

/// Puts a verified app in place of the running one and relaunches it.
@MainActor
enum AppReplacer {
    /// Replaces the running bundle, starts the new app once this process
    /// exits, then quits.
    static func installAndRelaunch(_ staged: URL) async throws {
        let target = Bundle.main.bundleURL
        if FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: staged)
        } else {
            try await replaceAsAdministrator(target, with: staged)
        }
        try relaunchAfterExit(target)
        NSApp.terminate(nil)
    }

    /// Asks for an administrator password, for an app in a folder that the
    /// user cannot write. The paths reach the shell only as quoted forms.
    private static func replaceAsAdministrator(_ target: URL, with staged: URL) async throws {
        let script = [
            "on run argv",
            "set source to quoted form of item 1 of argv",
            "set destination to quoted form of item 2 of argv",
            "do shell script \"/bin/rm -rf \" & destination & \" && /usr/bin/ditto \" & source & \" \" & destination "
                + "with administrator privileges",
            "end run"
        ]
        let arguments = script.flatMap { ["-e", $0] } + [staged.path, target.path]
        _ = try await ProcessRunner.run("/usr/bin/osascript", arguments)
    }

    /// A detached shell waits for this process to exit, then opens the app.
    private static func relaunchAfterExit(_ app: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
            "sh", String(ProcessInfo.processInfo.processIdentifier), app.path
        ]
        try process.run()
    }
}
