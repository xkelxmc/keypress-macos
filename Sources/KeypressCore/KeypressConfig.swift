import Foundation

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
    }

    // MARK: - Properties

    private let userDefaults: UserDefaults

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

    // MARK: - Initialization

    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Load persisted values or use defaults
        self.enabled = userDefaults.object(forKey: Keys.enabled) as? Bool ?? Defaults.enabled
        self.launchAtLogin = userDefaults.object(forKey: Keys.launchAtLogin) as? Bool ?? Defaults.launchAtLogin

        if let positionRaw = userDefaults.string(forKey: Keys.position),
           let position = OverlayPosition(rawValue: positionRaw) {
            self.position = position
        } else {
            self.position = Defaults.position
        }

        if let sizeRaw = userDefaults.string(forKey: Keys.size),
           let size = OverlaySize(rawValue: sizeRaw) {
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
           let displayMode = DisplayMode(rawValue: displayModeRaw) {
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
    }

    // MARK: - Testing Support

    /// Creates a KeypressConfig instance with custom UserDefaults (for testing).
    internal static func makeForTesting(userDefaults: UserDefaults) -> KeypressConfig {
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
    }
}
