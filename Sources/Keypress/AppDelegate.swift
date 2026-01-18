import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.setupStatusItem()
    }

    private func setupStatusItem() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = self.statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "keyboard",
                accessibilityDescription: "Keypress")
        }

        self.setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Keypress v0.1.0", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let enabledItem = NSMenuItem(
            title: "Enabled",
            action: #selector(self.toggleEnabled),
            keyEquivalent: "")
        enabledItem.state = .on
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

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        sender.state = sender.state == .on ? .off : .on
    }

    @objc private func openSettings() {
        // TODO: Open settings window
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
