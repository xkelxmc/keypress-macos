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
