import Foundation
import OSLog
import RevzenCore
import Synchronization

/// The event log for diagnosing Revzen: every Dock click, scroll and hover,
/// every preview and window action. Settings turns it on; it is off by
/// default, and a disabled log does not build its messages.
///
/// Events go to OSLog (category "debug", level debug) and to
/// `~/Library/Logs/Revzen/revzen.log`. Errors always go to OSLog at error
/// level, with the area as the category. The file moves to `revzen.log.1`
/// when it passes 5 MB, so the log never holds more than about 10 MB.
enum DebugLog {
    enum Area: String {
        case app, click, scroll, hover, pointer, preview, window, capture, workspace, update, settings
    }

    static let fileURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appending(path: "Logs/Revzen/revzen.log")

    private static let enabled = Atomic<Bool>(false)
    static let subsystem = "com.kilimcininkoroglu.revzen"
    private static let logger = Logger(subsystem: subsystem, category: "debug")
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
        logger(for: area).error("\(message, privacy: .public)")
        guard isEnabled else { return }
        writer.write(Date(), "[\(area.rawValue)] ERROR \(message)")
    }

    /// Deletes `revzen.log` and `revzen.log.1`. They hold window titles and
    /// app names of other apps. A later event starts a new file.
    static func deleteFiles() throws {
        try writer.deleteFiles()
    }

    /// The OSLog logger for failures of one area.
    static func logger(for area: Area) -> Logger {
        Logger(subsystem: subsystem, category: area.rawValue)
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
                try append(Data("\(stamp) \(LogLine.singleLine(line))\n".utf8))
                failed = false
            } catch {
                handle = nil
                // Report once per failure streak, not once per event.
                if !failed {
                    DebugLog.logger(for: .app).error("Debug log write failed: \(error.localizedDescription, privacy: .public)")
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

    /// The file holds content of other apps, so only the user can read it.
    private func openHandle() throws -> FileHandle {
        if let handle { return handle }
        let manager = FileManager.default
        let folder = url.deletingLastPathComponent()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        if manager.fileExists(atPath: url.path) {
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } else {
            guard manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let opened = try FileHandle(forWritingTo: url)
        try opened.seekToEnd()
        handle = opened
        return opened
    }

    func deleteFiles() throws {
        try queue.sync {
            try handle?.close()
            handle = nil
            for file in [url, url.appendingPathExtension("1")] where FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        }
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
