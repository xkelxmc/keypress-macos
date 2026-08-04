import AppKit
import SwiftUI

enum SceneTypography {
    /// Screenshots headline at 60 pt; the video caption uses a smaller line.
    static func headlineFont(size: CGFloat = 60) -> Font {
        Font.system(size: size, weight: .semibold, design: .serif)
    }

    /// Builds the display headline from markup where the single `*accented*` word
    /// switches to italic serif in the stage accent colour.
    static func headline(_ markup: String, accent: Color, size: CGFloat = 60) -> Text {
        let font = self.headlineFont(size: size)
        return markup
            .split(separator: "*", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, part in
                let run = Text(String(part)).font(font)
                return index.isMultiple(of: 2) ? run : run.italic().foregroundStyle(accent)
            }
            .reduce(Text(verbatim: ""), +)
    }
}

struct SceneKicker: View {
    let text: String

    var body: some View {
        Text(self.text.uppercased())
            .font(.system(size: 16, weight: .semibold, design: .monospaced))
            .tracking(3)
            .foregroundStyle(StagePalette.accent.opacity(0.9))
    }
}

/// The one-sentence benefit line under the headline.
struct SceneSubline: View {
    let text: String
    var tone: StageTone = .dark

    var body: some View {
        Text(self.text)
            .font(.system(size: 23, weight: .regular))
            .lineSpacing(5)
            .multilineTextAlignment(.center)
            .foregroundStyle(StagePalette.foreground(for: self.tone).opacity(0.68))
            .frame(maxWidth: 940)
    }
}

/// App icon + wordmark, shown above the hero kicker.
struct SceneBrandRow: View {
    var body: some View {
        HStack(spacing: 15) {
            if let icon = SceneBrandRow.iconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 10.5, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10.5, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.5), radius: 9, y: 5)
            }

            Text("Show KeyPress")
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(StagePalette.darkForeground.opacity(0.95))
        }
    }

    /// Generator runs from the repo root, same convention as the output directory.
    @MainActor private static let iconImage = NSImage(contentsOfFile: "assets/icon/icon-art-cat.png")
}

/// Mono label pill used for state chips and feature callouts.
struct SceneChip: View {
    let text: String
    var tone: StageTone = .dark
    var isAccented: Bool = false

    var body: some View {
        Text(self.text.uppercased())
            .font(.system(size: 15, weight: .medium, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(self.textColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background {
                Capsule()
                    .fill(self.isAccented ? StagePalette.accent.opacity(0.1) : StagePalette.surface(for: self.tone))
                    .overlay {
                        Capsule()
                            .strokeBorder(self.borderColor, lineWidth: 1)
                    }
            }
    }

    private var textColor: Color {
        self.isAccented
            ? StagePalette.accent.opacity(0.92)
            : StagePalette.foreground(for: self.tone).opacity(0.62)
    }

    private var borderColor: Color {
        self.isAccented
            ? StagePalette.accent.opacity(0.32)
            : StagePalette.surfaceBorder(for: self.tone)
    }
}

/// Small caption under tiles and plates.
struct SceneCaption: View {
    let text: String
    var opacity: Double = 0.5

    var body: some View {
        Text(self.text.uppercased())
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .tracking(2)
            .opacity(self.opacity)
    }
}

struct SceneTileBackground: View {
    var tone: StageTone = .dark
    var cornerRadius: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
            .fill(StagePalette.surface(for: self.tone))
            .overlay {
                RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                    .strokeBorder(StagePalette.surfaceBorder(for: self.tone), lineWidth: 1)
            }
    }
}
