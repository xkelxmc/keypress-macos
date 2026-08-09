import CoreGraphics
import Foundation
import Testing
@testable import KeypressCore

// MARK: - EchoKeyboard

/// Stands in for the system key-state probe so tests can hold keys down.
private final class EchoKeyboard: @unchecked Sendable {
    private var downKeys: Set<CGKeyCode> = []
    private let lock = NSLock()

    var probe: SingleKeyState.KeyDownProbe {
        { keyCode in self.lock.withLock { self.downKeys.contains(keyCode) } }
    }

    func press(_ keyCode: Int64) {
        self.lock.withLock { _ = self.downKeys.insert(CGKeyCode(keyCode)) }
    }

    func release(_ keyCode: Int64) {
        self.lock.withLock { _ = self.downKeys.remove(CGKeyCode(keyCode)) }
    }
}

// MARK: - EchoKeys

private enum EchoKeys {
    static let letterA = KeySymbol(id: "key-a", display: "A")
    static let letterB = KeySymbol(id: "key-b", display: "B")
    static let letterC = KeySymbol(id: "key-c", display: "C")
    static let letterV = KeySymbol(id: "key-v", display: "V")
    static let space = KeySymbol(id: "space", display: "␣", isSpecial: true)
    static let returnKey = KeySymbol(id: "return", display: "⏎", isSpecial: true)
    static let tab = KeySymbol(id: "tab", display: "⇥", isSpecial: true)
    static let backspace = KeySymbol(id: "delete", display: "⌫", isSpecial: true)
    static let forwardDelete = KeySymbol(id: "forward-delete", display: "⌦", isSpecial: true)
    static let escape = KeySymbol(id: "escape", display: "ESC", isSpecial: true)
    static let arrowLeft = KeySymbol(id: "arrow-left", display: "←", isSpecial: true)
    static let functionOne = KeySymbol(id: "f1", display: "F1", isSpecial: true)
    static let command = KeySymbol(id: "command-left", display: "⌘", isModifier: true)
    static let shift = KeySymbol(id: "shift-left", display: "⇧", isModifier: true)

    static let codeA: Int64 = 0x00
    static let codeB: Int64 = 0x0B
    static let codeC: Int64 = 0x08
    static let codeV: Int64 = 0x09
    static let codeSpace: Int64 = 0x31
    static let codeReturn: Int64 = 0x24
    static let codeTab: Int64 = 0x30
    static let codeBackspace: Int64 = 0x33
    static let codeCommand: Int64 = 0x37
    static let codeShift: Int64 = 0x38
}

// MARK: - Text zone

@Suite("TextEchoState Text Tests")
struct TextEchoStateTextTests {
    @Test("Initial state is empty")
    @MainActor
    func initialState() {
        let state = TextEchoState(isKeyDown: { _ in false })

        #expect(state.lines.isEmpty)
        #expect(state.commandKeys.isEmpty)
        #expect(state.hasKeys == false)
        #expect(state.hasTextLines == false)
    }

    @Test("Typing lands as real text, lowercase by default")
    @MainActor
    func typingProducesText() {
        let state = TextEchoState(isKeyDown: { _ in false })

        type(state, "abc")

        #expect(state.lines.map(\.text) == ["abc"])
        #expect(state.commandKeys.isEmpty)
    }

    @Test("Space is a real space, not a symbol")
    @MainActor
    func spaceIsASpace() {
        let state = TextEchoState(isKeyDown: { _ in false })

        press(state, EchoKeys.codeA, EchoKeys.letterA)
        press(state, EchoKeys.codeSpace, EchoKeys.space)
        press(state, EchoKeys.codeB, EchoKeys.letterB)

        #expect(state.lines.map(\.text) == ["a b"])
    }

    @Test("Enter and Tab are dim marks inline, never a line break")
    @MainActor
    func enterAndTabAreInlineMarks() {
        let state = TextEchoState(isKeyDown: { _ in false })

        press(state, EchoKeys.codeA, EchoKeys.letterA)
        press(state, EchoKeys.codeReturn, EchoKeys.returnKey)
        press(state, EchoKeys.codeTab, EchoKeys.tab)
        press(state, EchoKeys.codeB, EchoKeys.letterB)

        #expect(state.lines.count == 1)
        #expect(state.lines[0].text == "a⏎⇥b")
        #expect(state.lines[0].glyphs.map(\.kind) == [.character, .mark, .mark, .character])
    }

    @Test("Held Shift uppercases the echoed character")
    @MainActor
    func shiftUppercases() {
        let state = TextEchoState(isKeyDown: { _ in false })

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: EchoKeys.codeShift, modifiers: .maskShift),
            symbol: EchoKeys.shift)
        press(state, EchoKeys.codeA, EchoKeys.letterA, modifiers: .maskShift)
        press(state, EchoKeys.codeB, EchoKeys.letterB)

        #expect(state.lines.map(\.text) == ["Ab"])
        #expect(state.commandKeys.map(\.symbol.display) == ["⇧"])
    }

    @Test("The CapsLock flag uppercases the echoed character")
    @MainActor
    func capsLockUppercases() {
        let state = TextEchoState(isKeyDown: { _ in false })

        press(state, EchoKeys.codeA, EchoKeys.letterA, modifiers: .maskAlphaShift)

        #expect(state.lines.map(\.text) == ["A"])
    }

    /// `KeyCodeMapper` upper-cases the layout's character for the keycap, and ß upper-cases to
    /// "SS" — lower-casing that back would echo "ss". The character the layout produced is
    /// carried alongside for exactly this, and it already reflects Shift and CapsLock, so the
    /// flags must not be consulted on top of it.
    @Test("A key whose uppercase is two letters echoes the character that was typed")
    @MainActor
    func lossyUppercaseEchoesTheTypedCharacter() {
        let state = TextEchoState(isKeyDown: { _ in false })
        let sharpS = KeySymbol(id: "key-27", display: "SS", typedText: "ß")

        press(state, 0x1B, sharpS)
        press(state, 0x1B, sharpS, modifiers: .maskAlphaShift)

        #expect(state.lines.map(\.text) == ["ßß"])
    }

    @Test("A line wraps by character at its budget, never by word")
    @MainActor
    func wrapsByCharacter() {
        let state = TextEchoState(isKeyDown: { _ in false })
        let sentence = "the quick brown foxes jump"

        type(state, sentence)

        #expect(state.lines.count == 2)
        #expect(state.lines[0].text.count == TextEchoState.maxLineCharacters)
        // The wrap lands mid-word: a word wrap would have moved "foxes" down with it.
        #expect(state.lines.map(\.text).joined() == sentence)
    }

    @Test("Glyphs already drawn are never re-flowed by later typing")
    @MainActor
    func earlierLinesNeverChange() {
        let state = TextEchoState(isKeyDown: { _ in false })

        type(state, String(repeating: "a", count: TextEchoState.maxLineCharacters))
        let firstLine = state.lines[0]

        type(state, "bbb")

        #expect(state.lines[0] == firstLine)
        #expect(state.lines.map(\.text) == [firstLine.text, "bbb"])
    }

    @Test("A key held down keeps typing its character")
    @MainActor
    func keyRepeatKeepsTyping() {
        let keyboard = EchoKeyboard()
        let state = TextEchoState(isKeyDown: keyboard.probe)

        keyboard.press(EchoKeys.codeA)
        press(state, EchoKeys.codeA, EchoKeys.letterA)
        press(state, EchoKeys.codeA, EchoKeys.letterA)
        press(state, EchoKeys.codeA, EchoKeys.letterA)

        #expect(state.lines.map(\.text) == ["aaa"])
    }

    @Test("A fourth line pushes the oldest one off at once")
    @MainActor
    func fourthLineEvictsTheOldest() {
        let state = TextEchoState(isKeyDown: { _ in false })
        let full = String(repeating: "x", count: TextEchoState.maxLineCharacters)

        type(state, full + full + full)
        #expect(state.lines.count == TextEchoState.maxLines)
        let secondLineID = state.lines[1].id

        type(state, "y")

        #expect(state.lines.count == TextEchoState.maxLines)
        #expect(state.lines[0].id == secondLineID)
        #expect(state.lines.last?.text == "y")
    }

    @Test("Clear empties both zones")
    @MainActor
    func test_clear() {
        let state = TextEchoState(isKeyDown: { _ in false })

        type(state, "abc")
        press(state, 0x35, EchoKeys.escape)
        #expect(state.hasKeys)

        state.clear()

        #expect(state.lines.isEmpty)
        #expect(state.commandKeys.isEmpty)
        #expect(state.commandRepeatCount == 0)
        #expect(state.hasKeys == false)
    }
}

// MARK: - Lifecycle

/// Three rules end a line, and they only make sense against each other: the one being written
/// has no clock, the ones above it age out while typing continues, and once typing stops the
/// idle clock clears whatever is still up.
@Suite("TextEchoState Lifecycle Tests")
struct TextEchoStateLifecycleTests {
    /// A line full of 24 characters, so the next keystroke has to start a new one.
    private static let fullLine = String(repeating: "x", count: TextEchoState.maxLineCharacters)

    @Test("The line being written never ages out, however long the typing goes on")
    @MainActor
    func newestLineHasNoLifetime() async {
        let state = TextEchoState(isKeyDown: { _ in false })
        state.lineLifetime = 0.2
        state.idleTimeout = 5

        type(state, "a")
        for _ in 0..<5 {
            try? await Task.sleep(for: .milliseconds(100))
            type(state, "b")
        }

        // Well past the lifetime, and every character is still there.
        #expect(state.lines.map(\.text) == ["abbbbb"])
    }

    @Test("A line ages out once a newer one has taken its place")
    @MainActor
    func replacedLineAgesOut() async {
        let state = TextEchoState(isKeyDown: { _ in false })
        state.lineLifetime = 0.25
        state.idleTimeout = 5

        type(state, Self.fullLine + "a")
        #expect(state.lines.count == 2)

        for _ in 0..<6 {
            try? await Task.sleep(for: .milliseconds(100))
            type(state, "b")
        }

        // The upper line's own countdown ran out while the lower one was still being written.
        #expect(state.lines.map(\.text) == ["abbbbbb"])
    }

    @Test("A single line goes when the typing stops")
    @MainActor
    func idleTakesTheZone() async {
        let state = TextEchoState(isKeyDown: { _ in false })
        state.lineLifetime = 5
        state.idleTimeout = 0.1

        type(state, "hi")
        #expect(state.hasTextLines)

        await waitUntil { state.lines.isEmpty }

        #expect(state.lines.isEmpty)
        #expect(state.hasKeys == false)
    }

    /// With the idle well inside the line lifetime, the idle clock is what clears the zone and
    /// both lines go together — no hole left above text that is still on screen.
    @Test("When typing stops, every line goes at once")
    @MainActor
    func idleTakesEveryLineTogether() async {
        let state = TextEchoState(isKeyDown: { _ in false })
        state.lineLifetime = 1
        state.idleTimeout = 0.25

        type(state, Self.fullLine + "a")
        #expect(state.lines.count == 2)

        // Halfway to the idle: the upper line's countdown is running but nowhere near done.
        try? await Task.sleep(for: .milliseconds(120))
        #expect(state.lines.count == 2)

        await waitUntil { state.lines.isEmpty }
        #expect(state.lines.isEmpty)
    }

    /// Erasing the newest line away hands the line before it back to the typist, and a line
    /// being written has no countdown.
    @Test("A line promoted back by Backspace stops ageing out")
    @MainActor
    func backspacePromotionCancelsTheCountdown() async {
        let state = TextEchoState(isKeyDown: { _ in false })
        state.lineLifetime = 0.2
        state.idleTimeout = 5

        type(state, Self.fullLine + "a")
        #expect(state.lines.count == 2)

        press(state, EchoKeys.codeBackspace, EchoKeys.backspace)
        #expect(state.lines.count == 1)

        try? await Task.sleep(for: .milliseconds(350))

        #expect(state.lines.map(\.text) == [Self.fullLine])
    }

    @Test("Both clocks come from the keyboard settings")
    @MainActor
    func timingsComeFromSettings() {
        let state = TextEchoState(isKeyDown: { _ in false })

        #expect(state.lineLifetime == TextEchoState.defaultLineLifetime)
        #expect(state.idleTimeout == TextEchoState.defaultIdleTimeout)

        state.apply(KeyboardSettings(textLineLifetime: 7, textIdleTimeout: 4))

        #expect(state.lineLifetime == 7)
        #expect(state.idleTimeout == 4)
    }

    /// The settings really drive the zone, not just its properties: an idle shorter than the
    /// default has to take the echo away sooner than the default would.
    @Test("The echo clears on the idle the settings carry")
    @MainActor
    func settingsIdleDrivesClearing() async {
        let state = TextEchoState(
            settings: KeyboardSettings(textLineLifetime: 10, textIdleTimeout: 0.5),
            isKeyDown: { _ in false })

        type(state, "hi")
        #expect(state.hasTextLines)

        await waitUntil { state.lines.isEmpty }

        #expect(state.lines.isEmpty)
    }

    @Test("Timings out of range are held inside it")
    func timingsAreClamped() {
        let tooLong = KeyboardSettings(textLineLifetime: 99, textIdleTimeout: 99)
        let tooShort = KeyboardSettings(textLineLifetime: 0, textIdleTimeout: 0)

        #expect(tooLong.textLineLifetime == KeyboardSettings.textLineLifetimeRange.upperBound)
        #expect(tooLong.textIdleTimeout == KeyboardSettings.textIdleTimeoutRange.upperBound)
        #expect(tooShort.textLineLifetime == KeyboardSettings.textLineLifetimeRange.lowerBound)
        #expect(tooShort.textIdleTimeout == KeyboardSettings.textIdleTimeoutRange.lowerBound)
    }

    /// The two clocks run independently: while typing continues, finished lines thin out one by
    /// one, and once it stops the idle clock clears whatever is left. Keeping the idle the
    /// shorter of the two makes that the usual way the zone goes — but a line whose countdown
    /// ends after the typing stopped is not held back, and may still leave on its own first.
    @Test("The idle is shorter than a line's lifetime by default")
    func idleOutrunsTheLineLifetime() {
        #expect(TextEchoState.defaultIdleTimeout < TextEchoState.defaultLineLifetime)
    }
}

// MARK: - Backspace

@Suite("TextEchoState Backspace Tests")
struct TextEchoStateBackspaceTests {
    @Test("Backspace deletes a character and shows in the command zone")
    @MainActor
    func backspaceDeletesAndShows() {
        let state = TextEchoState(isKeyDown: { _ in false })

        type(state, "abc")
        press(state, EchoKeys.codeBackspace, EchoKeys.backspace)

        #expect(state.lines.map(\.text) == ["ab"])
        #expect(state.commandKeys.map(\.symbol.display) == ["⌫"])
    }

    @Test("Key repeat of Backspace deletes one character per event")
    @MainActor
    func backspaceRepeatDeletesPerEvent() {
        let keyboard = EchoKeyboard()
        let state = TextEchoState(isKeyDown: keyboard.probe)

        type(state, "abcd")
        keyboard.press(EchoKeys.codeBackspace)
        press(state, EchoKeys.codeBackspace, EchoKeys.backspace)
        press(state, EchoKeys.codeBackspace, EchoKeys.backspace)
        press(state, EchoKeys.codeBackspace, EchoKeys.backspace)

        #expect(state.lines.map(\.text) == ["a"])
        // A repeat is not a new press, so the badge stays at one.
        #expect(state.commandRepeatCount == 1)
    }

    @Test("Emptying the newest line lets the next Backspace reach the one before it")
    @MainActor
    func backspaceCrossesIntoThePreviousLine() {
        let state = TextEchoState(isKeyDown: { _ in false })

        type(state, String(repeating: "a", count: TextEchoState.maxLineCharacters) + "b")
        #expect(state.lines.count == 2)

        press(state, EchoKeys.codeBackspace, EchoKeys.backspace)
        #expect(state.lines.count == 1)

        press(state, EchoKeys.codeBackspace, EchoKeys.backspace)
        #expect(state.lines.map(\.text.count) == [TextEchoState.maxLineCharacters - 1])
    }

    @Test("Backspacing past the top brings nothing back")
    @MainActor
    func backspacePastTheTopResurrectsNothing() {
        let state = TextEchoState(isKeyDown: { _ in false })

        type(state, "ab")
        for _ in 0..<6 {
            press(state, EchoKeys.codeBackspace, EchoKeys.backspace)
            release(state, EchoKeys.codeBackspace, EchoKeys.backspace)
        }

        #expect(state.lines.isEmpty)

        type(state, "c")
        #expect(state.lines.map(\.text) == ["c"])
    }

    /// Erasing is someone working, so it holds the zone open exactly as typing does.
    @Test("Erasing restarts the zone's idle clock")
    @MainActor
    func deletingCountsAsActivity() async {
        let state = TextEchoState(isKeyDown: { _ in false })
        state.lineLifetime = 5
        state.idleTimeout = 0.4

        type(state, "abc")
        try? await Task.sleep(for: .milliseconds(250))
        press(state, EchoKeys.codeBackspace, EchoKeys.backspace)
        try? await Task.sleep(for: .milliseconds(250))

        // Half a second after the last character was typed, and the zone is still up because
        // the Backspace reset the clock.
        #expect(state.lines.map(\.text) == ["ab"])

        await waitUntil { state.lines.isEmpty }
        #expect(state.lines.isEmpty)
    }

    @Test("Text the zone has let go of is not reachable by Backspace")
    @MainActor
    func expiredTextIsGoneForGood() async {
        let state = TextEchoState(isKeyDown: { _ in false })
        state.idleTimeout = 0.01

        type(state, "secret")
        await waitUntil { state.lines.isEmpty }

        press(state, EchoKeys.codeBackspace, EchoKeys.backspace)

        #expect(state.lines.isEmpty)
    }

    @Test("⌘⌫ is a command only — it never guesses what to delete")
    @MainActor
    func modifiedBackspaceLeavesTextAlone() {
        let state = TextEchoState(isKeyDown: { _ in false })

        type(state, "abc")
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: EchoKeys.codeCommand, modifiers: .maskCommand),
            symbol: EchoKeys.command)
        press(state, EchoKeys.codeBackspace, EchoKeys.backspace, modifiers: .maskCommand)

        #expect(state.lines.map(\.text) == ["abc"])
        #expect(state.commandKeys.map(\.symbol.display) == ["⌘", "⌫"])
    }

    @Test("Forward Delete is a command and leaves the echo alone")
    @MainActor
    func forwardDeleteLeavesTextAlone() {
        let state = TextEchoState(isKeyDown: { _ in false })

        type(state, "abc")
        press(state, 0x75, EchoKeys.forwardDelete)

        #expect(state.lines.map(\.text) == ["abc"])
        #expect(state.commandKeys.map(\.symbol.display) == ["⌦"])
    }
}

// MARK: - Routing

@Suite("TextEchoState Routing Tests")
struct TextEchoStateRoutingTests {
    @Test("A held command modifier keeps its keys out of the echo")
    @MainActor
    func commandModifierRoutesToCommandZone() {
        let state = TextEchoState(isKeyDown: { _ in false })

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: EchoKeys.codeCommand, modifiers: .maskCommand),
            symbol: EchoKeys.command)
        press(state, EchoKeys.codeV, EchoKeys.letterV, modifiers: .maskCommand)

        #expect(state.lines.isEmpty)
        #expect(state.commandKeys.map(\.symbol.display) == ["⌘", "V"])
    }

    @Test("Unmodified non-text keys land in the command zone")
    @MainActor
    func standaloneNonTextKeysGoToCommandZone() {
        let cases: [(Int64, KeySymbol)] = [
            (0x7B, EchoKeys.arrowLeft),
            (0x35, EchoKeys.escape),
            (0x7A, EchoKeys.functionOne),
        ]

        for (keyCode, symbol) in cases {
            let state = TextEchoState(isKeyDown: { _ in false })
            press(state, keyCode, symbol)

            #expect(state.lines.isEmpty)
            #expect(state.commandKeys.map(\.symbol.display) == [symbol.display])
        }
    }

    /// This mode already splits input the way Shortcuts Only asks for, so the setting has
    /// nothing left to decide here and is dropped on the way in — Backspace included, which
    /// keeps erasing the echo.
    @Test("Shortcuts-only has no effect: the echo and the command zone both keep working")
    @MainActor
    func contentModeHasNoEffect() {
        let state = TextEchoState(
            settings: KeyboardSettings(contentMode: .shortcutsOnly),
            isKeyDown: { _ in false })

        type(state, "abc")
        press(state, EchoKeys.codeBackspace, EchoKeys.backspace)

        #expect(state.contentMode == .allKeys)
        #expect(state.lines.map(\.text) == ["ab"])
        #expect(state.commandKeys.map(\.symbol.display) == ["⌫"])

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: EchoKeys.codeCommand, modifiers: .maskCommand),
            symbol: EchoKeys.command)
        press(state, EchoKeys.codeC, EchoKeys.letterC, modifiers: .maskCommand)

        #expect(state.lines.map(\.text) == ["ab"])
        #expect(state.commandKeys.map(\.symbol.display) == ["⌘", "C"])
    }

    @Test("Switching to shortcuts-only leaves the echo exactly as it stands")
    @MainActor
    func switchingToShortcutsOnlyLeavesEchoAlone() {
        let state = TextEchoState(isKeyDown: { _ in false })

        type(state, "abc")

        state.contentMode = .shortcutsOnly

        #expect(state.contentMode == .allKeys)
        #expect(state.lines.map(\.text) == ["abc"])
    }

    /// The echo routes by what a key produces — ⏎ and ⇥ are text here — so the special-key
    /// filter has nothing to decide and is not allowed to punch holes in typed text.
    @Test("The special-key filter has no effect on the echo")
    @MainActor
    func specialKeyFilterHasNoEffect() {
        var settings = KeyboardSettings()
        settings.filters.showSpecialKeys = false
        let state = TextEchoState(settings: settings, isKeyDown: { _ in false })

        press(state, EchoKeys.codeA, EchoKeys.letterA)
        press(state, EchoKeys.codeReturn, EchoKeys.returnKey)
        press(state, EchoKeys.codeB, EchoKeys.letterB)

        #expect(state.lines.map(\.text) == ["a⏎b"])
        #expect(state.filters.showSpecialKeys)
    }

    /// F-keys land in the command zone here, and the F-key filter must not empty it.
    @Test("The function-key filter has no effect on the command zone")
    @MainActor
    func functionKeyFilterHasNoEffect() {
        var settings = KeyboardSettings()
        settings.filters.showFunctionKeys = false
        let state = TextEchoState(settings: settings, isKeyDown: { _ in false })

        press(state, 0x7A, KeySymbol(id: "f1", display: "F1", isSpecial: true))

        #expect(state.commandKeys.map(\.symbol.display) == ["F1"])
        #expect(state.filters.showFunctionKeys)
    }

    @Test("Turning a category filter off leaves the drawn glyphs where they are")
    @MainActor
    func filterChangeDoesNotReflowDrawnText() {
        let state = TextEchoState(isKeyDown: { _ in false })

        press(state, EchoKeys.codeA, EchoKeys.letterA)
        press(state, EchoKeys.codeReturn, EchoKeys.returnKey)
        press(state, EchoKeys.codeB, EchoKeys.letterB)
        let drawn = state.lines

        var filters = state.filters
        filters.showSpecialKeys = false
        state.filters = filters

        #expect(state.lines == drawn)
    }

    @Test("apply() propagates the settings the echo actually uses")
    @MainActor
    func applySettings() {
        let state = TextEchoState(isKeyDown: { _ in false })

        state.apply(KeyboardSettings(
            contentMode: .shortcutsOnly,
            filters: KeyboardFilterSettings(
                showStandaloneModifiers: false,
                showFunctionKeys: false),
            timeout: 3,
            maxItems: 9))

        #expect(state.contentMode == .allKeys)
        #expect(state.filters.showStandaloneModifiers == false)
        #expect(state.filters.showFunctionKeys)
        #expect(state.keyTimeout == 3)
    }

    @Test("Releasing one modifier side preserves the other")
    @MainActor
    func independentModifierSides() {
        let state = TextEchoState(isKeyDown: { _ in false })
        let leftShift = KeySymbol(id: "shift-left", display: "⇧", isModifier: true)
        let rightShift = KeySymbol(id: "shift-right", display: "⇧", isModifier: true)

        for (keyCode, symbol) in [(0x38, leftShift), (0x3C, rightShift)] {
            state.processEvent(
                KeyEvent(
                    type: .flagsChanged,
                    keyCode: Int64(keyCode),
                    modifiers: .maskShift,
                    modifierIsPressed: true),
                symbol: symbol)
        }
        state.processEvent(
            KeyEvent(
                type: .flagsChanged,
                keyCode: 0x38,
                modifiers: .maskShift,
                modifierIsPressed: false),
            symbol: leftShift)

        #expect(!state.physicallyPressedKeys.contains(leftShift.id))
        #expect(state.physicallyPressedKeys.contains(rightShift.id))
    }

    @Test("A shortcuts-only setting still leaves an unmodified function key in the zone")
    @MainActor
    func functionKeyReachesCommandZoneUnderShortcutsOnly() {
        let state = TextEchoState(
            settings: KeyboardSettings(contentMode: .shortcutsOnly),
            isKeyDown: { _ in false })

        press(state, 0x7A, EchoKeys.functionOne)

        #expect(state.commandKeys.contains { $0.symbol.id == EchoKeys.functionOne.id })
    }
}

// MARK: - Command zone parity

/// The two modes are meant to be indistinguishable in the command zone, so the proof is the
/// same script run through both and compared, rather than each mode's own expectations.
@Suite("Command Zone Parity")
struct CommandZoneParityTests {
    private typealias Script = @MainActor (any KeyEventSink) -> Void

    private static let scripts: [(String, Script)] = [
        ("⌘V pressed three times", { state in
            state.processEvent(
                KeyEvent(type: .flagsChanged, keyCode: EchoKeys.codeCommand, modifiers: .maskCommand),
                symbol: EchoKeys.command)
            for _ in 0..<3 {
                press(state, EchoKeys.codeV, EchoKeys.letterV, modifiers: .maskCommand)
                release(state, EchoKeys.codeV, EchoKeys.letterV, modifiers: .maskCommand)
            }
        }),
        ("a standalone command repeated", { state in
            for _ in 0..<5 {
                press(state, 0x35, EchoKeys.escape)
                release(state, 0x35, EchoKeys.escape)
            }
        }),
        ("a different command after a repeat", { state in
            state.processEvent(
                KeyEvent(type: .flagsChanged, keyCode: EchoKeys.codeCommand, modifiers: .maskCommand),
                symbol: EchoKeys.command)
            for _ in 0..<2 {
                press(state, EchoKeys.codeV, EchoKeys.letterV, modifiers: .maskCommand)
                release(state, EchoKeys.codeV, EchoKeys.letterV, modifiers: .maskCommand)
            }
            press(state, EchoKeys.codeC, EchoKeys.letterC, modifiers: .maskCommand)
        }),
        ("a lone modifier gluing itself to a lingering command", { state in
            for _ in 0..<2 {
                press(state, 0x35, EchoKeys.escape)
                release(state, 0x35, EchoKeys.escape)
            }
            state.processEvent(
                KeyEvent(type: .flagsChanged, keyCode: EchoKeys.codeShift, modifiers: .maskShift),
                symbol: EchoKeys.shift)
        }),
        ("a released shortcut lingering", { state in
            state.processEvent(
                KeyEvent(type: .flagsChanged, keyCode: EchoKeys.codeCommand, modifiers: .maskCommand),
                symbol: EchoKeys.command)
            press(state, EchoKeys.codeC, EchoKeys.letterC, modifiers: .maskCommand)
            release(state, EchoKeys.codeC, EchoKeys.letterC, modifiers: .maskCommand)
            state.processEvent(
                KeyEvent(type: .flagsChanged, keyCode: EchoKeys.codeCommand, modifiers: []),
                symbol: EchoKeys.command)
        }),
        ("Shift held while typing", { state in
            state.processEvent(
                KeyEvent(type: .flagsChanged, keyCode: EchoKeys.codeShift, modifiers: .maskShift),
                symbol: EchoKeys.shift)
            press(state, EchoKeys.codeA, EchoKeys.letterA, modifiers: .maskShift)
        }),
        ("arrows and Escape with nothing held", { state in
            press(state, 0x7B, EchoKeys.arrowLeft)
            release(state, 0x7B, EchoKeys.arrowLeft)
            press(state, 0x35, EchoKeys.escape)
        }),
    ]

    @Test("Both two-zone modes show the same command zone for the same input")
    @MainActor
    func zonesMatch() {
        for (name, script) in Self.scripts {
            let ribbon = HorizontalHistoryState(isKeyDown: { _ in false })
            let echo = TextEchoState(isKeyDown: { _ in false })

            script(ribbon)
            script(echo)

            #expect(
                ribbon.commandKeys.map(\.symbol.id) == echo.commandKeys.map(\.symbol.id),
                "keys differ for \(name)")
            #expect(
                ribbon.commandRepeatCount == echo.commandRepeatCount,
                "repeat count differs for \(name)")
            #expect(
                ribbon.pressedCommandKeyIDs.count == echo.pressedCommandKeyIDs.count,
                "press state differs for \(name)")
        }
    }

    /// The reviewer's probe: hold a letter down so it autorepeats, then press ⌘ without letting
    /// go. Those repeats are the letter still typing, not a shortcut — a "⌘A" here is a command
    /// the user never pressed, and the audience would see it appear out of nowhere.
    @Test("A modifier joining a held key invents no shortcut in either mode")
    @MainActor
    func modifierJoiningAHeldKeyIsNotAShortcut() {
        let keyboard = EchoKeyboard()
        let ribbon = HorizontalHistoryState(isKeyDown: keyboard.probe)
        let echo = TextEchoState(isKeyDown: keyboard.probe)

        keyboard.press(EchoKeys.codeA)
        for state in [ribbon as any KeyEventSink, echo as any KeyEventSink] {
            press(state, EchoKeys.codeA, EchoKeys.letterA)
            state.processEvent(
                KeyEvent(
                    type: .flagsChanged,
                    keyCode: EchoKeys.codeCommand,
                    modifiers: .maskCommand),
                symbol: EchoKeys.command)
            press(state, EchoKeys.codeA, EchoKeys.letterA, modifiers: .maskCommand)
            press(state, EchoKeys.codeA, EchoKeys.letterA, modifiers: .maskCommand)
        }

        #expect(ribbon.commandKeys.map(\.symbol.display) == ["⌘"])
        #expect(echo.commandKeys.map(\.symbol.display) == ["⌘"])
        // The echo keeps typing while the key is held; the ribbon shows one keycap per press.
        #expect(echo.lines.map(\.text) == ["a"])
        #expect(ribbon.ribbonKeys.map(\.display) == ["a"])
    }

    /// Once the key is really let go, the next press with ⌘ still held is a shortcut again.
    @Test("Releasing the held key restores the shortcut in either mode")
    @MainActor
    func releasingTheHeldKeyRestoresTheShortcut() {
        let keyboard = EchoKeyboard()
        let ribbon = HorizontalHistoryState(isKeyDown: keyboard.probe)
        let echo = TextEchoState(isKeyDown: keyboard.probe)

        for state in [ribbon as any KeyEventSink, echo as any KeyEventSink] {
            keyboard.press(EchoKeys.codeA)
            press(state, EchoKeys.codeA, EchoKeys.letterA)
            state.processEvent(
                KeyEvent(
                    type: .flagsChanged,
                    keyCode: EchoKeys.codeCommand,
                    modifiers: .maskCommand),
                symbol: EchoKeys.command)
            keyboard.release(EchoKeys.codeA)
            release(state, EchoKeys.codeA, EchoKeys.letterA, modifiers: .maskCommand)
            keyboard.press(EchoKeys.codeA)
            press(state, EchoKeys.codeA, EchoKeys.letterA, modifiers: .maskCommand)
            keyboard.release(EchoKeys.codeA)
        }

        #expect(ribbon.commandKeys.map(\.symbol.display) == ["⌘", "A"])
        #expect(echo.commandKeys.map(\.symbol.display) == ["⌘", "A"])
        #expect(ribbon.commandRepeatCount == echo.commandRepeatCount)
    }

    /// A key up can go missing — the tap is disabled, the overlay is toggled off, the app
    /// switches. The probe is the only way back: without it the key stays marked as typing and
    /// swallows every later shortcut built on it.
    @Test("A missed key up does not swallow the next shortcut")
    @MainActor
    func missedKeyUpDoesNotSwallowLaterShortcuts() {
        let keyboard = EchoKeyboard()
        let echo = TextEchoState(isKeyDown: keyboard.probe)

        keyboard.press(EchoKeys.codeA)
        press(echo, EchoKeys.codeA, EchoKeys.letterA)
        // The key really came up, but the event never arrived.
        keyboard.release(EchoKeys.codeA)

        echo.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: EchoKeys.codeCommand, modifiers: .maskCommand),
            symbol: EchoKeys.command)
        press(echo, EchoKeys.codeA, EchoKeys.letterA, modifiers: .maskCommand)

        #expect(echo.commandKeys.map(\.symbol.display) == ["⌘", "A"])
    }

    @Test("Key repeat inflates neither mode's badge")
    @MainActor
    func heldCommandKeyDoesNotCountRepeats() {
        let keyboard = EchoKeyboard()
        let ribbon = HorizontalHistoryState(isKeyDown: keyboard.probe)
        let echo = TextEchoState(isKeyDown: keyboard.probe)

        keyboard.press(0x35)
        for state in [ribbon as any KeyEventSink, echo as any KeyEventSink] {
            press(state, 0x35, EchoKeys.escape)
            press(state, 0x35, EchoKeys.escape)
            press(state, 0x35, EchoKeys.escape)
        }

        #expect(ribbon.commandRepeatCount == 1)
        #expect(echo.commandRepeatCount == 1)
    }
}

// MARK: - Helpers

@MainActor
private func press(
    _ state: any KeyEventSink,
    _ keyCode: Int64,
    _ symbol: KeySymbol,
    modifiers: CGEventFlags = [])
{
    state.processEvent(
        KeyEvent(type: .keyDown, keyCode: keyCode, modifiers: modifiers),
        symbol: symbol)
}

@MainActor
private func release(
    _ state: any KeyEventSink,
    _ keyCode: Int64,
    _ symbol: KeySymbol,
    modifiers: CGEventFlags = [])
{
    state.processEvent(
        KeyEvent(type: .keyUp, keyCode: keyCode, modifiers: modifiers),
        symbol: symbol)
}

/// Types `text` as a run of unmodified presses, one keycode per character.
@MainActor
private func type(_ state: TextEchoState, _ text: String) {
    for character in text {
        let symbol: KeySymbol = switch character {
        case " ": EchoKeys.space
        case "\n": EchoKeys.returnKey
        case "\t": EchoKeys.tab
        default: KeySymbol(id: "key-\(character)", display: String(character))
        }
        let keyCode = Int64(character.asciiValue ?? 0)
        press(state, keyCode, symbol)
        release(state, keyCode, symbol)
    }
}

/// The deadline is a guard against hanging, not a measurement: a passing test leaves on the
/// first check that succeeds. It has to clear the longest wait here — an idle the settings
/// clamp to 0.5s — by enough that a loaded CI runner, where MainActor work queues behind other
/// tests, still gets there.
@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while !condition(), clock.now < deadline {
        try? await clock.sleep(for: .milliseconds(10))
    }
}
