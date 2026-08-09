import CoreGraphics
import Foundation
import Testing
@testable import KeypressCore

// MARK: - RibbonKeyboard

/// Stands in for the system key-state probe so tests can hold keys down.
private final class RibbonKeyboard: @unchecked Sendable {
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

// MARK: - Keys

private enum Keys {
    static let letterA = KeySymbol(id: "key-a", display: "A")
    static let letterB = KeySymbol(id: "key-b", display: "B")
    static let letterC = KeySymbol(id: "key-c", display: "C")
    static let letterL = KeySymbol(id: "key-l", display: "L")
    static let letterV = KeySymbol(id: "key-v", display: "V")
    static let digit4 = KeySymbol(id: "key-4", display: "4")
    static let space = KeySymbol(id: "space", display: "␣", isSpecial: true)
    static let returnKey = KeySymbol(id: "return", display: "⏎", isSpecial: true)
    static let tab = KeySymbol(id: "tab", display: "⇥", isSpecial: true)
    static let backspace = KeySymbol(id: "delete", display: "⌫", isSpecial: true)
    static let escape = KeySymbol(id: "escape", display: "ESC", isSpecial: true)
    static let arrowLeft = KeySymbol(id: "arrow-left", display: "←", isSpecial: true)
    static let functionOne = KeySymbol(id: "f1", display: "F1", isSpecial: true)
    static let command = KeySymbol(id: "command-left", display: "⌘", isModifier: true)
    static let shift = KeySymbol(id: "shift-left", display: "⇧", isModifier: true)
    static let control = KeySymbol(id: "control-left", display: "⌃", isModifier: true)

    static let codeA: Int64 = 0x00
    static let codeB: Int64 = 0x0B
    static let codeC: Int64 = 0x08
    static let codeL: Int64 = 0x25
    static let codeV: Int64 = 0x09
    static let codeSpace: Int64 = 0x31
    static let codeCommand: Int64 = 0x37
    static let codeShift: Int64 = 0x38
    static let codeControl: Int64 = 0x3B
}

// MARK: - HorizontalHistoryStateTests

@Suite("HorizontalHistoryState Ribbon Tests")
struct HorizontalHistoryStateRibbonTests {
    @Test("Initial state is empty")
    @MainActor
    func initialState() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        #expect(state.ribbonKeys.isEmpty)
        #expect(state.commandKeys.isEmpty)
        #expect(state.hasKeys == false)
        #expect(state.hasRibbonKeys == false)
        #expect(state.hasCommandKeys == false)
        #expect(state.latestRibbonKeyID == nil)
    }

    @Test("Letters, space, enter and tab keep press order in the ribbon")
    @MainActor
    func chronologicalOrder() {
        let state = HorizontalHistoryState(
            settings: KeyboardSettings(maxItems: 12),
            isKeyDown: { _ in false })

        press(state, Keys.codeA, Keys.letterA)
        press(state, Keys.codeSpace, Keys.space)
        press(state, Keys.codeB, Keys.letterB)
        press(state, 0x24, Keys.returnKey)
        press(state, 0x30, Keys.tab)
        press(state, Keys.codeC, Keys.letterC)

        #expect(state.ribbonKeys.map(\.display) == ["a", "␣", "b", "⏎", "⇥", "c"])
        #expect(state.commandKeys.isEmpty)
    }

    @Test("Every press of the same letter creates a new entry")
    @MainActor
    func repeatedLetterCreatesNewEntries() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        press(state, Keys.codeL, Keys.letterL)
        press(state, Keys.codeL, Keys.letterL)

        #expect(state.ribbonKeys.count == 2)
        #expect(state.ribbonKeys[0].id != state.ribbonKeys[1].id)
        #expect(state.ribbonKeys.map(\.display) == ["l", "l"])
    }

    @Test("Every press of Space creates a new entry")
    @MainActor
    func repeatedSpaceCreatesNewEntries() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        press(state, Keys.codeA, Keys.letterA)
        press(state, Keys.codeSpace, Keys.space)
        press(state, Keys.codeB, Keys.letterB)
        press(state, Keys.codeSpace, Keys.space)

        #expect(state.ribbonKeys.map(\.display) == ["a", "␣", "b", "␣"])
        #expect(Set(state.ribbonKeys.map(\.id)).count == 4)
    }

    @Test("Letters are lowercase without Shift or CapsLock")
    @MainActor
    func lowercaseByDefault() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        press(state, Keys.codeA, Keys.letterA)

        #expect(state.ribbonKeys.map(\.display) == ["a"])
        #expect(state.ribbonKeys.first?.symbol.display == "A")
    }

    @Test("Held Shift uppercases ribbon letters")
    @MainActor
    func shiftUppercasesRibbonLetter() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: Keys.codeShift, modifiers: .maskShift),
            symbol: Keys.shift)
        press(state, Keys.codeA, Keys.letterA, modifiers: .maskShift)

        #expect(state.ribbonKeys.map(\.display) == ["A"])
    }

    @Test("CapsLock flag uppercases ribbon letters")
    @MainActor
    func capsLockUppercasesRibbonLetter() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        press(state, Keys.codeA, Keys.letterA, modifiers: .maskAlphaShift)

        #expect(state.ribbonKeys.map(\.display) == ["A"])
    }

    @Test("Latest ribbon key is the newest entry until another key arrives")
    @MainActor
    func latestFlagMovesWithTheNewestKey() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        press(state, Keys.codeSpace, Keys.space)
        #expect(state.latestRibbonKeyID == state.ribbonKeys.last?.id)

        press(state, Keys.codeA, Keys.letterA)
        #expect(state.latestRibbonKeyID == state.ribbonKeys.last?.id)
        #expect(state.ribbonKeys.first?.id != state.latestRibbonKeyID)
    }

    @Test("A command key clears the latest ribbon key")
    @MainActor
    func latestFlagClearedByCommandKey() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        press(state, Keys.codeSpace, Keys.space)
        #expect(state.latestRibbonKeyID != nil)

        press(state, 0x7B, Keys.arrowLeft)

        #expect(state.latestRibbonKeyID == nil)
        #expect(state.ribbonKeys.map(\.display) == ["␣"])
        #expect(state.commandKeys.map(\.symbol.display) == ["←"])
    }

    @Test("Press state is scoped to the entry the press created")
    @MainActor
    func pressedRibbonKeyIsPerInstance() {
        let keyboard = RibbonKeyboard()
        let state = HorizontalHistoryState(isKeyDown: keyboard.probe)

        keyboard.press(Keys.codeA)
        press(state, Keys.codeA, Keys.letterA)
        keyboard.release(Keys.codeA)
        release(state, Keys.codeA, Keys.letterA)

        keyboard.press(Keys.codeA)
        press(state, Keys.codeA, Keys.letterA)

        #expect(state.ribbonKeys.count == 2)
        #expect(state.pressedRibbonKeyIDs == [state.ribbonKeys[1].id])
    }

    @Test("Key repeat while held does not add a second keycap")
    @MainActor
    func keyRepeatDoesNotDuplicateRibbonKey() {
        let keyboard = RibbonKeyboard()
        let state = HorizontalHistoryState(isKeyDown: keyboard.probe)

        keyboard.press(Keys.codeA)
        press(state, Keys.codeA, Keys.letterA)
        press(state, Keys.codeA, Keys.letterA)
        press(state, Keys.codeA, Keys.letterA)

        #expect(state.ribbonKeys.count == 1)
    }

    @Test("Ribbon evicts the oldest entry at maxItems")
    @MainActor
    func evictionRemovesOldestEntry() {
        let state = HorizontalHistoryState(
            settings: KeyboardSettings(maxItems: 3),
            isKeyDown: { _ in false })

        for (index, symbol) in [Keys.letterA, Keys.letterB, Keys.letterC, Keys.letterL, Keys.letterV].enumerated() {
            press(state, Int64(index), symbol)
        }

        #expect(state.ribbonKeys.map(\.display) == ["c", "l", "v"])
        #expect(state.latestRibbonKeyID == state.ribbonKeys.last?.id)
    }

    @Test("A held key evicted from the ribbon never returns on key repeat")
    @MainActor
    func evictedHeldKeyDoesNotReturn() {
        let keyboard = RibbonKeyboard()
        let state = HorizontalHistoryState(
            settings: KeyboardSettings(maxItems: 3),
            isKeyDown: keyboard.probe)

        keyboard.press(Keys.codeA)
        press(state, Keys.codeA, Keys.letterA)
        press(state, Keys.codeB, Keys.letterB)
        press(state, Keys.codeC, Keys.letterC)
        press(state, Keys.codeL, Keys.letterL)
        #expect(state.ribbonKeys.map(\.display) == ["b", "c", "l"])

        press(state, Keys.codeA, Keys.letterA)
        press(state, Keys.codeA, Keys.letterA)

        #expect(state.ribbonKeys.map(\.display) == ["b", "c", "l"])
        #expect(state.pressedRibbonKeyIDs.isEmpty)
    }

    @Test("maxItems is clamped to the supported range")
    @MainActor
    func maxItemsIsClamped() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        state.maxItems = 100
        #expect(state.maxItems == 12)

        state.maxItems = 1
        #expect(state.maxItems == 3)
    }

    @Test("Each ribbon entry expires on its own timeout")
    @MainActor
    func ribbonEntryExpires() async {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })
        state.keyTimeout = 0.01

        press(state, Keys.codeA, Keys.letterA)
        #expect(state.hasRibbonKeys)

        await waitUntil { state.ribbonKeys.isEmpty }

        #expect(state.ribbonKeys.isEmpty)
        #expect(state.latestRibbonKeyID == nil)
        #expect(state.hasKeys == false)
    }

    @Test("Clear empties both zones")
    @MainActor
    func test_clear() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        press(state, Keys.codeA, Keys.letterA)
        press(state, 0x35, Keys.escape)
        #expect(state.hasKeys)

        state.clear()

        #expect(state.ribbonKeys.isEmpty)
        #expect(state.commandKeys.isEmpty)
        #expect(state.latestRibbonKeyID == nil)
        #expect(state.pressedRibbonKeyIDs.isEmpty)
        #expect(state.commandRepeatCount == 0)
        #expect(state.hasKeys == false)
    }
}

// MARK: - HorizontalHistoryStateRoutingTests

@Suite("HorizontalHistoryState Routing Tests")
struct HorizontalHistoryStateRoutingTests {
    @Test("A held command modifier routes every key to the command zone")
    @MainActor
    func commandModifierRoutesToCommandZone() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: Keys.codeCommand, modifiers: .maskCommand),
            symbol: Keys.command)
        press(state, Keys.codeC, Keys.letterC, modifiers: .maskCommand)

        #expect(state.ribbonKeys.isEmpty)
        #expect(state.commandKeys.map(\.symbol.display) == ["⌘", "C"])
    }

    @Test("Shift alone keeps input in the ribbon and shows ⇧ in the command zone")
    @MainActor
    func shiftOnlyKeepsRibbonRouting() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: Keys.codeShift, modifiers: .maskShift),
            symbol: Keys.shift)
        press(state, Keys.codeA, Keys.letterA, modifiers: .maskShift)

        #expect(state.ribbonKeys.map(\.display) == ["A"])
        #expect(state.commandKeys.map(\.symbol.display) == ["⇧"])
    }

    @Test("A combo started from Shift lands entirely in the command zone")
    @MainActor
    func comboStartedFromShift() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: Keys.codeShift, modifiers: .maskShift),
            symbol: Keys.shift)
        state.processEvent(
            KeyEvent(
                type: .flagsChanged,
                keyCode: Keys.codeControl,
                modifiers: [.maskShift, .maskControl]),
            symbol: Keys.control)
        state.processEvent(
            KeyEvent(
                type: .flagsChanged,
                keyCode: Keys.codeCommand,
                modifiers: [.maskShift, .maskControl, .maskCommand]),
            symbol: Keys.command)
        press(
            state,
            0x15,
            Keys.digit4,
            modifiers: [.maskShift, .maskControl, .maskCommand])

        #expect(state.ribbonKeys.isEmpty)
        #expect(state.commandKeys.map(\.symbol.display) == ["⇧", "⌃", "⌘", "4"])
    }

    @Test("Unmodified non-text keys land in the command zone")
    @MainActor
    func standaloneNonTextKeysGoToCommandZone() {
        let cases: [(Int64, KeySymbol)] = [
            (0x7B, Keys.arrowLeft),
            (0x35, Keys.escape),
            (0x7A, Keys.functionOne),
            (0x33, Keys.backspace),
        ]

        for (keyCode, symbol) in cases {
            let state = HorizontalHistoryState(isKeyDown: { _ in false })
            press(state, keyCode, symbol)

            #expect(state.ribbonKeys.isEmpty)
            #expect(state.commandKeys.map(\.symbol.display) == [symbol.display])
        }
    }

    @Test("Key repeat of a held ribbon key does not become a command")
    @MainActor
    func autorepeatOfHeldRibbonKeyIsNotACommand() {
        let keyboard = RibbonKeyboard()
        let state = HorizontalHistoryState(isKeyDown: keyboard.probe)

        keyboard.press(Keys.codeA)
        press(state, Keys.codeA, Keys.letterA)
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: Keys.codeCommand, modifiers: .maskCommand),
            symbol: Keys.command)
        press(state, Keys.codeA, Keys.letterA, modifiers: .maskCommand)

        #expect(state.ribbonKeys.map(\.display) == ["a"])
        #expect(state.commandKeys.map(\.symbol.display) == ["⌘"])

        keyboard.release(Keys.codeA)
        release(state, Keys.codeA, Keys.letterA, modifiers: .maskCommand)
        keyboard.press(Keys.codeA)
        press(state, Keys.codeA, Keys.letterA, modifiers: .maskCommand)

        #expect(state.ribbonKeys.map(\.display) == ["a"])
        #expect(state.commandKeys.map(\.symbol.display) == ["⌘", "A"])
        #expect(state.commandRepeatCount == 1)
    }

    @Test("Backspace never erases the ribbon")
    @MainActor
    func backspaceLeavesRibbonIntact() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        press(state, Keys.codeA, Keys.letterA)
        press(state, Keys.codeB, Keys.letterB)
        press(state, 0x33, Keys.backspace)

        #expect(state.ribbonKeys.map(\.display) == ["a", "b"])
        #expect(state.commandKeys.map(\.symbol.display) == ["⌫"])
    }

    @Test("Shortcuts-only mode keeps the ribbon empty and the command zone working")
    @MainActor
    func shortcutsOnlyKeepsRibbonEmpty() {
        let state = HorizontalHistoryState(
            settings: KeyboardSettings(contentMode: .shortcutsOnly),
            isKeyDown: { _ in false })

        press(state, Keys.codeA, Keys.letterA)
        press(state, Keys.codeSpace, Keys.space)

        #expect(state.ribbonKeys.isEmpty)

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: Keys.codeCommand, modifiers: .maskCommand),
            symbol: Keys.command)
        press(state, Keys.codeC, Keys.letterC, modifiers: .maskCommand)

        #expect(state.ribbonKeys.isEmpty)
        #expect(state.commandKeys.map(\.symbol.display) == ["⌘", "C"])
    }

    @Test("Switching to shortcuts-only clears the ribbon")
    @MainActor
    func switchingToShortcutsOnlyClearsRibbon() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        press(state, Keys.codeA, Keys.letterA)
        #expect(state.hasRibbonKeys)

        state.contentMode = .shortcutsOnly

        #expect(state.ribbonKeys.isEmpty)
        #expect(state.latestRibbonKeyID == nil)
    }
}

// MARK: - HorizontalHistoryStateCommandZoneTests

@Suite("HorizontalHistoryState Command Zone Tests")
struct HorizontalHistoryStateCommandZoneTests {
    @Test("Repeating the same shortcut increments the repeat counter")
    @MainActor
    func repeatCounterIncrements() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: Keys.codeCommand, modifiers: .maskCommand),
            symbol: Keys.command)
        for _ in 0..<3 {
            press(state, Keys.codeV, Keys.letterV, modifiers: .maskCommand)
            release(state, Keys.codeV, Keys.letterV, modifiers: .maskCommand)
        }

        #expect(state.commandKeys.map(\.symbol.display) == ["⌘", "V"])
        #expect(state.commandRepeatCount == 3)
        #expect(state.commandRepeatKeyID == state.commandKeys.last?.id)
    }

    @Test("Repeating a standalone command key increments the repeat counter")
    @MainActor
    func standaloneCommandRepeatCounter() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        for _ in 0..<5 {
            press(state, 0x33, Keys.backspace)
            release(state, 0x33, Keys.backspace)
        }

        #expect(state.commandKeys.map(\.symbol.display) == ["⌫"])
        #expect(state.commandRepeatCount == 5)
    }

    @Test("A different command resets the repeat counter")
    @MainActor
    func repeatCounterResetsOnDifferentCommand() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: Keys.codeCommand, modifiers: .maskCommand),
            symbol: Keys.command)
        for _ in 0..<2 {
            press(state, Keys.codeV, Keys.letterV, modifiers: .maskCommand)
            release(state, Keys.codeV, Keys.letterV, modifiers: .maskCommand)
        }
        #expect(state.commandRepeatCount == 2)

        press(state, Keys.codeC, Keys.letterC, modifiers: .maskCommand)

        #expect(state.commandKeys.map(\.symbol.display) == ["⌘", "C"])
        #expect(state.commandRepeatCount == 1)
    }

    @Test("An expired command restarts the repeat counter")
    @MainActor
    func repeatCounterResetsAfterExpiry() async {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })
        state.keyTimeout = 0.01

        press(state, 0x35, Keys.escape)
        release(state, 0x35, Keys.escape)
        #expect(state.commandRepeatCount == 1)

        await waitUntil { state.commandKeys.isEmpty }
        #expect(state.commandRepeatCount == 0)

        press(state, 0x35, Keys.escape)

        #expect(state.commandRepeatCount == 1)
    }

    @Test("Key repeat while held does not increment the repeat counter")
    @MainActor
    func heldCommandKeyDoesNotCountRepeats() {
        let keyboard = RibbonKeyboard()
        let state = HorizontalHistoryState(isKeyDown: keyboard.probe)

        keyboard.press(0x33)
        press(state, 0x33, Keys.backspace)
        press(state, 0x33, Keys.backspace)
        press(state, 0x33, Keys.backspace)

        #expect(state.commandKeys.map(\.symbol.display) == ["⌫"])
        #expect(state.commandRepeatCount == 1)
    }

    @Test("A modifier pressed alone silences the badge of a lingering command")
    @MainActor
    func loneModifierSilencesStaleBadge() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        for _ in 0..<2 {
            press(state, 0x33, Keys.backspace)
            release(state, 0x33, Keys.backspace)
        }
        #expect(state.commandRepeatCount == 2)

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: Keys.codeShift, modifiers: .maskShift),
            symbol: Keys.shift)

        #expect(state.commandKeys.map(\.symbol.display) == ["⇧", "⌫"])
        #expect(state.commandRepeatCount == 1)
    }

    @Test("Command zone press state uses entry ids, not symbol ids")
    @MainActor
    func pressedCommandKeyIDsUseEntryIDs() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: Keys.codeCommand, modifiers: .maskCommand),
            symbol: Keys.command)
        press(state, 0x33, Keys.backspace, modifiers: .maskCommand)

        #expect(state.commandKeys.count == 2)
        #expect(state.pressedCommandKeyIDs == Set(state.commandKeys.map(\.id)))

        release(state, 0x33, Keys.backspace, modifiers: .maskCommand)

        #expect(state.pressedCommandKeyIDs == [state.commandKeys[0].id])
    }

    @Test("A released command lingers until the timeout")
    @MainActor
    func commandLingersAfterRelease() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: Keys.codeCommand, modifiers: .maskCommand),
            symbol: Keys.command)
        press(state, Keys.codeC, Keys.letterC, modifiers: .maskCommand)
        release(state, Keys.codeC, Keys.letterC, modifiers: .maskCommand)
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: Keys.codeCommand, modifiers: []),
            symbol: Keys.command)

        #expect(state.commandKeys.map(\.symbol.display) == ["⌘", "C"])
    }
}

// MARK: - HorizontalHistoryStateFilterTests

@Suite("HorizontalHistoryState Filter Tests")
struct HorizontalHistoryStateFilterTests {
    @Test("showFunctionKeys=false hides F-keys from both zones")
    @MainActor
    func functionKeysFiltered() {
        var settings = KeyboardSettings()
        settings.filters.showFunctionKeys = false
        let state = HorizontalHistoryState(settings: settings, isKeyDown: { _ in false })

        press(state, 0x7A, Keys.functionOne)

        #expect(state.ribbonKeys.isEmpty)
        #expect(state.commandKeys.isEmpty)
    }

    @Test("showSpecialKeys=false hides special keys from both zones")
    @MainActor
    func specialKeysFiltered() {
        var settings = KeyboardSettings()
        settings.filters.showSpecialKeys = false
        let state = HorizontalHistoryState(settings: settings, isKeyDown: { _ in false })

        press(state, 0x35, Keys.escape)
        press(state, Keys.codeSpace, Keys.space)
        press(state, Keys.codeA, Keys.letterA)

        #expect(state.commandKeys.isEmpty)
        #expect(state.ribbonKeys.map(\.display) == ["a"])
    }

    @Test("showStandaloneModifiers=false hides a held modifier but keeps ribbon casing")
    @MainActor
    func standaloneModifiersFiltered() {
        var settings = KeyboardSettings()
        settings.filters.showStandaloneModifiers = false
        let state = HorizontalHistoryState(settings: settings, isKeyDown: { _ in false })

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: Keys.codeShift, modifiers: .maskShift),
            symbol: Keys.shift)
        press(state, Keys.codeA, Keys.letterA, modifiers: .maskShift)

        #expect(state.commandKeys.isEmpty)
        #expect(state.ribbonKeys.map(\.display) == ["A"])
    }

    @Test("Turning a filter off removes matching ribbon entries and keeps the order")
    @MainActor
    func filterChangeReconcilesRibbon() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        press(state, Keys.codeA, Keys.letterA)
        press(state, Keys.codeSpace, Keys.space)
        press(state, Keys.codeB, Keys.letterB)
        #expect(state.ribbonKeys.map(\.display) == ["a", "␣", "b"])

        var filters = state.filters
        filters.showSpecialKeys = false
        state.filters = filters

        #expect(state.ribbonKeys.map(\.display) == ["a", "b"])
    }

    @Test("apply() propagates keyboard settings to both zones")
    @MainActor
    func applySettings() {
        let state = HorizontalHistoryState(isKeyDown: { _ in false })

        state.apply(KeyboardSettings(
            contentMode: .shortcutsOnly,
            filters: KeyboardFilterSettings(showFunctionKeys: false),
            timeout: 3,
            maxItems: 9))

        #expect(state.contentMode == .shortcutsOnly)
        #expect(state.filters.showFunctionKeys == false)
        #expect(state.keyTimeout == 3)
        #expect(state.maxItems == 9)
    }
}

// MARK: - Helpers

@MainActor
private func press(
    _ state: HorizontalHistoryState,
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
    _ state: HorizontalHistoryState,
    _ keyCode: Int64,
    _ symbol: KeySymbol,
    modifiers: CGEventFlags = [])
{
    state.processEvent(
        KeyEvent(type: .keyUp, keyCode: keyCode, modifiers: modifiers),
        symbol: symbol)
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(1))
    while !condition(), clock.now < deadline {
        try? await clock.sleep(for: .milliseconds(10))
    }
}
