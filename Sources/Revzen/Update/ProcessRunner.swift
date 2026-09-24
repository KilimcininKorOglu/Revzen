import Foundation

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

    /// Throws when the tool cannot start or exits with a non-zero status.
    static func run(_ tool: String, _ arguments: [String]) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        return try await withCheckedThrowingContinuation { continuation in
            // Reading to the end before the wait keeps a full pipe from
            // blocking the tool.
            DispatchQueue.global(qos: .userInitiated).async {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let message = errors.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let text = (String(bytes: message, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: Failure(tool: tool, status: process.terminationStatus, message: text))
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}
