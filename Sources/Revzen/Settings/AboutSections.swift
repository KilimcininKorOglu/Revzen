import SwiftUI

/// The automatic check setting and the manual check.
struct UpdatesSection: View {
    @Binding var autoCheck: Bool
    let updates: UpdateService

    var body: some View {
        Section("Updates") {
            Toggle(isOn: $autoCheck) {
                Text("Check for updates automatically")
                Text("Revzen asks GitHub for a new release once a day.")
            }
            LabeledContent("Last checked") {
                HStack {
                    Text(lastCheckText)
                        .foregroundStyle(.secondary)
                    Button("Check Now", action: updates.checkNow)
                }
            }
        }
    }

    private var lastCheckText: String {
        updates.lastCheck?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
    }
}

/// The debug log switch, for reporting a problem.
struct DiagnosticsSection: View {
    @Binding var debugLogging: Bool

    var body: some View {
        Section("Diagnostics") {
            Toggle(isOn: $debugLogging) {
                Text("Debug logging")
                Text(
                    "Writes every Dock click, hover, scroll and window action to \(logPath), "
                        + "including the window titles and names of other apps. It turns off when Revzen quits. "
                        + "Delete the log after you send it.")
            }
            LabeledContent("Log file") {
                HStack {
                    Button("Show in Finder", action: showLog)
                    Button("Delete Log", role: .destructive, action: deleteLog)
                }
            }
        }
    }

    private var logPath: String {
        (DebugLog.fileURL.path as NSString).abbreviatingWithTildeInPath
    }

    private func showLog() {
        let file = DebugLog.fileURL
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            ErrorReporter.present("There is no debug log yet", error: CocoaError(.fileNoSuchFile))
        }
    }

    private func deleteLog() {
        do {
            try DebugLog.deleteFiles()
        } catch {
            ErrorReporter.present("The debug log could not be deleted", error: error)
        }
    }
}

struct AboutSection: View {
    var body: some View {
        Section("About") {
            LabeledContent("Version", value: AppInfo.versionString)
            LabeledContent("Developer", value: AppInfo.developer)
            LabeledContent("GitHub") {
                Link("github.com/\(AppInfo.repository)", destination: AppInfo.repositoryURL)
            }
            LabeledContent("X") {
                Link("x.com/KogOglan", destination: AppInfo.xURL)
            }
        }
    }
}
