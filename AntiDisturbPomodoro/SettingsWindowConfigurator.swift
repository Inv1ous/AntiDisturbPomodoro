import SwiftUI
import AppKit

/// Configures the SwiftUI Settings window to float above other windows and
/// automatically close when it loses key status.
struct SettingsWindowConfigurator: NSViewRepresentable {
    class Coordinator {
        var observer: NSObjectProtocol?
        weak var window: NSWindow?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Configure once when the window becomes available
        guard context.coordinator.observer == nil, let window = nsView.window else { return }
        context.coordinator.window = window

        // Bring to front and keep above normal windows
        window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // Close when clicking outside (on resign key)
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            window?.close()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let observer = coordinator.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
