import Foundation
import Testing
@testable import KeypressCore

@Suite("KeypressConfig Tests")
struct KeypressConfigTests {
    @Test("Default values are correct")
    @MainActor
    func test_defaultValues() {
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
    func test_persistence() {
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
    func test_allPositions() {
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
    func test_codable() throws {
        let position = OverlayPosition.topLeft
        let encoded = try JSONEncoder().encode(position)
        let decoded = try JSONDecoder().decode(OverlayPosition.self, from: encoded)
        #expect(decoded == position)
    }
}

@Suite("OverlaySize Tests")
struct OverlaySizeTests {
    @Test("Scale factors are correct")
    func test_scaleFactors() {
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
