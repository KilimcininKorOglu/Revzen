import AppKit
import ApplicationServices
import CoreGraphics
import Observation

/// Tracks the two TCC grants Revzen needs: Accessibility for the event tap and
/// window control, Screen Recording for window previews.
@MainActor
@Observable
final class Permissions {
    private(set) var accessibility = AXIsProcessTrusted()
    private(set) var screenRecording = CGPreflightScreenCaptureAccess()

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    func refresh() {
        accessibility = AXIsProcessTrusted()
        screenRecording = CGPreflightScreenCaptureAccess()
    }

    func requestAccessibility() {
        // The literal is the value of kAXTrustedCheckOptionPrompt, a C global
        // that Swift 6 does not accept as concurrency-safe.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            openPrivacyPane("Privacy_Accessibility")
        }
    }

    func requestScreenRecording() {
        if !CGRequestScreenCaptureAccess() {
            openPrivacyPane("Privacy_ScreenCapture")
        }
    }

    /// Calls `action` once Accessibility is granted. macOS sends no
    /// notification for the grant, so this polls once a second until it arrives.
    func whenAccessibilityGranted(_ action: @escaping @MainActor () -> Void) {
        pollTask?.cancel()
        refresh()
        if accessibility {
            action()
            return
        }
        pollTask = Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return // cancelled by stopWaiting()
                }
                guard let self else { return }
                self.refresh()
                if self.accessibility {
                    self.pollTask = nil
                    action()
                    return
                }
            }
        }
    }

    func stopWaiting() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            preconditionFailure("invalid System Settings URL for \(anchor)")
        }
        NSWorkspace.shared.open(url)
    }
}
