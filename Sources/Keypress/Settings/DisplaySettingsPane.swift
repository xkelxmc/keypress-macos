import KeypressCore
import SwiftUI

// MARK: - DisplaySettingsPane

@MainActor
struct DisplaySettingsPane: View {
    @Bindable var config: KeypressConfig

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Display Mode
                SettingsSection("Display Mode") {
                    Picker("Mode", selection: self.$config.displayMode) {
                        ForEach(DisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)

                    Text(self.config.displayMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
        }
    }

    // MARK: - Single Mode Settings

    @ViewBuilder
    private var singleModeSettings: some View {
        SettingsSection("Single Mode Options") {
            Toggle("Show modifiers only", isOn: self.$config.showModifiersOnly)
                .toggleStyle(.checkbox)

            Text("Only shows key combinations with modifiers (⌘, ⌥, ⌃, ⇧). Regular letters and numbers are hidden.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - History Mode Settings

    @ViewBuilder
    private var historyModeSettings: some View {
        SettingsSection("History Mode Options") {
            SettingsRow("Max keys", subtitle: "Maximum keys displayed at once") {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { Double(self.config.maxKeys) },
                            set: { self.config.maxKeys = Int($0) }
                        ),
                        in: 3 ... 12,
                        step: 1
                    )
                    .frame(width: 120)
                    Text("\(self.config.maxKeys)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
            }

            Toggle("Duplicate letters", isOn: self.$config.duplicateLetters)
                .toggleStyle(.checkbox)

            Text("When enabled, typing \"hello\" shows 5 keys. When disabled, shows 4 (no repeat).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .padding(.vertical, 4)

            Toggle("Limit includes modifiers", isOn: self.$config.limitIncludesModifiers)
                .toggleStyle(.checkbox)

            Text("When enabled, max keys limit applies to all keys. When disabled, modifiers don't count towards the limit.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
            "Shows only the latest keystroke. Each new key replaces the previous. Best for shortcut demos."
        case .history:
            "Shows a queue of recent keystrokes. Keys accumulate and fade over time. Best for typing demos."
        }
    }
}
