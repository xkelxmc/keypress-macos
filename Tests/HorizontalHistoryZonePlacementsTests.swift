import CoreGraphics
import Foundation
import Testing
@testable import Keypress
@testable import KeypressCore

private let visibleHeight: CGFloat = 1000
private let step = HorizontalHistoryZonePlacements.nominalZoneHeight
    + HorizontalHistoryZonePlacements.spacing

/// Placements round-trip through normalized coordinates, so distances come back a few ulps
/// off the whole numbers they were derived from.
private func isClose(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
    abs(lhs - rhs) <= tolerance
}

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

    /// The moving zone's height only enters the bracketing case, where both zones get an
    /// explicit point. An anchored pair is separated by the height of the zone that stays,
    /// which is the command zone in every mode.
    @Test("A taller zone is bracketed further from its command zone")
    func tallerZoneWidensTheBracket() {
        let free = DisplayPlacement.custom(
            center: NormalizedPoint(x: 0.5, y: 0.5),
            fallbackAnchor: .bottomRight)

        let oneRow = HorizontalHistoryZonePlacements.derived(
            from: free,
            visibleHeight: visibleHeight)
        let threeLines = HorizontalHistoryZonePlacements.derived(
            from: free,
            visibleHeight: visibleHeight,
            primaryZoneHeight: 150)

        #expect(Self.verticalSeparation(threeLines) > Self.verticalSeparation(oneRow))
        // Half of each zone plus the gap: neither can reach into the other.
        #expect(
            Self.verticalSeparation(threeLines)
                >= (HorizontalHistoryZonePlacements.nominalZoneHeight + 150) / 2)
    }

    @Test("The text echo budgets all three of its lines")
    func textEchoBudgetsThreeLines() {
        #expect(
            KeyboardPresentation.stackedHistory.primaryZoneNominalHeight
                > KeyboardPresentation.horizontalHistory.primaryZoneNominalHeight)
        #expect(
            KeyboardPresentation.stackedHistory.primaryZoneNominalHeight
                >= TextEchoStyle.zoneHeight(lineCount: TextEchoState.maxLines))
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
    static func verticalSeparation(_ pair: HorizontalHistoryZonePlacements) -> CGFloat {
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

@Suite("Zone Layout Reconciliation")
struct ZoneLayoutReconciliationTests {
    private static let free = DisplayPlacement.custom(
        center: NormalizedPoint(x: 0.5, y: 0.5),
        fallbackAnchor: .bottomRight)

    private static let displayID = UUID()

    /// A display's stored state, assembled the way settings really hold it — so the marker's
    /// own "no marker but a pair means mode 2" inference is exercised too.
    private static func displays(
        laidOutFor: KeyboardPresentation?,
        placement: DisplayPlacement,
        commandZonePlacement: DisplayPlacement?) -> DisplaySettings
    {
        var displays = DisplaySettings()
        displays.setPlacement(placement, for: self.displayID)
        if let commandZonePlacement {
            displays.setCommandZonePlacement(commandZonePlacement, for: self.displayID)
        }
        if let laidOutFor {
            displays.setZoneLayoutPresentation(laidOutFor, for: self.displayID)
        }
        return displays
    }

    private static func plan(
        presentation: KeyboardPresentation,
        laidOutFor: KeyboardPresentation?,
        placement: DisplayPlacement,
        commandZonePlacement: DisplayPlacement?) -> ZoneLayoutPlan
    {
        ZoneLayoutPlan.resolve(
            presentation: presentation,
            displays: self.displays(
                laidOutFor: laidOutFor,
                placement: placement,
                commandZonePlacement: commandZonePlacement),
            displayID: self.displayID,
            scale: 1,
            visibleHeight: visibleHeight)
    }

    @Test("Latest has nothing to lay out")
    func latestHasNoZones() {
        #expect(
            Self.plan(
                presentation: .latest,
                laidOutFor: nil,
                placement: .defaultPlacement,
                commandZonePlacement: nil) == .none)
    }

    @Test("A display that has never carried a pair is derived from its widget placement")
    func firstTimeDerivation() {
        let plan = Self.plan(
            presentation: .horizontalHistory,
            laidOutFor: nil,
            placement: Self.free,
            commandZonePlacement: nil)

        guard case let .relayout(placements) = plan else {
            Issue.record("a display with no pair has to be laid out")
            return
        }
        #expect(placements == HorizontalHistoryZonePlacements.derived(
            from: Self.free,
            visibleHeight: visibleHeight))
    }

    /// A layout the running mode made is that mode's own, drags and all — the whole point of
    /// the marker is that a manual placement survives every later launch.
    @Test("A pair laid out by the running mode is adopted untouched")
    func sameModeKeepsManualPlacements() {
        for presentation in [KeyboardPresentation.horizontalHistory, .stackedHistory] {
            let dragged = DisplayPlacement.custom(
                center: NormalizedPoint(x: 0.2, y: 0.8),
                fallbackAnchor: .topLeft)
            #expect(
                Self.plan(
                    presentation: presentation,
                    laidOutFor: presentation,
                    placement: dragged,
                    commandZonePlacement: Self.free) == .adopt,
                "\(presentation) should keep its own layout")
        }
    }

    /// The bug this exists for: a free placement bracketed for one row of keycaps leaves the
    /// zones 88pt apart, and three plaques of text need 141pt — so the echo used to be drawn
    /// through the command zone.
    @Test("A mode-2 pair is re-derived wide enough for the echo's three lines")
    func modeTwoPairIsRelaidOutForTheEcho() {
        let modeTwo = HorizontalHistoryZonePlacements.derived(
            from: Self.free,
            visibleHeight: visibleHeight)
        #expect(isClose(HorizontalHistoryZonePlacementsTests.verticalSeparation(modeTwo), 88))

        let plan = Self.plan(
            presentation: .stackedHistory,
            laidOutFor: .horizontalHistory,
            placement: modeTwo.ribbon,
            commandZonePlacement: modeTwo.commandZone)

        guard case let .relayout(placements) = plan else {
            Issue.record("a mode-2 pair has to be re-derived for the echo")
            return
        }
        #expect(isClose(HorizontalHistoryZonePlacementsTests.verticalSeparation(placements), 141))
    }

    /// Symmetrical: going back leaves the ribbon its own, tighter pair rather than the echo's.
    @Test("Going back to mode 2 re-derives the pair again")
    func echoPairIsRelaidOutForTheRibbon() {
        let echoPair = HorizontalHistoryZonePlacements.derived(
            from: Self.free,
            visibleHeight: visibleHeight,
            primaryZoneHeight: KeyboardPresentation.stackedHistory.primaryZoneNominalHeight)

        let plan = Self.plan(
            presentation: .horizontalHistory,
            laidOutFor: .stackedHistory,
            placement: echoPair.ribbon,
            commandZonePlacement: echoPair.commandZone)

        guard case let .relayout(placements) = plan else {
            Issue.record("an echo pair has to be re-derived for the ribbon")
            return
        }
        #expect(isClose(HorizontalHistoryZonePlacementsTests.verticalSeparation(placements), 88))
    }

    /// Re-deriving reads the original spot back out of the pair, so switching back and forth
    /// cannot walk the layout across the screen.
    @Test("Switching modes repeatedly keeps the layout in the same place")
    func repeatedSwitchesDoNotDrift() {
        var placement = Self.free
        var commandZone: DisplayPlacement?
        var laidOutFor: KeyboardPresentation?
        var seen: [DisplayPlacement] = []

        for presentation in [
            KeyboardPresentation.horizontalHistory,
            .stackedHistory,
            .horizontalHistory,
            .stackedHistory,
        ] {
            guard case let .relayout(placements) = Self.plan(
                presentation: presentation,
                laidOutFor: laidOutFor,
                placement: placement,
                commandZonePlacement: commandZone)
            else {
                Issue.record("every mode change has to re-derive")
                return
            }
            placement = placements.ribbon
            commandZone = placements.commandZone
            laidOutFor = presentation
            seen.append(HorizontalHistoryZonePlacements.origin(
                primary: placements.ribbon,
                commandZone: placements.commandZone))
        }

        #expect(seen.allSatisfy { origin in
            guard case let .custom(center, _) = origin,
                  case let .custom(free, _) = Self.free
            else {
                return false
            }
            return isClose(CGFloat(center.x), CGFloat(free.x))
                && isClose(CGFloat(center.y), CGFloat(free.y))
        })
    }

    /// The upgrade path for someone who already ran mode 2: their settings carry a pair and no
    /// marker at all. Mode 2 has to leave that layout exactly where they left it, and mode 3
    /// has to re-derive it.
    @Test("A pair written before the marker existed is mode 2's")
    func absentMarkerIsAdoptedByModeTwoAndRelaidOutByModeThree() {
        let modeTwo = HorizontalHistoryZonePlacements.derived(
            from: Self.free,
            visibleHeight: visibleHeight)

        #expect(
            Self.plan(
                presentation: .horizontalHistory,
                laidOutFor: nil,
                placement: modeTwo.ribbon,
                commandZonePlacement: modeTwo.commandZone) == .adopt)

        guard case let .relayout(placements) = Self.plan(
            presentation: .stackedHistory,
            laidOutFor: nil,
            placement: modeTwo.ribbon,
            commandZonePlacement: modeTwo.commandZone)
        else {
            Issue.record("the echo has to re-derive a pair it did not lay out")
            return
        }
        #expect(isClose(HorizontalHistoryZonePlacementsTests.verticalSeparation(placements), 141))
    }

    /// Settings written before the marker existed carry a pair and no marker. That pair can
    /// only have come from the mode that had two zones first.
    @Test("A pair with no marker is read as mode 2's")
    func absentMarkerMeansModeTwo() throws {
        let displayID = UUID()
        var displays = DisplaySettings()
        displays.setPlacement(Self.free, for: displayID)
        displays.setCommandZonePlacement(Self.free, for: displayID)

        let legacy = try JSONDecoder().decode(
            DisplaySettings.self,
            from: JSONEncoder().encode(displays))

        #expect(legacy.zoneLayoutPresentations.isEmpty)
        #expect(legacy.zoneLayoutPresentation(for: displayID) == .horizontalHistory)
        #expect(legacy.zoneLayoutPresentation(for: UUID()) == nil)
    }

    @Test("The marker round-trips through settings")
    func markerRoundTrips() throws {
        let displayID = UUID()
        var displays = DisplaySettings()
        displays.setZoneLayoutPresentation(.stackedHistory, for: displayID)

        let decoded = try JSONDecoder().decode(
            DisplaySettings.self,
            from: JSONEncoder().encode(displays))

        #expect(decoded.zoneLayoutPresentation(for: displayID) == .stackedHistory)

        var cleared = decoded
        cleared.removeZoneLayoutPresentation(for: displayID)
        #expect(cleared.zoneLayoutPresentation(for: displayID) == nil)
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

    @Test("Both two-zone modes carry a second window, Latest does not")
    func windowCountPerPresentation() {
        #expect(KeyboardPresentation.horizontalHistory.usesSeparateCommandZoneWindow)
        #expect(KeyboardPresentation.stackedHistory.usesSeparateCommandZoneWindow)
        #expect(KeyboardPresentation.latest.usesSeparateCommandZoneWindow == false)
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
