import CoreGraphics
import Foundation
import Testing
@testable import Keypress
@testable import KeypressCore

private let visibleHeight: CGFloat = 1000
private let step = HorizontalHistoryZonePlacements.nominalZoneHeight
    + HorizontalHistoryZonePlacements.spacing

private func derived(_ placement: DisplayPlacement) -> HorizontalHistoryZonePlacements {
    HorizontalHistoryZonePlacements.derived(
        from: placement,
        visibleHeight: visibleHeight)
}

@Suite("Horizontal History Zone Placements")
struct HorizontalHistoryZonePlacementsTests {
    @Test("A bottom anchor keeps the command zone and lifts the ribbon clear of it")
    func bottomAnchor() {
        let placements = derived(
            .anchor(position: .bottomRight, horizontalOffset: 20, verticalOffset: 20))

        #expect(placements.commandZone == .anchor(
            position: .bottomRight,
            horizontalOffset: 20,
            verticalOffset: 20))
        // Offsets grow away from the anchored edge, so a larger one sits higher up.
        #expect(placements.ribbon == .anchor(
            position: .bottomRight,
            horizontalOffset: 20,
            verticalOffset: 20 + Double(step)))
    }

    @Test("A top anchor keeps the command zone and drops the ribbon below it")
    func topAnchor() {
        let placements = derived(
            .anchor(position: .topLeft, horizontalOffset: 32, verticalOffset: 12))

        #expect(placements.commandZone == .anchor(
            position: .topLeft,
            horizontalOffset: 32,
            verticalOffset: 12))
        #expect(placements.ribbon == .anchor(
            position: .topLeft,
            horizontalOffset: 32,
            verticalOffset: 12 + Double(step)))
    }

    @Test("Anchored zones keep the side they were on")
    func anchorKeepsSide() {
        for position in OverlayPosition.allCases {
            let placements = derived(
                .anchor(position: position, horizontalOffset: 20, verticalOffset: 20))

            guard case let .anchor(ribbonPosition, ribbonOffset, _) = placements.ribbon else {
                // Centred anchors become explicit points; their side is checked below.
                continue
            }
            #expect(ribbonPosition == position)
            #expect(ribbonOffset == 20)
        }
    }

    @Test("A centred anchor becomes two explicit points straddling the centre")
    func centerAnchor() {
        let placements = derived(
            .anchor(position: .centerLeft, horizontalOffset: 20, verticalOffset: 20))

        guard case let .custom(ribbonCenter, ribbonFallback) = placements.ribbon,
              case let .custom(commandCenter, commandFallback) = placements.commandZone
        else {
            Issue.record("centred anchors must resolve to explicit points")
            return
        }

        #expect(ribbonCenter.y > 0.5)
        #expect(commandCenter.y < 0.5)
        #expect(ribbonCenter.x == commandCenter.x)
        #expect(ribbonFallback == .centerLeft)
        #expect(commandFallback == .centerLeft)
    }

    @Test("A free placement splits into two points around the original spot")
    func customPlacement() {
        let original = NormalizedPoint(x: 0.42, y: 0.5)
        let placements = derived(.custom(center: original, fallbackAnchor: .bottomLeft))

        guard case let .custom(ribbonCenter, _) = placements.ribbon,
              case let .custom(commandCenter, _) = placements.commandZone
        else {
            Issue.record("a free placement must stay free")
            return
        }

        #expect(ribbonCenter.x == original.x)
        #expect(commandCenter.x == original.x)
        // The ribbon takes the upper half; NormalizedPoint counts y upwards.
        #expect(ribbonCenter.y > original.y)
        #expect(commandCenter.y < original.y)
    }

    @Test("The two zones never overlap, whatever the display placement was")
    func zonesNeverOverlap() {
        let placements: [DisplayPlacement] = OverlayPosition.allCases.map {
            .anchor(position: $0, horizontalOffset: 20, verticalOffset: 20)
        } + [
            .custom(center: NormalizedPoint(x: 0.5, y: 0.5), fallbackAnchor: .bottomRight),
            .custom(center: NormalizedPoint(x: 0.1, y: 0.9), fallbackAnchor: .topLeft),
        ]

        for placement in placements {
            let pair = derived(placement)
            let separation = Self.verticalSeparation(pair)
            #expect(
                separation >= HorizontalHistoryZonePlacements.nominalZoneHeight,
                "zones overlap for \(placement)")
        }
    }

    @Test("The larger overlay sizes push the zones further apart")
    func scaleWidensTheGap() {
        let anchor = DisplayPlacement.anchor(
            position: .bottomRight,
            horizontalOffset: 20,
            verticalOffset: 20)

        let small = HorizontalHistoryZonePlacements.derived(
            from: anchor,
            scale: 0.75,
            visibleHeight: visibleHeight)
        let large = HorizontalHistoryZonePlacements.derived(
            from: anchor,
            scale: 1.25,
            visibleHeight: visibleHeight)

        #expect(Self.verticalSeparation(large) > Self.verticalSeparation(small))
    }

    @Test("Deriving twice from the same placement gives the same answer")
    func derivationIsStable() {
        let anchor = DisplayPlacement.anchor(
            position: .bottomCenter,
            horizontalOffset: 20,
            verticalOffset: 20)

        #expect(derived(anchor) == derived(anchor))
    }

    /// How far apart the two zones' centres end up, in points.
    private static func verticalSeparation(_ pair: HorizontalHistoryZonePlacements) -> CGFloat {
        switch (pair.ribbon, pair.commandZone) {
        case let (.anchor(_, _, ribbonOffset), .anchor(_, _, commandOffset)):
            abs(CGFloat(ribbonOffset - commandOffset))
        case let (.custom(ribbonCenter, _), .custom(commandCenter, _)):
            abs(CGFloat(ribbonCenter.y - commandCenter.y)) * visibleHeight
        default:
            0
        }
    }
}

@Suite("Zone Independence")
struct ZoneIndependenceTests {
    /// The whole point of two windows: whatever the command zone does, the ribbon's
    /// placement — the only thing its window position is computed from — cannot change.
    @Test("The ribbon's placement is untouched by everything the command zone does")
    func ribbonPlacementIsIndependent() {
        let displayID = UUID()
        var displays = DisplaySettings()
        displays.setPlacement(
            .anchor(position: .bottomRight, horizontalOffset: 20, verticalOffset: 108),
            for: displayID)

        let ribbonPlacement = displays.placement(for: displayID)

        displays.setCommandZonePlacement(
            .anchor(position: .bottomRight, horizontalOffset: 20, verticalOffset: 20),
            for: displayID)
        #expect(displays.placement(for: displayID) == ribbonPlacement)

        displays.setCommandZonePlacement(
            .custom(center: NormalizedPoint(x: 0.9, y: 0.1), fallbackAnchor: .topLeft),
            for: displayID)
        #expect(displays.placement(for: displayID) == ribbonPlacement)

        displays.removeCommandZonePlacement(for: displayID)
        #expect(displays.placement(for: displayID) == ribbonPlacement)
    }

    @Test("Only horizontal history carries a second window")
    func windowCountPerPresentation() {
        #expect(KeyboardPresentation.horizontalHistory.usesSeparateCommandZoneWindow)
        #expect(KeyboardPresentation.latest.usesSeparateCommandZoneWindow == false)
        #expect(KeyboardPresentation.stackedHistory.usesSeparateCommandZoneWindow == false)
    }

    @Test("Each display migrates on its own")
    func migrationIsPerDisplay() {
        let first = UUID()
        let second = UUID()
        var displays = DisplaySettings()
        displays.setPlacement(
            .anchor(position: .topLeft, horizontalOffset: 20, verticalOffset: 20),
            for: first)

        let pair = HorizontalHistoryZonePlacements.derived(
            from: displays.placement(for: first),
            visibleHeight: visibleHeight)
        displays.setPlacement(pair.ribbon, for: first)
        displays.setCommandZonePlacement(pair.commandZone, for: first)

        #expect(displays.commandZonePlacement(for: first) != nil)
        #expect(displays.commandZonePlacement(for: second) == nil)
    }

    /// A stored command-zone placement is what marks a display as migrated, so a second pass
    /// has to leave the already-derived pair alone rather than deriving from it again.
    @Test("A migrated display is not migrated a second time")
    func migrationRunsOnce() {
        let displayID = UUID()
        var displays = DisplaySettings()
        displays.setPlacement(
            .anchor(position: .bottomRight, horizontalOffset: 20, verticalOffset: 20),
            for: displayID)

        func migrateIfNeeded() {
            guard displays.commandZonePlacement(for: displayID) == nil else { return }
            let pair = HorizontalHistoryZonePlacements.derived(
                from: displays.placement(for: displayID),
                visibleHeight: visibleHeight)
            displays.setPlacement(pair.ribbon, for: displayID)
            displays.setCommandZonePlacement(pair.commandZone, for: displayID)
        }

        migrateIfNeeded()
        let afterFirst = displays

        migrateIfNeeded()
        migrateIfNeeded()

        #expect(displays == afterFirst)
    }
}
