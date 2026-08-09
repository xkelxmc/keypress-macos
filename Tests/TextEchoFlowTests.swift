import CoreGraphics
import Foundation
import Testing
@testable import Keypress
@testable import KeypressCore

@Suite("Text Echo Flow")
struct TextEchoFlowTests {
    /// The newest line has to sit on the anchored side, so the line being written is the one
    /// that never moves when the block grows.
    @Test("A zone in the lower half grows upwards, one in the upper half downwards")
    func flowFollowsTheHalfOfTheScreen() {
        let lower: [OverlayPosition] = [.bottomLeft, .bottomCenter, .bottomRight]
        let upper: [OverlayPosition] = [.topLeft, .topCenter, .topRight]

        for position in lower {
            #expect(
                TextEchoFlow.resolve(placement: .anchor(
                    position: position,
                    horizontalOffset: 20,
                    verticalOffset: 20)) == .up,
                "\(position) should flow up")
        }
        for position in upper {
            #expect(
                TextEchoFlow.resolve(placement: .anchor(
                    position: position,
                    horizontalOffset: 20,
                    verticalOffset: 20)) == .down,
                "\(position) should flow down")
        }
    }

    @Test("A free placement is judged against the middle of the display")
    func freePlacementUsesItsOwnCentre() {
        #expect(
            TextEchoFlow.resolve(placement: .custom(
                center: NormalizedPoint(x: 0.5, y: 0.2),
                fallbackAnchor: .bottomRight)) == .up)
        #expect(
            TextEchoFlow.resolve(placement: .custom(
                center: NormalizedPoint(x: 0.5, y: 0.8),
                fallbackAnchor: .topRight)) == .down)
    }

    /// A dying line has to leave the way the history travels, or it crosses the line being
    /// read on its way out.
    @Test("A leaving line drifts the way the history flows")
    func driftFollowsTheFlow() {
        #expect(TextEchoFlow.up.driftDirection < 0)
        #expect(TextEchoFlow.down.driftDirection > 0)
    }

    /// Each line carries its own plaque now, so there is no container drawn around the stack
    /// and nothing near it to clip against. The only boundary left is the overlay window's
    /// shadow-safe margin, which the drift comes nowhere near — so that assertion is a sanity
    /// bound rather than the knife's edge it used to be.
    ///
    /// What still has to hold is the design relation the fade exists for: it must be over
    /// while the plaque has barely moved, or a plaque is seen drifting on its own, clear of the
    /// stack, with nothing holding it. That is what lengthening the fade would break.
    @Test("A leaving line fades out long before it stops moving, and never leaves the window")
    func fadeOutrunsTheDrift() {
        #expect(
            KeypressTiming.textEchoLineFadeDuration
                <= KeypressTiming.textEchoLineDriftDuration / 2)
        #expect(
            KeypressTiming.textEchoLineDriftAtFadeOut
                < overlayShadowInset / OverlaySize.large.scaleFactor)
    }

    @Test("Three plaques are taller than one, by exactly two plaques and their gaps")
    func zoneHeightGrowsPerLine() {
        let one = TextEchoStyle.zoneHeight(lineCount: 1)
        let three = TextEchoStyle.zoneHeight(lineCount: TextEchoState.maxLines)

        #expect(one == TextEchoStyle.nominalPlaqueHeight)
        #expect(three == one + 2 * (TextEchoStyle.nominalPlaqueHeight + TextEchoStyle.lineSpacing))
    }

    /// The lift is optical, so it has to follow the type it is correcting rather than being a
    /// fixed number of points: a theme that renders the echo larger leans by proportionally
    /// more, and a fixed lift would under-correct it.
    @Test("The optical lift follows the size the text is rendered at")
    func opticalLiftIsProportional() {
        let normal = KeyboardTheme(fontScale: 1)
        let large = KeyboardTheme(fontScale: 1.5)

        #expect(
            TextEchoStyle.opticalCenteringOffset(for: large)
                == TextEchoStyle.opticalCenteringOffset(for: normal) * 1.5)

        // Around 2pt at the shipped size: enough to take most of the lean out of lowercase,
        // well short of the ~3.1pt that would centre lowercase exactly and press capitals
        // into the plaque's top edge.
        let shipped = TextEchoStyle.opticalCenteringOffset(for: normal)
        #expect(shipped > 1.5)
        #expect(shipped < 2.5)
    }

    /// The echo wears no keyboard frame, so its plaques are the whole zone and the budget is
    /// exactly what they occupy — a container's padding would be room that is never used.
    @Test("The zone budget is the plaques themselves")
    func zoneBudgetIsTheStack() {
        #expect(
            KeyboardPresentation.stackedHistory.primaryZoneNominalHeight
                == TextEchoStyle.zoneHeight(lineCount: TextEchoState.maxLines))
    }
}
