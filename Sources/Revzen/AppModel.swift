import AppKit
import OSLog
import Observation
import RevzenCore

let log = Logger(subsystem: "com.kilimcininkoroglu.revzen", category: "app")

/// Owns the settings, the permission state and the services that act on the Dock.
@MainActor
@Observable
final class AppModel {
    let permissions = Permissions()
    let loginItem = LoginItem()

    var settings: RevzenSettings {
        didSet {
            guard settings != oldValue else { return }
            DebugLog.setEnabled(settings.debugLogging)
            DebugLog.event(.settings, "changed: \(settings.logDescription)")
            services?.setExcluded(settings.excludedBundleIDs)
            do {
                try store.save(settings)
            } catch {
                ErrorReporter.present("Revzen could not save the settings", error: error)
            }
        }
    }

    @ObservationIgnored let updates = UpdateService()
    @ObservationIgnored private var updateWindow: UpdateWindowController?
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private var services: DockServices?

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        do {
            settings = try store.load()
        } catch {
            settings = RevzenSettings()
            ErrorReporter.present("Revzen could not read the saved settings. The defaults are in use.", error: error)
        }
        DebugLog.setEnabled(settings.debugLogging)
        DebugLog.event(.settings, "loaded: \(settings.logDescription)")
    }

    func start() {
        loginItem.applyDefault()
        startUpdates()
        if !permissions.accessibility {
            permissions.requestAccessibility()
        }
        permissions.whenAccessibilityGranted { [weak self] in
            self?.startServices()
        }
    }

    func stop() {
        permissions.stopWaiting()
        updates.stop()
        services?.stop()
        services = nil
    }

    private func startServices() {
        let services = DockServices(excludedBundleIDs: settings.excludedBundleIDs) { [weak self] in
            self?.settings ?? RevzenSettings()
        }
        do {
            try services.start()
            self.services = services
        } catch {
            services.stop()
            ErrorReporter.present("Revzen could not start Dock click handling", error: error)
        }
    }
}

extension AppModel {
    private func startUpdates() {
        let window = UpdateWindowController(service: updates)
        updates.onPresent = { [weak window] in window?.show() }
        updateWindow = window
        updates.start { [weak self] in self?.settings.autoCheckUpdates ?? false }
    }
}

/// Shows an error to the user. Every failure that changes what the user sees
/// goes through here, so no failure stays silent.
@MainActor
enum ErrorReporter {
    static func present(_ message: String, error: Error) {
        DebugLog.error(.app, "\(message): \(error.localizedDescription)")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
