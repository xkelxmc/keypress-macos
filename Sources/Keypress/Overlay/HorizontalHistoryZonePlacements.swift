import CoreGraphics
import Foundation
import KeypressCore

/// The pair of placements a two-zone keyboard mode uses on one display.
///
/// The two zones are separate windows with separate placements precisely so that neither can
/// shift the other when it appears. That only works if both placements are explicit, so the
/// first time such a mode runs on a display the pair is derived from whatever single placement
/// the display already had and written straight back into settings.
///
/// The derivation keeps the command zone where the widget already was and moves the mode's own
/// zone out of its way — never the reverse — so the spot the user originally chose stays
/// occupied.
struct HorizontalHistoryZonePlacements: Equatable {
    /// The mode's own zone: the horizontal ribbon, or the text echo.
    let ribbon: DisplayPlacement
    let commandZone: DisplayPlacement

    /// Height one row of keycaps occupies, used only to keep the zones apart. A keycap is 48pt
    /// tall, sits in a well up to 6pt deep, and the theme container adds about 12pt above and
    /// below. The result is an estimate on purpose: it has to separate the zones, not measure
    /// them. The command zone is one such row in every mode.
    static let nominalZoneHeight: CGFloat = 78

    /// Gap left between the two zones.
    static let spacing: CGFloat = 10

    /// Derives the pair.
    ///
    /// - Parameter primaryZoneHeight: how tall the mode's own zone is. It only matters when
    ///   both zones need an explicit point, because an anchored pair is separated by the
    ///   height of the zone that stays put — but the text echo is three lines tall, and a pair
    ///   spaced for one row would overlap.
    static func derived(
        from placement: DisplayPlacement,
        scale: CGFloat = 1,
        visibleHeight: CGFloat,
        primaryZoneHeight: CGFloat = HorizontalHistoryZonePlacements.nominalZoneHeight)
        -> HorizontalHistoryZonePlacements
    {
        let commandZoneHeight = self.nominalZoneHeight * scale
        let step = commandZoneHeight + self.spacing
        let bracketingStep = (commandZoneHeight + primaryZoneHeight * scale) / 2 + self.spacing

        switch placement {
        case let .anchor(position, horizontalOffset, verticalOffset):
            switch position.verticalAnchor {
            case .top, .bottom:
                // Both offsets are measured from the anchored edge, so pushing the mode's zone
                // one command zone further from that edge puts it beside the command zone:
                // below a top anchor, above a bottom one.
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
                    step: bracketingStep,
                    visibleHeight: visibleHeight)
            }

        case let .custom(center, fallbackAnchor):
            return self.bracketing(
                center: center,
                fallbackAnchor: fallbackAnchor,
                step: bracketingStep,
                visibleHeight: visibleHeight)
        }
    }

    /// The spot a pair was derived from, read back out of the pair itself.
    ///
    /// Deriving overwrites the display's single placement, so the widget's original spot is not
    /// stored anywhere — but the derivation is reversible, which is what lets a mode re-derive
    /// the pair for its own zone heights without the layout creeping across the screen every
    /// time the mode changes.
    static func origin(
        primary: DisplayPlacement,
        commandZone: DisplayPlacement) -> DisplayPlacement
    {
        switch (primary, commandZone) {
        case let (.custom(primaryCenter, _), .custom(commandCenter, fallbackAnchor)):
            // The pair straddles the point, so the point is halfway between them.
            .custom(
                center: NormalizedPoint(
                    x: commandCenter.x,
                    y: (primaryCenter.y + commandCenter.y) / 2),
                fallbackAnchor: fallbackAnchor)
        default:
            // An anchored pair left the command zone exactly where the widget was.
            commandZone
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

// MARK: - ZoneLayoutPlan

/// What a display's zone pair needs when a two-zone mode takes over.
enum ZoneLayoutPlan: Equatable {
    /// Nothing to do: the mode has no second zone.
    case none

    /// The pair on this display is already this mode's own. Leave every placement alone —
    /// including any the user dragged — and only record that it belongs to this mode.
    case adopt

    /// The pair was laid out for something else. Re-derive both placements for this mode's own
    /// zone heights.
    case relayout(HorizontalHistoryZonePlacements)
}

extension ZoneLayoutPlan {
    /// Decides what a display needs, given what is stored for it.
    ///
    /// Re-deriving discards a layout the user may have dragged by hand in the other mode. That
    /// is deliberate: the two modes need different amounts of room, and a pair spaced for one
    /// row of keycaps puts three lines of text straight through the command zone. A layout that
    /// moved is fixable by dragging; two zones drawn on top of each other are not.
    static func resolve(
        presentation: KeyboardPresentation,
        displays: DisplaySettings,
        displayID: UUID,
        scale: CGFloat,
        visibleHeight: CGFloat) -> ZoneLayoutPlan
    {
        guard presentation.usesSeparateCommandZoneWindow else { return .none }
        guard displays.zoneLayoutPresentation(for: displayID) != presentation else { return .adopt }

        let placement = displays.placement(for: displayID)
        let source = displays.commandZonePlacement(for: displayID).map {
            HorizontalHistoryZonePlacements.origin(primary: placement, commandZone: $0)
        } ?? placement

        return .relayout(HorizontalHistoryZonePlacements.derived(
            from: source,
            scale: scale,
            visibleHeight: visibleHeight,
            primaryZoneHeight: presentation.primaryZoneNominalHeight))
    }
}

// MARK: - KeyboardPresentation helpers

extension KeyboardPresentation {
    /// Whether the mode puts its command zone in a window of its own.
    ///
    /// Both two-zone modes do; Latest draws everything in one. This is what decides how many
    /// overlay windows a display carries.
    var usesSeparateCommandZoneWindow: Bool {
        switch self {
        case .horizontalHistory, .stackedHistory: true
        case .latest: false
        }
    }

    /// How tall the mode's own zone is, for keeping the two zones apart. The text echo budgets
    /// all three of its plaques and the gaps between them even before any of them exist: room
    /// allocated for one line is room the other two would land outside of.
    var primaryZoneNominalHeight: CGFloat {
        switch self {
        case .latest, .horizontalHistory:
            HorizontalHistoryZonePlacements.nominalZoneHeight
        case .stackedHistory:
            TextEchoStyle.zoneHeight(lineCount: TextEchoState.maxLines)
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
