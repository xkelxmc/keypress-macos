import CoreGraphics
import Foundation
import KeypressCore

// MARK: - OverlayZone

/// Which zone of a two-zone mode an overlay window carries.
///
/// The zones never share a window. Each has a placement of its own and appears or leaves on its
/// own, so neither can move the other by so much as a pixel.
enum OverlayZone: Equatable {
    /// What the mode is about: the horizontal ribbon, or the text echo.
    case primary

    /// The command zone, identical in every mode that has one.
    case commands
}

// MARK: - TextEchoFlow

/// Which way the echo's history travels.
///
/// The newest line always sits on the side the widget is anchored to, so the line being written
/// is the one closest to the screen edge and the older ones stack away from it. A widget in the
/// lower half of the screen therefore grows upwards, one in the upper half downwards — and a
/// line leaving drifts the same way the history does, out of the reader's way rather than
/// across the line they are reading.
enum TextEchoFlow: Equatable {
    /// Newest line at the bottom, history above it, dying lines drift up.
    case up

    /// Newest line at the top, history below it, dying lines drift down.
    case down

    /// Resolves the direction from where the text zone sits on its display.
    ///
    /// A free placement carries its centre as a fraction of the visible frame, so 0.5 already
    /// is the display's midpoint and no screen geometry has to be consulted.
    static func resolve(placement: DisplayPlacement) -> TextEchoFlow {
        switch placement {
        case let .anchor(position, _, _):
            switch position.verticalAnchor {
            case .bottom: .up
            case .top: .down
            // A centred zone has as much room either way; typing that grows upwards is the
            // one people already know from chat and terminal windows.
            case .center: .up
            }
        case let .custom(center, _):
            center.y < 0.5 ? .up : .down
        }
    }

    /// How far a leaving line travels, and in which direction.
    var driftDirection: CGFloat {
        switch self {
        case .up: -1
        case .down: 1
        }
    }
}
