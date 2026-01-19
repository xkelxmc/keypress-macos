import CoreGraphics
import Foundation
import Testing
@testable import KeypressCore

@Suite("KeyCodeMapper Tests")
struct KeyCodeMapperTests {
    @Test("Maps modifier keys correctly")
    func modifierKeys() {
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

        // Note: Caps Lock (0x39) is intentionally excluded from modifiers
        // because macOS doesn't provide reliable press/release events for it
    }

    @Test("Maps special keys correctly")
    func specialKeys() {
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
        #expect(escape?.display == "ESC")
    }

    @Test("Maps arrow keys correctly")
    func test_arrowKeys() {
        #expect(KeyCodeMapper.symbol(for: 0x7B)?.display == "←")
        #expect(KeyCodeMapper.symbol(for: 0x7C)?.display == "→")
        #expect(KeyCodeMapper.symbol(for: 0x7D)?.display == "↓")
        #expect(KeyCodeMapper.symbol(for: 0x7E)?.display == "↑")
    }

    @Test("Letter keycodes are recognized")
    func letterKeys() {
        // Without CGEvent, character keys return "?" (actual char comes from CGEvent at runtime)
        // We just verify the keycodes are recognized as valid keys
        #expect(KeyCodeMapper.symbol(for: 0x00) != nil) // A
        #expect(KeyCodeMapper.symbol(for: 0x0B) != nil) // B
        #expect(KeyCodeMapper.symbol(for: 0x08) != nil) // C
        #expect(KeyCodeMapper.symbol(for: 0x06) != nil) // Z
        #expect(KeyCodeMapper.isModifier(0x00) == false)
    }

    @Test("Number keycodes are recognized")
    func numberKeys() {
        // Without CGEvent, character keys return "?" (actual char comes from CGEvent at runtime)
        #expect(KeyCodeMapper.symbol(for: 0x12) != nil) // 1
        #expect(KeyCodeMapper.symbol(for: 0x13) != nil) // 2
        #expect(KeyCodeMapper.symbol(for: 0x1D) != nil) // 0
        #expect(KeyCodeMapper.isModifier(0x12) == false)
    }

    @Test("Maps function keys correctly")
    func test_functionKeys() {
        #expect(KeyCodeMapper.symbol(for: 0x7A)?.display == "F1")
        #expect(KeyCodeMapper.symbol(for: 0x78)?.display == "F2")
        #expect(KeyCodeMapper.symbol(for: 0x6F)?.display == "F12")
    }

    @Test("Returns nil for unknown keycodes")
    func unknownKeycode() {
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
    func activeModifiersEmpty() {
        let modifiers = KeyCodeMapper.activeModifiers(from: [])
        #expect(modifiers.isEmpty)
    }
}

@Suite("KeyEvent Tests")
struct KeyEventTests {
    @Test("KeyEvent stores values correctly")
    func keyEventInit() {
        let timestamp = Date()
        let event = KeyEvent(
            type: .keyDown,
            keyCode: 0x00,
            modifiers: .maskCommand,
            timestamp: timestamp)

        #expect(event.type == KeyEvent.EventType.keyDown)
        #expect(event.keyCode == 0x00)
        #expect(event.modifiers == CGEventFlags.maskCommand)
        #expect(event.timestamp == timestamp)
    }

    @Test("KeyEvent is Equatable")
    func keyEventEquatable() {
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
    func hashable() {
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
    func identifiable() {
        let symbol = KeySymbol(id: "test-id", display: "T")
        #expect(symbol.id == "test-id")
    }
}

// MARK: - Full Keyboard Tests

@Suite("Full Keyboard Tests")
struct FullKeyboardTests {
    // MARK: - All Modifier Keys

    @Test("All modifier keys (left and right)")
    func allModifierKeys() {
        let modifierKeycodes: [(Int64, String)] = [
            // Left modifiers
            (0x37, "⌘"), // Command Left
            (0x38, "⇧"), // Shift Left
            (0x3A, "⌥"), // Option Left
            (0x3B, "⌃"), // Control Left
            // Right modifiers
            (0x36, "⌘"), // Command Right
            (0x3C, "⇧"), // Shift Right
            (0x3D, "⌥"), // Option Right
            (0x3E, "⌃"), // Control Right
            // Note: Caps Lock (0x39) and Fn (0x3F) are intentionally excluded
            // - Caps Lock: macOS doesn't provide reliable press/release events
            // - Fn: not a standard modifier, handled specially by the system
        ]

        for (keyCode, expectedDisplay) in modifierKeycodes {
            let symbol = KeyCodeMapper.symbol(for: keyCode)
            #expect(symbol != nil, "Modifier keycode \(String(format: "0x%02X", keyCode)) should produce a symbol")
            #expect(
                symbol?.display == expectedDisplay,
                "Keycode \(String(format: "0x%02X", keyCode)) should display \(expectedDisplay)")
            #expect(symbol?.isModifier == true, "Keycode \(String(format: "0x%02X", keyCode)) should be a modifier")
        }
    }

    // MARK: - All Function Keys F1-F20

    @Test("All function keys F1-F20")
    func allFunctionKeys() {
        let functionKeycodes: [(Int64, String)] = [
            (0x7A, "F1"),
            (0x78, "F2"),
            (0x63, "F3"),
            (0x76, "F4"),
            (0x60, "F5"),
            (0x61, "F6"),
            (0x62, "F7"),
            (0x64, "F8"),
            (0x65, "F9"),
            (0x6D, "F10"),
            (0x67, "F11"),
            (0x6F, "F12"),
            (0x69, "F13"),
            (0x6B, "F14"),
            (0x71, "F15"),
            (0x6A, "F16"),
            (0x40, "F17"),
            (0x4F, "F18"),
            (0x50, "F19"),
            (0x5A, "F20"),
        ]

        for (keyCode, expectedDisplay) in functionKeycodes {
            let symbol = KeyCodeMapper.symbol(for: keyCode)
            #expect(symbol != nil, "Function key \(expectedDisplay) should produce a symbol")
            #expect(
                symbol?.display == expectedDisplay,
                "Function key \(String(format: "0x%02X", keyCode)) should display \(expectedDisplay)")
            #expect(symbol?.isModifier == false, "Function keys should not be modifiers")
        }
    }

    // MARK: - All Letter Keys A-Z

    @Test("All letter keys A-Z")
    func allLetterKeys() {
        let letterKeycodes: [(Int64, String)] = [
            (0x00, "A"), (0x0B, "B"), (0x08, "C"), (0x02, "D"), (0x0E, "E"),
            (0x03, "F"), (0x05, "G"), (0x04, "H"), (0x22, "I"), (0x26, "J"),
            (0x28, "K"), (0x25, "L"), (0x2E, "M"), (0x2D, "N"), (0x1F, "O"),
            (0x23, "P"), (0x0C, "Q"), (0x0F, "R"), (0x01, "S"), (0x11, "T"),
            (0x20, "U"), (0x09, "V"), (0x0D, "W"), (0x07, "X"), (0x10, "Y"),
            (0x06, "Z"),
        ]

        for (keyCode, expectedDisplay) in letterKeycodes {
            let symbol = KeyCodeMapper.symbol(for: keyCode)
            #expect(symbol != nil, "Letter \(expectedDisplay) should produce a symbol")
            // Note: with CGEvent, actual display depends on keyboard layout
            // Without CGEvent, we get "?" for character keys
            #expect(symbol?.isModifier == false, "Letter keys should not be modifiers")
        }
    }

    // MARK: - All Number Keys 0-9

    @Test("All number keys 0-9")
    func allNumberKeys() {
        let numberKeycodes: [(Int64, String)] = [
            (0x1D, "0"),
            (0x12, "1"),
            (0x13, "2"),
            (0x14, "3"),
            (0x15, "4"),
            (0x17, "5"),
            (0x16, "6"),
            (0x1A, "7"),
            (0x1C, "8"),
            (0x19, "9"),
        ]

        for (keyCode, expectedDisplay) in numberKeycodes {
            let symbol = KeyCodeMapper.symbol(for: keyCode)
            #expect(symbol != nil, "Number \(expectedDisplay) should produce a symbol")
            #expect(symbol?.isModifier == false, "Number keys should not be modifiers")
        }
    }

    // MARK: - All Special Keys

    @Test("All special keys")
    func allSpecialKeys() {
        let specialKeycodes: [(Int64, String)] = [
            (0x24, "⏎"), // Return
            (0x30, "⇥"), // Tab
            (0x31, "␣"), // Space
            (0x33, "⌫"), // Delete
            (0x35, "ESC"), // Escape
            (0x4C, "⌤"), // Enter (numpad)
            (0x75, "⌦"), // Forward Delete
        ]

        for (keyCode, expectedDisplay) in specialKeycodes {
            let symbol = KeyCodeMapper.symbol(for: keyCode)
            #expect(symbol != nil, "Special key \(expectedDisplay) should produce a symbol")
            #expect(
                symbol?.display == expectedDisplay,
                "Keycode \(String(format: "0x%02X", keyCode)) should display \(expectedDisplay)")
        }
    }

    // MARK: - All Arrow Keys

    @Test("All arrow keys")
    func allArrowKeys() {
        let arrowKeycodes: [(Int64, String)] = [
            (0x7B, "←"), // Left
            (0x7C, "→"), // Right
            (0x7D, "↓"), // Down
            (0x7E, "↑"), // Up
        ]

        for (keyCode, expectedDisplay) in arrowKeycodes {
            let symbol = KeyCodeMapper.symbol(for: keyCode)
            #expect(symbol != nil, "Arrow key should produce a symbol")
            #expect(symbol?.display == expectedDisplay)
        }
    }

    // MARK: - All Navigation Keys

    @Test("All navigation keys")
    func allNavigationKeys() {
        let navKeycodes: [(Int64, String)] = [
            (0x73, "↖"), // Home
            (0x77, "↘"), // End
            (0x74, "⇞"), // Page Up
            (0x79, "⇟"), // Page Down
        ]

        for (keyCode, expectedDisplay) in navKeycodes {
            let symbol = KeyCodeMapper.symbol(for: keyCode)
            #expect(symbol != nil, "Navigation key should produce a symbol")
            #expect(symbol?.display == expectedDisplay)
        }
    }

    // MARK: - All Numpad Keys

    @Test("All numpad keys")
    func allNumpadKeys() {
        let numpadKeycodes: [(Int64, String)] = [
            (0x52, "0"), (0x53, "1"), (0x54, "2"), (0x55, "3"),
            (0x56, "4"), (0x57, "5"), (0x58, "6"), (0x59, "7"),
            (0x5B, "8"), (0x5C, "9"),
            (0x41, "."), // Decimal
            (0x43, "*"), // Multiply
            (0x45, "+"), // Plus
            (0x4B, "/"), // Divide
            (0x4E, "-"), // Minus
            (0x51, "="), // Equals
            (0x47, "⌧"), // Clear
        ]

        for (keyCode, expectedDisplay) in numpadKeycodes {
            let symbol = KeyCodeMapper.symbol(for: keyCode)
            #expect(symbol != nil, "Numpad key should produce a symbol")
            // Without CGEvent, character keys return "?"
        }
    }

    // MARK: - Punctuation Keys

    @Test("All punctuation keys")
    func allPunctuationKeys() {
        let punctKeycodes: [Int64] = [
            0x1E, // ]
            0x21, // [
            0x27, // '
            0x29, // ;
            0x2A, // \
            0x2B, // ,
            0x2C, // /
            0x2F, // .
            0x32, // `
            0x18, // =
            0x1B, // -
        ]

        for keyCode in punctKeycodes {
            let symbol = KeyCodeMapper.symbol(for: keyCode)
            #expect(symbol != nil, "Punctuation keycode \(String(format: "0x%02X", keyCode)) should produce a symbol")
        }
    }
}

// MARK: - Modifier Combination Tests

@Suite("Modifier Combination Tests")
struct ModifierCombinationTests {
    @Test("Command + Shift combination flags")
    func cmdShiftFlags() {
        let flags: CGEventFlags = [.maskCommand, .maskShift]
        let modifiers = KeyCodeMapper.activeModifiers(from: flags)

        #expect(modifiers.count == 2)
        #expect(modifiers.contains { $0.display == "⌘" })
        #expect(modifiers.contains { $0.display == "⇧" })
    }

    @Test("All four modifiers combination")
    func allFourModifiers() {
        let flags: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let modifiers = KeyCodeMapper.activeModifiers(from: flags)

        #expect(modifiers.count == 4)
        #expect(modifiers.contains { $0.display == "⌘" })
        #expect(modifiers.contains { $0.display == "⇧" })
        #expect(modifiers.contains { $0.display == "⌥" })
        #expect(modifiers.contains { $0.display == "⌃" })
    }

    @Test("Command + Option combination")
    func cmdOptionFlags() {
        let flags: CGEventFlags = [.maskCommand, .maskAlternate]
        let modifiers = KeyCodeMapper.activeModifiers(from: flags)

        #expect(modifiers.count == 2)
        #expect(modifiers.contains { $0.display == "⌘" })
        #expect(modifiers.contains { $0.display == "⌥" })
    }

    @Test("Control + Shift combination")
    func ctrlShiftFlags() {
        let flags: CGEventFlags = [.maskControl, .maskShift]
        let modifiers = KeyCodeMapper.activeModifiers(from: flags)

        #expect(modifiers.count == 2)
        #expect(modifiers.contains { $0.display == "⌃" })
        #expect(modifiers.contains { $0.display == "⇧" })
    }
}

// MARK: - KeyCategory Tests

@Suite("KeyCategory Tests")
struct KeyCategoryTests {
    @Test("Command key returns command category")
    func commandCategory() {
        let symbol = KeySymbol(id: "command-left", display: "⌘", isModifier: true)
        #expect(KeyCodeMapper.category(for: symbol) == .command)

        let symbolRight = KeySymbol(id: "command-right", display: "⌘", isModifier: true)
        #expect(KeyCodeMapper.category(for: symbolRight) == .command)
    }

    @Test("Shift key returns shift category")
    func shiftCategory() {
        let symbol = KeySymbol(id: "shift-left", display: "⇧", isModifier: true)
        #expect(KeyCodeMapper.category(for: symbol) == .shift)

        let symbolRight = KeySymbol(id: "shift-right", display: "⇧", isModifier: true)
        #expect(KeyCodeMapper.category(for: symbolRight) == .shift)
    }

    @Test("Option key returns option category")
    func optionCategory() {
        let symbol = KeySymbol(id: "option-left", display: "⌥", isModifier: true)
        #expect(KeyCodeMapper.category(for: symbol) == .option)

        let symbolRight = KeySymbol(id: "option-right", display: "⌥", isModifier: true)
        #expect(KeyCodeMapper.category(for: symbolRight) == .option)
    }

    @Test("Control key returns control category")
    func controlCategory() {
        let symbol = KeySymbol(id: "control-left", display: "⌃", isModifier: true)
        #expect(KeyCodeMapper.category(for: symbol) == .control)

        let symbolRight = KeySymbol(id: "control-right", display: "⌃", isModifier: true)
        #expect(KeyCodeMapper.category(for: symbolRight) == .control)
    }

    @Test("Fn key returns command category")
    func fnCategory() {
        let symbol = KeySymbol(id: "fn", display: "fn", isModifier: true)
        #expect(KeyCodeMapper.category(for: symbol) == .command)
    }

    @Test("Escape key returns escape category")
    func escapeCategory() {
        let symbol = KeySymbol(id: "escape", display: "ESC", isSpecial: true)
        #expect(KeyCodeMapper.category(for: symbol) == .escape)
    }

    @Test("Function keys return function category")
    func functionCategory() {
        let functionKeys = ["f1", "f2", "f3", "f10", "f12", "f20"]
        for keyId in functionKeys {
            let symbol = KeySymbol(id: keyId, display: keyId.uppercased(), isSpecial: true)
            #expect(KeyCodeMapper.category(for: symbol) == .function, "Key \(keyId) should be function category")
        }
    }

    @Test("Arrow keys return navigation category")
    func arrowCategory() {
        let arrowKeys = [
            ("arrow-left", "←"),
            ("arrow-right", "→"),
            ("arrow-up", "↑"),
            ("arrow-down", "↓"),
        ]
        for (id, display) in arrowKeys {
            let symbol = KeySymbol(id: id, display: display, isSpecial: true)
            #expect(KeyCodeMapper.category(for: symbol) == .navigation, "Key \(id) should be navigation category")
        }
    }

    @Test("Navigation keys return navigation category")
    func navigationCategory() {
        let navKeys = [
            ("home", "↖"),
            ("end", "↘"),
            ("page-up", "⇞"),
            ("page-down", "⇟"),
        ]
        for (id, display) in navKeys {
            let symbol = KeySymbol(id: id, display: display, isSpecial: true)
            #expect(KeyCodeMapper.category(for: symbol) == .navigation, "Key \(id) should be navigation category")
        }
    }

    @Test("Editing keys return editing category")
    func editingCategory() {
        let editingKeys = [
            ("space", "␣"),
            ("tab", "⇥"),
            ("return", "⏎"),
            ("enter", "⌤"),
            ("delete", "⌫"),
            ("forward-delete", "⌦"),
        ]
        for (id, display) in editingKeys {
            let symbol = KeySymbol(id: id, display: display, isSpecial: true)
            #expect(KeyCodeMapper.category(for: symbol) == .editing, "Key \(id) should be editing category")
        }
    }

    @Test("Letter keys return letter category")
    func letterCategory() {
        let letterSymbol = KeySymbol(id: "key-0", display: "A")
        #expect(KeyCodeMapper.category(for: letterSymbol) == .letter)

        let numberSymbol = KeySymbol(id: "key-18", display: "1")
        #expect(KeyCodeMapper.category(for: numberSymbol) == .letter)

        let punctSymbol = KeySymbol(id: "key-27", display: ";")
        #expect(KeyCodeMapper.category(for: punctSymbol) == .letter)
    }
}
