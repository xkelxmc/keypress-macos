import AppKit
import KeypressCore
import SwiftUI

@MainActor
enum ScreenshotGenerator {
    /// One folder per locale, the way the store listings are uploaded: its ten
    /// frames next to its App Preview.
    private static let outputRoot = "assets/appstore/generated"
    private static let suiteName = "dev.keypress.screenshots"

    static func run() {
        let arguments = self.screenshotArguments()

        DispatchQueue.main.async {
            do {
                try self.execute(arguments: arguments)
                exit(0)
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        RunLoop.main.run()
    }

    private static func screenshotArguments() -> [String] {
        guard let flagIndex = CommandLine.arguments.firstIndex(of: "--screenshot") else { return [] }
        return Array(CommandLine.arguments.dropFirst(flagIndex + 1))
    }

    private static func execute(arguments: [String]) throws {
        let request = try ScreenshotRequest(arguments: arguments)

        if request.listsScenes {
            for scene in SceneCatalog.scenes(for: .enUS) {
                print("\(scene.id.rawValue)\t\(scene.copy.headline.replacingOccurrences(of: "*", with: ""))")
            }
            return
        }

        for locale in request.locales {
            try self.render(locale: locale, sceneIDs: request.sceneIDs)
        }
    }

    private static func render(locale: MarketingLocale, sceneIDs: Set<String>) throws {
        let scenes = SceneCatalog.scenes(for: locale)
        let knownIDs = Set(scenes.map(\.id.rawValue))
        if let unknownID = sceneIDs.subtracting(knownIDs).first {
            throw ScreenshotError.invalidArguments(
                "Unknown scene '\(unknownID)'. Run Keypress --screenshot list to see available scenes")
        }

        let directory = "\(self.outputRoot)/\(locale.rawValue)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        for (index, scene) in scenes.enumerated() where sceneIDs.isEmpty || sceneIDs.contains(scene.id.rawValue) {
            try self.render(
                scene: scene,
                locale: locale,
                index: index + 1,
                total: scenes.count,
                directory: directory)
        }
    }

    private static func render(
        scene: ScreenshotScene,
        locale: MarketingLocale,
        index: Int,
        total: Int,
        directory: String) throws
    {
        let configs = try self.makeConfigs(for: scene, locale: locale)
        defer { self.clearEphemeralDefaults() }

        let rootView = try ScreenshotSceneView(
            scene: scene,
            strings: MarketingStrings.table(for: locale),
            index: index,
            total: total,
            configs: configs,
            assets: self.makeAssets(for: scene, configs: configs))
            .environment(\.colorScheme, scene.stage.colorScheme)

        let renderer = ImageRenderer(content: rootView)
        renderer.proposedSize = ProposedViewSize(ScreenshotCanvas.size)
        renderer.scale = ScreenshotCanvas.renderScale
        renderer.isOpaque = true

        guard let image = renderer.cgImage else {
            throw ScreenshotError.renderFailed(scene.id.rawValue)
        }

        let expectedWidth = Int(ScreenshotCanvas.size.width * ScreenshotCanvas.renderScale)
        let expectedHeight = Int(ScreenshotCanvas.size.height * ScreenshotCanvas.renderScale)
        guard image.width == expectedWidth, image.height == expectedHeight else {
            throw ScreenshotError.invalidDimensions(
                sceneID: scene.id.rawValue,
                width: image.width,
                height: image.height,
                expectedWidth: expectedWidth,
                expectedHeight: expectedHeight)
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.pngEncodingFailed(scene.id.rawValue)
        }

        let filename = String(format: "%02d-%@.png", index, scene.id.rawValue)
        let outputPath = "\(directory)/\(filename)"
        try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        print("\(outputPath) — \(image.width)x\(image.height)")
    }

    /// The settings window is AppKit-backed, so it is rasterized before the scene is drawn.
    private static func makeAssets(
        for scene: ScreenshotScene,
        configs: SceneConfigs) throws -> SceneAssets
    {
        let destination: SettingsDestination? = switch scene.id {
        case .studio: .pet
        case .studioAppearance: .keyboardAppearance
        default: nil
        }
        guard let destination else { return SceneAssets() }

        let navigation = SettingsNavigationState()
        navigation.selectedDestination = destination
        let settings = SettingsView(
            config: configs[.light],
            navigation: navigation,
            onboardingProgress: .shared)
            .environment(\.colorScheme, .light)
            .environment(\.controlActiveState, .active)

        guard let image = WindowCapture.image(
            of: settings,
            contentSize: StudioSceneMetrics.windowSize(for: scene.id),
            appearance: .aqua)
        else {
            throw ScreenshotError.settingsCaptureFailed
        }
        return SceneAssets(settingsWindow: image)
    }

    private static func makeConfigs(for scene: ScreenshotScene, locale: MarketingLocale) throws -> SceneConfigs {
        var byTheme: [ThemeSelection: KeypressConfig] = [:]
        for selection in scene.keyboardThemes {
            byTheme[selection] = try self.makeConfig(themeSelection: selection, locale: locale)
        }
        return try SceneConfigs(
            fallback: self.makeConfig(themeSelection: .dark, locale: locale),
            byTheme: byTheme)
    }

    /// Every scene gets a pristine, isolated settings store — never the user's own.
    private static func makeConfig(themeSelection: ThemeSelection, locale: MarketingLocale) throws -> KeypressConfig {
        guard let userDefaults = UserDefaults(suiteName: self.suiteName) else {
            throw ScreenshotError.userDefaultsUnavailable
        }

        userDefaults.removePersistentDomain(forName: self.suiteName)
        let config = KeypressConfig.makeEphemeral(userDefaults: userDefaults)
        config.appearance.keyboardThemeSelection = themeSelection
        config.appearance.pointerThemeSelection = themeSelection
        // The captured settings window renders in the locale the frame ships to.
        config.general.language = locale.appLanguage
        return config
    }

    private static func clearEphemeralDefaults() {
        UserDefaults(suiteName: self.suiteName)?.removePersistentDomain(forName: self.suiteName)
    }
}

/// `--screenshot [scene-id ...] [--language <code>|all] | list`
struct ScreenshotRequest {
    let sceneIDs: Set<String>
    let locales: [MarketingLocale]
    let listsScenes: Bool

    init(arguments: [String]) throws {
        var ids: [String] = []
        var locales = MarketingLocale.allCases
        var lists = false
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "list":
                lists = true
                index += 1
            case "--language":
                guard index + 1 < arguments.count else {
                    throw ScreenshotError.invalidArguments("--language needs a code or 'all'")
                }
                locales = try Self.locales(for: arguments[index + 1])
                index += 2
            default:
                ids.append(arguments[index])
                index += 1
            }
        }

        if lists, !ids.isEmpty {
            throw ScreenshotError.invalidArguments("'list' cannot be combined with scene IDs")
        }

        self.sceneIDs = Set(ids)
        self.locales = locales
        self.listsScenes = lists
    }

    private static func locales(for value: String) throws -> [MarketingLocale] {
        if value == "all" {
            return MarketingLocale.allCases
        }
        guard let locale = MarketingLocale(rawValue: value) else {
            throw ScreenshotError.invalidArguments(
                "Unknown language '\(value)'. Use 'all' or one of: "
                    + MarketingLocale.allCases.map(\.rawValue).joined(separator: ", "))
        }
        return [locale]
    }
}

enum ScreenshotError: LocalizedError {
    case invalidArguments(String)
    case invalidDimensions(
        sceneID: String,
        width: Int,
        height: Int,
        expectedWidth: Int,
        expectedHeight: Int)
    case pngEncodingFailed(String)
    case renderFailed(String)
    case settingsCaptureFailed
    case userDefaultsUnavailable

    var errorDescription: String? {
        switch self {
        case let .invalidArguments(message):
            message
        case let .invalidDimensions(sceneID, width, height, expectedWidth, expectedHeight):
            "Scene '\(sceneID)' rendered at \(width)x\(height), expected \(expectedWidth)x\(expectedHeight)"
        case let .pngEncodingFailed(sceneID):
            "Cannot encode scene '\(sceneID)' as PNG"
        case let .renderFailed(sceneID):
            "Cannot render scene '\(sceneID)'"
        case .settingsCaptureFailed:
            "Cannot capture the settings window for the studio scene"
        case .userDefaultsUnavailable:
            "Cannot create the screenshot UserDefaults suite"
        }
    }
}
