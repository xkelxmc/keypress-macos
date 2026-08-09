import CoreGraphics
import SwiftUI
import Testing
@testable import Keypress
@testable import KeypressCore

@Suite("Keyboard Presentation Demo")
struct KeyboardPresentationDemoTests {
    /// The two-zone modes draw a whole zone the other mode does not, and the onboarding step is
    /// the smallest surface they have to do it on. That surface clips rather than shrinks, so a
    /// scale that stopped fitting would cut a zone off instead of making it smaller.
    ///
    /// The demo lays out at full size and is only drawn scaled, so the rendered size is the
    /// unscaled one and the scale has to be applied here.
    @MainActor
    @Test("Both two-zone demos fit the onboarding preview surface")
    func twoZoneDemosFitOnboardingSurface() throws {
        for presentation in [KeyboardPresentation.horizontalHistory, .stackedHistory] {
            guard let size = try Self.layoutSize(for: presentation) else {
                // No offscreen rendering available in this environment — nothing to measure,
                // but the other presentation still gets its turn.
                continue
            }

            let drawnHeight = size.height * KeyboardPresentationDemo.twoZoneScale
            #expect(drawnHeight <= KeyboardPresentationDemo.onboardingSurfaceHeight)
        }
    }

    @MainActor
    private static func layoutSize(for presentation: KeyboardPresentation) throws -> CGSize? {
        let suiteName = "test.keyboard.demo.\(presentation.rawValue)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let config = KeypressConfig.makeEphemeral(userDefaults: defaults)
        config.appearance.keyboardThemeSelection = .dark
        config.keyboard.presentation = presentation

        let renderer = ImageRenderer(content: KeyboardPresentationDemo(config: config))
        renderer.scale = 1
        return renderer.nsImage?.size
    }
}
