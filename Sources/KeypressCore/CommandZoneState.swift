import CoreGraphics
import Foundation

// MARK: - CommandZoneState

/// The command zone shared by every two-zone keyboard mode.
///
/// A mode splits input in two: whatever produces text goes to that mode's own zone, and
/// everything else — held modifiers, shortcuts, arrows, Escape, Backspace — lands here and is
/// displayed as one combination, like Latest mode, with a ×N badge when the same command is
/// pressed again.
///
/// It is one object rather than a rule each mode reimplements, because the two modes are meant
/// to be indistinguishable here: a divergence would be a bug in whichever mode was written
/// second, and invisible until someone compared them side by side.
@MainActor
@Observable
public final class CommandZoneState {
    // MARK: - Properties

    /// Modifiers that reroute every keypress into the command zone. Shift is absent on
    /// purpose: it uppercases text input instead of capturing it.
    public static let commandModifierFlags: CGEventFlags = [
        .maskCommand,
        .maskAlternate,
        .maskControl,
        .maskSecondaryFn,
    ]

    /// Zone contents: held modifiers followed by the current combination.
    public var keys: [PressedKey] {
        self.keyState.pressedKeys
    }

    /// How many times the displayed command was pressed in a row. `0` when the zone shows no
    /// command, `1` for a single press; views draw the ×N badge above `1`.
    ///
    /// The count is matched against what is on screen right now: pressing a modifier alone
    /// glues it onto a lingering combination, and the badge of the old command must not
    /// survive that.
    public var repeatCount: Int {
        guard self.hasCombination else { return 0 }
        return self.currentSignature == self.signature ? self.repeats : 1
    }

    /// Id of the keycap that should carry the ×N badge — the last non-modifier key of the
    /// displayed command.
    public var repeatKeyID: String? {
        self.keys.last { !$0.symbol.isModifier }?.id
    }

    public var hasKeys: Bool {
        self.keyState.hasKeys
    }

    public var keyTimeout: TimeInterval {
        get { self.keyState.keyTimeout }
        set { self.keyState.keyTimeout = newValue }
    }

    public var contentMode: KeyboardContentMode {
        get { self.keyState.contentMode }
        set { self.keyState.contentMode = newValue }
    }

    public var filters: KeyboardFilterSettings {
        get { self.keyState.filters }
        set { self.keyState.filters = newValue }
    }

    /// Set of symbol ids for all keys that are physically pressed in the zone.
    public var physicallyPressedKeys: Set<String> {
        self.keyState.physicallyPressedKeys
    }

    /// Set of symbol ids for modifiers that are physically pressed.
    public var pressedModifierIds: Set<String> {
        self.keyState.pressedModifierIds
    }

    /// Ids of the keycaps whose key is physically down right now. Entry ids, not symbol ids —
    /// views must never match a press by symbol id.
    public var pressedKeyIDs: Set<String> {
        let physicallyPressed = self.keyState.physicallyPressedKeys
        return Set(
            self.keys
                .filter { physicallyPressed.contains($0.symbol.id) }
                .map(\.id))
    }

    private let keyState: SingleKeyState

    private var signature: String?
    private var repeats: Int = 0

    private var hasCombination: Bool {
        self.keys.contains { !$0.symbol.isModifier }
    }

    private var currentSignature: String {
        self.keys.map(\.symbol.id).joined(separator: "+")
    }

    // MARK: - Lifecycle

    public init(isKeyDown: @escaping SingleKeyState.KeyDownProbe) {
        self.keyState = SingleKeyState(isKeyDown: isKeyDown)
    }

    // MARK: - Event handling

    /// Hands a modifier or flags event straight to the zone, which is where all of them go.
    public func processModifierEvent(_ event: KeyEvent, symbol: KeySymbol) {
        self.keyState.processEvent(event, symbol: symbol)
    }

    /// Drops keys the system no longer reports as pressed, before a new press is judged.
    public func reconcileHeldKeys() {
        self.keyState.reconcileHeldKeys()
    }

    /// Registers a key press as a command and updates the repeat count.
    ///
    /// A key held down repeats `keyDown` over and over; those repeats keep the command on
    /// screen but must never inflate the badge, which counts deliberate presses.
    public func register(event: KeyEvent, symbol: KeySymbol) {
        let isKeyRepeat = self.keyState.physicallyPressedKeys.contains(symbol.id)
        let previousSignature = self.signature
        let hadCombination = self.hasCombination

        self.keyState.processReconciledEvent(event, symbol: symbol)

        guard !isKeyRepeat else { return }

        let signature = self.currentSignature
        self.repeats = hadCombination && signature == previousSignature ? self.repeats + 1 : 1
        self.signature = signature
    }

    /// Releases a key the zone is tracking. Keys that never reached the zone are ignored, so a
    /// mode's own zone keeps sole ownership of the presses it took.
    public func releaseIfTracked(event: KeyEvent, symbol: KeySymbol) {
        guard self.keyState.physicallyPressedKeys.contains(symbol.id) else { return }
        self.keyState.processEvent(event, symbol: symbol)
    }

    public func clear() {
        self.keyState.clear()
        self.signature = nil
        self.repeats = 0
    }

    /// Returns true if the modifier is physically pressed (not just visible).
    public func isModifierPressed(_ symbolId: String) -> Bool {
        self.keyState.isModifierPressed(symbolId)
    }

    /// Whether the event's modifiers capture the keypress for this zone.
    public static func capturesInput(modifiers: CGEventFlags) -> Bool {
        !modifiers.isDisjoint(with: self.commandModifierFlags)
    }
}
