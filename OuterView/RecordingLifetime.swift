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

struct RecordingCloseGuard: NSViewRepresentable {
    let capture: CaptureController
    let locked: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.locked = locked
        coordinator.capture = capture
        RecordingLifetime.shared.capture = capture
        RecordingLifetime.shared.locked = locked
        DispatchQueue.main.async { [weak view, weak coordinator] in
            guard let view, let coordinator, coordinator.active, let window = view.window else { return }
            // Install once per attachment. Rewrapping SwiftUI's delegate on every
            // state update can form a forwarding cycle during close/quit.
            guard coordinator.window == nil else { return }
            coordinator.window = window
            var original = window.delegate
            while let prior = original as? Coordinator { original = prior.original }
            coordinator.original = original
            window.delegate = coordinator
        }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.active = false
        if coordinator.window?.delegate === coordinator { coordinator.window?.delegate = coordinator.original }
        if RecordingLifetime.shared.capture === coordinator.capture {
            RecordingLifetime.shared.capture = nil
            RecordingLifetime.shared.locked = false
        }
    }
    final class Coordinator: NSObject, NSWindowDelegate {
        weak var window: NSWindow?
        weak var original: NSWindowDelegate?
        weak var capture: CaptureController?
        var active = true
        var locked = false
        private var closing = false
        private var canClose = false
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if locked || capture?.locked == true { RecordingLifetime.shared.explain(); return false }
            if canClose { return original?.windowShouldClose?(sender) ?? true }
            guard !closing else { return false }
            guard let capture else { return original?.windowShouldClose?(sender) ?? true }
            closing = true
            Task { @MainActor [weak self, weak sender] in
                await capture.shutdownAndWait()
                guard let self, let sender else { return }
                self.canClose = true
                sender.performClose(nil)
                self.canClose = false
                self.closing = false
            }
            return false
        }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }
        override func forwardingTarget(for selector: Selector!) -> Any? { original }
    }
}
