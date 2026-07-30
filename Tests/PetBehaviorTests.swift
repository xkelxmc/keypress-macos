import Foundation
import KeypressCore
import Testing
@testable import Keypress

@Suite("Pet Behavior")
struct PetBehaviorTests {
    @Test("Typing speed maps from six to eighteen frames per second")
    func typingRate() {
        let now = 100.0
        #expect(PetTypingRate.framesPerSecond(timestamps: [99.9], now: now) == 6)

        let fastTimestamps = (0..<12).map { now - Double($0) * 0.08 }
        #expect(PetTypingRate.framesPerSecond(timestamps: fastTimestamps, now: now) == 18)
    }

    @Test("Cycle mode follows the stable order and skips disabled activities")
    func cycleOrder() {
        var scheduler = PetActivityScheduler()
        let enabled: [PetAmbientActivity] = [.stretch, .playTail]

        #expect(scheduler.next(mode: .cycle, enabled: enabled, randomValue: 0) == .stretch)
        #expect(scheduler.next(mode: .cycle, enabled: enabled, randomValue: 0) == .playTail)
        #expect(scheduler.next(mode: .cycle, enabled: enabled, randomValue: 0) == .stretch)
    }

    @Test("Random mode avoids an immediate repeat")
    func randomOrder() {
        var scheduler = PetActivityScheduler()
        let enabled = PetAmbientActivity.allCases
        let first = scheduler.next(mode: .random, enabled: enabled, randomValue: 0)
        let second = scheduler.next(mode: .random, enabled: enabled, randomValue: 0)

        #expect(first != nil)
        #expect(second != first)
    }

    @Test("Interactive states outrank autonomous states")
    func priorities() {
        #expect(PetRuntimeState.carried.canInterrupt(.typing))
        #expect(!PetRuntimeState.typing.canInterrupt(.carried))
        #expect(PetRuntimeState.typing.canInterrupt(.petting))
        #expect(!PetRuntimeState.petting.canInterrupt(.typing))
        #expect(PetRuntimeState.typing.canInterrupt(.settling))
        #expect(!PetRuntimeState.settling.canInterrupt(.typing))
        #expect(!PetRuntimeState.petting.canInterrupt(.pouncing(mirrored: false)))
        #expect(PetRuntimeState.typing.canInterrupt(.pouncing(mirrored: false)))
        #expect(PetRuntimeState.carried.canInterrupt(.pouncing(mirrored: false)))
        #expect(PetRuntimeState.pouncing(mirrored: false).canInterrupt(.ambient(.stretch)))
    }

    @Test("Top-left keyboard places the pet below-left")
    func topLeftInitialPlacement() {
        #expect(
            PetInitialPlacement.origin(
                petSize: self.petSize,
                keyboardFrame: CGRect(x: 24, y: 700, width: 200, height: 80),
                visibleFrame: self.visibleFrame)
                == CGPoint(x: 24, y: 568))
    }

    @Test("Bottom-left keyboard places the pet above-left")
    func bottomLeftInitialPlacement() {
        #expect(
            PetInitialPlacement.origin(
                petSize: self.petSize,
                keyboardFrame: CGRect(x: 24, y: 20, width: 200, height: 80),
                visibleFrame: self.visibleFrame)
                == CGPoint(x: 24, y: 112))
    }

    @Test("Top-right keyboard places the pet below-right")
    func topRightInitialPlacement() {
        #expect(
            PetInitialPlacement.origin(
                petSize: self.petSize,
                keyboardFrame: CGRect(x: 776, y: 700, width: 200, height: 80),
                visibleFrame: self.visibleFrame)
                == CGPoint(x: 876, y: 568))
    }

    @Test("Bottom-right keyboard places the pet above-right")
    func bottomRightInitialPlacement() {
        #expect(
            PetInitialPlacement.origin(
                petSize: self.petSize,
                keyboardFrame: CGRect(x: 776, y: 20, width: 200, height: 80),
                visibleFrame: self.visibleFrame)
                == CGPoint(x: 876, y: 112))
    }

    @Test("Zero-size keyboard anchor still controls the initial corner")
    func zeroSizeInitialPlacementAnchor() {
        #expect(
            PetInitialPlacement.origin(
                petSize: self.petSize,
                keyboardFrame: CGRect(origin: CGPoint(x: 24, y: 780), size: .zero),
                visibleFrame: self.visibleFrame)
                == CGPoint(x: 24, y: 568))
    }

    @Test("Bottom zero-size keyboard anchor reserves one keyboard row")
    func bottomZeroSizeInitialPlacementAnchor() {
        #expect(
            PetInitialPlacement.origin(
                petSize: self.petSize,
                keyboardFrame: CGRect(origin: CGPoint(x: 24, y: 20), size: .zero),
                visibleFrame: self.visibleFrame)
                == CGPoint(x: 24, y: 112))
    }

    @Test("Bundled atlas and manifest satisfy the production contract")
    @MainActor
    func bundledAtlas() throws {
        #expect(PetSpriteSheet.shared.isAvailable)
        let image = try #require(PetSpriteSheet.shared.image(for: .idle, frameIndex: 0))
        #expect(image.size == CGSize(width: 272, height: 208))
        #expect(PetSpriteSheet.shared.image(for: .looking(direction: 15), frameIndex: 0) != nil)
    }

    @Test("Directional clips require eight frames")
    func directionalClipContract() {
        let clips = [
            "idle",
            "typing",
            "sleepTransition",
            "sleep",
            "pounceRight",
            "stretch",
            "groom",
            "playTail",
            "petReaction",
            "carried",
            "settle",
            "lookUpper",
            "lookLower",
        ].reduce(into: [String: PetClipDefinition]()) { clips, name in
            clips[name] = PetClipDefinition(
                row: name == "lookLower" ? 11 : 0,
                start: 0,
                count: name.hasPrefix("look") ? 7 : 1,
                fps: 1,
                loop: false,
                reversible: false)
        }
        let manifest = PetSpriteManifest(
            cellWidth: 272,
            cellHeight: 208,
            columns: 16,
            rows: 12,
            clips: clips)

        #expect(throws: PetSpriteError.invalidClip) {
            try manifest.validate(atlasWidth: 4352, atlasHeight: 2496)
        }
    }

    private var visibleFrame: CGRect {
        CGRect(x: 0, y: 0, width: 1000, height: 800)
    }

    private var petSize: CGSize {
        CGSize(width: 100, height: 120)
    }
}
