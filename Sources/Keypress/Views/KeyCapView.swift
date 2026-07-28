import AppKit
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
    /// Whether the key is physically pressed (for modifiers only).
    /// Affects visual appearance: pressed keys appear pushed down.
    let isPressed: Bool
    /// Whether to delay press animation (when overlay just appeared).
    let delayPressAnimation: Bool

    /// Local state to delay press animation on appear.
    /// This creates a visible "press down" effect when key first appears.
    @State private var showPressedState: Bool = false
    /// Task for delayed press animation.
    @State private var pressDelayTask: Task<Void, Never>?

    init(
        symbol: KeySymbol,
        config: KeypressConfig = .shared,
        isPressed: Bool = false,
        delayPressAnimation: Bool = false)
    {
        self.symbol = symbol
        self.config = config
        self.isPressed = isPressed
        self.delayPressAnimation = delayPressAnimation
    }

    /// Effective pressed state — combines external isPressed with appear delay.
    private var effectivelyPressed: Bool {
        self.isPressed && (!self.delayPressAnimation || self.showPressedState)
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

    private var keyboardTheme: KeyboardTheme {
        self.config.effectiveTheme(isSystemDark: self.systemIsDark).keyboard
    }

    private var cornerRadius: CGFloat {
        let range: ClosedRange<CGFloat> = switch self.keyboardTheme.material {
        case .gaming: 2...6
        case .classic: 6...14
        case .aluminum: 4...11
        case .graphite, .monochrome, .glass, .minimal, .neon: 2...12
        }
        let minRadius = range.lowerBound
        let maxRadius = range.upperBound
        return minRadius + (maxRadius - minRadius) * self.style.cornerRadius
    }

    private var depth: CGFloat {
        let maximum: CGFloat = switch self.keyboardTheme.material {
        case .classic: 8
        case .gaming: 7
        case .aluminum: 4
        case .graphite, .monochrome, .glass, .minimal, .neon: 6
        }
        return maximum * self.style.depth
    }

    private var topInset: CGFloat {
        switch self.keyboardTheme.material {
        case .classic: 4.5
        case .gaming: 2
        case .graphite, .aluminum, .monochrome, .glass, .minimal, .neon: 3
        }
    }

    // MARK: - Colors

    private var baseColor: Color {
        self.style.color.color
    }

    private var textColor: Color {
        if self.config.appearance.keyboardThemeSelection == .system
            || self.config.appearance.keyboardThemeSelection == .dark
        {
            let keyColor = self.style.color
            let brightness = (keyColor.red + keyColor.green + keyColor.blue) / 3
            return brightness > 0.5 ? .black : .white
        }
        return self.keyboardTheme.textColor.color
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch self.style.style {
            case .mechanical:
                self.mechanicalBody
            case .flat:
                self.flatBody
            case .minimal:
                self.minimalBody
            }
        }
        .scaleEffect(x: self.pressScale.width, y: self.pressScale.height)
        .rotationEffect(.degrees(self.pressRotation))
        .shadow(
            color: self.pressGlowColor.opacity(self.pressGlowOpacity),
            radius: self.pressGlowRadius)
        .animation(self.pressAnimation, value: self.effectivelyPressed)
        .onAppear { self.scheduleShowPressed() }
        .onDisappear { self.pressDelayTask?.cancel() }
        .onChange(of: self.isPressed) { _, newValue in
            if newValue {
                self.scheduleShowPressed()
            } else {
                self.pressDelayTask?.cancel()
                self.showPressedState = false
            }
        }
    }

    // MARK: - Press Animation Constants

    /// Vertical offset when key is pressed (top surface moves down).
    private var pressOffset: CGFloat {
        guard self.effectivelyPressed else { return 0 }
        return switch self.keyboardTheme.pressEffect {
        case .travel: 2.5
        case .deepTravel: 4.5
        case .compress: 1.25
        case .scale: 0
        case .snap: 3
        case .glow: 0.75
        }
    }

    private var pressedDepthReduction: CGFloat {
        guard self.effectivelyPressed else { return 0 }
        return switch self.keyboardTheme.pressEffect {
        case .travel: 2
        case .deepTravel: 4
        case .compress: 1
        case .scale, .glow: 0
        case .snap: 2.5
        }
    }

    private var pressedShadowMultiplier: CGFloat {
        self.effectivelyPressed ? 0.5 : 1.0
    }

    private var flatPressOffset: CGFloat {
        guard self.effectivelyPressed else { return 0 }
        return switch self.keyboardTheme.pressEffect {
        case .travel: 1.5
        case .deepTravel: 2.5
        case .compress: 0.75
        case .scale, .glow: 0
        case .snap: 1.5
        }
    }

    private var pressScale: CGSize {
        guard self.effectivelyPressed else { return CGSize(width: 1, height: 1) }
        return switch self.keyboardTheme.pressEffect {
        case .travel, .deepTravel:
            CGSize(width: 1, height: 1)
        case .compress:
            CGSize(width: 0.98, height: 0.9)
        case .scale:
            CGSize(width: 0.94, height: 0.94)
        case .snap:
            CGSize(width: 0.96, height: 0.92)
        case .glow:
            CGSize(width: 1.025, height: 1.025)
        }
    }

    private var pressRotation: Double {
        guard self.effectivelyPressed, self.keyboardTheme.pressEffect == .snap else { return 0 }
        return -1.25
    }

    private var pressGlowColor: Color {
        switch self.keyboardTheme.material {
        case .gaming:
            self.baseColor.lighter(by: 0.3)
        case .neon:
            self.keyboardTheme.borderColor.color
        case .graphite, .aluminum, .monochrome, .classic, .glass, .minimal:
            self.baseColor
        }
    }

    private var pressGlowOpacity: Double {
        guard self.effectivelyPressed else { return 0 }
        return switch self.keyboardTheme.pressEffect {
        case .snap: 0.7
        case .glow: 0.95
        case .travel, .deepTravel, .compress, .scale: 0
        }
    }

    private var pressGlowRadius: CGFloat {
        switch self.keyboardTheme.pressEffect {
        case .snap: 9
        case .glow: 16
        case .travel, .deepTravel, .compress, .scale: 0
        }
    }

    private var pressAnimation: Animation {
        switch self.keyboardTheme.pressEffect {
        case .travel:
            .spring(response: 0.15, dampingFraction: 0.7)
        case .deepTravel:
            .spring(response: 0.24, dampingFraction: 0.62)
        case .compress:
            .spring(response: 0.14, dampingFraction: 0.82)
        case .scale:
            .easeOut(duration: 0.12)
        case .snap:
            .interpolatingSpring(stiffness: 520, damping: 30)
        case .glow:
            .spring(response: 0.2, dampingFraction: 0.58)
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

    /// Schedules showing pressed state.
    /// When overlay just appeared (delayPressAnimation=true), waits for fade-in to complete.
    /// When overlay was already visible, shows press immediately.
    private func scheduleShowPressed() {
        self.pressDelayTask?.cancel()
        guard self.isPressed else {
            self.showPressedState = false
            return
        }
        guard self.delayPressAnimation else {
            self.showPressedState = true
            return
        }
        self.showPressedState = false
        self.pressDelayTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self.showPressedState = true
        }
    }

    // MARK: - Flat Style (modern flat design)

    private var flatBody: some View {
        let flatShadowOffset: CGFloat = self.effectivelyPressed ? 1 : 2

        return ZStack {
            if self.keyboardTheme.material == .neon {
                self.neonDepthLayer
            }

            RoundedRectangle(cornerRadius: self.cornerRadius)
                .fill(self.flatShadowColor)
                .blur(radius: self.flatShadowRadius)
                .offset(y: flatShadowOffset)

            self.flatSurface

            self.flatHighlight

            if self.keyboardTheme.material == .neon {
                self.neonEdge
            } else if self.keyboardTheme.borderWidth > 0 {
                RoundedRectangle(cornerRadius: self.cornerRadius)
                    .strokeBorder(
                        self.keyboardTheme.borderColor.color,
                        lineWidth: CGFloat(self.keyboardTheme.borderWidth))
            }

            self.keyLabel
        }
        .frame(width: self.size.width, height: self.size.height)
        .offset(y: self.flatPressOffset)
    }

    private var flatShadowColor: Color {
        let opacity = switch self.keyboardTheme.material {
        case .monochrome: 0.16
        case .glass: 0.24
        case .neon: 0.36
        case .graphite, .aluminum, .classic, .minimal, .gaming: 0.3
        }
        return Color.black.opacity(opacity * self.style.shadowIntensity * self.pressedShadowMultiplier)
    }

    private var flatShadowRadius: CGFloat {
        if self.keyboardTheme.material == .monochrome {
            return self.effectivelyPressed ? 1 : 2
        }
        return self.effectivelyPressed ? 3 : 4
    }

    private var neonDepthColor: Color {
        self.keyboardTheme.colorScheme.shift.color
    }

    private var neonSecondaryColor: Color {
        self.neonDepthColor.lighter(by: 0.3)
    }

    private var neonDepthLayer: some View {
        RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.025, green: 0.03, blue: 0.07),
                        self.neonDepthColor.darker(by: 0.32),
                    ],
                    startPoint: .top,
                    endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                    .strokeBorder(self.neonSecondaryColor.opacity(0.86), lineWidth: 1.25)
            }
            .offset(y: self.effectivelyPressed ? 1.5 : 5)
            .shadow(
                color: self.neonSecondaryColor.opacity(self.effectivelyPressed ? 0.34 : 0.58),
                radius: self.effectivelyPressed ? 3 : 6,
                y: 2)
    }

    private var neonEdge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            self.keyboardTheme.borderColor.color,
                            self.neonSecondaryColor,
                            self.keyboardTheme.borderColor.color,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing),
                    lineWidth: max(2, CGFloat(self.keyboardTheme.borderWidth)))
                .shadow(
                    color: self.keyboardTheme.borderColor.color.opacity(0.9),
                    radius: self.effectivelyPressed ? 11 : 7)
                .shadow(
                    color: self.neonSecondaryColor.opacity(0.55),
                    radius: self.effectivelyPressed ? 18 : 11)

            RoundedRectangle(
                cornerRadius: max(2, self.cornerRadius - 3),
                style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            self.neonSecondaryColor.opacity(0.92),
                            self.keyboardTheme.borderColor.color.opacity(0.6),
                        ],
                        startPoint: .top,
                        endPoint: .bottom),
                    lineWidth: max(0.8, CGFloat(self.keyboardTheme.borderWidth) * 0.48))
                .padding(self.effectivelyPressed ? 2.5 : 4.5)
                .shadow(color: self.neonSecondaryColor.opacity(0.48), radius: 4)
        }
    }

    @ViewBuilder
    private var flatSurface: some View {
        switch self.keyboardTheme.material {
        case .glass:
            RoundedRectangle(cornerRadius: self.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            self.baseColor.lighter(by: 0.12).opacity(0.92),
                            self.baseColor.opacity(0.76),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
        case .neon:
            RoundedRectangle(cornerRadius: self.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            self.baseColor.lighter(by: 0.04),
                            self.baseColor.darker(by: 0.08),
                        ],
                        startPoint: .top,
                        endPoint: .bottom))
        case .monochrome:
            RoundedRectangle(cornerRadius: self.cornerRadius)
                .fill(self.baseColor.opacity(0.92))
        case .graphite, .aluminum, .classic, .minimal, .gaming:
            RoundedRectangle(cornerRadius: self.cornerRadius)
                .fill(self.baseColor)
        }
    }

    @ViewBuilder
    private var flatHighlight: some View {
        if self.keyboardTheme.material != .monochrome {
            RoundedRectangle(cornerRadius: self.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(self.keyboardTheme.material == .glass ? 0.24 : 0.15),
                            Color.white.opacity(0),
                        ],
                        startPoint: .top,
                        endPoint: .center))
        }
    }

    // MARK: - Minimal Style (text with background)

    private var minimalBody: some View {
        ZStack {
            // Simple pill background
            RoundedRectangle(cornerRadius: self.minimalCornerRadius)
                .fill(self.baseColor.opacity(self.effectivelyPressed ? 0.95 : 0.85))

            if self.keyboardTheme.borderWidth > 0 {
                RoundedRectangle(cornerRadius: self.minimalCornerRadius)
                    .strokeBorder(
                        self.keyboardTheme.borderColor.color,
                        lineWidth: CGFloat(self.keyboardTheme.borderWidth))
            }

            // Label
            self.minimalLabel
                .padding(.horizontal, 6)
        }
        .frame(width: self.minimalWidth, height: self.minimalHeight)
    }

    private var minimalCornerRadius: CGFloat {
        self.minimalHeight / 2 // Pill shape
    }

    private var minimalWidth: CGFloat {
        switch self.size {
        case .standard: 40
        case .modifier: 80 // Increased from 64 for better text fit
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
                    .font(self.keyFont(size: 13))
                if !info.label.isEmpty {
                    Text(info.label)
                        .font(self.keyFont(size: 10))
                }
            }
            .foregroundColor(self.textColor)
        } else {
            // Regular key
            Text(self.symbol.display)
                .font(self.keyFont(size: self.minimalFontSize))
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
            .fill(self.mechanicalShadowColor)
            .frame(width: self.size.width - 2, height: self.size.height)
            .blur(radius: self.mechanicalShadowRadius)
            .offset(y: self.depth + 4 - self.pressedDepthReduction)
    }

    /// The dark well/recess the key sits in.
    private var keyWell: some View {
        RoundedRectangle(cornerRadius: self.cornerRadius + 2)
            .fill(self.keyWellColor)
            .frame(width: self.size.width, height: self.size.height + self.depth)
            .overlay {
                if self.keyboardTheme.material == .gaming {
                    RoundedRectangle(cornerRadius: self.cornerRadius + 2)
                        .stroke(self.baseColor.lighter(by: 0.3).opacity(0.42), lineWidth: 1)
                }
            }
    }

    /// The 3D keycap with top surface and beveled sides.
    private var keycap: some View {
        ZStack {
            // Side/bevel (visible depth)
            self.keycapSides

            // Top surface
            self.keycapTop
        }
        .offset(y: -self.depth / 2 + self.pressOffset)
    }

    /// The visible sides of the keycap (creates 3D depth effect).
    private var keycapSides: some View {
        let effectiveDepth = max(0, self.depth - self.pressedDepthReduction)
        return ZStack {
            // Bottom edge (darkest)
            RoundedRectangle(cornerRadius: self.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: self.keycapSideColors,
                        startPoint: .top,
                        endPoint: .bottom))
                .frame(width: self.size.width - 2, height: self.size.height)
                .offset(y: effectiveDepth / 2)

            if self.keyboardTheme.material == .gaming {
                RoundedRectangle(cornerRadius: self.cornerRadius)
                    .strokeBorder(
                        self.gamingRimColor.opacity(self.effectivelyPressed ? 0.38 : 0.88),
                        lineWidth: 1.4)
                    .frame(width: self.size.width - 3, height: self.size.height - 1)
                    .offset(y: effectiveDepth / 2 + 1)
                    .shadow(
                        color: self.gamingRimColor.opacity(self.effectivelyPressed ? 0.2 : 0.58),
                        radius: self.effectivelyPressed ? 2 : 5,
                        y: 2)

                if self.category == .letter {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    self.gamingRimColor.opacity(0.92),
                                    KeyColor.pointerCyan.color.opacity(0.58),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing))
                        .frame(width: self.size.width - 14, height: 2)
                        .offset(y: effectiveDepth / 2 + self.size.height / 2 - 3)
                        .shadow(color: self.gamingRimColor.opacity(0.7), radius: 4)
                }
            }
        }
    }

    private var gamingRimColor: Color {
        self.category == .letter
            ? self.keyboardTheme.colorScheme.command.color
            : self.baseColor.lighter(by: 0.24)
    }

    /// The top pressable surface of the keycap.
    private var keycapTop: some View {
        ZStack {
            // Main surface with gradient for concave effect
            RoundedRectangle(cornerRadius: self.cornerRadius - 1)
                .fill(
                    LinearGradient(
                        colors: self.keycapTopColors,
                        startPoint: .top,
                        endPoint: .bottom))
                .frame(
                    width: self.size.width - self.topInset * 2,
                    height: self.size.height - self.topInset * 2)

            // Subtle inner border for depth
            RoundedRectangle(cornerRadius: self.cornerRadius - 1)
                .strokeBorder(
                    LinearGradient(
                        colors: self.keycapBorderColors,
                        startPoint: .top,
                        endPoint: .bottom),
                    lineWidth: self.keyboardTheme.material == .gaming ? 1.5 : 1)
                .frame(
                    width: self.size.width - self.topInset * 2,
                    height: self.size.height - self.topInset * 2)
                .shadow(
                    color: self.keyboardTheme.material == .gaming
                        ? self.baseColor.lighter(by: 0.25).opacity(0.45)
                        : .clear,
                    radius: self.keyboardTheme.material == .gaming ? 4 : 0)

            // Key label
            self.keyLabel
        }
        .offset(y: -self.depth / 2 + 1)
    }

    private var mechanicalShadowColor: Color {
        let opacity = switch self.keyboardTheme.material {
        case .aluminum: 0.26
        case .classic: 0.34
        case .gaming: 0.62
        case .graphite, .monochrome, .glass, .minimal, .neon: 0.4
        }
        return Color.black.opacity(opacity * self.style.shadowIntensity * self.pressedShadowMultiplier)
    }

    private var mechanicalShadowRadius: CGFloat {
        let baseRadius: CGFloat = self.keyboardTheme.material == .gaming ? 5 : 8
        return self.effectivelyPressed ? max(2, baseRadius - 2) : baseRadius
    }

    private var keyWellColor: Color {
        switch self.keyboardTheme.material {
        case .aluminum:
            Color(red: 0.52, green: 0.53, blue: 0.56)
        case .classic:
            Color(red: 0.20, green: 0.13, blue: 0.08)
        case .gaming:
            Color(red: 0.015, green: 0.02, blue: 0.03)
        case .graphite, .monochrome, .glass, .minimal, .neon:
            Color.black.opacity(0.85)
        }
    }

    private var keycapSideColors: [Color] {
        switch self.keyboardTheme.material {
        case .aluminum:
            [self.baseColor.darker(by: 0.12), self.baseColor.darker(by: 0.24)]
        case .classic:
            [self.baseColor.darker(by: 0.16), self.baseColor.darker(by: 0.34)]
        case .gaming:
            if self.category == .letter {
                [
                    Color(red: 0.10, green: 0.23, blue: 0.07),
                    Color(red: 0.025, green: 0.075, blue: 0.035),
                ]
            } else {
                [self.baseColor.lighter(by: 0.05), self.baseColor.darker(by: 0.3)]
            }
        case .graphite, .monochrome, .glass, .minimal, .neon:
            [self.baseColor.opacity(0.3), self.baseColor.opacity(0.15)]
        }
    }

    private var keycapTopColors: [Color] {
        switch self.keyboardTheme.material {
        case .aluminum:
            [
                self.baseColor.lighter(by: 0.16),
                self.baseColor,
                self.baseColor.darker(by: 0.08),
            ]
        case .classic:
            [
                self.baseColor.lighter(by: 0.14),
                self.baseColor,
                self.baseColor.darker(by: 0.13),
            ]
        case .gaming:
            [
                self.baseColor.lighter(by: 0.08),
                self.baseColor,
                self.baseColor.darker(by: 0.18),
            ]
        case .graphite, .monochrome, .glass, .minimal, .neon:
            [
                self.baseColor.lighter(by: 0.1),
                self.baseColor,
                self.baseColor.darker(by: 0.05),
            ]
        }
    }

    private var keycapBorderColors: [Color] {
        switch self.keyboardTheme.material {
        case .aluminum:
            [Color.white.opacity(0.72), Color.white.opacity(0.16), Color.black.opacity(0.18)]
        case .classic:
            [Color.white.opacity(0.32), Color.clear, Color.black.opacity(0.28)]
        case .gaming:
            [
                self.baseColor.lighter(by: 0.38).opacity(0.82),
                self.baseColor.opacity(0.25),
                Color.black.opacity(0.52),
            ]
        case .graphite:
            [Color.white.opacity(0.14), Color.white.opacity(0.035), Color.black.opacity(0.14)]
        case .monochrome, .glass, .minimal, .neon:
            [Color.white.opacity(0.25), Color.white.opacity(0.05), Color.black.opacity(0.1)]
        }
    }

    /// The label displayed on the keycap.
    @ViewBuilder
    private var keyLabel: some View {
        if self.symbol.isModifier, let info = ModifierInfo.from(symbolId: self.symbol.id) {
            // Modifier: icon + label stacked
            VStack(spacing: 2) {
                Text(info.icon)
                    .font(self.keyFont(size: 16))
                if !info.label.isEmpty {
                    Text(info.label)
                        .font(self.keyFont(size: 9))
                }
            }
            .foregroundColor(self.textColor)
        } else {
            // Regular key: single label
            Text(self.symbol.display)
                .font(self.keyFont(size: self.fontSize))
                .foregroundColor(self.textColor)
        }
    }

    // MARK: - Helpers

    private var systemIsDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func keyFont(size: CGFloat) -> Font {
        let scaledSize = size * CGFloat(self.keyboardTheme.fontScale)
        return ThemeFont.font(
            family: self.keyboardTheme.fontFamily,
            size: scaledSize,
            weight: self.keyboardTheme.fontWeight)
    }

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
