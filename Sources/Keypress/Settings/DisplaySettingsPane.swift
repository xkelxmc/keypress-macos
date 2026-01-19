import KeypressCore
import SwiftUI

// MARK: - DisplaySettingsPane

@MainActor
struct DisplaySettingsPane: View {
    @Bindable var config: KeypressConfig

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Display Mode
                SettingsRow("Display Mode", subtitle: self.config.displayMode.description) {
                    Picker("", selection: self.$config.displayMode) {
                        ForEach(DisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                Divider()

                // Mode-specific settings
                if self.config.displayMode == .single {
                    self.singleModeSettings
                } else {
                    self.historyModeSettings
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Single Mode Settings

    @ViewBuilder
    private var singleModeSettings: some View {
        SettingsRow(
            "Show modifiers only",
            subtitle: "Only show key combinations with modifiers (⌘, ⌥, ⌃, ⇧)")
        {
            Toggle("", isOn: self.$config.showModifiersOnly)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    // MARK: - History Mode Settings

    @ViewBuilder
    private var historyModeSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsRow("Max keys", subtitle: "Maximum keys displayed at once") {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { Double(self.config.maxKeys) },
                            set: { self.config.maxKeys = Int($0) }),
                        in: 3...12,
                        step: 1)
                        .frame(width: 120)
                    Text("\(self.config.maxKeys)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
            }

            Divider()

            SettingsRow(
                "Duplicate letters",
                subtitle: "Show repeated keys (e.g., \"hello\" shows 5 keys)")
            {
                Toggle("", isOn: self.$config.duplicateLetters)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Divider()

            SettingsRow(
                "Limit includes modifiers",
                subtitle: "Count modifier keys towards max limit")
            {
                Toggle("", isOn: self.$config.limitIncludesModifiers)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }
}

// MARK: - DisplayMode Extension

extension DisplayMode {
    var displayName: String {
        switch self {
        case .single: "Single"
        case .history: "History"
        }
    }

    var description: String {
        switch self {
        case .single:
            "Shows only the latest keystroke"
        case .history:
            "Shows a queue of recent keystrokes"
        }
    }
}
