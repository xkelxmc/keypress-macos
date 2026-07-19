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

    /// Returns true if the modifier with given symbol ID is physically pressed.
    /// Used for press animation — modifiers can be visible but released.
    func isModifierPressed(_ symbolId: String) -> Bool

    /// Set of symbol IDs for modifiers that are physically pressed.
    /// Used for efficient batch checking in views.
    var pressedModifierIds: Set<String> { get }

    /// Set of symbol IDs for all keys that are physically pressed.
    /// Includes both modifiers and regular keys.
    var physicallyPressedKeys: Set<String> { get }
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

    /// All keys that are physically pressed right now (by symbol.id).
    /// Used for press animation — tracks both modifiers and regular keys.
    public private(set) var physicallyPressedKeys: Set<String> = []

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Processes a key event and updates state.
    public func processEvent(_ event: KeyEvent, symbol: KeySymbol?) {
        guard let symbol else { return }

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
        self.physicallyPressedKeys.removeAll()
    }

    /// Returns true if the modifier is physically pressed (not just visible).
    public func isModifierPressed(_ symbolId: String) -> Bool {
        // Modifier is pressed if it's visible AND not in releasedModifiers
        let isVisible = self.pressedKeys.contains { $0.symbol.id == symbolId && $0.symbol.isModifier }
        return isVisible && !self.releasedModifiers.contains(symbolId)
    }

    /// Set of symbol IDs for modifiers that are physically pressed.
    public var pressedModifierIds: Set<String> {
        let visibleModifierIds = Set(
            self.pressedKeys
                .filter(\.symbol.isModifier)
                .map(\.symbol.id))
        return visibleModifierIds.subtracting(self.releasedModifiers)
    }

    // MARK: - Private Methods

    private func handleKeyDown(symbol: KeySymbol) {
        // Track physical press state
        self.physicallyPressedKeys.insert(symbol.id)

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
                .filter(\.symbol.isModifier)
                .map(\.symbol.id))
        if !modifierIds.isEmpty {
            self.keyModifierAssociations[keyId] = modifierIds
        }
    }

    private func handleKeyUp(symbol: KeySymbol) {
        // Track physical release state
        self.physicallyPressedKeys.remove(symbol.id)

        // For regular keys, the timeout handles removal
        // For modifiers, remove immediately on release
        if symbol.isModifier {
            self.removeModifier(symbolId: symbol.id)
        }
    }

    private func handleFlagsChanged(keyCode: Int64, symbol: KeySymbol, flags: CGEventFlags) {
        let isPressed = self.isModifierPressed(keyCode: keyCode, flags: flags)

        // Track physical press state
        if isPressed {
            self.physicallyPressedKeys.insert(symbol.id)
        } else {
            self.physicallyPressedKeys.remove(symbol.id)
        }

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
            flags.contains(.maskCommand)
        case 0x38, 0x3C: // Shift
            flags.contains(.maskShift)
        case 0x3A, 0x3D: // Option
            flags.contains(.maskAlternate)
        case 0x3B, 0x3E: // Control
            flags.contains(.maskControl)
        case 0x3F: // Fn
            flags.contains(.maskSecondaryFn)
        default:
            false
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
            // Only process modifiers that are in releasedModifiers (physically released)
            for modifierId in associatedModifiers where self.releasedModifiers.contains(modifierId) {
                // Check if no other key is associated with this modifier
                let stillHasAssociations = self.keyModifierAssociations.values.contains { $0.contains(modifierId) }
                if !stillHasAssociations {
                    self.releasedModifiers.remove(modifierId)
                    self.pressedKeys.removeAll { $0.symbol.id == modifierId }
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
        let modifiers = self.pressedKeys.filter(\.symbol.isModifier)
        let special = self.pressedKeys.filter(\.symbol.isSpecial)
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
                let keptIds = Set(result.map(\.id))
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
                let keptIds = Set(result.map(\.id))
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

/// Tracks the latest key combination for visualization (Single mode).
/// Keys held down at the same time are shown together; once every key is
/// released the combination stays visible until the timeout fires.
@MainActor
@Observable
public final class SingleKeyState: KeyStateProtocol {
    // MARK: - Types

    /// Reports whether a key is physically down right now.
    /// Injectable so tests can drive the state machine deterministically.
    public typealias KeyDownProbe = @Sendable (CGKeyCode) -> Bool

    /// A non-modifier key that is currently held down.
    private struct HeldKey {
        let keyCode: CGKeyCode
        let key: PressedKey
    }

    // MARK: - Properties

    /// Cap on simultaneously displayed non-modifier keys — Single mode shows a
    /// combination, not a typing stream.
    private static let maxSimultaneousKeys = 4

    /// Currently displayed keys: active modifiers followed by the combination.
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

    /// Non-modifier keys physically held right now, in press order.
    private var heldKeys: [HeldKey] = []

    /// Last combination, kept visible after every key of it was released.
    private var lingeringKeys: [PressedKey] = []

    /// Modifiers that were released but kept visible because a combination is shown.
    private var releasedModifiers: Set<String> = []

    private var timeoutTask: Task<Void, Never>?

    private let isKeyDown: KeyDownProbe

    /// All keys that are physically pressed right now (by symbol.id).
    /// Used for press animation — tracks both modifiers and regular keys.
    public private(set) var physicallyPressedKeys: Set<String> = []

    /// Whether a combination is on screen (held or waiting for the timeout).
    private var hasComboKeys: Bool {
        !self.heldKeys.isEmpty || !self.lingeringKeys.isEmpty
    }

    // MARK: - Initialization

    public init(isKeyDown: @escaping KeyDownProbe = { CGEventSource.keyState(.combinedSessionState, key: $0) }) {
        self.isKeyDown = isKeyDown
    }

    // MARK: - Public Methods

    /// Processes a key event and updates state.
    public func processEvent(_ event: KeyEvent, symbol: KeySymbol?) {
        guard let symbol else { return }

        switch event.type {
        case .keyDown:
            self.handleKeyDown(keyCode: event.keyCode, symbol: symbol)
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
        self.heldKeys.removeAll()
        self.lingeringKeys.removeAll()
        self.physicallyPressedKeys.removeAll()
    }

    /// Returns true if the modifier is physically pressed (not just visible).
    public func isModifierPressed(_ symbolId: String) -> Bool {
        // Modifier is pressed if it's in activeModifiers AND not in releasedModifiers
        let isActive = self.activeModifiers.contains { $0.symbol.id == symbolId }
        return isActive && !self.releasedModifiers.contains(symbolId)
    }

    /// Set of symbol IDs for modifiers that are physically pressed.
    public var pressedModifierIds: Set<String> {
        let activeIds = Set(self.activeModifiers.map(\.symbol.id))
        return activeIds.subtracting(self.releasedModifiers)
    }

    // MARK: - Private Methods

    private func handleKeyDown(keyCode: Int64, symbol: KeySymbol) {
        // Track physical press state
        self.physicallyPressedKeys.insert(symbol.id)

        if symbol.isModifier {
            // Track modifier but don't display alone yet
            if !self.activeModifiers.contains(where: { $0.symbol.id == symbol.id }) {
                let key = PressedKey(symbol: symbol)
                self.activeModifiers.append(key)
            }
            // Pressed again — no longer a released modifier kept for the combo
            self.releasedModifiers.remove(symbol.id)
            // Update display with current modifiers (preserve the current combination)
            self.updateDisplay()
            return
        }

        // If showModifiersOnly and no modifiers, ignore this key entirely
        if self.showModifiersOnly, self.activeModifiers.isEmpty {
            return
        }

        self.dropStaleHeldKeys()

        if self.heldKeys.isEmpty {
            // Nothing is held — this key starts a new combination
            self.lingeringKeys.removeAll()
            self.forgetReleasedModifiers()
        }

        // Key repeats fire keyDown over and over while a key is held
        if !self.heldKeys.contains(where: { $0.key.symbol.id == symbol.id }) {
            self.heldKeys.append(HeldKey(
                keyCode: CGKeyCode(truncatingIfNeeded: keyCode),
                key: PressedKey(symbol: symbol)))
            if self.heldKeys.count > Self.maxSimultaneousKeys {
                self.heldKeys.removeFirst(self.heldKeys.count - Self.maxSimultaneousKeys)
            }
        }

        self.updateDisplay()
        self.scheduleTimeout()
    }

    private func handleKeyUp(symbol: KeySymbol) {
        // Track physical release state
        self.physicallyPressedKeys.remove(symbol.id)

        if symbol.isModifier {
            self.activeModifiers.removeAll { $0.symbol.id == symbol.id }
            // If no more modifiers and showModifiersOnly, clear display
            if self.showModifiersOnly, self.activeModifiers.isEmpty {
                self.pressedKeys.removeAll()
            }
            return
        }

        guard self.heldKeys.contains(where: { $0.key.symbol.id == symbol.id }) else { return }

        let displayedKeys = self.heldKeys.map(\.key)
        self.heldKeys.removeAll { $0.key.symbol.id == symbol.id }

        if self.heldKeys.isEmpty {
            // Everything released — keep the combination up until the timeout
            self.lingeringKeys = displayedKeys
            self.scheduleTimeout()
        }

        self.updateDisplay()
    }

    /// Drops keys the system no longer reports as pressed. A key up can be missed
    /// (tap disabled by the system, overlay toggled off, app switch), which would
    /// otherwise strand a key on screen and glue it to later combinations.
    private func dropStaleHeldKeys() {
        let staleIds = Set(
            self.heldKeys
                .filter { !self.isKeyDown($0.keyCode) }
                .map(\.key.symbol.id))
        guard !staleIds.isEmpty else { return }

        self.heldKeys.removeAll { staleIds.contains($0.key.symbol.id) }
        self.physicallyPressedKeys.subtract(staleIds)
    }

    private func forgetReleasedModifiers() {
        for modifierId in self.releasedModifiers {
            self.activeModifiers.removeAll { $0.symbol.id == modifierId }
        }
        self.releasedModifiers.removeAll()
    }

    private func handleFlagsChanged(keyCode: Int64, symbol: KeySymbol, flags: CGEventFlags) {
        let isPressed = self.isModifierPressed(keyCode: keyCode, flags: flags)

        // Track physical press state
        if isPressed {
            self.physicallyPressedKeys.insert(symbol.id)
        } else {
            self.physicallyPressedKeys.remove(symbol.id)
        }

        if isPressed {
            if !self.activeModifiers.contains(where: { $0.symbol.id == symbol.id }) {
                let key = PressedKey(symbol: symbol)
                self.activeModifiers.append(key)
            }
            // Modifier pressed again — no longer released
            self.releasedModifiers.remove(symbol.id)
        } else {
            // Modifier released
            if self.hasComboKeys {
                // Keep modifier visible — mark as released but don't remove
                self.releasedModifiers.insert(symbol.id)
            } else {
                // No combination to keep it with — remove immediately
                self.activeModifiers.removeAll { $0.symbol.id == symbol.id }
            }
        }

        self.updateDisplay()
    }

    private func isModifierPressed(keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 0x37, 0x36: flags.contains(.maskCommand)
        case 0x38, 0x3C: flags.contains(.maskShift)
        case 0x3A, 0x3D: flags.contains(.maskAlternate)
        case 0x3B, 0x3E: flags.contains(.maskControl)
        case 0x3F: flags.contains(.maskSecondaryFn)
        default: false
        }
    }

    private func updateDisplay() {
        // Held keys are the live truth; the lingering snapshot only shows once
        // everything is released.
        let comboKeys = self.heldKeys.isEmpty ? self.lingeringKeys : self.heldKeys.map(\.key)

        guard !self.showModifiersOnly || !self.activeModifiers.isEmpty else {
            self.pressedKeys = []
            return
        }

        var newKeys = self.activeModifiers.sorted { lhs, rhs in
            lhs.pressedAt < rhs.pressedAt
        }
        newKeys.append(contentsOf: comboKeys)

        self.pressedKeys = newKeys
    }

    private func scheduleTimeout() {
        self.timeoutTask?.cancel()
        self.timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.keyTimeout ?? 1.5))

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.handleTimeout()
            }
        }
    }

    private func handleTimeout() {
        self.dropStaleHeldKeys()

        // Keys still held stay on screen; re-arming means a missed key up is
        // caught by the next check instead of stranding the combination.
        guard self.heldKeys.isEmpty else {
            self.scheduleTimeout()
            return
        }

        self.lingeringKeys.removeAll()
        self.forgetReleasedModifiers()
        self.updateDisplay()
    }
}
