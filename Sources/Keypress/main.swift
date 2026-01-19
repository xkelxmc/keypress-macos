import AppKit
import KeypressCore

// Keypress - keyboard visualizer for macOS
// Entry point for the menu bar application

// Check for screenshot mode
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
