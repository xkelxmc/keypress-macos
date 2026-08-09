import Foundation
import QuartzCore

// MARK: - AnimationTraceEvent

/// One thing the animation pipeline did, with when it did it.
///
/// The point of recording these is that the defects in this area are invisible to the tests
/// that would normally catch them: a layout read reports the model value, not what the render
/// server is drawing, so a keycap animating from the wrong place measures as perfect. A trace
/// says what transaction each piece actually ran in, and the analyzer below turns that into
/// pass or fail without anyone having to watch a screen recording frame by frame.
struct AnimationTraceEvent: Codable, Equatable {
    enum Kind: String, Codable {
        /// The block decided what to do about a change of contents or presence.
        case apply

        /// Contents put into final form while the block is still invisible.
        case compose

        /// The raise, issued on the frame after the composed one.
        case raise

        case exit

        /// The ribbon classified a row change.
        case conveyor

        /// A keycap's press state changed.
        case press

        /// The repeat badge's count changed.
        case repeatCount
    }

    var kind: Kind

    /// `CACurrentMediaTime` at the moment of the record.
    var time: TimeInterval

    /// Frame index derived from `time` and the display's refresh rate. Derived, not a display
    /// link tick — enough to tell "same frame" from "different frame", which is what the
    /// analyzer asks.
    var frame: Int

    var phaseIn: String?
    var phaseOut: String?

    /// Which animation the step chose, or `instant` when it deliberately chose none.
    var animation: String?

    var detail: String?
}

// MARK: - AnimationTraceViolation

/// A rule the pipeline is supposed to hold to, and did not.
enum AnimationTraceViolation: Equatable {
    /// A keycap animated its press while the block was raising it. Two animations moving the
    /// same leaf is exactly the stagger the block is supposed to prevent.
    case pressInsideRaise(frame: Int)

    /// The composed frame and the raise landed together, so the raise had the content change
    /// to carry as well as the movement.
    case composeAndRaiseInSameFrame(frame: Int)

    /// The row slid while the block was not settled.
    case conveyorOutsideSettled(frame: Int)

    /// A raise was never preceded by a compose.
    case raiseWithoutCompose(frame: Int)
}

// MARK: - AnimationTrace

/// Reads a trace and reports what went wrong. Pure, so it can be tested on traces written by
/// hand as well as on ones recorded from a real run.
enum AnimationTrace {
    static func violations(
        in events: [AnimationTraceEvent],
        enterDuration: TimeInterval = KeypressTiming.blockEnterDuration) -> [AnimationTraceViolation]
    {
        var violations: [AnimationTraceViolation] = []
        var lastComposeFrame: Int?
        var raiseWindow: (start: TimeInterval, end: TimeInterval)?

        for event in events {
            switch event.kind {
            case .compose:
                lastComposeFrame = event.frame

            case .raise:
                guard let composeFrame = lastComposeFrame else {
                    violations.append(.raiseWithoutCompose(frame: event.frame))
                    raiseWindow = (event.time, event.time + enterDuration)
                    continue
                }
                if composeFrame == event.frame {
                    violations.append(.composeAndRaiseInSameFrame(frame: event.frame))
                }
                lastComposeFrame = nil
                raiseWindow = (event.time, event.time + enterDuration)

            case .press:
                guard let window = raiseWindow,
                      event.time >= window.start,
                      event.time <= window.end,
                      event.animation != "instant"
                else {
                    continue
                }
                violations.append(.pressInsideRaise(frame: event.frame))

            case .conveyor:
                guard event.animation != "instant", event.phaseIn != "shown" else { continue }
                violations.append(.conveyorOutsideSettled(frame: event.frame))

            case .apply, .exit, .repeatCount:
                continue
            }
        }

        return violations
    }
}

// MARK: - AnimationJournal

/// Writes the trace, when asked to.
///
/// Off unless `KeypressAnimationJournal` is set, and deliberately not behind `#if DEBUG` — the
/// release build's view graph is the one whose behaviour is in question, so it has to be the
/// one that can be recorded.
///
/// ```
/// defaults write dev.keypress.app KeypressAnimationJournal -bool YES
/// ```
///
/// Lands in `~/Library/Caches/Keypress/`, one NDJSON file per launch.
@MainActor
final class AnimationJournal {
    static let shared = AnimationJournal()

    let isEnabled: Bool

    private let startedAt = CACurrentMediaTime()
    private let framesPerSecond: Double
    private var handle: FileHandle?
    private let encoder = JSONEncoder()

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "KeypressAnimationJournal")
        self.framesPerSecond = 60
        guard self.isEnabled else { return }
        self.handle = Self.makeFile()
    }

    func record(
        _ kind: AnimationTraceEvent.Kind,
        phaseIn: String? = nil,
        phaseOut: String? = nil,
        animation: String? = nil,
        detail: String? = nil)
    {
        guard self.isEnabled, let handle = self.handle else { return }

        let time = CACurrentMediaTime()
        let event = AnimationTraceEvent(
            kind: kind,
            time: time,
            frame: Int((time - self.startedAt) * self.framesPerSecond),
            phaseIn: phaseIn,
            phaseOut: phaseOut,
            animation: animation,
            detail: detail)

        guard var line = try? self.encoder.encode(event) else { return }
        line.append(0x0A)
        try? handle.write(contentsOf: line)
    }

    private static func makeFile() -> FileHandle? {
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask).first
        else {
            return nil
        }

        let directory = caches.appendingPathComponent("Keypress", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let name = "animation-\(Int(Date().timeIntervalSince1970)).ndjson"
        let url = directory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try? FileHandle(forWritingTo: url)
    }
}
