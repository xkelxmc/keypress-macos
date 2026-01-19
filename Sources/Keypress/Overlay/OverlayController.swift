import AppKit
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
    }

    // MARK: - Public Methods

    /// Starts key monitoring and shows overlay when keys are pressed.
    func start() {
        guard self.keyMonitor == nil else { return }

        // Create appropriate key state based on display mode
        self.createKeyState()

        // Create overlay window based on display mode
        switch self.config.displayMode {
        case .single:
            self.overlayWindow = OverlayWindow(singleKeyState: self.singleKeyState!, config: self.config)
        case .history:
            self.overlayWindow = OverlayWindow(keyState: self.historyKeyState!, config: self.config)
        }

        // Create key monitor with callback
        self.keyMonitor = KeyMonitor { [weak self] event, symbol in
            Task { @MainActor [weak self] in
                self?.currentKeyState?.processEvent(event, symbol: symbol)
            }
        }

        // Try to start monitoring directly - KeyMonitor.start() returns false if no permissions
        if self.keyMonitor?.start() == true {
            print("[Keypress] KeyMonitor started successfully")
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

        self.keyMonitor?.stop()
        self.keyMonitor = nil

        self.overlayWindow?.hideOverlay()
        self.overlayWindow = nil

        self.currentKeyState?.clear()
        self.historyKeyState = nil
        self.singleKeyState = nil
    }

    /// Updates overlay position based on current settings.
    func updatePosition() {
        self.overlayWindow?.updatePosition()
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
    }

    /// Updates single mode settings.
    func updateSingleSettings() {
        self.singleKeyState?.showModifiersOnly = self.config.showModifiersOnly
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

                if hasKeys != wasVisible {
                    if hasKeys {
                        self.overlayWindow?.showOverlay()
                    } else {
                        self.overlayWindow?.hideOverlay()
                    }
                    wasVisible = hasKeys
                }

                try? await Task.sleep(for: .milliseconds(16)) // ~60fps check
            }
        }
    }
}
