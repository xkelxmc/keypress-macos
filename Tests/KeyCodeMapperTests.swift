import CoreGraphics
import Foundation
import Testing
@testable import KeypressCore

@Suite("KeyCodeMapper Tests")
struct KeyCodeMapperTests {
    @Test("Maps modifier keys correctly")
    func test_modifierKeys() {
        // Command keys
        let cmdLeft = KeyCodeMapper.symbol(for: 0x37)
        #expect(cmdLeft?.display == "⌘")
        #expect(cmdLeft?.isModifier == true)

        let cmdRight = KeyCodeMapper.symbol(for: 0x36)
        #expect(cmdRight?.display == "⌘")
        #expect(cmdRight?.isModifier == true)

        // Shift keys
        let shiftLeft = KeyCodeMapper.symbol(for: 0x38)
        #expect(shiftLeft?.display == "⇧")
        #expect(shiftLeft?.isModifier == true)

        // Option keys
        let optionLeft = KeyCodeMapper.symbol(for: 0x3A)
        #expect(optionLeft?.display == "⌥")
        #expect(optionLeft?.isModifier == true)

        // Control keys
        let controlLeft = KeyCodeMapper.symbol(for: 0x3B)
        #expect(controlLeft?.display == "⌃")
        #expect(controlLeft?.isModifier == true)

        // Caps Lock
        let capsLock = KeyCodeMapper.symbol(for: 0x39)
        #expect(capsLock?.display == "⇪")
        #expect(capsLock?.isModifier == true)
    }

    @Test("Maps special keys correctly")
    func test_specialKeys() {
        let returnKey = KeyCodeMapper.symbol(for: 0x24)
        #expect(returnKey?.display == "⏎")
        #expect(returnKey?.isModifier == false)

        let tab = KeyCodeMapper.symbol(for: 0x30)
        #expect(tab?.display == "⇥")

        let space = KeyCodeMapper.symbol(for: 0x31)
        #expect(space?.display == "␣")

        let delete = KeyCodeMapper.symbol(for: 0x33)
        #expect(delete?.display == "⌫")

        let escape = KeyCodeMapper.symbol(for: 0x35)
        #expect(escape?.display == "⎋")
    }

    @Test("Maps arrow keys correctly")
    func test_arrowKeys() {
        #expect(KeyCodeMapper.symbol(for: 0x7B)?.display == "←")
        #expect(KeyCodeMapper.symbol(for: 0x7C)?.display == "→")
        #expect(KeyCodeMapper.symbol(for: 0x7D)?.display == "↓")
        #expect(KeyCodeMapper.symbol(for: 0x7E)?.display == "↑")
    }

    @Test("Maps letter keys correctly")
    func test_letterKeys() {
        #expect(KeyCodeMapper.symbol(for: 0x00)?.display == "A")
        #expect(KeyCodeMapper.symbol(for: 0x0B)?.display == "B")
        #expect(KeyCodeMapper.symbol(for: 0x08)?.display == "C")
        #expect(KeyCodeMapper.symbol(for: 0x06)?.display == "Z")
    }

    @Test("Maps number keys correctly")
    func test_numberKeys() {
        #expect(KeyCodeMapper.symbol(for: 0x12)?.display == "1")
        #expect(KeyCodeMapper.symbol(for: 0x13)?.display == "2")
        #expect(KeyCodeMapper.symbol(for: 0x1D)?.display == "0")
    }

    @Test("Maps function keys correctly")
    func test_functionKeys() {
        #expect(KeyCodeMapper.symbol(for: 0x7A)?.display == "F1")
        #expect(KeyCodeMapper.symbol(for: 0x78)?.display == "F2")
        #expect(KeyCodeMapper.symbol(for: 0x6F)?.display == "F12")
    }

    @Test("Returns nil for unknown keycodes")
    func test_unknownKeycode() {
        let unknown = KeyCodeMapper.symbol(for: 0xFF)
        #expect(unknown == nil)
    }

    @Test("isModifier returns correct values")
    func test_isModifier() {
        #expect(KeyCodeMapper.isModifier(0x37) == true) // Command
        #expect(KeyCodeMapper.isModifier(0x38) == true) // Shift
        #expect(KeyCodeMapper.isModifier(0x00) == false) // A
        #expect(KeyCodeMapper.isModifier(0x24) == false) // Return
    }

    @Test("activeModifiers extracts flags correctly")
    func test_activeModifiers() {
        let flags: CGEventFlags = [.maskCommand, .maskShift]
        let modifiers = KeyCodeMapper.activeModifiers(from: flags)

        #expect(modifiers.count == 2)
        #expect(modifiers.contains { $0.display == "⌘" })
        #expect(modifiers.contains { $0.display == "⇧" })
    }

    @Test("activeModifiers returns empty for no modifiers")
    func test_activeModifiersEmpty() {
        let modifiers = KeyCodeMapper.activeModifiers(from: [])
        #expect(modifiers.isEmpty)
    }
}

@Suite("KeyEvent Tests")
struct KeyEventTests {
    @Test("KeyEvent stores values correctly")
    func test_keyEventInit() {
        let timestamp = Date()
        let event = KeyEvent(
            type: .keyDown,
            keyCode: 0x00,
            modifiers: .maskCommand,
            timestamp: timestamp
        )

        #expect(event.type == KeyEvent.EventType.keyDown)
        #expect(event.keyCode == 0x00)
        #expect(event.modifiers == CGEventFlags.maskCommand)
        #expect(event.timestamp == timestamp)
    }

    @Test("KeyEvent is Equatable")
    func test_keyEventEquatable() {
        let timestamp = Date()
        let event1 = KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: [], timestamp: timestamp)
        let event2 = KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: [], timestamp: timestamp)
        let event3 = KeyEvent(type: .keyUp, keyCode: 0x00, modifiers: [], timestamp: timestamp)

        #expect(event1 == event2)
        #expect(event1 != event3)
    }
}

@Suite("KeySymbol Tests")
struct KeySymbolTests {
    @Test("KeySymbol is Hashable")
    func test_hashable() {
        let symbol1 = KeySymbol(id: "a", display: "A")
        let symbol2 = KeySymbol(id: "a", display: "A")
        let symbol3 = KeySymbol(id: "b", display: "B")

        var set: Set<KeySymbol> = []
        set.insert(symbol1)
        set.insert(symbol2)
        set.insert(symbol3)

        #expect(set.count == 2)
    }

    @Test("KeySymbol id is Identifiable")
    func test_identifiable() {
        let symbol = KeySymbol(id: "test-id", display: "T")
        #expect(symbol.id == "test-id")
    }
}
