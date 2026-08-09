import CoreGraphics
import Foundation

// MARK: - TextEchoGlyph

/// One character of the echo.
///
/// Enter and Tab produce no character of their own but are worth seeing, so they are carried
/// inline as dim marks rather than as a line break the reader could not tell apart from the
/// echo's own wrapping.
public struct TextEchoGlyph: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        /// Ordinary typed text, drawn at full strength.
        case character

        /// Enter or Tab, drawn dimmed.
        case mark
    }

    public let id: String
    public let text: String
    public let kind: Kind

    public init(id: String, text: String, kind: Kind) {
        self.id = id
        self.text = text
        self.kind = kind
    }
}

// MARK: - TextEchoLine

/// One line of the echo, with an identity of its own.
///
/// Lines are model entities rather than a rendering detail because each one comes and goes on
/// its own terms, and because the wrap has to be decided once, when the character arrives: a
/// line re-flowed later would move glyphs that have already been read.
public struct TextEchoLine: Identifiable, Equatable, Sendable {
    public let id: String
    public var glyphs: [TextEchoGlyph]

    public init(id: String, glyphs: [TextEchoGlyph]) {
        self.id = id
        self.glyphs = glyphs
    }

    public var text: String {
        self.glyphs.map(\.text).joined()
    }

    public var characterCount: Int {
        self.glyphs.reduce(0) { $0 + $1.text.count }
    }

    public var isEmpty: Bool {
        self.glyphs.isEmpty
    }
}

// MARK: - TextEchoState

/// State model for the text echo mode.
///
/// The overlay repeats what is being typed, large and always in the same place, for an audience
/// that cannot read the real text field. Input is split in two:
/// - the **text zone**, up to three lines of real text;
/// - the **command zone**, shared verbatim with the horizontal history mode.
///
/// Three things end a line, and none of them keeps a copy — someone who switches away to type a
/// password and comes back must not find their earlier sentence waiting for them:
/// - the line being written has no clock at all and lives as long as the typing does;
/// - a line that a newer one has replaced ages out on its own, one plaque at a time, so a long
///   burst of typing leaves a trail that thins out behind it;
/// - and once typing stops the shorter idle clock clears whatever is still up. A line whose own
///   countdown ends first is not held back for it, so it may still leave alone.
@MainActor
@Observable
public final class TextEchoState: KeyEventSink {
    // MARK: - Properties

    /// How many lines the zone shows at once. A fourth line pushes the oldest off immediately.
    public nonisolated static let maxLines = 3

    /// Characters a line holds before the next one starts. The wrap is by character, not by
    /// word: a word wrap would yank the word being read down to the next line.
    public nonisolated static let maxLineCharacters = 24

    /// How long a line lives once a newer one has taken its place.
    public nonisolated static let defaultLineLifetime: TimeInterval = 3.5

    /// How long the whole zone stays up after the last thing typed or erased.
    ///
    /// Shorter than a line's lifetime so that in the common case the idle clock is what clears
    /// the zone. A line whose own countdown was already running when typing stopped is not
    /// held back, though: if it runs out first, that line still leaves on its own.
    public nonisolated static let defaultIdleTimeout: TimeInterval = 2

    /// Keys that produce text and therefore belong in the echo. Enter and Tab produce a mark
    /// instead of a character, but they are still typing.
    private static let textSpecialKeyIDs: Set<String> = ["space", "return", "enter", "tab"]

    /// The key that deletes the last character of the echo.
    private static let backspaceKeyID = "delete"

    /// Lines in reading order: oldest first, newest last.
    public private(set) var lines: [TextEchoLine] = []

    /// The zone every non-text keypress lands in, shared with the horizontal history mode.
    public let commandZone: CommandZoneState

    public var commandKeys: [PressedKey] {
        self.commandZone.keys
    }

    public var commandRepeatCount: Int {
        self.commandZone.repeatCount
    }

    public var commandRepeatKeyID: String? {
        self.commandZone.repeatKeyID
    }

    public var pressedCommandKeyIDs: Set<String> {
        self.commandZone.pressedKeyIDs
    }

    public var hasTextLines: Bool {
        !self.lines.isEmpty
    }

    public var hasCommandKeys: Bool {
        self.commandZone.hasKeys
    }

    public var hasKeys: Bool {
        self.hasTextLines || self.hasCommandKeys
    }

    /// The command zone's timeout. The text zone keeps its own two clocks below.
    public var keyTimeout: TimeInterval {
        get { self.commandZone.keyTimeout }
        set { self.commandZone.keyTimeout = newValue }
    }

    /// How long a line lives once a newer one has taken its place. The line being written has
    /// no lifetime at all: it lives for as long as the typing does.
    public var lineLifetime: TimeInterval = TextEchoState.defaultLineLifetime {
        didSet {
            guard self.lineLifetime != oldValue else { return }
            self.rearmLineTimeouts()
        }
    }

    /// How long the zone stays up after the last thing typed or erased.
    public var idleTimeout: TimeInterval = TextEchoState.defaultIdleTimeout {
        didSet {
            guard self.idleTimeout != oldValue else { return }
            self.rearmIdleTimeout()
        }
    }

    /// Content mode in force here. Shortcuts Only is dropped on the way in: the echo is the
    /// typed text itself, and the command zone next to it already shows what that setting asks
    /// for.
    public var contentMode: KeyboardContentMode {
        get { self.commandZone.contentMode }
        set { self.commandZone.contentMode = newValue.ignoringShortcutsOnly }
    }

    /// Filters in force here. The F-key and special-key switches are dropped on the way in:
    /// this mode routes by what a key produces, and ⏎, ⇥ and ␣ are text in the echo.
    public var filters: KeyboardFilterSettings {
        get { self.commandZone.filters }
        set { self.commandZone.filters = newValue.ignoringKeyCategories }
    }

    public var physicallyPressedKeys: Set<String> {
        self.commandZone.physicallyPressedKeys
    }

    public var pressedModifierIds: Set<String> {
        self.commandZone.pressedModifierIds
    }

    private let isKeyDown: SingleKeyState.KeyDownProbe

    /// Keycodes of the keys that are physically down and have been typing into the echo.
    ///
    /// A key that is already typing keeps typing while it is held, and pressing a modifier
    /// halfway through must not turn the rest of its autorepeat into a shortcut the user never
    /// pressed. The keycode is kept so a missed key up can be noticed later.
    private var heldTextKeys: [String: CGKeyCode] = [:]

    private var lineSequence: UInt64 = 0
    private var glyphSequence: UInt64 = 0

    /// One countdown per line that is no longer the one being written. The newest line never
    /// appears here.
    private var timeoutTasks: [String: Task<Void, Never>] = [:]
    private var timeoutStartedAt: [String: TimeInterval] = [:]

    private var idleTask: Task<Void, Never>?
    private var idleStartedAt: TimeInterval?

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
        self.commandZone = CommandZoneState(isKeyDown: isKeyDown)
        self.isKeyDown = isKeyDown
        self.apply(settings)
    }

    // MARK: - Functions

    /// Applies keyboard settings. `maxItems` is deliberately ignored: the echo mirrors typed
    /// text, so it shows every press and always the same three lines.
    public func apply(_ settings: KeyboardSettings) {
        self.keyTimeout = settings.timeout
        self.contentMode = settings.contentMode
        self.filters = settings.filters
        self.lineLifetime = settings.textLineLifetime
        self.idleTimeout = settings.textIdleTimeout
    }

    public func processEvent(_ event: KeyEvent, symbol: KeySymbol?) {
        guard let symbol else { return }

        guard !symbol.isModifier, event.type != .flagsChanged else {
            self.commandZone.processModifierEvent(event, symbol: symbol)
            return
        }

        switch event.type {
        case .keyDown:
            self.handleKeyDown(event: event, symbol: symbol)
        case .keyUp:
            self.heldTextKeys.removeValue(forKey: symbol.id)
            self.commandZone.releaseIfTracked(event: event, symbol: symbol)
        case .flagsChanged:
            break
        }
    }

    public func clear() {
        self.clearLines()
        self.heldTextKeys.removeAll()
        self.commandZone.clear()
    }

    /// Returns true if the modifier is physically pressed (not just visible).
    public func isModifierPressed(_ symbolId: String) -> Bool {
        self.commandZone.isModifierPressed(symbolId)
    }

    // MARK: - Event handling

    private func handleKeyDown(event: KeyEvent, symbol: KeySymbol) {
        self.commandZone.reconcileHeldKeys()
        self.dropStaleTextKeys()

        guard KeyboardEventFilter.disposition(
            for: event,
            symbol: symbol,
            settings: self.settingsSnapshot) == .display
        else {
            return
        }

        guard !self.routesToText(event: event, symbol: symbol) else {
            self.append(event: event, symbol: symbol)
            return
        }

        // A key already typing into the echo keeps repeating while it is held. Pressing ⌘
        // afterwards must not turn those repeats into a "⌘A" the user never pressed.
        if self.heldTextKeys[symbol.id] == nil {
            self.commandZone.register(event: event, symbol: symbol)
        }

        // Backspace is the one key that belongs to both zones: it is a command the audience
        // should see, and it really does take a character out of the text being echoed.
        if self.deletesText(event: event, symbol: symbol) {
            self.deleteLastCharacter()
        }
    }

    /// Forgets text keys the system no longer reports as pressed. A key up can be missed (tap
    /// disabled, overlay toggled off, app switch), which would otherwise leave a key marked as
    /// typing forever and swallow every later shortcut built on it.
    private func dropStaleTextKeys() {
        self.heldTextKeys = self.heldTextKeys.filter { self.isKeyDown($0.value) }
    }

    private func routesToText(event: KeyEvent, symbol: KeySymbol) -> Bool {
        guard !CommandZoneState.capturesInput(modifiers: event.modifiers) else { return false }
        return !symbol.isSpecial || Self.textSpecialKeyIDs.contains(symbol.id)
    }

    /// Whether this press erases a character from the echo.
    ///
    /// Only a plain Backspace does. ⌘⌫ and ⌥⌫ delete a line or a word in the real field, and
    /// the echo has no way to know which characters those were, so it leaves the text alone
    /// rather than deleting the wrong thing.
    private func deletesText(event: KeyEvent, symbol: KeySymbol) -> Bool {
        symbol.id == Self.backspaceKeyID
            && !CommandZoneState.capturesInput(modifiers: event.modifiers)
    }

    // MARK: - Text

    /// Appends one keystroke to the newest line, starting a new one when the budget is full.
    ///
    /// Key repeats are appended like any other press: holding a key really does type the
    /// character over and over, and the echo shows what was typed.
    ///
    /// A line only starts counting down once a newer one has taken its place, so the line being
    /// written is handed its lifetime here — by the line that replaces it.
    private func append(event: KeyEvent, symbol: KeySymbol) {
        defer { self.scheduleIdleTimeout() }

        let glyph = self.glyph(for: symbol, modifiers: event.modifiers)
        self.heldTextKeys[symbol.id] = CGKeyCode(truncatingIfNeeded: event.keyCode)

        if let index = self.lines.indices.last,
           self.lines[index].characterCount + glyph.text.count <= Self.maxLineCharacters
        {
            self.lines[index].glyphs.append(glyph)
            return
        }

        if let previous = self.lines.last {
            self.scheduleLineTimeout(for: previous.id)
        }

        self.lineSequence &+= 1
        self.lines.append(TextEchoLine(
            id: "echo-line-\(self.lineSequence)",
            glyphs: [glyph]))
        self.enforceLineLimit()
    }

    private func glyph(for symbol: KeySymbol, modifiers: CGEventFlags) -> TextEchoGlyph {
        self.glyphSequence &+= 1
        let id = "echo-glyph-\(self.glyphSequence)"

        switch symbol.id {
        case "space":
            return TextEchoGlyph(id: id, text: " ", kind: .character)
        case "return", "enter", "tab":
            return TextEchoGlyph(id: id, text: symbol.display, kind: .mark)
        default:
            return TextEchoGlyph(
                id: id,
                text: Self.echoDisplay(for: symbol, modifiers: modifiers),
                kind: .character)
        }
    }

    /// The layout's own character already carries Shift and CapsLock, so it is echoed verbatim.
    ///
    /// Only keys that arrived without one (the US-QWERTY fallback) fall back to re-casing
    /// `display`, where CapsLock has no reliable key events on macOS (`KeyCodeMapper` omits it)
    /// and the event's alpha-shift flag is the only signal available — best effort, as in the
    /// ribbon.
    private static func echoDisplay(for symbol: KeySymbol, modifiers: CGEventFlags) -> String {
        if let typedText = symbol.typedText {
            return typedText
        }
        let isUppercase = modifiers.contains(.maskShift) || modifiers.contains(.maskAlphaShift)
        return isUppercase ? symbol.display.uppercased() : symbol.display.lowercased()
    }

    /// Removes the last character still on screen, crossing into the previous line when the
    /// newest one empties.
    ///
    /// It only ever reaches into lines that are still visible. A line that has already expired
    /// or been evicted is gone for good — backspacing past the top of the echo must not pull
    /// anything back into view.
    ///
    /// Erasing is activity, so it holds the zone open like typing does.
    private func deleteLastCharacter() {
        defer { self.scheduleIdleTimeout() }

        guard let index = self.lines.indices.last else { return }

        self.lines[index].glyphs.removeLast()
        guard self.lines[index].isEmpty else { return }

        self.cancelLineTimeout(for: self.lines[index].id)
        self.lines.remove(at: index)

        // Erasing a line away promotes the one before it back to being written, and the line
        // being written never counts down.
        if let promoted = self.lines.last {
            self.cancelLineTimeout(for: promoted.id)
        }
    }

    private func enforceLineLimit() {
        guard self.lines.count > Self.maxLines else { return }

        let overflow = self.lines.count - Self.maxLines
        for line in self.lines.prefix(overflow) {
            self.cancelLineTimeout(for: line.id)
        }
        self.lines.removeFirst(overflow)
    }

    private func clearLines() {
        for task in self.timeoutTasks.values {
            task.cancel()
        }
        self.timeoutTasks.removeAll()
        self.timeoutStartedAt.removeAll()
        self.cancelIdleTimeout()
        self.lines.removeAll()
    }

    // MARK: - Timeouts

    private func scheduleLineTimeout(for lineID: String) {
        self.timeoutStartedAt[lineID] = ProcessInfo.processInfo.systemUptime
        self.rearmLineTimeout(for: lineID)
    }

    private func rearmLineTimeouts() {
        for lineID in self.timeoutStartedAt.keys {
            self.rearmLineTimeout(for: lineID)
        }
    }

    private func rearmLineTimeout(for lineID: String) {
        guard let timeoutStartedAt = self.timeoutStartedAt[lineID] else { return }

        self.timeoutTasks[lineID]?.cancel()
        let elapsed = ProcessInfo.processInfo.systemUptime - timeoutStartedAt
        let remaining = max(0, self.lineLifetime - elapsed)
        self.timeoutTasks[lineID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self?.removeLine(id: lineID)
        }
    }

    private func cancelLineTimeout(for lineID: String) {
        self.timeoutTasks[lineID]?.cancel()
        self.timeoutTasks.removeValue(forKey: lineID)
        self.timeoutStartedAt.removeValue(forKey: lineID)
    }

    private func removeLine(id: String) {
        self.cancelLineTimeout(for: id)
        self.lines.removeAll { $0.id == id }
    }

    // MARK: - Idle

    /// Restarts the zone's idle clock after something was typed or erased.
    ///
    /// An echo with nothing in it has nothing to hold open, so the clock only runs while there
    /// is text on screen — a Backspace that clears the last character takes the zone with it
    /// rather than leaving an empty one waiting to time out.
    private func scheduleIdleTimeout() {
        guard self.hasTextLines else {
            self.cancelIdleTimeout()
            return
        }
        self.idleStartedAt = ProcessInfo.processInfo.systemUptime
        self.rearmIdleTimeout()
    }

    private func rearmIdleTimeout() {
        guard let idleStartedAt = self.idleStartedAt else { return }

        self.idleTask?.cancel()
        let elapsed = ProcessInfo.processInfo.systemUptime - idleStartedAt
        let remaining = max(0, self.idleTimeout - elapsed)
        self.idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            // Whatever is still up goes at once, including lines whose own countdown had not
            // run out.
            self?.clearLines()
        }
    }

    private func cancelIdleTimeout() {
        self.idleTask?.cancel()
        self.idleTask = nil
        self.idleStartedAt = nil
    }
}
