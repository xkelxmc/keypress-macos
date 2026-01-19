import AppKit
import KeypressCore
import SwiftUI

/// Controls the Settings window lifecycle.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    /// Opens the Settings window, creating it if necessary.
    func showSettings() {
        if let window = self.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(config: KeypressConfig.shared)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Keypress Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 480, height: 560))
        window.center()
        window.isReleasedWhenClosed = false

        // Keep reference and show
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closes the Settings window.
    func closeSettings() {
        self.window?.close()
    }
}
