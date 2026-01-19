import AppKit
@preconcurrency import ApplicationServices
import Foundation
import os.log

private let logger = Logger(subsystem: "dev.keypress.app", category: "AccessibilityPermission")

/// Manages Accessibility permission state with live updates.
/// Uses DistributedNotificationCenter to detect permission changes without app restart.
@MainActor
public final class AccessibilityPermission {
    // MARK: - Singleton

    public static let shared = AccessibilityPermission()

    // MARK: - Types

    public typealias PermissionChangeHandler = @MainActor @Sendable (Bool) -> Void

    // MARK: - Properties

    private var notificationObserver: NSObjectProtocol?
    private var pollingTask: Task<Void, Never>?
    private var changeHandler: PermissionChangeHandler?
    private var lastKnownState: Bool = false

    /// Current permission state (may be cached, use check() for fresh value).
    public private(set) var isGranted: Bool = false

    // MARK: - Initialization

    private init() {
        self.isGranted = Self.check()
        self.lastKnownState = self.isGranted
        logger.info("Init: AXIsProcessTrusted=\(self.isGranted), functionalTest=\(Self.functionalTest())")
        self.setupNotificationObserver()
    }

    // Note: No deinit cleanup needed - this is a singleton that lives for app lifetime.
    // Observer and task will be cleaned up when app terminates.

    // MARK: - Public Methods

    /// Checks if accessibility permission is granted (fresh check, not cached).
    public static func check() -> Bool {
        AXIsProcessTrusted()
    }

    /// Requests accessibility permission, showing system prompt if not already granted.
    /// Returns true if already granted, false if prompt was shown.
    @discardableResult
    public static func request() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings > Privacy & Security > Accessibility.
    public static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Sets handler to be called when permission state changes.
    public func onPermissionChange(_ handler: @escaping PermissionChangeHandler) {
        self.changeHandler = handler
    }

    /// Starts polling for permission changes (fallback if notifications don't work).
    /// Polls every 500ms until granted, then stops.
    public func startPolling() {
        guard self.pollingTask == nil else { return }
        print("[AccessibilityPermission] Starting polling...")

        self.pollingTask = Task { [weak self] in
            var pollCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))

                guard let self else { return }

                pollCount += 1
                let axTrusted = Self.check()
                let functional = Self.functionalTest()

                // Log every 10th poll or when state changes
                if pollCount % 10 == 0 {
                    print("[AccessibilityPermission] Poll #\(pollCount): AX=\(axTrusted), func=\(functional)")
                }

                // Use functional test as the source of truth
                if functional != self.lastKnownState {
                    print("[AccessibilityPermission] Permission changed! functional=\(functional)")
                    self.lastKnownState = functional
                    self.isGranted = functional
                    self.changeHandler?(functional)

                    // Stop polling once granted
                    if functional {
                        print("[AccessibilityPermission] Granted, stopping polling")
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
    /// This is more reliable than AXIsProcessTrusted() in some edge cases.
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

    // MARK: - Private Methods

    private func setupNotificationObserver() {
        // Listen for accessibility permission changes via distributed notification.
        // This fires when any app's accessibility permissions change in System Settings.
        self.notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: nil)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                // Important: Add delay before checking.
                // The notification fires before the TCC database is fully updated.
                try? await Task.sleep(for: .milliseconds(250))

                guard let self else { return }
                self.refreshPermissionState()
            }
        }
    }

    private func refreshPermissionState() {
        let currentState = Self.check()
        if currentState != self.lastKnownState {
            self.lastKnownState = currentState
            self.isGranted = currentState
            self.changeHandler?(currentState)

            // Stop polling if granted
            if currentState {
                self.stopPolling()
            }
        }
    }
}
