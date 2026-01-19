import KeypressCore
import SwiftUI

// MARK: - ColorSchemePreset

enum ColorSchemePreset: String, CaseIterable {
    case dark
    case monochromeDark
    case light

    var displayName: String {
        switch self {
        case .dark: "Dark (Colored)"
        case .monochromeDark: "Dark (Mono)"
        case .light: "Light"
        }
    }

    var scheme: KeyColorScheme {
        switch self {
        case .dark: .dark
        case .monochromeDark: .monochromeDark
        case .light: .light
        }
    }

    static func from(_ scheme: KeyColorScheme) -> ColorSchemePreset? {
        if scheme == .dark { return .dark }
        if scheme == .monochromeDark { return .monochromeDark }
        if scheme == .light { return .light }
        return nil
    }
}

// MARK: - AppearanceSettingsPane

@MainActor
struct AppearanceSettingsPane: View {
    @Bindable var config: KeypressConfig
    @State private var selectedPreset: ColorSchemePreset = .dark

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
                    HStack(spacing: 12) {
                        ForEach(ColorSchemePreset.allCases, id: \.self) { preset in
                            ColorSchemeButton(
                                preset: preset,
                                isSelected: self.selectedPreset == preset
                            ) {
                                self.selectedPreset = preset
                                self.config.colorScheme = preset.scheme
                            }
                        }
                    }
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
        .onAppear {
            self.selectedPreset = ColorSchemePreset.from(self.config.colorScheme) ?? .dark
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

// MARK: - ColorSchemeButton

@MainActor
struct ColorSchemeButton: View {
    let preset: ColorSchemePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            VStack(spacing: 6) {
                // Color preview squares
                HStack(spacing: 4) {
                    ForEach(self.previewColors, id: \.self) { color in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: 20, height: 20)
                    }
                }

                Text(self.preset.displayName)
                    .font(.caption)
                    .foregroundStyle(self.isSelected ? .primary : .secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(self.isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var previewColors: [Color] {
        let scheme = self.preset.scheme
        return [
            scheme.letter.color,
            scheme.command.color,
            scheme.shift.color,
            scheme.option.color,
        ]
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
