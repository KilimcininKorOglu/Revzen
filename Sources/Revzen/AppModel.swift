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
            services?.setExcluded(settings.excludedBundleIDs)
            do {
                try store.save(settings)
            } catch {
                ErrorReporter.present("Revzen could not save the settings", error: error)
            }
        }
    }

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
