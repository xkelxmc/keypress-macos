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
    let kicker: String
    /// Display headline; the single `*word*` between asterisks renders as the accent.
    let headline: String
    /// One plain-language sentence under the headline explaining the benefit.
    let subline: String
    let stage: StageTone
    /// Keyboard themes this scene needs a configuration for, one per themed tile.
    var keyboardThemes: [ThemeSelection] = [.dark]
    /// Hero carries the brand row (app icon + name) above the kicker.
    var showsBrand: Bool = false
    var contentRect: CGRect = ScreenshotCanvas.contentRect
}

enum SceneCatalog {
    static let scenes: [ScreenshotScene] = [
        ScreenshotScene(
            id: .hero,
            kicker: "Live input overlay for macOS",
            headline: "Every *keystroke*, on screen.",
            subline: "Real mechanical keycaps, a glowing cursor halo and a typing cat — "
                + "built for screen shares, streams and tutorials.",
            stage: .dark,
            showsBrand: true,
            contentRect: ScreenshotCanvas.heroContentRect),
        ScreenshotScene(
            id: .cursorHalo,
            kicker: "Cursor halo",
            headline: "Never lose the *pointer* again.",
            subline: "Shapes, glow and distinct reactions to clicks, drags and scrolls. "
                + "Your viewers always know where the action is.",
            stage: .dark,
            keyboardThemes: []),
        ScreenshotScene(
            id: .pet,
            kicker: "Keypress pet",
            headline: "A *cat* that types with you.",
            subline: "It types at your speed, watches the cursor and naps when you rest. "
                + "Every habit has its own switch.",
            stage: .dark),
        ScreenshotScene(
            id: .themes,
            kicker: "Themes",
            headline: "Nine looks. Or build your *own*.",
            subline: "Nine built-in families for keyboard and pointer — "
                + "or design your own, down to per-key colors.",
            stage: .dark,
            keyboardThemes: [.dark, .classic, .modern, .gaming, .neon, .mono]),
        ScreenshotScene(
            id: .stackedHistory,
            kicker: "Stacked history",
            headline: "Typing your viewers can *read*.",
            subline: "Continuous typing folds into readable lines "
                + "while the active shortcut stays anchored.",
            stage: .dark),
        ScreenshotScene(
            id: .placement,
            kicker: "Displays & position",
            headline: "Exactly where it *belongs*.",
            subline: "Drag the real overlay on any display — "
                + "with snapping, guides and a saved spot per screen.",
            stage: .dark),
        ScreenshotScene(
            id: .studio,
            kicker: "Native settings",
            headline: "A *studio*, not a settings sheet.",
            subline: "Live previews, theme galleries and per-behavior controls "
                + "in a native sidebar interface.",
            stage: .dark,
            keyboardThemes: [.light],
            contentRect: ScreenshotCanvas.tallContentRect),
        ScreenshotScene(
            id: .studioAppearance,
            kicker: "Keyboard appearance",
            headline: "Tune every *key*.",
            subline: "Materials, press effects, fonts and per-category colors — "
                + "with a live preview pinned on top.",
            stage: .dark,
            keyboardThemes: [.light],
            contentRect: ScreenshotCanvas.tallContentRect),
        ScreenshotScene(
            id: .languages,
            kicker: "Five languages",
            headline: "Speaks your *language*.",
            subline: "Keys come from your active layout — "
                + "accents, umlauts and Cyrillic show exactly what you typed.",
            stage: .dark),
        ScreenshotScene(
            id: .privacy,
            kicker: "Private by design",
            headline: "Nothing *leaves* your Mac.",
            subline: "Keystrokes are drawn, then forgotten. "
                + "Passwords stay hidden while macOS Secure Input is active.",
            stage: .dark),
    ]
}

enum SceneKeys {
    static let command = KeySymbol(id: "command-left", display: "⌘", isModifier: true)
    static let shift = KeySymbol(id: "shift-left", display: "⇧", isModifier: true)

    static let chord = [Self.shift, Self.command, Self.letter("K")]

    static func letter(_ display: String) -> KeySymbol {
        KeySymbol(id: "key-\(display.lowercased())", display: display)
    }
}
