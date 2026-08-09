import AppKit
import KeypressCore
import SwiftUI

struct SceneContentView: View {
    let scene: ScreenshotScene
    let strings: MarketingStrings
    let configs: SceneConfigs
    let assets: SceneAssets

    var body: some View {
        switch self.scene.id {
        case .hero:
            HeroSceneView(configs: self.configs)
        case .cursorHalo:
            CursorHaloSceneView(labels: self.strings.haloVariants)
        case .pet:
            PetSceneView(configs: self.configs, chips: self.strings.petChips)
        case .themes:
            ThemesSceneView(configs: self.configs, footnote: self.strings.themesFootnote)
        case .stackedHistory:
            StackedHistorySceneView(configs: self.configs)
        case .placement:
            PlacementSceneView(configs: self.configs, strings: self.strings)
        case .studio, .studioAppearance:
            StudioSceneView(windowImage: self.assets.settingsWindow)
        case .languages:
            LanguagesSceneView(configs: self.configs)
        case .privacy:
            PrivacySceneView(strings: self.strings)
        }
    }
}

// MARK: - Shared building blocks

/// A themed keycap row inside the shipping keyboard container.
struct SceneKeyboardRow: View {
    let keys: [KeySymbol]
    let config: KeypressConfig
    var isPressed: Bool = false

    private var theme: KeyboardTheme {
        self.config.effectiveTheme(isSystemDark: true).keyboard
    }

    var body: some View {
        KeyboardThemeContainer(config: self.config) {
            HStack(spacing: CGFloat(self.theme.keySpacing)) {
                ForEach(Array(self.keys.enumerated()), id: \.offset) { _, symbol in
                    KeyCapView(
                        symbol: symbol,
                        config: self.config,
                        isPressed: self.isPressed)
                }
            }
        }
    }
}

/// One frame of the shipping pet atlas, sized by its drawn content width.
struct PetSpriteImage: View {
    let state: PetRuntimeState
    let frameIndex: Int
    let contentWidth: CGFloat

    var body: some View {
        let canvas = PetSpriteMetrics.canvasSize(contentWidth: self.contentWidth)
        return Group {
            if let image = PetSpriteSheet.shared.image(for: self.state, frameIndex: self.frameIndex) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else {
                Color.clear
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}

/// The macOS arrow cursor the halo is drawn around. `alignsTipToCentre` puts the
/// hotspot on the container centre the way the running app does; otherwise the
/// glyph itself is centred, which reads better when the halo is the only subject.
struct PointerCursorImage: View {
    let height: CGFloat
    var alignsTipToCentre: Bool = true

    var body: some View {
        let cursor = NSCursor.arrow.image
        let width = self.height * cursor.size.width / cursor.size.height
        return Image(nsImage: cursor)
            .resizable()
            .interpolation(.high)
            .frame(width: width, height: self.height)
            .shadow(color: Color.black.opacity(0.45), radius: 6, y: 3)
            .offset(
                x: self.alignsTipToCentre ? width / 2 : 0,
                y: self.alignsTipToCentre ? self.height / 2 : 0)
    }
}

/// A staged macOS app window the overlay pieces sit on — gives every scene a
/// real desktop context without capturing anyone's actual screen.
struct SceneWindow<Content: View>: View {
    let title: String
    let size: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack(spacing: 8) {
                    Circle().fill(Color.stageHex(0xFF5F57)).frame(width: 12, height: 12)
                    Circle().fill(Color.stageHex(0xFEBC2E)).frame(width: 12, height: 12)
                    Circle().fill(Color.stageHex(0x28C840)).frame(width: 12, height: 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 18)

                Text(self.title)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .frame(height: 40)
            .background(Color.white.opacity(0.045))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1)
            }

            self.content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: self.size.width, height: self.size.height)
        .background {
            LinearGradient(
                colors: [Color.stageHex(0x16161D), Color.stageHex(0x0E0E14)],
                startPoint: .top,
                endPoint: .bottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.55), radius: 44, y: 26)
        .shadow(color: Color.black.opacity(0.25), radius: 8, y: 4)
    }
}

/// Syntax-colored mock code, laid out like an editor buffer.
private struct SceneCodeText: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            self.line((Self.comment, "// toggle the overlay mid-call"))
            self.line(
                (Self.keyword, "func "),
                (Self.function, "toggleOverlay"),
                (Self.plain, "() {"))
            self.line(
                (Self.plain, "    isVisible."),
                (Self.function, "toggle"),
                (Self.plain, "()"))
            self.line(
                (Self.plain, "    "),
                (Self.keyword, "withAnimation"),
                (Self.plain, "(.spring) { halo."),
                (Self.function, "pulse"),
                (Self.plain, "() }"))
            self.line((Self.plain, "}"))
        }
        .font(.system(size: 16, weight: .regular, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }

    private static let comment = Color.white.opacity(0.32)
    private static let keyword = Color.stageHex(0xFF7AB2)
    private static let function = Color.stageHex(0x6BDFFF)
    private static let plain = Color.white.opacity(0.85)

    private func line(_ runs: (Color, String)...) -> Text {
        runs.map { color, string in
            Text(verbatim: string).foregroundStyle(color)
        }
        .reduce(Text(verbatim: ""), +)
    }
}

/// Dotted canvas-app background for the halo window.
struct SceneDotGridView: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 26
            var y: CGFloat = step / 2
            while y < size.height {
                var x: CGFloat = step / 2
                while x < size.width {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)),
                        with: .color(Color.white.opacity(0.07)))
                    x += step
                }
                y += step
            }
        }
    }
}

private struct DashedGuide: Shape {
    let isHorizontal: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if self.isHorizontal {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        } else {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        return path
    }
}

// MARK: - 01 hero

private struct HeroSceneView: View {
    let configs: SceneConfigs

    private static let halo = PointerTheme(
        shape: .squircle,
        lineStyle: .aura,
        decoration: .none,
        primaryColor: .pointerCyan,
        strokeWidth: 6,
        glowRadius: 28,
        glowIntensity: 0.9)

    var body: some View {
        ZStack {
            SceneWindow(title: "demo.swift — Xcode", size: CGSize(width: 940, height: 400)) {
                SceneCodeText()
            }
            .offset(y: 20)

            ZStack {
                PointerThemeArtwork(theme: Self.halo, size: 230, reaction: .primary)
                PointerCursorImage(height: 68, alignsTipToCentre: false)
            }
            .offset(x: 300, y: 30)

            ScaledView(scale: 1.35) {
                SceneKeyboardRow(
                    keys: SceneKeys.chord,
                    config: self.configs[.dark],
                    isPressed: true)
            }
            .offset(y: 190)

            PetSpriteImage(state: .typing, frameIndex: 3, contentWidth: 104)
                .offset(x: -290, y: -228)
        }
    }
}

// MARK: - 02 cursor-halo

private struct CursorHaloSceneView: View {
    /// One caption per variant tile, in the order the themes are declared.
    let labels: [String]

    private static let primary = PointerTheme(
        shape: .squircle,
        lineStyle: .aura,
        decoration: .innerRing,
        primaryColor: .pointerCyan,
        strokeWidth: 6,
        glowRadius: 28,
        glowIntensity: 0.95)

    private static let deepCyan = KeyColor(red: 0.04, green: 0.35, blue: 0.52)

    private static let variants: [PointerTheme] = [
        PointerTheme(
            shape: .circle,
            lineStyle: .aura,
            decoration: .centerDot,
            primaryColor: .pointerCyan,
            secondaryColor: Self.deepCyan,
            strokeWidth: 4,
            glowRadius: 20),
        ThemeDefinition.neon.pointer,
        PointerTheme(
            shape: .square,
            lineStyle: .solid,
            decoration: .none,
            primaryColor: .pointerCyan,
            secondaryColor: Self.deepCyan,
            strokeWidth: 4,
            glowRadius: 18,
            glowIntensity: 0.7),
        PointerTheme(
            shape: .diamond,
            lineStyle: .segmented,
            decoration: .cornerBrackets,
            primaryColor: .pointerCyan,
            secondaryColor: Self.deepCyan,
            strokeWidth: 3,
            glowRadius: 16,
            glowIntensity: 0.75),
    ]

    var body: some View {
        ZStack {
            SceneWindow(title: "board — whiteboard", size: CGSize(width: 900, height: 296)) {
                ZStack {
                    SceneDotGridView()

                    ZStack {
                        PointerThemeArtwork(theme: Self.primary, size: 190, reaction: .drag)
                        PointerCursorImage(height: 58)
                    }
                }
            }
            .offset(y: -86)

            HStack(spacing: 24) {
                ForEach(Array(Self.variants.enumerated()), id: \.offset) { index, variant in
                    VStack(spacing: 12) {
                        PointerThemeArtwork(
                            theme: variant,
                            size: 82,
                            reaction: .movement)
                            .frame(height: 92)

                        SceneCaption(text: self.labels[index])
                    }
                    .frame(width: 262, height: 150)
                    .background { SceneTileBackground() }
                }
            }
            .offset(y: 178)
        }
        .foregroundStyle(StagePalette.darkForeground)
    }
}

// MARK: - 03 pet

private struct PetSceneView: View {
    let configs: SceneConfigs
    let chips: [String]

    var body: some View {
        VStack(spacing: 34) {
            ZStack {
                ScaledView(scale: 1.9) {
                    SceneKeyboardRow(
                        keys: ["H", "E", "L", "L", "O"].map(SceneKeys.letter),
                        config: self.configs[.dark])
                }

                PetSpriteImage(state: .typing, frameIndex: 2, contentWidth: 168)
                    .offset(y: -138)
            }
            .frame(height: 300)

            HStack(spacing: 16) {
                ForEach(self.chips, id: \.self) { chip in
                    SceneChip(text: chip)
                }
            }
        }
    }
}

// MARK: - 04 themes

private struct ThemesSceneView: View {
    let configs: SceneConfigs
    let footnote: String

    private static let rows: [[(label: String, theme: ThemeSelection)]] = [
        [("dark", .dark), ("classic", .classic), ("modern", .modern)],
        [("gaming", .gaming), ("neon", .neon), ("mono", .mono)],
    ]

    var body: some View {
        VStack(spacing: 26) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 24) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, tile in
                        VStack(spacing: 18) {
                            ScaledView(scale: 1.05) {
                                SceneKeyboardRow(
                                    keys: SceneKeys.chord,
                                    config: self.configs[tile.theme])
                            }
                            .frame(height: 104)

                            SceneCaption(text: tile.label)
                        }
                        .frame(width: 396, height: 182)
                        .background { SceneTileBackground() }
                    }
                }
            }

            SceneCaption(text: self.footnote, opacity: 0.4)
                .padding(.top, 2)
        }
        .foregroundStyle(StagePalette.darkForeground)
    }
}

// MARK: - 05 stacked-history

private struct StackedHistorySceneView: View {
    let configs: SceneConfigs

    private var theme: KeyboardTheme {
        self.configs[.dark].effectiveTheme(isSystemDark: true).keyboard
    }

    var body: some View {
        SceneWindow(title: "zsh — keypress", size: CGSize(width: 900, height: 470)) {
            ZStack(alignment: .topLeading) {
                SceneTerminalText()

                VStack(alignment: .leading, spacing: 10) {
                    TypedTextRow(text: "git commit -m \"ship 2.0\"", theme: self.theme)
                        .opacity(0.42)
                    TypedTextRow(text: "every keystroke, on screen", theme: self.theme)
                        .opacity(0.72)

                    SceneKeyboardRow(
                        keys: SceneKeys.chord,
                        config: self.configs[.dark],
                        isPressed: true)
                        .padding(.top, 4)
                }
                .scaleEffect(1.12, anchor: .bottomLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(26)
            }
        }
    }
}

private struct SceneTerminalText: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            self.line((Self.prompt, "~/keypress "), (Self.plain, "git status"))
            self.line((Self.dim, "On branch "), (Self.cyan, "main"))
            self.line((Self.prompt, "~/keypress "), (Self.plain, "swift build"))
            self.line((Self.dim, "Compiling Keypress…"))
            self.line((Self.green, "Build complete!"), (Self.dim, " (3.4s)"))
        }
        .font(.system(size: 15.5, weight: .regular, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
    }

    private static let prompt = Color.white.opacity(0.5)
    private static let plain = Color.white.opacity(0.85)
    private static let dim = Color.white.opacity(0.38)
    private static let cyan = StagePalette.accent.opacity(0.85)
    private static let green = Color.stageHex(0x7EE787)

    private func line(_ runs: (Color, String)...) -> Text {
        runs.map { color, string in
            Text(verbatim: string).foregroundStyle(color)
        }
        .reduce(Text(verbatim: ""), +)
    }
}

// MARK: - 06 placement

private struct PlacementSceneView: View {
    let configs: SceneConfigs
    let strings: MarketingStrings

    var body: some View {
        VStack(spacing: 30) {
            HStack(spacing: 40) {
                DisplayPlate(
                    caption: self.strings.placementCaptions[0],
                    isDragging: true,
                    config: self.configs[.dark])

                DisplayPlate(
                    caption: self.strings.placementCaptions[1],
                    isDragging: false,
                    config: self.configs[.dark])
            }

            HStack(spacing: 16) {
                ForEach(self.strings.placementChips, id: \.self) { chip in
                    SceneChip(text: chip)
                }
            }
        }
        .foregroundStyle(StagePalette.darkForeground)
    }
}

private struct DisplayPlate: View {
    private static let plateSize = CGSize(width: 520, height: 300)

    let caption: String
    let isDragging: Bool
    let config: KeypressConfig

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.stageHex(0x14141F),
                                Color.stageHex(0x0B0B12),
                            ],
                            startPoint: .top,
                            endPoint: .bottom))
                    .overlay {
                        RadialGradient(
                            colors: [
                                StagePalette.darkGlowIndigo.opacity(0.5),
                                .clear,
                            ],
                            center: UnitPoint(x: 0.35, y: 0.3),
                            startRadius: 0,
                            endRadius: 340)
                    }
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 16)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if self.isDragging {
                    self.miniKeyboard
                        .opacity(0.3)
                        .offset(x: -128, y: 88)

                    DashedGuide(isHorizontal: true)
                        .stroke(
                            StagePalette.accent.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 7]))
                        .frame(width: Self.plateSize.width, height: 1)
                        .offset(y: -18)

                    DashedGuide(isHorizontal: false)
                        .stroke(
                            StagePalette.accent.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1.5, dash: [7, 7]))
                        .frame(width: 1, height: Self.plateSize.height)
                        .offset(x: 84)

                    self.miniKeyboard
                        .offset(x: 84, y: -18)
                        .shadow(color: StagePalette.accent.opacity(0.28), radius: 11)
                } else {
                    self.miniKeyboard
                        .offset(x: 128, y: -74)
                }
            }
            .frame(width: Self.plateSize.width, height: Self.plateSize.height)

            SceneCaption(text: self.caption, opacity: 0.45)
        }
    }

    private var miniKeyboard: some View {
        ScaledView(scale: 0.74) {
            SceneKeyboardRow(keys: SceneKeys.chord, config: self.config)
        }
    }
}

// MARK: - 07 studio

enum StudioSceneMetrics {
    static let scale: CGFloat = 0.84

    /// Shorter than the shipping window so the scroll edge falls in the gap above a
    /// section header instead of slicing a control in half; tuned per pane.
    static func windowSize(for id: SceneID) -> CGSize {
        CGSize(width: 980, height: id == .studioAppearance ? 552 : 590)
    }
}

private struct StudioSceneView: View {
    let windowImage: NSImage?

    var body: some View {
        Group {
            if let windowImage = self.windowImage {
                Image(nsImage: windowImage)
                    .resizable()
                    .interpolation(.high)
            } else {
                Color.clear
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: 980 * StudioSceneMetrics.scale)
        .shadow(color: Color.black.opacity(0.6), radius: 52, y: 30)
        .shadow(color: Color.black.opacity(0.24), radius: 9, y: 4)
    }
}

// MARK: - 08 languages

private struct LanguagesSceneView: View {
    let configs: SceneConfigs

    private static let locales = ["EN", "DE", "ES", "FR", "RU"]

    var body: some View {
        VStack(spacing: 26) {
            ScaledView(scale: 1.5) {
                SceneKeyboardRow(
                    keys: ["B", "O", "N", "J", "O", "U", "R"].map(SceneKeys.letter),
                    config: self.configs[.dark])
            }

            HStack(spacing: 36) {
                ScaledView(scale: 1.5) {
                    SceneKeyboardRow(
                        keys: [SceneKeys.command, SceneKeys.letter("Ü")],
                        config: self.configs[.dark],
                        isPressed: true)
                }

                ScaledView(scale: 1.5) {
                    SceneKeyboardRow(
                        keys: [SceneKeys.letter("ñ")],
                        config: self.configs[.dark])
                }

                ScaledView(scale: 1.5) {
                    SceneKeyboardRow(
                        keys: [SceneKeys.letter("Я")],
                        config: self.configs[.dark])
                }
            }

            HStack(spacing: 14) {
                ForEach(Self.locales, id: \.self) { locale in
                    SceneChip(text: locale, isAccented: locale == "EN")
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - 09 privacy

private struct PrivacySceneView: View {
    let strings: MarketingStrings

    var body: some View {
        VStack(spacing: 42) {
            SceneWindow(title: self.strings.privacyWindowTitle, size: CGSize(width: 640, height: 264)) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(self.strings.privacyFieldLabel)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))

                    Text(verbatim: "• • • • • • • • • •")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .frame(width: 480, height: 48, alignment: .leading)
                        .padding(.horizontal, 18)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
                                }
                        }

                    HStack(spacing: 9) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .semibold))

                        Text(self.strings.privacyBadge)
                            .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                            .tracking(1.4)
                    }
                    .foregroundStyle(StagePalette.accent.opacity(0.9))
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.vertical, 24)
            }

            HStack(spacing: 18) {
                ForEach(self.strings.privacyPills, id: \.self) { pill in
                    SceneChip(text: pill, isAccented: true)
                }
            }
        }
    }
}
