import SwiftUI

@MainActor
final class RecordingLifetime {
    static let shared = RecordingLifetime()
    var locked = false
    func explain() {
        let alert = NSAlert()
        alert.messageText = "Finish saving your recording first"
        alert.informativeText = "Stop the recording and wait for it to save before closing OuterView. If saving failed, use Retry Save."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if RecordingLifetime.shared.locked { RecordingLifetime.shared.explain(); return .terminateCancel }
        return .terminateNow
    }
}

struct RecordingCloseGuard: NSViewRepresentable {
    let locked: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.locked = locked
        RecordingLifetime.shared.locked = locked
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            if window.delegate !== context.coordinator {
                context.coordinator.window = window
                context.coordinator.original = window.delegate
                window.delegate = context.coordinator
            }
        }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if coordinator.window?.delegate === coordinator { coordinator.window?.delegate = coordinator.original }
    }
    final class Coordinator: NSObject, NSWindowDelegate {
        weak var window: NSWindow?
        weak var original: NSWindowDelegate?
        var locked = false
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if locked { RecordingLifetime.shared.explain(); return false }
            return original?.windowShouldClose?(sender) ?? true
        }
        override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || (original?.responds(to: selector) ?? false) }
        override func forwardingTarget(for selector: Selector!) -> Any? { original }
    }
}
