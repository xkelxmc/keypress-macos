import Testing
@testable import Keypress

@Suite("Localization")
struct LocalizationTests {
    @Test("Every supported language contains every app string")
    func catalogCoverage() {
        for languageCode in ["en", "ru", "de", "es", "fr"] {
            let strings = StudioStrings(languageCode: languageCode)

            for key in StudioStrings.supportedKeys {
                #expect(strings.hasLocalizedValue(for: key))
            }
        }
    }

    @Test("Unknown strings use the supplied key as the final fallback")
    func unknownFallback() {
        let strings = StudioStrings(languageCode: "de")

        #expect(strings["missing.localization.key"] == "missing.localization.key")
    }
}
