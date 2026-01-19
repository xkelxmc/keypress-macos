import CoreGraphics
import Foundation

// MARK: - KeyStateProtocol

/// Common interface for key state tracking (shared by KeyState and SingleKeyState).
@MainActor
public protocol KeyStateProtocol: AnyObject {
    /// Currently displayed keys.
    var pressedKeys: [PressedKey] { get }

    /// Whether any keys are currently displayed.
    var hasKeys: Bool { get }

    /// Timeout duration for keys.
    var keyTimeout: TimeInterval { get set }

    /// Processes a key event and updates state.
    func processEvent(_ event: KeyEvent, symbol: KeySymbol?)

    /// Removes all displayed keys.
    func clear()
}

// MARK: - PressedKey

/// Represents a currently pressed key with metadata.
public struct PressedKey: Identifiable, Equatable, Sendable {
    public let id: String
    public let symbol: KeySymbol
    public let pressedAt: Date

    /// Creates a pressed key with unique ID.
    /// - For modifiers: ID is based on symbol.id (so same modifier doesn't duplicate)
    /// - For special keys: ID is based on symbol.id (no duplicates, like modifiers)
    /// - For regular keys: ID includes timestamp for uniqueness (allows "hello" → h e l l o)
    public init(symbol: KeySymbol, pressedAt: Date = Date()) {
        if symbol.isModifier || symbol.isSpecial {
            // Modifiers and special keys use stable ID (don't duplicate)
            self.id = symbol.id
        } else {
            // Regular keys get unique ID (allows repeated keys)
            self.id = "\(symbol.id)-\(pressedAt.timeIntervalSince1970)"
        }
        self.symbol = symbol
        self.pressedAt = pressedAt
    }
}

// MARK: - KeyState

/// Tracks currently pressed keys for visualization.
/// Modifiers stay until released, regular keys timeout after a delay.
@MainActor
@Observable
public final class KeyState: KeyStateProtocol {
    // MARK: - Properties

    /// Currently pressed keys, ordered for display.
    /// Modifiers first, then regular keys by press time.
    public private(set) var pressedKeys: [PressedKey] = []

    /// Whether any keys are currently pressed.
    public var hasKeys: Bool {
        !self.pressedKeys.isEmpty
    }

    /// Timeout duration for regular keys (from Settings).
    public var keyTimeout: TimeInterval = 1.5

    /// Maximum number of keys to display. Range: 3-12.
    public var maxDisplayedKeys: Int = 6

    /// Whether to allow duplicate regular keys when typing.
    /// When true, "hello" shows 5 keys; when false, shows 4 (no repeat).
    public var duplicateLetters: Bool = true

    /// Whether modifiers count towards the max keys limit.
    /// When true, limit is total keys. When false, limit is only for non-modifiers.
    public var limitIncludesModifiers: Bool = true

    private var timeoutTasks: [String: Task<Void, Never>] = [:]

    /// Modifiers that were released but are kept visible because they're associated with a key
    private var releasedModifiers: Set<String> = []

    /// Maps key IDs to their associated modifier symbol IDs (for keeping combos together)
    private var keyModifierAssociations: [String: Set<String>] = [:]

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Processes a key event and updates state.
    public func processEvent(_ event: KeyEvent, symbol: KeySymbol?) {
        guard let symbol = symbol else { return }

        switch event.type {
        case .keyDown:
            self.handleKeyDown(symbol: symbol)
        case .keyUp:
            self.handleKeyUp(symbol: symbol)
        case .flagsChanged:
            self.handleFlagsChanged(keyCode: event.keyCode, symbol: symbol, flags: event.modifiers)
        }
    }

    /// Removes all pressed keys.
    public func clear() {
        for task in self.timeoutTasks.values {
            task.cancel()
        }
        self.timeoutTasks.removeAll()
        self.releasedModifiers.removeAll()
        self.keyModifierAssociations.removeAll()
        self.pressedKeys.removeAll()
    }

    // MARK: - Private Methods

    private func handleKeyDown(symbol: KeySymbol) {
        if symbol.isModifier {
            // Modifiers: only add if not already present, no timeout
            if !self.pressedKeys.contains(where: { $0.symbol.id == symbol.id }) {
                let key = PressedKey(symbol: symbol)
                self.addKey(key)
            }
            // If this modifier was in releasedModifiers, it's being pressed again
            self.releasedModifiers.remove(symbol.id)
        } else if symbol.isSpecial {
            // Special keys: don't duplicate, but use timeout (refresh timeout on re-press)
            self.cancelTimeout(for: symbol.id)
            if !self.pressedKeys.contains(where: { $0.symbol.id == symbol.id }) {
                let key = PressedKey(symbol: symbol)
                self.addKey(key)
                // Associate with current modifiers
                self.associateKeyWithModifiers(keyId: key.id)
            }
            self.scheduleTimeout(for: symbol.id)
        } else {
            // Regular keys
            if self.duplicateLetters {
                // Allow duplicates: each press is unique (typing "hello" → h e l l o)
                let key = PressedKey(symbol: symbol)
                self.addKey(key)
                // Associate with current modifiers
                self.associateKeyWithModifiers(keyId: key.id)
                self.scheduleTimeout(for: key.id)
            } else {
                // No duplicates: refresh timeout on re-press, don't add if already present
                self.cancelTimeout(for: symbol.id)
                if !self.pressedKeys.contains(where: { $0.symbol.id == symbol.id }) {
                    let key = PressedKey(symbol: symbol)
                    self.addKey(key)
                    // Associate with current modifiers
                    self.associateKeyWithModifiers(keyId: key.id)
                }
                self.scheduleTimeout(for: symbol.id)
            }
        }
    }

    /// Associates a key with currently active modifiers
    private func associateKeyWithModifiers(keyId: String) {
        let modifierIds = Set(
            self.pressedKeys
                .filter { $0.symbol.isModifier }
                .map { $0.symbol.id }
        )
        if !modifierIds.isEmpty {
            self.keyModifierAssociations[keyId] = modifierIds
        }
    }

    private func handleKeyUp(symbol: KeySymbol) {
        // For regular keys, the timeout handles removal
        // For modifiers, remove immediately on release
        if symbol.isModifier {
            self.removeModifier(symbolId: symbol.id)
        }
    }

    private func handleFlagsChanged(keyCode: Int64, symbol: KeySymbol, flags: CGEventFlags) {
        let isPressed = self.isModifierPressed(keyCode: keyCode, flags: flags)

        if isPressed {
            if !self.pressedKeys.contains(where: { $0.symbol.id == symbol.id }) {
                let key = PressedKey(symbol: symbol)
                self.addKey(key)
            }
        } else {
            self.removeModifier(symbolId: symbol.id)
        }
    }

    private func isModifierPressed(keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 0x37, 0x36: // Command
            return flags.contains(.maskCommand)
        case 0x38, 0x3C: // Shift
            return flags.contains(.maskShift)
        case 0x3A, 0x3D: // Option
            return flags.contains(.maskAlternate)
        case 0x3B, 0x3E: // Control
            return flags.contains(.maskControl)
        case 0x3F: // Fn
            return flags.contains(.maskSecondaryFn)
        default:
            return false
        }
    }

    private func addKey(_ key: PressedKey) {
        self.pressedKeys.append(key)
        self.sortAndLimit()
    }

    private func removeKey(id: String) {
        self.cancelTimeout(for: id)
        self.pressedKeys.removeAll { $0.id == id }

        // Clean up associated modifiers
        if let associatedModifiers = self.keyModifierAssociations.removeValue(forKey: id) {
            for modifierId in associatedModifiers {
                // Only remove if this modifier is in releasedModifiers (physically released)
                // and no other key is associated with it
                if self.releasedModifiers.contains(modifierId) {
                    let stillHasAssociations = self.keyModifierAssociations.values.contains { $0.contains(modifierId) }
                    if !stillHasAssociations {
                        self.releasedModifiers.remove(modifierId)
                        self.pressedKeys.removeAll { $0.symbol.id == modifierId }
                    }
                }
            }
        }
    }

    private func removeModifier(symbolId: String) {
        // Check if any key is associated with this modifier
        let hasAssociatedKeys = self.keyModifierAssociations.values.contains { $0.contains(symbolId) }

        if hasAssociatedKeys {
            // Don't remove yet — mark as released but keep visible
            self.releasedModifiers.insert(symbolId)
        } else {
            // No associated keys — remove immediately
            self.pressedKeys.removeAll { $0.symbol.id == symbolId }
        }
    }

    private func sortAndLimit() {
        // Sort order: modifiers first, then special keys, then regular keys (by press time)
        self.pressedKeys.sort { lhs, rhs in
            let lhsPriority = self.sortPriority(lhs.symbol)
            let rhsPriority = self.sortPriority(rhs.symbol)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.pressedAt < rhs.pressedAt
        }

        // Limit keys based on limitIncludesModifiers setting
        let modifiers = self.pressedKeys.filter { $0.symbol.isModifier }
        let special = self.pressedKeys.filter { $0.symbol.isSpecial }
        let regular = self.pressedKeys.filter { !$0.symbol.isModifier && !$0.symbol.isSpecial }

        if self.limitIncludesModifiers {
            // Total limit applies to all keys
            if self.pressedKeys.count > self.maxDisplayedKeys {
                var result: [PressedKey] = []
                var remaining = self.maxDisplayedKeys

                // Keep all modifiers (up to limit)
                let keptModifiers = Array(modifiers.prefix(remaining))
                result.append(contentsOf: keptModifiers)
                remaining -= keptModifiers.count

                // Keep special keys (up to remaining)
                let keptSpecial = Array(special.suffix(remaining))
                result.append(contentsOf: keptSpecial)
                remaining -= keptSpecial.count

                // Keep most RECENT regular keys
                let keptRegular = Array(regular.suffix(remaining))
                result.append(contentsOf: keptRegular)

                // Cancel timeouts for evicted keys
                let keptIds = Set(result.map { $0.id })
                for key in self.pressedKeys where !keptIds.contains(key.id) {
                    self.cancelTimeout(for: key.id)
                }

                self.pressedKeys = result
            }
        } else {
            // Limit applies only to non-modifiers (regular + special)
            let nonModifiers = special + regular
            if nonModifiers.count > self.maxDisplayedKeys {
                // Keep all modifiers
                var result: [PressedKey] = modifiers

                var remaining = self.maxDisplayedKeys

                // Keep special keys (up to limit)
                let keptSpecial = Array(special.suffix(remaining))
                result.append(contentsOf: keptSpecial)
                remaining -= keptSpecial.count

                // Keep most RECENT regular keys
                let keptRegular = Array(regular.suffix(remaining))
                result.append(contentsOf: keptRegular)

                // Cancel timeouts for evicted non-modifier keys
                let keptIds = Set(result.map { $0.id })
                for key in self.pressedKeys where !keptIds.contains(key.id) {
                    self.cancelTimeout(for: key.id)
                }

                self.pressedKeys = result
            }
        }
    }

    private func sortPriority(_ symbol: KeySymbol) -> Int {
        if symbol.isModifier { return 0 }
        if symbol.isSpecial { return 1 }
        return 2
    }

    private func scheduleTimeout(for keyId: String) {
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.keyTimeout ?? 1.5))

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.removeKey(id: keyId)
            }
        }

        self.timeoutTasks[keyId] = task
    }

    private func cancelTimeout(for keyId: String) {
        self.timeoutTasks[keyId]?.cancel()
        self.timeoutTasks.removeValue(forKey: keyId)
    }
}

// MARK: - SingleKeyState

/// Tracks only the latest key combination for visualization (Single mode).
/// Each new keypress replaces the previous display.
@MainActor
@Observable
public final class SingleKeyState: KeyStateProtocol {
    // MARK: - Properties

    /// Currently displayed keys (latest combination only).
    /// Modifiers + one non-modifier key.
    public private(set) var pressedKeys: [PressedKey] = []

    /// Whether any keys are currently displayed.
    public var hasKeys: Bool {
        !self.pressedKeys.isEmpty
    }

    /// Timeout duration before keys disappear.
    public var keyTimeout: TimeInterval = 1.5

    /// When true, only show combinations that include modifiers.
    public var showModifiersOnly: Bool = false

    /// Currently held modifiers (tracked separately for combination display).
    private var activeModifiers: [PressedKey] = []

    /// Last non-modifier key pressed (kept for display when modifiers change).
    private var lastNonModifierKey: PressedKey?

    /// Modifiers that were released but kept visible because lastNonModifierKey exists
    private var releasedModifiers: Set<String> = []

    private var timeoutTask: Task<Void, Never>?

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Processes a key event and updates state.
    public func processEvent(_ event: KeyEvent, symbol: KeySymbol?) {
        guard let symbol = symbol else { return }

        switch event.type {
        case .keyDown:
            self.handleKeyDown(symbol: symbol)
        case .keyUp:
            self.handleKeyUp(symbol: symbol)
        case .flagsChanged:
            self.handleFlagsChanged(keyCode: event.keyCode, symbol: symbol, flags: event.modifiers)
        }
    }

    /// Removes all displayed keys.
    public func clear() {
        self.timeoutTask?.cancel()
        self.timeoutTask = nil
        self.pressedKeys.removeAll()
        self.activeModifiers.removeAll()
        self.releasedModifiers.removeAll()
        self.lastNonModifierKey = nil
    }

    // MARK: - Private Methods

    private func handleKeyDown(symbol: KeySymbol) {
        if symbol.isModifier {
            // Track modifier but don't display alone yet
            if !self.activeModifiers.contains(where: { $0.symbol.id == symbol.id }) {
                let key = PressedKey(symbol: symbol)
                self.activeModifiers.append(key)
            }
            // Update display with current modifiers (preserve last non-modifier key)
            self.updateDisplay()
        } else {
            // If showModifiersOnly and no modifiers, ignore this key entirely
            if self.showModifiersOnly && self.activeModifiers.isEmpty {
                return
            }

            // Non-modifier key: clear released modifiers first (they're not part of this new combo)
            for modifierId in self.releasedModifiers {
                self.activeModifiers.removeAll { $0.symbol.id == modifierId }
            }
            self.releasedModifiers.removeAll()

            // Store new key and show combination
            self.lastNonModifierKey = PressedKey(symbol: symbol)
            self.updateDisplay()
            self.scheduleTimeout()
        }
    }

    private func handleKeyUp(symbol: KeySymbol) {
        if symbol.isModifier {
            self.activeModifiers.removeAll { $0.symbol.id == symbol.id }
            // If no more modifiers and showModifiersOnly, clear display
            if self.showModifiersOnly && self.activeModifiers.isEmpty {
                self.pressedKeys.removeAll()
            }
        }
    }

    private func handleFlagsChanged(keyCode: Int64, symbol: KeySymbol, flags: CGEventFlags) {
        let isPressed = self.isModifierPressed(keyCode: keyCode, flags: flags)

        if isPressed {
            if !self.activeModifiers.contains(where: { $0.symbol.id == symbol.id }) {
                let key = PressedKey(symbol: symbol)
                self.activeModifiers.append(key)
            }
            // Modifier pressed again — no longer released
            self.releasedModifiers.remove(symbol.id)
        } else {
            // Modifier released
            if self.lastNonModifierKey != nil {
                // Keep modifier visible — mark as released but don't remove
                self.releasedModifiers.insert(symbol.id)
            } else {
                // No key to keep combo with — remove immediately
                self.activeModifiers.removeAll { $0.symbol.id == symbol.id }
            }
        }

        // Update display to reflect current modifiers
        // Only update if we have something displayed or modifiers changed
        if !self.pressedKeys.isEmpty || !self.activeModifiers.isEmpty || self.lastNonModifierKey != nil {
            self.updateDisplay()
        }
    }

    private func isModifierPressed(keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 0x37, 0x36: return flags.contains(.maskCommand)
        case 0x38, 0x3C: return flags.contains(.maskShift)
        case 0x3A, 0x3D: return flags.contains(.maskAlternate)
        case 0x3B, 0x3E: return flags.contains(.maskControl)
        case 0x3F: return flags.contains(.maskSecondaryFn)
        default: return false
        }
    }

    private func updateDisplay() {
        var newKeys: [PressedKey] = []

        // Add active modifiers (sorted)
        let sortedModifiers = self.activeModifiers.sorted { lhs, rhs in
            lhs.pressedAt < rhs.pressedAt
        }
        newKeys.append(contentsOf: sortedModifiers)

        // Add the last non-modifier key if exists
        if let lastKey = self.lastNonModifierKey {
            newKeys.append(lastKey)
        }

        // Apply showModifiersOnly filter
        if self.showModifiersOnly {
            let hasModifiers = !self.activeModifiers.isEmpty
            let hasNonModifier = self.lastNonModifierKey != nil
            // Only show if we have modifiers AND a non-modifier key
            if !hasModifiers || !hasNonModifier {
                // Don't update display for non-modified keys
                if self.lastNonModifierKey != nil && !hasModifiers {
                    return
                }
            }
        }

        self.pressedKeys = newKeys
    }

    private func scheduleTimeout() {
        self.timeoutTask?.cancel()
        self.timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.keyTimeout ?? 1.5))

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.clearKeyAndReleasedModifiers()
            }
        }
    }

    private func clearKeyAndReleasedModifiers() {
        self.lastNonModifierKey = nil
        // Remove modifiers that were released while key was visible
        for modifierId in self.releasedModifiers {
            self.activeModifiers.removeAll { $0.symbol.id == modifierId }
        }
        self.releasedModifiers.removeAll()
        self.updateDisplay()
    }
}
