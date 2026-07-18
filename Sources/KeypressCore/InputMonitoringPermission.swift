import AppKit
@preconcurrency import ApplicationServices
import Foundation
import IOKit.hid
import os.log

private let logger = Logger(subsystem: "dev.keypress.app", category: "InputMonitoringPermission")

/// Manages Input Monitoring permission state with live updates.
/// Input Monitoring (not Accessibility) is what a listen-only CGEvent tap
/// requires since macOS 10.15, and it is available to sandboxed apps.
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
        logger.info("Init: IOHIDCheckAccess=\(self.isGranted), functionalTest=\(Self.functionalTest())")
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
                let functional = Self.functionalTest()

                // Log every 10th poll or when state changes
                if pollCount % 10 == 0 {
                    print("[InputMonitoringPermission] Poll #\(pollCount): granted=\(granted), func=\(functional)")
                }

                // Use functional test as the source of truth
                if functional != self.lastKnownState {
                    print("[InputMonitoringPermission] Permission changed! functional=\(functional)")
                    self.lastKnownState = functional
                    self.isGranted = functional
                    self.changeHandler?(functional)

                    // Stop polling once granted
                    if functional {
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

    /// Performs a functional test by attempting to create an event tap.
    /// This is more reliable than IOHIDCheckAccess() in some edge cases.
    public static func functionalTest() -> Bool {
        let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil)
        else {
            return false
        }

        // Immediately disable and release the tap
        CGEvent.tapEnable(tap: tap, enable: false)
        return true
    }
}
