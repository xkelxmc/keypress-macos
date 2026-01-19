import AppKit
import KeyboardShortcuts
import KeypressCore
import Observation

/// Manages the overlay window lifecycle and key monitoring.
@MainActor
final class OverlayController {
    // MARK: - Properties

    private let config: KeypressConfig
    private let permission = AccessibilityPermission.shared
    private var keyMonitor: KeyMonitor?
    private var overlayWindow: OverlayWindow?
    private var observationTask: Task<Void, Never>?

    // Key state (one of these will be used based on display mode)
    private var historyKeyState: KeyState?
    private var singleKeyState: SingleKeyState?

    // Hint state (independent of key state)
    private let hintState = HintState()

    // Screen observers
    private var screenParametersObserver: Any?
    private var workspaceObserver: Any?

    /// Current key state protocol reference for common operations.
    private var currentKeyState: (any KeyStateProtocol)? {
        switch self.config.displayMode {
        case .single: self.singleKeyState
        case .history: self.historyKeyState
        }
    }

    var isRunning: Bool {
        self.keyMonitor?.isRunning ?? false
    }

    // MARK: - Initialization

    init(config: KeypressConfig = .shared) {
        self.config = config
    }

    deinit {
        self.observationTask?.cancel()
        // Note: stopObservingScreens() would require @MainActor, but deinit can't be async
        // The observers will be cleaned up automatically when the object is deallocated
    }

    // MARK: - Public Methods

    /// Starts key monitoring and shows overlay when keys are pressed.
    func start() {
        guard self.keyMonitor == nil else { return }

        // Clean up any existing overlay window (e.g., from delayed stop)
        self.overlayWindow?.hideOverlay()
        self.overlayWindow = nil
        self.hintState.hide()

        // Create appropriate key state based on display mode
        self.createKeyState()

        // Create overlay window based on display mode
        switch self.config.displayMode {
        case .single:
            self.overlayWindow = OverlayWindow(
                singleKeyState: self.singleKeyState!,
                hintState: self.hintState,
                config: self.config
            )
        case .history:
            self.overlayWindow = OverlayWindow(
                keyState: self.historyKeyState!,
                hintState: self.hintState,
                config: self.config
            )
        }

        // Create key monitor with callback
        self.keyMonitor = KeyMonitor { [weak self] event, symbol in
            Task { @MainActor [weak self] in
                self?.currentKeyState?.processEvent(event, symbol: symbol)
            }
        }

        // Start observing screen changes
        self.startObservingScreens()

        // Try to start monitoring directly - KeyMonitor.start() returns false if no permissions
        if self.keyMonitor?.start() == true {
            print("[Keypress] KeyMonitor started successfully")
            // Sync with currently held modifiers
            self.keyMonitor?.emitCurrentModifiers()
            self.startObservingKeyState()
        } else {
            print("[Keypress] KeyMonitor.start() failed, requesting permissions...")

            // Request permission (shows system dialog if app not in list)
            AccessibilityPermission.request()

            // Subscribe to permission changes
            self.permission.onPermissionChange { [weak self] granted in
                print("[Keypress] Permission changed: \(granted)")
                if granted {
                    self?.startMonitoring()
                }
            }

            // Start polling as fallback
            self.permission.startPolling()
        }
    }

    /// Stops key monitoring and hides overlay.
    func stop() {
        self.observationTask?.cancel()
        self.observationTask = nil

        self.stopObservingScreens()

        self.keyMonitor?.stop()
        self.keyMonitor = nil

        self.overlayWindow?.hideOverlay()
        self.overlayWindow = nil

        self.currentKeyState?.clear()
        self.historyKeyState = nil
        self.singleKeyState = nil

        self.hintState.hide()
    }

    /// Stops key monitoring and clears keys, but keeps overlay window for hint.
    /// Call stop() later to fully clean up.
    func stopMonitoring() {
        self.keyMonitor?.stop()
        self.keyMonitor = nil
        self.currentKeyState?.clear()
    }

    /// Updates overlay position based on current settings.
    func updatePosition() {
        self.overlayWindow?.updatePosition(on: self.selectedScreen())
    }

    /// Returns the screen to display the overlay on based on current settings.
    private func selectedScreen() -> NSScreen? {
        switch self.config.monitorSelection {
        case .auto:
            // Get screen of the frontmost application's key window
            return self.screenOfFrontmostApp() ?? NSScreen.main
        case .fixed(let index):
            let screens = NSScreen.screens
            // Fallback to main screen if index is out of bounds (monitor disconnected)
            return index < screens.count ? screens[index] : NSScreen.main
        }
    }

    /// Returns the screen that contains the frontmost application's key window.
    private func screenOfFrontmostApp() -> NSScreen? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        // Try to get the key window's screen using Accessibility API
        let pid = frontmostApp.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else {
            return nil
        }

        // Get window position
        var positionRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, &positionRef) == .success,
              let positionValue = positionRef else {
            return nil
        }

        var position = CGPoint.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position) else {
            return nil
        }

        // Find the screen that contains this position
        for screen in NSScreen.screens {
            if screen.frame.contains(position) {
                return screen
            }
        }

        return nil
    }

    /// Updates overlay opacity based on current settings.
    func updateOpacity() {
        self.overlayWindow?.alphaValue = self.config.opacity
    }

    /// Updates key timeout based on current settings.
    func updateKeyTimeout() {
        self.historyKeyState?.keyTimeout = self.config.keyTimeout
        self.singleKeyState?.keyTimeout = self.config.keyTimeout
    }

    /// Updates history mode settings.
    func updateHistorySettings() {
        self.historyKeyState?.maxDisplayedKeys = self.config.maxKeys
        self.historyKeyState?.duplicateLetters = self.config.duplicateLetters
        self.historyKeyState?.limitIncludesModifiers = self.config.limitIncludesModifiers
    }

    /// Updates single mode settings.
    func updateSingleSettings() {
        self.singleKeyState?.showModifiersOnly = self.config.showModifiersOnly
    }

    /// Shows toggle hint with the current state and shortcut text.
    func showToggleHint(isEnabled: Bool) {
        let shortcutText = KeyboardShortcuts.getShortcut(for: .toggleOverlay)?.displayString ?? ""
        self.hintState.show(isEnabled: isEnabled, shortcutText: shortcutText)
    }

    // MARK: - Private Methods

    private func createKeyState() {
        switch self.config.displayMode {
        case .single:
            let state = SingleKeyState()
            state.keyTimeout = self.config.keyTimeout
            state.showModifiersOnly = self.config.showModifiersOnly
            self.singleKeyState = state
        case .history:
            let state = KeyState()
            state.keyTimeout = self.config.keyTimeout
            state.maxDisplayedKeys = self.config.maxKeys
            state.duplicateLetters = self.config.duplicateLetters
            state.limitIncludesModifiers = self.config.limitIncludesModifiers
            self.historyKeyState = state
        }
    }

    private func startMonitoring() {
        let started = self.keyMonitor?.start() ?? false
        print("[Keypress] KeyMonitor.start() returned: \(started)")
        if started {
            self.startObservingKeyState()
        }
    }

    private func startObservingKeyState() {
        self.observationTask = Task { [weak self] in
            guard let self = self else { return }

            var wasVisible = false

            while !Task.isCancelled {
                let hasKeys = self.currentKeyState?.hasKeys ?? false
                let hasHint = self.hintState.currentHint != nil
                let shouldBeVisible = hasKeys || hasHint

                if shouldBeVisible != wasVisible {
                    if shouldBeVisible {
                        self.overlayWindow?.showOverlay()
                    } else {
                        self.overlayWindow?.hideOverlay()
                    }
                    wasVisible = shouldBeVisible
                }

                try? await Task.sleep(for: .milliseconds(16)) // ~60fps check
            }
        }

        // Observe config changes
        self.startObservingConfig()
    }

    private func startObservingConfig() {
        // Track last known values to detect changes
        var lastPosition = self.config.position
        var lastOpacity = self.config.opacity
        var lastSize = self.config.size
        var lastKeyTimeout = self.config.keyTimeout
        var lastMaxKeys = self.config.maxKeys
        var lastDuplicateLetters = self.config.duplicateLetters
        var lastLimitIncludesModifiers = self.config.limitIncludesModifiers
        var lastShowModifiersOnly = self.config.showModifiersOnly
        var lastDisplayMode = self.config.displayMode
        var lastMonitorSelection = self.config.monitorSelection

        Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }

                // Check for position change
                if self.config.position != lastPosition {
                    lastPosition = self.config.position
                    self.updatePosition()
                }

                // Check for monitor selection change
                if self.config.monitorSelection != lastMonitorSelection {
                    lastMonitorSelection = self.config.monitorSelection
                    self.updatePosition()
                }

                // Check for opacity change
                if self.config.opacity != lastOpacity {
                    lastOpacity = self.config.opacity
                    self.overlayWindow?.alphaValue = self.config.opacity
                }

                // Check for size change
                if self.config.size != lastSize {
                    lastSize = self.config.size
                    // Size requires overlay recreation (handled by SwiftUI binding)
                }

                // Check for timeout change
                if self.config.keyTimeout != lastKeyTimeout {
                    lastKeyTimeout = self.config.keyTimeout
                    self.updateKeyTimeout()
                }

                // Check for history mode settings
                if self.config.maxKeys != lastMaxKeys {
                    lastMaxKeys = self.config.maxKeys
                    self.updateHistorySettings()
                }
                if self.config.duplicateLetters != lastDuplicateLetters {
                    lastDuplicateLetters = self.config.duplicateLetters
                    self.updateHistorySettings()
                }
                if self.config.limitIncludesModifiers != lastLimitIncludesModifiers {
                    lastLimitIncludesModifiers = self.config.limitIncludesModifiers
                    self.updateHistorySettings()
                }

                // Check for single mode settings
                if self.config.showModifiersOnly != lastShowModifiersOnly {
                    lastShowModifiersOnly = self.config.showModifiersOnly
                    self.updateSingleSettings()
                }

                // Check for display mode change (requires restart)
                if self.config.displayMode != lastDisplayMode {
                    lastDisplayMode = self.config.displayMode
                    self.recreateForDisplayMode()
                }

                try? await Task.sleep(for: .milliseconds(100)) // Check 10x per second
            }
        }
    }

    private func recreateForDisplayMode() {
        // Save running state
        let wasRunning = self.isRunning

        // Stop and restart with new mode
        self.stop()

        if wasRunning {
            self.start()
        }
    }

    // MARK: - Screen Observation

    private func startObservingScreens() {
        // Observe screen parameter changes (monitor connect/disconnect)
        self.screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreensChanged()
            }
        }

        // Observe active app changes (for Auto mode)
        self.workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Only update position if in Auto mode
                if case .auto = self.config.monitorSelection {
                    self.updatePosition()
                }
            }
        }
    }

    private func stopObservingScreens() {
        if let observer = self.screenParametersObserver {
            NotificationCenter.default.removeObserver(observer)
            self.screenParametersObserver = nil
        }
        if let observer = self.workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.workspaceObserver = nil
        }
    }

    private func handleScreensChanged() {
        // Validate current selection
        if case .fixed(let index) = self.config.monitorSelection {
            if index >= NSScreen.screens.count {
                // Selected monitor was disconnected, reset to auto
                self.config.monitorSelection = .auto
            }
        }
        // Update position for the new screen configuration
        self.updatePosition()
    }
}
