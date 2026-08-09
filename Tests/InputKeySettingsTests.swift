import Foundation
import Testing
@testable import KeypressCore

@Suite("Input Key Width")
struct InputKeyWidthTests {
    @Test("Symbol ids map to the key whose setting governs them")
    func symbolMapping() {
        #expect(InputKey.from(symbolID: "space") == .space)
        #expect(InputKey.from(symbolID: "return") == .enter)
        #expect(InputKey.from(symbolID: "enter") == .enter)
        #expect(InputKey.from(symbolID: "delete") == .backspace)
        #expect(InputKey.from(symbolID: "tab") == .tab)
    }

    @Test("Forward Delete follows the Backspace setting")
    func forwardDeleteFollowsBackspace() {
        #expect(InputKey.from(symbolID: "forward-delete") == .backspace)

        let narrow = InputKeySettings(widthMode: .narrow)
        #expect(narrow.rendersWide(.backspace, isControlPosition: true) == false)

        let customBackspaceNarrow = InputKeySettings(
            widthMode: .custom,
            widths: InputKeyWidths(backspace: false))
        #expect(customBackspaceNarrow.rendersWide(.backspace, isControlPosition: true) == false)
    }

    @Test("Keys outside the input group are governed by no setting")
    func unrelatedSymbols() {
        #expect(InputKey.from(symbolID: "a") == nil)
        #expect(InputKey.from(symbolID: "escape") == nil)
        #expect(InputKey.from(symbolID: "command-left") == nil)
    }

    @Test("Wide mode is wide in a control position and standard in ribbon history")
    func wideMode() {
        let settings = InputKeySettings(widthMode: .wide)

        for key in InputKey.allCases {
            #expect(settings.rendersWide(key, isControlPosition: true))
            #expect(settings.rendersWide(key, isControlPosition: false) == false)
        }
    }

    @Test("Narrow mode is standard everywhere")
    func narrowMode() {
        let settings = InputKeySettings(widthMode: .narrow)

        for key in InputKey.allCases {
            #expect(settings.rendersWide(key, isControlPosition: true) == false)
            #expect(settings.rendersWide(key, isControlPosition: false) == false)
        }
    }

    @Test("Custom mode follows the per-key choice, still only in a control position")
    func customMode() {
        let settings = InputKeySettings(
            widthMode: .custom,
            widths: InputKeyWidths(space: false, enter: true, backspace: true, tab: false))

        #expect(settings.rendersWide(.space, isControlPosition: true) == false)
        #expect(settings.rendersWide(.enter, isControlPosition: true))
        #expect(settings.rendersWide(.backspace, isControlPosition: true))
        #expect(settings.rendersWide(.tab, isControlPosition: true) == false)

        for key in InputKey.allCases {
            #expect(settings.rendersWide(key, isControlPosition: false) == false)
        }
    }

    @Test("Custom widths default to today's wide behaviour")
    func customDefaultsMatchWide() {
        let settings = InputKeySettings(widthMode: .custom)

        for key in InputKey.allCases {
            #expect(settings.rendersWide(key, isControlPosition: true))
        }
    }

    @Test("The per-key subscript reads and writes every key")
    func widthSubscript() {
        var widths = InputKeyWidths()

        for key in InputKey.allCases {
            widths[key] = false
            #expect(widths[key] == false)
            widths[key] = true
            #expect(widths[key])
        }
    }
}

@Suite("Input Key Tint")
struct InputKeyTintTests {
    @Test("A dark keycap lifts and a light one sinks")
    func tintDirection() {
        let dark = KeyColor.charcoal.inputKeyTinted()
        let light = KeyColor.aluminum.inputKeyTinted()

        #expect(Self.brightness(dark) > Self.brightness(.charcoal))
        #expect(Self.brightness(light) < Self.brightness(.aluminum))
    }

    @Test("The shift stays subtle")
    func tintStaysSubtle() {
        for color in [KeyColor.charcoal, .aluminum, .commandGreen, .shiftRed, .optionBlue] {
            let shift = abs(Self.brightness(color.inputKeyTinted()) - Self.brightness(color))
            #expect(shift < 0.1)
        }
    }

    @Test("Channels stay in range and alpha is preserved")
    func tintStaysInRange() {
        for color in [
            KeyColor(red: 0, green: 0, blue: 0),
            KeyColor(red: 1, green: 1, blue: 1),
            KeyColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 0.5),
        ] {
            let tinted = color.inputKeyTinted()
            #expect((0...1).contains(tinted.red))
            #expect((0...1).contains(tinted.green))
            #expect((0...1).contains(tinted.blue))
            #expect(tinted.alpha == color.alpha)
        }
    }

    @Test("A tinted colour is never identical to its source")
    func tintIsVisible() {
        for color in [KeyColor.charcoal, .aluminum, .commandGreen] {
            #expect(color.inputKeyTinted() != color)
        }
    }

    private static func brightness(_ color: KeyColor) -> Double {
        (color.red + color.green + color.blue) / 3
    }
}

@Suite("Settings Backward Compatibility")
struct SettingsBackwardCompatibilityTests {
    /// A settings document as written by a build that predates the input-key and echo-timing
    /// fields, and still carries the two history switches that have since been removed.
    private static let legacyDocument = """
    {
      "schemaVersion": 4,
      "keyboard": {
        "enabled": true,
        "displayMode": "history",
        "contentMode": "allKeys",
        "filters": {
          "showStandaloneModifiers": false,
          "showFunctionKeys": false,
          "showSpecialKeys": true
        },
        "historyLayout": "horizontal",
        "size": "large",
        "opacity": 0.8,
        "timeout": 2.5,
        "maxItems": 9,
        "duplicateLetters": false,
        "limitIncludesModifiers": false,
        "pressAnimationModifiers": false,
        "pressAnimationRegularKeys": true
      },
      "displays": {
        "target": { "followPointer": {} },
        "placements": {},
        "fallbackPlacement": {
          "anchor": {
            "position": "topLeft",
            "horizontalOffset": 40,
            "verticalOffset": 30
          }
        }
      }
    }
    """

    @Test("Keyboard settings written before the new fields keep every stored value")
    func legacyKeyboardSettingsSurvive() throws {
        let data = try #require(Self.legacyDocument.data(using: .utf8))
        let settings = try JSONDecoder().decode(AppSettings.self, from: data).keyboard

        #expect(settings.displayMode == .history)
        #expect(settings.historyLayout == .horizontal)
        #expect(settings.size == .large)
        #expect(settings.opacity == 0.8)
        #expect(settings.timeout == 2.5)
        #expect(settings.maxItems == 9)
        #expect(settings.pressAnimationModifiers == false)
        #expect(settings.pressAnimationRegularKeys)
        #expect(settings.filters.showStandaloneModifiers == false)
        #expect(settings.filters.showFunctionKeys == false)
        #expect(settings.filters.showSpecialKeys)
    }

    @Test("Fields added later fall back to their defaults")
    func newFieldsUseDefaults() throws {
        let data = try #require(Self.legacyDocument.data(using: .utf8))
        let settings = try JSONDecoder().decode(AppSettings.self, from: data).keyboard

        #expect(settings.inputKeys.widthMode == .wide)
        #expect(settings.inputKeys.highlight)
        #expect(settings.inputKeys.widths == InputKeyWidths())
        #expect(settings.textLineLifetime == TextEchoState.defaultLineLifetime)
        #expect(settings.textIdleTimeout == TextEchoState.defaultIdleTimeout)
    }

    /// Fields that no longer exist are simply not read: a document still carrying them has to
    /// decode without complaint, and without dragging anything else down with it.
    @Test("Removed fields in a stored document are ignored")
    func removedFieldsAreIgnored() throws {
        let data = try #require(Self.legacyDocument.data(using: .utf8))
        let settings = try JSONDecoder().decode(AppSettings.self, from: data).keyboard

        #expect(settings == KeyboardSettings(
            displayMode: .history,
            filters: KeyboardFilterSettings(
                showStandaloneModifiers: false,
                showFunctionKeys: false),
            size: .large,
            opacity: 0.8,
            timeout: 2.5,
            maxItems: 9,
            pressAnimationModifiers: false))
    }

    @Test("A display document without command-zone placements decodes to none")
    func legacyDisplaysDecode() throws {
        let data = try #require(Self.legacyDocument.data(using: .utf8))
        let displays = try JSONDecoder().decode(AppSettings.self, from: data).displays

        #expect(displays.commandZonePlacements.isEmpty)
        #expect(displays.commandZonePlacement(for: UUID()) == nil)
        #expect(displays.fallbackPlacement == .anchor(
            position: .topLeft,
            horizontalOffset: 40,
            verticalOffset: 30))
    }

    @Test("Command zone placements round-trip and can be cleared")
    func commandZonePlacementRoundTrip() throws {
        let displayID = UUID()
        var displays = DisplaySettings()
        displays.setCommandZonePlacement(
            .anchor(position: .bottomLeft, horizontalOffset: 12, verticalOffset: 34),
            for: displayID)

        let encoded = try JSONEncoder().encode(displays)
        let decoded = try JSONDecoder().decode(DisplaySettings.self, from: encoded)

        #expect(decoded.commandZonePlacement(for: displayID) == .anchor(
            position: .bottomLeft,
            horizontalOffset: 12,
            verticalOffset: 34))

        displays.removeCommandZonePlacement(for: displayID)
        #expect(displays.commandZonePlacement(for: displayID) == nil)
    }

    @Test("Input key settings decode field by field")
    func partialInputKeySettingsDecode() throws {
        let json = #"{"widthMode":"narrow"}"#
        let data = try #require(json.data(using: .utf8))
        let settings = try JSONDecoder().decode(InputKeySettings.self, from: data)

        #expect(settings.widthMode == .narrow)
        #expect(settings.highlight)
        #expect(settings.widths == InputKeyWidths())
    }
}
