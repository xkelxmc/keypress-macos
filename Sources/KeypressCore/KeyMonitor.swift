import AppKit
import Foundation
import IOKit.hid

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
    public let modifiers: NSEvent.ModifierFlags
    public let timestamp: Date

    public init(type: EventType, keyCode: Int64, modifiers: NSEvent.ModifierFlags, timestamp: Date = Date()) {
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

/// Monitors keyboard events with NSEvent monitors, which report key presses
/// without ever touching the Accessibility framework.
/// Requires the Input Monitoring permission for events of other apps.
@MainActor
public final class KeyMonitor {
    // MARK: - Types

    public typealias EventHandler = (KeyEvent, KeySymbol?) -> Void

    // MARK: - Properties

    /// The global monitor covers every other app; the local one covers our own
    /// windows (Settings), which a global monitor never sees.
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let eventHandler: EventHandler

    private static let monitoredEvents: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]

    public private(set) var isRunning = false

    // MARK: - Initialization

    public init(eventHandler: @escaping EventHandler) {
        self.eventHandler = eventHandler
    }

    // MARK: - Public Methods

    /// Checks if the app has the Input Monitoring permission.
    public static func hasInputMonitoringPermission() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Prompts user to grant the Input Monitoring permission.
    /// Returns true if already granted.
    @discardableResult
    public static func requestInputMonitoringPermission() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    /// Returns current modifier flags from the system.
    public static func currentModifierFlags() -> NSEvent.ModifierFlags {
        NSEvent.modifierFlags
    }

    /// Emits flagsChanged events for currently pressed modifiers.
    /// Call this after start() to sync state with physically held keys.
    public func emitCurrentModifiers() {
        let flags = Self.currentModifierFlags()
        let modifierKeyCodes: [(Int64, NSEvent.ModifierFlags)] = [
            (0x37, .command), // Left Command
            (0x38, .shift), // Left Shift
            (0x3A, .option), // Left Option
            (0x3B, .control), // Left Control
        ]

        for (keyCode, mask) in modifierKeyCodes where flags.contains(mask) {
            let event = KeyEvent(type: .flagsChanged, keyCode: keyCode, modifiers: flags)
            if let symbol = KeyCodeMapper.symbol(for: keyCode, modifiers: flags) {
                self.eventHandler(event, symbol)
            }
        }
    }

    /// Starts monitoring keyboard events.
    /// Monitors are installed regardless of permission state; events of other
    /// apps only start flowing once Input Monitoring is granted.
    @discardableResult
    public func start() -> Bool {
        guard !self.isRunning else { return true }

        self.globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.monitoredEvents) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }

        self.localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.monitoredEvents) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
            return event
        }

        self.isRunning = self.globalMonitor != nil
        return self.isRunning
    }

    /// Stops monitoring keyboard events.
    public func stop() {
        if let globalMonitor = self.globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor = self.localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        self.isRunning = false
    }

    // MARK: - Event Handling

    private func handle(_ event: NSEvent) {
        let eventType: KeyEvent.EventType
        switch event.type {
        case .keyDown:
            eventType = .keyDown
        case .keyUp:
            eventType = .keyUp
        case .flagsChanged:
            eventType = .flagsChanged
        default:
            return
        }

        let keyCode = Int64(event.keyCode)
        let modifiers = event.modifierFlags

        // `characters` is only defined for key events; reading it on a
        // flagsChanged event raises.
        let character = eventType == .flagsChanged ? nil : event.characters

        let keyEvent = KeyEvent(type: eventType, keyCode: keyCode, modifiers: modifiers)
        let symbol = KeyCodeMapper.symbol(for: keyCode, modifiers: modifiers, character: character)
        self.eventHandler(keyEvent, symbol)
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
        // CapsLock excluded — macOS doesn't provide reliable press/release events
    ]

    // MARK: - Special Keys (shown with modifiers, no duplicates, timeout-based removal)

    private static let specialKeys: [Int64: KeySymbol] = [
        0x24: KeySymbol(id: "return", display: "⏎", isSpecial: true),
        0x30: KeySymbol(id: "tab", display: "⇥", isSpecial: true),
        0x31: KeySymbol(id: "space", display: "␣", isSpecial: true),
        0x33: KeySymbol(id: "delete", display: "⌫", isSpecial: true),
        0x35: KeySymbol(id: "escape", display: "ESC", isSpecial: true),
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

    /// Fallback US QWERTY mapping for when the event carries a control character (Ctrl pressed).
    private static let fallbackCharacters: [Int64: String] = [
        // Letters (US QWERTY)
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F",
        0x05: "G", 0x04: "H", 0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L",
        0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P", 0x0C: "Q", 0x0F: "R",
        0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
        0x10: "Y", 0x06: "Z",
        // Numbers
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "5",
        0x17: "6", 0x18: "7", 0x19: "8", 0x1A: "9", 0x1B: "0",
        0x1C: "-", 0x1D: "=",
        // Punctuation
        0x1E: "]", 0x21: "[", 0x27: "'", 0x29: ";", 0x2A: "\\",
        0x2B: ",", 0x2C: "/", 0x2F: ".", 0x32: "`",
        // Numpad
        0x41: ".", 0x43: "*", 0x45: "+", 0x47: "⌧", 0x4B: "/", 0x4E: "-",
        0x52: "0", 0x53: "1", 0x54: "2", 0x55: "3", 0x56: "4",
        0x57: "5", 0x58: "6", 0x59: "7", 0x5B: "8", 0x5C: "9",
    ]

    // MARK: - Public Methods

    /// Returns the symbol for a given keycode, using the event's character for accurate representation.
    /// This method respects the current keyboard layout (e.g., Russian, German, etc.).
    public static func symbol(
        for keyCode: Int64,
        modifiers: NSEvent.ModifierFlags = [],
        character: String? = nil) -> KeySymbol?
    {
        // Check modifier keys first
        if let modifier = modifierKeys[keyCode] {
            return modifier
        }

        // Check special keys
        if let special = specialKeys[keyCode] {
            return special
        }

        // For character keys, use the character the event carries
        if self.characterKeycodes.contains(keyCode) {
            if let character, let displayable = Self.displayableCharacter(character) {
                return KeySymbol(id: "key-\(keyCode)", display: displayable.uppercased())
            }
            // Fallback to US QWERTY when the event carries control chars (Ctrl pressed)
            if let fallback = fallbackCharacters[keyCode] {
                return KeySymbol(id: "key-\(keyCode)", display: fallback)
            }
            return KeySymbol(id: "key-\(keyCode)", display: "?")
        }

        return nil
    }

    /// Returns the character if it can be shown on a keycap.
    /// Returns nil for control characters (when Ctrl is pressed).
    private static func displayableCharacter(_ string: String) -> String? {
        guard !string.isEmpty else { return nil }

        // Filter out control characters (ASCII 0-31) - these occur when Ctrl is pressed
        guard let firstChar = string.unicodeScalars.first,
              firstChar.value >= 32,
              let char = string.first,
              char.isLetter || char.isNumber || char.isPunctuation || char.isSymbol || char.isWhitespace
        else {
            return nil
        }

        return string
    }

    /// Returns true if the keycode represents a modifier key.
    public static func isModifier(_ keyCode: Int64) -> Bool {
        self.modifierKeys[keyCode] != nil
    }

    /// Extracts active modifier symbols from event flags.
    public static func activeModifiers(from flags: NSEvent.ModifierFlags) -> [KeySymbol] {
        var modifiers: [KeySymbol] = []

        if flags.contains(.control) {
            modifiers.append(KeySymbol(id: "control", display: "⌃", isModifier: true))
        }
        if flags.contains(.option) {
            modifiers.append(KeySymbol(id: "option", display: "⌥", isModifier: true))
        }
        if flags.contains(.shift) {
            modifiers.append(KeySymbol(id: "shift", display: "⇧", isModifier: true))
        }
        if flags.contains(.command) {
            modifiers.append(KeySymbol(id: "command", display: "⌘", isModifier: true))
        }

        return modifiers
    }

    /// Returns the category for a given symbol.
    public static func category(for symbol: KeySymbol) -> KeyCategory {
        let id = symbol.id

        // Modifiers
        if id.hasPrefix("command") { return .command }
        if id.hasPrefix("shift") { return .shift }
        if id.hasPrefix("option") { return .option }
        if id.hasPrefix("control") { return .control }
        if id == "capslock" { return .capsLock }
        if id == "fn" { return .command } // Fn grouped with command

        // Special keys
        if id == "escape" { return .escape }

        // Function keys
        if id.hasPrefix("f") && id.dropFirst().allSatisfy(\.isNumber) {
            return .function
        }

        // Navigation
        if id.hasPrefix("arrow") || id == "home" || id == "end" ||
            id == "page-up" || id == "page-down"
        {
            return .navigation
        }

        // Editing
        if id == "space" || id == "tab" || id == "return" ||
            id == "enter" || id == "delete" || id == "forward-delete"
        {
            return .editing
        }

        // Default: letter (includes numbers, punctuation, etc.)
        return .letter
    }
}
