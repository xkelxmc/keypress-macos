import Foundation
import SwiftUI

// MARK: - OverlayPosition

/// Position of the key visualization overlay on screen.
/// 8 preset positions: 4 corners + 4 edge centers.
public enum OverlayPosition: String, CaseIterable, Codable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case centerLeft
    case centerRight
    case bottomLeft
    case bottomCenter
    case bottomRight
}

// MARK: - OverlaySize

/// Size presets for the key visualization.
public enum OverlaySize: String, CaseIterable, Codable, Sendable {
    case small
    case medium
    case large

    /// Scale factor relative to base size.
    public var scaleFactor: CGFloat {
        switch self {
        case .small: 0.75
        case .medium: 1.0
        case .large: 1.25
        }
    }
}

// MARK: - DisplayMode

/// Display mode for key visualization.
public enum DisplayMode: String, CaseIterable, Codable, Sendable {
    /// Only latest keystroke/combination visible. Each new key replaces previous.
    /// Best for shortcut demos, teaching.
    case single

    /// Queue of recent keystrokes. Keys accumulate and fade over time.
    /// Best for typing demos, streaming.
    case history
}

// MARK: - KeyCategory

/// Category of a key for color assignment.
public enum KeyCategory: String, CaseIterable, Codable, Sendable {
    case letter // A-Z, 0-9
    case command // ⌘
    case shift // ⇧
    case option // ⌥
    case control // ⌃
    case capsLock // ⇪
    case escape // ⎋
    case function // F1-F20
    case navigation // Arrows, Page Up/Down, Home, End
    case editing // Space, Tab, Return, Delete, Backspace
}

// MARK: - MonitorSelection

/// Selection for which monitor to display the overlay on.
public enum MonitorSelection: Codable, Sendable, Equatable, Hashable {
    /// Automatically follow active window (overlay appears on monitor where user is typing).
    case auto
    /// Fixed to a specific monitor by index (0-based into NSScreen.screens).
    case fixed(index: Int)
}

// MARK: - KeyboardFrameStyle

/// Style for the container around keys.
public enum KeyboardFrameStyle: String, CaseIterable, Codable, Sendable {
    /// 3D keyboard frame with depth and materials.
    case frame

    /// Simple semi-transparent overlay background.
    case overlay

    /// No background, keys float freely.
    case none
}

// MARK: - KeyCapStyle

/// Visual style for keycap rendering.
public enum KeyCapStyle: String, CaseIterable, Codable, Sendable {
    /// 3D mechanical keyboard style with depth and shadows.
    case mechanical

    /// Flat modern style with subtle shadows.
    case flat

    /// Minimal style with just text and background.
    case minimal
}

// MARK: - AppearanceMode

/// Appearance mode for color scheme selection.
public enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    /// Follow system light/dark mode automatically.
    case auto

    /// Fixed dark scheme with colored modifiers.
    case dark

    /// Fixed monochrome dark scheme.
    case monochrome

    /// Fixed light scheme with colored modifiers.
    case light

    /// Custom user-defined colors for each category.
    case custom

    /// Display name for UI.
    public var displayName: String {
        switch self {
        case .auto: "Auto"
        case .dark: "Dark"
        case .monochrome: "Mono"
        case .light: "Light"
        case .custom: "Custom"
        }
    }
}

// MARK: - KeyColor

/// A color that can be stored in UserDefaults.
public struct KeyColor: Codable, Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(_ color: Color) {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor.gray
        self.red = Double(nsColor.redComponent)
        self.green = Double(nsColor.greenComponent)
        self.blue = Double(nsColor.blueComponent)
        self.alpha = Double(nsColor.alphaComponent)
    }

    public var color: Color {
        Color(red: self.red, green: self.green, blue: self.blue, opacity: self.alpha)
    }

    // MARK: - Preset Colors

    /// Dark charcoal for regular keys.
    public static let charcoal = KeyColor(red: 0.15, green: 0.15, blue: 0.17)

    /// Light aluminum for regular keys (light mode).
    public static let aluminum = KeyColor(red: 0.88, green: 0.88, blue: 0.90)

    /// Green for Command key.
    public static let commandGreen = KeyColor(red: 0.20, green: 0.70, blue: 0.45)

    /// Red/coral for Shift key.
    public static let shiftRed = KeyColor(red: 0.90, green: 0.30, blue: 0.25)

    /// Blue for Option key.
    public static let optionBlue = KeyColor(red: 0.25, green: 0.45, blue: 0.95)

    /// Orange for Control key.
    public static let controlOrange = KeyColor(red: 0.95, green: 0.55, blue: 0.20)

    /// Teal for Escape key.
    public static let escapeTeal = KeyColor(red: 0.20, green: 0.75, blue: 0.70)

    /// Purple for Function keys.
    public static let functionPurple = KeyColor(red: 0.60, green: 0.40, blue: 0.80)

    /// Gray for Caps Lock.
    public static let capsLockGray = KeyColor(red: 0.35, green: 0.35, blue: 0.38)
}

// MARK: - KeyCategoryStyle

/// Complete style configuration for a key category.
public struct KeyCategoryStyle: Codable, Sendable, Equatable {
    /// Base color for the keycap.
    public var color: KeyColor

    /// 3D depth effect intensity (0.0 = flat, 1.0 = full 3D).
    public var depth: Double

    /// Corner radius multiplier (0.0 = sharp, 1.0 = maximum rounded).
    public var cornerRadius: Double

    /// Shadow intensity (0.0 = no shadow, 1.0 = full shadow).
    public var shadowIntensity: Double

    /// Visual style for the keycap.
    public var style: KeyCapStyle

    public init(
        color: KeyColor,
        depth: Double = 1.0,
        cornerRadius: Double = 0.5,
        shadowIntensity: Double = 1.0,
        style: KeyCapStyle = .mechanical)
    {
        self.color = color
        self.depth = depth.clamped(to: 0.0...1.0)
        self.cornerRadius = cornerRadius.clamped(to: 0.0...1.0)
        self.shadowIntensity = shadowIntensity.clamped(to: 0.0...1.0)
        self.style = style
    }

    /// Creates a default style for a category based on a color scheme.
    public static func `default`(for category: KeyCategory, scheme: KeyColorScheme) -> KeyCategoryStyle {
        KeyCategoryStyle(
            color: scheme.color(for: category),
            depth: 1.0,
            cornerRadius: 0.5,
            shadowIntensity: 1.0,
            style: .mechanical)
    }
}

// MARK: - Double Extension

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - KeyColorScheme

/// Complete color scheme for all key categories.
public struct KeyColorScheme: Codable, Sendable, Equatable {
    public var letter: KeyColor
    public var command: KeyColor
    public var shift: KeyColor
    public var option: KeyColor
    public var control: KeyColor
    public var capsLock: KeyColor
    public var escape: KeyColor
    public var function: KeyColor
    public var navigation: KeyColor
    public var editing: KeyColor

    public init(
        letter: KeyColor = .charcoal,
        command: KeyColor = .commandGreen,
        shift: KeyColor = .shiftRed,
        option: KeyColor = .optionBlue,
        control: KeyColor = .controlOrange,
        capsLock: KeyColor = .capsLockGray,
        escape: KeyColor = .escapeTeal,
        function: KeyColor = .functionPurple,
        navigation: KeyColor = .charcoal,
        editing: KeyColor = .charcoal)
    {
        self.letter = letter
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
        self.capsLock = capsLock
        self.escape = escape
        self.function = function
        self.navigation = navigation
        self.editing = editing
    }

    /// Returns the color for a given category.
    public func color(for category: KeyCategory) -> KeyColor {
        switch category {
        case .letter: self.letter
        case .command: self.command
        case .shift: self.shift
        case .option: self.option
        case .control: self.control
        case .capsLock: self.capsLock
        case .escape: self.escape
        case .function: self.function
        case .navigation: self.navigation
        case .editing: self.editing
        }
    }

    // MARK: - Presets

    /// Default dark scheme with colored modifiers.
    public static let dark = KeyColorScheme()

    /// Monochrome dark scheme.
    public static let monochromeDark = KeyColorScheme(
        letter: .charcoal,
        command: .charcoal,
        shift: .charcoal,
        option: .charcoal,
        control: .charcoal,
        capsLock: .charcoal,
        escape: .charcoal,
        function: .charcoal,
        navigation: .charcoal,
        editing: .charcoal)

    /// Light scheme with colored modifiers.
    public static let light = KeyColorScheme(
        letter: .aluminum,
        command: .commandGreen,
        shift: .shiftRed,
        option: .optionBlue,
        control: .controlOrange,
        capsLock: KeyColor(red: 0.75, green: 0.75, blue: 0.78),
        escape: .escapeTeal,
        function: .functionPurple,
        navigation: .aluminum,
        editing: .aluminum)
}

// MARK: - KeypressConfig

/// Application settings with UserDefaults persistence.
@MainActor
@Observable
public final class KeypressConfig {
    // MARK: - Singleton

    /// Shared settings instance.
    public static let shared = KeypressConfig()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let enabled = "settings.enabled"
        static let launchAtLogin = "settings.launchAtLogin"
        static let position = "settings.position"
        static let size = "settings.size"
        static let opacity = "settings.opacity"
        static let keyTimeout = "settings.keyTimeout"
        // Display mode
        static let displayMode = "settings.displayMode"
        static let showModifiersOnly = "settings.showModifiersOnly"
        static let maxKeys = "settings.maxKeys"
        static let duplicateLetters = "settings.duplicateLetters"
        static let limitIncludesModifiers = "settings.limitIncludesModifiers"
        // Appearance
        static let keyCapStyle = "settings.keyCapStyle"
        static let colorScheme = "settings.colorScheme"
        static let appearanceMode = "settings.appearanceMode"
        static let customColorScheme = "settings.customColorScheme"
        static let keyboardFrameStyle = "settings.keyboardFrameStyle"
        static let categoryStyleOverrides = "settings.categoryStyleOverrides"
        // Monitor
        static let monitorSelection = "settings.monitorSelection"
    }

    /// Key name for global hotkey (used by KeyboardShortcuts in main app).
    public static let globalHotkeyName = "toggleKeypress"

    // MARK: - Defaults

    private enum Defaults {
        static let enabled = true
        static let launchAtLogin = false
        static let position = OverlayPosition.bottomRight
        static let size = OverlaySize.medium
        static let opacity: Double = 1.0
        static let keyTimeout: Double = 1.5
        // Display mode
        static let displayMode = DisplayMode.single
        static let showModifiersOnly = false
        static let maxKeys = 6
        static let duplicateLetters = true
        static let limitIncludesModifiers = true
        // Appearance
        static let keyCapStyle = KeyCapStyle.mechanical
        static let colorScheme = KeyColorScheme.dark
        static let appearanceMode = AppearanceMode.auto
        static let customColorScheme = KeyColorScheme.dark
        static let keyboardFrameStyle = KeyboardFrameStyle.frame
        static let categoryStyleOverrides: [KeyCategory: KeyCategoryStyle] = [:]
        // Monitor
        static let monitorSelection = MonitorSelection.auto
    }

    // MARK: - Properties

    private let userDefaults: UserDefaults
    private var themeObserver: NSObjectProtocol?

    /// Whether key visualization is enabled.
    public var enabled: Bool {
        didSet { self.userDefaults.set(self.enabled, forKey: Keys.enabled) }
    }

    /// Whether app should launch at login.
    public var launchAtLogin: Bool {
        didSet { self.userDefaults.set(self.launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    /// Position of the overlay on screen.
    public var position: OverlayPosition {
        didSet { self.userDefaults.set(self.position.rawValue, forKey: Keys.position) }
    }

    /// Size of the key visualization.
    public var size: OverlaySize {
        didSet { self.userDefaults.set(self.size.rawValue, forKey: Keys.size) }
    }

    /// Opacity of the overlay (0.0 to 1.0).
    public var opacity: Double {
        didSet { self.userDefaults.set(self.opacity, forKey: Keys.opacity) }
    }

    /// Duration in seconds before a regular key disappears.
    /// Range: 0.5 to 5.0 seconds.
    public var keyTimeout: Double {
        didSet { self.userDefaults.set(self.keyTimeout, forKey: Keys.keyTimeout) }
    }

    // MARK: - Display Mode Properties

    /// Current display mode (single or history).
    public var displayMode: DisplayMode {
        didSet { self.userDefaults.set(self.displayMode.rawValue, forKey: Keys.displayMode) }
    }

    /// (Single mode) Only show key combinations that include modifiers.
    /// When true, regular letters/numbers without modifiers are hidden.
    public var showModifiersOnly: Bool {
        didSet { self.userDefaults.set(self.showModifiersOnly, forKey: Keys.showModifiersOnly) }
    }

    /// (History mode) Maximum number of keys to display at once.
    /// Range: 3 to 12.
    public var maxKeys: Int {
        didSet { self.userDefaults.set(self.maxKeys, forKey: Keys.maxKeys) }
    }

    /// (History mode) Whether to allow duplicate letters when typing.
    /// When true, "hello" shows 5 keys; when false, shows 4 (no repeat).
    public var duplicateLetters: Bool {
        didSet { self.userDefaults.set(self.duplicateLetters, forKey: Keys.duplicateLetters) }
    }

    /// (History mode) Whether modifiers count towards the max keys limit.
    /// When true (default), limit is total keys. When false, limit is only for letters.
    public var limitIncludesModifiers: Bool {
        didSet { self.userDefaults.set(self.limitIncludesModifiers, forKey: Keys.limitIncludesModifiers) }
    }

    // MARK: - Appearance Properties

    /// Visual style for keycap rendering.
    public var keyCapStyle: KeyCapStyle {
        didSet { self.userDefaults.set(self.keyCapStyle.rawValue, forKey: Keys.keyCapStyle) }
    }

    /// Color scheme for key categories (active scheme, may be preset or custom).
    public var colorScheme: KeyColorScheme {
        didSet {
            if let encoded = try? JSONEncoder().encode(self.colorScheme) {
                self.userDefaults.set(encoded, forKey: Keys.colorScheme)
            }
        }
    }

    /// Custom color scheme with user-defined colors for each category.
    /// Only used when appearanceMode is .custom.
    public var customColorScheme: KeyColorScheme {
        didSet {
            if let encoded = try? JSONEncoder().encode(self.customColorScheme) {
                self.userDefaults.set(encoded, forKey: Keys.customColorScheme)
            }
            // If in custom mode, sync to active colorScheme
            if self.appearanceMode == .custom {
                self.colorScheme = self.customColorScheme
            }
        }
    }

    /// User's appearance mode preference (auto follows system, others are fixed).
    public var appearanceMode: AppearanceMode {
        didSet {
            self.userDefaults.set(self.appearanceMode.rawValue, forKey: Keys.appearanceMode)
            self.updateColorSchemeForAppearanceMode()
        }
    }

    /// Style for the container around keys (frame, overlay, or none).
    public var keyboardFrameStyle: KeyboardFrameStyle {
        didSet { self.userDefaults.set(self.keyboardFrameStyle.rawValue, forKey: Keys.keyboardFrameStyle) }
    }

    /// Custom style overrides for key categories (only stores customized categories).
    public var categoryStyleOverrides: [KeyCategory: KeyCategoryStyle] {
        didSet {
            if let encoded = try? JSONEncoder().encode(self.categoryStyleOverrides) {
                self.userDefaults.set(encoded, forKey: Keys.categoryStyleOverrides)
            }
        }
    }

    // MARK: - Monitor Properties

    /// Which monitor to display the overlay on.
    public var monitorSelection: MonitorSelection {
        didSet {
            if let encoded = try? JSONEncoder().encode(self.monitorSelection) {
                self.userDefaults.set(encoded, forKey: Keys.monitorSelection)
            }
        }
    }

    // MARK: - Initialization

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Load persisted values or use defaults
        self.enabled = userDefaults.object(forKey: Keys.enabled) as? Bool ?? Defaults.enabled
        self.launchAtLogin = userDefaults.object(forKey: Keys.launchAtLogin) as? Bool ?? Defaults.launchAtLogin

        if let positionRaw = userDefaults.string(forKey: Keys.position),
           let position = OverlayPosition(rawValue: positionRaw)
        {
            self.position = position
        } else {
            self.position = Defaults.position
        }

        if let sizeRaw = userDefaults.string(forKey: Keys.size),
           let size = OverlaySize(rawValue: sizeRaw)
        {
            self.size = size
        } else {
            self.size = Defaults.size
        }

        if userDefaults.object(forKey: Keys.opacity) != nil {
            self.opacity = userDefaults.double(forKey: Keys.opacity)
        } else {
            self.opacity = Defaults.opacity
        }

        if userDefaults.object(forKey: Keys.keyTimeout) != nil {
            self.keyTimeout = userDefaults.double(forKey: Keys.keyTimeout)
        } else {
            self.keyTimeout = Defaults.keyTimeout
        }

        // Display mode settings
        if let displayModeRaw = userDefaults.string(forKey: Keys.displayMode),
           let displayMode = DisplayMode(rawValue: displayModeRaw)
        {
            self.displayMode = displayMode
        } else {
            self.displayMode = Defaults.displayMode
        }

        self.showModifiersOnly = userDefaults.object(forKey: Keys.showModifiersOnly) as? Bool
            ?? Defaults.showModifiersOnly

        if userDefaults.object(forKey: Keys.maxKeys) != nil {
            self.maxKeys = userDefaults.integer(forKey: Keys.maxKeys)
        } else {
            self.maxKeys = Defaults.maxKeys
        }

        self.duplicateLetters = userDefaults.object(forKey: Keys.duplicateLetters) as? Bool
            ?? Defaults.duplicateLetters

        self.limitIncludesModifiers = userDefaults.object(forKey: Keys.limitIncludesModifiers) as? Bool
            ?? Defaults.limitIncludesModifiers

        // Appearance settings
        if let styleRaw = userDefaults.string(forKey: Keys.keyCapStyle),
           let style = KeyCapStyle(rawValue: styleRaw)
        {
            self.keyCapStyle = style
        } else {
            self.keyCapStyle = Defaults.keyCapStyle
        }

        if let colorSchemeData = userDefaults.data(forKey: Keys.colorScheme),
           let scheme = try? JSONDecoder().decode(KeyColorScheme.self, from: colorSchemeData)
        {
            self.colorScheme = scheme
        } else {
            self.colorScheme = Defaults.colorScheme
        }

        if let customSchemeData = userDefaults.data(forKey: Keys.customColorScheme),
           let scheme = try? JSONDecoder().decode(KeyColorScheme.self, from: customSchemeData)
        {
            self.customColorScheme = scheme
        } else {
            self.customColorScheme = Defaults.customColorScheme
        }

        if let modeRaw = userDefaults.string(forKey: Keys.appearanceMode),
           let mode = AppearanceMode(rawValue: modeRaw)
        {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = Defaults.appearanceMode
        }

        if let styleRaw = userDefaults.string(forKey: Keys.keyboardFrameStyle),
           let style = KeyboardFrameStyle(rawValue: styleRaw)
        {
            self.keyboardFrameStyle = style
        } else {
            self.keyboardFrameStyle = Defaults.keyboardFrameStyle
        }

        if let overridesData = userDefaults.data(forKey: Keys.categoryStyleOverrides),
           let overrides = try? JSONDecoder().decode([KeyCategory: KeyCategoryStyle].self, from: overridesData)
        {
            self.categoryStyleOverrides = overrides
        } else {
            self.categoryStyleOverrides = Defaults.categoryStyleOverrides
        }

        // Monitor settings
        if let monitorData = userDefaults.data(forKey: Keys.monitorSelection),
           let selection = try? JSONDecoder().decode(MonitorSelection.self, from: monitorData)
        {
            self.monitorSelection = selection
        } else {
            self.monitorSelection = Defaults.monitorSelection
        }

        // Setup system theme observer and sync color scheme
        self.setupThemeObserver()
        self.updateColorSchemeForAppearanceMode()
    }

    // MARK: - Theme Observer

    /// Sets up observer for system appearance changes.
    private func setupThemeObserver() {
        self.themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateColorSchemeForAppearanceMode()
            }
        }
    }

    /// Returns true if system is in dark mode.
    private func systemIsDark() -> Bool {
        guard let appearance = NSApp?.effectiveAppearance else {
            return true // Default to dark when running in tests or before app launch
        }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Updates colorScheme based on appearanceMode and system theme.
    private func updateColorSchemeForAppearanceMode() {
        let newScheme: KeyColorScheme = switch self.appearanceMode {
        case .auto: self.systemIsDark() ? .dark : .light
        case .dark: .dark
        case .monochrome: .monochromeDark
        case .light: .light
        case .custom: self.customColorScheme
        }
        if self.colorScheme != newScheme {
            self.colorScheme = newScheme
        }
    }

    // MARK: - Style Access

    /// Returns the effective style for a category.
    /// Uses custom override if available, otherwise returns default style based on current color scheme
    /// and global keyCapStyle setting.
    public func effectiveStyle(for category: KeyCategory) -> KeyCategoryStyle {
        if let override = self.categoryStyleOverrides[category] {
            return override
        }
        return KeyCategoryStyle(
            color: self.colorScheme.color(for: category),
            depth: 1.0,
            cornerRadius: 0.5,
            shadowIntensity: 1.0,
            style: self.keyCapStyle)
    }

    /// Returns true if a category has a custom style override.
    public func hasStyleOverride(for category: KeyCategory) -> Bool {
        self.categoryStyleOverrides[category] != nil
    }

    /// Sets or removes a style override for a category.
    public func setStyleOverride(_ style: KeyCategoryStyle?, for category: KeyCategory) {
        if let style {
            self.categoryStyleOverrides[category] = style
        } else {
            self.categoryStyleOverrides.removeValue(forKey: category)
        }
    }

    // MARK: - Testing Support

    /// Creates a KeypressConfig instance with custom UserDefaults (for testing).
    static func makeForTesting(userDefaults: UserDefaults) -> KeypressConfig {
        let settings = KeypressConfig(userDefaults: userDefaults)
        return settings
    }

    /// Resets all settings to defaults.
    public func resetToDefaults() {
        self.enabled = Defaults.enabled
        self.launchAtLogin = Defaults.launchAtLogin
        self.position = Defaults.position
        self.size = Defaults.size
        self.opacity = Defaults.opacity
        self.keyTimeout = Defaults.keyTimeout
        self.displayMode = Defaults.displayMode
        self.showModifiersOnly = Defaults.showModifiersOnly
        self.maxKeys = Defaults.maxKeys
        self.duplicateLetters = Defaults.duplicateLetters
        self.limitIncludesModifiers = Defaults.limitIncludesModifiers
        self.keyCapStyle = Defaults.keyCapStyle
        self.colorScheme = Defaults.colorScheme
        self.customColorScheme = Defaults.customColorScheme
        self.appearanceMode = Defaults.appearanceMode
        self.keyboardFrameStyle = Defaults.keyboardFrameStyle
        self.categoryStyleOverrides = Defaults.categoryStyleOverrides
        self.monitorSelection = Defaults.monitorSelection
    }
}
