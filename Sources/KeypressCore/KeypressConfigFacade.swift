import AppKit
import CoreGraphics
import Foundation

/// Observable settings facade backed by one versioned AppSettings document.
@MainActor
@Observable
public final class KeypressConfig {
    public static let shared = KeypressConfig()
    public static let globalHotkeyName = "toggleKeypress"
    public static let storageKey = "settings.app"

    public private(set) var schemaVersion = AppSettings.currentSchemaVersion

    public var general: GeneralSettings {
        didSet { self.persist() }
    }

    public var keyboard: KeyboardSettings {
        didSet {
            let normalized = self.keyboard.normalized()
            if self.keyboard != normalized {
                self.keyboard = normalized
            }
            self.persist()
        }
    }

    public var pointer: PointerSettings {
        didSet {
            let normalized = self.pointer.normalized()
            if self.pointer != normalized {
                self.pointer = normalized
            }
            self.persist()
        }
    }

    public var pet: PetSettings {
        didSet {
            let normalized = self.pet.normalized()
            if self.pet != normalized {
                self.pet = normalized
            }
            self.persist()
        }
    }

    public var appearance: AppearanceSettings {
        didSet { self.persist() }
    }

    public var displays: DisplaySettings {
        didSet { self.persist() }
    }

    public var hud: HUDSettings {
        didSet {
            let normalized = self.hud.normalized()
            if self.hud != normalized {
                self.hud = normalized
            }
            self.persist()
        }
    }

    private let userDefaults: UserDefaults
    private let defersPersistence: Bool
    private var isLoading = true
    private var persistenceTask: Task<Void, Never>?

    private init(
        userDefaults: UserDefaults = .standard,
        defersPersistence: Bool = true)
    {
        self.userDefaults = userDefaults
        self.defersPersistence = defersPersistence

        let loaded = Self.load(from: userDefaults)
        self.schemaVersion = AppSettings.currentSchemaVersion
        self.general = loaded.general
        self.keyboard = loaded.keyboard.normalized()
        self.pointer = loaded.pointer.normalized()
        self.pet = loaded.pet.normalized()
        self.appearance = loaded.appearance
        self.displays = loaded.displays
        self.hud = loaded.hud.normalized()
        self.isLoading = false
        self.persist()
    }

    public var snapshot: AppSettings {
        AppSettings(
            schemaVersion: self.schemaVersion,
            general: self.general,
            keyboard: self.keyboard,
            pointer: self.pointer,
            pet: self.pet,
            appearance: self.appearance,
            displays: self.displays,
            hud: self.hud)
    }

    public func effectiveTheme(isSystemDark: Bool) -> ThemeDefinition {
        self.appearance.resolvedTheme(isSystemDark: isSystemDark)
    }

    public func beginCustomizingTheme(isSystemDark: Bool) {
        self.appearance.beginCustomizing(isSystemDark: isSystemDark)
    }

    public func beginCustomizingKeyboardTheme(isSystemDark: Bool) {
        self.appearance.beginCustomizingKeyboard(isSystemDark: isSystemDark)
    }

    public func beginCustomizingPointerTheme(isSystemDark: Bool) {
        self.appearance.beginCustomizingPointer(isSystemDark: isSystemDark)
    }

    public func resetToDefaults() {
        let defaults = AppSettings()
        self.isLoading = true
        self.schemaVersion = defaults.schemaVersion
        self.general = defaults.general
        self.keyboard = defaults.keyboard
        self.pointer = defaults.pointer
        self.pet = defaults.pet
        self.appearance = defaults.appearance
        self.displays = defaults.displays
        self.hud = defaults.hud
        self.isLoading = false
        self.persist()
    }

    public static func makeEphemeral(userDefaults: UserDefaults) -> KeypressConfig {
        KeypressConfig(userDefaults: userDefaults, defersPersistence: false)
    }

    static func makeForTesting(userDefaults: UserDefaults) -> KeypressConfig {
        self.makeEphemeral(userDefaults: userDefaults)
    }

    private func persist() {
        guard !self.isLoading else { return }

        guard self.defersPersistence else {
            self.persistImmediately(self.snapshot)
            return
        }

        self.persistenceTask?.cancel()
        let snapshot = self.snapshot
        self.persistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }

            do {
                let data = try await Task.detached(priority: .utility) {
                    try JSONEncoder().encode(snapshot)
                }.value
                guard !Task.isCancelled else { return }
                self.userDefaults.set(data, forKey: Self.storageKey)
            } catch {
                print("[Keypress] ERROR: Failed to save settings: \(error)")
            }
            self.persistenceTask = nil
        }
    }

    public func flushPersistence() {
        guard !self.isLoading else { return }
        self.persistenceTask?.cancel()
        self.persistenceTask = nil
        self.persistImmediately(self.snapshot)
    }

    private func persistImmediately(_ snapshot: AppSettings) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            self.userDefaults.set(data, forKey: Self.storageKey)
        } catch {
            print("[Keypress] ERROR: Failed to save settings: \(error)")
        }
    }

    private static func load(from userDefaults: UserDefaults) -> AppSettings {
        if let data = userDefaults.data(forKey: storageKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            return self.migrateStoredSettings(settings)
        }

        return Self.migrateLegacySettings(from: userDefaults)
    }

    private static func migrateStoredSettings(_ settings: AppSettings) -> AppSettings {
        guard settings.schemaVersion < 2 else { return settings }

        var migrated = settings
        let keyboardTheme = migrated.appearance.customTheme.keyboard
        let injectedBorderColors = [
            KeyColor(red: 1, green: 1, blue: 1, alpha: 0.12),
            KeyColor(red: 0, green: 0, blue: 0, alpha: 0.12),
        ]
        if keyboardTheme.keyCapStyle == .mechanical,
           keyboardTheme.borderWidth == 1,
           injectedBorderColors.contains(keyboardTheme.borderColor)
        {
            migrated.appearance.customTheme.keyboard.borderWidth = 0
        }
        migrated.schemaVersion = AppSettings.currentSchemaVersion
        return migrated
    }
}

// MARK: - Legacy Migration

extension KeypressConfig {
    private enum LegacyKeys {
        static let enabled = "settings.enabled"
        static let launchAtLogin = "settings.launchAtLogin"
        static let position = "settings.position"
        static let size = "settings.size"
        static let opacity = "settings.opacity"
        static let keyTimeout = "settings.keyTimeout"
        static let horizontalOffset = "settings.horizontalOffset"
        static let verticalOffset = "settings.verticalOffset"
        static let displayMode = "settings.displayMode"
        static let showModifiersOnly = "settings.showModifiersOnly"
        static let maxKeys = "settings.maxKeys"
        static let duplicateLetters = "settings.duplicateLetters"
        static let limitIncludesModifiers = "settings.limitIncludesModifiers"
        static let keyCapStyle = "settings.keyCapStyle"
        static let colorScheme = "settings.colorScheme"
        static let appearanceMode = "settings.appearanceMode"
        static let customColorScheme = "settings.customColorScheme"
        static let keyboardFrameStyle = "settings.keyboardFrameStyle"
        static let categoryStyleOverrides = "settings.categoryStyleOverrides"
        static let pressAnimationModifiers = "settings.pressAnimationModifiers"
        static let pressAnimationRegularKeys = "settings.pressAnimationRegularKeys"
        static let monitorSelection = "settings.monitorSelection"
    }

    private static func migrateLegacySettings(from defaults: UserDefaults) -> AppSettings {
        let displayMode = defaults.string(forKey: LegacyKeys.displayMode)
            .flatMap(DisplayMode.init(rawValue:)) ?? .single
        let contentMode: KeyboardContentMode = displayMode == .single
            && Self.legacyBool(
                defaults,
                key: LegacyKeys.showModifiersOnly,
                defaultValue: false)
            ? .shortcutsOnly
            : .allKeys
        let position = defaults.string(forKey: LegacyKeys.position)
            .flatMap(OverlayPosition.init(rawValue:)) ?? .bottomRight
        let horizontalOffset = Self.legacyDouble(
            defaults,
            key: LegacyKeys.horizontalOffset,
            defaultValue: 20)
        let verticalOffset = Self.legacyDouble(
            defaults,
            key: LegacyKeys.verticalOffset,
            defaultValue: 20)

        let legacyColorScheme = Self.decode(
            KeyColorScheme.self,
            from: defaults,
            key: LegacyKeys.colorScheme) ?? .dark
        let customColorScheme = Self.decode(
            KeyColorScheme.self,
            from: defaults,
            key: LegacyKeys.customColorScheme) ?? legacyColorScheme
        let categoryStyles = Self.decode(
            [KeyCategory: KeyCategoryStyle].self,
            from: defaults,
            key: LegacyKeys.categoryStyleOverrides) ?? [:]
        let keyCapStyle = defaults.string(forKey: LegacyKeys.keyCapStyle)
            .flatMap(KeyCapStyle.init(rawValue:)) ?? .mechanical
        let frameStyle = defaults.string(forKey: LegacyKeys.keyboardFrameStyle)
            .flatMap(KeyboardFrameStyle.init(rawValue:)) ?? .frame
        let migratedSelection = Self.migrateThemeSelection(
            defaults.string(forKey: LegacyKeys.appearanceMode))
        let preservesVisualOverrides = keyCapStyle != .mechanical
            || frameStyle != .frame
            || !categoryStyles.isEmpty
        let themeSelection: ThemeSelection = migratedSelection == .custom || preservesVisualOverrides
            ? .custom
            : migratedSelection
        let migratedColorScheme = migratedSelection == .custom
            ? customColorScheme
            : legacyColorScheme
        let systemIsDark = NSApp?.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) != .aqua
        let migratedBaseTheme = AppearanceSettings(themeSelection: migratedSelection)
            .resolvedTheme(isSystemDark: systemIsDark)

        let customTheme = ThemeDefinition(
            keyboard: KeyboardTheme(
                keyCapStyle: keyCapStyle,
                frameStyle: frameStyle,
                borderWidth: keyCapStyle == .mechanical ? 0 : 1,
                colorScheme: migratedColorScheme,
                categoryStyles: categoryStyles),
            pointer: migratedBaseTheme.pointer,
            hud: migratedBaseTheme.hud)

        return AppSettings(
            general: GeneralSettings(
                enabled: Self.legacyBool(defaults, key: LegacyKeys.enabled, defaultValue: true),
                launchAtLogin: Self.legacyBool(
                    defaults,
                    key: LegacyKeys.launchAtLogin,
                    defaultValue: false)),
            keyboard: KeyboardSettings(
                displayMode: displayMode,
                contentMode: contentMode,
                size: defaults.string(forKey: LegacyKeys.size)
                    .flatMap(OverlaySize.init(rawValue:)) ?? .medium,
                opacity: Self.legacyDouble(defaults, key: LegacyKeys.opacity, defaultValue: 1),
                timeout: Self.legacyDouble(defaults, key: LegacyKeys.keyTimeout, defaultValue: 1.5),
                maxItems: Self.legacyInt(defaults, key: LegacyKeys.maxKeys, defaultValue: 6),
                duplicateLetters: Self.legacyBool(
                    defaults,
                    key: LegacyKeys.duplicateLetters,
                    defaultValue: true),
                limitIncludesModifiers: Self.legacyBool(
                    defaults,
                    key: LegacyKeys.limitIncludesModifiers,
                    defaultValue: true),
                pressAnimationModifiers: Self.legacyBool(
                    defaults,
                    key: LegacyKeys.pressAnimationModifiers,
                    defaultValue: true),
                pressAnimationRegularKeys: Self.legacyBool(
                    defaults,
                    key: LegacyKeys.pressAnimationRegularKeys,
                    defaultValue: true)),
            appearance: AppearanceSettings(
                keyboardThemeSelection: themeSelection,
                pointerThemeSelection: .dark,
                customTheme: customTheme),
            displays: DisplaySettings(
                target: Self.migrateDisplayTarget(from: defaults),
                fallbackPlacement: .anchor(
                    position: position,
                    horizontalOffset: horizontalOffset,
                    verticalOffset: verticalOffset)))
    }

    private static func migrateThemeSelection(_ rawValue: String?) -> ThemeSelection {
        switch rawValue {
        case "dark": .dark
        case "light": .light
        case "monochrome": .mono
        case "custom": .custom
        default: .system
        }
    }

    private static func migrateDisplayTarget(from defaults: UserDefaults) -> DisplayTarget {
        guard let selection = decode(
            MonitorSelection.self,
            from: defaults,
            key: LegacyKeys.monitorSelection)
        else {
            return .followPointer
        }

        switch selection {
        case .auto:
            return .followPointer
        case let .fixed(index):
            guard let displayID = Self.displayUUID(at: index) else {
                return .followPointer
            }
            return .fixed(displayID)
        }
    }

    private static func displayUUID(at index: Int) -> UUID? {
        guard NSScreen.screens.indices.contains(index),
              let screenNumber = NSScreen.screens[index]
                  .deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let displayUUID = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(screenNumber.uint32Value))
        else {
            return nil
        }

        return UUID(
            uuidString: CFUUIDCreateString(nil, displayUUID.takeRetainedValue()) as String)
    }

    private static func legacyBool(
        _ defaults: UserDefaults,
        key: String,
        defaultValue: Bool) -> Bool
    {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }

    private static func legacyDouble(
        _ defaults: UserDefaults,
        key: String,
        defaultValue: Double) -> Double
    {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.double(forKey: key)
    }

    private static func legacyInt(
        _ defaults: UserDefaults,
        key: String,
        defaultValue: Int) -> Int
    {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.integer(forKey: key)
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from defaults: UserDefaults,
        key: String) -> Value?
    {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Compatibility Accessors

extension KeypressConfig {
    public var enabled: Bool {
        get { self.general.enabled }
        set { self.general.enabled = newValue }
    }

    public var launchAtLogin: Bool {
        get { self.general.launchAtLogin }
        set { self.general.launchAtLogin = newValue }
    }

    public var position: OverlayPosition {
        get {
            switch self.displays.fallbackPlacement {
            case let .anchor(position, _, _): position
            case let .custom(_, fallbackAnchor): fallbackAnchor
            }
        }
        set {
            self.displays.fallbackPlacement = .anchor(
                position: newValue,
                horizontalOffset: Double(self.horizontalOffset),
                verticalOffset: Double(self.verticalOffset))
        }
    }

    public var horizontalOffset: CGFloat {
        get {
            switch self.displays.fallbackPlacement {
            case let .anchor(_, horizontalOffset, _): CGFloat(horizontalOffset)
            case .custom: 20
            }
        }
        set {
            self.displays.fallbackPlacement = .anchor(
                position: self.position,
                horizontalOffset: Double(max(0, min(500, newValue))),
                verticalOffset: Double(self.verticalOffset))
        }
    }

    public var verticalOffset: CGFloat {
        get {
            switch self.displays.fallbackPlacement {
            case let .anchor(_, _, verticalOffset): CGFloat(verticalOffset)
            case .custom: 20
            }
        }
        set {
            self.displays.fallbackPlacement = .anchor(
                position: self.position,
                horizontalOffset: Double(self.horizontalOffset),
                verticalOffset: Double(max(0, min(300, newValue))))
        }
    }

    public var size: OverlaySize {
        get { self.keyboard.size }
        set { self.keyboard.size = newValue }
    }

    public var opacity: Double {
        get { self.keyboard.opacity }
        set { self.keyboard.opacity = newValue }
    }

    public var keyTimeout: Double {
        get { self.keyboard.timeout }
        set { self.keyboard.timeout = newValue }
    }

    public var displayMode: DisplayMode {
        get { self.keyboard.displayMode }
        set { self.keyboard.displayMode = newValue }
    }

    public var showModifiersOnly: Bool {
        get { self.keyboard.contentMode == .shortcutsOnly }
        set { self.keyboard.contentMode = newValue ? .shortcutsOnly : .allKeys }
    }

    public var maxKeys: Int {
        get { self.keyboard.maxItems }
        set { self.keyboard.maxItems = newValue }
    }

    public var duplicateLetters: Bool {
        get { self.keyboard.duplicateLetters }
        set { self.keyboard.duplicateLetters = newValue }
    }

    public var limitIncludesModifiers: Bool {
        get { self.keyboard.limitIncludesModifiers }
        set { self.keyboard.limitIncludesModifiers = newValue }
    }

    public var pressAnimationModifiers: Bool {
        get { self.keyboard.pressAnimationModifiers }
        set { self.keyboard.pressAnimationModifiers = newValue }
    }

    public var pressAnimationRegularKeys: Bool {
        get { self.keyboard.pressAnimationRegularKeys }
        set { self.keyboard.pressAnimationRegularKeys = newValue }
    }

    public var appearanceMode: AppearanceMode {
        get {
            switch self.appearance.keyboardThemeSelection {
            case .system: .auto
            case .dark, .classic, .modern, .gaming, .neon: .dark
            case .light: .light
            case .mono, .minimal: .monochrome
            case .custom: .custom
            }
        }
        set {
            self.appearance.keyboardThemeSelection = switch newValue {
            case .auto: .system
            case .dark: .dark
            case .monochrome: .mono
            case .light: .light
            case .custom: .custom
            }
        }
    }

    public var keyCapStyle: KeyCapStyle {
        get { self.effectiveThemeForCurrentSystem().keyboard.keyCapStyle }
        set {
            self.beginCustomizingKeyboardTheme(isSystemDark: self.systemIsDark)
            self.appearance.customTheme.keyboard.keyCapStyle = newValue
        }
    }

    public var keyboardFrameStyle: KeyboardFrameStyle {
        get { self.effectiveThemeForCurrentSystem().keyboard.frameStyle }
        set {
            self.beginCustomizingKeyboardTheme(isSystemDark: self.systemIsDark)
            self.appearance.customTheme.keyboard.frameStyle = newValue
        }
    }

    public var colorScheme: KeyColorScheme {
        get { self.effectiveThemeForCurrentSystem().keyboard.colorScheme }
        set {
            self.beginCustomizingKeyboardTheme(isSystemDark: self.systemIsDark)
            self.appearance.customTheme.keyboard.colorScheme = newValue
        }
    }

    public var customColorScheme: KeyColorScheme {
        get { self.appearance.customTheme.keyboard.colorScheme }
        set { self.appearance.customTheme.keyboard.colorScheme = newValue }
    }

    public var categoryStyleOverrides: [KeyCategory: KeyCategoryStyle] {
        get { self.appearance.customTheme.keyboard.categoryStyles }
        set { self.appearance.customTheme.keyboard.categoryStyles = newValue }
    }

    public var monitorSelection: MonitorSelection {
        get {
            switch self.displays.target {
            case .followPointer:
                .auto
            case let .fixed(displayID):
                Self.displayIndex(for: displayID).map(MonitorSelection.fixed(index:)) ?? .auto
            case let .selected(displayIDs):
                displayIDs.first
                    .flatMap(Self.displayIndex(for:))
                    .map(MonitorSelection.fixed(index:)) ?? .auto
            }
        }
        set {
            switch newValue {
            case .auto:
                self.displays.target = .followPointer
            case let .fixed(index):
                self.displays.target = Self.displayUUID(at: index).map(DisplayTarget.fixed) ?? .followPointer
            }
        }
    }

    public func effectiveStyle(for category: KeyCategory) -> KeyCategoryStyle {
        let theme = self.effectiveThemeForCurrentSystem()
        if let style = theme.keyboard.categoryStyles[category] {
            return style
        }
        return KeyCategoryStyle(
            color: theme.keyboard.colorScheme.color(for: category),
            depth: 1,
            cornerRadius: 0.5,
            shadowIntensity: 1,
            style: theme.keyboard.keyCapStyle)
    }

    public func hasStyleOverride(for category: KeyCategory) -> Bool {
        self.appearance.customTheme.keyboard.categoryStyles[category] != nil
    }

    public func setStyleOverride(_ style: KeyCategoryStyle?, for category: KeyCategory) {
        self.beginCustomizingKeyboardTheme(isSystemDark: self.systemIsDark)
        if let style {
            self.appearance.customTheme.keyboard.categoryStyles[category] = style
        } else {
            self.appearance.customTheme.keyboard.categoryStyles.removeValue(forKey: category)
        }
    }

    private var systemIsDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func effectiveThemeForCurrentSystem() -> ThemeDefinition {
        self.effectiveTheme(isSystemDark: self.systemIsDark)
    }

    private static func displayIndex(for displayID: UUID) -> Int? {
        NSScreen.screens.firstIndex { screen in
            guard let screenNumber = screen
                .deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(screenNumber.uint32Value))
            else {
                return false
            }

            return UUID(
                uuidString: CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String) == displayID
        }
    }
}
