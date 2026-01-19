import AppKit
import KeypressCore
import Observation

/// Manages the overlay window lifecycle and key monitoring.
@MainActor
final class OverlayController {
    // MARK: - Properties

    private let config: KeypressConfig
    private let keyState: KeyState
    private let permission = AccessibilityPermission.shared
    private var keyMonitor: KeyMonitor?
    private var overlayWindow: OverlayWindow?
    private var observationTask: Task<Void, Never>?

    var isRunning: Bool {
        self.keyMonitor?.isRunning ?? false
    }

    // MARK: - Initialization

    init(config: KeypressConfig = .shared, keyState: KeyState = KeyState()) {
        self.config = config
        self.keyState = keyState
        self.keyState.keyTimeout = config.keyTimeout
    }

    deinit {
        self.observationTask?.cancel()
    }

    // MARK: - Public Methods

    /// Starts key monitoring and shows overlay when keys are pressed.
    func start() {
        guard self.keyMonitor == nil else { return }

        // Create overlay window
        self.overlayWindow = OverlayWindow(keyState: self.keyState, config: self.config)

        // Create key monitor with callback
        self.keyMonitor = KeyMonitor { [weak self] event, symbol in
            Task { @MainActor [weak self] in
                self?.keyState.processEvent(event, symbol: symbol)
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

        self.keyState.clear()
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
        self.keyState.keyTimeout = self.config.keyTimeout
    }

    // MARK: - Private Methods

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
                let hasKeys = self.keyState.hasKeys

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
