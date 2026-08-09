import CoreGraphics
import Foundation
import KeypressCore

/// The pair of placements the horizontal-history mode uses on one display.
///
/// The two zones are separate windows with separate placements precisely so that neither can
/// shift the other when it appears. That only works if both placements are explicit, so the
/// first time the mode runs on a display the pair is derived from whatever single placement
/// the display already had and written straight back into settings.
///
/// The derivation keeps the command zone where the widget already was and moves the ribbon
/// out of its way — never the reverse — so the spot the user originally chose stays occupied.
struct HorizontalHistoryZonePlacements: Equatable {
    let ribbon: DisplayPlacement
    let commandZone: DisplayPlacement

    /// Height one zone occupies, used only to keep the two apart. A keycap is 48pt tall, sits
    /// in a well up to 6pt deep, and the theme container adds about 12pt above and below.
    /// The result is an estimate on purpose: it has to separate the zones, not measure them.
    static let nominalZoneHeight: CGFloat = 78

    /// Gap left between the two zones.
    static let spacing: CGFloat = 10

    static func derived(
        from placement: DisplayPlacement,
        scale: CGFloat = 1,
        visibleHeight: CGFloat) -> HorizontalHistoryZonePlacements
    {
        let step = self.nominalZoneHeight * scale + self.spacing

        switch placement {
        case let .anchor(position, horizontalOffset, verticalOffset):
            switch position.verticalAnchor {
            case .top, .bottom:
                // Both offsets are measured from the anchored edge, so pushing the ribbon
                // one zone further from that edge puts it beside the command zone: below a
                // top anchor, above a bottom one.
                return HorizontalHistoryZonePlacements(
                    ribbon: .anchor(
                        position: position,
                        horizontalOffset: horizontalOffset,
                        verticalOffset: verticalOffset + Double(step)),
                    commandZone: placement)
            case .center:
                // A centred anchor ignores its vertical offset — the window centres itself —
                // so the only way to separate the two is to give both an explicit point.
                return self.bracketing(
                    center: NormalizedPoint(x: position.normalizedX, y: 0.5),
                    fallbackAnchor: position,
                    step: step,
                    visibleHeight: visibleHeight)
            }

        case let .custom(center, fallbackAnchor):
            return self.bracketing(
                center: center,
                fallbackAnchor: fallbackAnchor,
                step: step,
                visibleHeight: visibleHeight)
        }
    }

    /// Splits one free-standing point into two, ribbon above and command zone below, so the
    /// pair straddles the spot the widget used to occupy.
    private static func bracketing(
        center: NormalizedPoint,
        fallbackAnchor: OverlayPosition,
        step: CGFloat,
        visibleHeight: CGFloat) -> HorizontalHistoryZonePlacements
    {
        // NormalizedPoint counts y upwards, so the ribbon takes the larger value.
        let halfStep = visibleHeight > 0 ? Double(step / 2) / Double(visibleHeight) : 0
        return HorizontalHistoryZonePlacements(
            ribbon: .custom(
                center: NormalizedPoint(x: center.x, y: center.y + halfStep),
                fallbackAnchor: fallbackAnchor),
            commandZone: .custom(
                center: NormalizedPoint(x: center.x, y: center.y - halfStep),
                fallbackAnchor: fallbackAnchor))
    }
}

// MARK: - KeyboardPresentation helpers

extension KeyboardPresentation {
    /// Whether the mode puts its command zone in a window of its own.
    ///
    /// Only horizontal history splits into two windows; the other modes draw everything in
    /// one. This is what decides how many overlay windows a display carries.
    var usesSeparateCommandZoneWindow: Bool {
        switch self {
        case .horizontalHistory: true
        case .latest, .stackedHistory: false
        }
    }
}

// MARK: - OverlayPosition helpers

extension OverlayPosition {
    enum VerticalAnchor {
        case top
        case center
        case bottom
    }

    var verticalAnchor: VerticalAnchor {
        switch self {
        case .topLeft, .topCenter, .topRight: .top
        case .centerLeft, .centerRight: .center
        case .bottomLeft, .bottomCenter, .bottomRight: .bottom
        }
    }

    /// Where a zone anchored to this position sits across the display, as a fraction of the
    /// visible width.
    ///
    /// The edge offset is deliberately dropped: turning it into a fraction would need the
    /// zone's width, which changes with what is on screen. An edge-anchored zone lands
    /// against its edge once the window clamps it, which is what the anchor asked for.
    var normalizedX: Double {
        switch self {
        case .topLeft, .centerLeft, .bottomLeft: 0
        case .topCenter, .bottomCenter: 0.5
        case .topRight, .centerRight, .bottomRight: 1
        }
    }
}
