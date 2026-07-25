import AppKit
import Foundation
import IOKit.hid
import os.log

private let logger = Logger(subsystem: "dev.keypress.app", category: "InputMonitoringPermission")

/// Manages Input Monitoring permission state with live updates.
/// Input Monitoring (not Accessibility) is what NSEvent global monitors
/// require since macOS 10.15, and it is available to sandboxed apps.
@MainActor
public final class InputMonitoringPermission {
    // MARK: - Singleton

    public static let shared = InputMonitoringPermission()

    // MARK: - Types

    public typealias PermissionChangeHandler = @MainActor @Sendable (Bool) -> Void

    // MARK: - Properties

    private var pollingTask: Task<Void, Never>?
    private var changeHandler: PermissionChangeHandler?
    private var lastKnownState: Bool = false

    /// Current permission state (may be cached, use check() for fresh value).
    public private(set) var isGranted: Bool = false

    // MARK: - Initialization

    private init() {
        self.isGranted = Self.check()
        self.lastKnownState = self.isGranted
        logger.info("Init: IOHIDCheckAccess=\(self.isGranted)")
    }

    // Note: No deinit cleanup needed - this is a singleton that lives for app lifetime.

    // MARK: - Public Methods

    /// Checks if Input Monitoring permission is granted (fresh check, not cached).
    public static func check() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Requests Input Monitoring permission, showing the system prompt if not already granted.
    /// Returns true if already granted.
    @discardableResult
    public static func request() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// Opens System Settings > Privacy & Security > Input Monitoring.
    public static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Sets handler to be called when permission state changes.
    public func onPermissionChange(_ handler: @escaping PermissionChangeHandler) {
        self.changeHandler = handler
    }

    /// Starts polling for permission changes.
    /// Polls every 500ms until granted, then stops.
    public func startPolling() {
        guard self.pollingTask == nil else { return }
        print("[InputMonitoringPermission] Starting polling...")

        self.pollingTask = Task { [weak self] in
            var pollCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))

                guard let self else { return }

                pollCount += 1
                let granted = Self.check()

                // Log every 10th poll or when state changes
                if pollCount % 10 == 0 {
                    print("[InputMonitoringPermission] Poll #\(pollCount): granted=\(granted)")
                }

                if granted != self.lastKnownState {
                    print("[InputMonitoringPermission] Permission changed! granted=\(granted)")
                    self.lastKnownState = granted
                    self.isGranted = granted
                    self.changeHandler?(granted)

                    // Stop polling once granted
                    if granted {
                        print("[InputMonitoringPermission] Granted, stopping polling")
                        return
                    }
                }
            }
        }
    }

    /// Stops polling for permission changes.
    public func stopPolling() {
        self.pollingTask?.cancel()
        self.pollingTask = nil
    }
}
