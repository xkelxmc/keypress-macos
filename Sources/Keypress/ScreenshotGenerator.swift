import AppKit
import KeypressCore
import SwiftUI

@MainActor
enum ScreenshotGenerator {
    private static let canvasSize = CGSize(width: 1440, height: 900)
    private static let outputDirectory = "assets/appstore/generated"
    private static let renderScale: CGFloat = 2
    private static let suiteName = "dev.keypress.screenshots"

    private static let command = KeySymbol(id: "command-left", display: "⌘", isModifier: true)
    private static let shift = KeySymbol(id: "shift-left", display: "⇧", isModifier: true)
    private static let option = KeySymbol(id: "option-left", display: "⌥", isModifier: true)
    private static let control = KeySymbol(id: "control-left", display: "⌃", isModifier: true)

    private static let scenes: [ScreenshotScene] = [
        ScreenshotScene(
            id: "hero",
            headline: "Every keystroke, on screen.",
            subtitle: "live keyboard overlay for macos".uppercased(),
            background: .image("assets/screenshots/screenshot-bg-dark.png"),
            appearance: .dark,
            content: .keyboard(
                keys: [
                    Self.command,
                    Self.shift,
                    KeySymbol(id: "k", display: "K"),
                ],
                keyCapStyle: .mechanical,
                scale: 3,
                placement: .center)),
        ScreenshotScene(
            id: "in-context",
            headline: "Your audience sees what you pressed.",
            subtitle: "screen shares · streams · talks".uppercased(),
            background: .image("assets/screenshots/screenshot-bg-light.png"),
            appearance: .light,
            content: .keyboard(
                keys: [
                    Self.command,
                    Self.shift,
                    KeySymbol(id: "k", display: "K"),
                ],
                keyCapStyle: .mechanical,
                scale: 1.8,
                placement: .bottom)),
        ScreenshotScene(
            id: "single-mode",
            headline: "Just the shortcut.",
            subtitle: "single mode".uppercased(),
            background: .plate(.dark),
            appearance: .dark,
            content: .keyboard(
                keys: [
                    Self.command,
                    Self.option,
                    Self.shift,
                    KeySymbol(id: "4", display: "4"),
                ],
                keyCapStyle: .mechanical,
                scale: 2.8,
                placement: .center)),
        ScreenshotScene(
            id: "history-mode",
            headline: "Or every letter, as you type.",
            subtitle: "history mode".uppercased(),
            background: .plate(.dark),
            appearance: .dark,
            content: .keyboard(
                keys: [
                    KeySymbol(id: "h", display: "H"),
                    KeySymbol(id: "e", display: "E"),
                    KeySymbol(id: "l", display: "L"),
                    KeySymbol(id: "l2", display: "L"),
                    KeySymbol(id: "o", display: "O"),
                ],
                keyCapStyle: .mechanical,
                scale: 2.4,
                placement: .center)),
        ScreenshotScene(
            id: "unobtrusive",
            headline: "Invisible until you type.",
            subtitle: "no window · no dock icon · click-through".uppercased(),
            background: .plate(.dark),
            appearance: .dark,
            content: .diptych(
                imagePath: "assets/screenshots/screenshot-bg-dark.png",
                keys: [
                    Self.command,
                    Self.shift,
                    KeySymbol(id: "k", display: "K"),
                ],
                scale: 1.1)),
        ScreenshotScene(
            id: "keycap-styles",
            headline: "Three ways to look.",
            subtitle: "mechanical · flat · minimal".uppercased(),
            background: .plate(.light),
            appearance: .light,
            content: .keycapStyles(
                keys: [
                    Self.command,
                    KeySymbol(id: "k", display: "K"),
                ],
                styles: [.mechanical, .flat, .minimal],
                scale: 1.9)),
        ScreenshotScene(
            id: "colors",
            headline: "Your colors, key by key.",
            subtitle: "ten key categories · fully customizable".uppercased(),
            background: .plate(.dark),
            appearance: .dark,
            content: .colors(
                rows: [
                    [Self.command, Self.shift, Self.option, Self.control],
                    [
                        KeySymbol(id: "escape", display: "⎋", isSpecial: true),
                        KeySymbol(id: "f1", display: "F1", isSpecial: true),
                        KeySymbol(id: "a", display: "A"),
                        KeySymbol(id: "left", display: "←", isSpecial: true),
                        KeySymbol(id: "return", display: "⏎", isSpecial: true),
                    ],
                ],
                keyCapStyle: .mechanical,
                scale: 2.4)),
    ]

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
                print("\(scene.id)\t\(scene.headline)")
            }
            return
        }

        if arguments.contains("list") {
            throw ScreenshotError.invalidArguments("'list' cannot be combined with scene IDs")
        }

        let selectedScenes = try self.selectedScenes(for: arguments)
        try self.validateBackgrounds(for: selectedScenes)
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

        let knownIDs = Set(self.scenes.map(\.id))
        if let unknownID = requestedIDs.first(where: { !knownIDs.contains($0) }) {
            throw ScreenshotError.invalidArguments(
                "Unknown scene '\(unknownID)'. Run Keypress --screenshot list to see available scenes")
        }

        let requestedIDSet = Set(requestedIDs)
        return self.scenes.filter { requestedIDSet.contains($0.id) }
    }

    private static func validateBackgrounds(for scenes: [ScreenshotScene]) throws {
        var checkedPaths: Set<String> = []

        for path in scenes.flatMap(\.requiredImagePaths) where checkedPaths.insert(path).inserted {
            guard FileManager.default.fileExists(atPath: path) else {
                throw ScreenshotError.missingBackground(path)
            }
            guard NSImage(contentsOfFile: path) != nil else {
                throw ScreenshotError.unreadableBackground(path)
            }
        }
    }

    private static func render(scene: ScreenshotScene, index: Int) throws {
        let configs = try self.makeConfigs(for: scene)
        defer { self.clearEphemeralDefaults() }

        let backgroundImage = scene.background.imagePath.flatMap { NSImage(contentsOfFile: $0) }
        let contentImage = scene.content.imagePath.flatMap { NSImage(contentsOfFile: $0) }
        let rootView = ScreenshotSceneView(
            scene: scene,
            index: index,
            total: self.scenes.count,
            configs: configs,
            backgroundImage: backgroundImage,
            contentImage: contentImage)
            .environment(\.colorScheme, scene.colorScheme)

        let renderer = ImageRenderer(content: rootView)
        renderer.proposedSize = ProposedViewSize(self.canvasSize)
        renderer.scale = self.renderScale
        renderer.isOpaque = true

        guard let image = renderer.cgImage else {
            throw ScreenshotError.renderFailed(scene.id)
        }

        let expectedWidth = Int(self.canvasSize.width * self.renderScale)
        let expectedHeight = Int(self.canvasSize.height * self.renderScale)
        guard image.width == expectedWidth, image.height == expectedHeight else {
            throw ScreenshotError.invalidDimensions(
                sceneID: scene.id,
                width: image.width,
                height: image.height,
                expectedWidth: expectedWidth,
                expectedHeight: expectedHeight)
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotError.pngEncodingFailed(scene.id)
        }

        let filename = String(format: "%02d-%@.png", index, scene.id)
        let outputPath = "\(self.outputDirectory)/\(filename)"
        try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        print("\(outputPath) — \(image.width)x\(image.height)")
    }

    private static func makeConfigs(for scene: ScreenshotScene) throws -> [KeypressConfig] {
        switch scene.content {
        case let .keyboard(_, keyCapStyle, _, _):
            try [self.makeConfig(
                appearance: scene.appearance,
                keyCapStyle: keyCapStyle,
                keyboardFrameStyle: .frame)]
        case .diptych:
            try [self.makeConfig(
                appearance: scene.appearance,
                keyCapStyle: .mechanical,
                keyboardFrameStyle: .frame)]
        case let .keycapStyles(_, styles, _):
            try styles.map {
                try self.makeConfig(
                    appearance: scene.appearance,
                    keyCapStyle: $0,
                    keyboardFrameStyle: .frame)
            }
        case let .colors(_, keyCapStyle, _):
            try [self.makeConfig(
                appearance: scene.appearance,
                keyCapStyle: keyCapStyle,
                keyboardFrameStyle: .none)]
        }
    }

    private static func makeConfig(
        appearance: AppearanceMode,
        keyCapStyle: KeyCapStyle,
        keyboardFrameStyle: KeyboardFrameStyle) throws -> KeypressConfig
    {
        guard appearance != .auto else {
            throw ScreenshotError.invalidAppearance
        }
        guard let userDefaults = UserDefaults(suiteName: self.suiteName) else {
            throw ScreenshotError.userDefaultsUnavailable
        }

        userDefaults.removePersistentDomain(forName: self.suiteName)
        let config = KeypressConfig.makeEphemeral(userDefaults: userDefaults)
        config.appearanceMode = appearance
        config.keyCapStyle = keyCapStyle
        config.keyboardFrameStyle = keyboardFrameStyle
        return config
    }

    private static func clearEphemeralDefaults() {
        UserDefaults(suiteName: self.suiteName)?.removePersistentDomain(forName: self.suiteName)
    }
}

private struct ScreenshotScene {
    let id: String
    let headline: String
    let subtitle: String
    let background: SceneBackground
    let appearance: AppearanceMode
    let content: SceneContent

    var colorScheme: ColorScheme {
        self.appearance == .light ? .light : .dark
    }

    var requiredImagePaths: [String] {
        [self.background.imagePath, self.content.imagePath].compactMap(\.self)
    }
}

private enum PlateTone {
    case dark
    case light
}

private enum SceneBackground {
    case plate(PlateTone)
    case image(String)

    var imagePath: String? {
        guard case let .image(path) = self else { return nil }
        return path
    }

    var usesDarkForeground: Bool {
        switch self {
        case .plate(.light): false
        case .plate(.dark), .image: true
        }
    }
}

private enum ScenePlacement {
    case center
    case bottom

    var alignment: Alignment {
        switch self {
        case .center: .center
        case .bottom: .bottom
        }
    }
}

private enum SceneContent {
    case keyboard(
        keys: [KeySymbol],
        keyCapStyle: KeyCapStyle,
        scale: CGFloat = 2.6,
        placement: ScenePlacement = .center)
    case diptych(imagePath: String, keys: [KeySymbol], scale: CGFloat = 2.6)
    case keycapStyles(keys: [KeySymbol], styles: [KeyCapStyle], scale: CGFloat = 2.6)
    case colors(rows: [[KeySymbol]], keyCapStyle: KeyCapStyle, scale: CGFloat = 2.6)

    var imagePath: String? {
        guard case let .diptych(imagePath, _, _) = self else { return nil }
        return imagePath
    }
}

private enum ScreenshotError: LocalizedError {
    case invalidArguments(String)
    case invalidAppearance
    case invalidDimensions(
        sceneID: String,
        width: Int,
        height: Int,
        expectedWidth: Int,
        expectedHeight: Int)
    case missingBackground(String)
    case pngEncodingFailed(String)
    case renderFailed(String)
    case unreadableBackground(String)
    case userDefaultsUnavailable

    var errorDescription: String? {
        switch self {
        case let .invalidArguments(message):
            message
        case .invalidAppearance:
            "Screenshot scenes must use an explicit appearance mode"
        case let .invalidDimensions(sceneID, width, height, expectedWidth, expectedHeight):
            "Scene '\(sceneID)' rendered at \(width)x\(height), expected \(expectedWidth)x\(expectedHeight)"
        case let .missingBackground(path):
            [
                "Missing required background: \(path)",
                "",
                "Add background images or generate from macOS wallpaper videos:",
                "  cd ~/Library/Containers/com.apple.NeptuneOneExtension/Data/Library/Application\\ Support/Videos/",
                "  ffmpeg -i \"Tahoe Light Landscape.mov\" -vframes 1 assets/screenshots/screenshot-bg-light.png",
                "  ffmpeg -i \"Tahoe Dark Landscape.mov\" -vframes 1 assets/screenshots/screenshot-bg-dark.png",
            ].joined(separator: "\n")
        case let .pngEncodingFailed(sceneID):
            "Cannot encode scene '\(sceneID)' as PNG"
        case let .renderFailed(sceneID):
            "Cannot render scene '\(sceneID)'"
        case let .unreadableBackground(path):
            "Cannot load required background: \(path)"
        case .userDefaultsUnavailable:
            "Cannot create the screenshot UserDefaults suite"
        }
    }
}

private struct ScreenshotSceneView: View {
    private static let canvasSize = CGSize(width: 1440, height: 900)
    private static let contentSize = CGSize(width: 1248, height: 504)
    private static let contentCenter = CGPoint(x: 720, y: 552)
    private static let margin: CGFloat = 96

    let scene: ScreenshotScene
    let index: Int
    let total: Int
    let configs: [KeypressConfig]
    let backgroundImage: NSImage?
    let contentImage: NSImage?

    private var foregroundColor: Color {
        self.scene.background.usesDarkForeground
            ? Color(red: 242 / 255, green: 240 / 255, blue: 236 / 255)
            : Color(red: 22 / 255, green: 21 / 255, blue: 26 / 255)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SceneBackgroundView(background: self.scene.background, image: self.backgroundImage)

            SceneContentView(
                content: self.scene.content,
                configs: self.configs,
                image: self.contentImage,
                foregroundColor: self.foregroundColor)
                .frame(width: Self.contentSize.width, height: Self.contentSize.height)
                .position(Self.contentCenter)

            VStack(alignment: .leading, spacing: 16) {
                Text(self.scene.headline)
                    .font(.system(size: 64, weight: .semibold, design: .serif))
                    .tracking(-1)
                    .lineSpacing(4)
                    .frame(width: 900, alignment: .leading)
                    .multilineTextAlignment(.leading)

                Text(self.scene.subtitle)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .tracking(2.5)
                    .opacity(0.55)
            }
            .foregroundStyle(self.foregroundColor)
            .padding(.leading, Self.margin)
            .padding(.top, Self.margin)

            Text(String(format: "%02d / %02d", self.index, self.total))
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(self.foregroundColor)
                .opacity(0.3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(Self.margin)
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .clipped()
    }
}

private struct SceneBackgroundView: View {
    let background: SceneBackground
    let image: NSImage?

    var body: some View {
        switch self.background {
        case let .plate(tone):
            self.plate(tone: tone)
        case .image:
            ZStack {
                if let image = self.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }

                LinearGradient(
                    stops: [
                        Gradient.Stop(color: Color.black.opacity(0.45), location: 0),
                        Gradient.Stop(color: .clear, location: 0.55),
                        Gradient.Stop(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom)
            }
            .frame(width: 1440, height: 900)
            .clipped()
        }
    }

    private func plate(tone: PlateTone) -> some View {
        let colors: [Color]
        let vignetteOpacity: Double

        switch tone {
        case .dark:
            colors = [
                Color(red: 37 / 255, green: 37 / 255, blue: 42 / 255),
                Color(red: 23 / 255, green: 23 / 255, blue: 26 / 255),
            ]
            vignetteOpacity = 0.45
        case .light:
            colors = [
                Color(red: 237 / 255, green: 235 / 255, blue: 230 / 255),
                Color(red: 218 / 255, green: 215 / 255, blue: 208 / 255),
            ]
            vignetteOpacity = 0.1
        }

        return ZStack {
            RadialGradient(
                colors: colors,
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 0,
                endRadius: 1000)
            RadialGradient(
                colors: [.clear, Color.black.opacity(vignetteOpacity)],
                center: .center,
                startRadius: 0,
                endRadius: 850)
        }
        .frame(width: 1440, height: 900)
    }
}

private struct SceneContentView: View {
    let content: SceneContent
    let configs: [KeypressConfig]
    let image: NSImage?
    let foregroundColor: Color

    var body: some View {
        switch self.content {
        case let .keyboard(keys, _, scale, placement):
            ScaledKeyboardView(keys: keys, config: self.configs[0], scale: scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placement.alignment)
        case let .diptych(_, keys, scale):
            DiptychView(
                image: self.image,
                keys: keys,
                config: self.configs[0],
                scale: scale,
                foregroundColor: self.foregroundColor)
        case let .keycapStyles(keys, styles, scale):
            VStack(spacing: 40) {
                ForEach(Array(styles.enumerated()), id: \.offset) { index, style in
                    HStack(spacing: 32) {
                        Text(style.rawValue.uppercased())
                            .font(.system(size: 15, weight: .regular, design: .monospaced))
                            .foregroundStyle(self.foregroundColor)
                            .opacity(0.5)
                            .frame(width: 160, alignment: .trailing)

                        ScaledKeyboardView(keys: keys, config: self.configs[index], scale: scale)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case let .colors(rows, _, scale):
            ScaledKeyGridView(rows: rows, config: self.configs[0], scale: scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct DiptychView: View {
    private static let panelSize = CGSize(width: 608, height: 342)

    let image: NSImage?
    let keys: [KeySymbol]
    let config: KeypressConfig
    let scale: CGFloat
    let foregroundColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            self.panel(label: "idle", showsKeyboard: false)
            self.panel(label: "typing", showsKeyboard: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func panel(label: String, showsKeyboard: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottom) {
                if let image = self.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }

                if showsKeyboard {
                    ScaledKeyboardView(keys: self.keys, config: self.config, scale: self.scale)
                        .padding(.bottom, 24)
                }
            }
            .frame(width: Self.panelSize.width, height: Self.panelSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Text(label)
                .font(.system(size: 16, weight: .regular, design: .monospaced))
                .foregroundStyle(self.foregroundColor)
                .opacity(0.5)
        }
    }
}

private struct ScaledKeyboardView: View {
    private static let keySpacing: CGFloat = 6

    let keys: [KeySymbol]
    let config: KeypressConfig
    let scale: CGFloat

    private var keyboard: some View {
        KeyboardFrameView(config: self.config) {
            HStack(spacing: Self.keySpacing) {
                ForEach(self.keys) { symbol in
                    KeyCapView(
                        symbol: symbol,
                        config: self.config,
                        isPressed: false,
                        delayPressAnimation: false)
                }
            }
        }
    }

    var body: some View {
        // scaleEffect does not affect layout, so the parent must reserve the scaled
        // footprint itself — measured, not estimated, or every scene drifts off centre.
        let natural = ViewMeasure.fittingSize(of: self.keyboard)
        return self.keyboard
            .scaleEffect(self.scale)
            .frame(width: natural.width * self.scale, height: natural.height * self.scale)
    }
}

private struct ScaledKeyGridView: View {
    private static let spacing: CGFloat = 20

    let rows: [[KeySymbol]]
    let config: KeypressConfig
    let scale: CGFloat

    private var grid: some View {
        VStack(spacing: Self.spacing) {
            ForEach(Array(self.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.spacing) {
                    ForEach(row) { symbol in
                        KeyCapView(
                            symbol: symbol,
                            config: self.config,
                            isPressed: false,
                            delayPressAnimation: false)
                    }
                }
            }
        }
    }

    var body: some View {
        let natural = ViewMeasure.fittingSize(of: self.grid)
        return self.grid
            .scaleEffect(self.scale)
            .frame(width: natural.width * self.scale, height: natural.height * self.scale)
    }
}

/// Exact layout size of a SwiftUI subtree, resolved synchronously so `ImageRenderer`
/// scenes can reserve space for `scaleEffect`-scaled content.
@MainActor
private enum ViewMeasure {
    static func fittingSize(of view: some View) -> CGSize {
        let controller = NSHostingController(rootView: view)
        return controller.sizeThatFits(in: CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude))
    }
}
