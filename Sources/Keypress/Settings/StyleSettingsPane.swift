import KeypressCore
import SwiftUI

// MARK: - StyleSettingsPane

@MainActor
struct StyleSettingsPane: View {
    @Bindable var config: KeypressConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Preview with wallpaper background
            KeyPreview(config: self.config)

            Divider()

            // Settings
            VStack(alignment: .leading, spacing: 16) {
                SettingsRow("Keycap Style", subtitle: self.config.keyCapStyle.description) {
                    Picker("", selection: self.$config.keyCapStyle) {
                        ForEach(KeyCapStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                Divider()

                SettingsRow("Background", subtitle: self.config.keyboardFrameStyle.description) {
                    Picker("", selection: self.$config.keyboardFrameStyle) {
                        ForEach(KeyboardFrameStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }

            Spacer()
        }
        .padding(.top, 12)
        .padding(.horizontal, 12)
    }
}
