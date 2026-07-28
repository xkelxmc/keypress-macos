import KeypressCore
import SwiftUI

/// Simple view displaying pressed keys as styled keycaps.
struct KeyVisualizationView: View {
    var keyState: KeyState
    let config: KeypressConfig
    var appliesSizeScale = true

    var body: some View {
        KeyVisualizationContent(
            pressedKeys: self.keyState.pressedKeys,
            physicallyPressedKeys: self.keyState.physicallyPressedKeys,
            hasKeys: self.keyState.hasKeys,
            config: self.config,
            appliesSizeScale: self.appliesSizeScale)
    }
}

/// View for Single mode (SingleKeyState).
struct SingleKeyVisualizationView: View {
    var keyState: SingleKeyState
    let config: KeypressConfig
    var appliesSizeScale = true

    var body: some View {
        KeyVisualizationContent(
            pressedKeys: self.keyState.pressedKeys,
            physicallyPressedKeys: self.keyState.physicallyPressedKeys,
            hasKeys: self.keyState.hasKeys,
            config: self.config,
            appliesSizeScale: self.appliesSizeScale)
    }
}

/// Shared visualization content (used by both modes).
private struct KeyVisualizationContent: View {
    let pressedKeys: [PressedKey]
    let physicallyPressedKeys: Set<String>
    let hasKeys: Bool
    let config: KeypressConfig
    let appliesSizeScale: Bool

    /// Tracks if overlay just appeared (was hidden, now visible).
    /// Used to delay press animation until fade-in completes.
    @State private var overlayJustAppeared: Bool = true
    /// Task for delayed clearing of overlayJustAppeared flag.
    @State private var appearDelayTask: Task<Void, Never>?

    private var keyboardTheme: KeyboardTheme {
        self.config.effectiveTheme(isSystemDark: self.systemIsDark).keyboard
    }

    var body: some View {
        let keysView = HStack(spacing: CGFloat(self.keyboardTheme.keySpacing)) {
            ForEach(self.pressedKeys) { key in
                KeyCapView(
                    symbol: key.symbol,
                    config: self.config,
                    isPressed: self.isKeyPressed(key),
                    delayPressAnimation: self.overlayJustAppeared)
            }
        }

        KeyboardThemeContainer(config: self.config) {
            keysView
        }
        .scaleEffect(self.appliesSizeScale ? self.config.size.scaleFactor : 1)
        .opacity(self.hasKeys ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: self.hasKeys)
        .onChange(of: self.hasKeys) { wasVisible, isVisible in
            if !wasVisible, isVisible {
                // Overlay just appeared — delay press animation
                self.overlayJustAppeared = true
                // Cancel any pending task
                self.appearDelayTask?.cancel()
                // After fade-in completes, clear the flag
                self.appearDelayTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    self.overlayJustAppeared = false
                }
            } else if !isVisible {
                // Overlay hidden — reset for next appearance
                self.appearDelayTask?.cancel()
                self.overlayJustAppeared = true
            }
        }
        .onDisappear {
            self.appearDelayTask?.cancel()
        }
    }

    /// Determines if a key should show pressed animation based on settings.
    private func isKeyPressed(_ key: PressedKey) -> Bool {
        let isPhysicallyPressed = self.physicallyPressedKeys.contains(key.symbol.id)

        if key.symbol.isModifier {
            return isPhysicallyPressed && self.config.pressAnimationModifiers
        } else {
            return isPhysicallyPressed && self.config.pressAnimationRegularKeys
        }
    }

    private var systemIsDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

// MARK: - KeyboardThemeContainer

struct KeyboardThemeContainer<Content: View>: View {
    let config: KeypressConfig
    let disableOuterShadow: Bool
    @ViewBuilder let content: () -> Content

    init(
        config: KeypressConfig,
        disableOuterShadow: Bool = false,
        @ViewBuilder content: @escaping () -> Content)
    {
        self.config = config
        self.disableOuterShadow = disableOuterShadow
        self.content = content
    }

    private var theme: KeyboardTheme {
        self.config.effectiveTheme(isSystemDark: self.systemIsDark).keyboard
    }

    var body: some View {
        switch self.theme.frameStyle {
        case .frame:
            KeyboardFrameView(config: self.config, disableOuterShadow: self.disableOuterShadow) {
                self.content()
            }
        case .overlay:
            self.content()
                .padding(.horizontal, self.horizontalPadding)
                .padding(.vertical, self.verticalPadding)
                .background {
                    KeyboardOverlaySurface(
                        theme: self.theme,
                        disableOuterShadow: self.disableOuterShadow)
                }
        case .none:
            self.content()
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
        }
    }

    private var horizontalPadding: CGFloat {
        switch self.theme.material {
        case .neon: 16
        case .glass: 15
        case .graphite, .aluminum, .monochrome, .classic, .minimal, .gaming: 14
        }
    }

    private var verticalPadding: CGFloat {
        switch self.theme.material {
        case .neon: 13
        case .glass: 12
        case .graphite, .aluminum, .monochrome, .classic, .minimal, .gaming: 12
        }
    }

    private var systemIsDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private struct KeyboardOverlaySurface: View {
    let theme: KeyboardTheme
    let disableOuterShadow: Bool

    var body: some View {
        ZStack {
            if self.theme.material == .neon {
                RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.02, green: 0.025, blue: 0.06),
                                self.neonSecondaryColor.darker(by: 0.34),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing))
                    .overlay {
                        RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                            .strokeBorder(self.neonSecondaryColor.opacity(0.7), lineWidth: 1.2)
                    }
                    .offset(y: 5)
                    .shadow(color: self.neonSecondaryColor.opacity(0.42), radius: 10, y: 4)
            }

            RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                .fill(self.background)
                .overlay {
                    RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                        .strokeBorder(self.border, lineWidth: self.borderWidth)
                }
                .overlay {
                    if self.theme.material == .neon {
                        RoundedRectangle(
                            cornerRadius: max(3, self.cornerRadius - 4),
                            style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        self.neonSecondaryColor.opacity(0.76),
                                        self.theme.borderColor.color.opacity(0.42),
                                    ],
                                    startPoint: .topTrailing,
                                    endPoint: .bottomLeading),
                                lineWidth: 0.9)
                            .padding(5)
                    }
                }
                .shadow(
                    color: self.disableOuterShadow ? .clear : self.shadowColor,
                    radius: self.disableOuterShadow ? 0 : self.shadowRadius,
                    y: self.disableOuterShadow ? 0 : 8)
        }
    }

    private var cornerRadius: CGFloat {
        switch self.theme.material {
        case .neon: 11
        case .glass: 16
        case .gaming: 7
        case .graphite, .aluminum, .monochrome, .classic, .minimal: 14
        }
    }

    private var background: LinearGradient {
        let colors: [Color] = switch self.theme.material {
        case .glass:
            [
                Color(red: 0.10, green: 0.14, blue: 0.21).opacity(0.82),
                Color(red: 0.035, green: 0.05, blue: 0.09).opacity(0.9),
            ]
        case .neon:
            [
                Color(red: 0.025, green: 0.035, blue: 0.07).opacity(0.96),
                Color(red: 0.07, green: 0.025, blue: 0.09).opacity(0.94),
            ]
        case .monochrome:
            [Color.black.opacity(0.66), Color.black.opacity(0.76)]
        case .classic:
            [
                Color(red: 0.25, green: 0.16, blue: 0.09).opacity(0.9),
                Color(red: 0.12, green: 0.07, blue: 0.04).opacity(0.94),
            ]
        case .gaming:
            [
                Color(red: 0.035, green: 0.045, blue: 0.06).opacity(0.96),
                Color(red: 0.01, green: 0.015, blue: 0.025).opacity(0.98),
            ]
        case .graphite, .aluminum, .minimal:
            [Color.black.opacity(0.7), Color.black.opacity(0.72)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var border: LinearGradient {
        let colors: [Color] = switch self.theme.material {
        case .glass:
            [Color.white.opacity(0.28), Color.white.opacity(0.04)]
        case .neon:
            [self.theme.borderColor.color.opacity(0.9), KeyColor.pointerPurple.color.opacity(0.72)]
        case .gaming:
            [KeyColor(red: 0.48, green: 1, blue: 0.18).color.opacity(0.55), Color.clear]
        case .graphite, .aluminum, .monochrome, .classic, .minimal:
            [Color.white.opacity(0.12), Color.clear]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var borderWidth: CGFloat {
        switch self.theme.material {
        case .neon: 2
        case .glass, .gaming: 1
        case .graphite, .aluminum, .monochrome, .classic, .minimal: 0.75
        }
    }

    private var shadowColor: Color {
        switch self.theme.material {
        case .neon:
            self.theme.borderColor.color.opacity(0.42)
        case .gaming:
            KeyColor(red: 0.48, green: 1, blue: 0.18).color.opacity(0.24)
        case .graphite, .aluminum, .monochrome, .classic, .glass, .minimal:
            Color.black.opacity(0.4)
        }
    }

    private var shadowRadius: CGFloat {
        switch self.theme.material {
        case .neon: 22
        case .gaming: 14
        case .graphite, .aluminum, .monochrome, .classic, .glass, .minimal: 16
        }
    }

    private var neonSecondaryColor: Color {
        self.theme.colorScheme.shift.color.lighter(by: 0.28)
    }
}

// MARK: - KeyboardFrameView

/// 3D keyboard frame container that wraps keycaps.
/// Creates a realistic "keyboard fragment" appearance with depth and materials.
struct KeyboardFrameView<Content: View>: View {
    let config: KeypressConfig
    let disableOuterShadow: Bool
    @ViewBuilder let content: () -> Content

    init(config: KeypressConfig, disableOuterShadow: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.config = config
        self.disableOuterShadow = disableOuterShadow
        self.content = content
    }

    private var theme: KeyboardTheme {
        self.config.effectiveTheme(isSystemDark: self.systemIsDark()).keyboard
    }

    private var outerCornerRadius: CGFloat {
        switch self.theme.material {
        case .classic: 13
        case .gaming: 7
        case .aluminum: 18
        case .graphite, .monochrome, .glass, .minimal, .neon: 16
        }
    }

    private var innerCornerRadius: CGFloat {
        switch self.theme.material {
        case .classic: 9
        case .gaming: 4
        case .aluminum: 13
        case .graphite, .monochrome, .glass, .minimal, .neon: 12
        }
    }

    private var frameThickness: CGFloat {
        switch self.theme.material {
        case .classic: 12
        case .gaming: 8
        case .aluminum: 9
        case .graphite, .monochrome, .glass, .minimal, .neon: 10
        }
    }

    // MARK: - Colors

    /// Whether we're in a light color scheme.
    private var isLightMode: Bool {
        let letterColor = self.theme.colorScheme.letter
        let luminance = 0.2126 * letterColor.red
            + 0.7152 * letterColor.green
            + 0.0722 * letterColor.blue
        return luminance > 0.55
    }

    private func systemIsDark() -> Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Frame base color — dark aluminum or light aluminum.
    private var frameColor: Color {
        switch self.theme.material {
        case .aluminum:
            Color(red: 0.82, green: 0.83, blue: 0.86)
        case .classic:
            Color(red: 0.34, green: 0.22, blue: 0.12)
        case .gaming:
            Color(red: 0.025, green: 0.032, blue: 0.045)
        case .graphite, .monochrome, .glass, .minimal, .neon:
            if self.isLightMode {
                Color(red: 0.85, green: 0.85, blue: 0.87)
            } else {
                Color(red: 0.12, green: 0.12, blue: 0.14)
            }
        }
    }

    /// Inner well color — where keys sit.
    private var wellColor: Color {
        switch self.theme.material {
        case .aluminum:
            Color(red: 0.66, green: 0.67, blue: 0.70)
        case .classic:
            Color(red: 0.15, green: 0.09, blue: 0.05)
        case .gaming:
            Color(red: 0.008, green: 0.012, blue: 0.02)
        case .graphite, .monochrome, .glass, .minimal, .neon:
            if self.isLightMode {
                Color(red: 0.75, green: 0.75, blue: 0.78)
            } else {
                Color(red: 0.06, green: 0.06, blue: 0.08)
            }
        }
    }

    /// Highlight for top edge.
    private var highlightColor: Color {
        switch self.theme.material {
        case .aluminum:
            Color.white.opacity(0.9)
        case .classic:
            Color(red: 1, green: 0.78, blue: 0.48).opacity(0.25)
        case .gaming:
            KeyColor(red: 0.48, green: 1, blue: 0.18).color.opacity(0.38)
        case .graphite, .monochrome, .glass, .minimal, .neon:
            if self.isLightMode {
                Color.white.opacity(0.8)
            } else {
                Color.white.opacity(0.15)
            }
        }
    }

    /// Shadow color for inner well.
    private var innerShadowColor: Color {
        switch self.theme.material {
        case .aluminum:
            Color.black.opacity(0.22)
        case .classic:
            Color.black.opacity(0.54)
        case .gaming:
            Color.black.opacity(0.82)
        case .graphite, .monochrome, .glass, .minimal, .neon:
            if self.isLightMode {
                Color.black.opacity(0.15)
            } else {
                Color.black.opacity(0.6)
            }
        }
    }

    // MARK: - Body

    var body: some View {
        self.content()
            .padding(.horizontal, self.frameThickness + 4)
            .padding(.vertical, self.frameThickness + 2)
            .background(
                ZStack {
                    // Outer drop shadow (can be disabled for screenshots)
                    if !self.disableOuterShadow {
                        RoundedRectangle(cornerRadius: self.outerCornerRadius)
                            .fill(self.outerShadowColor)
                            .blur(radius: self.outerShadowRadius)
                            .offset(y: self.theme.material == .gaming ? 5 : 8)
                    }

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
            .overlay {
                if self.theme.material == .gaming {
                    RoundedRectangle(cornerRadius: self.outerCornerRadius)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    KeyColor(red: 0.48, green: 1, blue: 0.18).color.opacity(0.72),
                                    KeyColor.pointerCyan.color.opacity(0.32),
                                    Color.clear,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing),
                            lineWidth: 1.5)
                }
            }
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
                        lineWidth: self.theme.material == .gaming ? 2 : 1.5)
                    .frame(width: wellWidth, height: wellHeight)
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private var outerShadowColor: Color {
        switch self.theme.material {
        case .gaming:
            KeyColor(red: 0.48, green: 1, blue: 0.18).color.opacity(0.24)
        case .classic:
            Color(red: 0.12, green: 0.06, blue: 0.02).opacity(0.58)
        case .graphite, .aluminum, .monochrome, .glass, .minimal, .neon:
            Color.black.opacity(0.5)
        }
    }

    private var outerShadowRadius: CGFloat {
        self.theme.material == .gaming ? 13 : 20
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

// MARK: - Previews

#Preview("Key Visualization") {
    @Previewable @State var keyState = KeyState()

    KeyVisualizationView(keyState: keyState, config: .shared)
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
