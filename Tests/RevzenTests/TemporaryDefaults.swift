import Foundation
import Testing

/// A UserDefaults suite for one test. `remove()` deletes the domain and its
/// plist, which `removePersistentDomain` leaves behind as an empty file in
/// ~/Library/Preferences.
final class TemporaryDefaults {
    let name = "revzen.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    func remove() {
        defaults.removePersistentDomain(forName: name)
        let file = URL.libraryDirectory.appending(path: "Preferences/\(name).plist")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            Issue.record(error, "could not delete \(file.path)")
        }
    }
}
