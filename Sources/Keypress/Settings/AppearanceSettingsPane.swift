import KeypressCore
import SwiftUI

// MARK: - AppearanceSettingsPane

@MainActor
struct AppearanceSettingsPane: View {
    @Bindable var config: KeypressConfig

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Keycap Style
                SettingsSection("Keycap Style") {
                    Picker("Style", selection: self.$config.keyCapStyle) {
                        ForEach(KeyCapStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)

                    Text(self.config.keyCapStyle.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Color Scheme
                SettingsSection("Color Scheme") {
                    Picker("Appearance", selection: self.$config.appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)

                    Text(self.appearanceModeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Preview
                SettingsSection("Preview") {
                    KeyPreview(config: self.config)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appearanceModeDescription: String {
        switch self.config.appearanceMode {
        case .auto: "Follows system light/dark mode."
        case .dark: "Dark keys with colored modifiers."
        case .monochrome: "All dark keys, no color."
        case .light: "Light keys with colored modifiers."
        }
    }
}

// MARK: - KeyCapStyle Extension

extension KeyCapStyle {
    var displayName: String {
        switch self {
        case .mechanical: "Mechanical"
        case .flat: "Flat"
        case .minimal: "Minimal"
        }
    }

    var description: String {
        switch self {
        case .mechanical: "3D skeuomorphic keycaps with depth and shadows."
        case .flat: "Modern flat design with subtle shadows. (Coming soon)"
        case .minimal: "Text only with simple background. (Coming soon)"
        }
    }
}

// MARK: - KeyPreview

@MainActor
struct KeyPreview: View {
    let config: KeypressConfig

    var body: some View {
        HStack(spacing: 8) {
            self.previewKey(text: "⌘", category: .command)
            self.previewKey(text: "⇧", category: .shift)
            self.previewKey(text: "K", category: .letter)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.8))
        )
    }

    @ViewBuilder
    private func previewKey(text: String, category: KeyCategory) -> some View {
        let color = self.config.colorScheme.color(for: category).color

        Text(text)
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color)
            )
    }
}
