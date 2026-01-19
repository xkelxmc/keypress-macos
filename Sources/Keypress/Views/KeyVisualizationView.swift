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
            config: self.config)
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
            config: self.config)
    }
}

/// Shared visualization content (used by both modes).
private struct KeyVisualizationContent: View {
    let pressedKeys: [PressedKey]
    let hasKeys: Bool
    let config: KeypressConfig

    var body: some View {
        let keysView = HStack(spacing: 6) {
            ForEach(self.pressedKeys) { key in
                KeyCapView(symbol: key.symbol, config: self.config)
            }
        }

        Group {
            switch self.config.keyboardFrameStyle {
            case .frame:
                KeyboardFrameView(config: self.config) {
                    keysView
                }
            case .overlay:
                keysView
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.black.opacity(0.7))
                            .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8))
            case .none:
                keysView
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
            }
        }
        .scaleEffect(self.config.size.scaleFactor)
        .opacity(self.hasKeys ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: self.hasKeys)
    }
}

// MARK: - KeyboardFrameView

/// 3D keyboard frame container that wraps keycaps.
/// Creates a realistic "keyboard fragment" appearance with depth and materials.
struct KeyboardFrameView<Content: View>: View {
    let config: KeypressConfig
    @ViewBuilder let content: () -> Content

    // MARK: - Layout Constants

    private let outerCornerRadius: CGFloat = 16
    private let innerCornerRadius: CGFloat = 12
    private let frameThickness: CGFloat = 10
    private let depth: CGFloat = 4

    // MARK: - Colors

    /// Whether we're in a light color scheme.
    private var isLightMode: Bool {
        self.config.appearanceMode == .light ||
            (self.config.appearanceMode == .auto && !self.systemIsDark())
    }

    private func systemIsDark() -> Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Frame base color — dark aluminum or light aluminum.
    private var frameColor: Color {
        self.isLightMode
            ? Color(red: 0.85, green: 0.85, blue: 0.87)
            : Color(red: 0.12, green: 0.12, blue: 0.14)
    }

    /// Inner well color — where keys sit.
    private var wellColor: Color {
        self.isLightMode
            ? Color(red: 0.75, green: 0.75, blue: 0.78)
            : Color(red: 0.06, green: 0.06, blue: 0.08)
    }

    /// Highlight for top edge.
    private var highlightColor: Color {
        self.isLightMode
            ? Color.white.opacity(0.8)
            : Color.white.opacity(0.15)
    }

    /// Shadow color for inner well.
    private var innerShadowColor: Color {
        self.isLightMode
            ? Color.black.opacity(0.15)
            : Color.black.opacity(0.6)
    }

    // MARK: - Body

    var body: some View {
        self.content()
            .padding(.horizontal, self.frameThickness + 4)
            .padding(.vertical, self.frameThickness + 2)
            .background(
                ZStack {
                    // Outer drop shadow
                    RoundedRectangle(cornerRadius: self.outerCornerRadius)
                        .fill(Color.black.opacity(0.5))
                        .blur(radius: 20)
                        .offset(y: 8)

                    // Main frame body
                    self.frameBody

                    // Inner well (recessed area)
                    self.innerWell
                })
    }

    // MARK: - Frame Components

    /// The main frame body with gradient for 3D effect.
    private var frameBody: some View {
        RoundedRectangle(cornerRadius: self.outerCornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        self.frameColor.lighter(by: 0.08),
                        self.frameColor,
                        self.frameColor.darker(by: 0.05),
                    ],
                    startPoint: .top,
                    endPoint: .bottom))
            .overlay(
                // Subtle outer border
                RoundedRectangle(cornerRadius: self.outerCornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                self.highlightColor,
                                Color.clear,
                                Color.black.opacity(self.isLightMode ? 0.1 : 0.3),
                            ],
                            startPoint: .top,
                            endPoint: .bottom),
                        lineWidth: 1))
    }

    /// The recessed inner well where keys sit.
    private var innerWell: some View {
        GeometryReader { geometry in
            let wellWidth = geometry.size.width - self.frameThickness * 2
            let wellHeight = geometry.size.height - self.frameThickness * 2

            ZStack {
                // Well base
                RoundedRectangle(cornerRadius: self.innerCornerRadius)
                    .fill(self.wellColor)
                    .frame(width: wellWidth, height: wellHeight)

                // Inner shadow (top and left) for depth
                RoundedRectangle(cornerRadius: self.innerCornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                self.innerShadowColor,
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .center))
                    .frame(width: wellWidth, height: wellHeight)

                // Inner border
                RoundedRectangle(cornerRadius: self.innerCornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(self.isLightMode ? 0.2 : 0.5),
                                Color.black.opacity(self.isLightMode ? 0.1 : 0.3),
                                self.isLightMode ? Color.white.opacity(0.3) : Color.white.opacity(0.05),
                            ],
                            startPoint: .top,
                            endPoint: .bottom),
                        lineWidth: 1.5)
                    .frame(width: wellWidth, height: wellHeight)
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    /// Subtle highlight along the top edge for a polished look.
    private var topHighlight: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            self.highlightColor,
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom))
                .frame(width: geometry.size.width * 0.6, height: 2)
                .position(x: geometry.size.width / 2, y: 1.5)
        }
    }
}

// MARK: - Color Extensions

extension Color {
    fileprivate func lighter(by amount: Double) -> Color {
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor.gray
        return Color(
            red: min(1.0, Double(nsColor.redComponent) + amount),
            green: min(1.0, Double(nsColor.greenComponent) + amount),
            blue: min(1.0, Double(nsColor.blueComponent) + amount))
    }

    fileprivate func darker(by amount: Double) -> Color {
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor.gray
        return Color(
            red: max(0.0, Double(nsColor.redComponent) - amount),
            green: max(0.0, Double(nsColor.greenComponent) - amount),
            blue: max(0.0, Double(nsColor.blueComponent) - amount))
    }
}

// MARK: - Previews

#Preview("Key Visualization") {
    @Previewable @State var keyState = KeyState()

    KeyVisualizationView(keyState: keyState, config: KeypressConfig.shared)
        .frame(width: 400, height: 120)
        .background(Color.gray.opacity(0.3))
        .onAppear {
            Task { @MainActor in
                keyState.processEvent(
                    KeyEvent(type: .keyDown, keyCode: 0x37, modifiers: .maskCommand),
                    symbol: KeySymbol(id: "cmd", display: "⌘", isModifier: true))
                keyState.processEvent(
                    KeyEvent(type: .keyDown, keyCode: 0x38, modifiers: .maskShift),
                    symbol: KeySymbol(id: "shift", display: "⇧", isModifier: true))
                keyState.processEvent(
                    KeyEvent(type: .keyDown, keyCode: 0x00, modifiers: []),
                    symbol: KeySymbol(id: "k", display: "K"))
            }
        }
}

#Preview("Keyboard Frame Dark") {
    KeyboardFrameView(config: KeypressConfig.shared) {
        HStack(spacing: 6) {
            KeyCapView(symbol: KeySymbol(id: "command-left", display: "⌘", isModifier: true))
            KeyCapView(symbol: KeySymbol(id: "shift-left", display: "⇧", isModifier: true))
            KeyCapView(symbol: KeySymbol(id: "a", display: "A"))
        }
    }
    .padding(60)
    .background(Color.black)
}

#Preview("Without Frame") {
    HStack(spacing: 6) {
        KeyCapView(symbol: KeySymbol(id: "command-left", display: "⌘", isModifier: true))
        KeyCapView(symbol: KeySymbol(id: "shift-left", display: "⇧", isModifier: true))
        KeyCapView(symbol: KeySymbol(id: "a", display: "A"))
    }
    .padding(16)
    .padding(60)
    .background(Color.black)
}
