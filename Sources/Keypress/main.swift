import AppKit
import KeypressCore

// Keypress - keyboard visualizer for macOS
// Entry point for the menu bar application

// Check for offline rendering modes.
#if ENABLE_PREVIEW
if CommandLine.arguments.contains("--preview") {
    // Blocks on its own run loop and exits when done.
    PreviewGenerator.run()
}
#endif

if CommandLine.arguments.contains("--screenshot") {
    ScreenshotGenerator.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate

    // Hide from Dock
    app.setActivationPolicy(.accessory)

    app.run()
}
