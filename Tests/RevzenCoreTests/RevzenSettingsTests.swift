import Foundation
import Testing

@testable import RevzenCore

@Suite("RevzenSettings")
struct RevzenSettingsTests {
    private func makeStore() -> (SettingsStore, UserDefaults) {
        let suite = "revzen.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (SettingsStore(defaults: defaults), defaults)
    }

    @Test("A fresh install starts with the documented defaults")
    func freshInstallUsesDefaults() throws {
        let (store, _) = makeStore()
        let settings = try store.load()
        #expect(settings.hoverDelayMs == RevzenSettings.defaultHoverDelayMs)
        #expect(settings.excludedBundleIDs.isEmpty)
        #expect(settings.showOtherSpaces == false)
        #expect(settings.autoCheckUpdates)
        #expect(settings.debugLogging == false)
    }

    @Test("Saved settings survive a relaunch")
    func roundTrip() throws {
        let (store, _) = makeStore()
        let saved = RevzenSettings(
            hoverDelayMs: 750,
            excludedBundleIDs: ["com.apple.Terminal"],
            showOtherSpaces: true,
            autoCheckUpdates: false,
            debugLogging: true
        )
        try store.save(saved)
        #expect(try store.load() == saved)
    }

    @Test(
        "The hover delay stays inside the slider range, whatever the source",
        arguments: [
            (-50, 0), (0, 0), (1200, 1200), (99_999, 2000)
        ])
    func hoverDelayIsClamped(input: Int, expected: Int) {
        var settings = RevzenSettings(hoverDelayMs: input)
        #expect(settings.hoverDelayMs == expected)
        settings.hoverDelayMs = input
        #expect(settings.hoverDelayMs == expected)
    }

    @Test("A stored delay outside the range is clamped on load")
    func decodedDelayIsClamped() throws {
        let (store, defaults) = makeStore()
        let json = #"{"hoverDelayMs":-10,"excludedBundleIDs":[],"showOtherSpaces":false}"#
        defaults.set(Data(json.utf8), forKey: SettingsStore.key)
        #expect(try store.load().hoverDelayMs == 0)
    }

    @Test("Settings saved by an older build get the automatic check on and debug logging off")
    func olderSettingsEnableAutoCheck() throws {
        let (store, defaults) = makeStore()
        let json = #"{"hoverDelayMs":300,"excludedBundleIDs":["com.apple.Terminal"],"showOtherSpaces":true}"#
        defaults.set(Data(json.utf8), forKey: SettingsStore.key)
        let settings = try store.load()
        #expect(settings.autoCheckUpdates)
        #expect(settings.debugLogging == false)
        #expect(settings.hoverDelayMs == 300)
    }

    @Test("A corrupt stored value is reported, not silently replaced by defaults")
    func corruptValueThrows() {
        let (store, defaults) = makeStore()
        defaults.set(Data("not json".utf8), forKey: SettingsStore.key)
        #expect(throws: DecodingError.self) { try store.load() }
    }
}
