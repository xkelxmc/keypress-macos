import AppKit
import KeyboardShortcuts
import KeypressCore
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum EnabledChangeSource {
        case launch
        case menu
        case shortcut
        case settings
    }

    private var statusItem: NSStatusItem?
    private var overlayController: OverlayController?
    private var enabledMenuItem: NSMenuItem?
    private var startupTask: Task<Void, Never>?
    private var delayedStopTask: Task<Void, Never>?
    private var appliedEnabledState: Bool?
    private var lastObservedEnabled: Bool?
    private var lastObservedLanguage: AppLanguage?

    private var config: KeypressConfig {
        KeypressConfig.shared
    }

    private var strings: StudioStrings {
        StudioStrings(languageCode: self.config.general.language.studioLanguageCode)
    }

    /// App version from bundle (e.g., "0.1.0").
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.setupStatusItem()
        self.setupOverlay()
        self.setupGlobalShortcuts()
        self.startObservingConfig()
    }

    func applicationWillTerminate(_ notification: Notification) {
        self.startupTask?.cancel()
        self.delayedStopTask?.cancel()
        self.overlayController?.stop()
        self.config.flushPersistence()
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

        let symbolName = self.config.general.enabled ? "keyboard.fill" : "keyboard"
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Keypress")
    }

    private func setupMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Keypress v\(self.appVersion)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let enabledItem = NSMenuItem(
            title: self.strings["menu.enabled"],
            action: #selector(self.toggleEnabled),
            keyEquivalent: "")
        enabledItem.state = self.config.general.enabled ? .on : .off
        self.enabledMenuItem = enabledItem
        menu.addItem(enabledItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: self.strings["menu.settings"],
            action: #selector(self.openSettings),
            keyEquivalent: ","))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: self.strings["menu.quit"],
            action: #selector(self.quit),
            keyEquivalent: "q"))

        menu.delegate = self
        self.statusItem?.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        self.enabledMenuItem?.state = self.config.general.enabled ? .on : .off
        self.updateEnabledMenuItemTitle()
    }

    private func updateEnabledMenuItemTitle() {
        guard let item = self.enabledMenuItem else { return }

        if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleOverlay) {
            item.title = "\(self.strings["menu.enabled"]) (\(shortcut.displayString))"
        } else {
            item.title = self.strings["menu.enabled"]
        }
    }

    private func setupOverlay() {
        self.overlayController = OverlayController(config: self.config)
        self.applyEnabledState(source: .launch)
    }

    private func setupGlobalShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .toggleOverlay) { [weak self] in
            Task { @MainActor [weak self] in
                self?.performToggle(source: .shortcut)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .togglePointer) { [weak self] in
            Task { @MainActor [weak self] in
                self?.togglePointer()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .switchContentMode) { [weak self] in
            Task { @MainActor [weak self] in
                self?.switchContentMode()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .editPosition) { [weak self] in
            Task { @MainActor [weak self] in
                self?.overlayController?.openPositionEditor()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .increaseOverlaySize) { [weak self] in
            Task { @MainActor [weak self] in
                self?.changeOverlaySize(by: 1, shortcut: .increaseOverlaySize)
            }
        }

        KeyboardShortcuts.onKeyUp(for: .decreaseOverlaySize) { [weak self] in
            Task { @MainActor [weak self] in
                self?.changeOverlaySize(by: -1, shortcut: .decreaseOverlaySize)
            }
        }
    }

    private func startObservingConfig() {
        self.lastObservedEnabled = self.config.general.enabled
        self.lastObservedLanguage = self.config.general.language
        self.observeNextConfigChange()
    }

    private func observeNextConfigChange() {
        withObservationTracking {
            _ = self.config.general.enabled
            _ = self.config.general.language
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.applyObservedConfigChanges()
            }
        }
    }

    private func applyObservedConfigChanges() {
        let enabled = self.config.general.enabled
        let language = self.config.general.language
        let enabledChanged = self.lastObservedEnabled != enabled
        let languageChanged = self.lastObservedLanguage != language
        self.lastObservedEnabled = enabled
        self.lastObservedLanguage = language
        self.observeNextConfigChange()

        if languageChanged {
            self.setupMenu()
            SettingsWindowController.shared.updateWindowTitle()
        }
        if enabledChanged {
            self.applyEnabledState(source: .settings)
        }
    }

    private func applyEnabledState(source: EnabledChangeSource) {
        let isEnabled = self.config.general.enabled
        self.enabledMenuItem?.state = isEnabled ? .on : .off
        self.updateStatusIcon()

        guard self.appliedEnabledState != isEnabled else { return }
        self.appliedEnabledState = isEnabled
        self.startupTask?.cancel()
        self.startupTask = nil
        self.delayedStopTask?.cancel()
        self.delayedStopTask = nil

        if isEnabled {
            if source == .launch {
                self.startupTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    self?.overlayController?.start()
                }
            } else {
                self.overlayController?.start()
            }

            if source == .shortcut {
                self.showHUD(
                    key: "hud.keypress.on",
                    shortcut: .toggleOverlay,
                    kind: .positive)
            }
            return
        }

        guard source == .shortcut else {
            self.overlayController?.stop()
            return
        }

        self.overlayController?.stopMonitoring()
        self.showHUD(
            key: "hud.keypress.off",
            shortcut: .toggleOverlay,
            kind: .negative)
        self.delayedStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.overlayController?.stop()
        }
    }

    // MARK: - Actions

    private func performToggle(source: EnabledChangeSource) {
        self.config.general.enabled.toggle()
        self.applyEnabledState(source: source)
    }

    private func togglePointer() {
        self.config.pointer.enabled.toggle()
        self.overlayController?.refreshPointer()
        self.showHUD(
            key: self.config.pointer.enabled ? "hud.pointer.on" : "hud.pointer.off",
            shortcut: .togglePointer,
            kind: self.config.pointer.enabled ? .positive : .negative)
    }

    private func switchContentMode() {
        self.config.keyboard.contentMode = switch self.config.keyboard.contentMode {
        case .allKeys: .shortcutsOnly
        case .shortcutsOnly: .allKeys
        }

        self.showHUD(
            key: self.config.keyboard.contentMode == .allKeys
                ? "hud.content.all"
                : "hud.content.shortcuts",
            shortcut: .switchContentMode,
            kind: .mode)
    }

    private func changeOverlaySize(by offset: Int, shortcut: KeyboardShortcuts.Name) {
        let sizes = OverlaySize.allCases
        guard let currentIndex = sizes.firstIndex(of: self.config.keyboard.size) else { return }
        let nextIndex = min(max(currentIndex + offset, sizes.startIndex), sizes.index(before: sizes.endIndex))
        let size = sizes[nextIndex]
        self.config.keyboard.size = size

        let localizedSize = self.strings["size.\(size.rawValue)"]
        let text = String(
            format: self.strings["hud.size"],
            locale: self.strings.locale,
            localizedSize)
        self.overlayController?.showHUD(
            text: text,
            shortcut: KeyboardShortcuts.getShortcut(for: shortcut)?.displayString,
            kind: .mode)
    }

    private func showHUD(
        key: String,
        shortcut: KeyboardShortcuts.Name,
        kind: HUDKind)
    {
        self.overlayController?.showHUD(
            text: self.strings[key],
            shortcut: KeyboardShortcuts.getShortcut(for: shortcut)?.displayString,
            kind: kind)
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        self.performToggle(source: .menu)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showSettings()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
