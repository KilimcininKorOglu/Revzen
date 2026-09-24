import RevzenCore
import SwiftUI

/// The Settings window. Standard SwiftUI form controls follow the system
/// light and dark appearance without extra code.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            GeneralSection(model: model, loginItem: model.loginItem)
            ExcludedAppsSection(excluded: $model.settings.excludedBundleIDs)
            PermissionsSection(permissions: model.permissions)
            UpdatesSection(autoCheck: $model.settings.autoCheckUpdates, updates: model.updates)
            DiagnosticsSection(debugLogging: $model.settings.debugLogging)
            AboutSection()
        }
        .formStyle(.grouped)
        // The grouped form scrolls, so the window also fits a small screen.
        .frame(width: 480, height: 640)
        .onAppear {
            model.permissions.refresh()
            model.loginItem.refresh()
        }
    }
}

private struct GeneralSection: View {
    @Bindable var model: AppModel
    @Bindable var loginItem: LoginItem

    var body: some View {
        Section("General") {
            Toggle("Launch at login", isOn: $loginItem.isEnabled)
            if loginItem.needsApproval {
                LabeledContent("Allow Revzen in Login Items to finish.") {
                    Button("Open Login Items…", action: loginItem.openSystemSettings)
                }
            }
            LabeledContent {
                HStack {
                    Slider(value: hoverDelay, in: sliderRange, step: 50)
                    Text("\(model.settings.hoverDelayMs) ms")
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
            } label: {
                Text("Preview delay")
                Text("Time between hovering a Dock icon and showing its windows.")
            }
            Toggle(isOn: $model.settings.showOtherSpaces) {
                Text("Show windows from other Spaces")
                Text("Off: the preview lists only the windows of the current Space.")
            }
        }
    }

    private var sliderRange: ClosedRange<Double> {
        Double(RevzenSettings.hoverDelayRange.lowerBound)...Double(RevzenSettings.hoverDelayRange.upperBound)
    }

    private var hoverDelay: Binding<Double> {
        Binding(
            get: { Double(model.settings.hoverDelayMs) },
            set: { model.settings.hoverDelayMs = Int($0) }
        )
    }
}

/// Apps where Revzen does nothing: no click handling, preview or scroll.
private struct ExcludedAppsSection: View {
    @Binding var excluded: Set<String>
    @State private var selection: String?

    var body: some View {
        Section {
            List(excluded.sorted(), id: \.self, selection: $selection) { bundleID in
                ExcludedAppRow(bundleID: bundleID)
            }
            .frame(minHeight: 90)
            HStack {
                Button("Add App…", action: addApp)
                Button("Remove") {
                    if let selection {
                        excluded.remove(selection)
                        self.selection = nil
                    }
                }
                .disabled(selection == nil)
            }
        } header: {
            Text("Excluded Apps")
        } footer: {
            Text("Revzen leaves these apps alone: the Dock handles their clicks, and they get no preview or scroll switching.")
                .foregroundStyle(.secondary)
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier {
                excluded.insert(bundleID)
            } else {
                ErrorReporter.present(
                    "\(url.lastPathComponent) has no bundle identifier",
                    error: CocoaError(.fileReadCorruptFile)
                )
            }
        }
    }
}

private struct ExcludedAppRow: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
                .resizable()
                .frame(width: 20, height: 20)
            Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
            Spacer()
            Text(bundleID)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}

private struct PermissionsSection: View {
    let permissions: Permissions

    var body: some View {
        Section("Permissions") {
            PermissionRow(
                title: "Accessibility",
                detail: "Needed to handle Dock clicks and control windows.",
                granted: permissions.accessibility,
                request: permissions.requestAccessibility
            )
            PermissionRow(
                title: "Screen Recording",
                detail: "Needed to show window previews.",
                granted: permissions.screenRecording,
                request: permissions.requestScreenRecording
            )
        }
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
