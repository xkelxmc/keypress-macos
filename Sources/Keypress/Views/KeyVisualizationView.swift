import KeypressCore
import SwiftUI

/// Simple view displaying pressed keys as styled text.
/// MVP version — will be replaced with skeuomorphic design in Phase 3.
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

/// Simple badge view for a single key.
struct KeyBadgeView: View {
    let symbol: KeySymbol

    var body: some View {
        Text(self.symbol.display)
            .font(.system(size: self.fontSize, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .frame(minWidth: self.minWidth, minHeight: 36)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(self.symbol.isModifier ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
    }

    private var fontSize: CGFloat {
        // Smaller font for text keys, larger for symbols
        self.symbol.display.count == 1 ? 20 : 16
    }

    private var minWidth: CGFloat {
        self.symbol.isModifier ? 36 : 28
    }
}

#Preview("Key Visualization") {
    @Previewable @State var keyState = KeyState()

    KeyVisualizationView(keyState: keyState, config: KeypressConfig.shared)
        .frame(width: 500, height: 120)
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
                    symbol: KeySymbol(id: "a", display: "A")
                )
            }
        }
}
