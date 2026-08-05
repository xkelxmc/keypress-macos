import CoreGraphics
import KeypressCore

enum SceneID: String {
    case hero
    case cursorHalo = "cursor-halo"
    case pet
    case themes
    case stackedHistory = "stacked-history"
    case placement
    case studio
    case studioAppearance = "customize"
    case languages
    case privacy
}

struct ScreenshotScene {
    let id: SceneID
    /// Kicker, headline and subline in the locale being rendered.
    let copy: SceneCopy
    let stage: StageTone
    /// Keyboard themes this scene needs a configuration for, one per themed tile.
    var keyboardThemes: [ThemeSelection] = [.dark]
    /// Hero carries the brand row (app icon + name) above the kicker.
    var showsBrand: Bool = false
    var contentRect: CGRect = ScreenshotCanvas.contentRect
}

/// Scene order and layout are the same in every locale; only the copy changes.
enum SceneCatalog {
    static func scenes(for locale: MarketingLocale) -> [ScreenshotScene] {
        let strings = MarketingStrings.table(for: locale)
        return [
            ScreenshotScene(
                id: .hero,
                copy: strings.hero,
                stage: .dark,
                showsBrand: true,
                contentRect: ScreenshotCanvas.heroContentRect),
            ScreenshotScene(
                id: .cursorHalo,
                copy: strings.cursorHalo,
                stage: .dark,
                keyboardThemes: []),
            ScreenshotScene(
                id: .pet,
                copy: strings.pet,
                stage: .dark),
            ScreenshotScene(
                id: .themes,
                copy: strings.themes,
                stage: .dark,
                keyboardThemes: [.dark, .classic, .modern, .gaming, .neon, .mono]),
            ScreenshotScene(
                id: .stackedHistory,
                copy: strings.stackedHistory,
                stage: .dark),
            ScreenshotScene(
                id: .placement,
                copy: strings.placement,
                stage: .dark),
            ScreenshotScene(
                id: .studio,
                copy: strings.studio,
                stage: .dark,
                keyboardThemes: [.light],
                contentRect: ScreenshotCanvas.tallContentRect),
            ScreenshotScene(
                id: .studioAppearance,
                copy: strings.studioAppearance,
                stage: .dark,
                keyboardThemes: [.light],
                contentRect: ScreenshotCanvas.tallContentRect),
            ScreenshotScene(
                id: .languages,
                copy: strings.languages,
                stage: .dark),
            ScreenshotScene(
                id: .privacy,
                copy: strings.privacy,
                stage: .dark),
        ]
    }
}

enum SceneKeys {
    static let command = KeySymbol(id: "command-left", display: "⌘", isModifier: true)
    static let shift = KeySymbol(id: "shift-left", display: "⇧", isModifier: true)

    static let chord = [Self.shift, Self.command, Self.letter("K")]

    static func letter(_ display: String) -> KeySymbol {
        KeySymbol(id: "key-\(display.lowercased())", display: display)
    }
}
