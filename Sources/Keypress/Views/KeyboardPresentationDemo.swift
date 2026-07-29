import KeypressCore
import SwiftUI

@MainActor
struct KeyboardPresentationDemo: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let config: KeypressConfig
    let reduceMotion: Bool
    let replayLabel: String?

    @State private var pressedKeyIDs: Set<String> = []
    @State private var replayTask: Task<Void, Never>?

    init(
        config: KeypressConfig,
        reduceMotion: Bool = false,
        replayLabel: String? = nil)
    {
        self.config = config
        self.reduceMotion = reduceMotion
        self.replayLabel = replayLabel
    }

    var body: some View {
        ZStack {
            self.presentationContent
                .id(self.config.keyboard.presentation)
                .transition(
                    self.motionIsReduced
                        ? .opacity
                        : .scale(scale: 0.92).combined(with: .opacity))
                .accessibilityHidden(true)

            if let replayLabel {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            self.replay()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 30, height: 30)
                                .background(Color.black.opacity(0.3), in: Circle())
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color.white.opacity(0.13))
                                }
                                .contentShape(Circle())
                        }
                        .buttonStyle(StudioHoverButtonStyle(showsHoverSurface: false))
                        .foregroundStyle(.white.opacity(0.9))
                        .help(replayLabel)
                        .accessibilityLabel(replayLabel)
                    }
                    Spacer()
                }
                .padding(9)
            }
        }
        .animation(
            self.motionIsReduced
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.38, dampingFraction: 0.86),
            value: self.config.keyboard.presentation)
        .onAppear {
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
        }
    }

    @ViewBuilder
    private var presentationContent: some View {
        switch self.config.keyboard.presentation {
        case .latest:
            self.keyboardGroup(self.demoSymbols)
                .scaleEffect(0.72)
        case .horizontalHistory:
            self.keyboardGroup(self.horizontalSymbols)
                .scaleEffect(0.58)
        case .stackedHistory:
            if self.config.keyboard.contentMode == .allKeys {
                VStack(spacing: 8) {
                    StackedHistoryTextRow(
                        text: "HELLO",
                        theme: self.keyboardTheme)
                    self.keyboardGroup(self.demoSymbols)
                }
                .scaleEffect(0.58)
            } else {
                VStack(spacing: 8) {
                    self.keyboardGroup(self.shortcutHistorySymbols, animatesPresses: false)
                    self.keyboardGroup(self.demoSymbols)
                }
                .scaleEffect(0.58)
            }
        }
    }

    private func keyboardGroup(
        _ symbols: [KeySymbol],
        animatesPresses: Bool = true) -> some View
    {
        KeyboardThemeContainer(config: self.config, disableOuterShadow: true) {
            HStack(spacing: CGFloat(self.keyboardTheme.keySpacing)) {
                ForEach(symbols) { symbol in
                    let isPressed = animatesPresses
                        && self.animatesPress(for: symbol)
                        && self.pressedKeyIDs.contains(symbol.id)
                    KeyCapView(
                        symbol: symbol,
                        config: self.config,
                        isPressed: !self.motionIsReduced && isPressed)
                        .opacity(self.motionIsReduced && isPressed ? 0.7 : 1)
                        .animation(
                            self.motionIsReduced
                                ? .easeOut(duration: 0.12)
                                : nil,
                            value: isPressed)
                }
            }
        }
    }

    private func animatesPress(for symbol: KeySymbol) -> Bool {
        symbol.isModifier
            ? self.config.keyboard.pressAnimationModifiers
            : self.config.keyboard.pressAnimationRegularKeys
    }

    private var demoSymbols: [KeySymbol] {
        [
            KeySymbol(id: "shift-left", display: "⇧", isModifier: true),
            KeySymbol(id: "command-left", display: "⌘", isModifier: true),
            self.config.keyboard.contentMode == .allKeys
                ? KeySymbol(id: "key-40", display: "K")
                : KeySymbol(id: "key-9", display: "V"),
        ]
    }

    private var shortcutHistorySymbols: [KeySymbol] {
        [
            KeySymbol(id: "shift-left", display: "⇧", isModifier: true),
            KeySymbol(id: "command-left", display: "⌘", isModifier: true),
            KeySymbol(id: "key-8", display: "C"),
        ]
    }

    private var horizontalSymbols: [KeySymbol] {
        let previousKeys: [KeySymbol] = self.config.keyboard.contentMode == .allKeys
            ? [
                KeySymbol(id: "key-4", display: "H"),
                KeySymbol(id: "key-34", display: "I"),
            ]
            : [
                KeySymbol(id: "key-8", display: "C"),
            ]
        return Array(self.demoSymbols.prefix(2))
            + previousKeys
            + [self.demoSymbols[2]]
    }

    private func replay() {
        self.replayTask?.cancel()
        self.pressedKeyIDs.removeAll()
        let keyIDs = self.demoSymbols.map(\.id)

        self.replayTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }

            for keyID in keyIDs {
                self.pressedKeyIDs.insert(keyID)
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
            }

            try? await Task.sleep(for: .milliseconds(380))
            guard !Task.isCancelled else { return }

            for keyID in keyIDs.reversed() {
                self.pressedKeyIDs.remove(keyID)
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
            }
        }
    }

    private var keyboardTheme: KeyboardTheme {
        self.config.effectiveTheme(isSystemDark: true).keyboard
    }

    private var motionIsReduced: Bool {
        self.reduceMotion || self.systemReduceMotion
    }
}
