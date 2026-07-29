import AppKit
import KeyboardShortcuts
import KeypressCore
import ServiceManagement
import SwiftUI

@MainActor
struct GeneralSettingsPane: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig
    @State private var permissionGranted = InputMonitoringPermission.check()
    @State private var activeAlert: GeneralSettingsAlert?

    var body: some View {
        StudioPage(
            titleKey: "general.title",
            subtitleKey: "general.subtitle")
        {
            FeatureToggleCard(
                titleKey: "general.enabled",
                subtitleKey: "general.enabled.subtitle",
                systemImage: "power",
                tint: .blue,
                isOn: self.$config.general.enabled)

            StudioCard("general.app", systemImage: "gearshape.fill", tint: .blue) {
                SettingsRow("general.launchAtLogin", subtitleKey: "general.launchAtLogin.subtitle") {
                    Toggle(
                        self.strings["general.launchAtLogin"],
                        isOn: self.launchAtLoginBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(self.strings["general.launchAtLogin"])
                }

                StudioDivider()

                SettingsRow("general.language", subtitleKey: "general.language.subtitle") {
                    Picker("", selection: self.$config.general.language) {
                        Text(self.strings["language.system"]).tag(AppLanguage.system)
                        Text("English").tag(AppLanguage.english)
                        Text("Русский").tag(AppLanguage.russian)
                        Text("Deutsch").tag(AppLanguage.german)
                        Text("Español").tag(AppLanguage.spanish)
                        Text("Français").tag(AppLanguage.french)
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            StudioCard("general.hud", systemImage: "rectangle.and.text.magnifyingglass", tint: .purple) {
                SettingsRow("general.hud.enabled", subtitleKey: "general.hud.enabled.subtitle") {
                    Toggle(
                        self.strings["general.hud.enabled"],
                        isOn: self.$config.hud.enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel(self.strings["general.hud.enabled"])
                }

                if self.config.hud.enabled {
                    StudioDivider()

                    SettingsRow("general.hud.duration", subtitleKey: "general.hud.duration.subtitle") {
                        HStack(spacing: 8) {
                            Slider(value: self.$config.hud.duration, in: 0.5...4, step: 0.5)
                                .frame(width: 150)
                            Text(self.config.hud.duration, format: .number.precision(.fractionLength(1)))
                                .font(.caption.monospacedDigit())
                                .frame(width: 26, alignment: .trailing)
                            Text(self.strings["unit.seconds"])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            StudioCard("general.permission", systemImage: "hand.raised.fill", tint: self.permissionTint) {
                HStack(spacing: 12) {
                    Image(systemName: self
                        .permissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(self.permissionTint)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(self.strings[
                            self.permissionGranted ? "general.permission.granted" : "general.permission.required"
                        ])
                        .fontWeight(.medium)

                        Text(self.strings["general.permission.subtitle"])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !self.permissionGranted {
                        Button(self.strings["general.permission.open"]) {
                            let alreadyGranted = InputMonitoringPermission.request()
                            if alreadyGranted {
                                self.permissionGranted = true
                                OnboardingProgressStore.shared.updatePermission(true)
                            } else {
                                Task {
                                    await self.openPermissionSettingsIfNeeded()
                                }
                            }
                        }
                    }

                    Button {
                        Task {
                            await self.refreshPermission()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(self.strings["general.permission.check"])
                }
            }

            DestructiveSettingsAction(
                titleKey: "general.reset",
                subtitleKey: "general.reset.confirm.message",
                systemImage: "trash.fill")
            {
                self.activeAlert = .resetConfirmation
            }
        }
        .alert(item: self.$activeAlert) { alert in
            switch alert {
            case .resetConfirmation:
                Alert(
                    title: Text(self.strings["general.reset.confirm.title"]),
                    message: Text(self.strings["general.reset.confirm.message"]),
                    primaryButton: .destructive(Text(self.strings["general.reset"])) {
                        self.resetAllSettings()
                    },
                    secondaryButton: .cancel(Text(self.strings["action.cancel"])))
            case let .resetFailure(message):
                Alert(
                    title: Text(self.strings["general.reset.confirm.title"]),
                    message: Text(message),
                    dismissButton: .default(Text(self.strings["action.done"])))
            case let .operationFailure(message):
                Alert(
                    title: Text(self.strings["general.app"]),
                    message: Text(message),
                    dismissButton: .default(Text(self.strings["action.done"])))
            }
        }
        .onAppear {
            self.synchronizeLaunchAtLogin()
            Task {
                await self.refreshPermission()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            self.synchronizeLaunchAtLogin()
            Task {
                await self.refreshPermission()
            }
        }
    }

    private var permissionTint: Color {
        self.permissionGranted ? .green : .orange
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { self.config.general.launchAtLogin },
            set: { self.updateLaunchAtLogin($0) })
    }

    private func refreshPermission() async {
        let permissionGranted = await Task.detached(priority: .userInitiated) {
            InputMonitoringPermission.isReady()
        }.value
        self.permissionGranted = permissionGranted
        OnboardingProgressStore.shared.updatePermission(permissionGranted)
    }

    private func openPermissionSettingsIfNeeded() async {
        await self.refreshPermission()
        if !self.permissionGranted {
            InputMonitoringPermission.openSettings()
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            self.config.general.launchAtLogin = enabled
        } catch {
            print("[Keypress] ERROR: Failed to update launch at login: \(error)")
            self.activeAlert = .operationFailure(error.localizedDescription)
        }
    }

    private func synchronizeLaunchAtLogin() {
        let isRegistered = SMAppService.mainApp.status == .enabled
        if self.config.general.launchAtLogin != isRegistered {
            self.config.general.launchAtLogin = isRegistered
        }
    }

    private func resetAllSettings() {
        do {
            let loginStatus = SMAppService.mainApp.status
            if loginStatus == .enabled || loginStatus == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            self.activeAlert = .resetFailure(error.localizedDescription)
            return
        }

        [
            KeyboardShortcuts.Name.toggleOverlay,
            .togglePointer,
            .switchContentMode,
            .editPosition,
            .increaseOverlaySize,
            .decreaseOverlaySize,
        ].forEach { KeyboardShortcuts.reset($0) }
        self.config.resetToDefaults()
        self.synchronizeLaunchAtLogin()
    }
}

private enum GeneralSettingsAlert: Identifiable {
    case resetConfirmation
    case resetFailure(String)
    case operationFailure(String)

    var id: Int {
        switch self {
        case .resetConfirmation: 0
        case .resetFailure: 1
        case .operationFailure: 2
        }
    }
}
