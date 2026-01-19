import AppKit
import KeypressCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var overlayController: OverlayController?
    private var enabledMenuItem: NSMenuItem?

    private var config: KeypressConfig { KeypressConfig.shared }

    /// App version from bundle (e.g., "0.1.0").
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.setupStatusItem()
        self.setupOverlay()
    }

    func applicationWillTerminate(_ notification: Notification) {
        self.overlayController?.stop()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.updateStatusIcon()
        self.setupMenu()
    }

    /// Updates the menu bar icon based on enabled state.
    private func updateStatusIcon() {
        guard let button = self.statusItem?.button else { return }

        // Use filled icon when enabled, outline when disabled
        let symbolName = self.config.enabled ? "keyboard.fill" : "keyboard"
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Keypress"
        )
    }

    private func setupMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Keypress v\(self.appVersion)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let enabledItem = NSMenuItem(
            title: "Enabled",
            action: #selector(self.toggleEnabled),
            keyEquivalent: "")
        enabledItem.state = self.config.enabled ? .on : .off
        self.enabledMenuItem = enabledItem
        menu.addItem(enabledItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Settings...",
            action: #selector(self.openSettings),
            keyEquivalent: ","))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(self.quit),
            keyEquivalent: "q"))

        self.statusItem?.menu = menu
    }

    private func setupOverlay() {
        self.overlayController = OverlayController(config: self.config)

        if self.config.enabled {
            // Small delay to allow system permissions to "settle" after app restart
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self.overlayController?.start()
            }
        }
    }

    // MARK: - Actions

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        self.config.enabled.toggle()
        sender.state = self.config.enabled ? .on : .off
        self.updateStatusIcon()

        if self.config.enabled {
            self.overlayController?.start()
        } else {
            self.overlayController?.stop()
        }
    }

    @objc private func openSettings() {
        // TODO: Open settings window
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
