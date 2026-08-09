import CoreGraphics
import Foundation
import Testing
@testable import Keypress

private let current = CGSize(width: 400, height: 200)

@Suite("Overlay Frame Sizing")
struct OverlayFrameSizingTests {
    @Test("Content that outgrows the window resizes it at once")
    func growsImmediately() {
        #expect(
            WindowFrameSizing.update(
                current: current,
                target: CGSize(width: 460, height: 200),
                isHiding: false) == .grow)
        #expect(
            WindowFrameSizing.update(
                current: current,
                target: CGSize(width: 400, height: 260),
                isHiding: false) == .grow)
    }

    /// Growth cannot wait for a settle, so a size that grows on one axis is applied whole
    /// even though the other axis shrinks — the window is never the smaller of the two.
    @Test("Growth on either axis wins over a shrink on the other")
    func mixedChangeGrows() {
        #expect(
            WindowFrameSizing.update(
                current: current,
                target: CGSize(width: 460, height: 120),
                isHiding: false) == .grow)
    }

    @Test("Content that shrinks leaves the window alone for now")
    func shrinkIsDeferred() {
        #expect(
            WindowFrameSizing.update(
                current: current,
                target: CGSize(width: 340, height: 200),
                isHiding: false) == .deferShrink)
        #expect(
            WindowFrameSizing.update(
                current: current,
                target: CGSize(width: 400, height: 150),
                isHiding: false) == .deferShrink)
    }

    @Test("A size that already fits changes nothing")
    func unchangedWhenItFits() {
        #expect(
            WindowFrameSizing.update(
                current: current,
                target: current,
                isHiding: false) == .unchanged)
    }

    @Test("Sub-point differences are noise, not a resize")
    func toleranceAbsorbsNoise() {
        let noise = WindowFrameSizing.tolerance / 2
        #expect(
            WindowFrameSizing.update(
                current: current,
                target: CGSize(width: current.width + noise, height: current.height - noise),
                isHiding: false) == .unchanged)
    }

    /// The whole point of the exit fix: while the overlay leaves, the frame is untouchable no
    /// matter what the collapsing content reports.
    @Test("Nothing moves the frame while the overlay is leaving")
    func exitFreezesTheFrame() {
        let targets = [
            CGSize(width: 460, height: 260),
            CGSize(width: 340, height: 150),
            CGSize(width: 96, height: 96),
            current,
        ]

        for target in targets {
            #expect(
                WindowFrameSizing.update(
                    current: current,
                    target: target,
                    isHiding: true) == .frozen,
                "target \(target) must not move a frozen frame")
        }
    }

    @Test("The settle delay outlasts a frame at 60Hz")
    func settleDelayOutlastsAFrame() {
        #expect(WindowFrameSizing.settleDelay > .milliseconds(1000 / 60))
    }
}

@Suite("Overlay Hide Reasons")
struct OverlayHideReasonTests {
    /// A key timing out is the only ordinary end to an overlay, and the only one that gets to
    /// finish its fade.
    @Test("Only an expired key hides gracefully")
    func onlyExpiredKeysAreGraceful() {
        for reason in OverlayHideReason.allCases {
            let expected: OverlayHideStyle = reason == .keysExpired ? .graceful : .immediate
            #expect(reason.style == expected, "\(reason) should hide \(expected)")
        }
    }

    /// Anything that cuts the overlay short has to be gone at once: a fade would outlive the
    /// state it is animating, and in the secure-input case would keep showing input the app
    /// is no longer allowed to display.
    @Test("Every interruption hides immediately")
    func interruptionsAreImmediate() {
        let interruptions: [OverlayHideReason] = [
            .stopping,
            .secureInput,
            .placementEditor,
            .presentationChanged,
            .transientReset,
            .displayNoLongerTargeted,
        ]

        for reason in interruptions {
            #expect(reason.style == .immediate)
        }
        // Guards against a new reason quietly defaulting to graceful.
        #expect(OverlayHideReason.allCases.count == interruptions.count + 1)
    }
}
