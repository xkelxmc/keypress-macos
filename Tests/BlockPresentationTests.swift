import Foundation
import Testing
@testable import Keypress
@testable import KeypressCore

@Suite("Block Presentation")
struct BlockPresentationTests {
    @Test("A block with nothing in it starts hidden, and one with content starts shown")
    func initialPhase() {
        #expect(BlockPresentation(isPresent: false).phase == .hidden)
        #expect(BlockPresentation(isPresent: false).isRaised == false)

        // Content that is already there when the view is built — a stacked-history row, say —
        // is not animated in; it was never absent.
        #expect(BlockPresentation(isPresent: true).phase == .shown)
        #expect(BlockPresentation(isPresent: true).isRaised)
    }

    /// The entrance now has a beat before it: the block composes its contents while still low
    /// and transparent, and only then raises. Nothing about the contents may ride the raise.
    @Test("The first key composes the block, then raises it")
    func entering() {
        var presentation = BlockPresentation(isPresent: false)

        #expect(presentation.setPresent(true) == .enter)
        #expect(presentation.phase == .composing)
        #expect(presentation.isRaised == false, "a composing block is still down and invisible")

        let raised = presentation.raise()
        #expect(raised)
        #expect(presentation.phase == .entering)
        #expect(presentation.isRaised)

        presentation.finish(.enter)
        #expect(presentation.phase == .shown)
        #expect(presentation.isSettled)
    }

    @Test("A raise only happens out of composing")
    func raiseOnlyFromComposing() {
        for phase in [BlockPresentation.Phase.hidden, .entering, .shown, .exiting] {
            var presentation = BlockPresentation(phase: phase)
            let raised = presentation.raise()
            #expect(raised == false)
            #expect(presentation.phase == phase)
        }
    }

    /// A block that turns around before the frame boundary arrives must not be raised by the
    /// stale completion.
    @Test("A raise after the block turned around is ignored")
    func staleRaiseIsIgnored() {
        var presentation = BlockPresentation(phase: .composing)
        _ = presentation.setPresent(false)
        #expect(presentation.phase == .exiting)

        let raised = presentation.raise()
        #expect(raised == false)
        #expect(presentation.phase == .exiting)
    }

    @Test("The last key drops the block")
    func exiting() {
        var presentation = BlockPresentation(isPresent: true)

        #expect(presentation.setPresent(false) == .exit)
        #expect(presentation.phase == .exiting)
        #expect(presentation.isRaised == false)

        presentation.finish(.exit)
        #expect(presentation.phase == .hidden)
        #expect(presentation.isRaised == false)
    }

    /// Every keystroke after the first reports presence again; restarting the entrance each
    /// time would make the block twitch under the typing.
    @Test("More content while shown changes nothing")
    func repeatedPresenceIsIgnored() {
        var shown = BlockPresentation(isPresent: true)
        #expect(shown.setPresent(true) == nil)
        #expect(shown.phase == .shown)

        var composing = BlockPresentation(isPresent: false)
        _ = composing.setPresent(true)
        #expect(composing.setPresent(true) == nil)
        #expect(composing.phase == .composing)
    }

    @Test("Staying empty changes nothing")
    func repeatedAbsenceIsIgnored() {
        var hidden = BlockPresentation(isPresent: false)
        #expect(hidden.setPresent(false) == nil)
        #expect(hidden.phase == .hidden)

        var exiting = BlockPresentation(isPresent: true)
        _ = exiting.setPresent(false)
        #expect(exiting.setPresent(false) == nil)
        #expect(exiting.phase == .exiting)
    }

    /// The interrupt case: a key lands while the block is dropping away.
    @Test("A key arriving mid-exit turns the block straight back around")
    func interruptedExit() {
        var presentation = BlockPresentation(isPresent: true)
        _ = presentation.setPresent(false)
        #expect(presentation.phase == .exiting)

        #expect(presentation.setPresent(true) == .enter)
        #expect(presentation.phase == .composing)
    }

    /// The exit's completion arrives on a timer, so it can land after the block has already
    /// turned around. It must not drag the block back down.
    @Test("A stale animation result cannot undo a newer turn")
    func staleFinishIsIgnored() {
        var presentation = BlockPresentation(isPresent: true)
        _ = presentation.setPresent(false)
        _ = presentation.setPresent(true)

        presentation.finish(.exit)

        #expect(presentation.phase == .composing)
    }

    @Test("A quick exit and re-entry ends up shown, once")
    func exitThenEnterSettlesShown() {
        var presentation = BlockPresentation(isPresent: true)
        _ = presentation.setPresent(false)
        _ = presentation.setPresent(true)
        _ = presentation.raise()
        presentation.finish(.enter)

        #expect(presentation.phase == .shown)
        #expect(presentation.isRaised)
    }
}

@Suite("Block Step")
struct BlockStepTests {
    private static let full = ["a", "b"]
    private static let empty: [String] = []

    /// The defect this replaced: the contents and the phase were decided in two steps, so the
    /// update in between drew emptied contents at full opacity — the backdrop squeezing shut
    /// before the block had begun to leave. One step, or the collapse comes back.
    @Test("The step that empties the content keeps drawing the old content")
    func emptyingKeepsTheOldContent() {
        let step = BlockPresentation.step(
            phase: .shown,
            snapshot: Self.full,
            live: Self.empty,
            isPresent: false)

        #expect(step.snapshot == Self.full)
        #expect(step.phase == .exiting)
        #expect(step.animation == .exit)
    }

    @Test("Nothing that is drawn is ever empty while the block is on its way out")
    func exitNeverDrawsEmpty() {
        var phase = BlockPresentation.Phase.shown
        var snapshot: [String]? = Self.full

        // Every update the state can produce once the keys are gone.
        for _ in 0..<5 {
            let step = BlockPresentation.step(
                phase: phase,
                snapshot: snapshot,
                live: Self.empty,
                isPresent: false)
            snapshot = step.snapshot
            phase = step.phase
            #expect(snapshot == Self.full)
        }
    }

    @Test("Content is followed while it is there")
    func presentContentIsFollowed() {
        let step = BlockPresentation.step(
            phase: .shown,
            snapshot: ["a"],
            live: Self.full,
            isPresent: true)

        #expect(step.snapshot == Self.full)
        #expect(step.phase == .shown)
        #expect(step.animation == nil)
    }

    @Test("Entering takes the fresh content in the same step")
    func enteringTakesFreshContent() {
        let step = BlockPresentation.step(
            phase: .hidden,
            snapshot: nil,
            live: Self.full,
            isPresent: true)

        #expect(step.snapshot == Self.full)
        #expect(step.phase == .composing)
        #expect(step.animation == .enter)
    }

    /// The blob: a backdrop drawn around an empty row reads as a small dark shape, and if it
    /// is on screen when the entrance starts, the entrance grows it into a keycap.
    @Test("A hidden block draws nothing at all")
    func hiddenBlockDrawsNothing() {
        let step = BlockPresentation.step(
            phase: .hidden,
            snapshot: nil,
            live: Self.empty,
            isPresent: false)

        #expect(step.snapshot == nil)
        #expect(step.phase == .hidden)
    }

    /// The stale ghost: contents that outlive their exit are still there at the next
    /// entrance, so the block starts from the previous keycap and morphs into the new one.
    @Test("The contents die with the exit")
    func contentsDieWithTheExit() {
        var presentation = BlockPresentation(phase: .exiting)
        presentation.finish(.exit)
        #expect(presentation.phase == .hidden)

        #expect(BlockPresentation.retained(Self.full, in: presentation.phase) == nil)
    }

    @Test("Contents survive every phase except hidden")
    func contentsSurviveUntilHidden() {
        for phase in [BlockPresentation.Phase.composing, .entering, .shown, .exiting] {
            #expect(BlockPresentation.retained(Self.full, in: phase) == Self.full)
        }
    }

    /// Re-entering after an exit must start from nothing, not from the previous keycap: the
    /// step has to hand over the fresh contents with no trace of what was there before.
    @Test("A fresh entrance after an exit starts from nothing")
    func reentryStartsClean() {
        var presentation = BlockPresentation(phase: .exiting)
        presentation.finish(.exit)
        let cleared = BlockPresentation.retained(Self.full, in: presentation.phase)

        let step = BlockPresentation.step(
            phase: presentation.phase,
            snapshot: cleared,
            live: ["z"],
            isPresent: true)

        #expect(step.snapshot == ["z"])
        #expect(step.animation == .enter)
    }

    /// A key landing mid-exit has to replace the held contents in the very step that turns
    /// the block around, or the entrance would play on the outgoing contents.
    @Test("A key arriving mid-exit swaps the held content for the live one")
    func interruptSwapsContent() {
        let step = BlockPresentation.step(
            phase: .exiting,
            snapshot: Self.full,
            live: ["c"],
            isPresent: true)

        #expect(step.snapshot == ["c"])
        #expect(step.phase == .composing)
        #expect(step.animation == .enter)
    }

    @Test("An empty block is never raised")
    func emptyBlockIsNeverRaised() {
        var presentation = BlockPresentation(isPresent: false)
        #expect(presentation.isRaised == false)

        _ = presentation.setPresent(true)
        _ = presentation.setPresent(false)
        presentation.finish(.exit)
        #expect(presentation.isRaised == false)
    }
}

@Suite("Animation Slow Motion")
struct AnimationSlowMotionTests {
    /// The switch exists so the next live pass can be watched frame by frame.
    @Test("Slow motion scales the block timings together")
    func slowMotionScalesBlockTimings() {
        let factor = KeypressTiming.slowMotion

        #expect(KeypressTiming.scaled(KeypressTiming.blockEnterDuration) == 0.18 * factor)
        #expect(KeypressTiming.scaled(KeypressTiming.blockExitDuration) == 0.2 * factor)
        #expect(KeypressTiming.scaled(KeypressTiming.windowExitDelay) == 0.24 * factor)
    }

    /// The distance the block travels is a layout constant, not a duration, so slow motion
    /// has nothing to say about it.
    ///
    /// Note this cannot prove the multiplier is *confined* to the block durations: the test
    /// process runs at 1, where scaled and unscaled values are identical. That the conveyor
    /// and press timings never read it is structural, not pinned here.
    @Test("The travel distance is not a duration and does not scale")
    func distanceIsNotADuration() {
        #expect(KeypressTiming.blockDropOffset == KeyCapSize.standard.height / 2)
        #expect(KeypressTiming.windowShrinkSettleDelay == .milliseconds(80))
    }

    @Test("Slow motion defaults to real time")
    func defaultsToRealTime() {
        // No key set in the test process, so the multiplier is the identity.
        #expect(KeypressTiming.slowMotion == 1)
    }
}

@Suite("Block Presentation Timing")
struct BlockPresentationTimingTests {
    /// The window may not order out over the tail of the drop.
    @Test("The window outlasts the exit it is waiting for")
    func windowOutlastsTheExit() {
        #expect(KeypressTiming.windowExitDelay > KeypressTiming.blockExitDuration)
    }

    @Test("Each animation reports its own curve's duration")
    func animationDurations() {
        #expect(BlockAnimation.enter.duration == KeypressTiming.scaled(KeypressTiming.blockEnterDuration))
        #expect(BlockAnimation.exit.duration == KeypressTiming.scaled(KeypressTiming.blockExitDuration))
    }

    /// The block moves by half a keycap, which has to stay well inside the window's shadow
    /// inset at every overlay size — otherwise the movement would need the window to resize.
    @Test("The drop stays inside the window's shadow inset")
    func dropFitsInsideTheInset() {
        let largest = OverlaySize.large.scaleFactor
        #expect(KeypressTiming.blockDropOffset * largest < 48)
        #expect(KeypressTiming.blockDropOffset == KeyCapSize.standard.height / 2)
    }
}
