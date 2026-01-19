import AppKit
import KeypressCore
import SwiftUI

/// Generates promotional screenshots for README using real SwiftUI components.
/// Usage: Keypress --screenshot [light|dark|both] [wallpaper-path]
@MainActor
enum ScreenshotGenerator {
    private static let outputDir = "assets/screenshots/generated"
    private static let wallpaperDir = "assets/screenshots"
    private static let outputSize = CGSize(width: 1280, height: 720)

    static func run() {
        // Parse arguments
        let args = CommandLine.arguments
        var mode = "both"
        var customWallpaperPath: String?

        for (index, arg) in args.enumerated() {
            if arg == "--screenshot" {
                if index + 1 < args.count && !args[index + 1].hasPrefix("-") {
                    mode = args[index + 1]
                }
                if index + 2 < args.count && !args[index + 2].hasPrefix("-") {
                    customWallpaperPath = args[index + 2]
                }
            }
        }

        // Run on main thread for SwiftUI
        DispatchQueue.main.async {
            do {
                try self.generate(mode: mode, customWallpaperPath: customWallpaperPath)
                print("Done!")
                exit(0)
            } catch {
                print("Error: \(error.localizedDescription)")
                exit(1)
            }
        }

        // Keep running until screenshots are done
        RunLoop.main.run()
    }

    private static func generate(mode: String, customWallpaperPath: String?) throws {
        let fm = FileManager.default

        // Determine wallpaper paths
        let lightWallpaper = customWallpaperPath ?? "\(self.wallpaperDir)/screenshot-bg-light.png"
        let darkWallpaper = customWallpaperPath ?? "\(self.wallpaperDir)/screenshot-bg-dark.png"

        // Check wallpapers exist
        var missing: [String] = []
        if (mode == "light" || mode == "both") && !fm.fileExists(atPath: lightWallpaper) {
            missing.append("screenshot-bg-light.png")
        }
        if (mode == "dark" || mode == "both") && !fm.fileExists(atPath: darkWallpaper) {
            missing.append("screenshot-bg-dark.png")
        }

        if !missing.isEmpty {
            print("Error: Missing wallpaper backgrounds in \(self.wallpaperDir)")
            print("Missing: \(missing.joined(separator: ", "))")
            print("")
            print("Add background images or generate from macOS wallpaper videos:")
            print("  cd ~/Library/Containers/com.apple.NeptuneOneExtension/Data/Library/Application\\ Support/Videos/")
            print("  ffmpeg -i \"Tahoe Light Landscape.mov\" -vframes 1 \(self.wallpaperDir)/screenshot-bg-light.png")
            print("  ffmpeg -i \"Tahoe Dark Landscape.mov\" -vframes 1 \(self.wallpaperDir)/screenshot-bg-dark.png")
            throw NSError(domain: "Screenshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing wallpapers"])
        }

        // Create output directory
        let outputURL = URL(fileURLWithPath: self.outputDir)
        try fm.createDirectory(at: outputURL, withIntermediateDirectories: true)

        // Timestamp for unique filenames
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        // Generate screenshots
        if mode == "light" || mode == "both" {
            try self.generateScreenshot(
                wallpaperPath: lightWallpaper,
                outputPath: "\(self.outputDir)/keypress-light_\(timestamp).png",
                isDark: false
            )
        }

        if mode == "dark" || mode == "both" {
            try self.generateScreenshot(
                wallpaperPath: darkWallpaper,
                outputPath: "\(self.outputDir)/keypress-dark_\(timestamp).png",
                isDark: true
            )
        }
    }

    private static func generateScreenshot(wallpaperPath: String, outputPath: String, isDark: Bool) throws {
        guard let wallpaper = NSImage(contentsOfFile: wallpaperPath) else {
            throw NSError(domain: "Screenshot", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot load wallpaper"])
        }

        // Create config for screenshot (use shared, temporarily override settings)
        let config = KeypressConfig.shared
        let originalAppearance = config.appearanceMode
        let originalFrameStyle = config.keyboardFrameStyle

        config.appearanceMode = isDark ? .dark : .light
        config.keyboardFrameStyle = .frame

        defer {
            // Restore original settings
            config.appearanceMode = originalAppearance
            config.keyboardFrameStyle = originalFrameStyle
        }

        // Create the SwiftUI view with scale to fill ~70% of width
        let keysView = ScreenshotKeysView(config: config, scale: 3.0)

        // Render to image using ImageRenderer
        let renderer = ImageRenderer(content: keysView)
        renderer.scale = 2.0 // Retina

        guard let keysImage = renderer.nsImage else {
            throw NSError(domain: "Screenshot", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot render keys"])
        }

        // Composite wallpaper + keys
        let finalImage = NSImage(size: self.outputSize)
        finalImage.lockFocus()

        // Draw wallpaper scaled to fill
        wallpaper.draw(
            in: CGRect(origin: .zero, size: self.outputSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )

        // Draw keys centered
        let keysSize = keysImage.size
        let keysOrigin = CGPoint(
            x: (self.outputSize.width - keysSize.width) / 2,
            y: (self.outputSize.height - keysSize.height) / 2
        )
        keysImage.draw(
            in: CGRect(origin: keysOrigin, size: keysSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )

        finalImage.unlockFocus()

        // Save as PNG
        guard let tiffData = finalImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "Screenshot", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot convert to PNG"])
        }

        try pngData.write(to: URL(fileURLWithPath: outputPath))
        print("✓ Generated: \(outputPath)")
    }
}

// MARK: - Screenshot Keys View

/// SwiftUI view for screenshot - uses real KeyCapView and KeyboardFrameView components.
private struct ScreenshotKeysView: View {
    let config: KeypressConfig
    let scale: CGFloat

    init(config: KeypressConfig, scale: CGFloat = 3.0) {
        self.config = config
        self.scale = scale
    }

    private var keysView: some View {
        HStack(spacing: 6) {
            KeyCapView(
                symbol: KeySymbol(id: "command-left", display: "⌘", isModifier: true),
                config: self.config
            )
            KeyCapView(
                symbol: KeySymbol(id: "shift-left", display: "⇧", isModifier: true),
                config: self.config
            )
            KeyCapView(
                symbol: KeySymbol(id: "k", display: "K"),
                config: self.config
            )
        }
    }

    var body: some View {
        KeyboardFrameView(config: self.config) {
            self.keysView
        }
        .scaleEffect(self.scale)
        .padding(.horizontal, 150 * self.scale) // Extra horizontal for shadow
        .padding(.vertical, 120 * self.scale)
    }
}
