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

// MARK: - KeyEventSink

/// The whole of what the overlay controller needs from a key state: feed it events, ask
/// whether anything is on screen, wipe it.
///
/// Deliberately narrower than `KeyStateProtocol`, because a state model is free to shape
/// its contents however its mode requires — the horizontal ribbon keeps two independent
/// zones and has no single flat `pressedKeys` row to expose.
@MainActor
public protocol KeyEventSink: AnyObject {
    /// Whether anything is currently displayed.
    var hasKeys: Bool { get }

    /// Processes a key event and updates state.
    func processEvent(_ event: KeyEvent, symbol: KeySymbol?)

    /// Removes everything currently displayed.
    func clear()
}

// MARK: - KeyStateProtocol

/// Common interface for single-row key state tracking.
@MainActor
public protocol KeyStateProtocol: KeyEventSink {
    /// Currently displayed keys.
    var pressedKeys: [PressedKey] { get }

    /// Timeout duration for keys.
    var keyTimeout: TimeInterval { get set }

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
