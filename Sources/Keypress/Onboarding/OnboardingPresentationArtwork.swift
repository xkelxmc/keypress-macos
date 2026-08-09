import KeypressCore
import SwiftUI

/// The miniature each mode card carries.
///
/// Latest is one combination. The other two split input in two, and the card has to say so: the
/// mode's own zone on top — a row of the keys that produced text, or the text itself — and the
/// command zone under it. A modifier held down always routes to that lower zone, so it can never
/// appear in the row above.
@MainActor
struct OnboardingPresentationArtwork: View {
    let presentation: KeyboardPresentation
    let contentMode: KeyboardContentMode

    private static let ribbonLetters = ["h", "e", "l", "l", "o"]

    private let shift = OnboardingMiniKey(label: "⇧", width: 31)
    private let command = OnboardingMiniKey(label: "⌘", width: 31)

    var body: some View {
        switch self.presentation {
        case .latest:
            self.chord
        case .horizontalHistory:
            VStack(spacing: 4) {
                self.ribbon
                self.chord
            }
        case .stackedHistory:
            VStack(spacing: 4) {
                self.echoPlaque
                self.chord
            }
        }
    }

    private var ribbon: some View {
        HStack(spacing: 3) {
            ForEach(Array(Self.ribbonLetters.enumerated()), id: \.offset) { _, letter in
                OnboardingMiniKey(label: letter, width: 20)
            }
        }
    }

    /// Sentence case, because the echo shows the text that was typed rather than the keys that
    /// typed it — a plaque reading HELLO would be claiming Shift was held for every letter.
    private var echoPlaque: some View {
        Text(verbatim: "Hello")
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: 86, height: 19)
            .background(
                Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var chord: some View {
        HStack(spacing: 4) {
            self.shift
            self.command
            self.key
        }
    }

    private var key: OnboardingMiniKey {
        OnboardingMiniKey(
            label: self.shownContentMode == .allKeys ? "K" : "V",
            width: 23)
    }

    /// Read per card rather than from the settings: each card stands for its own mode, and only
    /// Latest's shows what the Content setting does.
    private var shownContentMode: KeyboardContentMode {
        self.presentation == .latest ? self.contentMode : self.contentMode.ignoringShortcutsOnly
    }
}

private struct OnboardingMiniKey: View {
    let label: String
    let width: CGFloat

    var body: some View {
        Text(self.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: self.width, height: 22)
            .background(
                Color.primary.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.13))
            }
    }
}

// MARK: - Previews

/// The chrome the settings pane and the onboarding step both wrap the artwork in, repeated here
/// so a preview shows the artwork at the size and on the surface it is really drawn on.
private struct PresentationCardPreview: View {
    let presentation: KeyboardPresentation
    let contentMode: KeyboardContentMode
    let selected: Bool

    var body: some View {
        VStack(spacing: 9) {
            OnboardingPresentationArtwork(
                presentation: self.presentation,
                contentMode: self.contentMode)
                .frame(height: 54)

            Text(verbatim: self.presentation.onboardingTitleKey)
                .font(.caption.weight(self.selected ? .bold : .medium))
                .foregroundStyle(self.selected ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .background(
            self.selected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    self.selected ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: self.selected ? 2 : 1)
        }
    }
}

// The three cards as the picker shows them, at the narrowest the settings pane ever gets them.
// Only Latest's artwork follows the Content setting, so the two rows differ in one card.
#Preview("Mode cards — all three") {
    VStack(spacing: 18) {
        ForEach([KeyboardContentMode.allKeys, .shortcutsOnly], id: \.self) { contentMode in
            HStack(spacing: 10) {
                ForEach(KeyboardPresentation.allCases, id: \.self) { presentation in
                    PresentationCardPreview(
                        presentation: presentation,
                        contentMode: contentMode,
                        selected: presentation == .horizontalHistory)
                }
            }
        }
    }
    .padding(24)
    .frame(width: 560)
}
