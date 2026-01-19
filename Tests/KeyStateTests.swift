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

    @Test("Duplicate modifier keyDown does not add duplicate")
    @MainActor
    func test_noDuplicateModifiers() {
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
    func test_regularKeysAllowDuplicates() {
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

        #expect(state.pressedKeys.count == state.maxDisplayedKeys)
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
    @Test("Modifier PressedKey uses stable ID from symbol")
    func test_modifierPressedKeyId() {
        let symbol = KeySymbol(id: "command", display: "⌘", isModifier: true)
        let key = PressedKey(symbol: symbol)

        // Modifier keys use symbol.id directly
        #expect(key.id == "command")
        #expect(key.symbol.display == "⌘")
    }

    @Test("Regular PressedKey uses unique ID with timestamp")
    func test_regularPressedKeyId() {
        let symbol = KeySymbol(id: "key-0", display: "A")
        let key = PressedKey(symbol: symbol)

        // Regular keys have unique ID with timestamp
        #expect(key.id.hasPrefix("key-0-"))
        #expect(key.id != symbol.id)
        #expect(key.symbol.display == "A")
    }

    @Test("Two regular keys with same symbol have different IDs")
    func test_regularKeysHaveUniqueIds() {
        let symbol = KeySymbol(id: "key-0", display: "A")
        let key1 = PressedKey(symbol: symbol)

        // Small delay to ensure different timestamp
        Thread.sleep(forTimeInterval: 0.001)
        let key2 = PressedKey(symbol: symbol)

        #expect(key1.id != key2.id)
    }

    @Test("PressedKey is Equatable")
    func test_equatable() {
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
    func test_keyDownShowsKey() {
        let state = SingleKeyState()
        let symbol = KeySymbol(id: "key-a", display: "A")

        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
            symbol: symbol
        )

        #expect(state.pressedKeys.count == 1)
        #expect(state.pressedKeys.first?.symbol.display == "A")
    }

    @Test("New keypress replaces previous")
    @MainActor
    func test_newKeyReplacesPrevious() {
        let state = SingleKeyState()

        // Press A
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
            symbol: KeySymbol(id: "key-a", display: "A")
        )
        #expect(state.pressedKeys.count == 1)
        #expect(state.pressedKeys.first?.symbol.display == "A")

        // Press B - should replace A
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x0B, modifiers: []),
            symbol: KeySymbol(id: "key-b", display: "B")
        )
        #expect(state.pressedKeys.count == 1)
        #expect(state.pressedKeys.first?.symbol.display == "B")
    }

    @Test("Modifier + key shows combination")
    @MainActor
    func test_modifierPlusKey() {
        let state = SingleKeyState()

        // Press Command
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: .maskCommand),
            symbol: KeySymbol(id: "command", display: "⌘", isModifier: true)
        )

        // Press A
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: .maskCommand),
            symbol: KeySymbol(id: "key-a", display: "A")
        )

        #expect(state.pressedKeys.count == 2)
        #expect(state.pressedKeys[0].symbol.display == "⌘")
        #expect(state.pressedKeys[1].symbol.display == "A")
    }

    @Test("Multiple modifiers + key")
    @MainActor
    func test_multipleModifiersPlusKey() {
        let state = SingleKeyState()

        // Press Command
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: .maskCommand),
            symbol: KeySymbol(id: "command", display: "⌘", isModifier: true)
        )

        // Press Shift
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x38, modifiers: [.maskCommand, .maskShift]),
            symbol: KeySymbol(id: "shift", display: "⇧", isModifier: true)
        )

        // Press A
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: [.maskCommand, .maskShift]),
            symbol: KeySymbol(id: "key-a", display: "A")
        )

        #expect(state.pressedKeys.count == 3)
        // Modifiers first, then key
        #expect(state.pressedKeys[0].symbol.isModifier == true)
        #expect(state.pressedKeys[1].symbol.isModifier == true)
        #expect(state.pressedKeys[2].symbol.display == "A")
    }

    @Test("Modifier stays with key after release, clears on new keypress")
    @MainActor
    func test_modifierRelease() {
        let state = SingleKeyState()

        // Press Command
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: .maskCommand),
            symbol: KeySymbol(id: "command", display: "⌘", isModifier: true)
        )

        // Press A (creates Cmd+A combination)
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: .maskCommand),
            symbol: KeySymbol(id: "key-a", display: "A")
        )
        #expect(state.pressedKeys.count == 2)

        // Release Command — modifier should stay with the key
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: []),
            symbol: KeySymbol(id: "command", display: "⌘", isModifier: true)
        )

        // Combination should stay together (Cmd+A)
        #expect(state.pressedKeys.count == 2)
        #expect(state.pressedKeys.first?.symbol.display == "⌘")

        // Press new key without modifier — released modifier should clear
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x01, modifiers: []),
            symbol: KeySymbol(id: "key-b", display: "B")
        )

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
            symbol: KeySymbol(id: "key-a", display: "A")
        )
        #expect(state.hasKeys == true)

        state.clear()

        #expect(state.pressedKeys.isEmpty)
        #expect(state.hasKeys == false)
    }

    @Test("showModifiersOnly filters regular keys")
    @MainActor
    func test_showModifiersOnlyFilters() {
        let state = SingleKeyState()
        state.showModifiersOnly = true

        // Press A (no modifier) - should NOT show
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
            symbol: KeySymbol(id: "key-a", display: "A")
        )

        #expect(state.pressedKeys.isEmpty)
    }

    @Test("showModifiersOnly shows modifier + key combination")
    @MainActor
    func test_showModifiersOnlyShowsCombination() {
        let state = SingleKeyState()
        state.showModifiersOnly = true

        // Press Command
        state.processEvent(
            KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: .maskCommand),
            symbol: KeySymbol(id: "command", display: "⌘", isModifier: true)
        )

        // Press A (with modifier) - should show
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: .maskCommand),
            symbol: KeySymbol(id: "key-a", display: "A")
        )

        #expect(state.pressedKeys.count == 2)
    }

    @Test("keyTimeout property is settable")
    @MainActor
    func test_keyTimeoutSettable() {
        let state = SingleKeyState()
        #expect(state.keyTimeout == 1.5) // default

        state.keyTimeout = 2.0
        #expect(state.keyTimeout == 2.0)
    }

    @Test("Conforms to KeyStateProtocol")
    @MainActor
    func test_conformsToProtocol() {
        let state: any KeyStateProtocol = SingleKeyState()

        #expect(state.pressedKeys.isEmpty)
        #expect(state.hasKeys == false)

        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
            symbol: KeySymbol(id: "key-a", display: "A")
        )

        #expect(state.hasKeys == true)

        state.clear()
        #expect(state.hasKeys == false)
    }
}

// MARK: - KeyState duplicateLetters Tests

@Suite("KeyState duplicateLetters Tests")
struct KeyStateDuplicateLettersTests {
    @Test("duplicateLetters=true allows repeated keys")
    @MainActor
    func test_duplicateLettersTrue() {
        let state = KeyState()
        state.duplicateLetters = true

        let symbol = KeySymbol(id: "key-l", display: "L")

        state.processEvent(KeyEvent(type: .keyDown, keyCode: 0x25, modifiers: []), symbol: symbol)
        state.processEvent(KeyEvent(type: .keyDown, keyCode: 0x25, modifiers: []), symbol: symbol)

        #expect(state.pressedKeys.count == 2)
    }

    @Test("duplicateLetters=false prevents repeated keys")
    @MainActor
    func test_duplicateLettersFalse() {
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
    func test_duplicateLettersFalseDifferentKeys() {
        let state = KeyState()
        state.duplicateLetters = false

        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
            symbol: KeySymbol(id: "key-a", display: "A")
        )
        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x0B, modifiers: []),
            symbol: KeySymbol(id: "key-b", display: "B")
        )

        #expect(state.pressedKeys.count == 2)
    }
}

// MARK: - KeyState maxDisplayedKeys Tests

@Suite("KeyState maxDisplayedKeys Tests")
struct KeyStateMaxDisplayedKeysTests {
    @Test("maxDisplayedKeys is configurable")
    @MainActor
    func test_maxDisplayedKeysConfigurable() {
        let state = KeyState()
        #expect(state.maxDisplayedKeys == 6) // default

        state.maxDisplayedKeys = 10
        #expect(state.maxDisplayedKeys == 10)
    }

    @Test("Custom maxDisplayedKeys limits keys")
    @MainActor
    func test_customMaxDisplayedKeysLimits() {
        let state = KeyState()
        state.maxDisplayedKeys = 3

        // Add 5 keys
        for i in 0 ..< 5 {
            state.processEvent(
                KeyEvent(type: .keyDown, keyCode: Int64(i), modifiers: []),
                symbol: KeySymbol(id: "key-\(i)", display: "\(i)")
            )
        }

        #expect(state.pressedKeys.count == 3)
    }
}
