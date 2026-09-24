import SwiftUI

/// The Settings window. Standard SwiftUI form controls follow the system
/// light and dark appearance without extra code.
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Section("Permissions") {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Needed to handle Dock clicks and control windows.",
                    granted: model.permissions.accessibility,
                    request: model.permissions.requestAccessibility
                )
                PermissionRow(
                    title: "Screen Recording",
                    detail: "Needed to show window previews.",
                    granted: model.permissions.screenRecording,
                    request: model.permissions.requestScreenRecording
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.permissions.refresh() }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let request: () -> Void

    var body: some View {
        LabeledContent {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant…", action: request)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}
