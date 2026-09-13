import SwiftUI

@MainActor
final class RecordingLifetime {
    static let shared = RecordingLifetime()
    weak var capture: CaptureController?
    var locked = false
    var isLocked: Bool { locked || capture?.locked == true }
    func explain() {
        let alert = NSAlert()
        alert.messageText = "Finish saving your recording first"
        alert.informativeText = "Stop the recording and wait for it to save before closing OuterView. If saving failed, use Retry Save."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    private var terminating = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let lifetime = RecordingLifetime.shared
        if lifetime.isLocked { lifetime.explain(); return .terminateCancel }
        guard let capture = lifetime.capture else { return .terminateNow }
        guard !terminating else { return .terminateLater }
        terminating = true
        // Keep the main run loop responsive while AVFoundation releases devices
        // on its own queue; don't tear down an active preview during termination.
        Task { @MainActor in
            await capture.shutdownAndWait()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// Registers capture for app termination without replacing SwiftUI's window delegate.
/// SwiftUI owns close availability through windowDismissBehavior in the workspace.
struct RecordingLifetimeRegistration: NSViewRepresentable {
    let capture: CaptureController
    let locked: Bool
    func makeCoordinator() -> Coordinator { Coordinator(capture: capture) }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        RecordingLifetime.shared.capture = capture
        RecordingLifetime.shared.locked = locked
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        let capture = coordinator.capture
        Task { @MainActor in
            await capture.shutdownAndWait()
            if RecordingLifetime.shared.capture === capture {
                RecordingLifetime.shared.capture = nil
                RecordingLifetime.shared.locked = false
            }
        }
    }
    final class Coordinator {
        let capture: CaptureController
        init(capture: CaptureController) { self.capture = capture }
    }
}
