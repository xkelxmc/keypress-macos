import Foundation

// MARK: - General

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system
    case english
    case german
    case spanish
    case french
    case russian

    public var localeIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .german: "de"
        case .spanish: "es"
        case .french: "fr"
        case .russian: "ru"
        }
    }
}

public struct GeneralSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var launchAtLogin: Bool
    public var language: AppLanguage

    public init(
        enabled: Bool = true,
        launchAtLogin: Bool = false,
        language: AppLanguage = .system)
    {
        self.enabled = enabled
        self.launchAtLogin = launchAtLogin
        self.language = language
    }
}

// MARK: - Keyboard

public enum KeyboardContentMode: String, CaseIterable, Codable, Sendable {
    case allKeys
    case shortcutsOnly
}

public enum HistoryLayout: String, CaseIterable, Codable, Sendable {
    case horizontal
    case stacked
}

public enum KeyboardPresentation: String, CaseIterable, Codable, Sendable {
    case latest
    case horizontalHistory
    case stackedHistory
}

public struct KeyboardFilterSettings: Codable, Sendable, Equatable {
    public var showStandaloneModifiers: Bool
    public var showFunctionKeys: Bool
    public var showSpecialKeys: Bool

    public init(
        showStandaloneModifiers: Bool = true,
        showFunctionKeys: Bool = true,
        showSpecialKeys: Bool = true)
    {
        self.showStandaloneModifiers = showStandaloneModifiers
        self.showFunctionKeys = showFunctionKeys
        self.showSpecialKeys = showSpecialKeys
    }

    public func includes(_ symbol: KeySymbol) -> Bool {
        let category = KeyCodeMapper.category(for: symbol)
        if category == .function {
            return self.showFunctionKeys
        }
        if symbol.isSpecial {
            return self.showSpecialKeys
        }
        return true
    }
}

// MARK: - Input Keys

/// The four keys whose width and tint the input-key settings govern.
public enum InputKey: String, CaseIterable, Codable, Sendable {
    case space
    case enter
    case backspace
    case tab

    /// The setting a key symbol obeys, or nil when the symbol is governed by none of them.
    ///
    /// Forward Delete has no row of its own: it is the same key in the other direction, so
    /// it follows whatever Backspace is set to rather than being left behind at full width.
    public static func from(symbolID: String) -> InputKey? {
        switch symbolID {
        case "space": .space
        case "return", "enter": .enter
        case "delete", "forward-delete": .backspace
        case "tab": .tab
        default: nil
        }
    }
}

public enum InputKeyWidthMode: String, CaseIterable, Codable, Sendable {
    /// Wide wherever the key acts as a control, standard once it rides into ribbon history.
    case wide

    /// Standard width everywhere, in every mode.
    case narrow

    /// Each key picks one of the two behaviours above.
    case custom
}

/// Per-key width choice for `InputKeyWidthMode.custom`. `true` means the key behaves like
/// `.wide`, `false` like `.narrow`.
public struct InputKeyWidths: Codable, Sendable, Equatable {
    public var space: Bool
    public var enter: Bool
    public var backspace: Bool
    public var tab: Bool

    public init(
        space: Bool = true,
        enter: Bool = true,
        backspace: Bool = true,
        tab: Bool = true)
    {
        self.space = space
        self.enter = enter
        self.backspace = backspace
        self.tab = tab
    }

    public subscript(key: InputKey) -> Bool {
        get {
            switch key {
            case .space: self.space
            case .enter: self.enter
            case .backspace: self.backspace
            case .tab: self.tab
            }
        }
        set {
            switch key {
            case .space: self.space = newValue
            case .enter: self.enter = newValue
            case .backspace: self.backspace = newValue
            case .tab: self.tab = newValue
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case space
        case enter
        case backspace
        case tab
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            space: (try? container.decode(Bool.self, forKey: .space)) ?? true,
            enter: (try? container.decode(Bool.self, forKey: .enter)) ?? true,
            backspace: (try? container.decode(Bool.self, forKey: .backspace)) ?? true,
            tab: (try? container.decode(Bool.self, forKey: .tab)) ?? true)
    }
}

public struct InputKeySettings: Codable, Sendable, Equatable {
    public var widthMode: InputKeyWidthMode
    public var widths: InputKeyWidths

    /// Gives Space, Enter, Backspace and Tab a tone of their own, subtly apart from the
    /// letter keys.
    public var highlight: Bool

    public init(
        widthMode: InputKeyWidthMode = .wide,
        widths: InputKeyWidths = InputKeyWidths(),
        highlight: Bool = true)
    {
        self.widthMode = widthMode
        self.widths = widths
        self.highlight = highlight
    }

    /// Whether the key renders wide.
    ///
    /// `isControlPosition` is false only for a horizontal-ribbon entry that is no longer the
    /// latest press; everywhere else these keys act as controls and may take the wide look.
    public func rendersWide(_ key: InputKey, isControlPosition: Bool) -> Bool {
        guard isControlPosition else { return false }
        return switch self.widthMode {
        case .wide: true
        case .narrow: false
        case .custom: self.widths[key]
        }
    }

    private enum CodingKeys: String, CodingKey {
        case widthMode
        case widths
        case highlight
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            widthMode: (try? container.decode(InputKeyWidthMode.self, forKey: .widthMode)) ?? .wide,
            widths: (try? container.decode(InputKeyWidths.self, forKey: .widths)) ?? InputKeyWidths(),
            highlight: (try? container.decode(Bool.self, forKey: .highlight)) ?? true)
    }
}

/// Which side of the horizontal-history widget the command zone gravitates to.
public enum CommandZoneSide: String, CaseIterable, Codable, Sendable {
    /// Follows the display placement's own horizontal anchor.
    case auto
    case left
    case right
}

public struct KeyboardSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var displayMode: DisplayMode
    public var contentMode: KeyboardContentMode
    public var filters: KeyboardFilterSettings
    public var historyLayout: HistoryLayout
    public var size: OverlaySize
    public var opacity: Double
    public var timeout: TimeInterval
    public var maxItems: Int
    public var duplicateLetters: Bool
    public var limitIncludesModifiers: Bool
    public var pressAnimationModifiers: Bool
    public var pressAnimationRegularKeys: Bool
    public var inputKeys: InputKeySettings
    public var commandZoneSide: CommandZoneSide

    public init(
        enabled: Bool = true,
        displayMode: DisplayMode = .single,
        contentMode: KeyboardContentMode = .allKeys,
        filters: KeyboardFilterSettings = KeyboardFilterSettings(),
        historyLayout: HistoryLayout = .horizontal,
        size: OverlaySize = .medium,
        opacity: Double = 1,
        timeout: TimeInterval = 1.5,
        maxItems: Int = 6,
        duplicateLetters: Bool = true,
        limitIncludesModifiers: Bool = true,
        pressAnimationModifiers: Bool = true,
        pressAnimationRegularKeys: Bool = true,
        inputKeys: InputKeySettings = InputKeySettings(),
        commandZoneSide: CommandZoneSide = .auto)
    {
        self.enabled = enabled
        self.displayMode = displayMode
        self.contentMode = contentMode
        self.filters = filters
        self.historyLayout = historyLayout
        self.size = size
        self.opacity = opacity.clamped(to: 0...1)
        self.timeout = timeout.clamped(to: 0.5...5)
        self.maxItems = max(3, min(12, maxItems))
        self.duplicateLetters = duplicateLetters
        self.limitIncludesModifiers = limitIncludesModifiers
        self.pressAnimationModifiers = pressAnimationModifiers
        self.pressAnimationRegularKeys = pressAnimationRegularKeys
        self.inputKeys = inputKeys
        self.commandZoneSide = commandZoneSide
    }

    func normalized() -> KeyboardSettings {
        KeyboardSettings(
            enabled: self.enabled,
            displayMode: self.displayMode,
            contentMode: self.contentMode,
            filters: self.filters,
            historyLayout: self.historyLayout,
            size: self.size,
            opacity: self.opacity,
            timeout: self.timeout,
            maxItems: self.maxItems,
            duplicateLetters: self.duplicateLetters,
            limitIncludesModifiers: self.limitIncludesModifiers,
            pressAnimationModifiers: self.pressAnimationModifiers,
            pressAnimationRegularKeys: self.pressAnimationRegularKeys,
            inputKeys: self.inputKeys,
            commandZoneSide: self.commandZoneSide)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case displayMode
        case contentMode
        case filters
        case historyLayout
        case size
        case opacity
        case timeout
        case maxItems
        case duplicateLetters
        case limitIncludesModifiers
        case pressAnimationModifiers
        case pressAnimationRegularKeys
        case inputKeys
        case commandZoneSide
    }

    /// Decodes field by field so a settings file written by an older build — which has no
    /// entry for fields added later — keeps every value it does carry instead of falling
    /// back to a wholesale default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = KeyboardSettings()
        self.init(
            enabled: (try? container.decode(Bool.self, forKey: .enabled)) ?? defaults.enabled,
            displayMode: (try? container.decode(DisplayMode.self, forKey: .displayMode))
                ?? defaults.displayMode,
            contentMode: (try? container.decode(KeyboardContentMode.self, forKey: .contentMode))
                ?? defaults.contentMode,
            filters: (try? container.decode(KeyboardFilterSettings.self, forKey: .filters))
                ?? defaults.filters,
            historyLayout: (try? container.decode(HistoryLayout.self, forKey: .historyLayout))
                ?? defaults.historyLayout,
            size: (try? container.decode(OverlaySize.self, forKey: .size)) ?? defaults.size,
            opacity: (try? container.decode(Double.self, forKey: .opacity)) ?? defaults.opacity,
            timeout: (try? container.decode(TimeInterval.self, forKey: .timeout)) ?? defaults.timeout,
            maxItems: (try? container.decode(Int.self, forKey: .maxItems)) ?? defaults.maxItems,
            duplicateLetters: (try? container.decode(Bool.self, forKey: .duplicateLetters))
                ?? defaults.duplicateLetters,
            limitIncludesModifiers: (try? container.decode(Bool.self, forKey: .limitIncludesModifiers))
                ?? defaults.limitIncludesModifiers,
            pressAnimationModifiers: (try? container.decode(Bool.self, forKey: .pressAnimationModifiers))
                ?? defaults.pressAnimationModifiers,
            pressAnimationRegularKeys: (try? container.decode(Bool.self, forKey: .pressAnimationRegularKeys))
                ?? defaults.pressAnimationRegularKeys,
            inputKeys: (try? container.decode(InputKeySettings.self, forKey: .inputKeys))
                ?? defaults.inputKeys,
            commandZoneSide: (try? container.decode(CommandZoneSide.self, forKey: .commandZoneSide))
                ?? defaults.commandZoneSide)
    }

    public var presentation: KeyboardPresentation {
        get {
            switch (self.displayMode, self.historyLayout) {
            case (.single, _):
                .latest
            case (.history, .horizontal):
                .horizontalHistory
            case (.history, .stacked):
                .stackedHistory
            }
        }
        set {
            switch newValue {
            case .latest:
                self.displayMode = .single
                self.historyLayout = .horizontal
            case .horizontalHistory:
                self.displayMode = .history
                self.historyLayout = .horizontal
            case .stackedHistory:
                self.displayMode = .history
                self.historyLayout = .stacked
            }
        }
    }
}

// MARK: - Pointer

public enum PointerVisibility: String, CaseIterable, Codable, Sendable {
    case onActivity
    case actionsOnly
    case always
}

public enum PointerShape: String, CaseIterable, Codable, Sendable {
    case circle
    case squircle
    case square
    case diamond
}

public enum PointerLineStyle: String, Codable, Sendable, Equatable {
    case aura
    case solid
    case double
    case segmented
    case neonDepth
}

public enum PointerDecoration: String, Codable, Sendable, Equatable {
    case none
    case centerDot
    case innerRing
    case crosshair
    case cornerBrackets
    case orbit
}

public enum PointerReactionStyle: String, Codable, Sendable, Equatable {
    case elastic
    case pulse
    case stepped
    case mechanical
    case fluid
    case subtle
    case tactical
    case electric
}

public struct PointerSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var visibility: PointerVisibility
    public var idleDelay: TimeInterval
    public var size: Double
    public var opacity: Double
    public var motionIntensity: Double
    public var showLeftClick: Bool
    public var showRightClick: Bool
    public var showMiddleClick: Bool
    public var showMovement: Bool
    public var showDrag: Bool
    public var showScroll: Bool

    public init(
        enabled: Bool = true,
        visibility: PointerVisibility = .onActivity,
        idleDelay: TimeInterval = 1.2,
        size: Double = 72,
        opacity: Double = 1,
        motionIntensity: Double = 0.55,
        showLeftClick: Bool = true,
        showRightClick: Bool = true,
        showMiddleClick: Bool = true,
        showMovement: Bool = true,
        showDrag: Bool = true,
        showScroll: Bool = true)
    {
        self.enabled = enabled
        self.visibility = visibility
        self.idleDelay = idleDelay.clamped(to: 0.1...10)
        self.size = size.clamped(to: 24...160)
        self.opacity = opacity.clamped(to: 0...1)
        self.motionIntensity = motionIntensity.clamped(to: 0...1)
        self.showLeftClick = showLeftClick
        self.showRightClick = showRightClick
        self.showMiddleClick = showMiddleClick
        self.showMovement = showMovement
        self.showDrag = showDrag
        self.showScroll = showScroll
    }

    func normalized() -> PointerSettings {
        PointerSettings(
            enabled: self.enabled,
            visibility: self.visibility,
            idleDelay: self.idleDelay,
            size: self.size,
            opacity: self.opacity,
            motionIntensity: self.motionIntensity,
            showLeftClick: self.showLeftClick,
            showRightClick: self.showRightClick,
            showMiddleClick: self.showMiddleClick,
            showMovement: self.showMovement,
            showDrag: self.showDrag,
            showScroll: self.showScroll)
    }
}

// MARK: - Pet

public enum PetVisibility: String, CaseIterable, Codable, Sendable {
    case always
    case typingOnly
}

public enum PetActivityMode: String, CaseIterable, Codable, Sendable {
    case cycle
    case random
}

public struct PetPlacement: Codable, Sendable, Equatable {
    public var displayID: UUID
    public var center: NormalizedPoint

    public init(displayID: UUID, center: NormalizedPoint) {
        self.displayID = displayID
        self.center = center
    }
}

public struct PetSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var visibility: PetVisibility
    public var activityMode: PetActivityMode
    public var size: Double
    public var sleep: Bool
    public var watchCursor: Bool
    public var huntCursor: Bool
    public var stretch: Bool
    public var groom: Bool
    public var playTail: Bool
    public var petReaction: Bool
    public var placement: PetPlacement?

    public init(
        enabled: Bool = true,
        visibility: PetVisibility = .always,
        activityMode: PetActivityMode = .cycle,
        size: Double = 128,
        sleep: Bool = true,
        watchCursor: Bool = true,
        huntCursor: Bool = true,
        stretch: Bool = true,
        groom: Bool = true,
        playTail: Bool = true,
        petReaction: Bool = true,
        placement: PetPlacement? = nil)
    {
        self.enabled = enabled
        self.visibility = visibility
        self.activityMode = activityMode
        self.size = size.clamped(to: 84...180)
        self.sleep = sleep
        self.watchCursor = watchCursor
        self.huntCursor = huntCursor
        self.stretch = stretch
        self.groom = groom
        self.playTail = playTail
        self.petReaction = petReaction
        self.placement = placement
    }

    func normalized() -> PetSettings {
        let normalizedPlacement = self.placement.map {
            PetPlacement(
                displayID: $0.displayID,
                center: NormalizedPoint(x: $0.center.x, y: $0.center.y))
        }
        return PetSettings(
            enabled: self.enabled,
            visibility: self.visibility,
            activityMode: self.activityMode,
            size: self.size,
            sleep: self.sleep,
            watchCursor: self.watchCursor,
            huntCursor: self.huntCursor,
            stretch: self.stretch,
            groom: self.groom,
            playTail: self.playTail,
            petReaction: self.petReaction,
            placement: normalizedPlacement)
    }
}

// MARK: - Appearance

public enum ThemeSelection: String, CaseIterable, Codable, Sendable {
    case system
    case dark
    case light
    case mono
    case classic
    case modern
    case minimal
    case gaming
    case neon
    case custom
}

public enum ThemeFontWeight: String, CaseIterable, Codable, Sendable {
    case regular
    case medium
    case semibold
    case bold
}

public enum KeyboardMaterial: String, Codable, Sendable, Equatable {
    case graphite
    case aluminum
    case monochrome
    case classic
    case glass
    case minimal
    case gaming
    case neon
}

public enum KeyboardPressEffect: String, Codable, Sendable, Equatable {
    case travel
    case deepTravel
    case compress
    case scale
    case snap
    case glow
}

public struct KeyboardTheme: Codable, Sendable, Equatable {
    public var keyCapStyle: KeyCapStyle
    public var frameStyle: KeyboardFrameStyle
    public var material: KeyboardMaterial
    public var pressEffect: KeyboardPressEffect
    public var fontFamily: String?
    public var fontWeight: ThemeFontWeight
    public var fontScale: Double
    public var textColor: KeyColor
    public var keySpacing: Double
    public var borderColor: KeyColor
    public var borderWidth: Double
    public var colorScheme: KeyColorScheme
    public var categoryStyles: [KeyCategory: KeyCategoryStyle]

    public init(
        keyCapStyle: KeyCapStyle = .mechanical,
        frameStyle: KeyboardFrameStyle = .frame,
        material: KeyboardMaterial = .graphite,
        pressEffect: KeyboardPressEffect? = nil,
        fontFamily: String? = nil,
        fontWeight: ThemeFontWeight = .medium,
        fontScale: Double = 1,
        textColor: KeyColor = .white,
        keySpacing: Double = 6,
        borderColor: KeyColor = KeyColor(red: 1, green: 1, blue: 1, alpha: 0.12),
        borderWidth: Double = 0,
        colorScheme: KeyColorScheme = .dark,
        categoryStyles: [KeyCategory: KeyCategoryStyle] = [:])
    {
        self.keyCapStyle = keyCapStyle
        self.frameStyle = frameStyle
        self.material = material
        self.pressEffect = pressEffect ?? (keyCapStyle == .minimal ? .scale : .travel)
        self.fontFamily = fontFamily
        self.fontWeight = fontWeight
        self.fontScale = fontScale.clamped(to: 0.5...2)
        self.textColor = textColor
        self.keySpacing = keySpacing.clamped(to: 0...24)
        self.borderColor = borderColor
        self.borderWidth = borderWidth.clamped(to: 0...8)
        self.colorScheme = colorScheme
        self.categoryStyles = categoryStyles
    }

    private enum CodingKeys: String, CodingKey {
        case keyCapStyle
        case frameStyle
        case material
        case pressEffect
        case fontFamily
        case fontWeight
        case fontScale
        case textColor
        case keySpacing
        case borderColor
        case borderWidth
        case colorScheme
        case categoryStyles
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let keyCapStyle = (try? container.decode(KeyCapStyle.self, forKey: .keyCapStyle)) ?? .mechanical

        self.init(
            keyCapStyle: keyCapStyle,
            frameStyle: (try? container.decode(KeyboardFrameStyle.self, forKey: .frameStyle)) ?? .frame,
            material: (try? container.decode(KeyboardMaterial.self, forKey: .material)) ?? .graphite,
            pressEffect: try? container.decode(KeyboardPressEffect.self, forKey: .pressEffect),
            fontFamily: try? container.decodeIfPresent(String.self, forKey: .fontFamily),
            fontWeight: (try? container.decode(ThemeFontWeight.self, forKey: .fontWeight)) ?? .medium,
            fontScale: (try? container.decode(Double.self, forKey: .fontScale)) ?? 1,
            textColor: (try? container.decode(KeyColor.self, forKey: .textColor)) ?? .white,
            keySpacing: (try? container.decode(Double.self, forKey: .keySpacing)) ?? 6,
            borderColor: (try? container.decode(KeyColor.self, forKey: .borderColor))
                ?? KeyColor(red: 1, green: 1, blue: 1, alpha: 0.12),
            borderWidth: (try? container.decode(Double.self, forKey: .borderWidth)) ?? 0,
            colorScheme: (try? container.decode(KeyColorScheme.self, forKey: .colorScheme)) ?? .dark,
            categoryStyles: (try? container.decode(
                [KeyCategory: KeyCategoryStyle].self,
                forKey: .categoryStyles)) ?? [:])
    }
}

public struct PointerTheme: Codable, Sendable, Equatable {
    public var shape: PointerShape
    public var lineStyle: PointerLineStyle
    public var decoration: PointerDecoration
    public var reactionStyle: PointerReactionStyle
    public var primaryColor: KeyColor
    public var secondaryColor: KeyColor
    public var coreColor: KeyColor
    public var strokeWidth: Double
    public var glowRadius: Double
    public var glowIntensity: Double

    public init(
        shape: PointerShape = .squircle,
        lineStyle: PointerLineStyle = .aura,
        decoration: PointerDecoration = .none,
        reactionStyle: PointerReactionStyle = .elastic,
        primaryColor: KeyColor = .pointerCyan,
        secondaryColor: KeyColor = .pointerPurple,
        coreColor: KeyColor = .white,
        strokeWidth: Double = 4,
        glowRadius: Double = 22,
        glowIntensity: Double = 0.85)
    {
        self.shape = shape
        self.lineStyle = lineStyle
        self.decoration = decoration
        self.reactionStyle = reactionStyle
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.coreColor = coreColor
        self.strokeWidth = strokeWidth.clamped(to: 1...16)
        self.glowRadius = glowRadius.clamped(to: 0...40)
        self.glowIntensity = glowIntensity.clamped(to: 0...1)
    }

    private enum CodingKeys: String, CodingKey {
        case shape
        case lineStyle
        case decoration
        case reactionStyle
        case primaryColor
        case secondaryColor
        case coreColor
        case strokeWidth
        case glowRadius
        case glowIntensity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            shape: (try? container.decode(PointerShape.self, forKey: .shape)) ?? .squircle,
            lineStyle: (try? container.decode(PointerLineStyle.self, forKey: .lineStyle)) ?? .aura,
            decoration: (try? container.decode(PointerDecoration.self, forKey: .decoration)) ?? .none,
            reactionStyle: (try? container.decode(PointerReactionStyle.self, forKey: .reactionStyle)) ?? .elastic,
            primaryColor: (try? container.decode(KeyColor.self, forKey: .primaryColor)) ?? .pointerCyan,
            secondaryColor: (try? container.decode(KeyColor.self, forKey: .secondaryColor)) ?? .pointerPurple,
            coreColor: (try? container.decode(KeyColor.self, forKey: .coreColor)) ?? .white,
            strokeWidth: (try? container.decode(Double.self, forKey: .strokeWidth)) ?? 4,
            glowRadius: (try? container.decode(Double.self, forKey: .glowRadius)) ?? 22,
            glowIntensity: (try? container.decode(Double.self, forKey: .glowIntensity)) ?? 0.85)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.shape, forKey: .shape)
        try container.encode(self.lineStyle, forKey: .lineStyle)
        try container.encode(self.decoration, forKey: .decoration)
        try container.encode(self.reactionStyle, forKey: .reactionStyle)
        try container.encode(self.primaryColor, forKey: .primaryColor)
        try container.encode(self.secondaryColor, forKey: .secondaryColor)
        try container.encode(self.coreColor, forKey: .coreColor)
        try container.encode(self.strokeWidth, forKey: .strokeWidth)
        try container.encode(self.glowRadius, forKey: .glowRadius)
        try container.encode(self.glowIntensity, forKey: .glowIntensity)
    }
}

public struct HUDPalette: Codable, Sendable, Equatable {
    public var backgroundColor: KeyColor
    public var textColor: KeyColor
    public var accentColor: KeyColor

    public init(
        backgroundColor: KeyColor = KeyColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 0.92),
        textColor: KeyColor = .white,
        accentColor: KeyColor = .commandGreen)
    {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.accentColor = accentColor
    }
}

public struct ThemeDefinition: Codable, Sendable, Equatable {
    public var keyboard: KeyboardTheme
    public var pointer: PointerTheme
    public var hud: HUDPalette

    public init(
        keyboard: KeyboardTheme = KeyboardTheme(),
        pointer: PointerTheme = PointerTheme(),
        hud: HUDPalette = HUDPalette())
    {
        self.keyboard = keyboard
        self.pointer = pointer
        self.hud = hud
    }

    public static let defaultTheme = ThemeDefinition()
    public static let dark = ThemeDefinition()
    public static let systemLight = ThemeDefinition(
        keyboard: KeyboardTheme(
            material: .graphite,
            pressEffect: .travel,
            textColor: KeyColor(red: 0.08, green: 0.08, blue: 0.1),
            borderColor: KeyColor(red: 0, green: 0, blue: 0, alpha: 0.12),
            colorScheme: .light),
        pointer: PointerTheme(
            primaryColor: KeyColor(red: 0.1, green: 0.55, blue: 0.95),
            secondaryColor: KeyColor(red: 0.65, green: 0.25, blue: 0.85)),
        hud: HUDPalette(
            backgroundColor: KeyColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 0.94),
            textColor: KeyColor(red: 0.08, green: 0.08, blue: 0.1),
            accentColor: .commandGreen))
    public static let light = ThemeDefinition(
        keyboard: KeyboardTheme(
            material: .aluminum,
            textColor: KeyColor(red: 0.08, green: 0.08, blue: 0.1),
            borderColor: KeyColor(red: 0, green: 0, blue: 0, alpha: 0.12),
            colorScheme: .light),
        pointer: PointerTheme(
            shape: .square,
            lineStyle: .double,
            decoration: .centerDot,
            reactionStyle: .pulse,
            primaryColor: KeyColor(red: 0.08, green: 0.42, blue: 0.92),
            secondaryColor: KeyColor(red: 0.08, green: 0.16, blue: 0.30),
            coreColor: .white,
            strokeWidth: 3,
            glowRadius: 10,
            glowIntensity: 0.4),
        hud: HUDPalette(
            backgroundColor: KeyColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 0.94),
            textColor: KeyColor(red: 0.08, green: 0.08, blue: 0.1),
            accentColor: .commandGreen))
    public static let mono = ThemeDefinition(
        keyboard: KeyboardTheme(
            keyCapStyle: .flat,
            frameStyle: .none,
            material: .monochrome,
            pressEffect: .compress,
            fontFamily: "dev.keypress.font.monospaced",
            fontWeight: .regular,
            keySpacing: 5,
            colorScheme: .monochromeDark),
        pointer: PointerTheme(
            shape: .circle,
            lineStyle: .segmented,
            decoration: .crosshair,
            reactionStyle: .stepped,
            primaryColor: KeyColor(red: 0.92, green: 0.92, blue: 0.94),
            secondaryColor: KeyColor(red: 0.08, green: 0.08, blue: 0.1),
            coreColor: KeyColor(red: 0.94, green: 0.94, blue: 0.96),
            strokeWidth: 2,
            glowRadius: 1,
            glowIntensity: 0.08))
    public static let classic = ThemeDefinition(
        keyboard: KeyboardTheme(
            keyCapStyle: .mechanical,
            frameStyle: .frame,
            material: .classic,
            pressEffect: .deepTravel,
            fontWeight: .medium,
            textColor: KeyColor(red: 0.16, green: 0.11, blue: 0.07),
            keySpacing: 7,
            colorScheme: KeyColorScheme(
                letter: KeyColor(red: 0.82, green: 0.72, blue: 0.57),
                command: KeyColor(red: 0.72, green: 0.49, blue: 0.24),
                shift: KeyColor(red: 0.67, green: 0.31, blue: 0.21),
                option: KeyColor(red: 0.64, green: 0.54, blue: 0.39),
                control: KeyColor(red: 0.77, green: 0.56, blue: 0.28),
                capsLock: KeyColor(red: 0.60, green: 0.54, blue: 0.45),
                escape: KeyColor(red: 0.70, green: 0.29, blue: 0.20),
                function: KeyColor(red: 0.68, green: 0.57, blue: 0.43),
                navigation: KeyColor(red: 0.82, green: 0.72, blue: 0.57),
                editing: KeyColor(red: 0.82, green: 0.72, blue: 0.57))),
        pointer: PointerTheme(
            shape: .circle,
            lineStyle: .double,
            decoration: .innerRing,
            reactionStyle: .mechanical,
            primaryColor: KeyColor(red: 1, green: 0.62, blue: 0.12),
            secondaryColor: KeyColor(red: 0.48, green: 0.20, blue: 0.06),
            coreColor: KeyColor(red: 1, green: 0.88, blue: 0.62),
            strokeWidth: 4,
            glowRadius: 12,
            glowIntensity: 0.58))
    public static let modern = ThemeDefinition(
        keyboard: KeyboardTheme(
            keyCapStyle: .flat,
            frameStyle: .overlay,
            material: .glass,
            pressEffect: .compress,
            fontWeight: .semibold,
            keySpacing: 8,
            borderWidth: 1,
            colorScheme: KeyColorScheme(
                letter: KeyColor(red: 0.14, green: 0.18, blue: 0.25, alpha: 0.88),
                command: KeyColor(red: 0.10, green: 0.48, blue: 0.78, alpha: 0.9),
                shift: KeyColor(red: 0.58, green: 0.27, blue: 0.62, alpha: 0.9),
                option: KeyColor(red: 0.24, green: 0.38, blue: 0.76, alpha: 0.9),
                control: KeyColor(red: 0.16, green: 0.60, blue: 0.66, alpha: 0.9),
                capsLock: KeyColor(red: 0.23, green: 0.29, blue: 0.38, alpha: 0.9),
                escape: KeyColor(red: 0.76, green: 0.28, blue: 0.38, alpha: 0.9),
                function: KeyColor(red: 0.35, green: 0.29, blue: 0.68, alpha: 0.9),
                navigation: KeyColor(red: 0.14, green: 0.18, blue: 0.25, alpha: 0.88),
                editing: KeyColor(red: 0.14, green: 0.18, blue: 0.25, alpha: 0.88))),
        pointer: PointerTheme(
            shape: .squircle,
            lineStyle: .solid,
            decoration: .orbit,
            reactionStyle: .fluid,
            primaryColor: KeyColor(red: 0.12, green: 0.58, blue: 1),
            secondaryColor: KeyColor(red: 0.62, green: 0.34, blue: 1),
            coreColor: .white,
            strokeWidth: 3,
            glowRadius: 16,
            glowIntensity: 0.58))
    public static let minimal = ThemeDefinition(
        keyboard: KeyboardTheme(
            keyCapStyle: .minimal,
            frameStyle: .none,
            material: .minimal,
            pressEffect: .scale,
            fontWeight: .regular,
            keySpacing: 4,
            borderWidth: 0,
            colorScheme: .monochromeDark),
        pointer: PointerTheme(
            shape: .circle,
            lineStyle: .double,
            decoration: .none,
            reactionStyle: .subtle,
            primaryColor: KeyColor(red: 0.08, green: 0.09, blue: 0.11),
            secondaryColor: KeyColor(red: 0.96, green: 0.96, blue: 0.98),
            coreColor: KeyColor(red: 0.12, green: 0.13, blue: 0.15),
            strokeWidth: 1.5,
            glowRadius: 0,
            glowIntensity: 0))
    public static let gaming = ThemeDefinition(
        keyboard: KeyboardTheme(
            keyCapStyle: .mechanical,
            frameStyle: .frame,
            material: .gaming,
            pressEffect: .snap,
            fontWeight: .bold,
            keySpacing: 5,
            colorScheme: KeyColorScheme(
                letter: KeyColor(red: 0.055, green: 0.065, blue: 0.08),
                command: KeyColor(red: 0.32, green: 0.82, blue: 0.18),
                shift: KeyColor(red: 0.92, green: 0.18, blue: 0.54),
                option: KeyColor(red: 0.08, green: 0.66, blue: 0.92),
                control: KeyColor(red: 0.95, green: 0.47, blue: 0.10),
                capsLock: KeyColor(red: 0.17, green: 0.19, blue: 0.23),
                escape: KeyColor(red: 0.92, green: 0.16, blue: 0.22),
                function: KeyColor(red: 0.55, green: 0.22, blue: 0.92),
                navigation: KeyColor(red: 0.055, green: 0.065, blue: 0.08),
                editing: KeyColor(red: 0.055, green: 0.065, blue: 0.08))),
        pointer: PointerTheme(
            shape: .diamond,
            lineStyle: .segmented,
            decoration: .cornerBrackets,
            reactionStyle: .tactical,
            primaryColor: KeyColor(red: 0.48, green: 1, blue: 0.18),
            secondaryColor: KeyColor(red: 1, green: 0.16, blue: 0.62),
            coreColor: .white,
            strokeWidth: 3,
            glowRadius: 18,
            glowIntensity: 0.85),
        hud: HUDPalette(accentColor: KeyColor(red: 0.48, green: 1, blue: 0.18)))
    public static let neon = ThemeDefinition(
        keyboard: KeyboardTheme(
            keyCapStyle: .flat,
            frameStyle: .overlay,
            material: .neon,
            pressEffect: .glow,
            fontWeight: .semibold,
            keySpacing: 9,
            borderColor: .pointerCyan,
            borderWidth: 2,
            colorScheme: KeyColorScheme(
                letter: KeyColor(red: 0.035, green: 0.045, blue: 0.07, alpha: 0.94),
                command: KeyColor(red: 0.03, green: 0.28, blue: 0.36, alpha: 0.94),
                shift: KeyColor(red: 0.38, green: 0.05, blue: 0.32, alpha: 0.94),
                option: KeyColor(red: 0.18, green: 0.08, blue: 0.38, alpha: 0.94),
                control: KeyColor(red: 0.04, green: 0.30, blue: 0.26, alpha: 0.94),
                capsLock: KeyColor(red: 0.08, green: 0.09, blue: 0.14, alpha: 0.94),
                escape: KeyColor(red: 0.42, green: 0.04, blue: 0.18, alpha: 0.94),
                function: KeyColor(red: 0.24, green: 0.07, blue: 0.42, alpha: 0.94),
                navigation: KeyColor(red: 0.035, green: 0.045, blue: 0.07, alpha: 0.94),
                editing: KeyColor(red: 0.035, green: 0.045, blue: 0.07, alpha: 0.94))),
        pointer: PointerTheme(
            shape: .squircle,
            lineStyle: .neonDepth,
            decoration: .innerRing,
            reactionStyle: .electric,
            primaryColor: .pointerCyan,
            secondaryColor: .pointerPurple,
            coreColor: .white,
            strokeWidth: 3.5,
            glowRadius: 28,
            glowIntensity: 1),
        hud: HUDPalette(accentColor: .pointerCyan))
}

public struct AppearanceSettings: Codable, Sendable, Equatable {
    public var keyboardThemeSelection: ThemeSelection
    public var pointerThemeSelection: ThemeSelection
    public var customTheme: ThemeDefinition

    public init(customTheme: ThemeDefinition = .defaultTheme) {
        self.keyboardThemeSelection = .system
        self.pointerThemeSelection = .dark
        self.customTheme = customTheme
    }

    public init(
        themeSelection: ThemeSelection,
        customTheme: ThemeDefinition = .defaultTheme)
    {
        self.keyboardThemeSelection = themeSelection
        self.pointerThemeSelection = themeSelection
        self.customTheme = customTheme
    }

    public init(
        keyboardThemeSelection: ThemeSelection,
        pointerThemeSelection: ThemeSelection,
        customTheme: ThemeDefinition = .defaultTheme)
    {
        self.keyboardThemeSelection = keyboardThemeSelection
        self.pointerThemeSelection = pointerThemeSelection
        self.customTheme = customTheme
    }

    public func resolvedTheme(isSystemDark: Bool) -> ThemeDefinition {
        let keyboardDefinition = self.resolvedDefinition(
            for: self.keyboardThemeSelection,
            isSystemDark: isSystemDark)
        let pointerDefinition = self.resolvedDefinition(
            for: self.pointerThemeSelection,
            isSystemDark: isSystemDark)
        return ThemeDefinition(
            keyboard: keyboardDefinition.keyboard,
            pointer: pointerDefinition.pointer,
            hud: keyboardDefinition.hud)
    }

    public mutating func beginCustomizingKeyboard(isSystemDark: Bool) {
        guard self.keyboardThemeSelection != .custom else { return }
        self.customTheme.keyboard = self.resolvedDefinition(
            for: self.keyboardThemeSelection,
            isSystemDark: isSystemDark).keyboard
        self.customTheme.hud = self.resolvedDefinition(
            for: self.keyboardThemeSelection,
            isSystemDark: isSystemDark).hud
        self.keyboardThemeSelection = .custom
    }

    public mutating func beginCustomizingPointer(isSystemDark: Bool) {
        guard self.pointerThemeSelection != .custom else { return }
        self.customTheme.pointer = self.resolvedDefinition(
            for: self.pointerThemeSelection,
            isSystemDark: isSystemDark).pointer
        self.pointerThemeSelection = .custom
    }

    public mutating func beginCustomizing(isSystemDark: Bool) {
        self.beginCustomizingKeyboard(isSystemDark: isSystemDark)
        self.beginCustomizingPointer(isSystemDark: isSystemDark)
    }

    public var themeSelection: ThemeSelection {
        get { self.keyboardThemeSelection }
        set {
            self.keyboardThemeSelection = newValue
            self.pointerThemeSelection = newValue
        }
    }

    private func resolvedDefinition(
        for selection: ThemeSelection,
        isSystemDark: Bool) -> ThemeDefinition
    {
        switch selection {
        case .system: isSystemDark ? .dark : .systemLight
        case .dark: .dark
        case .light: .light
        case .mono: .mono
        case .classic: .classic
        case .modern: .modern
        case .minimal: .minimal
        case .gaming: .gaming
        case .neon: .neon
        case .custom: self.customTheme
        }
    }

    private enum CodingKeys: String, CodingKey {
        case themeSelection
        case keyboardThemeSelection
        case pointerThemeSelection
        case customTheme
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacySelection = try? container.decode(ThemeSelection.self, forKey: .themeSelection)
        self.keyboardThemeSelection =
            (try? container.decode(ThemeSelection.self, forKey: .keyboardThemeSelection))
            ?? legacySelection
            ?? .system
        let decodedPointerSelection =
            (try? container.decode(ThemeSelection.self, forKey: .pointerThemeSelection))
            ?? legacySelection
            ?? .system
        self.pointerThemeSelection = switch decodedPointerSelection {
        case .system, .light:
            .dark
        default:
            decodedPointerSelection
        }
        self.customTheme =
            (try? container.decode(ThemeDefinition.self, forKey: .customTheme))
            ?? .defaultTheme
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.keyboardThemeSelection, forKey: .keyboardThemeSelection)
        try container.encode(self.pointerThemeSelection, forKey: .pointerThemeSelection)
        try container.encode(self.customTheme, forKey: .customTheme)
    }
}

// MARK: - Displays

public struct NormalizedPoint: Codable, Sendable, Equatable, Hashable {
    /// Horizontal center in NSScreen.visibleFrame: 0 is left and 1 is right.
    public var x: Double

    /// Vertical center in NSScreen.visibleFrame: 0 is bottom and 1 is top.
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x.isFinite ? x.clamped(to: 0...1) : 0.5
        self.y = y.isFinite ? y.clamped(to: 0...1) : 0.5
    }

    private enum CodingKeys: String, CodingKey {
        case x
        case y
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: (try? container.decode(Double.self, forKey: .x)) ?? 0.5,
            y: (try? container.decode(Double.self, forKey: .y)) ?? 0.5)
    }
}

public enum DisplayPlacement: Codable, Sendable, Equatable {
    case anchor(
        position: OverlayPosition,
        horizontalOffset: Double,
        verticalOffset: Double)
    case custom(center: NormalizedPoint, fallbackAnchor: OverlayPosition)

    public static let defaultPlacement = DisplayPlacement.anchor(
        position: .bottomRight,
        horizontalOffset: 20,
        verticalOffset: 20)
}

public enum StackedHistoryHorizontalAnchor: Sendable, Equatable {
    case leading
    case center
    case trailing
}

public enum StackedHistoryVerticalAnchor: Sendable, Equatable {
    case top
    case center
    case bottom
}

public struct StackedHistoryLayout: Sendable, Equatable {
    public let horizontalAnchor: StackedHistoryHorizontalAnchor
    public let verticalAnchor: StackedHistoryVerticalAnchor

    public init(_ placement: DisplayPlacement) {
        switch placement {
        case let .anchor(position, _, _):
            self.init(position)
        case .custom:
            self.init(
                horizontalAnchor: .center,
                verticalAnchor: .center)
        }
    }

    public init(
        horizontalAnchor: StackedHistoryHorizontalAnchor,
        verticalAnchor: StackedHistoryVerticalAnchor)
    {
        self.horizontalAnchor = horizontalAnchor
        self.verticalAnchor = verticalAnchor
    }

    public init(_ position: OverlayPosition) {
        self.horizontalAnchor = switch position {
        case .topLeft, .centerLeft, .bottomLeft:
            .leading
        case .topCenter, .bottomCenter:
            .center
        case .topRight, .centerRight, .bottomRight:
            .trailing
        }
        self.verticalAnchor = switch position {
        case .topLeft, .topCenter, .topRight:
            .top
        case .centerLeft, .centerRight:
            .center
        case .bottomLeft, .bottomCenter, .bottomRight:
            .bottom
        }
    }
}

public enum DisplayTarget: Codable, Sendable, Equatable {
    case followPointer
    case fixed(UUID)
    case selected(Set<UUID>)

    public var selectedDisplayIDs: Set<UUID> {
        switch self {
        case .followPointer: []
        case let .fixed(displayID): [displayID]
        case let .selected(displayIDs): displayIDs
        }
    }
}

public struct DisplaySettings: Codable, Sendable, Equatable {
    public var target: DisplayTarget
    public var rememberedSelectedDisplayIDs: Set<UUID>
    public var placements: [UUID: DisplayPlacement]
    public var fallbackPlacement: DisplayPlacement

    /// Placement of the horizontal-history command zone, when the user has dragged it out of
    /// the stacked default. An absent entry means the zone rides under the text ribbon.
    public var commandZonePlacements: [UUID: DisplayPlacement]

    public init(
        target: DisplayTarget = .followPointer,
        rememberedSelectedDisplayIDs: Set<UUID>? = nil,
        placements: [UUID: DisplayPlacement] = [:],
        fallbackPlacement: DisplayPlacement = .defaultPlacement,
        commandZonePlacements: [UUID: DisplayPlacement] = [:])
    {
        self.target = target
        self.rememberedSelectedDisplayIDs = rememberedSelectedDisplayIDs
            ?? (target.selectedDisplayIDs.count > 1 ? target.selectedDisplayIDs : [])
        self.placements = placements.mapValues(\.normalized)
        self.fallbackPlacement = fallbackPlacement.normalized
        self.commandZonePlacements = commandZonePlacements.mapValues(\.normalized)
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case rememberedSelectedDisplayIDs
        case placements
        case fallbackPlacement
        case commandZonePlacements
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let target =
            (try? container.decode(DisplayTarget.self, forKey: .target))
            ?? .followPointer
        let rememberedSelectedDisplayIDs =
            (try? container.decode(Set<UUID>.self, forKey: .rememberedSelectedDisplayIDs))
            ?? {
                if case let .selected(displayIDs) = target {
                    return displayIDs
                }
                return []
            }()
        self.target = target
        self.rememberedSelectedDisplayIDs = rememberedSelectedDisplayIDs
        self.placements =
            ((try? container.decode([UUID: DisplayPlacement].self, forKey: .placements)) ?? [:])
            .mapValues(\.normalized)
        self.fallbackPlacement =
            ((try? container.decode(DisplayPlacement.self, forKey: .fallbackPlacement))
                ?? .defaultPlacement)
            .normalized
        self.commandZonePlacements =
            ((try? container.decode(
                [UUID: DisplayPlacement].self,
                forKey: .commandZonePlacements)) ?? [:])
            .mapValues(\.normalized)
    }

    public func placement(for displayID: UUID) -> DisplayPlacement {
        self.placements[displayID] ?? self.fallbackPlacement
    }

    public mutating func setPlacement(_ placement: DisplayPlacement, for displayID: UUID) {
        self.placements[displayID] = placement.normalized
    }

    public mutating func removePlacement(for displayID: UUID) {
        self.placements.removeValue(forKey: displayID)
    }

    /// The command zone's own placement, or nil while it stays stacked under the ribbon.
    public func commandZonePlacement(for displayID: UUID) -> DisplayPlacement? {
        self.commandZonePlacements[displayID]
    }

    public mutating func setCommandZonePlacement(
        _ placement: DisplayPlacement,
        for displayID: UUID)
    {
        self.commandZonePlacements[displayID] = placement.normalized
    }

    public mutating func removeCommandZonePlacement(for displayID: UUID) {
        self.commandZonePlacements.removeValue(forKey: displayID)
    }
}

extension DisplayPlacement {
    fileprivate var normalized: DisplayPlacement {
        switch self {
        case let .anchor(position, horizontalOffset, verticalOffset):
            .anchor(
                position: position,
                horizontalOffset: horizontalOffset.isFinite
                    ? horizontalOffset.clamped(to: 0...200)
                    : 20,
                verticalOffset: verticalOffset.isFinite
                    ? verticalOffset.clamped(to: 0...200)
                    : 20)
        case let .custom(center, fallbackAnchor):
            .custom(
                center: NormalizedPoint(x: center.x, y: center.y),
                fallbackAnchor: fallbackAnchor)
        }
    }
}

// MARK: - HUD

public struct HUDSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var duration: TimeInterval

    public init(enabled: Bool = true, duration: TimeInterval = 1.6) {
        self.enabled = enabled
        self.duration = duration.clamped(to: 0.5...10)
    }

    func normalized() -> HUDSettings {
        HUDSettings(enabled: self.enabled, duration: self.duration)
    }
}

// MARK: - Versioned Snapshot

public struct AppSettings: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 4

    public var schemaVersion: Int
    public var general: GeneralSettings
    public var keyboard: KeyboardSettings
    public var pointer: PointerSettings
    public var pet: PetSettings
    public var appearance: AppearanceSettings
    public var displays: DisplaySettings
    public var hud: HUDSettings

    public init(
        schemaVersion: Int = AppSettings.currentSchemaVersion,
        general: GeneralSettings = GeneralSettings(),
        keyboard: KeyboardSettings = KeyboardSettings(),
        pointer: PointerSettings = PointerSettings(),
        pet: PetSettings = PetSettings(),
        appearance: AppearanceSettings = AppearanceSettings(),
        displays: DisplaySettings = DisplaySettings(),
        hud: HUDSettings = HUDSettings())
    {
        self.schemaVersion = schemaVersion
        self.general = general
        self.keyboard = keyboard.normalized()
        self.pointer = pointer.normalized()
        self.pet = pet.normalized()
        self.appearance = appearance
        self.displays = displays
        self.hud = hud.normalized()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case general
        case keyboard
        case pointer
        case pet
        case appearance
        case displays
        case hud
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: (try? container.decode(Int.self, forKey: .schemaVersion)) ?? 0,
            general: (try? container.decode(GeneralSettings.self, forKey: .general)) ?? GeneralSettings(),
            keyboard: (try? container.decode(KeyboardSettings.self, forKey: .keyboard)) ?? KeyboardSettings(),
            pointer: (try? container.decode(PointerSettings.self, forKey: .pointer)) ?? PointerSettings(),
            pet: (try? container.decode(PetSettings.self, forKey: .pet)) ?? PetSettings(),
            appearance: (try? container.decode(AppearanceSettings.self, forKey: .appearance)) ?? AppearanceSettings(),
            displays: (try? container.decode(DisplaySettings.self, forKey: .displays)) ?? DisplaySettings(),
            hud: (try? container.decode(HUDSettings.self, forKey: .hud)) ?? HUDSettings())
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension KeyColor {
    public static let white = KeyColor(red: 1, green: 1, blue: 1)
    public static let pointerCyan = KeyColor(red: 0.05, green: 0.8, blue: 1)
    public static let pointerPurple = KeyColor(red: 0.65, green: 0.3, blue: 1)

    /// A barely-there tone that sets Space, Enter, Backspace and Tab apart from the letter
    /// keys around them.
    ///
    /// The shift is relative to the key's own brightness — dark keycaps lift, light ones
    /// sink — so one rule reads the same on every material instead of needing a per-theme
    /// colour. A touch of desaturation keeps tinted colour keys from looking like a
    /// different category.
    public func inputKeyTinted() -> KeyColor {
        let brightness = (self.red + self.green + self.blue) / 3
        let shift = brightness > 0.5 ? -0.055 : 0.055

        func adjust(_ channel: Double) -> Double {
            let desaturated = channel + (brightness - channel) * 0.18
            return min(1, max(0, desaturated + shift))
        }

        return KeyColor(
            red: adjust(self.red),
            green: adjust(self.green),
            blue: adjust(self.blue),
            alpha: self.alpha)
    }
}
