import CoreGraphics
import Foundation
import KeypressCore

// MARK: - PlacementZoneSide

/// Which edge of the text ribbon the command zone lines up with.
enum PlacementZoneSide {
    case leading
    case center
    case trailing
}

// MARK: - PlacementZoneNeighbour

/// The other zone, as seen by the one being dragged.
///
/// Passing it into a drag lets the dragged zone stick to it. Sticking only decides where the
/// drop lands: each zone still stores a placement of its own and neither follows the other
/// afterwards.
struct PlacementZoneNeighbour: Equatable {
    let center: CGPoint
    let size: CGSize

    /// Gap the two zones keep when they stick together.
    var spacing: CGFloat = HorizontalHistoryZonePlacements.spacing
}

// MARK: - PlacementZoneGeometry

/// The placement editor's geometry, with no view attached.
///
/// Everything the editor does while dragging — turning a stored placement into an on-screen
/// centre, snapping to an anchor, keeping a zone on screen, deriving where the command zone
/// sits under the ribbon — is a pure function of the display's available frame and the size
/// of the preview being dragged. Keeping it out of the view is what makes it testable
/// without a window.
struct PlacementZoneGeometry: Equatable {
    /// The display's usable area, in the editor's own top-left-origin coordinate space.
    let availableFrame: CGRect

    /// Edge offsets an anchored placement keeps, taken from the display's own placement.
    let horizontalOffset: CGFloat
    let verticalOffset: CGFloat

    let snapThreshold: CGFloat
    let visualMargin: CGFloat

    /// Slack kept between a zone and the screen edge while dragging. Small on purpose: it is
    /// only there to keep a dragged zone from disappearing under the edge, and anything
    /// larger stops the user parking a zone in the very corner.
    static let defaultVisualMargin: CGFloat = 4

    init(
        availableFrame: CGRect,
        horizontalOffset: CGFloat = 20,
        verticalOffset: CGFloat = 20,
        snapThreshold: CGFloat = 32,
        visualMargin: CGFloat = PlacementZoneGeometry.defaultVisualMargin)
    {
        self.availableFrame = availableFrame
        self.horizontalOffset = horizontalOffset
        self.verticalOffset = verticalOffset
        self.snapThreshold = snapThreshold
        self.visualMargin = visualMargin
    }

    init(
        availableFrame: CGRect,
        resetPlacement: DisplayPlacement,
        snapThreshold: CGFloat = 32,
        visualMargin: CGFloat = PlacementZoneGeometry.defaultVisualMargin)
    {
        if case let .anchor(_, horizontalOffset, verticalOffset) = resetPlacement {
            self.init(
                availableFrame: availableFrame,
                horizontalOffset: CGFloat(horizontalOffset),
                verticalOffset: CGFloat(verticalOffset),
                snapThreshold: snapThreshold,
                visualMargin: visualMargin)
        } else {
            self.init(
                availableFrame: availableFrame,
                snapThreshold: snapThreshold,
                visualMargin: visualMargin)
        }
    }

    var availableFrameCenter: CGPoint {
        CGPoint(x: self.availableFrame.midX, y: self.availableFrame.midY)
    }

    // MARK: - Placement to centre

    func center(for placement: DisplayPlacement, previewSize: CGSize) -> CGPoint {
        switch placement {
        case let .anchor(position, _, _):
            self.anchorCenter(for: position, placement: placement, previewSize: previewSize)
        case let .custom(center, _):
            self.clamped(
                CGPoint(
                    x: self.availableFrame.minX + CGFloat(center.x) * self.availableFrame.width,
                    y: self.availableFrame.maxY - CGFloat(center.y) * self.availableFrame.height),
                previewSize: previewSize)
        }
    }

    func anchorCenter(
        for position: OverlayPosition,
        placement: DisplayPlacement? = nil,
        previewSize: CGSize) -> CGPoint
    {
        var horizontalOffset = self.horizontalOffset
        var verticalOffset = self.verticalOffset
        if case let .anchor(_, storedHorizontal, storedVertical)? = placement {
            horizontalOffset = CGFloat(storedHorizontal)
            verticalOffset = CGFloat(storedVertical)
        }

        let halfWidth = previewSize.width / 2
        let halfHeight = previewSize.height / 2
        let left = self.availableFrame.minX + horizontalOffset + halfWidth
        let centerX = self.availableFrame.midX
        let right = self.availableFrame.maxX - horizontalOffset - halfWidth
        let top = self.availableFrame.minY + verticalOffset + halfHeight
        let centerY = self.availableFrame.midY
        let bottom = self.availableFrame.maxY - verticalOffset - halfHeight

        let center = switch position {
        case .topLeft: CGPoint(x: left, y: top)
        case .topCenter: CGPoint(x: centerX, y: top)
        case .topRight: CGPoint(x: right, y: top)
        case .centerLeft: CGPoint(x: left, y: centerY)
        case .centerRight: CGPoint(x: right, y: centerY)
        case .bottomLeft: CGPoint(x: left, y: bottom)
        case .bottomCenter: CGPoint(x: centerX, y: bottom)
        case .bottomRight: CGPoint(x: right, y: bottom)
        }
        return self.clamped(center, previewSize: previewSize)
    }

    func clamped(_ center: CGPoint, previewSize: CGSize) -> CGPoint {
        let halfWidth = previewSize.width / 2 + self.visualMargin
        let halfHeight = previewSize.height / 2 + self.visualMargin
        guard self.availableFrame.width >= previewSize.width + self.visualMargin * 2,
              self.availableFrame.height >= previewSize.height + self.visualMargin * 2
        else {
            return self.availableFrameCenter
        }
        return CGPoint(
            x: min(
                max(center.x, self.availableFrame.minX + halfWidth),
                self.availableFrame.maxX - halfWidth),
            y: min(
                max(center.y, self.availableFrame.minY + halfHeight),
                self.availableFrame.maxY - halfHeight))
    }

    // MARK: - Centre to placement

    /// Where the dragged zone lands if it sticks to the other one: directly above or below
    /// it, one gap away, lined up on their centres or on either pair of edges.
    ///
    /// Returns nil unless the drag is already close to that arrangement. The horizontal
    /// alignment is only offered once the vertical one has taken, so a zone dragged far above
    /// its neighbour is never yanked sideways.
    func stickingCenter(
        draggedCenter: CGPoint,
        draggedSize: CGSize,
        neighbour: PlacementZoneNeighbour) -> CGPoint?
    {
        let halfHeights = neighbour.size.height / 2 + neighbour.spacing + draggedSize.height / 2
        let stackedYs = [neighbour.center.y - halfHeights, neighbour.center.y + halfHeights]

        guard let y = stackedYs.min(by: {
            abs($0 - draggedCenter.y) < abs($1 - draggedCenter.y)
        }), abs(y - draggedCenter.y) <= self.snapThreshold
        else {
            return nil
        }

        let alignedXs = [
            neighbour.center.x,
            neighbour.center.x - neighbour.size.width / 2 + draggedSize.width / 2,
            neighbour.center.x + neighbour.size.width / 2 - draggedSize.width / 2,
        ]
        let nearestX = alignedXs.min {
            abs($0 - draggedCenter.x) < abs($1 - draggedCenter.x)
        } ?? draggedCenter.x
        let x = abs(nearestX - draggedCenter.x) <= self.snapThreshold ? nearestX : draggedCenter.x

        return self.clamped(CGPoint(x: x, y: y), previewSize: draggedSize)
    }

    /// The placement a zone takes when the user drags its centre to `center`: stuck to the
    /// other zone when it lands beside it, an anchor when it lands near one, the display
    /// centre when it lands there, a free position otherwise.
    ///
    /// Sticking wins over the anchors, because parking a zone against its neighbour is the
    /// more specific intent and the gap between them has to come out exact.
    func placement(
        forDraggedCenter center: CGPoint,
        previewSize: CGSize,
        neighbour: PlacementZoneNeighbour? = nil) -> DisplayPlacement
    {
        if let neighbour, let stuck = self.stickingCenter(
            draggedCenter: center,
            draggedSize: previewSize,
            neighbour: neighbour)
        {
            return .custom(
                center: self.normalizedPoint(for: stuck),
                fallbackAnchor: self.nearestAnchor(to: stuck, previewSize: previewSize))
        }

        let clampedCenter = self.clamped(center, previewSize: previewSize)

        if hypot(
            self.availableFrameCenter.x - clampedCenter.x,
            self.availableFrameCenter.y - clampedCenter.y) <= self.snapThreshold
        {
            return .custom(
                center: NormalizedPoint(x: 0.5, y: 0.5),
                fallbackAnchor: self.nearestAnchor(to: clampedCenter, previewSize: previewSize))
        }

        if let snapped = OverlayPosition.allCases.first(where: { position in
            let snapCenter = self.anchorCenter(
                for: position,
                placement: self.snapPlacement(for: position),
                previewSize: previewSize)
            guard hypot(
                snapCenter.x - clampedCenter.x,
                snapCenter.y - clampedCenter.y) <= self.snapThreshold
            else {
                return false
            }
            return self.anchorAccepts(clampedCenter, at: position, anchorCenter: snapCenter)
        }) {
            return self.snapPlacement(for: snapped)
        }

        return .custom(
            center: self.normalizedPoint(for: clampedCenter),
            fallbackAnchor: self.nearestAnchor(to: clampedCenter, previewSize: previewSize))
    }

    /// Whether an anchor is still allowed to claim a drop that landed within its radius.
    ///
    /// An anchor sits one edge offset in from its corner, so the corner itself falls inside
    /// the magnet and used to be unreachable — every attempt to park there was pulled back
    /// out. The magnet therefore only pulls inwards: a drop pushed past the anchor towards
    /// the edge is the user reaching for the corner, and it is left where they put it.
    private func anchorAccepts(
        _ center: CGPoint,
        at position: OverlayPosition,
        anchorCenter: CGPoint) -> Bool
    {
        let tolerance: CGFloat = 0.5

        let horizontalIsInside = switch position {
        case .topLeft, .centerLeft, .bottomLeft:
            center.x >= anchorCenter.x - tolerance
        case .topRight, .centerRight, .bottomRight:
            center.x <= anchorCenter.x + tolerance
        case .topCenter, .bottomCenter:
            true
        }

        let verticalIsInside = switch position {
        case .topLeft, .topCenter, .topRight:
            center.y >= anchorCenter.y - tolerance
        case .bottomLeft, .bottomCenter, .bottomRight:
            center.y <= anchorCenter.y + tolerance
        case .centerLeft, .centerRight:
            true
        }

        return horizontalIsInside && verticalIsInside
    }

    func snapPlacement(for position: OverlayPosition) -> DisplayPlacement {
        .anchor(
            position: position,
            horizontalOffset: Double(self.horizontalOffset),
            verticalOffset: Double(self.verticalOffset))
    }

    func nearestAnchor(to center: CGPoint, previewSize: CGSize) -> OverlayPosition {
        OverlayPosition.allCases.min { lhs, rhs in
            let lhsCenter = self.anchorCenter(
                for: lhs,
                placement: self.snapPlacement(for: lhs),
                previewSize: previewSize)
            let rhsCenter = self.anchorCenter(
                for: rhs,
                placement: self.snapPlacement(for: rhs),
                previewSize: previewSize)
            return hypot(lhsCenter.x - center.x, lhsCenter.y - center.y) <
                hypot(rhsCenter.x - center.x, rhsCenter.y - center.y)
        } ?? .bottomRight
    }

    func normalizedPoint(for center: CGPoint) -> NormalizedPoint {
        NormalizedPoint(
            x: Double((center.x - self.availableFrame.minX) / self.availableFrame.width),
            y: Double((self.availableFrame.maxY - center.y) / self.availableFrame.height))
    }

    /// The placement to store, with an anchored zone's offsets measured from the edge it is
    /// anchored to so the overlay lands exactly where the preview stood.
    func placementForSaving(
        _ placement: DisplayPlacement,
        previewSize: CGSize) -> DisplayPlacement
    {
        let displayedCenter = self.center(for: placement, previewSize: previewSize)
        switch placement {
        case let .custom(_, fallbackAnchor):
            return .custom(
                center: self.normalizedPoint(for: displayedCenter),
                fallbackAnchor: fallbackAnchor)
        case let .anchor(position, horizontalOffset, verticalOffset):
            let halfWidth = previewSize.width / 2
            let halfHeight = previewSize.height / 2
            let savedHorizontalOffset = switch position {
            case .topLeft, .centerLeft, .bottomLeft:
                displayedCenter.x - halfWidth - self.availableFrame.minX
            case .topRight, .centerRight, .bottomRight:
                self.availableFrame.maxX - displayedCenter.x - halfWidth
            case .topCenter, .bottomCenter:
                CGFloat(horizontalOffset)
            }
            let savedVerticalOffset = switch position {
            case .topLeft, .topCenter, .topRight:
                displayedCenter.y - halfHeight - self.availableFrame.minY
            case .bottomLeft, .bottomCenter, .bottomRight:
                self.availableFrame.maxY - displayedCenter.y - halfHeight
            case .centerLeft, .centerRight:
                CGFloat(verticalOffset)
            }
            return .anchor(
                position: position,
                horizontalOffset: Double(max(0, savedHorizontalOffset)),
                verticalOffset: Double(max(0, savedVerticalOffset)))
        }
    }

    // MARK: - Stacked default

    /// Where the command zone sits while it has no placement of its own: directly under the
    /// ribbon, lined up on the side the overlay stacks it.
    func stackedCommandZoneCenter(
        ribbonCenter: CGPoint,
        ribbonSize: CGSize,
        commandZoneSize: CGSize,
        side: PlacementZoneSide,
        spacing: CGFloat) -> CGPoint
    {
        let x = switch side {
        case .leading:
            ribbonCenter.x - ribbonSize.width / 2 + commandZoneSize.width / 2
        case .trailing:
            ribbonCenter.x + ribbonSize.width / 2 - commandZoneSize.width / 2
        case .center:
            ribbonCenter.x
        }
        let y = ribbonCenter.y + ribbonSize.height / 2 + spacing + commandZoneSize.height / 2
        return self.clamped(CGPoint(x: x, y: y), previewSize: commandZoneSize)
    }
}

// MARK: - ZoneDragSession

/// Tracks one zone's drag.
///
/// A drag reports a translation measured from where it began, so the zone's position has to
/// be anchored to where it stood at that moment. The anchor is keyed by the gesture's own
/// `startLocation`, which is constant for the length of one drag and different for the next
/// one: a change carrying an unfamiliar start location begins a fresh grab. That is what
/// makes an abandoned drag harmless — if a gesture is cancelled and its `end()` never
/// arrives, the next drag still re-anchors instead of resuming against the old point.
struct ZoneDragSession: Equatable {
    private struct Grab: Equatable {
        /// Identity of the drag this anchor belongs to.
        let startLocation: CGPoint

        /// Where the zone stood when that drag began.
        let center: CGPoint
    }

    private var grab: Grab?

    var isDragging: Bool {
        self.grab != nil
    }

    /// Advances the drag and returns the zone's new placement.
    ///
    /// - Parameters:
    ///   - startLocation: the gesture's start location, which identifies this drag.
    ///   - currentCenter: where the zone stands right now, read only when a drag begins.
    ///   - translation: the drag's total translation since it began.
    mutating func placement(
        startLocation: CGPoint,
        currentCenter: @autoclosure () -> CGPoint,
        translation: CGSize,
        previewSize: CGSize,
        geometry: PlacementZoneGeometry,
        neighbour: PlacementZoneNeighbour? = nil) -> DisplayPlacement
    {
        let grab = if let existing = self.grab, existing.startLocation == startLocation {
            existing
        } else {
            Grab(startLocation: startLocation, center: currentCenter())
        }
        self.grab = grab

        return geometry.placement(
            forDraggedCenter: CGPoint(
                x: grab.center.x + translation.width,
                y: grab.center.y + translation.height),
            previewSize: previewSize,
            neighbour: neighbour)
    }

    mutating func end() {
        self.grab = nil
    }
}
