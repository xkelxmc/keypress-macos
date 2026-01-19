import KeypressCore
import SwiftUI

// MARK: - SettingsTab

enum SettingsTab: String, Hashable {
    case general
    case display
    case appearance
}

// MARK: - SettingsView

@MainActor
struct SettingsView: View {
    @Bindable var config: KeypressConfig
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: self.$selectedTab) {
            GeneralSettingsPane(config: self.config)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            DisplaySettingsPane(config: self.config)
                .tabItem { Label("Display", systemImage: "rectangle.on.rectangle") }
                .tag(SettingsTab.display)

            AppearanceSettingsPane(config: self.config)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag(SettingsTab.appearance)
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 480)
    }
}

// MARK: - Reusable Components

@MainActor
struct SettingsSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(self.title)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 10) {
                self.content()
            }
        }
    }
}

@MainActor
struct SettingsRow<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: () -> Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(self.title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            self.content()
        }
    }
}
