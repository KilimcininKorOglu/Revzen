import Foundation
import OSLog
import RevzenCore
import Synchronization

/// The event log for diagnosing Revzen: every Dock click, scroll and hover,
/// every preview and window action. Settings turns it on; it is off by
/// default, and a disabled log does not build its messages.
///
/// Lines go to OSLog (category "debug", level debug) and to
/// `~/Library/Logs/Revzen/revzen.log`. The file moves to `revzen.log.1`
/// when it passes 5 MB, so the log never holds more than about 10 MB.
enum DebugLog {
    enum Area: String {
        case app, click, scroll, hover, pointer, preview, window, capture, workspace, update, settings
    }

    static let fileURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appending(path: "Logs/Revzen/revzen.log")

    private static let enabled = Atomic<Bool>(false)
    private static let logger = Logger(subsystem: "com.kilimcininkoroglu.revzen", category: "debug")
    private static let writer = LogFileWriter(url: fileURL, maxSize: 5 * 1024 * 1024)

    static var isEnabled: Bool {
        enabled.load(ordering: .relaxed)
    }

    static func setEnabled(_ value: Bool) {
        guard enabled.exchange(value, ordering: .relaxed) != value else { return }
        if value {
            let system = ProcessInfo.processInfo.operatingSystemVersionString
            event(.app, "debug logging on, Revzen \(AppInfo.versionString), macOS \(system)")
        } else {
            writer.write(Date(), "[app] debug logging off")
        }
    }

    static func event(_ area: Area, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = "[\(area.rawValue)] \(message())"
        logger.debug("\(line, privacy: .public)")
        writer.write(Date(), line)
    }

    /// A failure always reaches OSLog at error level. The file gets it
    /// while the debug log is on, next to the events that led to it.
    static func error(_ area: Area, _ message: String) {
        log.error("\(message, privacy: .public)")
        guard isEnabled else { return }
        writer.write(Date(), "[\(area.rawValue)] ERROR \(message)")
    }
}

extension RevzenSettings {
    var logDescription: String {
        "delay=\(hoverDelayMs)ms excluded=\(excludedBundleIDs.sorted()) otherSpaces=\(showOtherSpaces) "
            + "autoUpdate=\(autoCheckUpdates) debug=\(debugLogging)"
    }
}

/// Appends lines to the log file on one serial queue.
private final class LogFileWriter: @unchecked Sendable {
    private let url: URL
    private let maxSize: UInt64
    /// Local time, so the lines match the clock of the person testing.
    private static let stampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .current)
    private let queue = DispatchQueue(label: "com.kilimcininkoroglu.revzen.debuglog")
    // Touched only on `queue`.
    private var handle: FileHandle?
    private var failed = false

    init(url: URL, maxSize: UInt64) {
        self.url = url
        self.maxSize = maxSize
    }

    func write(_ date: Date, _ line: String) {
        queue.async { [self] in
            let stamp = date.formatted(Self.stampStyle)
            do {
                try append(Data("\(stamp) \(line)\n".utf8))
                failed = false
            } catch {
                handle = nil
                // Report once per failure streak, not once per event.
                if !failed {
                    log.error("Debug log write failed: \(error.localizedDescription, privacy: .public)")
                }
                failed = true
            }
        }
    }

    private func append(_ data: Data) throws {
        let handle = try openHandle()
        try handle.write(contentsOf: data)
        if try handle.offset() > maxSize {
            try rotate()
        }
    }

    private func openHandle() throws -> FileHandle {
        if let handle { return handle }
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) {
            guard manager.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        }
        let opened = try FileHandle(forWritingTo: url)
        try opened.seekToEnd()
        handle = opened
        return opened
    }

    private func rotate() throws {
        try handle?.close()
        handle = nil
        let previous = url.appendingPathExtension("1")
        if FileManager.default.fileExists(atPath: previous.path) {
            try FileManager.default.removeItem(at: previous)
        }
        try FileManager.default.moveItem(at: url, to: previous)
    }
}
