import AppKit
import RevzenCore
import SwiftUI

/// Owns the one update window and brings it forward on request.
@MainActor
final class UpdateWindowController {
    private let service: UpdateService
    private var window: NSWindow?

    init(service: UpdateService) {
        self.service = service
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        // An accessory app does not come forward on its own.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: UpdateView(service: service) { [weak self] in
            self?.window?.close()
        }))
        window.title = "Software Update"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

/// The content of the update window for each state of the service.
struct UpdateView: View {
    let service: UpdateService
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(20)
        .frame(width: 440)
    }

    @ViewBuilder private var content: some View {
        switch service.state {
        case .idle, .checking:
            ProgressRow(text: "Checking for updates…")
        case .upToDate:
            Message(title: "Revzen is up to date", detail: "Version \(AppInfo.versionString) is the latest release.")
            buttons(primary: ("OK", dismiss))
        case let .available(release, version):
            Message(title: "Revzen \(version) is available", detail: "You have version \(AppInfo.versionString).")
            ReleaseNotes(text: release.notes)
            buttons(secondary: ("Later", dismiss), primary: ("Download and Install", service.download))
        case let .downloading(_, version):
            ProgressRow(text: "Downloading and verifying Revzen \(version)…")
        case let .ready(_, version):
            Message(title: "Revzen \(version) is ready", detail: "Revzen quits, installs the update and opens again.")
            buttons(secondary: ("Later", close), primary: ("Install and Relaunch", service.installAndRelaunch))
        case let .failed(message):
            Message(title: "The update did not complete", detail: message)
            buttons(primary: ("OK", dismiss))
        }
    }

    private func dismiss() {
        service.dismiss()
        close()
    }

    private func buttons(secondary: (String, () -> Void)? = nil, primary: (String, () -> Void)) -> some View {
        HStack {
            Spacer()
            if let secondary {
                Button(secondary.0, action: secondary.1)
                    .keyboardShortcut(.cancelAction)
            }
            Button(primary.0, action: primary.1)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct Message: View {
    let title: String
    let detail: String

    var body: some View {
        Text(title).font(.headline)
        Text(detail).foregroundStyle(.secondary).textSelection(.enabled)
    }
}

private struct ProgressRow: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text)
        }
    }
}

private struct ReleaseNotes: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "No release notes." : text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(8)
        }
        .frame(height: 160)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}
