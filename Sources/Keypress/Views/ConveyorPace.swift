import Foundation
import QuartzCore

// MARK: - ConveyorPace

/// How long the ribbon's conveyor step may take, given how fast the keys are arriving.
///
/// The row has to come to rest between keystrokes or its text cannot be read: at a hundred
/// milliseconds a key, a slide authored for a relaxed pace is still running when the next one
/// starts, so the ribbon is never still. The fix is not a second, snappier mode — a row that
/// changed character at some invisible threshold would read as a glitch. The slide simply gets
/// shorter as the gaps close, continuously, and returns to its full length as they open again.
///
/// The intervals are smoothed, so one hurried pair does not jerk the speed, and a pause resets
/// the estimate: the first key after a silence is a relaxed key, whatever came before it.
struct ConveyorPace: Equatable {
    // MARK: Tuning

    /// The mapping's four numbers, held apart from the pace itself so they can be overridden
    /// at launch and pinned by tests. Every one is clamped: these come from `defaults`, where
    /// a typo is a matter of one keystroke.
    struct Tuning: Equatable {
        let minDuration: TimeInterval
        let maxDuration: TimeInterval
        let intervalFactor: Double
        let quietReset: TimeInterval
        let smoothing: Double

        init(
            minDuration: TimeInterval,
            maxDuration: TimeInterval,
            intervalFactor: Double,
            quietReset: TimeInterval,
            smoothing: Double)
        {
            let low = minDuration.clamped(to: 0.01...0.5)
            self.minDuration = low
            self.maxDuration = maxDuration.clamped(to: low...1)
            self.intervalFactor = intervalFactor.clamped(to: 0.05...4)
            self.quietReset = quietReset.clamped(to: 0.05...5)
            self.smoothing = smoothing.clamped(to: 0.05...1)
        }

        /// The gap at which the row already gets its full, unhurried slide. Also what the
        /// estimate is reset to, so recovering from a pause starts relaxed and speeds up over
        /// a few keys rather than snapping to whatever the first two keys happened to be.
        var restInterval: TimeInterval {
            self.maxDuration / self.intervalFactor
        }

        /// Half a gap by default: the slide finishes, then the row rests, then the next key.
        func duration(forInterval interval: TimeInterval) -> TimeInterval {
            (self.intervalFactor * interval).clamped(to: self.minDuration...self.maxDuration)
        }
    }

    // MARK: Stored

    let tuning: Tuning

    private var smoothedInterval: TimeInterval
    private var lastAppend: TimeInterval?
    private var pacedDuration: TimeInterval

    init(tuning: Tuning) {
        self.tuning = tuning
        self.smoothedInterval = tuning.restInterval
        self.pacedDuration = tuning.maxDuration
    }

    // MARK: Use

    /// Takes in the moment a key was appended to the row.
    ///
    /// A gap of `quietReset` or more is not slow typing, it is the end of typing: the estimate
    /// is thrown away rather than averaged with what follows.
    mutating func recordAppend(at time: TimeInterval) {
        defer { self.lastAppend = time }

        guard let last = self.lastAppend, time - last < self.tuning.quietReset else {
            self.smoothedInterval = self.tuning.restInterval
            self.pacedDuration = self.tuning.maxDuration
            return
        }

        let interval = max(time - last, 0)
        let alpha = self.tuning.smoothing
        self.smoothedInterval = alpha * interval + (1 - alpha) * self.smoothedInterval
        self.pacedDuration = self.tuning.duration(forInterval: self.smoothedInterval)
    }

    /// How long a conveyor step happening at `time` should take.
    ///
    /// Not every step is an append — a head can also leave on its own timeout — and by then the
    /// typing that set the current pace is long over, so a step out of a silence gets the full
    /// slide regardless of how fast the last burst was.
    func duration(at time: TimeInterval) -> TimeInterval {
        guard let last = self.lastAppend, time - last < self.tuning.quietReset else {
            return self.tuning.maxDuration
        }
        return self.pacedDuration
    }
}

// MARK: - ConveyorPacer

/// Holds a `ConveyorPace` across view rebuilds, and reads the clock for it.
///
/// A reference on purpose: the pace decides how long a transaction lasts and is never drawn,
/// so recording a keystroke must not invalidate the view that owns it.
@MainActor
final class ConveyorPacer {
    private var pace: ConveyorPace
    private let now: () -> TimeInterval

    init(
        tuning: ConveyorPace.Tuning = KeypressTiming.conveyorTuning,
        now: @escaping () -> TimeInterval = { CACurrentMediaTime() })
    {
        self.pace = ConveyorPace(tuning: tuning)
        self.now = now
    }

    /// The duration for the conveyor step about to run, counting it as a keystroke when the
    /// row actually gained a key.
    func duration(appended: Bool) -> TimeInterval {
        let time = self.now()
        if appended {
            self.pace.recordAppend(at: time)
        }
        return self.pace.duration(at: time)
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
