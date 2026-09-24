import Foundation
import Synchronization

/// Runs a command-line tool and returns its standard output.
enum ProcessRunner {
    struct Failure: Error, LocalizedError {
        let tool: String
        let status: Int32
        let message: String

        var errorDescription: String? {
            "\(tool) failed with exit status \(status): \(message)"
        }
    }

    struct Timeout: Error, LocalizedError {
        let tool: String
        let limit: Duration

        var errorDescription: String? {
            "\(tool) did not finish within \(limit) and was stopped. Try the update again later."
        }
    }

    /// The limit for a tool that needs no user input.
    static let defaultTimeout: Duration = .seconds(300)

    /// Throws when the tool cannot start, exits with a non-zero status, or
    /// runs longer than `timeout`; the tool is then terminated. A nil
    /// timeout is for a tool that waits for the user, such as a password
    /// prompt.
    ///
    /// The exit is observed with `terminationHandler`. `waitUntilExit` spins
    /// a run loop on the calling thread and can miss the exit of a tool that
    /// was started from a Swift concurrency thread, which left the update
    /// hanging after `hdiutil detach`.
    static func run(_ tool: String, _ arguments: [String], timeout: Duration? = defaultTimeout) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = PipeReader()
        let errors = PipeReader()
        process.standardOutput = output.pipe
        process.standardError = errors.pipe
        DebugLog.event(.update, "run \(tool) \(arguments.joined(separator: " "))")
        let timedOut = TimeoutFlag()
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                // A full pipe would block the tool, so both pipes are read
                // from the start; they reach end of file when the tool exits.
                let data = output.wait()
                let message = errors.wait()
                DebugLog.event(.update, "\(tool) exited with status \(process.terminationStatus)")
                if let timeout, timedOut.isSet {
                    continuation.resume(throwing: Timeout(tool: tool, limit: timeout))
                    return
                }
                guard process.terminationStatus == 0 else {
                    let text = (String(bytes: message, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: Failure(tool: tool, status: process.terminationStatus, message: text))
                    return
                }
                continuation.resume(returning: data)
            }
            do {
                try process.run()
                output.start()
                errors.start()
                if let timeout {
                    terminate(process, after: timeout, flag: timedOut)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

extension ProcessRunner {
    private static func terminate(_ process: Process, after limit: Duration, flag: TimeoutFlag) {
        let seconds = Double(limit.components.seconds) + Double(limit.components.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            guard process.isRunning else { return }
            flag.set()
            DebugLog.error(.update, "\(process.executableURL?.path ?? "tool") ran longer than \(limit), terminating it")
            process.terminate()
        }
    }
}

/// Set once when the time limit stopped the tool.
private final class TimeoutFlag: Sendable {
    private let value = Mutex(false)

    var isSet: Bool { value.withLock { $0 } }

    func set() {
        value.withLock { $0 = true }
    }
}

/// Reads one pipe to its end on a background queue.
private final class PipeReader: @unchecked Sendable {
    let pipe = Pipe()
    private let done = DispatchGroup()
    // Written once on the read queue before `done` is left, read after `wait`.
    private var data = Data()

    /// The group is entered here, so a `wait` that runs before `start`
    /// still waits for the read.
    init() {
        done.enter()
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            done.leave()
        }
    }

    func wait() -> Data {
        done.wait()
        return data
    }
}
