import CoreGraphics
import Foundation

// MARK: - RibbonKey

/// One text-producing keypress in the horizontal ribbon.
///
/// Every press creates a new entry with a fresh id — repeated letters and repeated
/// Space render as separate keycaps, and SwiftUI identity stays stable while the row
/// scrolls.
public struct RibbonKey: Identifiable, Equatable, Sendable {
    public let id: String
    public let symbol: KeySymbol

    /// `symbol.display` with ribbon casing applied (lowercase unless Shift or CapsLock).
    public let display: String
    public let pressedAt: Date

    public init(id: String, symbol: KeySymbol, display: String, pressedAt: Date) {
        self.id = id
        self.symbol = symbol
        self.display = display
        self.pressedAt = pressedAt
    }
}

// MARK: - HorizontalHistoryState

/// State model for the redesigned horizontal history mode.
///
/// Input is split into two independently rendered zones:
/// - the **text ribbon**, a strictly chronological queue of text-producing keys;
/// - the **command zone**, a Latest-mode combination display for everything that
///   produces no text (held modifiers, shortcuts, arrows, Escape, Backspace, …).
///
/// The ribbon is append-only: entries are inserted at the tail and leave at the head
/// (eviction) or by their own timeout. Nothing is ever re-sorted, so a view can animate
/// the whole row as one block and never has to move a single keycap on its own.
@MainActor
@Observable
public final class HorizontalHistoryState: KeyEventSink {
    // MARK: - Types

    /// A ribbon key whose physical key is still down, used to scope the press
    /// animation to the exact entry that press created.
    ///
    /// `entryID` becomes nil once that entry leaves the ribbon (eviction or timeout)
    /// while the key is still held: the mapping has to outlive the entry so autorepeat
    /// keeps being recognised as a repeat instead of pushing a phantom copy of the key
    /// back onto the tail.
    private struct HeldRibbonKey {
        let keyCode: CGKeyCode
        var entryID: String?
    }

    // MARK: - Properties

    /// Modifiers that reroute every keypress into the command zone. Shift is absent on
    /// purpose: it uppercases ribbon input instead of capturing it.
    private static let commandModifierFlags: CGEventFlags = [
        .maskCommand,
        .maskAlternate,
        .maskControl,
        .maskSecondaryFn,
    ]

    /// Special keys that still produce text and therefore belong to the ribbon.
    private static let textSpecialKeyIDs: Set<String> = ["space", "return", "enter", "tab"]

    /// Ribbon entries in press order: oldest first, newest last.
    public private(set) var ribbonKeys: [RibbonKey] = []

    /// Id of the ribbon entry that is still the last thing pressed. Space, Enter and Tab
    /// render wide while they hold this spot and shrink once anything else is pressed.
    public private(set) var latestRibbonKeyID: String?

    /// Ids of the ribbon entries created by keys that are physically down right now.
    /// Per instance, not per symbol — pressing a letter that already sits in the row
    /// must not animate the older copies.
    public private(set) var pressedRibbonKeyIDs: Set<String> = []

    /// Command zone contents: held modifiers followed by the current combination.
    public var commandKeys: [PressedKey] {
        self.commandState.pressedKeys
    }

    /// How many times the displayed command was pressed in a row. `0` when the zone
    /// shows no command, `1` for a single press; views draw the ×N badge above `1`.
    ///
    /// The count is matched against what is on screen right now: pressing a modifier
    /// alone glues it onto a lingering combination, and the badge of the old command
    /// must not survive that.
    public var commandRepeatCount: Int {
        guard self.hasCommandCombination else { return 0 }
        return self.currentCommandSignature == self.commandSignature ? self.commandRepeats : 1
    }

    /// Id of the keycap that should carry the ×N badge — the last non-modifier key of
    /// the displayed command.
    public var commandRepeatKeyID: String? {
        self.commandKeys.last { !$0.symbol.isModifier }?.id
    }

    public var hasRibbonKeys: Bool {
        !self.ribbonKeys.isEmpty
    }

    public var hasCommandKeys: Bool {
        self.commandState.hasKeys
    }

    public var hasKeys: Bool {
        self.hasRibbonKeys || self.hasCommandKeys
    }

    public var keyTimeout: TimeInterval {
        get { self.commandState.keyTimeout }
        set {
            let oldValue = self.commandState.keyTimeout
            self.commandState.keyTimeout = newValue
            guard newValue != oldValue else { return }
            self.rearmRibbonTimeouts()
        }
    }

    /// Maximum number of ribbon entries. Range: 3-12.
    public var maxItems: Int = 6 {
        didSet {
            let clamped = max(3, min(12, self.maxItems))
            guard clamped == self.maxItems else {
                self.maxItems = clamped
                return
            }
            self.enforceRibbonLimit()
        }
    }

    public var contentMode: KeyboardContentMode {
        get { self.commandState.contentMode }
        set {
            let changed = self.commandState.contentMode != newValue
            self.commandState.contentMode = newValue
            guard changed, newValue == .shortcutsOnly else { return }
            self.clearRibbon()
        }
    }

    public var filters: KeyboardFilterSettings {
        get { self.commandState.filters }
        set {
            let changed = self.commandState.filters != newValue
            self.commandState.filters = newValue
            guard changed else { return }
            self.reconcileRibbonFilters()
        }
    }

    /// Set of symbol ids for all keys that are physically pressed in the command zone.
    public var physicallyPressedKeys: Set<String> {
        self.commandState.physicallyPressedKeys
    }

    /// Set of symbol ids for modifiers that are physically pressed.
    public var pressedModifierIds: Set<String> {
        self.commandState.pressedModifierIds
    }

    /// Ids of the command zone keycaps whose key is physically down right now. Entry
    /// ids, like `pressedRibbonKeyIDs` — views must never match a press by symbol id.
    public var pressedCommandKeyIDs: Set<String> {
        let physicallyPressed = self.commandState.physicallyPressedKeys
        return Set(
            self.commandKeys
                .filter { physicallyPressed.contains($0.symbol.id) }
                .map(\.id))
    }

    private let commandState: SingleKeyState
    private let isKeyDown: SingleKeyState.KeyDownProbe

    private var heldRibbonKeys: [String: HeldRibbonKey] = [:]
    private var ribbonSequence: UInt64 = 0
    private var timeoutTasks: [String: Task<Void, Never>] = [:]
    private var timeoutStartedAt: [String: TimeInterval] = [:]

    private var commandSignature: String?
    private var commandRepeats: Int = 0

    private var hasCommandCombination: Bool {
        self.commandKeys.contains { !$0.symbol.isModifier }
    }

    private var currentCommandSignature: String {
        self.commandKeys.map(\.symbol.id).joined(separator: "+")
    }

    private var settingsSnapshot: KeyboardSettings {
        KeyboardSettings(contentMode: self.contentMode, filters: self.filters)
    }

    // MARK: - Lifecycle

    public init(
        settings: KeyboardSettings = KeyboardSettings(),
        isKeyDown: @escaping SingleKeyState.KeyDownProbe = {
            CGEventSource.keyState(.combinedSessionState, key: $0)
        })
    {
        self.commandState = SingleKeyState(isKeyDown: isKeyDown)
        self.isKeyDown = isKeyDown
        self.apply(settings)
    }

    // MARK: - Functions

    /// Applies keyboard settings. `duplicateLetters` is deliberately ignored: the ribbon
    /// mirrors typed text, so every press always gets its own keycap.
    public func apply(_ settings: KeyboardSettings) {
        self.keyTimeout = settings.timeout
        self.contentMode = settings.contentMode
        self.filters = settings.filters
        self.maxItems = settings.maxItems
    }

    public func processEvent(_ event: KeyEvent, symbol: KeySymbol?) {
        guard let symbol else { return }

        guard !symbol.isModifier, event.type != .flagsChanged else {
            self.commandState.processEvent(event, symbol: symbol)
            return
        }

        switch event.type {
        case .keyDown:
            self.handleKeyDown(event: event, symbol: symbol)
        case .keyUp:
            self.handleKeyUp(event: event, symbol: symbol)
        case .flagsChanged:
            break
        }
    }

    public func clear() {
        self.clearRibbon()
        self.commandState.clear()
        self.commandSignature = nil
        self.commandRepeats = 0
    }

    /// Returns true if the modifier is physically pressed (not just visible).
    public func isModifierPressed(_ symbolId: String) -> Bool {
        self.commandState.isModifierPressed(symbolId)
    }

    // MARK: - Event handling

    private func handleKeyDown(event: KeyEvent, symbol: KeySymbol) {
        self.commandState.reconcileHeldKeys()
        self.dropStaleRibbonKeys()

        guard KeyboardEventFilter.disposition(
            for: event,
            symbol: symbol,
            settings: self.settingsSnapshot) == .display
        else {
            return
        }

        if self.routesToRibbon(event: event, symbol: symbol) {
            self.appendRibbonKey(event: event, symbol: symbol)
        } else if self.heldRibbonKeys[symbol.id] == nil {
            // A key already typed into the ribbon keeps repeating while held. Pressing ⌘
            // afterwards must not turn those repeats into a "⌘A" the user never pressed.
            self.registerCommand(event: event, symbol: symbol)
        }
    }

    private func handleKeyUp(event: KeyEvent, symbol: KeySymbol) {
        if let entryID = self.heldRibbonKeys.removeValue(forKey: symbol.id)?.entryID {
            self.pressedRibbonKeyIDs.remove(entryID)
        }
        guard self.commandState.physicallyPressedKeys.contains(symbol.id) else { return }
        self.commandState.processEvent(event, symbol: symbol)
    }

    private func routesToRibbon(event: KeyEvent, symbol: KeySymbol) -> Bool {
        guard self.contentMode == .allKeys else { return false }
        guard event.modifiers.isDisjoint(with: Self.commandModifierFlags) else { return false }
        return !symbol.isSpecial || Self.textSpecialKeyIDs.contains(symbol.id)
    }

    // MARK: - Ribbon

    private func appendRibbonKey(event: KeyEvent, symbol: KeySymbol) {
        // A key held down repeats keyDown; the ribbon shows physical presses, so the
        // repeat only keeps the existing keycap alive — and adds nothing at all once
        // that keycap is gone.
        if let held = self.heldRibbonKeys[symbol.id] {
            if let entryID = held.entryID {
                self.scheduleRibbonTimeout(for: entryID)
            }
            return
        }

        self.ribbonSequence &+= 1
        let key = RibbonKey(
            id: "ribbon-\(self.ribbonSequence)-\(symbol.id)",
            symbol: symbol,
            display: Self.ribbonDisplay(for: symbol, modifiers: event.modifiers),
            pressedAt: event.timestamp)

        self.ribbonKeys.append(key)
        self.latestRibbonKeyID = key.id
        self.heldRibbonKeys[symbol.id] = HeldRibbonKey(
            keyCode: CGKeyCode(truncatingIfNeeded: event.keyCode),
            entryID: key.id)
        self.pressedRibbonKeyIDs.insert(key.id)
        self.scheduleRibbonTimeout(for: key.id)
        self.enforceRibbonLimit()
    }

    /// CapsLock has no reliable key events on macOS (`KeyCodeMapper` omits it), so the
    /// event's alpha-shift flag is the only signal available — best effort.
    private static func ribbonDisplay(for symbol: KeySymbol, modifiers: CGEventFlags) -> String {
        guard !symbol.isSpecial else { return symbol.display }
        let isUppercase = modifiers.contains(.maskShift) || modifiers.contains(.maskAlphaShift)
        return isUppercase ? symbol.display.uppercased() : symbol.display.lowercased()
    }

    /// Drops ribbon keys the system no longer reports as pressed. A key up can be missed
    /// (tap disabled, overlay toggled off, app switch), which would otherwise strand a
    /// keycap in the pressed state and swallow the next press of the same key.
    private func dropStaleRibbonKeys() {
        let stale = self.heldRibbonKeys.filter { !self.isKeyDown($0.value.keyCode) }
        guard !stale.isEmpty else { return }

        for (symbolID, held) in stale {
            self.heldRibbonKeys.removeValue(forKey: symbolID)
            if let entryID = held.entryID {
                self.pressedRibbonKeyIDs.remove(entryID)
            }
        }
    }

    private func enforceRibbonLimit() {
        guard self.ribbonKeys.count > self.maxItems else { return }

        let overflow = self.ribbonKeys.count - self.maxItems
        for key in self.ribbonKeys.prefix(overflow) {
            self.forgetRibbonKey(id: key.id)
        }
        self.ribbonKeys.removeFirst(overflow)
    }

    private func reconcileRibbonFilters() {
        let invalidIDs = self.ribbonKeys
            .filter { !self.filters.includes($0.symbol) }
            .map(\.id)
        for keyID in invalidIDs {
            self.removeRibbonKey(id: keyID)
        }
    }

    private func removeRibbonKey(id: String) {
        self.forgetRibbonKey(id: id)
        self.ribbonKeys.removeAll { $0.id == id }
    }

    /// Drops every trace of a ribbon entry except its slot in `ribbonKeys`, so callers
    /// can remove the slot in whichever way suits them (head eviction or by id).
    private func forgetRibbonKey(id: String) {
        self.cancelRibbonTimeout(for: id)
        self.pressedRibbonKeyIDs.remove(id)
        if let symbolID = self.heldRibbonKeys.first(where: { $0.value.entryID == id })?.key {
            self.heldRibbonKeys[symbolID]?.entryID = nil
        }
        if self.latestRibbonKeyID == id {
            self.latestRibbonKeyID = nil
        }
    }

    private func clearRibbon() {
        for task in self.timeoutTasks.values {
            task.cancel()
        }
        self.timeoutTasks.removeAll()
        self.timeoutStartedAt.removeAll()
        self.ribbonKeys.removeAll()
        self.heldRibbonKeys.removeAll()
        self.pressedRibbonKeyIDs.removeAll()
        self.latestRibbonKeyID = nil
    }

    // MARK: - Command zone

    private func registerCommand(event: KeyEvent, symbol: KeySymbol) {
        let isKeyRepeat = self.commandState.physicallyPressedKeys.contains(symbol.id)
        let previousSignature = self.commandSignature
        let hadCombination = self.hasCommandCombination

        self.latestRibbonKeyID = nil
        self.commandState.processReconciledEvent(event, symbol: symbol)

        guard !isKeyRepeat else { return }

        let signature = self.currentCommandSignature
        self.commandRepeats = hadCombination && signature == previousSignature
            ? self.commandRepeats + 1
            : 1
        self.commandSignature = signature
    }

    // MARK: - Timeouts

    private func scheduleRibbonTimeout(for keyID: String) {
        self.timeoutStartedAt[keyID] = ProcessInfo.processInfo.systemUptime
        self.rearmRibbonTimeout(for: keyID)
    }

    private func rearmRibbonTimeouts() {
        for keyID in self.timeoutStartedAt.keys {
            self.rearmRibbonTimeout(for: keyID)
        }
    }

    private func rearmRibbonTimeout(for keyID: String) {
        guard let timeoutStartedAt = self.timeoutStartedAt[keyID] else { return }

        self.timeoutTasks[keyID]?.cancel()
        let elapsed = ProcessInfo.processInfo.systemUptime - timeoutStartedAt
        let remaining = max(0, self.keyTimeout - elapsed)
        self.timeoutTasks[keyID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.removeRibbonKey(id: keyID)
        }
    }

    private func cancelRibbonTimeout(for keyID: String) {
        self.timeoutTasks[keyID]?.cancel()
        self.timeoutTasks.removeValue(forKey: keyID)
        self.timeoutStartedAt.removeValue(forKey: keyID)
    }
}
