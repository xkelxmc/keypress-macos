import KeyboardShortcuts
import KeypressCore
import ServiceManagement
import SwiftUI

// MARK: - GeneralSettingsPane

@MainActor
struct GeneralSettingsPane: View {
    @Bindable var config: KeypressConfig

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Appearance
                SettingsSection("Appearance") {
                    SettingsRow("Size") {
                        Picker("Size", selection: self.$config.size) {
                            ForEach(OverlaySize.allCases, id: \.self) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }

                    SettingsRow("Opacity") {
                        HStack(spacing: 8) {
                            Slider(value: self.$config.opacity, in: 0.3...1.0)
                                .frame(width: 120)
                            Text("\(Int(round(self.config.opacity * 100)))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }

                Divider()

                // Behavior
                SettingsSection("Behavior") {
                    SettingsRow("Key timeout", subtitle: "How long keys stay visible") {
                        HStack(spacing: 8) {
                            Slider(value: self.$config.keyTimeout, in: 0.5...5.0, step: 0.5)
                                .frame(width: 120)
                            Text(String(format: "%.1fs", self.config.keyTimeout))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                }

                Divider()

                // System
                SettingsSection("System") {
                    Toggle("Launch at login", isOn: self.$config.launchAtLogin)
                        .toggleStyle(.checkbox)
                        .onChange(of: self.config.launchAtLogin) { _, newValue in
                            self.updateLaunchAtLogin(newValue)
                        }
                }

                Divider()

                // Shortcuts
                SettingsSection("Shortcuts") {
                    SettingsRow("Toggle overlay", subtitle: "Global hotkey to show/hide") {
                        KeyboardShortcuts.Recorder(for: .toggleOverlay)
                            .frame(width: 150)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.horizontal, 12)
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert on failure
            self.config.launchAtLogin = !enabled
        }
    }
}

// MARK: - OverlaySize Extension

extension OverlaySize {
    var displayName: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}
