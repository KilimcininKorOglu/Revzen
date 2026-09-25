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
        private var storedEnabled: Bool

        init(handler: @escaping Handler, enabled: Bool) {
            self.handler = handler
            storedEnabled = enabled
        }

        var enabled: Bool {
            get { lock.withLock { storedEnabled } }
            set { lock.withLock { storedEnabled = newValue } }
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

    /// A tap created with `enabled: false` receives nothing until
    /// `setEnabled(true)`.
    init(events: [CGEventType], enabled: Bool = true, handler: @escaping Handler) {
        context = Context(handler: handler, enabled: enabled)
        mask = events.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    }

    /// A disabled tap costs nothing: the window server does not send it the
    /// events, so they reach the apps without a round trip through Revzen.
    func setEnabled(_ enabled: Bool) {
        context.enabled = enabled
        if let port = context.port {
            CGEvent.tapEnable(tap: port, enable: enabled)
        }
    }

    func start() throws {
        let refcon = Unmanaged.passUnretained(context).toOpaque()
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: eventTapCallback,
                userInfo: refcon
            )
        else {
            throw Failure.createFailed
        }
        context.port = port
        // A new tap starts enabled. Applied here, before any setEnabled call.
        CGEvent.tapEnable(tap: port, enable: context.enabled)
        let thread = Thread { [context] in
            guard let port = context.port else { return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            let current = CFRunLoopGetCurrent()
            CFRunLoopAddSource(current, source, .commonModes)
            context.runLoop = current
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
            DebugLog.error(.app, "event tap disabled by the system (\(type.rawValue)), enabling it again")
            if let port = context.port, context.enabled {
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
