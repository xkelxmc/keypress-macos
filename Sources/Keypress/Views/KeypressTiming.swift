import Foundation
import KeypressCore
import SwiftUI

/// Every animation in the overlay, in one place.
///
/// Two reasons it is centralised rather than spread across the views. Animations that play
/// together have to be *slowed* together: a debug multiplier that stretches the block's
/// entrance but leaves the keycap press at full speed does not reveal a timing artefact, it
/// manufactures one. And a named constant is checkable — a test can assert no view invents an
/// animation of its own.
enum KeypressTiming {
    /// Stretches every animation so they can be watched frame by frame. Read once at launch
    /// from `KeypressAnimationSlowMotion`; 1 means normal speed.
    ///
    /// ```
    /// defaults write dev.keypress.app KeypressAnimationSlowMotion -float 10
    /// defaults delete dev.keypress.app KeypressAnimationSlowMotion
    /// ```
    static let slowMotion: Double = {
        let stored = UserDefaults.standard.double(forKey: "KeypressAnimationSlowMotion")
        return stored > 0 ? stored : 1
    }()

    /// Reads a number meant to be tuned by eye between launches.
    ///
    /// An unset key, a negative, or anything that is not a number at all reads as zero, which
    /// is never a meaningful value for a duration or a factor — so zero means "use the default"
    /// and everything else is taken but held inside `range`.
    static func tunable(_ stored: Double, default fallback: Double, in range: ClosedRange<Double>) -> Double {
        guard stored > 0 else { return fallback }
        return min(max(stored, range.lowerBound), range.upperBound)
    }

    private static func stored(
        _ key: String,
        default fallback: Double,
        in range: ClosedRange<Double>) -> Double
    {
        self.tunable(UserDefaults.standard.double(forKey: key), default: fallback, in: range)
    }

    /// Slows an animation without changing its shape, so springs stretch as faithfully as
    /// curves do.
    static func slowed(_ animation: Animation) -> Animation {
        self.slowMotion == 1 ? animation : animation.speed(1 / self.slowMotion)
    }

    /// Stretches a bare duration — for sleeps that have to outlast an animation.
    static func scaled(_ duration: TimeInterval) -> TimeInterval {
        duration * self.slowMotion
    }

    // MARK: - Block

    static let blockEnterDuration: TimeInterval = 0.18
    static let blockExitDuration: TimeInterval = 0.2

    /// How long the overlay window stays up after a zone empties.
    ///
    /// Longer than the exit itself: a zone's contents trail the key state by a frame, so the
    /// window has to hold past the animation's own length or it would order out over the last
    /// frame or two of the drop.
    static let windowExitDelay: TimeInterval = 0.24

    static var blockEnter: Animation {
        self.slowed(.easeOut(duration: self.blockEnterDuration))
    }

    static var blockExit: Animation {
        self.slowed(.easeIn(duration: self.blockExitDuration))
    }

    /// How far the block travels — half a standard keycap.
    ///
    /// Applied inside the overlay's scaled content, so it grows with the overlay size on its
    /// own, and it stays well within the window's shadow inset at every size: no window
    /// geometry is involved in the movement. A distance, so slow motion leaves it alone.
    static let blockDropOffset: CGFloat = 24

    // MARK: - Ribbon

    /// The conveyor: the whole row slides by one slot as a block.
    ///
    /// The curve is fixed; only its length moves, with the typing speed — see `ConveyorPace`.
    static func conveyor(duration: TimeInterval) -> Animation {
        self.slowed(.easeOut(duration: duration))
    }

    /// What the conveyor's length is allowed to be, and how quickly it follows the typing.
    ///
    /// Each number can be overridden at launch so the feel can be tuned without a rebuild;
    /// values are clamped, and anything unreadable falls back to the default here.
    ///
    /// ```
    /// defaults write dev.keypress.app KeypressConveyorMinDuration -float 0.05
    /// defaults write dev.keypress.app KeypressConveyorMaxDuration -float 0.12
    /// defaults write dev.keypress.app KeypressConveyorIntervalFactor -float 0.5
    /// defaults write dev.keypress.app KeypressConveyorQuietReset -float 0.5
    /// defaults write dev.keypress.app KeypressConveyorSmoothing -float 0.4
    /// ```
    static let conveyorTuning = ConveyorPace.Tuning(
        minDuration: stored("KeypressConveyorMinDuration", default: 0.05, in: 0.01...0.5),
        maxDuration: stored("KeypressConveyorMaxDuration", default: 0.12, in: 0.01...1),
        intervalFactor: stored("KeypressConveyorIntervalFactor", default: 0.5, in: 0.05...4),
        quietReset: stored("KeypressConveyorQuietReset", default: 0.5, in: 0.05...5),
        smoothing: stored("KeypressConveyorSmoothing", default: 0.4, in: 0.05...1))

    // MARK: - Keycap press

    static func press(_ effect: KeyboardPressEffect) -> Animation {
        let animation: Animation = switch effect {
        case .travel:
            .spring(response: 0.15, dampingFraction: 0.7)
        case .deepTravel:
            .spring(response: 0.24, dampingFraction: 0.62)
        case .compress:
            .spring(response: 0.14, dampingFraction: 0.82)
        case .scale:
            .easeOut(duration: 0.12)
        case .snap:
            .interpolatingSpring(stiffness: 520, damping: 30)
        case .glow:
            .spring(response: 0.2, dampingFraction: 0.58)
        }
        return self.slowed(animation)
    }

    // MARK: - Repeat badge

    static var badgePopRise: TimeInterval {
        self.scaled(0.08)
    }

    static var badgePopSettle: TimeInterval {
        self.scaled(0.22)
    }

    static let badgePopSpring = Spring(response: 0.18, dampingRatio: 0.55)

    // MARK: - Window geometry

    /// How long a measured content size must hold still before a shrink is applied. Not an
    /// animation — a debounce — so slow motion does not touch it.
    static let windowShrinkSettleDelay = Duration.milliseconds(80)
}
