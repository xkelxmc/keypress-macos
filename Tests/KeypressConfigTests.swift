import Foundation
import Testing
@testable import KeypressCore

@Suite("KeypressConfig Tests")
struct KeypressConfigTests {
    @Test("Default values are correct")
    @MainActor
    func defaultValues() {
        let defaults = UserDefaults(suiteName: "test.settings.defaults")!
        defaults.removePersistentDomain(forName: "test.settings.defaults")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        #expect(settings.enabled == true)
        #expect(settings.launchAtLogin == false)
        #expect(settings.position == .bottomRight)
        #expect(settings.size == .medium)
        #expect(settings.opacity == 1.0)
        #expect(settings.keyTimeout == 1.5)
    }

    @Test("KeypressConfig persist to UserDefaults")
    @MainActor
    func persistence() {
        let defaults = UserDefaults(suiteName: "test.settings.persistence")!
        defaults.removePersistentDomain(forName: "test.settings.persistence")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        settings.enabled = false
        settings.launchAtLogin = true
        settings.position = .topLeft
        settings.size = .large
        settings.opacity = 0.5
        settings.keyTimeout = 3.0

        #expect(defaults.bool(forKey: "settings.enabled") == false)
        #expect(defaults.bool(forKey: "settings.launchAtLogin") == true)
        #expect(defaults.string(forKey: "settings.position") == "topLeft")
        #expect(defaults.string(forKey: "settings.size") == "large")
        #expect(defaults.double(forKey: "settings.opacity") == 0.5)
        #expect(defaults.double(forKey: "settings.keyTimeout") == 3.0)
    }

    @Test("Reset to defaults works")
    @MainActor
    func test_resetToDefaults() {
        let defaults = UserDefaults(suiteName: "test.settings.reset")!
        defaults.removePersistentDomain(forName: "test.settings.reset")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        settings.enabled = false
        settings.position = .topCenter
        settings.opacity = 0.3

        settings.resetToDefaults()

        #expect(settings.enabled == true)
        #expect(settings.position == .bottomRight)
        #expect(settings.opacity == 1.0)
    }
}

@Suite("OverlayPosition Tests")
struct OverlayPositionTests {
    @Test("All 8 positions exist")
    func allPositions() {
        let positions = OverlayPosition.allCases
        #expect(positions.count == 8)
        #expect(positions.contains(.topLeft))
        #expect(positions.contains(.topCenter))
        #expect(positions.contains(.topRight))
        #expect(positions.contains(.centerLeft))
        #expect(positions.contains(.centerRight))
        #expect(positions.contains(.bottomLeft))
        #expect(positions.contains(.bottomCenter))
        #expect(positions.contains(.bottomRight))
    }

    @Test("Position is Codable")
    func codable() throws {
        let position = OverlayPosition.topLeft
        let encoded = try JSONEncoder().encode(position)
        let decoded = try JSONDecoder().decode(OverlayPosition.self, from: encoded)
        #expect(decoded == position)
    }
}

@Suite("OverlaySize Tests")
struct OverlaySizeTests {
    @Test("Scale factors are correct")
    func scaleFactors() {
        #expect(OverlaySize.small.scaleFactor == 0.75)
        #expect(OverlaySize.medium.scaleFactor == 1.0)
        #expect(OverlaySize.large.scaleFactor == 1.25)
    }

    @Test("Size is Codable")
    func test_codable() throws {
        let size = OverlaySize.large
        let encoded = try JSONEncoder().encode(size)
        let decoded = try JSONDecoder().decode(OverlaySize.self, from: encoded)
        #expect(decoded == size)
    }
}

@Suite("AppearanceMode Tests")
struct AppearanceModeTests {
    @Test("All 5 modes exist")
    func allModes() {
        let modes = AppearanceMode.allCases
        #expect(modes.count == 5)
        #expect(modes.contains(.auto))
        #expect(modes.contains(.dark))
        #expect(modes.contains(.monochrome))
        #expect(modes.contains(.light))
        #expect(modes.contains(.custom))
    }

    @Test("Display names are correct")
    func displayNames() {
        #expect(AppearanceMode.auto.displayName == "Auto")
        #expect(AppearanceMode.dark.displayName == "Dark")
        #expect(AppearanceMode.monochrome.displayName == "Mono")
        #expect(AppearanceMode.light.displayName == "Light")
        #expect(AppearanceMode.custom.displayName == "Custom")
    }

    @Test("AppearanceMode is Codable")
    func test_codable() throws {
        for mode in AppearanceMode.allCases {
            let encoded = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(AppearanceMode.self, from: encoded)
            #expect(decoded == mode)
        }
    }

    @Test("Default appearanceMode is auto")
    @MainActor
    func defaultAppearanceMode() {
        let defaults = UserDefaults(suiteName: "test.appearancemode.default")!
        defaults.removePersistentDomain(forName: "test.appearancemode.default")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)
        #expect(settings.appearanceMode == .auto)
    }

    @Test("AppearanceMode persists to UserDefaults")
    @MainActor
    func test_persistence() {
        let defaults = UserDefaults(suiteName: "test.appearancemode.persist")!
        defaults.removePersistentDomain(forName: "test.appearancemode.persist")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        settings.appearanceMode = .dark
        #expect(defaults.string(forKey: "settings.appearanceMode") == "dark")

        settings.appearanceMode = .monochrome
        #expect(defaults.string(forKey: "settings.appearanceMode") == "monochrome")

        settings.appearanceMode = .light
        #expect(defaults.string(forKey: "settings.appearanceMode") == "light")

        settings.appearanceMode = .auto
        #expect(defaults.string(forKey: "settings.appearanceMode") == "auto")
    }

    @Test("AppearanceMode updates colorScheme for fixed modes")
    @MainActor
    func fixedModeUpdatesColorScheme() {
        let defaults = UserDefaults(suiteName: "test.appearancemode.colorscheme")!
        defaults.removePersistentDomain(forName: "test.appearancemode.colorscheme")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        settings.appearanceMode = .dark
        #expect(settings.colorScheme == .dark)

        settings.appearanceMode = .monochrome
        #expect(settings.colorScheme == .monochromeDark)

        settings.appearanceMode = .light
        #expect(settings.colorScheme == .light)
    }

    @Test("Reset to defaults resets appearanceMode")
    @MainActor
    func test_resetToDefaults() {
        let defaults = UserDefaults(suiteName: "test.appearancemode.reset")!
        defaults.removePersistentDomain(forName: "test.appearancemode.reset")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        settings.appearanceMode = .light
        settings.resetToDefaults()

        #expect(settings.appearanceMode == .auto)
    }
}

@Suite("KeyCategoryStyle Tests")
struct KeyCategoryStyleTests {
    @Test("Default style has correct values")
    func test_defaultValues() {
        let style = KeyCategoryStyle(color: .charcoal)
        #expect(style.depth == 1.0)
        #expect(style.cornerRadius == 0.5)
        #expect(style.shadowIntensity == 1.0)
        #expect(style.style == .mechanical)
    }

    @Test("Values are clamped to valid range")
    func clamping() {
        let style = KeyCategoryStyle(
            color: .charcoal,
            depth: 2.0,
            cornerRadius: -0.5,
            shadowIntensity: 1.5)
        #expect(style.depth == 1.0)
        #expect(style.cornerRadius == 0.0)
        #expect(style.shadowIntensity == 1.0)
    }

    @Test("Default factory method uses scheme color")
    func defaultForCategory() {
        let style = KeyCategoryStyle.default(for: .command, scheme: .dark)
        #expect(style.color == .commandGreen)
        #expect(style.depth == 1.0)
        #expect(style.cornerRadius == 0.5)
    }

    @Test("KeyCategoryStyle is Codable")
    func test_codable() throws {
        let style = KeyCategoryStyle(
            color: .commandGreen,
            depth: 0.8,
            cornerRadius: 0.3,
            shadowIntensity: 0.9,
            style: .flat)
        let encoded = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(KeyCategoryStyle.self, from: encoded)
        #expect(decoded == style)
    }

    @Test("KeyCategoryStyle is Equatable")
    func equatable() {
        let style1 = KeyCategoryStyle(color: .charcoal, depth: 0.5)
        let style2 = KeyCategoryStyle(color: .charcoal, depth: 0.5)
        let style3 = KeyCategoryStyle(color: .charcoal, depth: 0.7)
        #expect(style1 == style2)
        #expect(style1 != style3)
    }
}

@Suite("CategoryStyleOverrides Tests")
struct CategoryStyleOverridesTests {
    @Test("Default has no overrides")
    @MainActor
    func defaultNoOverrides() {
        let defaults = UserDefaults(suiteName: "test.styleoverrides.default")!
        defaults.removePersistentDomain(forName: "test.styleoverrides.default")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)
        #expect(settings.categoryStyleOverrides.isEmpty)
    }

    @Test("effectiveStyle returns default when no override")
    @MainActor
    func effectiveStyleDefault() {
        let defaults = UserDefaults(suiteName: "test.styleoverrides.effective")!
        defaults.removePersistentDomain(forName: "test.styleoverrides.effective")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)
        let style = settings.effectiveStyle(for: .command)
        #expect(style.color == settings.colorScheme.color(for: .command))
    }

    @Test("effectiveStyle returns override when set")
    @MainActor
    func effectiveStyleOverride() {
        let defaults = UserDefaults(suiteName: "test.styleoverrides.override")!
        defaults.removePersistentDomain(forName: "test.styleoverrides.override")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        let customStyle = KeyCategoryStyle(color: .shiftRed, depth: 0.5)
        settings.setStyleOverride(customStyle, for: .command)

        let style = settings.effectiveStyle(for: .command)
        #expect(style.color == .shiftRed)
        #expect(style.depth == 0.5)
    }

    @Test("hasStyleOverride returns correct value")
    @MainActor
    func test_hasStyleOverride() {
        let defaults = UserDefaults(suiteName: "test.styleoverrides.has")!
        defaults.removePersistentDomain(forName: "test.styleoverrides.has")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)
        #expect(!settings.hasStyleOverride(for: .command))

        settings.setStyleOverride(KeyCategoryStyle(color: .charcoal), for: .command)
        #expect(settings.hasStyleOverride(for: .command))

        settings.setStyleOverride(nil, for: .command)
        #expect(!settings.hasStyleOverride(for: .command))
    }

    @Test("Overrides persist to UserDefaults")
    @MainActor
    func test_persistence() {
        let defaults = UserDefaults(suiteName: "test.styleoverrides.persist")!
        defaults.removePersistentDomain(forName: "test.styleoverrides.persist")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        let customStyle = KeyCategoryStyle(color: .optionBlue, depth: 0.3)
        settings.setStyleOverride(customStyle, for: .shift)

        #expect(defaults.data(forKey: "settings.categoryStyleOverrides") != nil)
    }

    @Test("Reset to defaults clears overrides")
    @MainActor
    func resetClearsOverrides() {
        let defaults = UserDefaults(suiteName: "test.styleoverrides.reset")!
        defaults.removePersistentDomain(forName: "test.styleoverrides.reset")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        settings.setStyleOverride(KeyCategoryStyle(color: .charcoal), for: .command)
        settings.setStyleOverride(KeyCategoryStyle(color: .charcoal), for: .shift)

        settings.resetToDefaults()

        #expect(settings.categoryStyleOverrides.isEmpty)
    }
}

@Suite("DisplayMode Tests")
struct DisplayModeTests {
    @Test("All display modes exist")
    func allModes() {
        let modes = DisplayMode.allCases
        #expect(modes.count == 2)
        #expect(modes.contains(.single))
        #expect(modes.contains(.history))
    }

    @Test("DisplayMode is Codable")
    func test_codable() throws {
        for mode in DisplayMode.allCases {
            let encoded = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(DisplayMode.self, from: encoded)
            #expect(decoded == mode)
        }
    }

    @Test("DisplayMode persists to UserDefaults")
    @MainActor
    func test_persistence() {
        let defaults = UserDefaults(suiteName: "test.displaymode.persist")!
        defaults.removePersistentDomain(forName: "test.displaymode.persist")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        settings.displayMode = .history
        #expect(defaults.string(forKey: "settings.displayMode") == "history")

        settings.displayMode = .single
        #expect(defaults.string(forKey: "settings.displayMode") == "single")
    }

    @Test("Default displayMode is single")
    @MainActor
    func defaultDisplayMode() {
        let defaults = UserDefaults(suiteName: "test.displaymode.default")!
        defaults.removePersistentDomain(forName: "test.displaymode.default")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)
        #expect(settings.displayMode == .single)
    }
}

@Suite("MonitorSelection Tests")
struct MonitorSelectionTests {
    @Test("MonitorSelection auto is Codable")
    func autoCodeable() throws {
        let selection = MonitorSelection.auto
        let encoded = try JSONEncoder().encode(selection)
        let decoded = try JSONDecoder().decode(MonitorSelection.self, from: encoded)
        #expect(decoded == selection)
    }

    @Test("MonitorSelection fixed is Codable")
    func fixedCodable() throws {
        let selection = MonitorSelection.fixed(index: 2)
        let encoded = try JSONEncoder().encode(selection)
        let decoded = try JSONDecoder().decode(MonitorSelection.self, from: encoded)
        #expect(decoded == selection)
    }

    @Test("MonitorSelection is Equatable")
    func equatable() {
        #expect(MonitorSelection.auto == MonitorSelection.auto)
        #expect(MonitorSelection.fixed(index: 1) == MonitorSelection.fixed(index: 1))
        #expect(MonitorSelection.fixed(index: 1) != MonitorSelection.fixed(index: 2))
        #expect(MonitorSelection.auto != MonitorSelection.fixed(index: 0))
    }

    @Test("MonitorSelection is Hashable")
    func hashable() {
        var set: Set<MonitorSelection> = []
        set.insert(.auto)
        set.insert(.fixed(index: 0))
        set.insert(.fixed(index: 1))
        set.insert(.auto) // duplicate
        #expect(set.count == 3)
    }

    @Test("Default monitorSelection is auto")
    @MainActor
    func defaultMonitorSelection() {
        let defaults = UserDefaults(suiteName: "test.monitor.default")!
        defaults.removePersistentDomain(forName: "test.monitor.default")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)
        #expect(settings.monitorSelection == .auto)
    }

    @Test("MonitorSelection persists to UserDefaults")
    @MainActor
    func test_persistence() throws {
        let defaults = UserDefaults(suiteName: "test.monitor.persist")!
        defaults.removePersistentDomain(forName: "test.monitor.persist")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        settings.monitorSelection = .fixed(index: 1)
        #expect(defaults.data(forKey: "settings.monitorSelection") != nil)

        // Verify decoded value
        let data = defaults.data(forKey: "settings.monitorSelection")!
        let decoded = try JSONDecoder().decode(MonitorSelection.self, from: data)
        #expect(decoded == .fixed(index: 1))
    }
}

@Suite("KeyboardFrameStyle Tests")
struct KeyboardFrameStyleTests {
    @Test("All frame styles exist")
    func allStyles() {
        let styles = KeyboardFrameStyle.allCases
        #expect(styles.count == 3)
        #expect(styles.contains(.frame))
        #expect(styles.contains(.overlay))
        #expect(styles.contains(.none))
    }

    @Test("KeyboardFrameStyle is Codable")
    func test_codable() throws {
        for style in KeyboardFrameStyle.allCases {
            let encoded = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(KeyboardFrameStyle.self, from: encoded)
            #expect(decoded == style)
        }
    }

    @Test("Default keyboardFrameStyle is frame")
    @MainActor
    func defaultStyle() {
        let defaults = UserDefaults(suiteName: "test.framestyle.default")!
        defaults.removePersistentDomain(forName: "test.framestyle.default")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)
        #expect(settings.keyboardFrameStyle == .frame)
    }

    @Test("KeyboardFrameStyle persists to UserDefaults")
    @MainActor
    func test_persistence() {
        let defaults = UserDefaults(suiteName: "test.framestyle.persist")!
        defaults.removePersistentDomain(forName: "test.framestyle.persist")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        settings.keyboardFrameStyle = .overlay
        #expect(defaults.string(forKey: "settings.keyboardFrameStyle") == "overlay")

        settings.keyboardFrameStyle = .none
        #expect(defaults.string(forKey: "settings.keyboardFrameStyle") == "none")
    }
}

@Suite("KeyCapStyle Tests")
struct KeyCapStyleTests {
    @Test("All keycap styles exist")
    func allStyles() {
        let styles = KeyCapStyle.allCases
        #expect(styles.count == 3)
        #expect(styles.contains(.mechanical))
        #expect(styles.contains(.flat))
        #expect(styles.contains(.minimal))
    }

    @Test("KeyCapStyle is Codable")
    func test_codable() throws {
        for style in KeyCapStyle.allCases {
            let encoded = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(KeyCapStyle.self, from: encoded)
            #expect(decoded == style)
        }
    }

    @Test("Default keyCapStyle is mechanical")
    @MainActor
    func defaultStyle() {
        let defaults = UserDefaults(suiteName: "test.keycapstyle.default")!
        defaults.removePersistentDomain(forName: "test.keycapstyle.default")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)
        #expect(settings.keyCapStyle == .mechanical)
    }

    @Test("KeyCapStyle persists to UserDefaults")
    @MainActor
    func test_persistence() {
        let defaults = UserDefaults(suiteName: "test.keycapstyle.persist")!
        defaults.removePersistentDomain(forName: "test.keycapstyle.persist")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        settings.keyCapStyle = .flat
        #expect(defaults.string(forKey: "settings.keyCapStyle") == "flat")

        settings.keyCapStyle = .minimal
        #expect(defaults.string(forKey: "settings.keyCapStyle") == "minimal")
    }
}

@Suite("KeyColor Tests")
struct KeyColorTests {
    @Test("KeyColor init stores values correctly")
    func initValues() {
        let color = KeyColor(red: 0.5, green: 0.6, blue: 0.7, alpha: 0.8)
        #expect(color.red == 0.5)
        #expect(color.green == 0.6)
        #expect(color.blue == 0.7)
        #expect(color.alpha == 0.8)
    }

    @Test("KeyColor default alpha is 1.0")
    func defaultAlpha() {
        let color = KeyColor(red: 0.5, green: 0.5, blue: 0.5)
        #expect(color.alpha == 1.0)
    }

    @Test("KeyColor is Equatable")
    func equatable() {
        let color1 = KeyColor(red: 0.5, green: 0.5, blue: 0.5)
        let color2 = KeyColor(red: 0.5, green: 0.5, blue: 0.5)
        let color3 = KeyColor(red: 0.6, green: 0.5, blue: 0.5)
        #expect(color1 == color2)
        #expect(color1 != color3)
    }

    @Test("KeyColor is Codable")
    func test_codable() throws {
        let color = KeyColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.9)
        let encoded = try JSONEncoder().encode(color)
        let decoded = try JSONDecoder().decode(KeyColor.self, from: encoded)
        #expect(decoded == color)
    }

    @Test("KeyColor presets are correct")
    func presets() {
        // Verify preset colors have expected values (approximate)
        #expect(KeyColor.charcoal.red < 0.2)
        #expect(KeyColor.aluminum.red > 0.8)
        #expect(KeyColor.commandGreen.green > KeyColor.commandGreen.red)
        #expect(KeyColor.shiftRed.red > KeyColor.shiftRed.green)
        #expect(KeyColor.optionBlue.blue > KeyColor.optionBlue.red)
        #expect(KeyColor.controlOrange.red > KeyColor.controlOrange.blue)
    }
}

@Suite("KeypressConfig Extended Properties Tests")
struct KeypressConfigExtendedPropertiesTests {
    @Test("showModifiersOnly persists to UserDefaults")
    @MainActor
    func showModifiersOnlyPersistence() {
        let defaults = UserDefaults(suiteName: "test.extended.showmodifiers")!
        defaults.removePersistentDomain(forName: "test.extended.showmodifiers")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)
        #expect(settings.showModifiersOnly == false) // default

        settings.showModifiersOnly = true
        #expect(defaults.bool(forKey: "settings.showModifiersOnly") == true)
    }

    @Test("maxKeys persists to UserDefaults")
    @MainActor
    func maxKeysPersistence() {
        let defaults = UserDefaults(suiteName: "test.extended.maxkeys")!
        defaults.removePersistentDomain(forName: "test.extended.maxkeys")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)
        #expect(settings.maxKeys == 6) // default

        settings.maxKeys = 10
        #expect(defaults.integer(forKey: "settings.maxKeys") == 10)
    }

    @Test("maxKeys is clamped to valid range")
    @MainActor
    func maxKeysClamping() {
        let defaults = UserDefaults(suiteName: "test.extended.maxkeys.clamp")!
        defaults.removePersistentDomain(forName: "test.extended.maxkeys.clamp")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        settings.maxKeys = 1 // below min
        #expect(settings.maxKeys == 3)

        settings.maxKeys = 20 // above max
        #expect(settings.maxKeys == 12)
    }

    @Test("duplicateLetters persists to UserDefaults")
    @MainActor
    func duplicateLettersPersistence() {
        let defaults = UserDefaults(suiteName: "test.extended.duplicate")!
        defaults.removePersistentDomain(forName: "test.extended.duplicate")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)
        #expect(settings.duplicateLetters == true) // default

        settings.duplicateLetters = false
        #expect(defaults.bool(forKey: "settings.duplicateLetters") == false)
    }

    @Test("horizontalOffset persists to UserDefaults")
    @MainActor
    func horizontalOffsetPersistence() {
        let defaults = UserDefaults(suiteName: "test.extended.hoffset")!
        defaults.removePersistentDomain(forName: "test.extended.hoffset")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)
        #expect(settings.horizontalOffset == 20) // default

        settings.horizontalOffset = 50
        #expect(defaults.double(forKey: "settings.horizontalOffset") == 50)
    }

    @Test("horizontalOffset is clamped to valid range")
    @MainActor
    func horizontalOffsetClamping() {
        let defaults = UserDefaults(suiteName: "test.extended.hoffset.clamp")!
        defaults.removePersistentDomain(forName: "test.extended.hoffset.clamp")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        settings.horizontalOffset = -10 // below min
        #expect(settings.horizontalOffset == 0)

        settings.horizontalOffset = 200 // above max
        #expect(settings.horizontalOffset == 100)
    }

    @Test("verticalOffset persists to UserDefaults")
    @MainActor
    func verticalOffsetPersistence() {
        let defaults = UserDefaults(suiteName: "test.extended.voffset")!
        defaults.removePersistentDomain(forName: "test.extended.voffset")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)
        #expect(settings.verticalOffset == 20) // default

        settings.verticalOffset = 75
        #expect(defaults.double(forKey: "settings.verticalOffset") == 75)
    }

    @Test("pressAnimationModifiers persists to UserDefaults")
    @MainActor
    func pressAnimationModifiersPersistence() {
        let defaults = UserDefaults(suiteName: "test.extended.pressmod")!
        defaults.removePersistentDomain(forName: "test.extended.pressmod")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)
        #expect(settings.pressAnimationModifiers == true) // default

        settings.pressAnimationModifiers = false
        #expect(defaults.bool(forKey: "settings.pressAnimationModifiers") == false)
    }

    @Test("pressAnimationRegularKeys persists to UserDefaults")
    @MainActor
    func pressAnimationRegularKeysPersistence() {
        let defaults = UserDefaults(suiteName: "test.extended.pressreg")!
        defaults.removePersistentDomain(forName: "test.extended.pressreg")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)
        #expect(settings.pressAnimationRegularKeys == true) // default

        settings.pressAnimationRegularKeys = false
        #expect(defaults.bool(forKey: "settings.pressAnimationRegularKeys") == false)
    }

    @Test("keyTimeout is clamped to valid range")
    @MainActor
    func keyTimeoutClamping() {
        let defaults = UserDefaults(suiteName: "test.extended.timeout.clamp")!
        defaults.removePersistentDomain(forName: "test.extended.timeout.clamp")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        settings.keyTimeout = 0.1 // below min
        #expect(settings.keyTimeout == 0.5)

        settings.keyTimeout = 10.0 // above max
        #expect(settings.keyTimeout == 5.0)
    }

    @Test("opacity is clamped to valid range")
    @MainActor
    func opacityClamping() {
        let defaults = UserDefaults(suiteName: "test.extended.opacity.clamp")!
        defaults.removePersistentDomain(forName: "test.extended.opacity.clamp")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        settings.opacity = -0.5 // below min
        #expect(settings.opacity == 0.0)

        settings.opacity = 1.5 // above max
        #expect(settings.opacity == 1.0)
    }

    @Test("Reset to defaults resets all extended properties")
    @MainActor
    func resetExtendedProperties() {
        let defaults = UserDefaults(suiteName: "test.extended.reset")!
        defaults.removePersistentDomain(forName: "test.extended.reset")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        // Change various properties
        settings.displayMode = .history
        settings.showModifiersOnly = true
        settings.maxKeys = 10
        settings.duplicateLetters = false
        settings.horizontalOffset = 50
        settings.verticalOffset = 50
        settings.keyboardFrameStyle = .overlay
        settings.keyCapStyle = .flat
        settings.pressAnimationModifiers = false
        settings.pressAnimationRegularKeys = false

        settings.resetToDefaults()

        #expect(settings.displayMode == .single)
        #expect(settings.showModifiersOnly == false)
        #expect(settings.maxKeys == 6)
        #expect(settings.duplicateLetters == true)
        #expect(settings.horizontalOffset == 20)
        #expect(settings.verticalOffset == 20)
        #expect(settings.keyboardFrameStyle == .frame)
        #expect(settings.keyCapStyle == .mechanical)
        #expect(settings.pressAnimationModifiers == true)
        #expect(settings.pressAnimationRegularKeys == true)
    }
}

@Suite("KeyColorScheme Tests")
struct KeyColorSchemeTests {
    @Test("Dark scheme has correct colors")
    func darkScheme() {
        let scheme = KeyColorScheme.dark
        #expect(scheme.letter == .charcoal)
        #expect(scheme.command == .commandGreen)
        #expect(scheme.shift == .shiftRed)
        #expect(scheme.option == .optionBlue)
        #expect(scheme.control == .controlOrange)
    }

    @Test("Monochrome scheme has all charcoal colors")
    func monochromeScheme() {
        let scheme = KeyColorScheme.monochromeDark
        #expect(scheme.letter == .charcoal)
        #expect(scheme.command == .charcoal)
        #expect(scheme.shift == .charcoal)
        #expect(scheme.option == .charcoal)
        #expect(scheme.control == .charcoal)
    }

    @Test("Light scheme has aluminum base")
    func lightScheme() {
        let scheme = KeyColorScheme.light
        #expect(scheme.letter == .aluminum)
        #expect(scheme.navigation == .aluminum)
        #expect(scheme.editing == .aluminum)
        // Modifiers are still colored
        #expect(scheme.command == .commandGreen)
        #expect(scheme.shift == .shiftRed)
    }

    @Test("color(for:) returns correct colors")
    func colorForCategory() {
        let scheme = KeyColorScheme.dark
        #expect(scheme.color(for: .letter) == scheme.letter)
        #expect(scheme.color(for: .command) == scheme.command)
        #expect(scheme.color(for: .shift) == scheme.shift)
        #expect(scheme.color(for: .option) == scheme.option)
        #expect(scheme.color(for: .control) == scheme.control)
        #expect(scheme.color(for: .escape) == scheme.escape)
        #expect(scheme.color(for: .function) == scheme.function)
        #expect(scheme.color(for: .navigation) == scheme.navigation)
        #expect(scheme.color(for: .editing) == scheme.editing)
    }

    @Test("KeyColorScheme is Codable")
    func test_codable() throws {
        let scheme = KeyColorScheme.dark
        let encoded = try JSONEncoder().encode(scheme)
        let decoded = try JSONDecoder().decode(KeyColorScheme.self, from: encoded)
        #expect(decoded == scheme)
    }

    @Test("KeyColorScheme is Equatable")
    func test_equatable() {
        #expect(KeyColorScheme.dark == KeyColorScheme.dark)
        #expect(KeyColorScheme.dark != KeyColorScheme.light)
        #expect(KeyColorScheme.monochromeDark != KeyColorScheme.dark)
    }
}
