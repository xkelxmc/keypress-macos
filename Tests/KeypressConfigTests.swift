import Foundation
import Testing
@testable import KeypressCore

private func makeDefaults(_ name: String) throws -> UserDefaults {
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("App Settings")
struct AppSettingsTests {
    @Test("Grouped defaults match the product defaults")
    @MainActor
    func groupedDefaults() throws {
        let settings = try KeypressConfig.makeForTesting(
            userDefaults: makeDefaults("test.app-settings.defaults"))

        #expect(settings.schemaVersion == AppSettings.currentSchemaVersion)
        #expect(settings.general == GeneralSettings())
        #expect(settings.keyboard == KeyboardSettings())
        #expect(settings.pointer == PointerSettings())
        #expect(settings.pet == PetSettings())
        #expect(settings.appearance == AppearanceSettings())
        #expect(settings.displays == DisplaySettings())
        #expect(settings.hud == HUDSettings())
    }

    @Test("One versioned document persists every group")
    @MainActor
    func versionedPersistence() throws {
        let defaults = try makeDefaults("test.app-settings.persistence")
        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        settings.general.language = .german
        settings.keyboard.historyLayout = .stacked
        settings.pointer.motionIntensity = 0.8
        settings.pet.visibility = .typingOnly
        settings.pet.activityMode = .random
        settings.appearance.themeSelection = .neon
        settings.displays.fallbackPlacement = .custom(
            center: NormalizedPoint(x: 0.25, y: 0.75),
            fallbackAnchor: .bottomRight)
        settings.hud.duration = 4

        let data = try #require(defaults.data(forKey: KeypressConfig.storageKey))
        let snapshot = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(snapshot.schemaVersion == AppSettings.currentSchemaVersion)
        #expect(snapshot.general.language == .german)
        #expect(snapshot.keyboard.historyLayout == .stacked)
        #expect(snapshot.pet.visibility == .typingOnly)
        #expect(snapshot.pet.activityMode == .random)
        #expect(snapshot.appearance.themeSelection == .neon)
        #expect(snapshot.hud.duration == 4)
    }

    @Test("Persisted document reloads")
    @MainActor
    func reload() throws {
        let defaults = try makeDefaults("test.app-settings.reload")
        let first = KeypressConfig.makeForTesting(userDefaults: defaults)
        first.keyboard.maxItems = 9
        first.pointer.visibility = .actionsOnly
        first.pet.size = 172
        first.pet.placement = PetPlacement(
            displayID: UUID(),
            center: NormalizedPoint(x: 0.25, y: 0.75))
        first.general.language = .spanish

        let second = KeypressConfig.makeForTesting(userDefaults: defaults)

        #expect(second.keyboard.maxItems == 9)
        #expect(second.pointer.visibility == .actionsOnly)
        #expect(second.pet.size == 172)
        #expect(second.pet.placement == first.pet.placement)
        #expect(second.general.language == .spanish)
    }

    @Test("Documents without pet settings receive pet defaults")
    @MainActor
    func missingPetDefaults() throws {
        let defaults = try makeDefaults("test.app-settings.pet-defaults")
        defaults.set(
            Data(#"{"schemaVersion":3}"#.utf8),
            forKey: KeypressConfig.storageKey)

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        #expect(settings.pet == PetSettings())
        #expect(settings.schemaVersion == AppSettings.currentSchemaVersion)
    }

    @Test("Schema one mechanical themes drop the injected outline")
    @MainActor
    func mechanicalBorderMigration() throws {
        let defaults = try makeDefaults("test.app-settings.mechanical-border-migration")
        let oldSettings = AppSettings(
            schemaVersion: 1,
            appearance: AppearanceSettings(
                themeSelection: .custom,
                customTheme: ThemeDefinition(
                    keyboard: KeyboardTheme(borderWidth: 1))))
        try defaults.set(JSONEncoder().encode(oldSettings), forKey: KeypressConfig.storageKey)

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        #expect(settings.schemaVersion == AppSettings.currentSchemaVersion)
        #expect(settings.appearance.customTheme.keyboard.borderWidth == 0)
    }

    @Test("Schema one light mechanical themes drop the injected outline")
    @MainActor
    func lightMechanicalBorderMigration() throws {
        let defaults = try makeDefaults("test.app-settings.light-mechanical-border-migration")
        let oldSettings = AppSettings(
            schemaVersion: 1,
            appearance: AppearanceSettings(
                themeSelection: .custom,
                customTheme: ThemeDefinition(
                    keyboard: KeyboardTheme(
                        borderColor: KeyColor(red: 0, green: 0, blue: 0, alpha: 0.12),
                        borderWidth: 1))))
        try defaults.set(JSONEncoder().encode(oldSettings), forKey: KeypressConfig.storageKey)

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        #expect(settings.schemaVersion == AppSettings.currentSchemaVersion)
        #expect(settings.appearance.customTheme.keyboard.borderWidth == 0)
    }

    @Test("Schema one preserves an intentional mechanical border")
    @MainActor
    func intentionalMechanicalBorderMigration() throws {
        let defaults = try makeDefaults("test.app-settings.intentional-mechanical-border")
        let oldSettings = AppSettings(
            schemaVersion: 1,
            appearance: AppearanceSettings(
                themeSelection: .custom,
                customTheme: ThemeDefinition(
                    keyboard: KeyboardTheme(
                        borderColor: .pointerCyan,
                        borderWidth: 2))))
        try defaults.set(JSONEncoder().encode(oldSettings), forKey: KeypressConfig.storageKey)

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        #expect(settings.appearance.customTheme.keyboard.borderColor == .pointerCyan)
        #expect(settings.appearance.customTheme.keyboard.borderWidth == 2)
    }

    @Test("Legacy flat keys migrate without deleting old data")
    @MainActor
    func legacyMigration() throws {
        let defaults = try makeDefaults("test.app-settings.migration")
        defaults.set(false, forKey: "settings.enabled")
        defaults.set(true, forKey: "settings.launchAtLogin")
        defaults.set("history", forKey: "settings.displayMode")
        defaults.set("large", forKey: "settings.size")
        defaults.set(0.45, forKey: "settings.opacity")
        defaults.set(3.5, forKey: "settings.keyTimeout")
        defaults.set(10, forKey: "settings.maxKeys")
        defaults.set("topLeft", forKey: "settings.position")
        defaults.set(42, forKey: "settings.horizontalOffset")
        defaults.set(64, forKey: "settings.verticalOffset")
        defaults.set("monochrome", forKey: "settings.appearanceMode")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        #expect(!settings.general.enabled)
        #expect(settings.general.launchAtLogin)
        #expect(settings.keyboard.displayMode == .history)
        #expect(settings.keyboard.size == .large)
        #expect(settings.keyboard.opacity == 0.45)
        #expect(settings.keyboard.timeout == 3.5)
        #expect(settings.keyboard.maxItems == 10)
        #expect(settings.appearance.themeSelection == .mono)
        #expect(
            settings.displays.fallbackPlacement == .anchor(
                position: .topLeft,
                horizontalOffset: 42,
                verticalOffset: 64))
        #expect(defaults.data(forKey: KeypressConfig.storageKey) != nil)
        #expect(defaults.string(forKey: "settings.position") == "topLeft")
    }

    @Test("Legacy history ignores the stale single-mode shortcut filter")
    @MainActor
    func legacyHistoryContentMode() throws {
        let defaults = try makeDefaults("test.app-settings.history-content-mode")
        defaults.set("history", forKey: "settings.displayMode")
        defaults.set(true, forKey: "settings.showModifiersOnly")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        #expect(settings.keyboard.displayMode == .history)
        #expect(settings.keyboard.contentMode == .allKeys)
    }

    @Test("Invalid numeric values are normalized on assignment")
    @MainActor
    func normalization() throws {
        let settings = try KeypressConfig.makeForTesting(
            userDefaults: makeDefaults("test.app-settings.normalization"))

        settings.keyboard.timeout = 100
        settings.keyboard.maxItems = -4
        settings.keyboard.opacity = -1
        settings.pointer.size = 500
        settings.pointer.motionIntensity = -2
        settings.pet.size = 500
        settings.pet.placement = PetPlacement(
            displayID: UUID(),
            center: NormalizedPoint(x: 0.5, y: 0.5))
        settings.pet.placement?.center.x = 2
        settings.pet.placement?.center.y = -.infinity
        settings.hud.duration = 100

        #expect(settings.keyboard.timeout == 5)
        #expect(settings.keyboard.maxItems == 3)
        #expect(settings.keyboard.opacity == 0)
        #expect(settings.pointer.size == 160)
        #expect(settings.pointer.motionIntensity == 0)
        #expect(settings.pet.size == 180)
        #expect(settings.pet.placement?.center == NormalizedPoint(x: 1, y: 0.5))
        #expect(settings.hud.duration == 10)
    }

    @Test("Legacy visual overrides migrate into the effective custom theme")
    @MainActor
    func legacyVisualOverrides() throws {
        let defaults = try makeDefaults("test.app-settings.visual-migration")
        defaults.set("light", forKey: "settings.appearanceMode")
        defaults.set("flat", forKey: "settings.keyCapStyle")
        defaults.set("none", forKey: "settings.keyboardFrameStyle")
        try defaults.set(JSONEncoder().encode(KeyColorScheme.light), forKey: "settings.colorScheme")

        let settings = KeypressConfig.makeForTesting(userDefaults: defaults)

        #expect(settings.appearance.themeSelection == .custom)
        #expect(settings.appearance.customTheme.keyboard.keyCapStyle == .flat)
        #expect(settings.appearance.customTheme.keyboard.frameStyle == .none)
        #expect(settings.appearance.customTheme.keyboard.borderWidth == 1)
        #expect(settings.appearance.customTheme.keyboard.colorScheme == .light)
    }

    @Test("Reset restores one complete default snapshot")
    @MainActor
    func reset() throws {
        let settings = try KeypressConfig.makeForTesting(
            userDefaults: makeDefaults("test.app-settings.reset"))
        settings.general.enabled = false
        settings.keyboard.historyLayout = .stacked
        settings.pointer.enabled = false
        settings.pet.enabled = false
        settings.appearance.themeSelection = .gaming

        settings.resetToDefaults()

        #expect(settings.snapshot == AppSettings())
    }
}

@Suite("Themes")
struct ThemeTests {
    @Test("Every built-in selection resolves")
    func builtInResolution() {
        let selections = ThemeSelection.allCases.filter { $0 != .custom }
        for selection in selections {
            let appearance = AppearanceSettings(themeSelection: selection)
            let theme = appearance.resolvedTheme(isSystemDark: true)
            #expect(theme != ThemeDefinition(
                keyboard: KeyboardTheme(fontScale: 0.5),
                pointer: PointerTheme(),
                hud: HUDPalette()))
        }
    }

    @Test("Built-in galleries contain distinct keyboard and pointer designs")
    func builtInDesignSignatures() {
        let selections = ThemeSelection.allCases.filter { $0 != .custom }
        let definitions = selections.map {
            AppearanceSettings(themeSelection: $0).resolvedTheme(isSystemDark: true)
        }
        let keyboardSignatures = Set(definitions.map {
            "\($0.keyboard.keyCapStyle.rawValue):\($0.keyboard.frameStyle.rawValue):"
                + "\($0.keyboard.material.rawValue):\($0.keyboard.pressEffect.rawValue)"
        })
        let pointerSignatures = Set(definitions.map {
            "\($0.pointer.shape.rawValue):\($0.pointer.lineStyle.rawValue):"
                + "\($0.pointer.decoration.rawValue):\($0.pointer.reactionStyle.rawValue)"
        })

        #expect(keyboardSignatures.count == selections.count - 1)
        #expect(pointerSignatures.count == selections.count - 1)
    }

    @Test("System selection follows supplied appearance")
    func systemResolution() {
        let appearance = AppearanceSettings(themeSelection: .system)
        #expect(appearance.resolvedTheme(isSystemDark: true) == .dark)
        #expect(appearance.resolvedTheme(isSystemDark: false) == .systemLight)
        #expect(appearance.resolvedTheme(isSystemDark: false).keyboard.material == .graphite)
        #expect(ThemeDefinition.light.keyboard.material == .aluminum)
    }

    @Test("Editing starts from the selected built-in")
    func beginCustomizing() {
        var appearance = AppearanceSettings(themeSelection: .modern)
        appearance.beginCustomizing(isSystemDark: true)

        #expect(appearance.themeSelection == .custom)
        #expect(appearance.customTheme == .modern)
    }

    @Test("Custom category styles override theme defaults")
    @MainActor
    func categoryStyleOverride() throws {
        let settings = try KeypressConfig.makeForTesting(
            userDefaults: makeDefaults("test.themes.category-style"))
        let style = KeyCategoryStyle(color: .shiftRed, depth: 0.4)

        settings.setStyleOverride(style, for: .command)

        #expect(settings.appearance.themeSelection == .custom)
        #expect(settings.effectiveStyle(for: .command) == style)
        #expect(settings.hasStyleOverride(for: .command))
    }
}

@Suite("Display Settings")
struct DisplaySettingsTests {
    @Test("Normalized coordinates clamp and use AppKit orientation")
    func normalizedPoint() {
        let point = NormalizedPoint(x: -2, y: 4)
        #expect(point.x == 0)
        #expect(point.y == 1)
    }

    @Test("Per-display placement falls back and mutates")
    func placements() {
        let displayID = UUID()
        let custom = DisplayPlacement.custom(
            center: NormalizedPoint(x: 0.2, y: 0.8),
            fallbackAnchor: .topLeft)
        var settings = DisplaySettings()

        #expect(settings.placement(for: displayID) == .defaultPlacement)

        settings.setPlacement(custom, for: displayID)
        #expect(settings.placement(for: displayID) == custom)

        settings.removePlacement(for: displayID)
        #expect(settings.placement(for: displayID) == .defaultPlacement)
    }

    @Test("Display target exposes selected IDs")
    func selectedIDs() {
        let first = UUID()
        let second = UUID()

        #expect(DisplayTarget.followPointer.selectedDisplayIDs.isEmpty)
        #expect(DisplayTarget.fixed(first).selectedDisplayIDs == [first])
        #expect(DisplayTarget.selected([first, second]).selectedDisplayIDs == [first, second])
    }
}

@Suite("Language")
struct LanguageTests {
    @Test("All live languages expose stable locale identifiers")
    func identifiers() {
        #expect(AppLanguage.system.localeIdentifier == nil)
        #expect(AppLanguage.english.localeIdentifier == "en")
        #expect(AppLanguage.german.localeIdentifier == "de")
        #expect(AppLanguage.spanish.localeIdentifier == "es")
        #expect(AppLanguage.french.localeIdentifier == "fr")
        #expect(AppLanguage.russian.localeIdentifier == "ru")
    }
}

@Suite("Visual Primitives")
struct VisualPrimitiveTests {
    @Test("Overlay positions and sizes remain stable")
    func overlayValues() {
        #expect(OverlayPosition.allCases.count == 8)
        #expect(OverlaySize.small.scaleFactor == 0.75)
        #expect(OverlaySize.medium.scaleFactor == 1)
        #expect(OverlaySize.large.scaleFactor == 1.25)
    }

    @Test("Category style clamps values")
    func categoryStyleClamping() {
        let style = KeyCategoryStyle(
            color: .charcoal,
            depth: 2,
            cornerRadius: -1,
            shadowIntensity: 3)

        #expect(style.depth == 1)
        #expect(style.cornerRadius == 0)
        #expect(style.shadowIntensity == 1)
    }

    @Test("Color schemes map every category")
    func colorSchemes() {
        #expect(KeyColorScheme.dark.color(for: .command) == .commandGreen)
        #expect(KeyColorScheme.light.color(for: .letter) == .aluminum)
        #expect(KeyColorScheme.monochromeDark.color(for: .escape) == .charcoal)
    }
}
