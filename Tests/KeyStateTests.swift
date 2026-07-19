import CoreGraphics
import Foundation
import Testing
@testable import KeypressCore

@Suite("KeyState Tests")
struct KeyStateTests {
    @Test("Initial state is empty")
    @MainActor
    func initialState() {
        let state = KeyState()
        #expect(state.pressedKeys.isEmpty)
        #expect(state.hasKeys == false)
    }

    @Test("KeyDown adds key to state")
    @MainActor
    func keyDownAddsKey() {
        let state = KeyState()
        let symbol = KeySymbol(id: "key-a", display: "A")
        let event = KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: [])

        state.processEvent(event, symbol: symbol)

        #expect(state.pressedKeys.count == 1)
        #expect(state.pressedKeys.first?.symbol.display == "A")
        #expect(state.hasKeys == true)
    }

    @Test("Modifier keyDown adds modifier")
    @MainActor
    func modifierKeyDown() {
        let state = KeyState()
        let symbol = KeySymbol(id: "command", display: "⌘", isModifier: true)
        let event = KeyEvent(type: .keyDown, keyCode: 0x37, modifiers: .maskCommand)

        state.processEvent(event, symbol: symbol)

        #expect(state.pressedKeys.count == 1)
        #expect(state.pressedKeys.first?.symbol.isModifier == true)
    }

    @Test("Modifier keyUp removes modifier immediately")
    @MainActor
    func modifierKeyUpRemoves() {
        let state = KeyState()
        let symbol = KeySymbol(id: "command", display: "⌘", isModifier: true)

        state.processEvent(KeyEvent(type: .keyDown, keyCode: 0x37, modifiers: .maskCommand), symbol: symbol)
        #expect(state.pressedKeys.count == 1)

        state.processEvent(KeyEvent(type: .keyUp, keyCode: 0x37, modifiers: []), symbol: symbol)
        #expect(state.pressedKeys.isEmpty)
    }

    @Test("Regular key stays after keyUp (waits for timeout)")
    @MainActor
    func regularKeyStaysAfterKeyUp() {
        let state = KeyState()
        let symbol = KeySymbol(id: "key-a", display: "A")

        state.processEvent(KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []), symbol: symbol)
        state.processEvent(KeyEvent(type: .keyUp, keyCode: 0x00, modifiers: []), symbol: symbol)

        // Key should still be there (waiting for timeout)
        #expect(state.pressedKeys.count == 1)
    }

    @Test("Duplicate modifier keyDown does not add duplicate")
    @MainActor
    func noDuplicateModifiers() {
        let state = KeyState()
        let symbol = KeySymbol(id: "command", display: "⌘", isModifier: true)
        let event = KeyEvent(type: .keyDown, keyCode: 0x37, modifiers: .maskCommand)

        state.processEvent(event, symbol: symbol)
        state.processEvent(event, symbol: symbol)

        // Modifiers should not duplicate
        #expect(state.pressedKeys.count == 1)
    }

    @Test("Regular keys allow duplicates for typing (hello → 5 keys)")
    @MainActor
    func regularKeysAllowDuplicates() {
        let state = KeyState()

        // Type "hello" - each keypress is unique
        let hSymbol = KeySymbol(id: "key-4", display: "H")
        let eSymbol = KeySymbol(id: "key-14", display: "E")
        let lSymbol = KeySymbol(id: "key-37", display: "L")
        let oSymbol = KeySymbol(id: "key-31", display: "O")

        state.processEvent(KeyEvent(type: .keyDown, keyCode: 0x04, modifiers: []), symbol: hSymbol)
        state.processEvent(KeyEvent(type: .keyDown, keyCode: 0x0E, modifiers: []), symbol: eSymbol)
        state.processEvent(KeyEvent(type: .keyDown, keyCode: 0x25, modifiers: []), symbol: lSymbol)
        state.processEvent(KeyEvent(type: .keyDown, keyCode: 0x25, modifiers: []), symbol: lSymbol)
        state.processEvent(KeyEvent(type: .keyDown, keyCode: 0x1F, modifiers: []), symbol: oSymbol)

        // All 5 keys should be present (including both 'l's)
        #expect(state.pressedKeys.count == 5)
    }

    @Test("Clear removes all keys")
    @MainActor
    func test_clear() {
        let state = KeyState()

        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
            symbol: KeySymbol(id: "key-a", display: "A"))
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x37, modifiers: .maskCommand),
            symbol: KeySymbol(id: "command", display: "⌘", isModifier: true))

        #expect(state.pressedKeys.count == 2)

        state.clear()

        #expect(state.pressedKeys.isEmpty)
    }

    @Test("Modifiers are sorted before regular keys")
    @MainActor
    func modifiersSortedFirst() {
        let state = KeyState()

        // Add regular key first
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
            symbol: KeySymbol(id: "key-a", display: "A"))

        // Add modifier second
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x37, modifiers: .maskCommand),
            symbol: KeySymbol(id: "command", display: "⌘", isModifier: true))

        #expect(state.pressedKeys.count == 2)
        #expect(state.pressedKeys[0].symbol.isModifier == true)
        #expect(state.pressedKeys[1].symbol.isModifier == false)
    }

    @Test("Max 6 keys displayed")
    @MainActor
    func maxKeysLimit() {
        let state = KeyState()

        // Add 8 keys
        for i in 0..<8 {
            let symbol = KeySymbol(id: "key-\(i)", display: "\(i)")
            state.processEvent(
                KeyEvent(type: .keyDown, keyCode: Int64(i), modifiers: []),
                symbol: symbol)
        }

        #expect(state.pressedKeys.count == state.maxDisplayedKeys)
        #expect(state.pressedKeys.count == 6)
    }

    @Test("Modifiers prioritized when at max keys")
    @MainActor
    func modifiersPrioritizedAtMax() {
        let state = KeyState()

        // Add 5 regular keys
        for i in 0..<5 {
            let symbol = KeySymbol(id: "key-\(i)", display: "\(i)")
            state.processEvent(
                KeyEvent(type: .keyDown, keyCode: Int64(i), modifiers: []),
                symbol: symbol)
        }

        // Add 3 modifiers
        let modifiers = [
            KeySymbol(id: "command", display: "⌘", isModifier: true),
            KeySymbol(id: "shift", display: "⇧", isModifier: true),
            KeySymbol(id: "option", display: "⌥", isModifier: true),
        ]

        for (i, mod) in modifiers.enumerated() {
            state.processEvent(
                KeyEvent(type: .keyDown, keyCode: Int64(0x37 + i), modifiers: []),
                symbol: mod)
        }

        #expect(state.pressedKeys.count == 6)

        // All 3 modifiers should be present
        let modifierCount = state.pressedKeys.count(where: { $0.symbol.isModifier })
        #expect(modifierCount == 3)
    }

    @Test("Null symbol is ignored")
    @MainActor
    func nullSymbolIgnored() {
        let state = KeyState()
        let event = KeyEvent(type: .keyDown, keyCode: 0xFF, modifiers: [])

        state.processEvent(event, symbol: nil)

        #expect(state.pressedKeys.isEmpty)
    }

    @Test("FlagsChanged adds modifier when pressed")
    @MainActor
    func flagsChangedAddsModifier() {
        let state = KeyState()
        let symbol = KeySymbol(id: "command-left", display: "⌘", isModifier: true)

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: .maskCommand),
            symbol: symbol)

        #expect(state.pressedKeys.count == 1)
        #expect(state.pressedKeys.first?.symbol.display == "⌘")
    }

    @Test("FlagsChanged removes modifier when released")
    @MainActor
    func flagsChangedRemovesModifier() {
        let state = KeyState()
        let symbol = KeySymbol(id: "command-left", display: "⌘", isModifier: true)

        // Press
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: .maskCommand),
            symbol: symbol)
        #expect(state.pressedKeys.count == 1)

        // Release
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: []),
            symbol: symbol)
        #expect(state.pressedKeys.isEmpty)
    }
}

@Suite("PressedKey Tests")
struct PressedKeyTests {
    @Test("Modifier PressedKey uses stable ID from symbol")
    func modifierPressedKeyId() {
        let symbol = KeySymbol(id: "command", display: "⌘", isModifier: true)
        let key = PressedKey(symbol: symbol)

        // Modifier keys use symbol.id directly
        #expect(key.id == "command")
        #expect(key.symbol.display == "⌘")
    }

    @Test("Regular PressedKey uses unique ID with timestamp")
    func regularPressedKeyId() {
        let symbol = KeySymbol(id: "key-0", display: "A")
        let key = PressedKey(symbol: symbol)

        // Regular keys have unique ID with timestamp
        #expect(key.id.hasPrefix("key-0-"))
        #expect(key.id != symbol.id)
        #expect(key.symbol.display == "A")
    }

    @Test("Two regular keys with same symbol have different IDs")
    func regularKeysHaveUniqueIds() {
        let symbol = KeySymbol(id: "key-0", display: "A")
        let key1 = PressedKey(symbol: symbol)

        // Small delay to ensure different timestamp
        Thread.sleep(forTimeInterval: 0.001)
        let key2 = PressedKey(symbol: symbol)

        #expect(key1.id != key2.id)
    }

    @Test("PressedKey is Equatable")
    func equatable() {
        let symbol = KeySymbol(id: "command", display: "⌘", isModifier: true)
        let date = Date()
        let key1 = PressedKey(symbol: symbol, pressedAt: date)
        let key2 = PressedKey(symbol: symbol, pressedAt: date)

        // Same modifier at same time = same ID
        #expect(key1 == key2)
    }
}

// MARK: - SingleKeyState Tests

@Suite("SingleKeyState Tests")
struct SingleKeyStateTests {
    @Test("Initial state is empty")
    @MainActor
    func test_initialState() {
        let state = SingleKeyState()
        #expect(state.pressedKeys.isEmpty)
        #expect(state.hasKeys == false)
    }

    @Test("KeyDown shows key")
    @MainActor
    func keyDownShowsKey() {
        let state = SingleKeyState()
        let symbol = KeySymbol(id: "key-a", display: "A")

        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
            symbol: symbol)

        #expect(state.pressedKeys.count == 1)
        #expect(state.pressedKeys.first?.symbol.display == "A")
    }

    @Test("New keypress replaces previous")
    @MainActor
    func newKeyReplacesPrevious() {
        let state = SingleKeyState(isKeyDown: { _ in false })

        // Press and release A
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
            symbol: KeySymbol(id: "key-a", display: "A"))
        #expect(state.pressedKeys.count == 1)
        #expect(state.pressedKeys.first?.symbol.display == "A")

        state.processEvent(
            KeyEvent(type: .keyUp, keyCode: 0x00, modifiers: []),
            symbol: KeySymbol(id: "key-a", display: "A"))
        // Released key stays visible until the timeout
        #expect(state.pressedKeys.count == 1)

        // Press B - should replace A
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x0B, modifiers: []),
            symbol: KeySymbol(id: "key-b", display: "B"))
        #expect(state.pressedKeys.count == 1)
        #expect(state.pressedKeys.first?.symbol.display == "B")
    }

    @Test("Modifier + key shows combination")
    @MainActor
    func modifierPlusKey() {
        let state = SingleKeyState()

        // Press Command
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: .maskCommand),
            symbol: KeySymbol(id: "command", display: "⌘", isModifier: true))

        // Press A
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: .maskCommand),
            symbol: KeySymbol(id: "key-a", display: "A"))

        #expect(state.pressedKeys.count == 2)
        #expect(state.pressedKeys[0].symbol.display == "⌘")
        #expect(state.pressedKeys[1].symbol.display == "A")
    }

    @Test("Multiple modifiers + key")
    @MainActor
    func multipleModifiersPlusKey() {
        let state = SingleKeyState()

        // Press Command
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: .maskCommand),
            symbol: KeySymbol(id: "command", display: "⌘", isModifier: true))

        // Press Shift
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x38, modifiers: [.maskCommand, .maskShift]),
            symbol: KeySymbol(id: "shift", display: "⇧", isModifier: true))

        // Press A
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: [.maskCommand, .maskShift]),
            symbol: KeySymbol(id: "key-a", display: "A"))

        #expect(state.pressedKeys.count == 3)
        // Modifiers first, then key
        #expect(state.pressedKeys[0].symbol.isModifier == true)
        #expect(state.pressedKeys[1].symbol.isModifier == true)
        #expect(state.pressedKeys[2].symbol.display == "A")
    }

    @Test("Modifier stays with key after release, clears on new keypress")
    @MainActor
    func modifierRelease() {
        let state = SingleKeyState(isKeyDown: { _ in false })

        // Press Command
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: .maskCommand),
            symbol: KeySymbol(id: "command", display: "⌘", isModifier: true))

        // Press A (creates Cmd+A combination)
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: .maskCommand),
            symbol: KeySymbol(id: "key-a", display: "A"))
        #expect(state.pressedKeys.count == 2)

        // Release Command — modifier should stay with the key
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: []),
            symbol: KeySymbol(id: "command", display: "⌘", isModifier: true))

        // Combination should stay together (Cmd+A)
        #expect(state.pressedKeys.count == 2)
        #expect(state.pressedKeys.first?.symbol.display == "⌘")

        // Press new key without modifier — released modifier should clear
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x01, modifiers: []),
            symbol: KeySymbol(id: "key-b", display: "B"))

        // Now only the new key should be shown
        #expect(state.pressedKeys.count == 1)
        #expect(state.pressedKeys.first?.symbol.display == "B")
    }

    @Test("Clear removes all keys")
    @MainActor
    func test_clear() {
        let state = SingleKeyState()

        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
            symbol: KeySymbol(id: "key-a", display: "A"))
        #expect(state.hasKeys == true)

        state.clear()

        #expect(state.pressedKeys.isEmpty)
        #expect(state.hasKeys == false)
    }

    @Test("showModifiersOnly filters regular keys")
    @MainActor
    func showModifiersOnlyFilters() {
        let state = SingleKeyState()
        state.showModifiersOnly = true

        // Press A (no modifier) - should NOT show
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
            symbol: KeySymbol(id: "key-a", display: "A"))

        #expect(state.pressedKeys.isEmpty)
    }

    @Test("showModifiersOnly shows modifier + key combination")
    @MainActor
    func showModifiersOnlyShowsCombination() {
        let state = SingleKeyState()
        state.showModifiersOnly = true

        // Press Command
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: .maskCommand),
            symbol: KeySymbol(id: "command", display: "⌘", isModifier: true))

        // Press A (with modifier) - should show
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: .maskCommand),
            symbol: KeySymbol(id: "key-a", display: "A"))

        #expect(state.pressedKeys.count == 2)
    }

    @Test("keyTimeout property is settable")
    @MainActor
    func keyTimeoutSettable() {
        let state = SingleKeyState()
        #expect(state.keyTimeout == 1.5) // default

        state.keyTimeout = 2.0
        #expect(state.keyTimeout == 2.0)
    }

    @Test("Conforms to KeyStateProtocol")
    @MainActor
    func conformsToProtocol() {
        let state: any KeyStateProtocol = SingleKeyState()

        #expect(state.pressedKeys.isEmpty)
        #expect(state.hasKeys == false)

        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
            symbol: KeySymbol(id: "key-a", display: "A"))

        #expect(state.hasKeys == true)

        state.clear()
        #expect(state.hasKeys == false)
    }
}

// MARK: - SingleKeyState Simultaneous Keys Tests

/// Stands in for the system key-state probe so tests can hold keys down.
private final class FakeKeyboard: @unchecked Sendable {
    private var downKeys: Set<CGKeyCode> = []
    private let lock = NSLock()

    var probe: SingleKeyState.KeyDownProbe {
        { keyCode in self.lock.withLock { self.downKeys.contains(keyCode) } }
    }

    func press(_ keyCode: CGKeyCode) {
        self.lock.withLock { _ = self.downKeys.insert(keyCode) }
    }

    func release(_ keyCode: CGKeyCode) {
        self.lock.withLock { _ = self.downKeys.remove(keyCode) }
    }
}

@Suite("SingleKeyState Simultaneous Keys Tests")
struct SingleKeyStateSimultaneousTests {
    private static let keyA = KeySymbol(id: "key-a", display: "A")
    private static let keyS = KeySymbol(id: "key-s", display: "S")
    private static let codeA: Int64 = 0x00
    private static let codeS: Int64 = 0x01

    @MainActor
    private func press(_ state: SingleKeyState, _ keyboard: FakeKeyboard, _ code: Int64, _ symbol: KeySymbol) {
        keyboard.press(CGKeyCode(code))
        state.processEvent(KeyEvent(type: .keyDown, keyCode: code, modifiers: []), symbol: symbol)
    }

    @MainActor
    private func release(_ state: SingleKeyState, _ keyboard: FakeKeyboard, _ code: Int64, _ symbol: KeySymbol) {
        keyboard.release(CGKeyCode(code))
        state.processEvent(KeyEvent(type: .keyUp, keyCode: code, modifiers: []), symbol: symbol)
    }

    @Test("Keys held together are shown together")
    @MainActor
    func simultaneousKeysShowTogether() {
        let keyboard = FakeKeyboard()
        let state = SingleKeyState(isKeyDown: keyboard.probe)

        self.press(state, keyboard, Self.codeA, Self.keyA)
        self.press(state, keyboard, Self.codeS, Self.keyS)

        #expect(state.pressedKeys.count == 2)
        #expect(state.pressedKeys.map(\.symbol.display) == ["A", "S"])
    }

    @Test("Releasing one key keeps the other on screen")
    @MainActor
    func releasingOneKeyKeepsOther() {
        let keyboard = FakeKeyboard()
        let state = SingleKeyState(isKeyDown: keyboard.probe)

        self.press(state, keyboard, Self.codeA, Self.keyA)
        self.press(state, keyboard, Self.codeS, Self.keyS)
        self.release(state, keyboard, Self.codeA, Self.keyA)

        #expect(state.pressedKeys.map(\.symbol.display) == ["S"])
    }

    @Test("Combination stays visible after every key is released")
    @MainActor
    func combinationStaysAfterFullRelease() {
        let keyboard = FakeKeyboard()
        let state = SingleKeyState(isKeyDown: keyboard.probe)

        self.press(state, keyboard, Self.codeA, Self.keyA)
        self.press(state, keyboard, Self.codeS, Self.keyS)
        self.release(state, keyboard, Self.codeA, Self.keyA)
        self.release(state, keyboard, Self.codeS, Self.keyS)

        // Still displayed — the timeout, not the release, clears it
        #expect(state.hasKeys == true)
    }

    @Test("Sequential typing does not accumulate keys")
    @MainActor
    func sequentialTypingDoesNotAccumulate() {
        let keyboard = FakeKeyboard()
        let state = SingleKeyState(isKeyDown: keyboard.probe)

        self.press(state, keyboard, Self.codeA, Self.keyA)
        self.release(state, keyboard, Self.codeA, Self.keyA)
        self.press(state, keyboard, Self.codeS, Self.keyS)

        #expect(state.pressedKeys.map(\.symbol.display) == ["S"])
    }

    @Test("Key repeat does not duplicate a held key")
    @MainActor
    func keyRepeatDoesNotDuplicate() {
        let keyboard = FakeKeyboard()
        let state = SingleKeyState(isKeyDown: keyboard.probe)

        self.press(state, keyboard, Self.codeA, Self.keyA)
        self.press(state, keyboard, Self.codeA, Self.keyA)
        self.press(state, keyboard, Self.codeA, Self.keyA)

        #expect(state.pressedKeys.count == 1)
    }

    @Test("Missed key up does not strand a key in later combinations")
    @MainActor
    func missedKeyUpDoesNotStrandKey() {
        let keyboard = FakeKeyboard()
        let state = SingleKeyState(isKeyDown: keyboard.probe)

        // A is pressed and released, but its key up event never arrives
        self.press(state, keyboard, Self.codeA, Self.keyA)
        keyboard.release(CGKeyCode(Self.codeA))

        self.press(state, keyboard, Self.codeS, Self.keyS)

        #expect(state.pressedKeys.map(\.symbol.display) == ["S"])
        #expect(state.physicallyPressedKeys.contains(Self.keyA.id) == false)
    }

    @Test("Simultaneous keys are capped")
    @MainActor
    func simultaneousKeysAreCapped() {
        let keyboard = FakeKeyboard()
        let state = SingleKeyState(isKeyDown: keyboard.probe)

        for index in 0..<6 {
            let code = Int64(index)
            self.press(state, keyboard, code, KeySymbol(id: "key-\(index)", display: "\(index)"))
        }

        #expect(state.pressedKeys.count == 4)
        // Oldest presses are dropped, most recent kept
        #expect(state.pressedKeys.map(\.symbol.display) == ["2", "3", "4", "5"])
    }

    @Test("Modifier is shown with simultaneously held keys")
    @MainActor
    func modifierWithSimultaneousKeys() {
        let keyboard = FakeKeyboard()
        let state = SingleKeyState(isKeyDown: keyboard.probe)

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: .maskCommand),
            symbol: KeySymbol(id: "command", display: "⌘", isModifier: true))
        self.press(state, keyboard, Self.codeA, Self.keyA)
        self.press(state, keyboard, Self.codeS, Self.keyS)

        #expect(state.pressedKeys.map(\.symbol.display) == ["⌘", "A", "S"])
    }
}

// MARK: - KeyState duplicateLetters Tests

@Suite("KeyState duplicateLetters Tests")
struct KeyStateDuplicateLettersTests {
    @Test("duplicateLetters=true allows repeated keys")
    @MainActor
    func duplicateLettersTrue() {
        let state = KeyState()
        state.duplicateLetters = true

        let symbol = KeySymbol(id: "key-l", display: "L")

        state.processEvent(KeyEvent(type: .keyDown, keyCode: 0x25, modifiers: []), symbol: symbol)
        state.processEvent(KeyEvent(type: .keyDown, keyCode: 0x25, modifiers: []), symbol: symbol)

        #expect(state.pressedKeys.count == 2)
    }

    @Test("duplicateLetters=false prevents repeated keys")
    @MainActor
    func duplicateLettersFalse() {
        let state = KeyState()
        state.duplicateLetters = false

        let symbol = KeySymbol(id: "key-l", display: "L")

        state.processEvent(KeyEvent(type: .keyDown, keyCode: 0x25, modifiers: []), symbol: symbol)
        state.processEvent(KeyEvent(type: .keyDown, keyCode: 0x25, modifiers: []), symbol: symbol)

        // Should only have 1 key (no duplicate)
        #expect(state.pressedKeys.count == 1)
    }

    @Test("duplicateLetters=false still allows different keys")
    @MainActor
    func duplicateLettersFalseDifferentKeys() {
        let state = KeyState()
        state.duplicateLetters = false

        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
            symbol: KeySymbol(id: "key-a", display: "A"))
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x0B, modifiers: []),
            symbol: KeySymbol(id: "key-b", display: "B"))

        #expect(state.pressedKeys.count == 2)
    }
}

// MARK: - KeyState maxDisplayedKeys Tests

@Suite("KeyState maxDisplayedKeys Tests")
struct KeyStateMaxDisplayedKeysTests {
    @Test("maxDisplayedKeys is configurable")
    @MainActor
    func maxDisplayedKeysConfigurable() {
        let state = KeyState()
        #expect(state.maxDisplayedKeys == 6) // default

        state.maxDisplayedKeys = 10
        #expect(state.maxDisplayedKeys == 10)
    }

    @Test("Custom maxDisplayedKeys limits keys")
    @MainActor
    func customMaxDisplayedKeysLimits() {
        let state = KeyState()
        state.maxDisplayedKeys = 3

        // Add 5 keys
        for i in 0..<5 {
            state.processEvent(
                KeyEvent(type: .keyDown, keyCode: Int64(i), modifiers: []),
                symbol: KeySymbol(id: "key-\(i)", display: "\(i)"))
        }

        #expect(state.pressedKeys.count == 3)
    }
}
