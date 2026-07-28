import AppKit
import KeypressCore
import SwiftUI

@MainActor
struct KeyboardSettingsPane: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig

    var body: some View {
        Group {
            if self.config.keyboard.enabled {
                StudioPreviewPage(
                    titleKey: "keyboard.title",
                    subtitleKey: "keyboard.subtitle",
                    preview: {
                        StudioPreviewSurface(height: 150) {
                            KeyboardSettingsPreview(config: self.config)
                        }
                    },
                    content: { self.settingsControls })
            } else {
                StudioPage(
                    titleKey: "keyboard.title",
                    subtitleKey: "keyboard.subtitle")
                {
                    self.keyboardToggle
                }
            }
        }
    }

    @ViewBuilder
    private var settingsControls: some View {
        self.keyboardToggle

        InputPermissionBanner()

        StudioCard("keyboard.behavior", systemImage: "slider.horizontal.3", tint: .blue) {
            SettingsRow("keyboard.mode", subtitleKey: "keyboard.mode.subtitle") {
                Picker("", selection: self.$config.keyboard.displayMode) {
                    Text(self.strings["keyboard.mode.single"]).tag(DisplayMode.single)
                    Text(self.strings["keyboard.mode.history"]).tag(DisplayMode.history)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
            }

            StudioDivider()

            SettingsRow("keyboard.content", subtitleKey: "keyboard.content.subtitle") {
                Picker("", selection: self.$config.keyboard.contentMode) {
                    Text(self.strings["keyboard.content.all"]).tag(KeyboardContentMode.allKeys)
                    Text(self.strings["keyboard.content.shortcuts"]).tag(KeyboardContentMode.shortcutsOnly)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
            }

            StudioDivider()

            SettingsRow("keyboard.timeout", subtitleKey: "keyboard.timeout.subtitle") {
                HStack(spacing: 8) {
                    Slider(value: self.$config.keyboard.timeout, in: 0.5...5.0, step: 0.5)
                        .frame(width: 150)
                    Text(self.config.keyboard.timeout, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                        .frame(width: 26, alignment: .trailing)
                    Text(self.strings["unit.seconds"])
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }

        StudioCard("keyboard.filters", systemImage: "line.3.horizontal.decrease.circle", tint: .cyan) {
            self.filterRow(
                "keyboard.filter.modifiers",
                subtitleKey: "keyboard.filter.modifiers.subtitle",
                binding: self.$config.keyboard.filters.showStandaloneModifiers)

            StudioDivider()

            self.filterRow(
                "keyboard.filter.functions",
                binding: self.$config.keyboard.filters.showFunctionKeys)

            StudioDivider()

            self.filterRow(
                "keyboard.filter.special",
                binding: self.$config.keyboard.filters.showSpecialKeys)
        }

        if self.config.keyboard.displayMode == .history {
            StudioCard(
                "keyboard.history",
                systemImage: "text.line.last.and.arrowtriangle.forward",
                tint: .teal)
            {
                SettingsRow("keyboard.historyLayout") {
                    Picker("", selection: self.$config.keyboard.historyLayout) {
                        Text(self.strings["keyboard.layout.horizontal"]).tag(HistoryLayout.horizontal)
                        Text(self.strings["keyboard.layout.stacked"]).tag(HistoryLayout.stacked)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }

                StudioDivider()

                SettingsRow("keyboard.maxKeys", subtitleKey: "keyboard.maxKeys.subtitle") {
                    Stepper(
                        value: self.$config.keyboard.maxItems,
                        in: 3...12)
                    {
                        Text("\(self.config.keyboard.maxItems)")
                            .monospacedDigit()
                    }
                    .frame(width: 92)
                }

                StudioDivider()

                self.switchRow(
                    "keyboard.duplicates",
                    subtitleKey: "keyboard.duplicates.subtitle",
                    binding: self.$config.keyboard.duplicateLetters)

                if self.config.keyboard.historyLayout == .horizontal {
                    StudioDivider()

                    self.switchRow(
                        "keyboard.limitModifiers",
                        subtitleKey: "keyboard.limitModifiers.subtitle",
                        binding: self.$config.keyboard.limitIncludesModifiers)
                }
            }
        }

        StudioCard("keyboard.animation", systemImage: "sparkles", tint: .orange) {
            self.switchRow(
                "keyboard.animateModifiers",
                subtitleKey: "keyboard.animateModifiers.subtitle",
                binding: self.$config.keyboard.pressAnimationModifiers)

            StudioDivider()

            self.switchRow(
                "keyboard.animateKeys",
                subtitleKey: "keyboard.animateKeys.subtitle",
                binding: self.$config.keyboard.pressAnimationRegularKeys)
        }
    }

    private var keyboardToggle: some View {
        FeatureToggleCard(
            titleKey: "keyboard.enabled",
            subtitleKey: "keyboard.enabled.subtitle",
            systemImage: "keyboard.fill",
            tint: .blue,
            isOn: self.$config.keyboard.enabled)
    }

    private func filterRow(
        _ titleKey: String,
        subtitleKey: String? = nil,
        binding: Binding<Bool>) -> some View
    {
        self.switchRow(titleKey, subtitleKey: subtitleKey, binding: binding)
    }

    private func switchRow(
        _ titleKey: String,
        subtitleKey: String? = nil,
        binding: Binding<Bool>) -> some View
    {
        SettingsRow(titleKey, subtitleKey: subtitleKey) {
            Toggle(self.strings[titleKey], isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(self.strings[titleKey])
        }
    }
}

private struct KeyboardSettingsPreview: View {
    let config: KeypressConfig

    private var keyboardTheme: KeyboardTheme {
        self.config.effectiveTheme(isSystemDark: self.isSystemDark).keyboard
    }

    private var symbols: [KeySymbol] {
        if self.config.keyboard.contentMode == .shortcutsOnly {
            [
                KeySymbol(id: "command-left", display: "⌘", isModifier: true),
                KeySymbol(id: "shift-left", display: "⇧", isModifier: true),
                KeySymbol(id: "k", display: "K"),
            ]
        } else if self.config.keyboard.displayMode == .single {
            [
                KeySymbol(id: "a", display: "A"),
            ]
        } else {
            ["H", "E", "L", "L", "O"].enumerated().map { index, letter in
                KeySymbol(id: "\(letter.lowercased())-\(index)", display: letter)
            }
        }
    }

    var body: some View {
        Group {
            if self.config.keyboard.contentMode == .allKeys,
               self.config.keyboard.displayMode == .history,
               self.config.keyboard.historyLayout == .stacked
            {
                VStack(alignment: .trailing, spacing: 8) {
                    self.previewContainer {
                        self.keys([
                            KeySymbol(id: "command-left", display: "⌘", isModifier: true),
                            KeySymbol(id: "shift-left", display: "⇧", isModifier: true),
                            KeySymbol(id: "k", display: "K"),
                        ])
                    }
                    self.previewContainer {
                        self.keys(
                            ["H", "E", "L", "L", "O"].enumerated().map { index, letter in
                                KeySymbol(id: "\(letter.lowercased())-\(index)", display: letter)
                            })
                    }
                }
            } else {
                self.previewContainer {
                    self.keys(self.symbols)
                }
            }
        }
        .scaleEffect(self.config.keyboard.size.scaleFactor)
        .opacity(self.config.keyboard.opacity)
    }

    private func previewContainer(
        @ViewBuilder keys: @escaping () -> some View) -> some View
    {
        KeyboardThemeContainer(config: self.config, disableOuterShadow: true) {
            keys()
        }
    }

    private func keys(_ symbols: [KeySymbol]) -> some View {
        HStack(spacing: CGFloat(self.keyboardTheme.keySpacing)) {
            ForEach(symbols) { symbol in
                KeyCapView(
                    symbol: symbol,
                    config: self.config,
                    isPressed: symbol.isModifier
                        ? self.config.keyboard.pressAnimationModifiers
                        : self.config.keyboard.pressAnimationRegularKeys)
            }
        }
    }

    private var isSystemDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
