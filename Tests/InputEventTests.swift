import CoreGraphics
import Foundation
import Testing
@testable import KeypressCore

@Suite("Input Events")
struct InputEventTests {
    @Test("Pointer event preserves normalized payload")
    func pointerPayload() {
        let timestamp: TimeInterval = 42.5
        let pointer = PointerEvent(
            kind: .buttonDown(button: .left, clickCount: 2),
            location: CGPoint(x: 120, y: 240),
            modifiers: .maskCommand,
            timestamp: timestamp)

        #expect(pointer.kind == .buttonDown(button: .left, clickCount: 2))
        #expect(pointer.location == CGPoint(x: 120, y: 240))
        #expect(pointer.modifiers == .maskCommand)
        #expect(pointer.timestamp == timestamp)
        #expect(InputEvent.pointer(pointer) == .pointer(pointer))
    }

    @Test("Pointer button numbers map to stable cases")
    func pointerButtons() {
        #expect(PointerButton(buttonNumber: 0) == .left)
        #expect(PointerButton(buttonNumber: 1) == .right)
        #expect(PointerButton(buttonNumber: 2) == .middle)
        #expect(PointerButton(buttonNumber: 8) == .other(8))
    }

    @Test("Input masks compose without overlapping")
    func masks() {
        #expect(InputEventMask.all.contains(.keyboard))
        #expect(InputEventMask.all.contains(.pointer))
        #expect(InputEventMask.pointer.contains(.scroll))
        #expect(!InputEventMask.keyboard.contains(.pointerMovement))
    }
}

@Suite("Keyboard Event Filters")
struct KeyboardEventFilterTests {
    @Test("Shortcuts-only mode rejects plain keys")
    func rejectsPlainKeys() {
        let settings = KeyboardSettings(contentMode: .shortcutsOnly)
        let event = KeyEvent(type: .keyDown, keyCode: 0, modifiers: [])
        let symbol = KeySymbol(id: "key-a", display: "A")

        #expect(
            KeyboardEventFilter.disposition(
                for: event,
                symbol: symbol,
                settings: settings) == .ignore)
    }

    @Test("Shortcuts-only mode accepts modified keys")
    func acceptsShortcut() {
        let settings = KeyboardSettings(contentMode: .shortcutsOnly)
        let event = KeyEvent(type: .keyDown, keyCode: 0, modifiers: .maskCommand)
        let symbol = KeySymbol(id: "key-a", display: "A")

        #expect(
            KeyboardEventFilter.disposition(
                for: event,
                symbol: symbol,
                settings: settings) == .display)
    }

    @Test("Enabled function and special categories override shortcuts-only mode")
    func acceptsEnabledSpecialCategories() {
        let settings = KeyboardSettings(contentMode: .shortcutsOnly)
        let event = KeyEvent(type: .keyDown, keyCode: 0x7A, modifiers: [])

        #expect(
            KeyboardEventFilter.disposition(
                for: event,
                symbol: KeySymbol(id: "f1", display: "F1", isSpecial: true),
                settings: settings) == .display)
        #expect(
            KeyboardEventFilter.disposition(
                for: event,
                symbol: KeySymbol(id: "return", display: "⏎", isSpecial: true),
                settings: settings) == .display)
    }

    @Test("Hidden standalone modifiers remain trackable")
    func tracksHiddenModifier() {
        var settings = KeyboardSettings()
        settings.filters.showStandaloneModifiers = false
        let event = KeyEvent(type: .flagsChanged, keyCode: 0x37, modifiers: .maskCommand)
        let symbol = KeySymbol(id: "command-left", display: "⌘", isModifier: true)

        #expect(
            KeyboardEventFilter.disposition(
                for: event,
                symbol: symbol,
                settings: settings) == .trackOnly)
    }

    @Test("Function and special filters use key categories")
    func categoryFilters() {
        var settings = KeyboardSettings()
        settings.filters.showFunctionKeys = false
        settings.filters.showSpecialKeys = false
        let event = KeyEvent(type: .keyDown, keyCode: 0, modifiers: [])

        #expect(
            KeyboardEventFilter.disposition(
                for: event,
                symbol: KeySymbol(id: "f1", display: "F1", isSpecial: true),
                settings: settings) == .ignore)
        #expect(
            KeyboardEventFilter.disposition(
                for: event,
                symbol: KeySymbol(id: "return", display: "⏎", isSpecial: true),
                settings: settings) == .ignore)
    }
}
