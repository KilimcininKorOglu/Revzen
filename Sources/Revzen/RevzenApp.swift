import AppKit
import SwiftUI

@main
struct RevzenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Revzen", systemImage: "dock.rectangle") {
            MenuContent(model: appDelegate.model)
        }
        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}

/// Items of the menu bar menu.
struct MenuContent: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !model.permissions.accessibility {
            Button("Grant Accessibility Access…") { model.permissions.requestAccessibility() }
        }
        if !model.permissions.screenRecording {
            Button("Grant Screen Recording Access…") { model.permissions.requestScreenRecording() }
        }
        Button("Settings…") {
            // An accessory app does not come forward on its own, so the
            // Settings window would open behind the frontmost app.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Check for Updates…") { model.updates.checkNow() }
        Divider()
        Button("Quit Revzen") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
