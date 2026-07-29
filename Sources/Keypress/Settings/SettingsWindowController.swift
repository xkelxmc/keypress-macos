import AppKit
import KeypressCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let navigation = SettingsNavigationState()

    private init() {}

    func showSettings(destination: SettingsDestination? = nil) {
        let progress = OnboardingProgressStore.shared
        progress.reconcileReadyState(
            config: KeypressConfig.shared,
            onboardingIsPresenting: OnboardingController.shared.isPresenting)
        if let destination {
            self.navigation.selectedDestination = destination
        } else if progress.deferred, progress.needsSetup(config: KeypressConfig.shared) {
            self.navigation.selectedDestination = .setup
        }

        if let window = self.window {
            self.updateWindowAccessibility()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            config: KeypressConfig.shared,
            navigation: self.navigation)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.title = ""
        window.toolbar = nil
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 980, height: 720))
        window.minSize = NSSize(width: 820, height: 620)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("KeypressSettingsWindow")

        self.window = window
        self.updateWindowAccessibility()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func updateWindowTitle() {
        self.updateWindowAccessibility()
    }

    func closeSettings() {
        self.window?.close()
    }

    private var localizedWindowTitle: String {
        let languageCode = KeypressConfig.shared.general.language.studioLanguageCode
        return StudioStrings(languageCode: languageCode)["window.settings.title"]
    }

    private func updateWindowAccessibility() {
        self.window?.title = ""
        self.window?.setAccessibilityLabel(self.localizedWindowTitle)
    }
}
