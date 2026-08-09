import KeypressCore
import SwiftUI

// MARK: - DemoWord

/// The word the two-zone demos type out.
///
/// The two modes show two different things about the same keystrokes: the ribbon shows the keys
/// that produced the text, the echo shows the text they produced. That is why one is raw
/// lowercase keycaps and the other is sentence case.
private enum DemoWord {
    static let ribbonLetters = ["h", "e", "l", "l", "o"]
    static let echoCharacters = Array("Hello")
    static let length = max(ribbonLetters.count, echoCharacters.count)
}

// MARK: - KeyboardPresentationDemo

@MainActor
struct KeyboardPresentationDemo: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let config: KeypressConfig
    let reduceMotion: Bool

    /// Bumped by whoever owns the replay control, which lives on the surface around this
    /// preview rather than inside it.
    let replayTrigger: Int

    /// The room the onboarding step gives this demo. The settings pane is roomier, so this is
    /// the height every mode has to draw inside — the surface clips, it does not shrink.
    static let onboardingSurfaceHeight: CGFloat = 118

    /// Both two-zone modes draw at one scale, so the command zone — literally the same zone in
    /// both — comes out the same size whichever of them is selected. Sized against
    /// `onboardingSurfaceHeight`, which two zones and the gap between them have to clear.
    static let twoZoneScale: CGFloat = 0.55

    @State private var pressedKeyIDs: Set<String> = []

    /// How much of the typed word is on screen. Full at rest: `ImageRenderer` draws without ever
    /// letting the replay's task run, so whatever stands here is what it captures.
    @State private var revealedCount = DemoWord.length

    @State private var replayTask: Task<Void, Never>?

    init(
        config: KeypressConfig,
        reduceMotion: Bool = false,
        replayTrigger: Int = 0)
    {
        self.config = config
        self.reduceMotion = reduceMotion
        self.replayTrigger = replayTrigger
    }

    var body: some View {
        self.presentationContent
            .id(self.config.keyboard.presentation)
            .transition(
                self.motionIsReduced
                    ? .opacity
                    : .scale(scale: 0.92).combined(with: .opacity))
            .accessibilityHidden(true)
            .animation(
                self.motionIsReduced
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.38, dampingFraction: 0.86),
                value: self.config.keyboard.presentation)
            .onAppear {
                self.replay()
            }
            .onChange(of: self.replayTrigger) { _, _ in
                self.replay()
            }
            .onChange(of: self.config.appearance.keyboardThemeSelection) { _, _ in
                self.replay()
            }
            .onChange(of: self.config.keyboard.presentation) { _, _ in
                self.replay()
            }
            .onChange(of: self.config.keyboard.contentMode) { _, _ in
                self.replay()
            }
            .onChange(of: self.config.keyboard.pressAnimationModifiers) { _, _ in
                self.replay()
            }
            .onChange(of: self.config.keyboard.pressAnimationRegularKeys) { _, _ in
                self.replay()
            }
            .onDisappear {
                self.replayTask?.cancel()
                self.pressedKeyIDs.removeAll()
                // A replay cancelled part-way through leaves half a word behind, and the next
                // one holds whatever it finds for its whole lead-in.
                self.revealedCount = DemoWord.length
            }
    }

    /// The two-zone modes are drawn the way the overlay lays them out by default: the mode's own
    /// zone on top, the command zone under it, each in a block of its own.
    @ViewBuilder
    private var presentationContent: some View {
        switch self.config.keyboard.presentation {
        case .latest:
            self.keyboardGroup(self.commandSymbols)
                .scaleEffect(0.72)
        case .horizontalHistory:
            VStack(spacing: HorizontalHistoryZonePlacements.spacing) {
                self.keyboardGroup(self.ribbonSymbols, revealed: self.revealedCount)
                self.keyboardGroup(self.commandSymbols)
            }
            .scaleEffect(Self.twoZoneScale)
        case .stackedHistory:
            VStack(spacing: HorizontalHistoryZonePlacements.spacing) {
                self.echoPlaque
                self.keyboardGroup(self.commandSymbols)
            }
            .scaleEffect(Self.twoZoneScale)
        }
    }

    /// One block of keycaps.
    ///
    /// `revealed` hides the tail of the row instead of dropping it, so the block keeps the width
    /// it will end up with and the letters arrive where they will stay — the way the real ribbon
    /// reads, rather than a row that re-centres itself under every keystroke.
    private func keyboardGroup(_ symbols: [KeySymbol], revealed: Int? = nil) -> some View {
        KeyboardThemeContainer(config: self.config, disableOuterShadow: true) {
            HStack(spacing: CGFloat(self.keyboardTheme.keySpacing)) {
                ForEach(Array(symbols.enumerated()), id: \.element.id) { index, symbol in
                    let isPressed = self.animatesPress(for: symbol)
                        && self.pressedKeyIDs.contains(symbol.id)
                    KeyCapView(
                        symbol: symbol,
                        config: self.config,
                        isPressed: !self.motionIsReduced && isPressed)
                        .opacity(
                            index < (revealed ?? symbols.count)
                                ? (self.motionIsReduced && isPressed ? 0.7 : 1)
                                : 0)
                        .animation(
                            self.motionIsReduced
                                ? .easeOut(duration: 0.12)
                                : nil,
                            value: isPressed)
                }
            }
        }
    }

    /// The echo's line, on the same plaque the live echo uses.
    private var echoPlaque: some View {
        TypedTextPlaque(
            theme: self.keyboardTheme,
            minimumHeight: TextEchoStyle.plaqueHeight(for: self.keyboardTheme))
        {
            self.echoText
                .font(TextEchoStyle.font(theme: self.keyboardTheme))
                .fixedSize()
                .offset(y: -TextEchoStyle.opticalCenteringOffset(for: self.keyboardTheme))
        }
    }

    /// The whole word, with the characters that have not been typed yet drawn in nothing at
    /// all — so the plaque is already the size it will end up and the text never reflows.
    private var echoText: Text {
        DemoWord.echoCharacters
            .enumerated()
            .reduce(Text(verbatim: "")) { text, character in
                text + Text(verbatim: String(character.element))
                    .foregroundColor(
                        character.offset < self.revealedCount
                            ? self.keyboardTheme.textColor.color
                            : .clear)
            }
    }

    private func animatesPress(for symbol: KeySymbol) -> Bool {
        symbol.isModifier
            ? self.config.keyboard.pressAnimationModifiers
            : self.config.keyboard.pressAnimationRegularKeys
    }

    /// The combination every mode ends on. In Latest it is the whole picture; in the two-zone
    /// modes it is what the command zone holds, which is why it never carries a letter that
    /// produced text.
    private var commandSymbols: [KeySymbol] {
        [
            KeySymbol(id: "shift-left", display: "⇧", isModifier: true),
            KeySymbol(id: "command-left", display: "⌘", isModifier: true),
            self.config.keyboard.effectiveContentMode == .allKeys
                ? KeySymbol(id: "key-40", display: "K")
                : KeySymbol(id: "key-9", display: "V"),
        ]
    }

    /// The ribbon's row: text-producing keys only, in the casing the ribbon renders them.
    /// A modifier held down routes to the command zone, so none can appear here.
    private var ribbonSymbols: [KeySymbol] {
        DemoWord.ribbonLetters
            .enumerated()
            .map { index, letter in
                KeySymbol(id: "demo-ribbon-\(index)", display: letter)
            }
    }

    private func replay() {
        self.replayTask?.cancel()
        self.pressedKeyIDs.removeAll()

        let typesFirst = self.config.keyboard.presentation != .latest
        // Only the ribbon has keycaps to flash while the word arrives; the echo's characters
        // land on a plaque with no keys of their own.
        let typedKeyIDs = self.config.keyboard.presentation == .horizontalHistory
            ? self.ribbonSymbols.map(\.id)
            : []
        let chordKeyIDs = self.commandSymbols.map(\.id)

        self.replayTask = Task { @MainActor in
            // The lead-in holds the finished word, which is what the surface was already
            // showing; it is cleared only once the typing is about to put it back. That also
            // leaves the word standing for `ImageRenderer`, which never gives this task a turn.
            guard await self.pause(.milliseconds(650)) else { return }

            if typesFirst {
                self.revealedCount = 0
                await self.playTyping(pressing: typedKeyIDs)
                guard await self.pause(.milliseconds(240)) else { return }
            }

            await self.playChord(chordKeyIDs)
        }
    }

    /// Reveals the word one keystroke at a time, flashing the keycap each one created where
    /// there is one.
    private func playTyping(pressing keyIDs: [String]) async {
        for step in 0..<DemoWord.length {
            let keyID = step < keyIDs.count ? keyIDs[step] : nil
            self.revealedCount = step + 1
            if let keyID {
                self.pressedKeyIDs.insert(keyID)
            }
            guard await self.pause(.milliseconds(150)) else { return }
            if let keyID {
                self.pressedKeyIDs.remove(keyID)
            }
            guard await self.pause(.milliseconds(70)) else { return }
        }
    }

    /// Presses the combination one key at a time, holds it, then lets it go in reverse.
    private func playChord(_ keyIDs: [String]) async {
        for keyID in keyIDs {
            self.pressedKeyIDs.insert(keyID)
            guard await self.pause(.milliseconds(140)) else { return }
        }

        guard await self.pause(.milliseconds(380)) else { return }

        for keyID in keyIDs.reversed() {
            self.pressedKeyIDs.remove(keyID)
            guard await self.pause(.milliseconds(90)) else { return }
        }
    }

    /// Waits, and reports whether the replay is still wanted.
    private func pause(_ duration: Duration) async -> Bool {
        try? await Task.sleep(for: duration)
        return !Task.isCancelled
    }

    private var keyboardTheme: KeyboardTheme {
        self.config.effectiveTheme(isSystemDark: true).keyboard
    }

    private var motionIsReduced: Bool {
        self.reduceMotion || self.systemReduceMotion
    }
}

// MARK: - Previews

/// A config of its own, so a preview can pin a mode and a size without touching the real one.
@MainActor
private func demoConfig(
    _ presentation: KeyboardPresentation,
    size: OverlaySize) -> KeypressConfig
{
    let suiteName = "preview.keyboard.demo.\(presentation.rawValue).\(size.rawValue)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    let config = KeypressConfig.makeEphemeral(userDefaults: defaults)
    config.appearance.keyboardThemeSelection = .dark
    config.keyboard.presentation = presentation
    config.keyboard.size = size
    return config
}

// Every mode at both extremes of the overlay size, each in the real preview surface. The
// replay button has to sit inside the rounded corner in all six, however wide the preview
// inside happens to lay out.
#Preview("Keyboard preview surface — every mode, min and max size") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(KeyboardPresentation.allCases, id: \.self) { presentation in
                ForEach([OverlaySize.small, .large], id: \.self) { size in
                    StudioPreviewSurface(height: 166) {
                        KeyboardPresentationDemo(config: demoConfig(presentation, size: size))
                    } accessory: {
                        StudioPreviewReplayButton(label: "Replay key press") {}
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

// The onboarding step gives the same demo 48pt less room than the settings pane does, so it is
// the height the two-zone modes have to fit in — both zones and the gap between them.
#Preview("Keyboard preview surface — onboarding height") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(KeyboardPresentation.allCases, id: \.self) { presentation in
                StudioPreviewSurface(height: KeyboardPresentationDemo.onboardingSurfaceHeight) {
                    KeyboardPresentationDemo(config: demoConfig(presentation, size: .medium))
                } accessory: {
                    StudioPreviewReplayButton(label: "Replay key press") {}
                }
            }
        }
        .padding(24)
        .frame(width: 620)
    }
}
