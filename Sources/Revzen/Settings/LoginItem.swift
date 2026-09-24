import Observation
import ServiceManagement

/// Launch at login through `SMAppService`. The system owns the state, so
/// it is read back after every change instead of being stored.
@MainActor
@Observable
final class LoginItem {
    private(set) var status = SMAppService.mainApp.status

    var isEnabled: Bool {
        get { status == .enabled }
        set { set(newValue) }
    }

    /// The user must still allow the item in System Settings > General > Login Items.
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            ErrorReporter.present("Revzen could not change the launch at login setting", error: error)
        }
        refresh()
    }
}
