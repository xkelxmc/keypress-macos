import AppKit
import CoreGraphics
import KeypressCore
import SwiftUI

// MARK: - TextEchoStyle

/// How the echo is drawn, in one place so the live overlay and the placement editor's preview
/// cannot disagree about how much room three lines take.
enum TextEchoStyle {
    /// Larger than the reference plaque's type: the whole mode exists because the real text
    /// field is too small to read from across a room or through a compressed stream.
    static let fontSize: CGFloat = 26

    /// What that larger type adds to a plaque's height, so the text keeps the reference's
    /// breathing room rather than filling its plaque edge to edge.
    static let plaqueHeightBonus: CGFloat = 8

    /// Gap between one line's plaque and the next.
    static let lineSpacing: CGFloat = 8

    /// Enter and Tab are typing, not text — visible, but never competing with the characters.
    static let markOpacity: Double = 0.42

    /// How far the text is lifted off the plaque's true centre, as a fraction of the type size.
    ///
    /// A line of type is centred by its line box, which reserves room above for ascenders and
    /// below for descenders. Echoed text is mostly lowercase, so most of that reserved room
    /// goes unused above the letters and the line reads as sitting low on its plaque. Measured
    /// on the shipped font at 26pt: lowercase leaves 24.4pt clear above and 18.2pt below, a
    /// 6.3pt lean; capitals leave 19.5pt and 18.2pt, a 1.3pt lean the other way.
    ///
    /// One offset has to serve both, because a line that shifted when a capital arrived would
    /// move glyphs already on screen. This is the value that leaves the two cases equally far
    /// off — about 2.4pt each, lowercase still a touch low, capitals a touch high — which is
    /// the least either can be asked to give up. Lifting far enough to centre lowercase
    /// exactly would take three times as much and press the capitals into the top edge.
    ///
    /// A taller plaque would not help: the lean comes from where the baseline sits inside the
    /// line box, so padding moves both clearances together and leaves the imbalance untouched.
    static let opticalCenteringFactor: CGFloat = 0.075

    /// The lift itself, in points, following whatever size the theme renders the text at.
    static func opticalCenteringOffset(for theme: KeyboardTheme) -> CGFloat {
        self.fontSize * theme.fontScale * self.opticalCenteringFactor
    }

    /// A plaque's height, as an estimate independent of the theme, for budgeting the zone's
    /// room on a display before anything has been drawn.
    static let nominalPlaqueHeight: CGFloat = 56

    @MainActor
    static func font(theme: KeyboardTheme) -> Font {
        ThemeFont.font(
            family: theme.fontFamily,
            size: self.fontSize * theme.fontScale,
            weight: theme.fontWeight)
    }

    static func plaqueHeight(for theme: KeyboardTheme) -> CGFloat {
        TypedTextPlaqueStyle.height(for: theme) + self.plaqueHeightBonus
    }

    /// The room a stack of `lineCount` plaques takes, gaps included.
    static func zoneHeight(lineCount: Int) -> CGFloat {
        CGFloat(lineCount) * self.nominalPlaqueHeight
            + CGFloat(max(0, lineCount - 1)) * self.lineSpacing
    }
}

// MARK: - TextEchoSnapshot

/// The lines one frame renders, held as view state so a line arriving, a line dying and the
/// surviving lines' single step all land in one transaction.
private struct TextEchoSnapshot: Equatable {
    var lines: [TextEchoLine] = []
}

// MARK: - TextEchoLinesView

/// The text zone: what is being typed, echoed as real text.
///
/// Every line gets a plaque of its own and the plaques stack with a gap, so a line reads as a
/// line rather than as a row inside a keyboard. The newest one sits on the anchored side and
/// history stacks away from it, so the line being written never moves when an older one dies.
struct TextEchoLinesView: View {
    var state: TextEchoState
    let config: KeypressConfig
    @ObservedObject var layoutState: OverlayLayoutState
    @Environment(\.blockPhase) private var blockPhase

    private var keyboardTheme: KeyboardTheme {
        self.config.effectiveTheme(isSystemDark: self.systemIsDark).keyboard
    }

    private var snapshot: TextEchoSnapshot {
        TextEchoSnapshot(lines: self.state.lines)
    }

    var body: some View {
        BlockPresentationView(
            value: self.snapshot,
            isPresent: self.state.hasTextLines,
            contentChange: self.lineChange)
        { snapshot in
            VStack(alignment: self.horizontalAlignment, spacing: TextEchoStyle.lineSpacing) {
                ForEach(self.orderedLines(in: snapshot), id: \.id) { line in
                    self.linePlaque(line)
                        .transition(self.lineTransition)
                }
            }
        }
    }

    /// Reading order on screen. The model is oldest first; a zone that flows downwards shows
    /// the newest line at the top, so it reads the other way round.
    private func orderedLines(in snapshot: TextEchoSnapshot) -> [TextEchoLine] {
        switch self.layoutState.textEchoFlow {
        case .up: snapshot.lines
        case .down: snapshot.lines.reversed()
        }
    }

    /// How the zone moves from one snapshot to the next.
    ///
    /// A keystroke changes a line's text without changing which lines exist, and that has to
    /// land instantly: an animated text change would slide the glyphs already on screen, which
    /// is the one thing the character-level wrap exists to prevent.
    ///
    /// Motion is for the history moving along — a line born at the tail, an old one leaving at
    /// the head — and then the whole stack takes its single step together. A line that
    /// disappears at the *tail* is one a Backspace just emptied, which is not history moving
    /// but the typist erasing: it goes at once, like the characters before it.
    private func lineChange(
        from old: TextEchoSnapshot,
        to new: TextEchoSnapshot) -> BlockContentChange
    {
        let oldIDs = old.lines.map(\.id)
        let newIDs = new.lines.map(\.id)

        guard self.blockPhase == .shown, oldIDs != newIDs else {
            self.record(.instant, from: old, to: new)
            return .instant
        }

        switch RibbonChange.classify(old: oldIDs, new: newIDs) {
        case .conveyor:
            let change = BlockContentChange.animated(KeypressTiming.textEchoLines)
            self.record(change, from: old, to: new)
            return change
        case .discontinuous:
            self.record(.instant, from: old, to: new)
            return .instant
        }
    }

    private func record(
        _ change: BlockContentChange,
        from old: TextEchoSnapshot,
        to new: TextEchoSnapshot)
    {
        AnimationJournal.shared.record(
            .conveyor,
            phaseIn: "\(self.blockPhase)",
            animation: change == .instant ? "instant" : "conveyor",
            detail: "\(old.lines.count)->\(new.lines.count) lines")
    }

    /// A line arrives by fading in where it will live, and leaves by drifting the way the
    /// history flows.
    ///
    /// The fade runs on its own, much shorter curve than the drift, so the plaque is gone
    /// before it has travelled far — a plaque still visible at the end of its drift would be
    /// floating on its own with nothing holding it.
    private var lineTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(KeypressTiming.textEchoLineEnter),
            removal: .opacity.animation(KeypressTiming.textEchoLineFade)
                .combined(with: .offset(
                    y: KeypressTiming.textEchoLineDrift
                        * self.layoutState.textEchoFlow.driftDirection)
                    .animation(KeypressTiming.textEchoLineDriftCurve)))
    }

    /// One line on its plaque, drawn as one styled string.
    ///
    /// Enter and Tab are concatenated in at a lower strength rather than rendered as their own
    /// views, so they sit in the run of characters exactly where they were typed and take part
    /// in the line's own layout.
    private func linePlaque(_ line: TextEchoLine) -> some View {
        TypedTextPlaque(
            theme: self.keyboardTheme,
            minimumHeight: TextEchoStyle.plaqueHeight(for: self.keyboardTheme))
        {
            line.glyphs
                .reduce(Text(verbatim: "")) { text, glyph in
                    text + Text(verbatim: glyph.text)
                        .foregroundColor(self.color(for: glyph))
                }
                .font(TextEchoStyle.font(theme: self.keyboardTheme))
                .fixedSize()
                // Drawn higher than it is laid out: the lift is optical, so it must not change
                // the plaque's size or where the next line sits.
                .offset(y: -TextEchoStyle.opticalCenteringOffset(for: self.keyboardTheme))
        }
    }

    private func color(for glyph: TextEchoGlyph) -> Color {
        let color = self.keyboardTheme.textColor.color
        return switch glyph.kind {
        case .character: color
        case .mark: color.opacity(TextEchoStyle.markOpacity)
        }
    }

    private var horizontalAlignment: HorizontalAlignment {
        switch self.layoutState.stackedHistoryLayout.horizontalAnchor {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private var systemIsDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

// MARK: - TextEchoPreviewLines

/// A stand-in echo, drawn from plain strings rather than a state machine.
///
/// The placement editor needs a preview whose footprint matches what the mode will really
/// occupy, and it needs it before a single key has been pressed — otherwise the user allocates
/// room for one line and the other two land on top of whatever is beside them.
struct TextEchoPreviewLines: View {
    let lines: [String]
    let config: KeypressConfig

    private var keyboardTheme: KeyboardTheme {
        let isSystemDark = NSApp?.effectiveAppearance
            .bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return self.config.effectiveTheme(isSystemDark: isSystemDark).keyboard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TextEchoStyle.lineSpacing) {
            ForEach(Array(self.lines.enumerated()), id: \.offset) { _, line in
                TypedTextPlaque(
                    theme: self.keyboardTheme,
                    minimumHeight: TextEchoStyle.plaqueHeight(for: self.keyboardTheme))
                {
                    Text(verbatim: line)
                        .font(TextEchoStyle.font(theme: self.keyboardTheme))
                        .foregroundStyle(self.keyboardTheme.textColor.color)
                        .fixedSize()
                        .offset(y: -TextEchoStyle.opticalCenteringOffset(for: self.keyboardTheme))
                }
            }
        }
    }
}

// MARK: - Preview Support

/// Drives a real `TextEchoState` from preview code.
@MainActor
private final class TextEchoPreviewRig {
    let state: TextEchoState
    let layoutState = OverlayLayoutState()

    init(flow: TextEchoFlow = .up) {
        self.state = TextEchoState(isKeyDown: { _ in false })
        // Previews outlive any real lifetime; keep every line on screen instead.
        self.state.lineLifetime = 3600
        self.state.idleTimeout = 3600
        self.layoutState.textEchoFlow = flow
    }

    func type(_ text: String) {
        for character in text {
            let key = Self.key(for: character)
            self.state.processEvent(
                KeyEvent(type: .keyDown, keyCode: key.code, modifiers: key.modifiers),
                symbol: key.symbol)
            self.state.processEvent(
                KeyEvent(type: .keyUp, keyCode: key.code, modifiers: key.modifiers),
                symbol: key.symbol)
        }
    }

    func backspace(times: Int = 1) {
        let symbol = KeySymbol(id: "delete", display: "⌫", isSpecial: true)
        for _ in 0..<times {
            self.state.processEvent(
                KeyEvent(type: .keyDown, keyCode: 0x33, modifiers: []),
                symbol: symbol)
            self.state.processEvent(
                KeyEvent(type: .keyUp, keyCode: 0x33, modifiers: []),
                symbol: symbol)
        }
    }

    private struct PreviewKey {
        let code: Int64
        let symbol: KeySymbol
        var modifiers: CGEventFlags = []
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
                symbol: KeySymbol(
                    id: "key-\(character.lowercased())",
                    display: String(character)),
                modifiers: character.isUppercase ? .maskShift : [])
        }
    }
}

// MARK: - Previews

// The three cases the optical lift has to serve at once, so the compromise can be judged in
// one look: text with no ascenders at all, text that is all capitals, and the mixed text most
// typing actually is. One static offset carries all three — a line that re-centred itself when
// a capital arrived would move glyphs already on screen.
#Preview("Echo — optical centering, lowercase vs caps") {
    VStack(alignment: .leading, spacing: 20) {
        TextEchoPreviewLines(lines: ["no ascenders anyone"], config: .shared)
        TextEchoPreviewLines(lines: ["ALL CAPS HERE"], config: .shared)
        TextEchoPreviewLines(lines: ["Mixed Ascenders hjkl"], config: .shared)
    }
    .padding(48)
    .background(Color.black)
}

#Preview("Echo — one line") {
    @Previewable @State var rig = TextEchoPreviewRig()
    TextEchoLinesView(state: rig.state, config: .shared, layoutState: rig.layoutState)
        .onAppear { rig.type("hello there") }
        .padding(48)
        .background(Color.black)
}

#Preview("Echo — three lines with marks") {
    @Previewable @State var rig = TextEchoPreviewRig()
    TextEchoLinesView(state: rig.state, config: .shared, layoutState: rig.layoutState)
        .onAppear { rig.type("git commit -m \"ship\"\nswift build\tand test it all") }
        .padding(48)
        .background(Color.black)
}

#Preview("Echo — flowing down") {
    @Previewable @State var rig = TextEchoPreviewRig(flow: .down)
    TextEchoLinesView(state: rig.state, config: .shared, layoutState: rig.layoutState)
        .onAppear { rig.type("first line of the echo\nsecond\tthird") }
        .padding(48)
        .background(Color.black)
}

#Preview("Echo — interactive") {
    @Previewable @State var rig = TextEchoPreviewRig()
    VStack(spacing: 24) {
        TextEchoLinesView(state: rig.state, config: .shared, layoutState: rig.layoutState)

        HStack(spacing: 12) {
            Button("Type") { rig.type("keypress ") }
            Button("Enter") { rig.type("\n") }
            Button("Backspace") { rig.backspace() }
        }
    }
    .onAppear { rig.type("hello") }
    .padding(48)
    .background(Color.black)
}
