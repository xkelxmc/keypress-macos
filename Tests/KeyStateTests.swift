import CoreGraphics
import Foundation
import Testing
@testable import KeypressCore

@Suite("Physical Modifier Sides")
struct PhysicalModifierSideTests {
    private let leftShift = KeySymbol(id: "shift-left", display: "⇧", isModifier: true)
    private let rightShift = KeySymbol(id: "shift-right", display: "⇧", isModifier: true)

    @Test("Releasing one side preserves the other")
    @MainActor
    func independentSides() {
        let state = SingleKeyState()

        state.processEvent(
            KeyEvent(
                type: .flagsChanged,
                keyCode: 0x38,
                modifiers: .maskShift,
                modifierIsPressed: true),
            symbol: self.leftShift)
        state.processEvent(
            KeyEvent(
                type: .flagsChanged,
                keyCode: 0x3C,
                modifiers: .maskShift,
                modifierIsPressed: true),
            symbol: self.rightShift)
        state.processEvent(
            KeyEvent(
                type: .flagsChanged,
                keyCode: 0x38,
                modifiers: .maskShift,
                modifierIsPressed: false),
            symbol: self.leftShift)

        #expect(!state.physicallyPressedKeys.contains(self.leftShift.id))
        #expect(state.physicallyPressedKeys.contains(self.rightShift.id))
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
    func initialState() {
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
