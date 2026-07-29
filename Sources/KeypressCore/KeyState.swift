import CoreGraphics
import Foundation

private func modifierIsPressed(
    event: KeyEvent,
    symbolID: String,
    physicallyPressedKeys: Set<String>) -> Bool
{
    if let modifierIsPressed = event.modifierIsPressed {
        return modifierIsPressed
    }
    if physicallyPressedKeys.contains(symbolID) {
        return false
    }

    switch event.keyCode {
    case 0x37, 0x36: return event.modifiers.contains(.maskCommand)
    case 0x38, 0x3C: return event.modifiers.contains(.maskShift)
    case 0x3A, 0x3D: return event.modifiers.contains(.maskAlternate)
    case 0x3B, 0x3E: return event.modifiers.contains(.maskControl)
    case 0x3F: return event.modifiers.contains(.maskSecondaryFn)
    default: return false
    }
}

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
    public var keyTimeout: TimeInterval = 1.5 {
        didSet {
            guard self.keyTimeout != oldValue else { return }
            self.rearmTimeouts()
        }
    }

    /// Maximum number of keys to display. Range: 3-12.
    public var maxDisplayedKeys: Int = 6 {
        didSet {
            let clamped = max(3, min(12, self.maxDisplayedKeys))
            guard clamped == self.maxDisplayedKeys else {
                self.maxDisplayedKeys = clamped
                self.sortAndLimit()
                return
            }
            self.sortAndLimit()
        }
    }

    /// Whether to allow duplicate regular keys when typing.
    /// When true, "hello" shows 5 keys; when false, shows 4 (no repeat).
    public var duplicateLetters: Bool = true

    /// Whether modifiers count towards the max keys limit.
    /// When true, limit is total keys. When false, limit is only for non-modifiers.
    public var limitIncludesModifiers: Bool = true {
        didSet {
            guard self.limitIncludesModifiers != oldValue else { return }
            self.sortAndLimit()
        }
    }

    public var contentMode: KeyboardContentMode = .allKeys {
        didSet {
            guard self.contentMode != oldValue else { return }
            self.reconcileDisplaySettings()
        }
    }

    public var filters = KeyboardFilterSettings() {
        didSet {
            guard self.filters != oldValue else { return }
            self.reconcileDisplaySettings()
        }
    }

    private var timeoutTasks: [String: Task<Void, Never>] = [:]
    private var timeoutStartedAt: [String: TimeInterval] = [:]
    private var hiddenModifiers: [String: PressedKey] = [:]

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
        if !symbol.isModifier, event.type == .keyDown {
            let settings = KeyboardSettings(
                contentMode: self.contentMode,
                filters: self.filters)
            guard KeyboardEventFilter.disposition(
                for: event,
                symbol: symbol,
                settings: settings) == .display
            else {
                return
            }
            self.promoteHiddenModifiers()
        }

        switch event.type {
        case .keyDown:
            self.handleKeyDown(symbol: symbol)
        case .keyUp:
            self.handleKeyUp(symbol: symbol)
        case .flagsChanged:
            self.handleFlagsChanged(event: event, symbol: symbol)
        }
    }

    /// Removes all pressed keys.
    public func clear() {
        for task in self.timeoutTasks.values {
            task.cancel()
        }
        self.timeoutTasks.removeAll()
        self.timeoutStartedAt.removeAll()
        self.hiddenModifiers.removeAll()
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
            guard self.filters.includes(symbol) else {
                self.hiddenModifiers[symbol.id] = PressedKey(symbol: symbol)
                self.pressedKeys.removeAll { $0.symbol.id == symbol.id }
                self.releasedModifiers.remove(symbol.id)
                return
            }

            // Modifiers: only add if not already present, no timeout
            if self.filters.showStandaloneModifiers,
               !self.pressedKeys.contains(where: { $0.symbol.id == symbol.id })
            {
                let key = PressedKey(symbol: symbol)
                self.addKey(key)
            } else if !self.filters.showStandaloneModifiers {
                self.hiddenModifiers[symbol.id] = PressedKey(symbol: symbol)
            }
            // If this modifier was in releasedModifiers, it's being pressed again
            self.releasedModifiers.remove(symbol.id)
        } else if symbol.isSpecial {
            // Special keys: don't duplicate, but use timeout (refresh timeout on re-press)
            self.cancelTimeout(for: symbol.id)
            if !self.pressedKeys.contains(where: { $0.symbol.id == symbol.id }) {
                let key = PressedKey(symbol: symbol)
                self.addKey(key)
            }
            guard self.pressedKeys.contains(where: { $0.id == symbol.id }) else {
                self.reconcileDisplaySettings()
                return
            }
            self.associateKeyWithModifiers(keyId: symbol.id)
            self.scheduleTimeout(for: symbol.id)
        } else {
            // Regular keys
            if self.duplicateLetters {
                // Allow duplicates: each press is unique (typing "hello" → h e l l o)
                let key = PressedKey(symbol: symbol)
                self.addKey(key)
                guard self.pressedKeys.contains(where: { $0.id == key.id }) else {
                    self.reconcileDisplaySettings()
                    return
                }
                // Associate with current modifiers
                self.associateKeyWithModifiers(keyId: key.id)
                self.scheduleTimeout(for: key.id)
            } else {
                // No duplicates: refresh timeout on re-press, don't add if already present
                let keyId: String
                if let existingKey = self.pressedKeys.first(where: { $0.symbol.id == symbol.id }) {
                    keyId = existingKey.id
                    self.cancelTimeout(for: keyId)
                } else {
                    let key = PressedKey(symbol: symbol)
                    self.addKey(key)
                    keyId = key.id
                }
                guard self.pressedKeys.contains(where: { $0.id == keyId }) else {
                    self.reconcileDisplaySettings()
                    return
                }
                self.associateKeyWithModifiers(keyId: keyId)
                self.scheduleTimeout(for: keyId)
            }
        }
    }

    /// Associates a key with currently active modifiers
    private func associateKeyWithModifiers(keyId: String) {
        self.keyModifierAssociations.removeValue(forKey: keyId)
        self.removeUnassociatedReleasedModifiers()

        let modifierIds = Set(
            self.pressedKeys
                .filter { $0.symbol.isModifier && !self.releasedModifiers.contains($0.symbol.id) }
                .map(\.symbol.id))
        if !modifierIds.isEmpty {
            self.keyModifierAssociations[keyId] = modifierIds
        }
    }

    private func reconcileDisplaySettings() {
        let filteredModifierIDs = Set(
            self.pressedKeys
                .filter { $0.symbol.isModifier && !self.filters.includes($0.symbol) }
                .map(\.symbol.id))
        for modifier in self.pressedKeys
            where filteredModifierIDs.contains(modifier.symbol.id)
            && self.physicallyPressedKeys.contains(modifier.symbol.id)
        {
            self.hiddenModifiers[modifier.symbol.id] = modifier
        }
        self.pressedKeys.removeAll { filteredModifierIDs.contains($0.symbol.id) }
        self.releasedModifiers.subtract(filteredModifierIDs)
        for keyID in Array(self.keyModifierAssociations.keys) {
            self.keyModifierAssociations[keyID]?.subtract(filteredModifierIDs)
            if self.keyModifierAssociations[keyID]?.isEmpty == true {
                self.keyModifierAssociations.removeValue(forKey: keyID)
            }
        }

        let invalidKeyIDs = self.pressedKeys
            .filter { key in
                guard !key.symbol.isModifier else { return false }
                guard self.filters.includes(key.symbol) else { return true }
                return self.contentMode == .shortcutsOnly
                    && !key.symbol.isSpecial
                    && self.keyModifierAssociations[key.id, default: []].isEmpty
            }
            .map(\.id)

        for keyID in invalidKeyIDs {
            self.removeKey(id: keyID)
        }

        if self.filters.showStandaloneModifiers {
            self.promoteHiddenModifiers()
        } else {
            let associatedModifierIDs = self.keyModifierAssociations.values.reduce(into: Set<String>()) {
                $0.formUnion($1)
            }
            let standaloneModifiers = self.pressedKeys.filter {
                $0.symbol.isModifier && !associatedModifierIDs.contains($0.symbol.id)
            }
            for modifier in standaloneModifiers
                where self.physicallyPressedKeys.contains(modifier.symbol.id)
            {
                self.hiddenModifiers[modifier.symbol.id] = modifier
            }

            let standaloneModifierIDs = Set(standaloneModifiers.map(\.symbol.id))
            self.pressedKeys.removeAll { standaloneModifierIDs.contains($0.symbol.id) }
            self.releasedModifiers.subtract(standaloneModifierIDs)
        }

        self.sortAndLimit()
    }

    private func handleKeyUp(symbol: KeySymbol) {
        // Track physical release state
        self.physicallyPressedKeys.remove(symbol.id)
        self.hiddenModifiers.removeValue(forKey: symbol.id)

        // For regular keys, the timeout handles removal
        // For modifiers, remove immediately on release
        if symbol.isModifier {
            self.removeModifier(symbolId: symbol.id)
        }
    }

    private func handleFlagsChanged(event: KeyEvent, symbol: KeySymbol) {
        let isPressed = modifierIsPressed(
            event: event,
            symbolID: symbol.id,
            physicallyPressedKeys: self.physicallyPressedKeys)

        // Track physical press state
        if isPressed {
            self.physicallyPressedKeys.insert(symbol.id)
        } else {
            self.physicallyPressedKeys.remove(symbol.id)
        }

        if isPressed {
            guard self.filters.includes(symbol) else {
                self.hiddenModifiers[symbol.id] = PressedKey(symbol: symbol)
                self.pressedKeys.removeAll { $0.symbol.id == symbol.id }
                self.releasedModifiers.remove(symbol.id)
                return
            }

            if self.filters.showStandaloneModifiers,
               !self.pressedKeys.contains(where: { $0.symbol.id == symbol.id })
            {
                let key = PressedKey(symbol: symbol)
                self.addKey(key)
            } else if !self.filters.showStandaloneModifiers {
                self.hiddenModifiers[symbol.id] = PressedKey(symbol: symbol)
            }
        } else {
            self.hiddenModifiers.removeValue(forKey: symbol.id)
            self.removeModifier(symbolId: symbol.id)
        }
    }

    private func promoteHiddenModifiers() {
        let modifiers = self.hiddenModifiers.values
            .filter { self.filters.includes($0.symbol) }
            .sorted { $0.pressedAt < $1.pressedAt }
        for modifier in modifiers {
            self.hiddenModifiers.removeValue(forKey: modifier.symbol.id)
        }
        for modifier in modifiers where !self.pressedKeys.contains(where: { $0.id == modifier.id }) {
            self.addKey(modifier)
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

                let keptIds = Set(result.map(\.id))
                let evictedKeys = self.pressedKeys.filter { !keptIds.contains($0.id) }
                self.pressedKeys = result
                self.cleanUpEvictedKeys(evictedKeys)
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

                let keptIds = Set(result.map(\.id))
                let evictedKeys = self.pressedKeys.filter { !keptIds.contains($0.id) }
                self.pressedKeys = result
                self.cleanUpEvictedKeys(evictedKeys)
            }
        }
    }

    private func cleanUpEvictedKeys(_ evictedKeys: [PressedKey]) {
        for key in evictedKeys {
            self.cancelTimeout(for: key.id)
            self.keyModifierAssociations.removeValue(forKey: key.id)
            if key.symbol.isModifier,
               self.physicallyPressedKeys.contains(key.symbol.id)
            {
                self.hiddenModifiers[key.symbol.id] = key
            }
        }

        self.removeUnassociatedReleasedModifiers()
    }

    private func removeUnassociatedReleasedModifiers() {
        let unassociatedReleasedModifiers = self.releasedModifiers.filter { modifierId in
            !self.keyModifierAssociations.values.contains { $0.contains(modifierId) }
        }
        self.releasedModifiers.subtract(unassociatedReleasedModifiers)
        self.pressedKeys.removeAll { unassociatedReleasedModifiers.contains($0.symbol.id) }
    }

    private func sortPriority(_ symbol: KeySymbol) -> Int {
        if symbol.isModifier { return 0 }
        if symbol.isSpecial { return 1 }
        return 2
    }

    private func scheduleTimeout(for keyId: String) {
        self.timeoutStartedAt[keyId] = ProcessInfo.processInfo.systemUptime
        self.rearmTimeout(for: keyId)
    }

    private func rearmTimeouts() {
        for keyId in self.timeoutStartedAt.keys {
            self.rearmTimeout(for: keyId)
        }
    }

    private func rearmTimeout(for keyId: String) {
        guard let timeoutStartedAt = self.timeoutStartedAt[keyId] else { return }

        self.timeoutTasks[keyId]?.cancel()
        let elapsed = ProcessInfo.processInfo.systemUptime - timeoutStartedAt
        let remaining = max(0, self.keyTimeout - elapsed)
        self.timeoutTasks[keyId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.removeKey(id: keyId)
            }
        }
    }

    private func cancelTimeout(for keyId: String) {
        self.timeoutTasks[keyId]?.cancel()
        self.timeoutTasks.removeValue(forKey: keyId)
        self.timeoutStartedAt.removeValue(forKey: keyId)
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
    public var keyTimeout: TimeInterval = 1.5 {
        didSet {
            guard self.keyTimeout != oldValue else { return }
            self.rearmTimeout()
        }
    }

    public var contentMode: KeyboardContentMode = .allKeys {
        didSet {
            guard self.contentMode != oldValue else { return }
            self.reconcileDisplaySettings()
        }
    }

    public var filters = KeyboardFilterSettings() {
        didSet {
            guard self.filters != oldValue else { return }
            self.reconcileDisplaySettings()
        }
    }

    /// Compatibility accessor for the former single-mode setting.
    public var showModifiersOnly: Bool {
        get { self.contentMode == .shortcutsOnly }
        set { self.contentMode = newValue ? .shortcutsOnly : .allKeys }
    }

    /// Currently held modifiers (tracked separately for combination display).
    private var activeModifiers: [PressedKey] = []

    /// Non-modifier keys physically held right now, in press order.
    private var heldKeys: [HeldKey] = []

    /// Every key that participated in the current simultaneous combination.
    private var currentCombinationKeys: [PressedKey] = []

    /// Last combination, kept visible after every key of it was released.
    private var lingeringKeys: [PressedKey] = []

    /// Modifiers that were released but kept visible because a combination is shown.
    private var releasedModifiers: Set<String> = []

    private var timeoutTask: Task<Void, Never>?
    private var timeoutStartedAt: TimeInterval?

    private let isKeyDown: KeyDownProbe

    /// All keys that are physically pressed right now (by symbol.id).
    /// Used for press animation — tracks both modifiers and regular keys.
    public private(set) var physicallyPressedKeys: Set<String> = []

    /// Whether a combination is on screen (held or waiting for the timeout).
    private var hasComboKeys: Bool {
        !self.heldKeys.isEmpty || !self.lingeringKeys.isEmpty
    }

    /// Whether the displayed combination still has a physically held non-modifier key.
    var hasHeldCombination: Bool {
        !self.heldKeys.isEmpty
    }

    // MARK: - Initialization

    public init(isKeyDown: @escaping KeyDownProbe = { CGEventSource.keyState(.combinedSessionState, key: $0) }) {
        self.isKeyDown = isKeyDown
    }

    // MARK: - Public Methods

    /// Processes a key event and updates state.
    public func processEvent(_ event: KeyEvent, symbol: KeySymbol?) {
        guard let symbol else { return }

        if event.type == .keyDown, !symbol.isModifier {
            self.reconcileHeldKeys()
        }
        self.processReconciledEvent(event, symbol: symbol)
    }

    func reconcileHeldKeys() {
        self.dropStaleHeldKeys()
    }

    func processReconciledEvent(_ event: KeyEvent, symbol: KeySymbol) {
        switch event.type {
        case .keyDown:
            self.handleKeyDown(event: event, symbol: symbol)
        case .keyUp:
            self.handleKeyUp(symbol: symbol)
        case .flagsChanged:
            self.handleFlagsChanged(event: event, symbol: symbol)
        }
    }

    /// Removes all displayed keys.
    public func clear() {
        self.timeoutTask?.cancel()
        self.timeoutTask = nil
        self.timeoutStartedAt = nil
        self.pressedKeys.removeAll()
        self.activeModifiers.removeAll()
        self.releasedModifiers.removeAll()
        self.heldKeys.removeAll()
        self.currentCombinationKeys.removeAll()
        self.lingeringKeys.removeAll()
        self.physicallyPressedKeys.removeAll()
    }

    /// Returns true if the modifier is physically pressed (not just visible).
    public func isModifierPressed(_ symbolId: String) -> Bool {
        // Modifier is pressed if it's in activeModifiers AND not in releasedModifiers
        let isActive = self.activeModifiers.contains {
            $0.symbol.id == symbolId && self.filters.includes($0.symbol)
        }
        return isActive && !self.releasedModifiers.contains(symbolId)
    }

    /// Set of symbol IDs for modifiers that are physically pressed.
    public var pressedModifierIds: Set<String> {
        let activeIds = Set(
            self.activeModifiers
                .filter { self.filters.includes($0.symbol) }
                .map(\.symbol.id))
        return activeIds.subtracting(self.releasedModifiers)
    }

    // MARK: - Private Methods

    private func handleKeyDown(event: KeyEvent, symbol: KeySymbol) {
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

        let settings = KeyboardSettings(
            contentMode: self.contentMode,
            filters: self.filters)
        guard KeyboardEventFilter.disposition(
            for: event,
            symbol: symbol,
            settings: settings) == .display
        else {
            return
        }

        if self.heldKeys.isEmpty {
            // Nothing is held — this key starts a new combination
            self.lingeringKeys.removeAll()
            self.currentCombinationKeys.removeAll()
            self.forgetReleasedModifiers()
        }

        // Key repeats fire keyDown over and over while a key is held
        if !self.heldKeys.contains(where: { $0.key.symbol.id == symbol.id }) {
            let key = PressedKey(symbol: symbol)
            self.heldKeys.append(HeldKey(
                keyCode: CGKeyCode(truncatingIfNeeded: event.keyCode),
                key: key))
            self.currentCombinationKeys.append(key)
            if self.heldKeys.count > Self.maxSimultaneousKeys {
                let overflow = self.heldKeys.count - Self.maxSimultaneousKeys
                let evictedIds = Set(self.heldKeys.prefix(overflow).map(\.key.id))
                self.heldKeys.removeFirst(overflow)
                self.currentCombinationKeys.removeAll { evictedIds.contains($0.id) }
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
            if self.contentMode == .shortcutsOnly, self.activeModifiers.isEmpty {
                self.pressedKeys.removeAll()
            }
            return
        }

        guard self.heldKeys.contains(where: { $0.key.symbol.id == symbol.id }) else { return }

        self.heldKeys.removeAll { $0.key.symbol.id == symbol.id }

        if self.heldKeys.isEmpty {
            // Everything released — keep the combination up until the timeout
            self.lingeringKeys = self.currentCombinationKeys
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
        self.updateDisplay()
    }

    private func forgetReleasedModifiers() {
        for modifierId in self.releasedModifiers {
            self.activeModifiers.removeAll { $0.symbol.id == modifierId }
        }
        self.releasedModifiers.removeAll()
    }

    private func reconcileDisplaySettings() {
        self.heldKeys.removeAll { !self.filters.includes($0.key.symbol) }
        self.currentCombinationKeys.removeAll { !self.filters.includes($0.symbol) }
        self.lingeringKeys.removeAll { !self.filters.includes($0.symbol) }

        let comboKeys = self.heldKeys.isEmpty ? self.lingeringKeys : self.heldKeys.map(\.key)
        if self.contentMode == .shortcutsOnly,
           self.activeModifiers.isEmpty,
           !comboKeys.contains(where: \.symbol.isSpecial)
        {
            self.heldKeys.removeAll()
            self.currentCombinationKeys.removeAll()
            self.lingeringKeys.removeAll()
        }

        if !self.hasComboKeys {
            self.timeoutTask?.cancel()
            self.timeoutTask = nil
            self.timeoutStartedAt = nil
            self.currentCombinationKeys.removeAll()
            self.forgetReleasedModifiers()
        }
        self.updateDisplay()
    }

    private func handleFlagsChanged(event: KeyEvent, symbol: KeySymbol) {
        let isPressed = modifierIsPressed(
            event: event,
            symbolID: symbol.id,
            physicallyPressedKeys: self.physicallyPressedKeys)

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

    private func updateDisplay() {
        // Held keys are the live truth; the lingering snapshot only shows once
        // everything is released.
        let comboKeys = self.heldKeys.isEmpty ? self.lingeringKeys : self.heldKeys.map(\.key)
        let includesSpecialKey = comboKeys.contains { $0.symbol.isSpecial }

        guard self.contentMode != .shortcutsOnly
            || !self.activeModifiers.isEmpty
            || includesSpecialKey
        else {
            self.pressedKeys = []
            return
        }

        if comboKeys.isEmpty, !self.filters.showStandaloneModifiers {
            self.pressedKeys = []
            return
        }

        var newKeys = self.activeModifiers
            .filter { self.filters.includes($0.symbol) }
            .sorted { lhs, rhs in
                lhs.pressedAt < rhs.pressedAt
            }
        newKeys.append(contentsOf: comboKeys)

        self.pressedKeys = newKeys
    }

    private func scheduleTimeout() {
        self.timeoutStartedAt = ProcessInfo.processInfo.systemUptime
        self.rearmTimeout()
    }

    private func rearmTimeout() {
        guard let timeoutStartedAt = self.timeoutStartedAt else { return }

        self.timeoutTask?.cancel()
        let elapsed = ProcessInfo.processInfo.systemUptime - timeoutStartedAt
        let remaining = max(0, self.keyTimeout - elapsed)
        self.timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.handleTimeout()
            }
        }
    }

    private func handleTimeout() {
        self.timeoutTask = nil
        self.timeoutStartedAt = nil
        self.dropStaleHeldKeys()

        // Keys still held stay on screen; re-arming means a missed key up is
        // caught by the next check instead of stranding the combination.
        guard self.heldKeys.isEmpty else {
            self.scheduleTimeout()
            return
        }

        self.lingeringKeys.removeAll()
        self.currentCombinationKeys.removeAll()
        self.forgetReleasedModifiers()
        self.updateDisplay()
    }
}

// MARK: - StackedHistoryState

public struct StackedHistoryEntry: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        case text
        case shortcut
    }

    public let id: String
    public var keys: [PressedKey]
    public let kind: Kind
    public let createdAt: Date
    public var updatedAt: Date

    public var text: String {
        self.keys.map { key in
            key.symbol.id == "space" ? " " : key.symbol.display
        }.joined()
    }

    public init(
        id: String = UUID().uuidString,
        keys: [PressedKey],
        kind: Kind = .text,
        createdAt: Date = Date(),
        updatedAt: Date? = nil)
    {
        self.id = id
        self.keys = keys
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

/// Keeps the latest key combination at the normal overlay anchor and stores
/// completed text and shortcut history separately.
@MainActor
@Observable
public final class StackedHistoryState: KeyStateProtocol {
    public static let textGroupingInterval: TimeInterval = 0.65
    public static let maxTextCharacters = 24

    public private(set) var entries: [StackedHistoryEntry] = []

    public var pressedKeys: [PressedKey] {
        self.anchorState.pressedKeys
    }

    public var physicallyPressedKeys: Set<String> {
        self.anchorState.physicallyPressedKeys
    }

    public var hasKeys: Bool {
        self.anchorState.hasKeys || !self.entries.isEmpty
    }

    public var hasAnchorKeys: Bool {
        self.anchorState.hasKeys
    }

    public var keyTimeout: TimeInterval {
        get { self.anchorState.keyTimeout }
        set {
            let oldValue = self.anchorState.keyTimeout
            self.anchorState.keyTimeout = newValue
            guard newValue != oldValue else { return }
            self.rearmEntryTimeouts()
        }
    }

    public var contentMode: KeyboardContentMode {
        get { self.anchorState.contentMode }
        set {
            let changed = self.anchorState.contentMode != newValue
            self.anchorState.contentMode = newValue
            guard changed else { return }

            self.pendingShortcut = nil
            self.currentCombinationIsShortcut = false
            self.currentTextContributions.removeAll()
            if newValue == .shortcutsOnly {
                self.clearTextEntries()
            }
        }
    }

    public var filters: KeyboardFilterSettings {
        get { self.anchorState.filters }
        set {
            let changed = self.anchorState.filters != newValue
            self.anchorState.filters = newValue
            guard changed else { return }

            self.pendingShortcut = nil
            self.currentCombinationIsShortcut = false
            self.reconcileShortcutEntries()
        }
    }

    public var duplicateLetters = true

    public var maxItems = 6 {
        didSet {
            let clamped = max(3, min(12, self.maxItems))
            guard clamped == self.maxItems else {
                self.maxItems = clamped
                self.enforceLimit()
                return
            }
            self.enforceLimit()
        }
    }

    public var pressedModifierIds: Set<String> {
        self.anchorState.pressedModifierIds
    }

    private let anchorState: SingleKeyState
    private var timeoutTasks: [String: Task<Void, Never>] = [:]
    private var timeoutStartedAt: [String: TimeInterval] = [:]
    private var textFragmentIsOpen = false
    private var currentCombinationIsShortcut = false
    private var currentTextContributions: [String: Int] = [:]
    private var pendingShortcut: StackedHistoryEntry?

    public init(
        settings: KeyboardSettings = KeyboardSettings(),
        isKeyDown: @escaping SingleKeyState.KeyDownProbe = {
            CGEventSource.keyState(.combinedSessionState, key: $0)
        })
    {
        self.anchorState = SingleKeyState(isKeyDown: isKeyDown)
        self.apply(settings)
    }

    public func apply(_ settings: KeyboardSettings) {
        self.keyTimeout = settings.timeout
        self.contentMode = settings.contentMode
        self.filters = settings.filters
        self.duplicateLetters = settings.duplicateLetters
        self.maxItems = settings.maxItems
    }

    public func processEvent(_ event: KeyEvent, symbol: KeySymbol?) {
        guard let symbol else { return }

        if event.type == .keyDown, !symbol.isModifier {
            self.anchorState.reconcileHeldKeys()
        }

        let wasPhysicallyPressed = self.anchorState.physicallyPressedKeys.contains(symbol.id)
        let hadHeldCombination = self.anchorState.hasHeldCombination
        let settings = KeyboardSettings(
            contentMode: self.contentMode,
            filters: self.filters)
        let disposition = KeyboardEventFilter.disposition(
            for: event,
            symbol: symbol,
            settings: settings)
        let isNewDisplayableKeyDown = event.type == .keyDown
            && !symbol.isModifier
            && !wasPhysicallyPressed
            && disposition == .display

        if isNewDisplayableKeyDown {
            if !hadHeldCombination {
                self.archivePendingShortcut()
                self.currentCombinationIsShortcut = !self.isTextInput(event: event, symbol: symbol)
                self.currentTextContributions.removeAll()
            } else if !self.isTextInput(event: event, symbol: symbol) {
                self.currentCombinationIsShortcut = true
                self.retractCurrentTextContributions()
            }
        }

        self.anchorState.processReconciledEvent(event, symbol: symbol)

        if event.type == .keyUp,
           !symbol.isModifier,
           hadHeldCombination,
           !self.anchorState.hasHeldCombination
        {
            if self.currentCombinationIsShortcut, self.anchorState.hasKeys {
                self.pendingShortcut = StackedHistoryEntry(
                    keys: self.anchorState.pressedKeys,
                    kind: .shortcut,
                    createdAt: event.timestamp)
            } else {
                self.pendingShortcut = nil
            }
            self.currentCombinationIsShortcut = false
            self.currentTextContributions.removeAll()
        }

        guard event.type == .keyDown, !symbol.isModifier else {
            if symbol.isModifier, !self.modifierKeepsTextOpen(symbol) {
                self.textFragmentIsOpen = false
            }
            return
        }

        guard !wasPhysicallyPressed else { return }

        if disposition == .display, self.isTextInput(event: event, symbol: symbol) {
            if let entryID = self.appendText(symbol: symbol, timestamp: event.timestamp) {
                self.currentTextContributions[entryID, default: 0] += 1
            }
        } else {
            self.textFragmentIsOpen = false
        }
    }

    public func clear() {
        self.anchorState.clear()
        self.clearEntries()
        self.pendingShortcut = nil
        self.currentCombinationIsShortcut = false
        self.currentTextContributions.removeAll()
    }

    public func isModifierPressed(_ symbolId: String) -> Bool {
        self.anchorState.isModifierPressed(symbolId)
    }

    private func isTextInput(event: KeyEvent, symbol: KeySymbol) -> Bool {
        guard self.contentMode == .allKeys else { return false }
        let shortcutFlags: CGEventFlags = [
            .maskCommand,
            .maskAlternate,
            .maskControl,
            .maskSecondaryFn,
        ]
        let isTextSymbol = !symbol.isSpecial || symbol.id == "space"
        return isTextSymbol && event.modifiers.isDisjoint(with: shortcutFlags)
    }

    private func modifierKeepsTextOpen(_ symbol: KeySymbol) -> Bool {
        switch KeyCodeMapper.category(for: symbol) {
        case .shift, .capsLock:
            true
        case .letter, .command, .option, .control, .escape, .function, .navigation, .editing:
            false
        }
    }

    private func appendText(symbol: KeySymbol, timestamp: Date) -> String? {
        if !self.duplicateLetters,
           let lastIndex = self.entries.indices.last,
           self.entries[lastIndex].kind == .text,
           self.entries[lastIndex].keys.contains(where: { $0.symbol.id == symbol.id })
        {
            self.entries[lastIndex].updatedAt = timestamp
            self.scheduleTimeout(for: self.entries[lastIndex].id)
            return nil
        }

        let key = PressedKey(symbol: symbol, pressedAt: timestamp)
        if self.textFragmentIsOpen,
           let lastIndex = self.entries.indices.last,
           self.entries[lastIndex].kind == .text,
           timestamp >= self.entries[lastIndex].updatedAt,
           timestamp.timeIntervalSince(self.entries[lastIndex].updatedAt) <= Self.textGroupingInterval,
           Self.textLength(self.entries[lastIndex].keys + [key]) <= Self.maxTextCharacters
        {
            self.entries[lastIndex].keys.append(key)
            self.entries[lastIndex].updatedAt = timestamp
            self.scheduleTimeout(for: self.entries[lastIndex].id)
        } else {
            let entry = StackedHistoryEntry(keys: [key], createdAt: timestamp)
            self.entries.append(entry)
            self.scheduleTimeout(for: entry.id)
            self.enforceLimit()
        }
        self.textFragmentIsOpen = true
        return self.entries.last?.id
    }

    private func retractCurrentTextContributions() {
        guard !self.currentTextContributions.isEmpty else { return }

        var emptyEntryIDs: Set<String> = []
        for (entryID, contributionCount) in self.currentTextContributions {
            guard let index = self.entries.firstIndex(where: { $0.id == entryID }) else { continue }

            self.entries[index].keys.removeLast(min(contributionCount, self.entries[index].keys.count))

            if let lastKey = self.entries[index].keys.last {
                self.entries[index].updatedAt = lastKey.pressedAt
            } else {
                emptyEntryIDs.insert(self.entries[index].id)
            }
        }
        for entryID in emptyEntryIDs {
            self.cancelTimeout(for: entryID)
        }
        self.entries.removeAll { emptyEntryIDs.contains($0.id) }
        self.currentTextContributions.removeAll()
    }

    private func archivePendingShortcut() {
        guard let pendingShortcut = self.pendingShortcut else { return }
        self.pendingShortcut = nil

        let displayedKeyIDs = Set(self.anchorState.pressedKeys.map(\.id))
        let shortcutKeyIDs = pendingShortcut.keys
            .filter { !$0.symbol.isModifier }
            .map(\.id)
        guard self.anchorState.hasKeys,
              shortcutKeyIDs.allSatisfy(displayedKeyIDs.contains)
        else {
            return
        }

        self.entries.append(pendingShortcut)
        self.scheduleTimeout(for: pendingShortcut.id)
        self.enforceLimit()
    }

    private static func textLength(_ keys: [PressedKey]) -> Int {
        keys.reduce(into: 0) { length, key in
            length += key.symbol.id == "space" ? 1 : key.symbol.display.count
        }
    }

    private func enforceLimit() {
        guard self.entries.count > self.maxItems else { return }

        let removed = self.entries.prefix(self.entries.count - self.maxItems)
        for entry in removed {
            self.currentTextContributions.removeValue(forKey: entry.id)
        }
        for entry in removed {
            self.cancelTimeout(for: entry.id)
        }
        self.entries.removeFirst(self.entries.count - self.maxItems)
    }

    private func clearTextEntries() {
        let textEntryIDs = self.entries
            .filter { $0.kind == .text }
            .map(\.id)
        for entryID in textEntryIDs {
            self.cancelTimeout(for: entryID)
        }
        self.entries.removeAll { $0.kind == .text }
        self.textFragmentIsOpen = false
        self.currentTextContributions.removeAll()
    }

    private func reconcileShortcutEntries() {
        let invalidEntryIDs = Set(
            self.entries
                .filter { entry in
                    entry.kind == .shortcut
                        && entry.keys.contains { !self.filters.includes($0.symbol) }
                }
                .map(\.id))
        for entryID in invalidEntryIDs {
            self.cancelTimeout(for: entryID)
        }
        self.entries.removeAll { invalidEntryIDs.contains($0.id) }
    }

    private func clearEntries() {
        for task in self.timeoutTasks.values {
            task.cancel()
        }
        self.timeoutTasks.removeAll()
        self.timeoutStartedAt.removeAll()
        self.entries.removeAll()
        self.textFragmentIsOpen = false
        self.currentTextContributions.removeAll()
    }

    private func scheduleTimeout(for entryID: String) {
        self.timeoutStartedAt[entryID] = ProcessInfo.processInfo.systemUptime
        self.rearmTimeout(for: entryID)
    }

    private func rearmEntryTimeouts() {
        for entryID in self.entries.map(\.id) {
            self.rearmTimeout(for: entryID)
        }
    }

    private func rearmTimeout(for entryID: String) {
        guard let timeoutStartedAt = self.timeoutStartedAt[entryID] else { return }

        self.timeoutTasks[entryID]?.cancel()
        let elapsed = ProcessInfo.processInfo.systemUptime - timeoutStartedAt
        let remaining = max(0, self.keyTimeout - elapsed)
        self.timeoutTasks[entryID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.removeEntry(id: entryID)
        }
    }

    private func cancelTimeout(for entryID: String) {
        self.timeoutTasks[entryID]?.cancel()
        self.timeoutTasks.removeValue(forKey: entryID)
        self.timeoutStartedAt.removeValue(forKey: entryID)
    }

    private func removeEntry(id: String) {
        self.cancelTimeout(for: id)
        self.currentTextContributions.removeValue(forKey: id)
        self.entries.removeAll { $0.id == id }
    }
}
