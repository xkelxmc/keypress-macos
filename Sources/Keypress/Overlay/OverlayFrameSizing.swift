import CoreGraphics
import Foundation

// MARK: - WindowFrameUpdate

/// What to do with the overlay window's frame after the content reports a new size.
enum WindowFrameUpdate: Equatable {
    /// Apply the new size straight away. The window may never be smaller than its content.
    case grow

    /// Keep the current frame and apply the new size only once the content settles.
    case deferShrink

    /// The frame already fits; leave it alone.
    case unchanged

    /// The overlay is on its way out. Do not touch the frame at all.
    case frozen
}

// MARK: - WindowFrameSizing

/// Decides whether a measured content size may move the window's frame.
///
/// The content animates, so its measured size arrives once per frame. Following it exactly
/// means resizing and repositioning the window on every one of those frames, which is what
/// made the overlay's exit stutter. The window therefore grows the moment it has to — content
/// must never be clipped — but only shrinks once the content has stopped changing, and never
/// moves at all while the overlay is fading out.
enum WindowFrameSizing {
    /// Sub-point differences are measurement noise, not a resize.
    static let tolerance: CGFloat = 0.5

    /// How long the size must hold still before a shrink is applied. Comfortably longer than
    /// a frame at 60Hz, so an animation in progress keeps postponing it.
    static var settleDelay: Duration {
        KeypressTiming.windowShrinkSettleDelay
    }

    static func update(
        current: CGSize,
        target: CGSize,
        isHiding: Bool) -> WindowFrameUpdate
    {
        guard !isHiding else { return .frozen }

        // A size that grows on either axis is applied whole: growth cannot wait, and the
        // window is never allowed to be the smaller of the two.
        if target.width > current.width + self.tolerance
            || target.height > current.height + self.tolerance
        {
            return .grow
        }

        if target.width < current.width - self.tolerance
            || target.height < current.height - self.tolerance
        {
            return .deferShrink
        }

        return .unchanged
    }
}

// MARK: - OverlayHideStyle

/// How the overlay leaves the screen.
enum OverlayHideStyle: Equatable {
    /// Let the content's fade play out, then order the window out. A key arriving in the
    /// meantime cancels it and the window stays.
    case graceful

    /// Order out now. Used wherever the overlay must be gone at once and an animation would
    /// be wrong — or would outlive the state it is animating.
    case immediate
}

// MARK: - OverlayHideReason

/// Why the overlay is being taken off screen.
///
/// Only one reason is an ordinary end to a keystroke; every other one is the overlay being
/// cut short by something outside it, where a lingering fade would be wrong.
enum OverlayHideReason: CaseIterable {
    /// The last key timed out — the normal, animated exit.
    case keysExpired

    /// Monitoring is stopping or the keyboard overlay was switched off.
    case stopping

    /// Secure input turned on: the overlay has to be gone immediately, not eventually.
    case secureInput

    /// The placement editor took over the screen.
    case placementEditor

    /// The mode changed and these windows are about to be replaced.
    case presentationChanged

    /// Sleep, wake or a lost event tap left the input state untrustworthy.
    case transientReset

    /// The display is no longer a target, so its window is going away.
    case displayNoLongerTargeted

    var style: OverlayHideStyle {
        switch self {
        case .keysExpired:
            .graceful
        case .stopping,
             .secureInput,
             .placementEditor,
             .presentationChanged,
             .transientReset,
             .displayNoLongerTargeted:
            .immediate
        }
    }
}
