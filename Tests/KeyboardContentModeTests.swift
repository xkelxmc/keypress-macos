import Testing
@testable import KeypressCore

@Suite("Keyboard Content Modes")
struct KeyboardContentModeTests {
    private let functionKey = KeySymbol(id: "f1", display: "F1", isSpecial: true)

    @Test("Function keys remain visible without modifiers in shortcuts-only mode")
    @MainActor
    func functionKeyOverride() {
        let state = SingleKeyState()
        state.contentMode = .shortcutsOnly

        state.processEvent(
            KeyEvent(type: .keyDown, keyCode: 0x7A, modifiers: []),
            symbol: self.functionKey)

        #expect(state.pressedKeys.contains { $0.symbol.id == self.functionKey.id })
    }
}
