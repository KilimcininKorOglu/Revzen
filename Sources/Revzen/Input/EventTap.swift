import CoreGraphics
import Foundation

/// A session event tap that runs on its own thread, so a slow main thread
/// never delays system input and never trips the tap timeout.
final class EventTap: Sendable {
    /// Returns true to swallow the event.
    typealias Handler = @Sendable (CGEventType, CGEvent) -> Bool

    enum Failure: Error, LocalizedError {
        case createFailed

        var errorDescription: String? {
            "macOS refused to create the event tap. Check the Accessibility permission of Revzen."
        }
    }

    /// CoreFoundation types are not Sendable, so the state the tap thread
    /// shares with the caller lives here behind a lock.
    private final class Context: @unchecked Sendable {
        let handler: Handler
        private let lock = NSLock()
        private var storedPort: CFMachPort?
        private var storedRunLoop: CFRunLoop?

        init(handler: @escaping Handler) {
            self.handler = handler
        }

        var port: CFMachPort? {
            get { lock.withLock { storedPort } }
            set { lock.withLock { storedPort = newValue } }
        }

        var runLoop: CFRunLoop? {
            get { lock.withLock { storedRunLoop } }
            set { lock.withLock { storedRunLoop = newValue } }
        }
    }

    private let context: Context
    private let mask: CGEventMask

    init(events: [CGEventType], handler: @escaping Handler) {
        context = Context(handler: handler)
        mask = events.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    }

    func start() throws {
        let refcon = Unmanaged.passUnretained(context).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            throw Failure.createFailed
        }
        context.port = port
        let thread = Thread { [context] in
            guard let port = context.port else { return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            let current = CFRunLoopGetCurrent()
            CFRunLoopAddSource(current, source, .commonModes)
            context.runLoop = current
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "com.kilimcininkoroglu.revzen.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        if let port = context.port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let loop = context.runLoop {
            CFRunLoopStop(loop)
        }
    }

    fileprivate static func handle(
        _ refcon: UnsafeMutableRawPointer?, _ type: CGEventType, _ event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let context = Unmanaged<Context>.fromOpaque(refcon).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            log.error("event tap disabled by the system (\(type.rawValue)), enabling it again")
            if let port = context.port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        return context.handler(type, event) ? nil : Unmanaged.passUnretained(event)
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    EventTap.handle(refcon, type, event)
}
