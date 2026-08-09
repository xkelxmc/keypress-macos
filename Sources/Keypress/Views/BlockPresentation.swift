import Foundation
import QuartzCore
import SwiftUI

// MARK: - BlockAnimation

/// The two authored animations a block plays.
enum BlockAnimation: Equatable {
    /// Rises into place while fading in.
    case enter

    /// Drops away while fading out.
    case exit

    var duration: TimeInterval {
        switch self {
        case .enter: KeypressTiming.scaled(KeypressTiming.blockEnterDuration)
        case .exit: KeypressTiming.scaled(KeypressTiming.blockExitDuration)
        }
    }

    var curve: Animation {
        switch self {
        case .enter: KeypressTiming.blockEnter
        case .exit: KeypressTiming.blockExit
        }
    }
}

// MARK: - BlockContentChange

/// How a change of contents should be animated while the block is on screen.
///
/// The block's own entrance and exit are fixed, but what happens *inside* it between them is
/// the caller's business — the ribbon's conveyor, for one, decides per change whether the row
/// may slide or has to cut.
enum BlockContentChange: Equatable {
    case animated(Animation)
    case instant
}

// MARK: - BlockStep

/// Everything one update decides at once: what the block draws, what phase it is in, and
/// which animation carries it there.
///
/// `snapshot` is optional because a hidden block draws *nothing* — not a backdrop wrapped
/// around an empty row, which reads as a small dark blob for however long it is on screen.
struct BlockStep<Value: Equatable>: Equatable {
    var snapshot: Value?
    var phase: BlockPresentation.Phase
    var animation: BlockAnimation?
}

// MARK: - BlockPresentation

/// Whether a block is on screen, and what it is doing about it.
///
/// A block is the backdrop and its keys treated as one thing, so it has to animate as one
/// thing: when the last key goes, the block must still draw those keys for as long as the
/// exit takes, or the backdrop is left collapsing around nothing.
///
/// The contents and the phase are decided *together*. Deciding them in two steps means the
/// frame in between draws emptied contents at full opacity — the backdrop squeezing shut
/// before the block has begun to leave.
struct BlockPresentation: Equatable {
    enum Phase: Equatable {
        case hidden

        /// Contents are in their final form, but the block is still low and transparent.
        ///
        /// Its own frame, so that everything a new arrangement costs — building the keycaps,
        /// resizing the backdrop, growing the window around it — is spent while nothing is
        /// visible, and the raise that follows has nothing left to do but move.
        case composing

        case entering
        case shown
        case exiting
    }

    private(set) var phase: Phase

    init(isPresent: Bool) {
        self.phase = isPresent ? .shown : .hidden
    }

    init(phase: Phase) {
        self.phase = phase
    }

    /// Block sits at its resting position, fully opaque.
    var isRaised: Bool {
        self.phase == .entering || self.phase == .shown
    }

    /// Whether the block is settled — neither arriving nor leaving.
    ///
    /// Animations that belong to the contents rather than the block (a keycap press, the
    /// conveyor, the repeat badge) run only here. Anywhere else they would be competing with
    /// the block's own movement for the same leaves.
    var isSettled: Bool {
        self.phase == .shown
    }

    /// Decides the block's next state in one step.
    ///
    /// While content is present the snapshot follows it. The moment it is gone the snapshot
    /// **stops** following — the same step that turns the phase to exiting keeps the previous
    /// contents, so no update ever draws the emptied ones. Once the exit is over the contents
    /// are dropped: a hidden block holds nothing to morph out of next time.
    static func step<Value: Equatable>(
        phase: Phase,
        snapshot: Value?,
        live: Value,
        isPresent: Bool) -> BlockStep<Value>
    {
        var presentation = BlockPresentation(phase: phase)
        let animation = presentation.setPresent(isPresent)
        return BlockStep(
            snapshot: self.retained(isPresent ? live : snapshot, in: presentation.phase),
            phase: presentation.phase,
            animation: animation)
    }

    /// A hidden block holds nothing.
    ///
    /// Keeping the outgoing contents past the exit is what let a stale keycap reappear and
    /// morph into the next one; drawing a backdrop around an empty row is what made the blob.
    /// Both are the same rule, so both go through here.
    static func retained<Value>(_ snapshot: Value?, in phase: Phase) -> Value? {
        phase == .hidden ? nil : snapshot
    }

    /// Moves the block to match the presence of content, returning the animation to play.
    ///
    /// Returns nil when the block is already going the right way, so a run of key presses
    /// does not restart the enter animation on every one of them.
    mutating func setPresent(_ isPresent: Bool) -> BlockAnimation? {
        switch (self.phase, isPresent) {
        case (.hidden, true), (.exiting, true):
            // A key arriving mid-exit turns the block straight back around. The offset is an
            // absolute position rather than a delta, so reversing cannot accumulate.
            self.phase = .composing
            return .enter
        case (.shown, false), (.entering, false), (.composing, false):
            self.phase = .exiting
            return .exit
        case (.hidden, false), (.composing, true), (.entering, true), (.shown, true),
             (.exiting, false):
            return nil
        }
    }

    /// Records that an animation finished. Ignored if the block has since turned around.
    mutating func finish(_ animation: BlockAnimation) {
        switch (self.phase, animation) {
        case (.entering, .enter):
            self.phase = .shown
        case (.exiting, .exit):
            self.phase = .hidden
        default:
            break
        }
    }

    /// Leaves the composed frame behind and starts the raise. Ignored if the block turned
    /// around before the frame boundary arrived.
    mutating func raise() -> Bool {
        guard self.phase == .composing else { return false }
        self.phase = .entering
        return true
    }
}

extension EnvironmentValues {
    // What the surrounding block is doing, so its contents can hold still while it moves.
    @Entry var blockPhase: BlockPresentation.Phase = .shown
}

// MARK: - BlockPresentationView

/// Gives a block an authored entrance and exit.
///
/// The block rises into place as one unit and drops away as one unit — backdrop and keys
/// together, no stagger — moving by transform and opacity only.
///
/// Two things make it one unit rather than a crowd of leaves moving in loose formation.
/// `geometryGroup()` stops SwiftUI pushing the offset down to each leaf to resolve against
/// whatever transaction that leaf happens to be in — without it a keycap created or removed
/// mid-flight animates from the wrong place, or from nowhere. `compositingGroup()` makes the
/// fade one fade rather than one per leaf. Both sit *inside* the offset and opacity, which is
/// what puts the barrier at the block's boundary instead of the keycap's.
struct BlockPresentationView<Value: Equatable, Content: View>: View {
    let value: Value
    let isPresent: Bool

    /// How to animate a change of contents while the block is on screen.
    var contentChange: (Value, Value) -> BlockContentChange = { _, _ in .instant }

    @ViewBuilder let content: (Value) -> Content

    @State private var snapshot: Value?
    @State private var presentation: BlockPresentation
    @State private var finishTask: Task<Void, Never>?

    init(
        value: Value,
        isPresent: Bool,
        contentChange: @escaping (Value, Value) -> BlockContentChange = { _, _ in .instant },
        @ViewBuilder content: @escaping (Value) -> Content)
    {
        self.value = value
        self.isPresent = isPresent
        self.contentChange = contentChange
        self.content = content
        self._snapshot = State(initialValue: isPresent ? value : nil)
        self._presentation = State(initialValue: BlockPresentation(isPresent: isPresent))
    }

    /// The live inputs, as one value, so a single reaction covers both of them. Splitting them
    /// across two reactions is what let the phase and the contents disagree for a frame.
    private struct Input: Equatable {
        let value: Value
        let isPresent: Bool
    }

    var body: some View {
        Group {
            // A hidden block draws nothing at all — not a backdrop around an empty row.
            if let snapshot = self.snapshot {
                self.content(snapshot)
            }
        }
        .environment(\.blockPhase, self.presentation.phase)
        .geometryGroup()
        .compositingGroup()
        .opacity(self.presentation.isRaised ? 1 : 0)
        .offset(y: self.presentation.isRaised ? 0 : KeypressTiming.blockDropOffset)
        .onChange(of: Input(value: self.value, isPresent: self.isPresent)) { _, input in
            self.apply(input)
        }
        .onDisappear { self.finishTask?.cancel() }
    }

    private func apply(_ input: Input) {
        let step = BlockPresentation.step(
            phase: self.presentation.phase,
            snapshot: self.snapshot,
            live: input.value,
            isPresent: input.isPresent)

        AnimationJournal.shared.record(
            .apply,
            phaseIn: "\(self.presentation.phase)",
            phaseOut: "\(step.phase)",
            animation: step.animation.map { "\($0)" } ?? "none",
            detail: input.isPresent ? "present" : "absent")

        switch step.animation {
        case .enter:
            self.compose(step)
        case .exit:
            AnimationJournal.shared.record(.exit, phaseOut: "exiting")
            withAnimation(BlockAnimation.exit.curve) { self.commit(step) }
            self.scheduleFinish(.exit)
        case nil:
            self.changeContent(to: step)
        }
    }

    /// Puts the block in its final form, then raises it on the next committed frame.
    ///
    /// The contents land with animations off while the block is still transparent and low, so
    /// by the time anything is visible it already has the right keys at the right width and
    /// the window has already grown around them. Only opacity and offset are animated after
    /// that. Letting the content swap share the raise's transaction is what made a blob grow
    /// into a keycap, and an outgoing keycap morph into the next one.
    private func compose(_ step: BlockStep<Value>) {
        self.finishTask?.cancel()

        var composing = Transaction()
        composing.disablesAnimations = true
        withTransaction(composing) {
            self.snapshot = step.snapshot
            self.presentation = BlockPresentation(phase: .composing)
        }

        AnimationJournal.shared.record(.compose, phaseOut: "composing")

        // A real frame boundary, not a task hop: the completion block of the transaction this
        // update belongs to runs once that transaction has been committed, so the composed
        // frame is on screen before the raise is even issued.
        CATransaction.setCompletionBlock { self.raise() }
    }

    private func raise() {
        var presentation = self.presentation
        guard presentation.raise() else { return }

        AnimationJournal.shared.record(.raise, phaseIn: "composing", phaseOut: "entering")
        withAnimation(BlockAnimation.enter.curve) { self.presentation = presentation }
        self.scheduleFinish(.enter)
    }

    /// A change of contents while the block stays put — the conveyor's business, not ours.
    private func changeContent(to step: BlockStep<Value>) {
        guard step.snapshot != self.snapshot else { return }

        let animation: Animation? = if let old = self.snapshot, let new = step.snapshot {
            switch self.contentChange(old, new) {
            case let .animated(animation): animation
            case .instant: nil
            }
        } else {
            nil
        }

        // Only the contents move here. Writing the phase as well would invalidate the block
        // itself and let this transaction re-resolve its leaves — which is how a conveyor
        // step could reach in and drag a keycap that was busy rising.
        if let animation {
            withAnimation(animation) { self.snapshot = step.snapshot }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { self.snapshot = step.snapshot }
        }
    }

    private func scheduleFinish(_ animation: BlockAnimation) {
        self.finishTask?.cancel()
        self.finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(animation.duration))
            guard !Task.isCancelled else { return }
            self.presentation.finish(animation)
            // Whatever the block was showing dies with the exit.
            self.snapshot = BlockPresentation.retained(
                self.snapshot,
                in: self.presentation.phase)
        }
    }

    private func commit(_ step: BlockStep<Value>) {
        self.snapshot = step.snapshot
        self.presentation = BlockPresentation(phase: step.phase)
    }
}
