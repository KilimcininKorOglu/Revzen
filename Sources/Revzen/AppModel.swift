import AppKit
import Observation
import OSLog
import RevzenCore

let log = Logger(subsystem: "com.kilimcininkoroglu.revzen", category: "app")

/// Owns the settings, the permission state and the services that act on the Dock.
@MainActor
@Observable
final class AppModel {
    let permissions = Permissions()

    var settings: RevzenSettings {
        didSet {
            guard settings != oldValue else { return }
            directory.setExcluded(settings.excludedBundleIDs)
            do {
                try store.save(settings)
            } catch {
                ErrorReporter.present("Revzen could not save the settings", error: error)
            }
        }
    }

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let directory = AppDirectory()
    @ObservationIgnored private let dock = DockAX()
    @ObservationIgnored private var workspaceObserver: WorkspaceObserver?
    @ObservationIgnored private var eventTap: EventTap?

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        do {
            settings = try store.load()
        } catch {
            settings = RevzenSettings()
            ErrorReporter.present("Revzen could not read the saved settings. The defaults are in use.", error: error)
        }
        directory.setExcluded(settings.excludedBundleIDs)
    }

    func start() {
        if !permissions.accessibility {
            permissions.requestAccessibility()
        }
        permissions.whenAccessibilityGranted { [weak self] in
            self?.startServices()
        }
    }

    func stop() {
        permissions.stopWaiting()
        eventTap?.stop()
        eventTap = nil
        workspaceObserver?.invalidate()
        workspaceObserver = nil
    }

    private func startServices() {
        workspaceObserver = WorkspaceObserver(directory: directory, dock: dock)
        let clicks = DockClickHandler(dock: dock, directory: directory)
        let tap = EventTap(events: [.leftMouseDown, .leftMouseUp], handler: clicks.handle)
        do {
            try tap.start()
            eventTap = tap
        } catch {
            ErrorReporter.present("Revzen could not start Dock click handling", error: error)
        }
    }
}

/// Shows an error to the user. Every failure that changes what the user sees
/// goes through here, so no failure stays silent.
@MainActor
enum ErrorReporter {
    static func present(_ message: String, error: Error) {
        log.error("\(message, privacy: .public): \(error.localizedDescription, privacy: .public)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
