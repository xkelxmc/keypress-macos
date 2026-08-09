import AppKit
import KeypressCore
import SwiftUI

@MainActor
struct KeyboardSettingsPane: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig

    var body: some View {
        if self.config.keyboard.enabled {
            StudioPreviewPage(
                titleKey: "keyboard.title",
                subtitleKey: "keyboard.subtitle",
                preview: {
                    StudioPreviewSurface(height: 166) {
                        KeyboardPresentationDemo(
                            config: self.config,
                            replayLabel: self.strings["onboarding.keyboard.replay"])
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

    @ViewBuilder
    private var settingsControls: some View {
        self.keyboardToggle

        InputPermissionBanner()

        StudioCard("keyboard.behavior", systemImage: "slider.horizontal.3", tint: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.strings["keyboard.mode"])
                        .font(.body)
                    Text(self.strings["keyboard.mode.subtitle"])
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    ForEach(KeyboardPresentation.allCases, id: \.self) { presentation in
                        self.presentationCard(presentation)
                    }
                }
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

        StudioCard("keyboard.inputKeys", systemImage: "space", tint: .indigo) {
            SettingsRow("keyboard.inputKeys.width", subtitleKey: "keyboard.inputKeys.width.subtitle") {
                Picker("", selection: self.$config.keyboard.inputKeys.widthMode) {
                    Text(self.strings["keyboard.inputKeys.width.wide"])
                        .tag(InputKeyWidthMode.wide)
                    Text(self.strings["keyboard.inputKeys.width.narrow"])
                        .tag(InputKeyWidthMode.narrow)
                    Text(self.strings["keyboard.inputKeys.width.custom"])
                        .tag(InputKeyWidthMode.custom)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            if self.config.keyboard.inputKeys.widthMode == .custom {
                ForEach(InputKey.allCases, id: \.self) { key in
                    StudioDivider()
                    self.inputKeyWidthRow(key)
                }
            }

            StudioDivider()

            self.switchRow(
                "keyboard.inputKeys.tint",
                subtitleKey: "keyboard.inputKeys.tint.subtitle",
                binding: self.$config.keyboard.inputKeys.highlight)
        }

        if self.config.keyboard.presentation == .horizontalHistory {
            StudioCard("keyboard.commandZone", systemImage: "rectangle.split.1x2", tint: .purple) {
                SettingsRow("keyboard.commandZone.side", subtitleKey: "keyboard.commandZone.side.subtitle") {
                    Picker("", selection: self.$config.keyboard.commandZoneSide) {
                        Text(self.strings["keyboard.commandZone.side.auto"]).tag(CommandZoneSide.auto)
                        Text(self.strings["keyboard.commandZone.side.left"]).tag(CommandZoneSide.left)
                        Text(self.strings["keyboard.commandZone.side.right"]).tag(CommandZoneSide.right)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }
            }
        }

        if self.config.keyboard.presentation != .latest {
            StudioCard(
                "keyboard.history",
                systemImage: "text.line.last.and.arrowtriangle.forward",
                tint: .teal)
            {
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

                if self.config.keyboard.presentation == .horizontalHistory {
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

    private func presentationCard(_ presentation: KeyboardPresentation) -> some View {
        let selected = self.config.keyboard.presentation == presentation

        return Button {
            self.presentationBinding.wrappedValue = presentation
        } label: {
            VStack(spacing: 9) {
                OnboardingPresentationArtwork(
                    presentation: presentation,
                    contentMode: self.config.keyboard.contentMode)
                    .frame(height: 54)
                    .accessibilityHidden(true)

                Text(self.strings[presentation.onboardingTitleKey])
                    .font(.caption.weight(selected ? .bold : .medium))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(11)
            .frame(maxWidth: .infinity)
            .background(
                selected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor : Color.primary.opacity(0.08),
                        lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(StudioHoverButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var presentationBinding: Binding<KeyboardPresentation> {
        Binding(
            get: { self.config.keyboard.presentation },
            set: { presentation in
                var keyboard = self.config.keyboard
                keyboard.presentation = presentation
                self.config.keyboard = keyboard
            })
    }

    private func filterRow(
        _ titleKey: String,
        subtitleKey: String? = nil,
        binding: Binding<Bool>) -> some View
    {
        self.switchRow(titleKey, subtitleKey: subtitleKey, binding: binding)
    }

    private func inputKeyWidthRow(_ key: InputKey) -> some View {
        SettingsRow(key.localizationKey) {
            Picker("", selection: self.widthBinding(for: key)) {
                Text(self.strings["keyboard.inputKeys.width.wide"]).tag(true)
                Text(self.strings["keyboard.inputKeys.width.narrow"]).tag(false)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 170)
        }
    }

    private func widthBinding(for key: InputKey) -> Binding<Bool> {
        Binding(
            get: { self.config.keyboard.inputKeys.widths[key] },
            set: { self.config.keyboard.inputKeys.widths[key] = $0 })
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

extension InputKey {
    fileprivate var localizationKey: String {
        switch self {
        case .space: "key.space"
        case .enter: "key.enter"
        case .backspace: "key.backspace"
        case .tab: "key.tab"
        }
    }
}
