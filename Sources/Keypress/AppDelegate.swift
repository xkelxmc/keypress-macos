import AppKit
import KeyboardShortcuts
import KeypressCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var overlayController: OverlayController?
    private var enabledMenuItem: NSMenuItem?
    private var delayedStopTask: Task<Void, Never>?

    private var config: KeypressConfig { KeypressConfig.shared }

    /// App version from bundle (e.g., "0.1.0").
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.setupStatusItem()
        self.setupOverlay()
        self.setupGlobalShortcut()
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

        menu.delegate = self
        self.statusItem?.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        self.updateEnabledMenuItemTitle()
    }

    /// Updates the Enabled menu item title to include shortcut hint if set.
    private func updateEnabledMenuItemTitle() {
        guard let item = self.enabledMenuItem else { return }

        if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleOverlay) {
            item.title = "Enabled (\(shortcut.displayString))"
        } else {
            item.title = "Enabled"
        }
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

    private func setupGlobalShortcut() {
        KeyboardShortcuts.onKeyUp(for: .toggleOverlay) { [weak self] in
            Task { @MainActor in
                self?.performToggle(triggeredByShortcut: true)
            }
        }
    }

    // MARK: - Actions

    /// Common toggle logic used by both menu item and global shortcut.
    /// - Parameter triggeredByShortcut: If true, shows toggle hint in overlay.
    private func performToggle(triggeredByShortcut: Bool = false) {
        // Cancel any pending delayed stop
        self.delayedStopTask?.cancel()
        self.delayedStopTask = nil

        self.config.enabled.toggle()
        self.enabledMenuItem?.state = self.config.enabled ? .on : .off
        self.updateStatusIcon()

        if self.config.enabled {
            self.overlayController?.start()
            // Show toggle hint when enabled via hotkey
            if triggeredByShortcut {
                self.overlayController?.showToggleHint(isEnabled: true)
            }
        } else {
            if triggeredByShortcut {
                // Stop monitoring immediately, show "Off" hint, then fully stop after delay
                self.overlayController?.stopMonitoring()
                self.overlayController?.showToggleHint(isEnabled: false)
                self.delayedStopTask = Task {
                    try? await Task.sleep(for: .seconds(2.0))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self.overlayController?.stop()
                    }
                }
            } else {
                self.overlayController?.stop()
            }
        }
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        self.performToggle()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showSettings()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
