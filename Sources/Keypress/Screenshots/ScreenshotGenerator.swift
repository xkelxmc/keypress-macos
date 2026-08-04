import AppKit
import KeypressCore
import SwiftUI

@MainActor
enum ScreenshotGenerator {
    private static let outputDirectory = "assets/appstore/generated"
    private static let suiteName = "dev.keypress.screenshots"

    private static var scenes: [ScreenshotScene] {
        SceneCatalog.scenes
    }

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
        if arguments == ["list"] {
            for scene in self.scenes {
                print("\(scene.id.rawValue)\t\(scene.headline.replacingOccurrences(of: "*", with: ""))")
            }
            return
        }

        if arguments.contains("list") {
            throw ScreenshotError.invalidArguments("'list' cannot be combined with scene IDs")
        }

        let selectedScenes = try self.selectedScenes(for: arguments)
        try FileManager.default.createDirectory(
            atPath: self.outputDirectory,
            withIntermediateDirectories: true)

        for scene in selectedScenes {
            guard let sceneIndex = self.scenes.firstIndex(where: { $0.id == scene.id }) else { continue }
            try self.render(scene: scene, index: sceneIndex + 1)
        }
    }

    private static func selectedScenes(for requestedIDs: [String]) throws -> [ScreenshotScene] {
        guard !requestedIDs.isEmpty else { return self.scenes }

        let knownIDs = Set(self.scenes.map(\.id.rawValue))
        if let unknownID = requestedIDs.first(where: { !knownIDs.contains($0) }) {
            throw ScreenshotError.invalidArguments(
                "Unknown scene '\(unknownID)'. Run Keypress --screenshot list to see available scenes")
        }

        let requestedIDSet = Set(requestedIDs)
        return self.scenes.filter { requestedIDSet.contains($0.id.rawValue) }
    }

    private static func render(scene: ScreenshotScene, index: Int) throws {
        let configs = try self.makeConfigs(for: scene)
        defer { self.clearEphemeralDefaults() }

        let rootView = try ScreenshotSceneView(
            scene: scene,
            index: index,
            total: self.scenes.count,
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
        let outputPath = "\(self.outputDirectory)/\(filename)"
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

    private static func makeConfigs(for scene: ScreenshotScene) throws -> SceneConfigs {
        var byTheme: [ThemeSelection: KeypressConfig] = [:]
        for selection in scene.keyboardThemes {
            byTheme[selection] = try self.makeConfig(themeSelection: selection)
        }
        return try SceneConfigs(
            fallback: self.makeConfig(themeSelection: .dark),
            byTheme: byTheme)
    }

    /// Every scene gets a pristine, isolated settings store — never the user's own.
    private static func makeConfig(themeSelection: ThemeSelection) throws -> KeypressConfig {
        guard let userDefaults = UserDefaults(suiteName: self.suiteName) else {
            throw ScreenshotError.userDefaultsUnavailable
        }

        userDefaults.removePersistentDomain(forName: self.suiteName)
        let config = KeypressConfig.makeEphemeral(userDefaults: userDefaults)
        config.appearance.keyboardThemeSelection = themeSelection
        config.appearance.pointerThemeSelection = themeSelection
        // Screenshots ship to en-US regardless of the machine that renders them.
        config.general.language = .english
        return config
    }

    private static func clearEphemeralDefaults() {
        UserDefaults(suiteName: self.suiteName)?.removePersistentDomain(forName: self.suiteName)
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
