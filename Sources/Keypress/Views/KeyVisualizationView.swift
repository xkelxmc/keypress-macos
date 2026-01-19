import KeypressCore
import SwiftUI

/// Simple view displaying pressed keys as styled keycaps.
struct KeyVisualizationView: View {
    @Bindable var keyState: KeyState
    let config: KeypressConfig

    var body: some View {
        KeyVisualizationContent(
            pressedKeys: self.keyState.pressedKeys,
            hasKeys: self.keyState.hasKeys,
            config: self.config
        )
    }
}

/// View for Single mode (SingleKeyState).
struct SingleKeyVisualizationView: View {
    @Bindable var keyState: SingleKeyState
    let config: KeypressConfig

    var body: some View {
        KeyVisualizationContent(
            pressedKeys: self.keyState.pressedKeys,
            hasKeys: self.keyState.hasKeys,
            config: self.config
        )
    }
}

/// Shared visualization content (used by both modes).
private struct KeyVisualizationContent: View {
    let pressedKeys: [PressedKey]
    let hasKeys: Bool
    let config: KeypressConfig

    var body: some View {
        HStack(spacing: 6) {
            ForEach(self.pressedKeys) { key in
                KeyCapView(symbol: key.symbol, config: self.config)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.7))
                .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
        )
        .scaleEffect(self.config.size.scaleFactor)
        .opacity(self.hasKeys ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: self.hasKeys)
    }
}

#Preview("Key Visualization") {
    @Previewable @State var keyState = KeyState()

    KeyVisualizationView(keyState: keyState, config: KeypressConfig.shared)
        .frame(width: 400, height: 120)
        .background(Color.gray.opacity(0.3))
        .onAppear {
            Task { @MainActor in
                keyState.processEvent(
                    KeyEvent(type: .keyDown, keyCode: 0x37, modifiers: .maskCommand),
                    symbol: KeySymbol(id: "cmd", display: "⌘", isModifier: true)
                )
                keyState.processEvent(
                    KeyEvent(type: .keyDown, keyCode: 0x38, modifiers: .maskShift),
                    symbol: KeySymbol(id: "shift", display: "⇧", isModifier: true)
                )
                keyState.processEvent(
                    KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
                    symbol: KeySymbol(id: "k", display: "K")
                )
            }
        }
}
