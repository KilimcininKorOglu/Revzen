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

    /// Copies the new app next to the installed one, then swaps the two with
    /// renames. The installed app stays in place until the copy is complete,
    /// and a failed swap moves it back.
    private static let swapScript = """
        new="$2.new"
        old="$2.old"
        /bin/rm -rf "$new" "$old"
        /usr/bin/ditto "$1" "$new" || { /bin/rm -rf "$new"; exit 1; }
        /bin/mv "$2" "$old" || { /bin/rm -rf "$new"; exit 1; }
        if ! /bin/mv "$new" "$2"; then
          /bin/mv "$old" "$2"
          /bin/rm -rf "$new"
          exit 1
        fi
        /bin/rm -rf "$old"
        """

    /// Asks for an administrator password, for an app in a folder that the
    /// user cannot write. The script and the paths reach the shell only as
    /// quoted forms.
    private static func replaceAsAdministrator(_ target: URL, with staged: URL) async throws {
        let script = [
            "on run argv",
            "set command to \"/bin/sh -c \" & quoted form of item 1 of argv & \" sh \" "
                + "& quoted form of item 2 of argv & \" \" & quoted form of item 3 of argv",
            "do shell script command with administrator privileges",
            "end run"
        ]
        let arguments = script.flatMap { ["-e", $0] } + [swapScript, staged.path, target.path]
        _ = try await ProcessRunner.run("/usr/bin/osascript", arguments)
    }

    /// LaunchServices keeps a quitting app registered for a moment after its
    /// process exits, and `open` fails with -600 (procNotFound) until then,
    /// so the shell retries it for up to 10 seconds.
    private static let relaunchScript = """
        while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
        attempt=1
        while [ "$attempt" -le 50 ]; do
          if /usr/bin/open "$2" 2>/dev/null; then
            echo "$(/bin/date +%Y-%m-%dT%H:%M:%S) [update] relaunched on attempt $attempt" >>"$3"
            exit 0
          fi
          attempt=$((attempt + 1))
          /bin/sleep 0.2
        done
        echo "$(/bin/date +%Y-%m-%dT%H:%M:%S) [update] ERROR relaunch failed, open Revzen by hand" >>"$3"
        exit 1
        """

    /// A detached shell waits for this process to exit, then opens the app.
    /// It reports to the debug log while that log is on.
    private static func relaunchAfterExit(_ app: URL) throws {
        let log = DebugLog.isEnabled ? DebugLog.fileURL.path : "/dev/null"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", relaunchScript, "sh", String(ProcessInfo.processInfo.processIdentifier), app.path, log]
        DebugLog.event(.update, "relaunching \(app.path) once this process exits")
        try process.run()
    }
}
