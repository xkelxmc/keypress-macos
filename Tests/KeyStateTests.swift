import CoreGraphics
import Foundation
import Testing
@testable import KeypressCore

@Suite("KeyState Tests")
struct KeyStateTests {
    @Test("Initial state is empty")
    @MainActor
    func test_initialState() {
        let state = KeyState()
        #expect(state.pressedKeys.isEmpty)
        #expect(state.hasKeys == false)
    }

    @Test("KeyDown adds key to state")
    @MainActor
    func test_keyDownAddsKey() {
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
    func test_modifierKeyDown() {
        let state = KeyState()
        let symbol = KeySymbol(id: "command", display: "⌘", isModifier: true)
        let event = KeyEvent(type: .keyDown, keyCode: 0x37, modifiers: .maskCommand)

        state.processEvent(event, symbol: symbol)

        #expect(state.pressedKeys.count == 1)
        #expect(state.pressedKeys.first?.symbol.isModifier == true)
    }

    @Test("Modifier keyUp removes modifier immediately")
    @MainActor
    func test_modifierKeyUpRemoves() {
        let state = KeyState()
        let symbol = KeySymbol(id: "command", display: "⌘", isModifier: true)

        state.processEvent(KeyEvent(type: .keyDown, keyCode: 0x37, modifiers: .maskCommand), symbol: symbol)
        #expect(state.pressedKeys.count == 1)

        state.processEvent(KeyEvent(type: .keyUp, keyCode: 0x37, modifiers: []), symbol: symbol)
        #expect(state.pressedKeys.isEmpty)
    }

    @Test("Regular key stays after keyUp (waits for timeout)")
    @MainActor
    func test_regularKeyStaysAfterKeyUp() {
        let state = KeyState()
        let symbol = KeySymbol(id: "key-a", display: "A")

        state.processEvent(KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []), symbol: symbol)
        state.processEvent(KeyEvent(type: .keyUp, keyCode: 0x00, modifiers: []), symbol: symbol)

        // Key should still be there (waiting for timeout)
        #expect(state.pressedKeys.count == 1)
    }

    @Test("Duplicate keyDown does not add duplicate")
    @MainActor
    func test_noDuplicateKeys() {
        let state = KeyState()
        let symbol = KeySymbol(id: "key-a", display: "A")
        let event = KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: [])

        state.processEvent(event, symbol: symbol)
        state.processEvent(event, symbol: symbol)

        #expect(state.pressedKeys.count == 1)
    }

    @Test("Clear removes all keys")
    @MainActor
    func test_clear() {
        let state = KeyState()

        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
            symbol: KeySymbol(id: "key-a", display: "A")
        )
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x37, modifiers: .maskCommand),
            symbol: KeySymbol(id: "command", display: "⌘", isModifier: true)
        )

        #expect(state.pressedKeys.count == 2)

        state.clear()

        #expect(state.pressedKeys.isEmpty)
    }

    @Test("Modifiers are sorted before regular keys")
    @MainActor
    func test_modifiersSortedFirst() {
        let state = KeyState()

        // Add regular key first
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
            symbol: KeySymbol(id: "key-a", display: "A")
        )

        // Add modifier second
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x37, modifiers: .maskCommand),
            symbol: KeySymbol(id: "command", display: "⌘", isModifier: true)
        )

        #expect(state.pressedKeys.count == 2)
        #expect(state.pressedKeys[0].symbol.isModifier == true)
        #expect(state.pressedKeys[1].symbol.isModifier == false)
    }

    @Test("Max 6 keys displayed")
    @MainActor
    func test_maxKeysLimit() {
        let state = KeyState()

        // Add 8 keys
        for i in 0 ..< 8 {
            let symbol = KeySymbol(id: "key-\(i)", display: "\(i)")
            state.processEvent(
                KeyEvent(type: .keyDown, keyCode: Int64(i), modifiers: []),
                symbol: symbol
            )
        }

        #expect(state.pressedKeys.count == KeyState.maxDisplayedKeys)
        #expect(state.pressedKeys.count == 6)
    }

    @Test("Modifiers prioritized when at max keys")
    @MainActor
    func test_modifiersPrioritizedAtMax() {
        let state = KeyState()

        // Add 5 regular keys
        for i in 0 ..< 5 {
            let symbol = KeySymbol(id: "key-\(i)", display: "\(i)")
            state.processEvent(
                KeyEvent(type: .keyDown, keyCode: Int64(i), modifiers: []),
                symbol: symbol
            )
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
                symbol: mod
            )
        }

        #expect(state.pressedKeys.count == 6)

        // All 3 modifiers should be present
        let modifierCount = state.pressedKeys.filter { $0.symbol.isModifier }.count
        #expect(modifierCount == 3)
    }

    @Test("Null symbol is ignored")
    @MainActor
    func test_nullSymbolIgnored() {
        let state = KeyState()
        let event = KeyEvent(type: .keyDown, keyCode: 0xFF, modifiers: [])

        state.processEvent(event, symbol: nil)

        #expect(state.pressedKeys.isEmpty)
    }

    @Test("FlagsChanged adds modifier when pressed")
    @MainActor
    func test_flagsChangedAddsModifier() {
        let state = KeyState()
        let symbol = KeySymbol(id: "command-left", display: "⌘", isModifier: true)

        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: .maskCommand),
            symbol: symbol
        )

        #expect(state.pressedKeys.count == 1)
        #expect(state.pressedKeys.first?.symbol.display == "⌘")
    }

    @Test("FlagsChanged removes modifier when released")
    @MainActor
    func test_flagsChangedRemovesModifier() {
        let state = KeyState()
        let symbol = KeySymbol(id: "command-left", display: "⌘", isModifier: true)

        // Press
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: .maskCommand),
            symbol: symbol
        )
        #expect(state.pressedKeys.count == 1)

        // Release
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: []),
            symbol: symbol
        )
        #expect(state.pressedKeys.isEmpty)
    }
}

@Suite("PressedKey Tests")
struct PressedKeyTests {
    @Test("PressedKey stores symbol correctly")
    func test_pressedKeyInit() {
        let symbol = KeySymbol(id: "test", display: "T")
        let key = PressedKey(symbol: symbol)

        #expect(key.id == "test")
        #expect(key.symbol.display == "T")
    }

    @Test("PressedKey is Equatable")
    func test_equatable() {
        let symbol = KeySymbol(id: "test", display: "T")
        let date = Date()
        let key1 = PressedKey(symbol: symbol, pressedAt: date)
        let key2 = PressedKey(symbol: symbol, pressedAt: date)

        #expect(key1 == key2)
    }
}
