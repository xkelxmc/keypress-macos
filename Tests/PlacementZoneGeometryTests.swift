import CoreGraphics
import Foundation
import Testing
@testable import Keypress
@testable import KeypressCore

private let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
private let geometry = PlacementZoneGeometry(availableFrame: screen)
private let ribbonSize = CGSize(width: 260, height: 90)
private let commandZoneSize = CGSize(width: 160, height: 90)

@Suite("Placement Zone Geometry")
struct PlacementZoneGeometryTests {
    @Test("An anchored placement sits its own half-size in from the anchored edges")
    func anchorCenters() {
        let topLeft = geometry.center(
            for: .anchor(position: .topLeft, horizontalOffset: 20, verticalOffset: 20),
            previewSize: ribbonSize)
        #expect(topLeft == CGPoint(x: 20 + 130, y: 20 + 45))

        let bottomRight = geometry.center(
            for: .anchor(position: .bottomRight, horizontalOffset: 20, verticalOffset: 20),
            previewSize: ribbonSize)
        #expect(bottomRight == CGPoint(x: 1600 - 20 - 130, y: 1000 - 20 - 45))
    }

    @Test("Two zones of different sizes anchor by their own size, not a shared one")
    func anchorUsesOwnSize() {
        let placement = DisplayPlacement.anchor(
            position: .bottomLeft,
            horizontalOffset: 20,
            verticalOffset: 20)

        let ribbon = geometry.center(for: placement, previewSize: ribbonSize)
        let commandZone = geometry.center(for: placement, previewSize: commandZoneSize)

        #expect(ribbon.x == 20 + ribbonSize.width / 2)
        #expect(commandZone.x == 20 + commandZoneSize.width / 2)
        #expect(ribbon != commandZone)
    }

    @Test("A drag away from every anchor keeps the exact dragged position")
    func freeDragKeepsPosition() {
        let target = CGPoint(x: 700, y: 300)
        let placement = geometry.placement(forDraggedCenter: target, previewSize: ribbonSize)

        guard case .custom = placement else {
            Issue.record("expected a free placement, got \(placement)")
            return
        }
        #expect(geometry.center(for: placement, previewSize: ribbonSize) == target)
    }

    /// The magnet has to keep working when approached from the inside, which is every drop
    /// that is not a deliberate reach for the corner.
    @Test("A drop pushed past an anchor towards the edge is left alone")
    func anchorReleasesTowardsTheEdge() {
        let anchorCenter = geometry.anchorCenter(
            for: .bottomRight,
            placement: geometry.snapPlacement(for: .bottomRight),
            previewSize: ribbonSize)
        let pastIt = CGPoint(x: anchorCenter.x + 8, y: anchorCenter.y + 8)

        let placement = geometry.placement(forDraggedCenter: pastIt, previewSize: ribbonSize)

        guard case .custom = placement else {
            Issue.record("a drop past the anchor must keep its own position, got \(placement)")
            return
        }
    }

    @Test("A drag inside the snap radius takes the anchor")
    func dragSnapsToAnchor() {
        let anchorCenter = geometry.anchorCenter(
            for: .topRight,
            placement: geometry.snapPlacement(for: .topRight),
            previewSize: ribbonSize)
        let nudged = CGPoint(x: anchorCenter.x - 10, y: anchorCenter.y + 10)

        let placement = geometry.placement(forDraggedCenter: nudged, previewSize: ribbonSize)

        #expect(placement == geometry.snapPlacement(for: .topRight))
    }

    @Test("A drag onto the display centre snaps there")
    func dragSnapsToCentre() {
        let placement = geometry.placement(
            forDraggedCenter: CGPoint(x: 805, y: 495),
            previewSize: ribbonSize)

        guard case let .custom(center, _) = placement else {
            Issue.record("expected a centred placement, got \(placement)")
            return
        }
        #expect(abs(center.x - 0.5) < 0.001)
        #expect(abs(center.y - 0.5) < 0.001)
    }

    /// The clamp is the only thing between a dragged zone and the screen edge, and it is
    /// deliberately tight so a zone can be parked in the very corner.
    @Test("A zone dragged past the edge stops one small margin short of it")
    func dragClampsToScreen() {
        let margin = PlacementZoneGeometry.defaultVisualMargin
        let placement = geometry.placement(
            forDraggedCenter: CGPoint(x: -400, y: -400),
            previewSize: ribbonSize)
        let center = geometry.center(for: placement, previewSize: ribbonSize)

        #expect(center.x - ribbonSize.width / 2 == screen.minX + margin)
        #expect(center.y - ribbonSize.height / 2 == screen.minY + margin)
    }

    @Test("A zone dropped in the corner keeps a small offset, not a fat one")
    func cornerDropStaysTight() {
        let margin = PlacementZoneGeometry.defaultVisualMargin
        // Far from any anchor horizontally, so the anchor snap cannot claim this drop.
        let placement = geometry.placement(
            forDraggedCenter: CGPoint(x: screen.midX, y: -400),
            previewSize: ribbonSize)
        let center = geometry.center(for: placement, previewSize: ribbonSize)

        #expect(center.y - ribbonSize.height / 2 == screen.minY + margin)
    }

    @Test("Saving a placement and reading it back lands on the same point")
    func savingRoundTrips() {
        let placements: [DisplayPlacement] = [
            .anchor(position: .topLeft, horizontalOffset: 20, verticalOffset: 20),
            .anchor(position: .bottomRight, horizontalOffset: 48, verticalOffset: 64),
            .custom(center: NormalizedPoint(x: 0.31, y: 0.77), fallbackAnchor: .bottomLeft),
        ]

        for placement in placements {
            let saved = geometry.placementForSaving(placement, previewSize: ribbonSize)
            #expect(
                geometry.center(for: saved, previewSize: ribbonSize)
                    == geometry.center(for: placement, previewSize: ribbonSize))
        }
    }

    @Test("The stacked command zone sits under the ribbon with the gap between them")
    func stackedCommandZoneSitsBelowRibbon() {
        let ribbonCenter = CGPoint(x: 800, y: 400)

        let stacked = geometry.stackedCommandZoneCenter(
            ribbonCenter: ribbonCenter,
            ribbonSize: ribbonSize,
            commandZoneSize: commandZoneSize,
            side: .center,
            spacing: 10)

        let ribbonBottom = ribbonCenter.y + ribbonSize.height / 2
        #expect(stacked.y - commandZoneSize.height / 2 == ribbonBottom + 10)
        #expect(stacked.x == ribbonCenter.x)
    }

    @Test("The stacked command zone lines up with the requested side")
    func stackedCommandZoneSide() {
        let ribbonCenter = CGPoint(x: 800, y: 400)

        func stacked(_ side: PlacementZoneSide) -> CGPoint {
            geometry.stackedCommandZoneCenter(
                ribbonCenter: ribbonCenter,
                ribbonSize: ribbonSize,
                commandZoneSize: commandZoneSize,
                side: side,
                spacing: 10)
        }

        let leadingEdge = ribbonCenter.x - ribbonSize.width / 2
        let trailingEdge = ribbonCenter.x + ribbonSize.width / 2
        #expect(stacked(.leading).x - commandZoneSize.width / 2 == leadingEdge)
        #expect(stacked(.trailing).x + commandZoneSize.width / 2 == trailingEdge)
    }
}

@Suite("Zone Sticking")
struct ZoneStickingTests {
    private static let neighbourCenter = CGPoint(x: 800, y: 500)
    private static let neighbour = PlacementZoneNeighbour(
        center: neighbourCenter,
        size: commandZoneSize)

    private static var gap: CGFloat {
        commandZoneSize.height / 2 + neighbour.spacing + ribbonSize.height / 2
    }

    @Test("A zone dropped just above the other sticks one gap above it")
    func sticksAbove() throws {
        let target = CGPoint(x: Self.neighbourCenter.x, y: Self.neighbourCenter.y - Self.gap)
        let stuck = try #require(geometry.stickingCenter(
            draggedCenter: CGPoint(x: target.x + 6, y: target.y + 9),
            draggedSize: ribbonSize,
            neighbour: Self.neighbour))

        #expect(stuck == target)
    }

    @Test("A zone dropped just below the other sticks one gap below it")
    func sticksBelow() throws {
        let target = CGPoint(x: Self.neighbourCenter.x, y: Self.neighbourCenter.y + Self.gap)
        let stuck = try #require(geometry.stickingCenter(
            draggedCenter: CGPoint(x: target.x - 5, y: target.y - 11),
            draggedSize: ribbonSize,
            neighbour: Self.neighbour))

        #expect(stuck == target)
    }

    @Test("A near-centred drop lines the two centres up")
    func alignsCentres() throws {
        let stuck = try #require(geometry.stickingCenter(
            draggedCenter: CGPoint(
                x: Self.neighbourCenter.x + 7,
                y: Self.neighbourCenter.y - Self.gap),
            draggedSize: ribbonSize,
            neighbour: Self.neighbour))

        #expect(stuck.x == Self.neighbourCenter.x)
    }

    @Test("A drop near either shared edge lines those edges up")
    func alignsEdges() throws {
        let leadingEdge = Self.neighbourCenter.x - commandZoneSize.width / 2
        let trailingEdge = Self.neighbourCenter.x + commandZoneSize.width / 2

        let leading = try #require(geometry.stickingCenter(
            draggedCenter: CGPoint(
                x: leadingEdge + ribbonSize.width / 2 + 8,
                y: Self.neighbourCenter.y - Self.gap),
            draggedSize: ribbonSize,
            neighbour: Self.neighbour))
        #expect(leading.x - ribbonSize.width / 2 == leadingEdge)

        let trailing = try #require(geometry.stickingCenter(
            draggedCenter: CGPoint(
                x: trailingEdge - ribbonSize.width / 2 - 8,
                y: Self.neighbourCenter.y - Self.gap),
            draggedSize: ribbonSize,
            neighbour: Self.neighbour))
        #expect(trailing.x + ribbonSize.width / 2 == trailingEdge)
    }

    @Test("A zone far from the other does not stick")
    func noStickOutsideTheThreshold() {
        let farBelow = CGPoint(
            x: Self.neighbourCenter.x,
            y: Self.neighbourCenter.y + Self.gap + geometry.snapThreshold + 1)

        #expect(geometry.stickingCenter(
            draggedCenter: farBelow,
            draggedSize: ribbonSize,
            neighbour: Self.neighbour) == nil)
    }

    /// Vertical adjacency is what opens the door; a zone nowhere near the stacked position
    /// must not be dragged sideways just for being at a similar height.
    @Test("A sideways drop does not stick on the horizontal alone")
    func noStickOnHorizontalAlone() {
        #expect(geometry.stickingCenter(
            draggedCenter: CGPoint(x: Self.neighbourCenter.x + 4, y: Self.neighbourCenter.y),
            draggedSize: ribbonSize,
            neighbour: Self.neighbour) == nil)
    }

    @Test("Sticking works the same whichever zone is being dragged")
    func stickingIsSymmetric() throws {
        let ribbonNeighbour = PlacementZoneNeighbour(
            center: Self.neighbourCenter,
            size: ribbonSize)
        let gap = ribbonSize.height / 2 + ribbonNeighbour.spacing + commandZoneSize.height / 2
        let target = CGPoint(x: Self.neighbourCenter.x, y: Self.neighbourCenter.y + gap)

        let stuck = try #require(geometry.stickingCenter(
            draggedCenter: CGPoint(x: target.x + 5, y: target.y - 7),
            draggedSize: commandZoneSize,
            neighbour: ribbonNeighbour))

        #expect(stuck == target)
    }

    /// Sticking decides where the drop lands and nothing more — the zone still stores an
    /// ordinary independent placement.
    @Test("A stuck drop still saves as a placement of its own")
    func stuckDropSavesIndependently() {
        let target = CGPoint(x: Self.neighbourCenter.x, y: Self.neighbourCenter.y - Self.gap)
        let placement = geometry.placement(
            forDraggedCenter: CGPoint(x: target.x + 6, y: target.y + 9),
            previewSize: ribbonSize,
            neighbour: Self.neighbour)

        guard case .custom = placement else {
            Issue.record("a stuck drop is a position of its own, got \(placement)")
            return
        }
        #expect(geometry.center(for: placement, previewSize: ribbonSize) == target)
    }

    @Test("Without a neighbour the drag behaves exactly as before")
    func noNeighbourKeepsOldBehaviour() {
        let target = CGPoint(x: Self.neighbourCenter.x + 6, y: Self.neighbourCenter.y - Self.gap + 9)

        #expect(
            geometry.placement(forDraggedCenter: target, previewSize: ribbonSize)
                == geometry.placement(
                    forDraggedCenter: target,
                    previewSize: ribbonSize,
                    neighbour: nil))
    }
}

@Suite("Zone Drag Session")
struct ZoneDragSessionTests {
    private static let start = DisplayPlacement.anchor(
        position: .topLeft,
        horizontalOffset: 20,
        verticalOffset: 20)

    /// Stands in for one SwiftUI drag: a start location that stays put for the drag's whole
    /// life, which is what tells the session one drag from the next.
    private static let firstDrag = CGPoint(x: 400, y: 400)
    private static let secondDrag = CGPoint(x: 900, y: 250)

    /// Every drag has to begin exactly where the zone is standing, or the zone jumps on the
    /// first pixel of movement.
    @Test("A drag tracks the cursor from its first pixel")
    func dragTracksFromFirstPixel() {
        var session = ZoneDragSession()
        let origin = geometry.center(for: Self.start, previewSize: ribbonSize)

        let placement = session.placement(
            startLocation: Self.firstDrag,
            currentCenter: origin,
            translation: CGSize(width: 300, height: 200),
            previewSize: ribbonSize,
            geometry: geometry)

        #expect(
            geometry.center(for: placement, previewSize: ribbonSize)
                == CGPoint(x: origin.x + 300, y: origin.y + 200))
    }

    @Test("Later changes in one drag stay relative to the original grab point")
    func dragUsesOneGrabPoint() {
        var session = ZoneDragSession()
        let origin = geometry.center(for: Self.start, previewSize: ribbonSize)

        _ = session.placement(
            startLocation: Self.firstDrag,
            currentCenter: origin,
            translation: CGSize(width: 100, height: 100),
            previewSize: ribbonSize,
            geometry: geometry)
        // The zone has moved, so a fresh reading of "where it stands" would be wrong here —
        // the session must keep using the point the drag began from.
        let placement = session.placement(
            startLocation: Self.firstDrag,
            currentCenter: CGPoint(x: 9999, y: 9999),
            translation: CGSize(width: 300, height: 200),
            previewSize: ribbonSize,
            geometry: geometry)

        #expect(
            geometry.center(for: placement, previewSize: ribbonSize)
                == CGPoint(x: origin.x + 300, y: origin.y + 200))
    }

    @Test("A second drag starts from where the first one left the zone")
    func secondDragStartsFresh() {
        var session = ZoneDragSession()
        let origin = geometry.center(for: Self.start, previewSize: ribbonSize)

        let afterFirst = session.placement(
            startLocation: Self.firstDrag,
            currentCenter: origin,
            translation: CGSize(width: 400, height: 260),
            previewSize: ribbonSize,
            geometry: geometry)
        session.end()
        #expect(session.isDragging == false)

        let restingCenter = geometry.center(for: afterFirst, previewSize: ribbonSize)
        let afterSecond = session.placement(
            startLocation: Self.secondDrag,
            currentCenter: restingCenter,
            translation: CGSize(width: 50, height: -30),
            previewSize: ribbonSize,
            geometry: geometry)

        #expect(
            geometry.center(for: afterSecond, previewSize: ribbonSize)
                == CGPoint(x: restingCenter.x + 50, y: restingCenter.y - 30))
    }

    /// A cancelled gesture never delivers its end, so the session is still holding the old
    /// drag's anchor when the next one starts — the failure mode a mid-drag view teardown
    /// used to cause. Note there is deliberately no `end()` call here.
    @Test("A drag that never ends does not poison the next drag")
    func abandonedDragDoesNotPoisonTheNext() {
        var session = ZoneDragSession()
        let origin = geometry.center(for: Self.start, previewSize: ribbonSize)

        let abandoned = session.placement(
            startLocation: Self.firstDrag,
            currentCenter: origin,
            translation: CGSize(width: 500, height: 300),
            previewSize: ribbonSize,
            geometry: geometry)
        #expect(session.isDragging)

        let restingCenter = geometry.center(for: abandoned, previewSize: ribbonSize)
        let resumed = session.placement(
            startLocation: Self.secondDrag,
            currentCenter: restingCenter,
            translation: CGSize(width: 10, height: 10),
            previewSize: ribbonSize,
            geometry: geometry)

        #expect(
            geometry.center(for: resumed, previewSize: ribbonSize)
                == CGPoint(x: restingCenter.x + 10, y: restingCenter.y + 10))
    }

    @Test("Each zone drags on its own session and its own size")
    func zonesDragIndependently() {
        var ribbonSession = ZoneDragSession()
        var commandZoneSession = ZoneDragSession()
        // Well clear of the edges and the snap points, so the test sees only the two
        // sessions and not the clamp.
        let ribbonOrigin = geometry.center(
            for: .custom(center: NormalizedPoint(x: 0.35, y: 0.62), fallbackAnchor: .topLeft),
            previewSize: ribbonSize)
        let commandOrigin = geometry.stackedCommandZoneCenter(
            ribbonCenter: ribbonOrigin,
            ribbonSize: ribbonSize,
            commandZoneSize: commandZoneSize,
            side: .leading,
            spacing: 10)

        let commandPlacement = commandZoneSession.placement(
            startLocation: Self.firstDrag,
            currentCenter: commandOrigin,
            translation: CGSize(width: 120, height: 40),
            previewSize: commandZoneSize,
            geometry: geometry)
        let ribbonPlacement = ribbonSession.placement(
            startLocation: Self.secondDrag,
            currentCenter: ribbonOrigin,
            translation: CGSize(width: -30, height: 70),
            previewSize: ribbonSize,
            geometry: geometry)

        #expect(
            geometry.center(for: commandPlacement, previewSize: commandZoneSize)
                == CGPoint(x: commandOrigin.x + 120, y: commandOrigin.y + 40))
        #expect(
            geometry.center(for: ribbonPlacement, previewSize: ribbonSize)
                == CGPoint(x: ribbonOrigin.x - 30, y: ribbonOrigin.y + 70))
    }
}
