import AppKit
import KeypressCore
import SwiftUI

/// Configurations for one scene, keyed by the theme each tile renders.
@MainActor
struct SceneConfigs {
    let fallback: KeypressConfig
    private let byTheme: [ThemeSelection: KeypressConfig]

    init(fallback: KeypressConfig, byTheme: [ThemeSelection: KeypressConfig]) {
        self.fallback = fallback
        self.byTheme = byTheme
    }

    subscript(selection: ThemeSelection) -> KeypressConfig {
        self.byTheme[selection] ?? self.fallback
    }
}

/// Bitmaps a scene needs that cannot be produced inside `ImageRenderer`.
@MainActor
struct SceneAssets {
    var settingsWindow: NSImage?
}

struct ScreenshotSceneView: View {
    let scene: ScreenshotScene
    let index: Int
    let total: Int
    let configs: SceneConfigs
    let assets: SceneAssets

    private var foregroundColor: Color {
        StagePalette.foreground(for: self.scene.stage)
    }

    var body: some View {
        ZStack(alignment: .top) {
            StageBackgroundView(tone: self.scene.stage)

            SceneContentView(
                scene: self.scene,
                configs: self.configs,
                assets: self.assets)
                .frame(
                    width: self.scene.contentRect.width,
                    height: self.scene.contentRect.height)
                .position(
                    x: self.scene.contentRect.midX,
                    y: self.scene.contentRect.midY)

            VStack(spacing: 0) {
                if self.scene.showsBrand {
                    SceneBrandRow()
                        .padding(.bottom, 22)
                }

                SceneKicker(text: self.scene.kicker)
                    .padding(.bottom, 14)

                SceneTypography.headline(self.scene.headline, accent: StagePalette.accent)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 14)

                SceneSubline(text: self.scene.subline, tone: self.scene.stage)
            }
            .foregroundStyle(self.foregroundColor)
            .padding(.top, 66)
            .frame(maxWidth: .infinity)

            Text(String(format: "%02d / %02d", self.index, self.total))
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(self.foregroundColor)
                .opacity(0.3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(44)
        }
        .frame(width: ScreenshotCanvas.size.width, height: ScreenshotCanvas.size.height)
        .clipped()
    }
}
