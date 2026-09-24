import AppKit
import Foundation

/// Puts a verified app in place of the running one and relaunches it.
@MainActor
enum AppReplacer {
    enum Failure: Error, LocalizedError {
        /// The user cancelled the administrator password prompt.
        case cancelled
        case administratorCopy(String)

        var errorDescription: String? {
            switch self {
            case .cancelled:
                "The administrator password prompt was cancelled."
            case .administratorCopy(let detail):
                "Revzen could not copy the update into its folder, so the installed version is unchanged. "
                    + "Try again, or install the update from the GitHub release page. (\(detail))"
            }
        }
    }

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
        do {
            // The password prompt waits for the user, so it has no time limit.
            _ = try await ProcessRunner.run("/usr/bin/osascript", arguments, timeout: nil)
        } catch let failure as ProcessRunner.Failure {
            // AppleScript reports a cancelled prompt as error -128.
            throw failure.message.contains("(-128)") ? Failure.cancelled : Failure.administratorCopy(failure.message)
        }
    }

    /// The relaunch shell writes its result here and to the system log
    /// through `logger`. The shell runs after this process exits, so the
    /// next launch reports the line through `DebugLog` and deletes the file.
    static let relaunchResultURL = DebugLog.fileURL.deletingLastPathComponent().appending(path: "relaunch.log")

    /// LaunchServices keeps a quitting app registered for a moment after its
    /// process exits, and `open` fails with -600 (procNotFound) until then,
    /// so the shell retries it for up to 10 seconds. The timestamp has the
    /// debug log format without the fraction of a second.
    private static let relaunchScript = """
        result="$3"
        report() {
          zone=$(/bin/date +%z)
          echo "$(/bin/date +%Y-%m-%dT%H:%M:%S)${zone%??}:${zone#???} $1" >"$result"
          /usr/bin/logger -t Revzen "[update] $1"
        }
        while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done
        attempt=1
        while [ "$attempt" -le 50 ]; do
          if reason=$(/usr/bin/open "$2" 2>&1); then
            report "relaunched on attempt $attempt"
            exit 0
          fi
          attempt=$((attempt + 1))
          /bin/sleep 0.2
        done
        report "ERROR relaunch failed after 50 attempts, open Revzen by hand: $reason"
        exit 1
        """

    /// A detached shell waits for this process to exit, then opens the app.
    private static func relaunchAfterExit(_ app: URL) throws {
        try FileManager.default.createDirectory(
            at: relaunchResultURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", relaunchScript, "sh", String(ProcessInfo.processInfo.processIdentifier), app.path, relaunchResultURL.path
        ]
        DebugLog.event(.update, "relaunching \(app.path) once this process exits")
        try process.run()
    }

    /// Reports the result of the relaunch after the last update, once.
    static func reportLastRelaunch() {
        guard let line = try? String(contentsOf: relaunchResultURL, encoding: .utf8) else { return }
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("ERROR") {
            DebugLog.error(.update, "last relaunch: \(text)")
        } else {
            DebugLog.event(.update, "last relaunch: \(text)")
        }
        do {
            try FileManager.default.removeItem(at: relaunchResultURL)
        } catch {
            DebugLog.error(.update, "could not delete \(relaunchResultURL.path): \(error.localizedDescription)")
        }
    }
}
