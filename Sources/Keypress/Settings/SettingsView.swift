import AppKit
import KeypressCore
import Observation
import SwiftUI

enum SettingsDestination: String, CaseIterable, Hashable, Identifiable {
    case setup
    case general
    case pointerAppearance = "pointer.appearance"
    case pointerSettings = "pointer.settings"
    case keyboardAppearance = "keyboard.appearance"
    case keyboardSettings = "keyboard.settings"
    case keyboardDisplays = "keyboard.displays"
    case shortcuts
    case about

    var id: Self {
        self
    }

    var titleKey: String {
        switch self {
        case .setup: "sidebar.setup"
        case .general: "sidebar.general"
        case .pointerAppearance, .keyboardAppearance: "sidebar.appearance"
        case .pointerSettings, .keyboardSettings: "sidebar.settings"
        case .keyboardDisplays: "sidebar.displays"
        case .shortcuts: "sidebar.shortcuts"
        case .about: "sidebar.about"
        }
    }

    var systemImage: String {
        switch self {
        case .setup: "sparkles"
        case .general: "gearshape.fill"
        case .pointerAppearance, .keyboardAppearance: "paintpalette.fill"
        case .pointerSettings: "cursorarrow.motionlines"
        case .keyboardSettings: "keyboard.fill"
        case .keyboardDisplays: "display.2"
        case .shortcuts: "command"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .setup: .purple
        case .general: .gray
        case .pointerAppearance, .pointerSettings: .orange
        case .keyboardAppearance, .keyboardSettings: .blue
        case .keyboardDisplays: .cyan
        case .shortcuts: .pink
        case .about: .indigo
        }
    }
}

@MainActor
@Observable
final class SettingsNavigationState {
    var selectedDestination: SettingsDestination? = .general
}

@MainActor
struct SettingsView: View {
    @Bindable var config: KeypressConfig
    @Bindable var navigation: SettingsNavigationState
    @Bindable var onboardingProgress: OnboardingProgressStore

    init(
        config: KeypressConfig,
        navigation: SettingsNavigationState,
        onboardingProgress: OnboardingProgressStore = .shared)
    {
        self.config = config
        self.navigation = navigation
        self.onboardingProgress = onboardingProgress
    }

    private var strings: StudioStrings {
        StudioStrings(languageCode: self.config.general.language.studioLanguageCode)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: self.$navigation.selectedDestination) {
                if self.showsSetup {
                    Section {
                        self.sidebarDestination(.setup)
                    }
                }

                Section {
                    self.sidebarDestination(.general)
                }

                Section {
                    self.sidebarDestination(.pointerSettings)
                    self.sidebarDestination(.pointerAppearance)
                } header: {
                    StudioSidebarSectionTitle(self.strings["sidebar.section.pointer"])
                }

                Section {
                    self.sidebarDestination(.keyboardSettings)
                    self.sidebarDestination(.keyboardAppearance)
                    self.sidebarDestination(.keyboardDisplays)
                } header: {
                    StudioSidebarSectionTitle(self.strings["sidebar.section.keyboard"])
                }

                Section {
                    self.sidebarDestination(.shortcuts)
                    self.sidebarDestination(.about)
                } header: {
                    StudioSidebarSectionTitle("Keypress")
                }
            }
            .navigationSplitViewColumnWidth(min: 196, ideal: 220, max: 244)
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: self.showsSetup ? 42 : 8)
                    .accessibilityHidden(true)
            }
            .background {
                ZStack {
                    Rectangle()
                        .fill(.regularMaterial)
                    Color(nsColor: .controlBackgroundColor)
                        .opacity(0.28)
                }
                .ignoresSafeArea()
            }
        } detail: {
            self.detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, minHeight: 620)
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.studioStrings, self.strings)
        .environment(\.locale, self.strings.locale)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification))
        { _ in
            self.refreshSetupState()
        }
        .onChange(of: self.config.general.enabled) {
                self.refreshSetupState()
            }
            .onChange(of: self.showsSetup) {
                if !self.showsSetup, self.navigation.selectedDestination == .setup {
                    self.navigation.selectedDestination = .general
                }
            }
    }

    private func sidebarDestination(_ destination: SettingsDestination) -> some View {
        StudioSidebarLabel(destination: destination)
            .tag(destination)
    }

    @ViewBuilder
    private var detail: some View {
        switch self.navigation.selectedDestination ?? .general {
        case .setup:
            SetupSettingsPane(
                config: self.config,
                progress: self.onboardingProgress)
        case .general:
            GeneralSettingsPane(config: self.config)
        case .keyboardSettings:
            KeyboardSettingsPane(config: self.config)
        case .pointerSettings:
            PointerSettingsPane(config: self.config)
        case .pointerAppearance:
            PointerAppearanceSettingsPane(
                config: self.config,
                openSettings: { self.navigation.selectedDestination = .pointerSettings })
        case .keyboardAppearance:
            KeyboardAppearanceSettingsPane(
                config: self.config,
                openSettings: { self.navigation.selectedDestination = .keyboardSettings })
        case .keyboardDisplays:
            PositionSettingsPane(
                config: self.config,
                openSettings: { self.navigation.selectedDestination = .keyboardSettings })
        case .shortcuts:
            ShortcutsSettingsPane()
        case .about:
            AboutSettingsPane()
        }
    }

    private var showsSetup: Bool {
        self.onboardingProgress.needsSetup(config: self.config)
    }

    private func refreshSetupState() {
        self.onboardingProgress.reconcileReadyState(
            config: self.config,
            onboardingIsPresenting: OnboardingController.shared.isPresenting)
        if !self.showsSetup, self.navigation.selectedDestination == .setup {
            self.navigation.selectedDestination = .general
        }
    }
}

private struct StudioSidebarSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(self.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct StudioSidebarLabel: View {
    @Environment(\.studioStrings) private var strings
    let destination: SettingsDestination

    var body: some View {
        Label {
            Text(self.strings[self.destination.titleKey])
        } icon: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: self.destination.systemImage)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(self.destination.tint.gradient, in: RoundedRectangle(cornerRadius: 5))

                if self.destination == .setup {
                    Circle()
                        .fill(.white)
                        .frame(width: 6, height: 6)
                        .overlay {
                            Circle().stroke(self.destination.tint, lineWidth: 1)
                        }
                        .offset(x: 2, y: -2)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

@MainActor
struct StudioPage<Content: View>: View {
    let titleKey: String
    let subtitleKey: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                self.content()
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            StudioPinnedRegion {
                StudioPageHeader(
                    titleKey: self.titleKey,
                    subtitleKey: self.subtitleKey,
                    identity: self.identity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    var identity: (systemImage: String, tint: Color) {
        switch self.titleKey {
        case "onboarding.settings.title":
            ("sparkles", .purple)
        case "general.title":
            ("gearshape.fill", .gray)
        case "pointer.appearance.title":
            ("paintpalette.fill", .orange)
        case "pointer.title":
            ("cursorarrow.motionlines", .orange)
        case "keyboard.appearance.title":
            ("paintpalette.fill", .blue)
        case "keyboard.title":
            ("keyboard.fill", .blue)
        case "displays.title":
            ("display.2", .cyan)
        case "shortcuts.title":
            ("command", .pink)
        case "about.title":
            ("info.circle.fill", .indigo)
        default:
            ("gearshape.fill", .accentColor)
        }
    }
}

@MainActor
struct StudioPreviewPage<Preview: View, Content: View>: View {
    let titleKey: String
    let subtitleKey: String
    @ViewBuilder let preview: () -> Preview
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                self.content()
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            StudioPinnedRegion {
                VStack(spacing: 0) {
                    StudioPageHeader(
                        titleKey: self.titleKey,
                        subtitleKey: self.subtitleKey,
                        identity: self.identity)

                    self.preview()
                        .frame(maxWidth: 820)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 14)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var identity: (systemImage: String, tint: Color) {
        switch self.titleKey {
        case "pointer.appearance.title":
            ("paintpalette.fill", .orange)
        case "keyboard.appearance.title":
            ("paintpalette.fill", .blue)
        case "keyboard.title":
            ("keyboard.fill", .blue)
        default:
            ("gearshape.fill", .accentColor)
        }
    }
}

@MainActor
private struct StudioPinnedRegion<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        self.content()
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: Color(nsColor: .windowBackgroundColor).opacity(0.82), location: 0),
                        .init(color: Color(nsColor: .windowBackgroundColor).opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom)
                    .frame(height: 18)
                    .offset(y: 18)
                    .allowsHitTesting(false)
            }
            .zIndex(10)
    }
}

@MainActor
private struct StudioPageHeader: View {
    @Environment(\.studioStrings) private var strings
    let titleKey: String
    let subtitleKey: String
    let identity: (systemImage: String, tint: Color)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: self.identity.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(self.identity.tint)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(
                    self.identity.tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(self.strings[self.titleKey])
                    .font(.system(size: 26, weight: .bold))
                Text(self.strings[self.subtitleKey])
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 580, alignment: .leading)
            }
        }
        .frame(maxWidth: 820, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
struct StudioCard<Content: View>: View {
    @Environment(\.studioStrings) private var strings
    let titleKey: String?
    let systemImage: String?
    let tint: Color
    @ViewBuilder let content: () -> Content

    init(
        _ titleKey: String? = nil,
        systemImage: String? = nil,
        tint: Color = .accentColor,
        @ViewBuilder content: @escaping () -> Content)
    {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.tint = tint
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let titleKey = self.titleKey {
                HStack(spacing: 8) {
                    if let systemImage = self.systemImage {
                        Image(systemName: systemImage)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(self.tint)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 20)
                            .accessibilityHidden(true)
                    }

                    Text(self.strings[titleKey])
                        .font(.headline)
                }
                .padding(.leading, 2)
            }

            VStack(alignment: .leading, spacing: 14) {
                self.content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
struct FeatureToggleCard: View {
    @Environment(\.studioStrings) private var strings
    let titleKey: String
    let subtitleKey: String
    let systemImage: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: self.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(self.tint)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(self.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.strings[self.titleKey])
                    .font(.headline)
                Text(self.strings[self.subtitleKey])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Toggle(self.strings[self.titleKey], isOn: self.$isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(self.strings[self.titleKey])
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@MainActor
struct DestructiveSettingsAction: View {
    @Environment(\.studioStrings) private var strings
    let titleKey: String
    let subtitleKey: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: self.action) {
            HStack(spacing: 12) {
                Image(systemName: self.systemImage)
                    .font(.title3)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(self.strings[self.titleKey])
                        .font(.headline)
                    Text(self.strings[self.subtitleKey])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity)
        .background(
            Color.red.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.red.opacity(0.15))
        }
    }
}

@MainActor
struct InputPermissionBanner: View {
    @Environment(\.studioStrings) private var strings
    @State private var isGranted = OnboardingProgressStore.shared.permissionGranted

    var body: some View {
        Group {
            if !self.isGranted {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.strings["general.permission.required"])
                            .fontWeight(.medium)
                        Text(self.strings["general.permission.subtitle"])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Button(self.strings["general.permission.open"]) {
                        let alreadyGranted = InputMonitoringPermission.request()
                        if alreadyGranted {
                            self.isGranted = true
                            OnboardingProgressStore.shared.updatePermission(true)
                        } else {
                            Task {
                                await self.openPermissionSettingsIfNeeded()
                            }
                        }
                    }
                }
                .padding(14)
                .background(
                    Color.orange.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .task {
            await self.refreshPermission()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification))
        { _ in
            Task {
                await self.refreshPermission()
            }
        }
    }

    private func refreshPermission() async {
        let permissionGranted = await Task.detached(priority: .userInitiated) {
            InputMonitoringPermission.isReady()
        }.value
        OnboardingProgressStore.shared.updatePermission(permissionGranted)
        self.isGranted = permissionGranted
    }

    private func openPermissionSettingsIfNeeded() async {
        await self.refreshPermission()
        if !self.isGranted {
            InputMonitoringPermission.openSettings()
        }
    }
}

@MainActor
struct SettingsRow<Content: View>: View {
    @Environment(\.studioStrings) private var strings
    let titleKey: String
    let subtitleKey: String?
    @ViewBuilder let content: () -> Content

    init(_ titleKey: String, subtitleKey: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.titleKey = titleKey
        self.subtitleKey = subtitleKey
        self.content = content
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                self.label
                Spacer(minLength: 24)
                self.content()
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                self.label
                self.content()
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(self.strings[self.titleKey])
                .font(.body)
            if let subtitleKey {
                Text(self.strings[subtitleKey])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StudioDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 2)
    }
}

struct StudioPreviewSurface<Content: View>: View {
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    init(height: CGFloat = 190, @ViewBuilder content: @escaping () -> Content) {
        self.height = height
        self.content = content
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.105, green: 0.115, blue: 0.135),
                    Color(red: 0.15, green: 0.165, blue: 0.195),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.045),
                    .clear,
                ],
                startPoint: .top,
                endPoint: .center)

            self.content()
        }
        .frame(height: self.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.075), lineWidth: 1)
        }
    }
}

@MainActor
struct DisabledFeatureView: View {
    @Environment(\.studioStrings) private var strings
    let titleKey: String
    let subtitleKey: String
    let buttonKey: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: self.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(self.tint)
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 64, height: 64)
                .background(
                    self.tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(self.strings[self.titleKey])
                .font(.title3.weight(.semibold))

            Text(self.strings[self.subtitleKey])
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button(self.strings[self.buttonKey], action: self.action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}
