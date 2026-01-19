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
                // Position
                SettingsSection("Position") {
                    PositionPicker(position: self.$config.position)
                }

                Divider()

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
                            Slider(value: self.$config.opacity, in: 0.3 ... 1.0, step: 0.1)
                                .frame(width: 120)
                            Text("\(Int(self.config.opacity * 100))%")
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
                            Slider(value: self.$config.keyTimeout, in: 0.5 ... 5.0, step: 0.5)
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

// MARK: - PositionPicker

@MainActor
struct PositionPicker: View {
    @Binding var position: OverlayPosition

    private let gridSize: CGFloat = 160
    private let dotSize: CGFloat = 16

    var body: some View {
        ZStack {
            // Monitor frame
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.5), lineWidth: 2)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                )

            // Position dots
            ForEach(OverlayPosition.allCases, id: \.self) { pos in
                Circle()
                    .fill(pos == self.position ? Color.accentColor : Color.secondary.opacity(0.4))
                    .frame(width: self.dotSize, height: self.dotSize)
                    .overlay(
                        Circle()
                            .stroke(pos == self.position ? Color.accentColor : Color.clear, lineWidth: 2)
                            .frame(width: self.dotSize + 4, height: self.dotSize + 4)
                    )
                    .position(self.dotPosition(for: pos))
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            self.position = pos
                        }
                    }
            }
        }
        .frame(width: self.gridSize, height: self.gridSize * 0.625) // 16:10 aspect ratio
        .contentShape(Rectangle())
    }

    private func dotPosition(for pos: OverlayPosition) -> CGPoint {
        let width = self.gridSize
        let height = self.gridSize * 0.625
        let margin: CGFloat = 16

        switch pos {
        case .topLeft:
            return CGPoint(x: margin, y: margin)
        case .topCenter:
            return CGPoint(x: width / 2, y: margin)
        case .topRight:
            return CGPoint(x: width - margin, y: margin)
        case .centerLeft:
            return CGPoint(x: margin, y: height / 2)
        case .centerRight:
            return CGPoint(x: width - margin, y: height / 2)
        case .bottomLeft:
            return CGPoint(x: margin, y: height - margin)
        case .bottomCenter:
            return CGPoint(x: width / 2, y: height - margin)
        case .bottomRight:
            return CGPoint(x: width - margin, y: height - margin)
        }
    }
}
