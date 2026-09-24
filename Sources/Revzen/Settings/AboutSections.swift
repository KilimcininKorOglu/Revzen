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
