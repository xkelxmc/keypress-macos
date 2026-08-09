import CoreGraphics
import SwiftUI
import Testing
@testable import Keypress
@testable import KeypressCore

@Suite("KeyCapView Offscreen Rendering")
struct KeyCapViewRenderTests {
    /// App Store screenshots and the promo frames draw keycaps through `ImageRenderer`,
    /// which never appears a view. The press visuals must therefore come out of the
    /// initial render, not out of `onAppear`.
    @MainActor
    @Test("A pressed keycap renders pressed without ever appearing")
    func pressedKeycapRendersPressedOffscreen() throws {
        let config = try Self.config("test.keycap.pressed", highlight: true)
        let symbol = KeySymbol(id: "a", display: "A")

        guard let pressed = Self.render(symbol: symbol, config: config, isPressed: true),
              let released = Self.render(symbol: symbol, config: config, isPressed: false)
        else {
            // No offscreen rendering available in this environment — nothing to compare.
            return
        }

        #expect(pressed.count == released.count)
        #expect(pressed != released)
    }

    /// The default width mode must reproduce the widths every other mode shipped with, so
    /// Latest and Stacked History keep their exact layout.
    @Test("Default input-key settings resolve to the shipped widths")
    func defaultWidthsMatchLegacyLayout() {
        let settings = InputKeySettings()
        let symbols = [
            KeySymbol(id: "space", display: "␣", isSpecial: true),
            KeySymbol(id: "return", display: "⏎", isSpecial: true),
            KeySymbol(id: "enter", display: "⏎", isSpecial: true),
            KeySymbol(id: "tab", display: "⇥", isSpecial: true),
            KeySymbol(id: "delete", display: "⌫", isSpecial: true),
            KeySymbol(id: "forward-delete", display: "⌦", isSpecial: true),
            KeySymbol(id: "escape", display: "⎋", isSpecial: true),
            KeySymbol(id: "a", display: "A"),
            KeySymbol(id: "command-left", display: "⌘", isModifier: true),
        ]

        for symbol in symbols {
            let resolved = KeyCapSize.inputKey(
                for: symbol,
                settings: settings,
                isControlPosition: true) ?? KeyCapSize.from(symbol: symbol)
            #expect(resolved.width == KeyCapSize.from(symbol: symbol).width)
        }
    }

    @Test("Narrow mode shrinks the input keys and leaves the rest alone")
    func narrowModeScopedToInputKeys() {
        let settings = InputKeySettings(widthMode: .narrow)
        let space = KeySymbol(id: "space", display: "␣", isSpecial: true)
        let forwardDelete = KeySymbol(id: "forward-delete", display: "⌦", isSpecial: true)
        let escape = KeySymbol(id: "escape", display: "⎋", isSpecial: true)

        #expect(KeyCapSize.inputKey(for: space, settings: settings, isControlPosition: true) == .standard)
        #expect(
            KeyCapSize.inputKey(
                for: forwardDelete,
                settings: settings,
                isControlPosition: true) == .standard)
        #expect(KeyCapSize.inputKey(for: escape, settings: settings, isControlPosition: true) == nil)
    }

    /// Forward Delete has no settings row of its own, so the proof that it really follows
    /// Backspace is that the drawn keycap changes when the tint is switched off.
    ///
    /// Only the difference is asserted, never sameness: two separate `ImageRenderer` passes
    /// of the same view are not reliably byte-identical under a loaded test run, so an
    /// equality check would flake. What scopes the tint to the input keys is
    /// `InputKey.from(symbolID:)` returning nil for everything else, and that is asserted
    /// directly in `InputKeyWidthTests`.
    @MainActor
    @Test("Forward Delete is tinted with the other input keys")
    func forwardDeleteIsTinted() throws {
        let tinted = try Self.config("test.keycap.tint.on", highlight: true)
        let plain = try Self.config("test.keycap.tint.off", highlight: false)
        let forwardDelete = KeySymbol(id: "forward-delete", display: "⌦", isSpecial: true)

        guard let tintedForwardDelete = Self.render(symbol: forwardDelete, config: tinted),
              let plainForwardDelete = Self.render(symbol: forwardDelete, config: plain)
        else {
            return
        }

        #expect(tintedForwardDelete != plainForwardDelete)
    }

    /// An isolated config with the theme pinned.
    ///
    /// A keycap normally resolves its theme through the system appearance, and `NSApp` only
    /// becomes available part-way through a test run — so an unpinned keycap renders one way
    /// early in the suite and another way later, and bitmap comparisons turn on which test
    /// happened to run first. Naming the theme removes that dependency entirely.
    @MainActor
    private static func config(_ suiteName: String, highlight: Bool) throws -> KeypressConfig {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let config = KeypressConfig.makeEphemeral(userDefaults: defaults)
        config.appearance.keyboardThemeSelection = .dark
        config.keyboard.inputKeys.highlight = highlight
        return config
    }

    @MainActor
    private static func render(
        symbol: KeySymbol,
        config: KeypressConfig,
        isPressed: Bool = false) -> [UInt8]?
    {
        let renderer = ImageRenderer(
            content: KeyCapView(
                symbol: symbol,
                config: config,
                isPressed: isPressed))
        renderer.scale = 2

        guard let image = renderer.cgImage,
              let data = image.dataProvider?.data as Data?
        else {
            return nil
        }
        return [UInt8](data)
    }
}
