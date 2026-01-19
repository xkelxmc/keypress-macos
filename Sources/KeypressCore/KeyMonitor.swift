@preconcurrency import ApplicationServices
import Carbon.HIToolbox
@preconcurrency import CoreFoundation
import Foundation

// MARK: - KeyEvent

/// Represents a keyboard event captured by KeyMonitor.
public struct KeyEvent: Sendable, Equatable {
    public enum EventType: Sendable {
        case keyDown
        case keyUp
        case flagsChanged
    }

    public let type: EventType
    public let keyCode: Int64
    public let modifiers: CGEventFlags
    public let timestamp: Date

    public init(type: EventType, keyCode: Int64, modifiers: CGEventFlags, timestamp: Date = Date()) {
        self.type = type
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.timestamp = timestamp
    }
}

// MARK: - KeySymbol

/// Displayable representation of a key.
public struct KeySymbol: Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let display: String
    public let isModifier: Bool
    /// Special keys (backspace, space, arrows, etc.) — shown with modifiers, no duplicates, but use timeout
    public let isSpecial: Bool

    public init(id: String, display: String, isModifier: Bool = false, isSpecial: Bool = false) {
        self.id = id
        self.display = display
        self.isModifier = isModifier
        self.isSpecial = isSpecial
    }
}

// MARK: - KeyMonitor

/// Monitors global keyboard events using CGEvent tap.
/// Requires Accessibility permissions.
public final class KeyMonitor: @unchecked Sendable {
    // MARK: - Types

    public typealias EventHandler = @Sendable (KeyEvent, KeySymbol?) -> Void

    // MARK: - Properties

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var monitorThread: Thread?
    private let eventHandler: EventHandler
    private let lock = NSLock()

    private var _isRunning = false
    public var isRunning: Bool {
        self.lock.withLock { self._isRunning }
    }

    // MARK: - Initialization

    public init(eventHandler: @escaping EventHandler) {
        self.eventHandler = eventHandler
    }

    deinit {
        self.stop()
    }

    // MARK: - Public Methods

    /// Checks if the app has Accessibility permissions.
    public static func hasAccessibilityPermissions() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompts user to grant Accessibility permissions.
    /// Returns true if already granted, false if prompt was shown.
    @discardableResult
    public static func requestAccessibilityPermissions() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Starts monitoring keyboard events.
    /// Returns false if permissions are not granted or tap creation fails.
    @discardableResult
    public func start() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }

        guard !self._isRunning else { return true }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: Self.eventCallback,
            userInfo: refcon
        ) else {
            return false
        }

        self.eventTap = tap

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            self.eventTap = nil
            return false
        }

        self.runLoopSource = source
        self._isRunning = true

        let thread = Thread { [weak self] in
            guard let self = self else { return }

            let runLoop = CFRunLoopGetCurrent()
            self.lock.withLock {
                self.runLoop = runLoop
            }

            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            CFRunLoopRun()

            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }

        thread.name = "KeyMonitor"
        thread.qualityOfService = .userInteractive
        self.monitorThread = thread
        thread.start()

        return true
    }

    /// Stops monitoring keyboard events.
    public func stop() {
        self.lock.lock()

        guard self._isRunning else {
            self.lock.unlock()
            return
        }

        self._isRunning = false

        if let tap = self.eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let runLoop = self.runLoop {
            CFRunLoopStop(runLoop)
        }

        self.lock.unlock()

        self.monitorThread = nil
        self.eventTap = nil
        self.runLoopSource = nil
        self.runLoop = nil
    }

    // MARK: - Event Callback

    private static let eventCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon = refcon else { return Unmanaged.passUnretained(event) }

        let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

        // Handle tap disabled event
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let modifiers = event.flags

        let eventType: KeyEvent.EventType
        switch type {
        case .keyDown:
            eventType = .keyDown
        case .keyUp:
            eventType = .keyUp
        case .flagsChanged:
            eventType = .flagsChanged
        default:
            return Unmanaged.passUnretained(event)
        }

        let keyEvent = KeyEvent(
            type: eventType,
            keyCode: keyCode,
            modifiers: modifiers
        )

        // Get symbol with current keyboard layout support
        let symbol = KeyCodeMapper.symbol(for: keyCode, modifiers: modifiers, event: event)
        monitor.eventHandler(keyEvent, symbol)

        return Unmanaged.passUnretained(event)
    }
}

// MARK: - KeyCodeMapper

/// Maps macOS keycodes to displayable symbols.
public enum KeyCodeMapper {
    // MARK: - Modifier Keys

    private static let modifierKeys: [Int64: KeySymbol] = [
        // Left modifiers
        0x38: KeySymbol(id: "shift-left", display: "⇧", isModifier: true),
        0x3B: KeySymbol(id: "control-left", display: "⌃", isModifier: true),
        0x3A: KeySymbol(id: "option-left", display: "⌥", isModifier: true),
        0x37: KeySymbol(id: "command-left", display: "⌘", isModifier: true),
        // Right modifiers
        0x3C: KeySymbol(id: "shift-right", display: "⇧", isModifier: true),
        0x3E: KeySymbol(id: "control-right", display: "⌃", isModifier: true),
        0x3D: KeySymbol(id: "option-right", display: "⌥", isModifier: true),
        0x36: KeySymbol(id: "command-right", display: "⌘", isModifier: true),
        // Function key
        0x3F: KeySymbol(id: "fn", display: "fn", isModifier: true),
        // Caps Lock
        0x39: KeySymbol(id: "capslock", display: "⇪", isModifier: true),
    ]

    // MARK: - Special Keys (shown with modifiers, no duplicates, timeout-based removal)

    private static let specialKeys: [Int64: KeySymbol] = [
        0x24: KeySymbol(id: "return", display: "⏎", isSpecial: true),
        0x30: KeySymbol(id: "tab", display: "⇥", isSpecial: true),
        0x31: KeySymbol(id: "space", display: "␣", isSpecial: true),
        0x33: KeySymbol(id: "delete", display: "⌫", isSpecial: true),
        0x35: KeySymbol(id: "escape", display: "⎋", isSpecial: true),
        0x4C: KeySymbol(id: "enter", display: "⌤", isSpecial: true),
        0x75: KeySymbol(id: "forward-delete", display: "⌦", isSpecial: true),

        // Arrow keys
        0x7B: KeySymbol(id: "arrow-left", display: "←", isSpecial: true),
        0x7C: KeySymbol(id: "arrow-right", display: "→", isSpecial: true),
        0x7D: KeySymbol(id: "arrow-down", display: "↓", isSpecial: true),
        0x7E: KeySymbol(id: "arrow-up", display: "↑", isSpecial: true),

        // Navigation
        0x73: KeySymbol(id: "home", display: "↖", isSpecial: true),
        0x77: KeySymbol(id: "end", display: "↘", isSpecial: true),
        0x74: KeySymbol(id: "page-up", display: "⇞", isSpecial: true),
        0x79: KeySymbol(id: "page-down", display: "⇟", isSpecial: true),

        // Function keys
        0x7A: KeySymbol(id: "f1", display: "F1", isSpecial: true),
        0x78: KeySymbol(id: "f2", display: "F2", isSpecial: true),
        0x63: KeySymbol(id: "f3", display: "F3", isSpecial: true),
        0x76: KeySymbol(id: "f4", display: "F4", isSpecial: true),
        0x60: KeySymbol(id: "f5", display: "F5", isSpecial: true),
        0x61: KeySymbol(id: "f6", display: "F6", isSpecial: true),
        0x62: KeySymbol(id: "f7", display: "F7", isSpecial: true),
        0x64: KeySymbol(id: "f8", display: "F8", isSpecial: true),
        0x65: KeySymbol(id: "f9", display: "F9", isSpecial: true),
        0x6D: KeySymbol(id: "f10", display: "F10", isSpecial: true),
        0x67: KeySymbol(id: "f11", display: "F11", isSpecial: true),
        0x6F: KeySymbol(id: "f12", display: "F12", isSpecial: true),
        0x69: KeySymbol(id: "f13", display: "F13", isSpecial: true),
        0x6B: KeySymbol(id: "f14", display: "F14", isSpecial: true),
        0x71: KeySymbol(id: "f15", display: "F15", isSpecial: true),
        0x6A: KeySymbol(id: "f16", display: "F16", isSpecial: true),
        0x40: KeySymbol(id: "f17", display: "F17", isSpecial: true),
        0x4F: KeySymbol(id: "f18", display: "F18", isSpecial: true),
        0x50: KeySymbol(id: "f19", display: "F19", isSpecial: true),
        0x5A: KeySymbol(id: "f20", display: "F20", isSpecial: true),
    ]

    // MARK: - Keycodes that produce characters (for layout detection)

    /// Keycodes that typically produce visible characters (letters, numbers, punctuation).
    private static let characterKeycodes: Set<Int64> = [
        // Letters
        0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26,
        0x28, 0x25, 0x2E, 0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11,
        0x20, 0x09, 0x0D, 0x07, 0x10, 0x06,
        // Numbers
        0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D,
        // Punctuation
        0x1E, 0x21, 0x27, 0x29, 0x2A, 0x2B, 0x2C, 0x2F, 0x32,
        // Numpad
        0x41, 0x43, 0x45, 0x47, 0x4B, 0x4E, 0x51,
        0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C,
    ]

    // MARK: - Public Methods

    /// Returns the symbol for a given keycode, using CGEvent for accurate character representation.
    /// This method respects the current keyboard layout (e.g., Russian, German, etc.).
    public static func symbol(for keyCode: Int64, modifiers: CGEventFlags = [], event: CGEvent? = nil) -> KeySymbol? {
        // Check modifier keys first
        if let modifier = modifierKeys[keyCode] {
            return modifier
        }

        // Check special keys
        if let special = specialKeys[keyCode] {
            return special
        }

        // For character keys, try to get the actual character from CGEvent
        if characterKeycodes.contains(keyCode) {
            if let event = event, let character = Self.extractCharacter(from: event) {
                return KeySymbol(id: "key-\(keyCode)", display: character.uppercased())
            }
            // Fallback to keycode-based lookup if no event provided
            return KeySymbol(id: "key-\(keyCode)", display: "?")
        }

        return nil
    }


    /// Extracts the character from a CGEvent using the current keyboard layout.
    private static func extractCharacter(from event: CGEvent) -> String? {
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)

        guard length > 0 else { return nil }

        var buffer = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &buffer)

        let string = String(utf16CodeUnits: buffer, count: length)

        // Filter out control characters
        guard let firstChar = string.first, !firstChar.isNewline, firstChar.isLetter || firstChar.isNumber || firstChar.isPunctuation || firstChar.isSymbol else {
            return string.isEmpty ? nil : string
        }

        return string
    }

    /// Returns true if the keycode represents a modifier key.
    public static func isModifier(_ keyCode: Int64) -> Bool {
        modifierKeys[keyCode] != nil
    }

    /// Extracts active modifier symbols from event flags.
    public static func activeModifiers(from flags: CGEventFlags) -> [KeySymbol] {
        var modifiers: [KeySymbol] = []

        if flags.contains(.maskControl) {
            modifiers.append(KeySymbol(id: "control", display: "⌃", isModifier: true))
        }
        if flags.contains(.maskAlternate) {
            modifiers.append(KeySymbol(id: "option", display: "⌥", isModifier: true))
        }
        if flags.contains(.maskShift) {
            modifiers.append(KeySymbol(id: "shift", display: "⇧", isModifier: true))
        }
        if flags.contains(.maskCommand) {
            modifiers.append(KeySymbol(id: "command", display: "⌘", isModifier: true))
        }

        return modifiers
    }
}
