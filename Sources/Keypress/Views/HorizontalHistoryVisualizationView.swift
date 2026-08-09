import AppKit
import CoreGraphics
import KeypressCore
import SwiftUI

// MARK: - RibbonChange

/// Shape of a change to the ribbon's contents, which decides whether the row may move.
///
/// The ribbon is a conveyor: entries leave at the head and arrive at the tail, so every
/// keycap moves by the same amount or not at all. Reshapes that break that pattern — a
/// filter change dropping entries from the middle, or a head kept alive by autorepeat
/// while its right-hand neighbour times out — would need keycaps to travel different
/// distances, so they are applied without animation instead.
enum RibbonChange: Equatable {
    /// Entries were dropped from the head and/or appended at the tail. Safe to slide.
    case conveyor

    /// Any other reshape. Apply instantly, with no motion at all.
    case discontinuous

    /// Classifies a transition between two ribbon id sequences.
    ///
    /// The result is `.conveyor` exactly when `new` can be produced from `old` by dropping
    /// zero or more entries from the head and appending zero or more at the tail: every
    /// surviving id keeps its order, forms a suffix of `old`, and forms a prefix of `new`.
    /// Ids are assumed unique within each sequence.
    static func classify(old: [String], new: [String]) -> RibbonChange {
        let survivors = Set(new)
        let kept = old.filter { survivors.contains($0) }
        guard old.suffix(kept.count).elementsEqual(kept),
              new.prefix(kept.count).elementsEqual(kept)
        else {
            return .discontinuous
        }
        return .conveyor
    }
}

// MARK: - RibbonSnapshot

/// The ribbon content one frame renders. Held as view state so the row's slide, the
/// eviction fade and the latest-key width change all land in a single transaction.
private struct RibbonSnapshot: Equatable {
    var keys: [RibbonKey] = []
    var latestID: String?
    var pressedIDs: Set<String> = []
}

// MARK: - HorizontalHistoryRibbonView

/// The text ribbon: a strictly chronological row of the keys that produced text.
///
/// Reading order is left to right. New keys append at the tail; the head leaves by
/// eviction or by its own timeout. Nothing is ever reordered.
struct HorizontalHistoryRibbonView: View {
    var state: HorizontalHistoryState
    let config: KeypressConfig
    @Environment(\.blockPhase) private var blockPhase

    /// How fast the row is allowed to slide, kept across rebuilds so it can watch the rhythm.
    @State private var pacer = ConveyorPacer()

    private var keyboardTheme: KeyboardTheme {
        self.config.effectiveTheme(isSystemDark: self.systemIsDark).keyboard
    }

    /// What the state currently holds, as one comparable value. The press set rides along so
    /// the block's exit draws the row exactly as it was rather than watching it empty.
    private var snapshot: RibbonSnapshot {
        RibbonSnapshot(
            keys: self.state.ribbonKeys,
            latestID: self.state.latestRibbonKeyID,
            pressedIDs: self.state.pressedRibbonKeyIDs)
    }

    private var keycapTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.9)),
            removal: .opacity)
    }

    var body: some View {
        BlockPresentationView(
            value: self.snapshot,
            isPresent: self.state.hasRibbonKeys,
            contentChange: self.rowChange)
        { snapshot in
            KeyboardThemeContainer(config: self.config) {
                HStack(spacing: CGFloat(self.keyboardTheme.keySpacing)) {
                    ForEach(snapshot.keys, id: \.id) { entry in
                        KeyCapView(
                            symbol: entry.symbol,
                            config: self.config,
                            isPressed: self.isPressed(entry, in: snapshot),
                            displayText: entry.display,
                            sizeOverride: self.sizeOverride(for: entry, in: snapshot))
                            .transition(self.keycapTransition)
                    }
                }
            }
        }
    }

    /// How the row moves from one snapshot to the next.
    ///
    /// One transaction covers the whole row, so every keycap slides by the same amount, the
    /// evicted head fades where it stood and the new tail pops in — or, for a reshape the
    /// conveyor cannot express, nothing moves at all. The slide's length comes from the typing
    /// speed, so the row still gets to rest between fast keystrokes; the new tail's pop rides
    /// the same transaction and shortens with it.
    private func rowChange(
        from old: RibbonSnapshot,
        to new: RibbonSnapshot) -> BlockContentChange
    {
        // The row only slides while the block is settled. During the block's own entrance or
        // exit a conveyor step would be moving the same keycaps the block is already moving.
        guard self.blockPhase == .shown else {
            self.record(.instant, from: old, to: new)
            return .instant
        }

        switch RibbonChange.classify(old: old.keys.map(\.id), new: new.keys.map(\.id)) {
        case .conveyor:
            // A head leaving on its own timeout is a conveyor step too, but it is not a
            // keystroke and must not be timed as one.
            let gainedAKey = new.keys.last?.id != old.keys.last?.id
            let duration = self.pacer.duration(appended: gainedAKey)
            let change = BlockContentChange.animated(KeypressTiming.conveyor(duration: duration))
            self.record(change, from: old, to: new, duration: duration)
            return change
        case .discontinuous:
            self.record(.instant, from: old, to: new)
            return .instant
        }
    }

    private func record(
        _ change: BlockContentChange,
        from old: RibbonSnapshot,
        to new: RibbonSnapshot,
        duration: TimeInterval? = nil)
    {
        let length = duration.map { " in \(Int($0 * 1000))ms" } ?? ""
        AnimationJournal.shared.record(
            .conveyor,
            phaseIn: "\(self.blockPhase)",
            animation: change == .instant ? "instant" : "conveyor",
            detail: "\(old.keys.count)->\(new.keys.count)\(length)")
    }

    /// Press state is matched per entry: pressing a letter that already sits in the row
    /// must never animate the older copies.
    private func isPressed(_ entry: RibbonKey, in snapshot: RibbonSnapshot) -> Bool {
        snapshot.pressedIDs.contains(entry.id) && self.config.pressAnimationRegularKeys
    }

    /// Space, Enter and Tab keep the control look only while they are the last thing
    /// pressed; once anything follows they shrink to letter width and ride the train.
    private func sizeOverride(for entry: RibbonKey, in snapshot: RibbonSnapshot) -> KeyCapSize? {
        KeyCapSize.inputKey(
            for: entry.symbol,
            settings: self.config.keyboard.inputKeys,
            isControlPosition: entry.id == snapshot.latestID)
    }

    private var systemIsDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

// MARK: - Preview Support

/// Stands in for the system key-state probe so previews can hold keys down.
private final class RibbonPreviewKeyboard: @unchecked Sendable {
    private var downKeys: Set<CGKeyCode> = []
    private let lock = NSLock()

    var probe: SingleKeyState.KeyDownProbe {
        { keyCode in self.lock.withLock { self.downKeys.contains(keyCode) } }
    }

    func press(_ keyCode: Int64) {
        self.lock.withLock { _ = self.downKeys.insert(CGKeyCode(keyCode)) }
    }

    func release(_ keyCode: Int64) {
        self.lock.withLock { _ = self.downKeys.remove(CGKeyCode(keyCode)) }
    }
}

/// Drives a real `HorizontalHistoryState` from preview code.
@MainActor
private final class RibbonPreviewRig {
    let state: HorizontalHistoryState

    private let keyboard: RibbonPreviewKeyboard
    private var heldKey: PreviewKey?

    init(maxItems: Int = 6) {
        let keyboard = RibbonPreviewKeyboard()
        self.keyboard = keyboard
        self.state = HorizontalHistoryState(
            settings: KeyboardSettings(maxItems: maxItems),
            isKeyDown: keyboard.probe)
        // Previews outlive any real timeout; keep every keycap on screen instead.
        self.state.keyTimeout = 3600
    }

    /// Types `text`, optionally leaving the final key physically held down.
    func type(_ text: String, holdingLast: Bool = false) {
        self.releaseHeld()

        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            let key = Self.key(for: character)
            self.keyboard.press(key.code)
            self.state.processEvent(
                KeyEvent(type: .keyDown, keyCode: key.code, modifiers: []),
                symbol: key.symbol)

            guard holdingLast, index == characters.count - 1 else {
                self.keyboard.release(key.code)
                self.state.processEvent(
                    KeyEvent(type: .keyUp, keyCode: key.code, modifiers: []),
                    symbol: key.symbol)
                continue
            }
            self.heldKey = key
        }
    }

    /// Lifts the key `type(_:holdingLast:)` left down, so the next press is a fresh one.
    func releaseHeld() {
        guard let held = self.heldKey else { return }
        self.heldKey = nil
        self.keyboard.release(held.code)
        self.state.processEvent(
            KeyEvent(type: .keyUp, keyCode: held.code, modifiers: []),
            symbol: held.symbol)
    }

    /// Presses ⌘ and taps `symbol` `times` times, leaving ⌘ held.
    func pressCommandShortcut(_ symbol: KeySymbol, keyCode: Int64, times: Int) {
        self.releaseHeld()

        let command = KeySymbol(id: "command-left", display: "⌘", isModifier: true)
        self.keyboard.press(0x37)
        self.state.processEvent(
            KeyEvent(
                type: .flagsChanged,
                keyCode: 0x37,
                modifiers: .maskCommand,
                modifierIsPressed: true),
            symbol: command)

        for _ in 0..<times {
            self.state.processEvent(
                KeyEvent(type: .keyDown, keyCode: keyCode, modifiers: .maskCommand),
                symbol: symbol)
            self.state.processEvent(
                KeyEvent(type: .keyUp, keyCode: keyCode, modifiers: .maskCommand),
                symbol: symbol)
        }
    }

    private struct PreviewKey {
        let code: Int64
        let symbol: KeySymbol
    }

    private static func key(for character: Character) -> PreviewKey {
        switch character {
        case " ":
            PreviewKey(code: 0x31, symbol: KeySymbol(id: "space", display: "␣", isSpecial: true))
        case "\n":
            PreviewKey(code: 0x24, symbol: KeySymbol(id: "return", display: "⏎", isSpecial: true))
        case "\t":
            PreviewKey(code: 0x30, symbol: KeySymbol(id: "tab", display: "⇥", isSpecial: true))
        default:
            PreviewKey(
                code: Int64(character.asciiValue ?? 0),
                symbol: KeySymbol(id: String(character), display: String(character).uppercased()))
        }
    }
}

// MARK: - Previews

#Preview("Ribbon — duplicate letter, one instance pressed") {
    @Previewable @State var rig = RibbonPreviewRig()
    HorizontalHistoryRibbonView(state: rig.state, config: .shared)
        .onAppear { rig.type("hell", holdingLast: true) }
        .padding(48)
        .background(Color.black)
}

#Preview("Ribbon — full row at maxItems") {
    @Previewable @State var rig = RibbonPreviewRig(maxItems: 6)
    HorizontalHistoryRibbonView(state: rig.state, config: .shared)
        .onAppear { rig.type("keypad") }
        .padding(48)
        .background(Color.black)
}

#Preview("Ribbon — conveyor (interactive)") {
    @Previewable @State var rig = RibbonPreviewRig(maxItems: 6)
    VStack(spacing: 24) {
        HorizontalHistoryRibbonView(state: rig.state, config: .shared)

        HStack(spacing: 12) {
            Button("Type letter") { rig.type("x") }
            Button("Type space") { rig.type(" ") }
            Button("Type duplicate") { rig.type("l", holdingLast: true) }
        }
    }
    .onAppear { rig.type("hello") }
    .padding(48)
    .background(Color.black)
}

#Preview("Ribbon — latest Space wide vs shrunk") {
    @Previewable @State var latest = RibbonPreviewRig()
    @Previewable @State var shrunk = RibbonPreviewRig()

    VStack(spacing: 24) {
        HorizontalHistoryRibbonView(state: latest.state, config: .shared)
            .onAppear { latest.type("hi ") }
        HorizontalHistoryRibbonView(state: shrunk.state, config: .shared)
            .onAppear { shrunk.type("hi you") }
    }
    .padding(48)
    .background(Color.black)
}

#Preview("Command zone — ⌘V ×3") {
    @Previewable @State var rig = RibbonPreviewRig()
    CommandZoneView(state: rig.state.commandZone, config: .shared)
        .onAppear {
            rig.pressCommandShortcut(KeySymbol(id: "v", display: "V"), keyCode: 0x09, times: 3)
        }
        .padding(48)
        .background(Color.black)
}

#Preview("Both zones stacked") {
    @Previewable @State var rig = RibbonPreviewRig()
    VStack(alignment: .leading, spacing: 10) {
        HorizontalHistoryRibbonView(state: rig.state, config: .shared)
        CommandZoneView(state: rig.state.commandZone, config: .shared)
    }
    .onAppear {
        rig.type("hello ")
        rig.pressCommandShortcut(KeySymbol(id: "v", display: "V"), keyCode: 0x09, times: 3)
    }
    .padding(48)
    .background(Color.black)
}
