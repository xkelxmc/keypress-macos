import KeypressCore
import SwiftUI

// MARK: - KeyCapSize

/// Size category for keycap rendering.
enum KeyCapSize {
    case standard   // Regular letter keys
    case modifier   // ⌘ ⌥ ⌃ ⇧
    case wide       // Space bar, Tab, Enter

    var width: CGFloat {
        switch self {
        case .standard: 44
        case .modifier: 52
        case .wide: 72
        }
    }

    var height: CGFloat { 44 }

    static func from(symbol: KeySymbol) -> KeyCapSize {
        if symbol.isModifier {
            return .modifier
        }

        switch symbol.id {
        case "space", "tab", "return", "enter", "delete", "forward-delete":
            return .wide
        default:
            return .standard
        }
    }
}

// MARK: - KeyCapView

/// Skeuomorphic 3D mechanical keycap view.
/// Renders a realistic keycap with top surface, sides, and shadow.
struct KeyCapView: View {
    let symbol: KeySymbol
    let isPressed: Bool

    init(symbol: KeySymbol, isPressed: Bool = true) {
        self.symbol = symbol
        self.isPressed = isPressed
    }

    // MARK: - Layout Constants

    private var size: KeyCapSize {
        KeyCapSize.from(symbol: self.symbol)
    }

    private let cornerRadius: CGFloat = 6
    private let depthOffset: CGFloat = 4
    private let shadowBlur: CGFloat = 6
    private let pressedOffset: CGFloat = 2

    // MARK: - Colors

    /// Top surface color (lighter)
    private var topColor: Color {
        self.symbol.isModifier
            ? Color(light: .init(white: 0.92, alpha: 1), dark: .init(white: 0.28, alpha: 1))
            : Color(light: .init(white: 0.96, alpha: 1), dark: .init(white: 0.24, alpha: 1))
    }

    /// Side/body color (darker)
    private var sideColor: Color {
        self.symbol.isModifier
            ? Color(light: .init(white: 0.82, alpha: 1), dark: .init(white: 0.18, alpha: 1))
            : Color(light: .init(white: 0.88, alpha: 1), dark: .init(white: 0.15, alpha: 1))
    }

    /// Border color
    private var borderColor: Color {
        Color(light: .init(white: 0.7, alpha: 1), dark: .init(white: 0.35, alpha: 1))
    }

    /// Text color
    private var textColor: Color {
        Color(light: .init(white: 0.1, alpha: 1), dark: .init(white: 0.95, alpha: 1))
    }

    /// Shadow color
    private var shadowColor: Color {
        Color.black.opacity(0.25)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Base shadow (beneath the key)
            self.baseShadow

            // Key body (sides visible when not pressed)
            self.keyBody

            // Top surface (the pressable cap)
            self.topSurface
        }
        .frame(width: self.size.width, height: self.size.height + self.depthOffset)
    }

    // MARK: - Subviews

    /// Shadow beneath the keycap.
    private var baseShadow: some View {
        RoundedRectangle(cornerRadius: self.cornerRadius)
            .fill(self.shadowColor)
            .frame(width: self.size.width - 2, height: self.size.height - 2)
            .blur(radius: self.isPressed ? self.shadowBlur * 0.5 : self.shadowBlur)
            .offset(y: self.isPressed ? self.depthOffset * 0.5 : self.depthOffset + 2)
    }

    /// The keycap body (darker sides).
    private var keyBody: some View {
        RoundedRectangle(cornerRadius: self.cornerRadius + 1)
            .fill(self.sideColor)
            .frame(width: self.size.width, height: self.size.height + self.depthOffset)
            .overlay(
                RoundedRectangle(cornerRadius: self.cornerRadius + 1)
                    .strokeBorder(self.borderColor, lineWidth: 0.5)
            )
    }

    /// The top surface of the keycap.
    private var topSurface: some View {
        ZStack {
            // Main surface
            RoundedRectangle(cornerRadius: self.cornerRadius)
                .fill(self.topColor)
                .frame(width: self.size.width - 4, height: self.size.height - 4)

            // Inner border for depth
            RoundedRectangle(cornerRadius: self.cornerRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.4),
                            Color.black.opacity(0.1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .frame(width: self.size.width - 4, height: self.size.height - 4)

            // Key label
            Text(self.symbol.display)
                .font(.system(size: self.fontSize, weight: .medium, design: .rounded))
                .foregroundColor(self.textColor)
        }
        .offset(y: self.isPressed ? 0 : -self.pressedOffset)
        .animation(.easeOut(duration: 0.05), value: self.isPressed)
    }

    // MARK: - Helpers

    private var fontSize: CGFloat {
        let display = self.symbol.display

        // Single character symbols get larger font
        if display.count == 1 {
            return 18
        }

        // Function keys and longer text get smaller font
        if display.hasPrefix("F") || display.count > 2 {
            return 12
        }

        return 14
    }
}

// MARK: - Color Extension

private extension Color {
    /// Creates a color that adapts to light/dark mode.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

// MARK: - Previews

#Preview("Single Keycap") {
    VStack(spacing: 20) {
        HStack(spacing: 8) {
            KeyCapView(symbol: KeySymbol(id: "a", display: "A"))
            KeyCapView(symbol: KeySymbol(id: "cmd", display: "⌘", isModifier: true))
            KeyCapView(symbol: KeySymbol(id: "space", display: "␣"))
        }

        HStack(spacing: 8) {
            KeyCapView(symbol: KeySymbol(id: "shift", display: "⇧", isModifier: true))
            KeyCapView(symbol: KeySymbol(id: "k", display: "K"))
            KeyCapView(symbol: KeySymbol(id: "return", display: "⏎"))
        }

        HStack(spacing: 8) {
            KeyCapView(symbol: KeySymbol(id: "esc", display: "⎋"))
            KeyCapView(symbol: KeySymbol(id: "delete", display: "⌫"))
            KeyCapView(symbol: KeySymbol(id: "f12", display: "F12"))
        }
    }
    .padding(40)
    .background(Color.gray.opacity(0.2))
}

#Preview("Pressed States") {
    HStack(spacing: 20) {
        VStack {
            KeyCapView(symbol: KeySymbol(id: "a", display: "A"), isPressed: false)
            Text("Resting").font(.caption)
        }
        VStack {
            KeyCapView(symbol: KeySymbol(id: "a", display: "A"), isPressed: true)
            Text("Pressed").font(.caption)
        }
    }
    .padding(40)
    .background(Color.gray.opacity(0.2))
}
