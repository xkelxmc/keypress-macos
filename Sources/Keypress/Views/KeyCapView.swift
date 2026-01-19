import KeypressCore
import SwiftUI

// MARK: - KeyCapSize

/// Size category for keycap rendering.
enum KeyCapSize {
    case standard // Regular letter keys (1u)
    case modifier // ⌘ ⌥ ⌃ ⇧ — wider with icon+label
    case wide // Space bar, Tab, Enter

    var width: CGFloat {
        switch self {
        case .standard: 48
        case .modifier: 72
        case .wide: 80
        }
    }

    var height: CGFloat {
        switch self {
        case .standard: 48
        case .modifier: 48
        case .wide: 48
        }
    }

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

// MARK: - ModifierInfo

/// Display info for modifier keys (icon + label).
private struct ModifierInfo {
    let icon: String
    let label: String

    static func from(symbolId: String) -> ModifierInfo? {
        switch symbolId {
        case "command-left", "command-right", "command":
            ModifierInfo(icon: "⌘", label: "command")
        case "shift-left", "shift-right", "shift":
            ModifierInfo(icon: "⇧", label: "shift")
        case "option-left", "option-right", "option":
            ModifierInfo(icon: "⌥", label: "option")
        case "control-left", "control-right", "control":
            ModifierInfo(icon: "⌃", label: "control")
        case "capslock":
            ModifierInfo(icon: "⇪", label: "caps lock")
        case "fn":
            ModifierInfo(icon: "fn", label: "")
        default:
            nil
        }
    }
}

// MARK: - KeyCapView

/// Skeuomorphic 3D mechanical keycap view.
/// Renders a realistic keycap with depth, beveled edges, and shadows.
struct KeyCapView: View {
    let symbol: KeySymbol
    let config: KeypressConfig

    init(symbol: KeySymbol, config: KeypressConfig = .shared) {
        self.symbol = symbol
        self.config = config
    }

    // MARK: - Layout Constants

    private var size: KeyCapSize {
        KeyCapSize.from(symbol: self.symbol)
    }

    private var category: KeyCategory {
        KeyCodeMapper.category(for: self.symbol)
    }

    private var style: KeyCategoryStyle {
        self.config.effectiveStyle(for: self.category)
    }

    /// Corner radius based on style setting (0.0-1.0 maps to 2-12).
    private var cornerRadius: CGFloat {
        let minRadius: CGFloat = 2
        let maxRadius: CGFloat = 12
        return minRadius + (maxRadius - minRadius) * self.style.cornerRadius
    }

    /// Depth based on style setting (0.0-1.0 maps to 0-6).
    private var depth: CGFloat {
        6 * self.style.depth
    }

    private let topInset: CGFloat = 3

    // MARK: - Colors

    private var baseColor: Color {
        self.style.color.color
    }

    /// Lighter version for top surface highlight.
    private var highlightColor: Color {
        self.baseColor.opacity(0.95)
    }

    /// Darker version for sides/depth.
    private var sideColor: Color {
        Color.black.opacity(0.5)
    }

    /// Text color based on background brightness.
    private var textColor: Color {
        let keyColor = self.style.color
        let brightness = (keyColor.red + keyColor.green + keyColor.blue) / 3
        return brightness > 0.5 ? .black : .white
    }

    // MARK: - Body

    var body: some View {
        switch self.style.style {
        case .mechanical:
            self.mechanicalBody
        case .flat:
            self.flatBody
        case .minimal:
            self.minimalBody
        }
    }

    // MARK: - Mechanical Style (3D skeuomorphic)

    private var mechanicalBody: some View {
        ZStack {
            // Shadow beneath key
            self.keyShadow

            // Key well (the dark "hole" the key sits in)
            self.keyWell

            // The 3D keycap itself
            self.keycap
        }
        .frame(width: self.size.width, height: self.size.height + self.depth)
    }

    // MARK: - Flat Style (modern flat design)

    private var flatBody: some View {
        ZStack {
            // Subtle drop shadow
            RoundedRectangle(cornerRadius: self.cornerRadius)
                .fill(Color.black.opacity(0.3 * self.style.shadowIntensity))
                .blur(radius: 4)
                .offset(y: 2)

            // Main surface
            RoundedRectangle(cornerRadius: self.cornerRadius)
                .fill(self.baseColor)

            // Subtle top highlight
            RoundedRectangle(cornerRadius: self.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.0),
                        ],
                        startPoint: .top,
                        endPoint: .center))

            // Border
            RoundedRectangle(cornerRadius: self.cornerRadius)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)

            // Label
            self.keyLabel
        }
        .frame(width: self.size.width, height: self.size.height)
    }

    // MARK: - Minimal Style (text with background)

    private var minimalBody: some View {
        ZStack {
            // Simple pill background
            RoundedRectangle(cornerRadius: self.minimalCornerRadius)
                .fill(self.baseColor.opacity(0.85))

            // Subtle border
            RoundedRectangle(cornerRadius: self.minimalCornerRadius)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)

            // Label
            self.minimalLabel
        }
        .frame(width: self.minimalWidth, height: self.minimalHeight)
    }

    private var minimalCornerRadius: CGFloat {
        self.minimalHeight / 2 // Pill shape
    }

    private var minimalWidth: CGFloat {
        switch self.size {
        case .standard: 40
        case .modifier: 64
        case .wide: 72
        }
    }

    private var minimalHeight: CGFloat {
        32
    }

    /// Label for minimal style (smaller, more compact).
    @ViewBuilder
    private var minimalLabel: some View {
        if self.symbol.isModifier, let info = ModifierInfo.from(symbolId: self.symbol.id) {
            // Modifier: icon + label inline
            HStack(spacing: 3) {
                Text(info.icon)
                    .font(.system(size: 13, weight: .medium))
                if !info.label.isEmpty {
                    Text(info.label)
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .foregroundColor(self.textColor)
        } else {
            // Regular key
            Text(self.symbol.display)
                .font(.system(size: self.minimalFontSize, weight: .medium))
                .foregroundColor(self.textColor)
        }
    }

    private var minimalFontSize: CGFloat {
        let display = self.symbol.display
        if display.count == 1 {
            return 15
        }
        if display.hasPrefix("F") || display.count > 2 {
            return 10
        }
        return 12
    }

    // MARK: - Subviews

    /// Soft shadow beneath the entire key.
    private var keyShadow: some View {
        RoundedRectangle(cornerRadius: self.cornerRadius + 2)
            .fill(Color.black.opacity(0.4 * self.style.shadowIntensity))
            .frame(width: self.size.width - 2, height: self.size.height)
            .blur(radius: 8)
            .offset(y: self.depth + 4)
    }

    /// The dark well/recess the key sits in.
    private var keyWell: some View {
        RoundedRectangle(cornerRadius: self.cornerRadius + 2)
            .fill(Color.black.opacity(0.85))
            .frame(width: self.size.width, height: self.size.height + self.depth)
    }

    /// The 3D keycap with top surface and beveled sides.
    private var keycap: some View {
        ZStack {
            // Side/bevel (visible depth)
            self.keycapSides

            // Top surface
            self.keycapTop
        }
        .offset(y: -self.depth / 2)
    }

    /// The visible sides of the keycap (creates 3D depth effect).
    private var keycapSides: some View {
        ZStack {
            // Bottom edge (darkest)
            RoundedRectangle(cornerRadius: self.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            self.baseColor.opacity(0.3),
                            self.baseColor.opacity(0.15),
                        ],
                        startPoint: .top,
                        endPoint: .bottom))
                .frame(width: self.size.width - 2, height: self.size.height)
                .offset(y: self.depth / 2)
        }
    }

    /// The top pressable surface of the keycap.
    private var keycapTop: some View {
        ZStack {
            // Main surface with gradient for concave effect
            RoundedRectangle(cornerRadius: self.cornerRadius - 1)
                .fill(
                    LinearGradient(
                        colors: [
                            self.baseColor.lighter(by: 0.1),
                            self.baseColor,
                            self.baseColor.darker(by: 0.05),
                        ],
                        startPoint: .top,
                        endPoint: .bottom))
                .frame(
                    width: self.size.width - self.topInset * 2,
                    height: self.size.height - self.topInset * 2)

            // Subtle inner border for depth
            RoundedRectangle(cornerRadius: self.cornerRadius - 1)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.25),
                            Color.white.opacity(0.05),
                            Color.black.opacity(0.1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom),
                    lineWidth: 1)
                .frame(
                    width: self.size.width - self.topInset * 2,
                    height: self.size.height - self.topInset * 2)

            // Key label
            self.keyLabel
        }
        .offset(y: -self.depth / 2 + 1)
    }

    /// The label displayed on the keycap.
    @ViewBuilder
    private var keyLabel: some View {
        if self.symbol.isModifier, let info = ModifierInfo.from(symbolId: self.symbol.id) {
            // Modifier: icon + label stacked
            VStack(spacing: 2) {
                Text(info.icon)
                    .font(.system(size: 16, weight: .medium))
                if !info.label.isEmpty {
                    Text(info.label)
                        .font(.system(size: 9, weight: .medium))
                }
            }
            .foregroundColor(self.textColor)
        } else {
            // Regular key: single label
            Text(self.symbol.display)
                .font(.system(size: self.fontSize, weight: .medium, design: .default))
                .foregroundColor(self.textColor)
        }
    }

    // MARK: - Helpers

    private var fontSize: CGFloat {
        let display = self.symbol.display

        // Single character symbols get larger font
        if display.count == 1 {
            return 20
        }

        // Function keys and longer text get smaller font
        if display.hasPrefix("F") || display.count > 2 {
            return 12
        }

        return 16
    }
}

// MARK: - Color Extensions

extension Color {
    /// Returns a lighter version of the color.
    fileprivate func lighter(by amount: Double) -> Color {
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor.gray
        return Color(
            red: min(1.0, Double(nsColor.redComponent) + amount),
            green: min(1.0, Double(nsColor.greenComponent) + amount),
            blue: min(1.0, Double(nsColor.blueComponent) + amount))
    }

    /// Returns a darker version of the color.
    fileprivate func darker(by amount: Double) -> Color {
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor.gray
        return Color(
            red: max(0.0, Double(nsColor.redComponent) - amount),
            green: max(0.0, Double(nsColor.greenComponent) - amount),
            blue: max(0.0, Double(nsColor.blueComponent) - amount))
    }
}

// MARK: - Previews

#Preview("All Key Types") {
    let config = KeypressConfig.shared

    VStack(spacing: 16) {
        // Modifiers
        HStack(spacing: 8) {
            KeyCapView(symbol: KeySymbol(id: "command-left", display: "⌘", isModifier: true), config: config)
            KeyCapView(symbol: KeySymbol(id: "shift-left", display: "⇧", isModifier: true), config: config)
            KeyCapView(symbol: KeySymbol(id: "option-left", display: "⌥", isModifier: true), config: config)
            KeyCapView(symbol: KeySymbol(id: "control-left", display: "⌃", isModifier: true), config: config)
        }

        // Letters
        HStack(spacing: 8) {
            KeyCapView(symbol: KeySymbol(id: "a", display: "A"), config: config)
            KeyCapView(symbol: KeySymbol(id: "k", display: "K"), config: config)
            KeyCapView(symbol: KeySymbol(id: "1", display: "1"), config: config)
        }

        // Special keys
        HStack(spacing: 8) {
            KeyCapView(symbol: KeySymbol(id: "escape", display: "⎋", isSpecial: true), config: config)
            KeyCapView(symbol: KeySymbol(id: "delete", display: "⌫", isSpecial: true), config: config)
            KeyCapView(symbol: KeySymbol(id: "return", display: "⏎", isSpecial: true), config: config)
        }

        // Function keys
        HStack(spacing: 8) {
            KeyCapView(symbol: KeySymbol(id: "f1", display: "F1", isSpecial: true), config: config)
            KeyCapView(symbol: KeySymbol(id: "f12", display: "F12", isSpecial: true), config: config)
        }
    }
    .padding(40)
    .background(Color.black)
}

#Preview("Combination") {
    HStack(spacing: 6) {
        KeyCapView(symbol: KeySymbol(id: "shift-left", display: "⇧", isModifier: true))
        KeyCapView(symbol: KeySymbol(id: "command-left", display: "⌘", isModifier: true))
        KeyCapView(symbol: KeySymbol(id: "a", display: "A"))
    }
    .padding(16)
    .background(
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.3)))
    .padding(40)
    .background(Color.black)
}
