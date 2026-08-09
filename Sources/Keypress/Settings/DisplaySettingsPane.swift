import AppKit
import KeypressCore
import SwiftUI

@MainActor
struct KeyboardSettingsPane: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig

    @State private var replayTrigger = 0

    var body: some View {
        if self.config.keyboard.enabled {
            StudioPreviewPage(
                titleKey: "keyboard.title",
                subtitleKey: "keyboard.subtitle",
                preview: {
                    StudioPreviewSurface(height: 166) {
                        KeyboardPresentationDemo(
                            config: self.config,
                            replayTrigger: self.replayTrigger)
                    } accessory: {
                        StudioPreviewReplayButton(
                            label: self.strings["onboarding.keyboard.replay"])
                        {
                            self.replayTrigger += 1
                        }
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

            // A two-zone mode has already split input the way Shortcuts Only asks for, so the
            // choice belongs to Latest alone.
            if self.config.keyboard.presentation == .latest {
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
            }

            StudioDivider()

            self.secondsRow(
                "keyboard.timeout",
                subtitleKey: "keyboard.timeout.subtitle",
                value: self.$config.keyboard.timeout,
                range: 0.5...5)

            // The echo's two clocks sit with the timeout they stand beside: all three say how
            // long something stays on screen, and reading one without the others tells you
            // little.
            if self.config.keyboard.presentation == .stackedHistory {
                StudioDivider()

                self.secondsRow(
                    "keyboard.echo.lineLifetime",
                    subtitleKey: "keyboard.echo.lineLifetime.subtitle",
                    value: self.$config.keyboard.textLineLifetime,
                    range: KeyboardSettings.textLineLifetimeRange)

                StudioDivider()

                self.secondsRow(
                    "keyboard.echo.idleTimeout",
                    subtitleKey: "keyboard.echo.idleTimeout.subtitle",
                    value: self.$config.keyboard.textIdleTimeout,
                    range: KeyboardSettings.textIdleTimeoutRange)
            }
        }

        StudioCard("keyboard.filters", systemImage: "line.3.horizontal.decrease.circle", tint: .cyan) {
            self.filterRow(
                "keyboard.filter.modifiers",
                subtitleKey: "keyboard.filter.modifiers.subtitle",
                binding: self.$config.keyboard.filters.showStandaloneModifiers)

            // The two-zone modes route a key by what it produces, so a category switch has
            // nothing to decide there and is not offered.
            if self.config.keyboard.presentation == .latest {
                StudioDivider()

                self.filterRow(
                    "keyboard.filter.functions",
                    subtitleKey: "keyboard.filter.functions.subtitle",
                    binding: self.$config.keyboard.filters.showFunctionKeys)

                StudioDivider()

                self.filterRow(
                    "keyboard.filter.special",
                    subtitleKey: "keyboard.filter.special.subtitle",
                    binding: self.$config.keyboard.filters.showSpecialKeys)
            }
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

        // The echo's line count is fixed, so only the ribbon has a length to set.
        if self.config.keyboard.presentation == .horizontalHistory {
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

    private func secondsRow(
        _ titleKey: String,
        subtitleKey: String,
        value: Binding<TimeInterval>,
        range: ClosedRange<TimeInterval>) -> some View
    {
        SettingsRow(titleKey, subtitleKey: subtitleKey) {
            HStack(spacing: 8) {
                Slider(value: value, in: range, step: 0.5)
                    .frame(width: 150)
                Text(value.wrappedValue, format: .number.precision(.fractionLength(1)))
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
                Text(self.strings["unit.seconds"])
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
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
