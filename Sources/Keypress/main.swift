import AppKit
import KeypressCore

/// Keypress - keyboard visualizer for macOS
/// Entry point for the menu bar application

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Hide from Dock
app.setActivationPolicy(.accessory)

app.run()
