import KeypressCore
import SwiftUI

/// Simple view displaying pressed keys as styled text.
/// MVP version — will be replaced with skeuomorphic design in Phase 3.
struct KeyVisualizationView: View {
    @Bindable var keyState: KeyState
    let config: KeypressConfig

    var body: some View {
        HStack(spacing: 8) {
            ForEach(self.keyState.pressedKeys) { key in
                KeyBadgeView(symbol: key.symbol)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .opacity(self.keyState.hasKeys ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: self.keyState.hasKeys)
        .scaleEffect(self.config.size.scaleFactor)
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
        .frame(width: 400, height: 100)
        .background(Color.gray.opacity(0.2))
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
