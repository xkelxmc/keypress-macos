import Foundation
import SwiftUI
import Testing
@testable import Keypress

/// The shipped numbers, so the cases below read as the feature rather than as arithmetic.
private let standard = ConveyorPace.Tuning(
    minDuration: 0.05,
    maxDuration: 0.12,
    intervalFactor: 0.5,
    quietReset: 0.5,
    smoothing: 0.4)

/// Types `count` keys `interval` apart, starting from a silence, and reports the duration of
/// the conveyor step each one triggered.
private func durations(
    typingEvery interval: TimeInterval,
    count: Int,
    tuning: ConveyorPace.Tuning = standard,
    startingAt start: TimeInterval = 100) -> [TimeInterval]
{
    var pace = ConveyorPace(tuning: tuning)
    return (0..<count).map { step in
        let time = start + Double(step) * interval
        pace.recordAppend(at: time)
        return pace.duration(at: time)
    }
}

/// The speed a steady stream of keys `interval` apart has settled on.
private func settledDuration(
    typingEvery interval: TimeInterval,
    count: Int = 40,
    tuning: ConveyorPace.Tuning = standard) -> TimeInterval
{
    durations(typingEvery: interval, count: count, tuning: tuning)
        .last ?? tuning.maxDuration
}

@Suite("Conveyor Pace")
struct ConveyorPaceTests {
    /// The whole point: at a fast pace the slide has to finish well before the next key, or the
    /// row never stops moving and its text cannot be read.
    @Test("Sustained fast typing halves the slide and leaves the row time to rest")
    func fastTypingLeavesTheRowAtRest() {
        let fast = settledDuration(typingEvery: 0.1)

        #expect(abs(fast - 0.05) < 0.001)
        #expect(fast < 0.1 / 2 + 0.001, "the row has to be still by the time the next key lands")
    }

    @Test("Typing faster than the floor holds at the floor")
    func veryFastTypingClampsAtTheFloor() {
        #expect(settledDuration(typingEvery: 0.06) == standard.minDuration)
        #expect(settledDuration(typingEvery: 0.02) == standard.minDuration)
    }

    /// Nothing changes for someone typing normally: they get the animation as authored.
    @Test("Relaxed typing keeps the full slide")
    func relaxedTypingStaysAtTheCeiling() {
        for interval in [0.25, 0.3, 0.4, 0.49] {
            let relaxed = durations(typingEvery: interval, count: 20)
            #expect(relaxed.allSatisfy { $0 == standard.maxDuration }, "at \(interval)s apart")
        }
    }

    /// Typing at exactly the gap the ceiling is defined by. The estimate sits on the boundary,
    /// where accumulated rounding can leave it a hair under, so this asks for the ceiling to
    /// within a nanosecond rather than to the last bit.
    @Test("Typing at the rest interval sits on the ceiling")
    func restIntervalTypingSitsOnTheCeiling() {
        let atRest = durations(typingEvery: standard.restInterval, count: 20)

        #expect(atRest.allSatisfy { abs($0 - standard.maxDuration) < 1e-9 })
    }

    /// Speed follows the typing, and only the typing: between the two extremes the slide is
    /// half the gap.
    @Test("In between, the slide is half the gap")
    func midRangeIsHalfTheInterval() {
        #expect(abs(settledDuration(typingEvery: 0.18) - 0.09) < 0.001)
        #expect(abs(settledDuration(typingEvery: 0.14) - 0.07) < 0.001)
    }

    /// The speed may never step: someone who types faster gets a shorter slide, always.
    @Test("A faster pace is never a slower slide")
    func fasterTypingNeverSlowsTheSlide() {
        let paces = stride(from: 0.06, through: 0.6, by: 0.02).map { interval in
            settledDuration(typingEvery: interval)
        }

        #expect(paces == paces.sorted())
    }

    /// A burst of two inside otherwise ordinary typing is not a change of pace, and the row
    /// must not lurch as if it were.
    @Test("One hurried pair barely moves the speed")
    func singleFastPairBarelyMoves() {
        var pace = ConveyorPace(tuning: standard)
        var time: TimeInterval = 100
        for _ in 0..<10 {
            pace.recordAppend(at: time)
            time += 0.3
        }
        let settled = pace.duration(at: time)

        // One key lands 40ms after its neighbour instead of 300ms.
        time += 0.04
        pace.recordAppend(at: time)
        let jolted = pace.duration(at: time)

        #expect(settled == standard.maxDuration)
        #expect(jolted > 0.09, "a single pair may nudge the speed, not change it")
    }

    /// A pause is the end of typing, not slow typing: whatever the last burst was, the key that
    /// breaks the silence gets the unhurried slide.
    @Test("A quiet gap resets the estimate")
    func quietGapResets() {
        var pace = Self.typed(20, every: 0.06, from: 100)
        #expect(pace.pace.duration(at: pace.time) == standard.minDuration)

        let broken = pace.time + standard.quietReset
        pace.pace.recordAppend(at: broken)

        #expect(pace.pace.duration(at: broken) == standard.maxDuration)
    }

    /// A pause that is not yet a silence is part of the rhythm and gets averaged in, so the
    /// speed drifts back towards the full slide instead of jumping to it.
    @Test("A gap short of the reset is averaged in, not thrown away")
    func gapBelowResetKeepsTheEstimate() {
        var pace = Self.typed(20, every: 0.06, from: 100)

        let resumed = pace.time + 0.2
        pace.pace.recordAppend(at: resumed)

        #expect(pace.pace.duration(at: resumed) > standard.minDuration)
        #expect(pace.pace.duration(at: resumed) < standard.maxDuration)
    }

    /// The head can also leave on its own timeout, long after the typing that set the pace.
    /// That step is not part of a burst and gets the full slide.
    @Test("A step out of a silence gets the full slide")
    func stepAfterSilenceIsUnhurried() {
        let pace = Self.typed(20, every: 0.06, from: 100)

        #expect(pace.pace.duration(at: pace.time) == standard.minDuration)
        #expect(pace.pace.duration(at: pace.time + 0.4) == standard.minDuration)
        #expect(pace.pace.duration(at: pace.time + 1.5) == standard.maxDuration)
    }

    /// A pace that has been typed into, and the moment of its last key.
    private static func typed(
        _ count: Int,
        every interval: TimeInterval,
        from start: TimeInterval) -> (pace: ConveyorPace, time: TimeInterval)
    {
        var pace = ConveyorPace(tuning: standard)
        var time = start
        for step in 0..<count {
            time = start + Double(step) * interval
            pace.recordAppend(at: time)
        }
        return (pace, time)
    }

    /// Before anything has been typed there is no rhythm to follow.
    @Test("The first key of a session gets the full slide")
    func firstKeyIsUnhurried() {
        var pace = ConveyorPace(tuning: standard)

        #expect(pace.duration(at: 100) == standard.maxDuration)
        pace.recordAppend(at: 100)
        #expect(pace.duration(at: 100) == standard.maxDuration)
    }

    /// Autorepeat, or two keys resolved in one frame: fast, but the arithmetic still has to
    /// stay inside the bounds.
    @Test("Keys landing in the same instant stay inside the bounds")
    func simultaneousAppendsStayBounded() {
        var pace = ConveyorPace(tuning: standard)
        for _ in 0..<10 {
            pace.recordAppend(at: 100)
        }

        #expect(pace.duration(at: 100) == standard.minDuration)
    }

    @Test("Every duration the mapping can produce is inside the bounds")
    func durationsAreAlwaysBounded() {
        for interval in stride(from: 0.0, through: 0.49, by: 0.01) {
            for duration in durations(typingEvery: interval, count: 25) {
                #expect(duration >= standard.minDuration)
                #expect(duration <= standard.maxDuration)
            }
        }
    }
}

@Suite("Conveyor Tuning")
struct ConveyorTuningTests {
    @Test("The shipped defaults are the ones the ribbon was tuned against")
    func shippedDefaults() {
        let tuning = KeypressTiming.conveyorTuning

        #expect(tuning.minDuration == 0.05)
        #expect(tuning.maxDuration == 0.12)
        #expect(tuning.intervalFactor == 0.5)
        #expect(tuning.quietReset == 0.5)
        #expect(tuning.smoothing == 0.4)
    }

    /// The ceiling is where the mapping and the authored animation meet: at the rest interval
    /// the row slides for exactly as long as it did before any of this existed.
    @Test("The rest interval is the gap that earns the full slide")
    func restIntervalYieldsTheCeiling() {
        let tuning = KeypressTiming.conveyorTuning

        #expect(tuning.restInterval == 0.24)
        #expect(tuning.duration(forInterval: tuning.restInterval) == tuning.maxDuration)
    }

    /// These come from `defaults`, where a stray minus sign or a string instead of a float is
    /// one keystroke away, and a zero-length or half-second conveyor step is not a thing the
    /// app should be able to be talked into.
    @Test("Nonsense values are pulled back into range")
    func valuesAreClamped() {
        let absurd = ConveyorPace.Tuning(
            minDuration: -3,
            maxDuration: 900,
            intervalFactor: 0,
            quietReset: -1,
            smoothing: 40)

        #expect(absurd.minDuration == 0.01)
        #expect(absurd.maxDuration == 1)
        #expect(absurd.intervalFactor == 0.05)
        #expect(absurd.quietReset == 0.05)
        #expect(absurd.smoothing == 1)
    }

    /// A ceiling below the floor would make the bounds an empty range, which is a crash, not a
    /// setting.
    @Test("A ceiling under the floor is lifted to meet it")
    func ceilingNeverFallsBelowFloor() {
        let inverted = ConveyorPace.Tuning(
            minDuration: 0.3,
            maxDuration: 0.05,
            intervalFactor: 0.5,
            quietReset: 0.5,
            smoothing: 0.4)

        #expect(inverted.minDuration == 0.3)
        #expect(inverted.maxDuration == 0.3)
        #expect(durations(typingEvery: 0.1, count: 10, tuning: inverted).allSatisfy { $0 == 0.3 })
    }

    /// `UserDefaults.double(forKey:)` reports zero for a missing key and for a value that is
    /// not a number, so zero is the only "not set" signal there is.
    @Test("An unreadable override falls back to the default")
    func unreadableOverridesFallBack() {
        #expect(KeypressTiming.tunable(0, default: 0.12, in: 0.01...1) == 0.12)
        #expect(KeypressTiming.tunable(-5, default: 0.12, in: 0.01...1) == 0.12)
        #expect(KeypressTiming.tunable(0.07, default: 0.12, in: 0.01...1) == 0.07)
        #expect(KeypressTiming.tunable(50, default: 0.12, in: 0.01...1) == 1)
    }

    /// Slow motion has to reach the conveyor as well, or watching a slowed run frame by frame
    /// would show the row snapping while everything around it crawls.
    @Test("Slow motion stretches the conveyor with everything else")
    func slowMotionAppliesToTheConveyor() {
        #expect(KeypressTiming.slowMotion == 1)
        #expect(
            KeypressTiming.conveyor(duration: 0.05)
                == KeypressTiming.slowed(.easeOut(duration: 0.05)))
    }

    /// The paced duration has to reach the animation. An easy way to lose it is to build the
    /// curve from a constant and pass the number nowhere.
    @Test("A different pace is a different animation")
    func durationReachesTheAnimation() {
        #expect(KeypressTiming.conveyor(duration: 0.05) != KeypressTiming.conveyor(duration: 0.12))
    }
}
