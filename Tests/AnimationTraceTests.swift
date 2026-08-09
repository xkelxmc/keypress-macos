import Foundation
import Testing
@testable import Keypress

private func event(
    _ kind: AnimationTraceEvent.Kind,
    time: TimeInterval,
    frame: Int,
    phaseIn: String? = nil,
    animation: String? = nil) -> AnimationTraceEvent
{
    AnimationTraceEvent(
        kind: kind,
        time: time,
        frame: frame,
        phaseIn: phaseIn,
        phaseOut: nil,
        animation: animation,
        detail: nil)
}

@Suite("Animation Trace")
struct AnimationTraceTests {
    private static let enterDuration: TimeInterval = 0.2

    /// What a healthy entrance looks like: compose on one frame, raise on the next, and any
    /// press that lands during the raise applies instantly rather than animating.
    @Test("A clean entrance reports nothing")
    func cleanEntrance() {
        let trace = [
            event(.apply, time: 0, frame: 0),
            event(.compose, time: 0, frame: 0),
            event(.raise, time: 0.017, frame: 1),
            event(.press, time: 0.05, frame: 3, phaseIn: "entering", animation: "instant"),
            event(.conveyor, time: 0.3, frame: 18, phaseIn: "shown", animation: "conveyor"),
        ]

        #expect(AnimationTrace.violations(in: trace, enterDuration: Self.enterDuration).isEmpty)
    }

    /// The composed frame has to be its own frame. Sharing one with the raise means the raise
    /// is carrying the content change as well as the movement — the defect that made a blob
    /// grow into a keycap.
    @Test("Compose and raise landing together is a violation")
    func composeAndRaiseTogether() {
        let trace = [
            event(.compose, time: 0, frame: 7),
            event(.raise, time: 0.001, frame: 7),
        ]

        #expect(
            AnimationTrace.violations(in: trace, enterDuration: Self.enterDuration)
                == [.composeAndRaiseInSameFrame(frame: 7)])
    }

    /// A keycap animating its press while the block is raising it is two animations moving
    /// the same leaf — exactly the stagger the block exists to prevent.
    @Test("A press animating inside the raise window is a violation")
    func pressInsideRaise() {
        let trace = [
            event(.compose, time: 0, frame: 0),
            event(.raise, time: 0.017, frame: 1),
            event(.press, time: 0.1, frame: 6, phaseIn: "entering", animation: "press"),
        ]

        #expect(
            AnimationTrace.violations(in: trace, enterDuration: Self.enterDuration)
                == [.pressInsideRaise(frame: 6)])
    }

    @Test("A press after the raise has finished is fine")
    func pressAfterRaise() {
        let trace = [
            event(.compose, time: 0, frame: 0),
            event(.raise, time: 0.017, frame: 1),
            event(.press, time: 0.5, frame: 30, phaseIn: "shown", animation: "press"),
        ]

        #expect(AnimationTrace.violations(in: trace, enterDuration: Self.enterDuration).isEmpty)
    }

    /// The row may only slide while the block is settled; anywhere else it would be dragging
    /// keycaps the block is already moving.
    @Test("A conveyor step outside the settled phase is a violation")
    func conveyorOutsideSettled() {
        let trace = [
            event(.conveyor, time: 0.05, frame: 3, phaseIn: "entering", animation: "conveyor"),
        ]

        #expect(
            AnimationTrace.violations(in: trace, enterDuration: Self.enterDuration)
                == [.conveyorOutsideSettled(frame: 3)])
    }

    @Test("A conveyor step that chose not to animate is fine in any phase")
    func instantConveyorIsAlwaysFine() {
        let trace = [
            event(.conveyor, time: 0.05, frame: 3, phaseIn: "exiting", animation: "instant"),
            event(.conveyor, time: 0.06, frame: 4, phaseIn: "composing", animation: "instant"),
        ]

        #expect(AnimationTrace.violations(in: trace, enterDuration: Self.enterDuration).isEmpty)
    }

    @Test("A raise with no compose before it is a violation")
    func raiseWithoutCompose() {
        let trace = [event(.raise, time: 0.017, frame: 1)]

        #expect(
            AnimationTrace.violations(in: trace, enterDuration: Self.enterDuration)
                == [.raiseWithoutCompose(frame: 1)])
    }

    @Test("Several entrances in a row are each judged on their own")
    func repeatedEntrances() {
        let trace = [
            event(.compose, time: 0, frame: 0),
            event(.raise, time: 0.017, frame: 1),
            event(.exit, time: 1, frame: 60),
            event(.compose, time: 2, frame: 120),
            event(.raise, time: 2.001, frame: 120),
        ]

        #expect(
            AnimationTrace.violations(in: trace, enterDuration: Self.enterDuration)
                == [.composeAndRaiseInSameFrame(frame: 120)])
    }

    @Test("An event round-trips through the journal's encoding")
    func eventRoundTrips() throws {
        let original = event(.press, time: 1.25, frame: 42, phaseIn: "shown", animation: "press")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnimationTraceEvent.self, from: data)

        #expect(decoded == original)
    }
}

@Suite("Animation Timing Source")
struct AnimationTimingSourceTests {
    /// Every animation in the overlay pipeline comes from `KeypressTiming`, so the debug
    /// multiplier stretches all of them together. A view that builds its own animation would
    /// keep running at full speed and make the slowed ones look wrong.
    @Test("No overlay view builds an animation of its own")
    func animationsComeFromTheTimingSource() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Keypress")

        let pipeline = [
            "Views/BlockPresentation.swift",
            "Views/ConveyorPace.swift",
            "Views/KeyCapView.swift",
            "Views/KeyVisualizationView.swift",
            "Views/HorizontalHistoryVisualizationView.swift",
            "Views/CommandZoneView.swift",
            "Views/TextEchoVisualizationView.swift",
            "Views/TypedTextRow.swift",
            "Overlay/OverlayWindow.swift",
        ]

        // Animation constructors that carry a tunable number with them.
        let inlineAnimations = [
            "easeOut(duration:",
            "easeIn(duration:",
            "easeInOut(duration:",
            "snappy(duration:",
            "spring(response:",
            "interpolatingSpring(stiffness:",
        ]

        for file in pipeline {
            let url = sources.appendingPathComponent(file)
            let contents = try String(contentsOf: url, encoding: .utf8)

            for (number, line) in contents
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
            {
                guard let found = inlineAnimations.first(where: { line.contains($0) }) else {
                    continue
                }
                Issue.record("\(file):\(number + 1) builds its own animation: \(found)")
            }
        }
    }
}
