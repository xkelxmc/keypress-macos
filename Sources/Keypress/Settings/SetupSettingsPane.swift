import KeypressCore
import SwiftUI

@MainActor
struct SetupSettingsPane: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig
    @Bindable var progress: OnboardingProgressStore

    var body: some View {
        StudioPage(
            titleKey: "onboarding.settings.title",
            subtitleKey: "onboarding.settings.subtitle")
        {
            StudioCard {
                HStack(spacing: 18) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.22), .cyan.opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing))
                        Image(systemName: "sparkles")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.purple)
                            .font(.system(size: 28, weight: .semibold))
                    }
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(self.strings["onboarding.settings.card.title"])
                            .font(.title3.weight(.semibold))
                        Text(self.strings["onboarding.settings.card.body"])
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)
                }
            }

            StudioCard(
                "onboarding.settings.status",
                systemImage: "checklist",
                tint: .cyan)
            {
                self.statusRow(
                    title: self.strings["onboarding.settings.progress"],
                    detail: String(
                        format: self.strings["onboarding.progress"],
                        self.progress.currentStep.rawValue + 1,
                        OnboardingStep.allCases.count),
                    image: "circle.grid.2x2.fill",
                    color: .purple)

                StudioDivider()

                self.statusRow(
                    title: self.strings["general.permission"],
                    detail: self.progress.permissionGranted
                        ? self.strings["general.permission.granted"]
                        : self.strings["general.permission.required"],
                    image: self.progress.permissionGranted
                        ? "checkmark.shield.fill"
                        : "lock.shield.fill",
                    color: self.progress.permissionGranted ? .green : .orange)
            }

            StudioCard(
                "onboarding.settings.privacy",
                systemImage: "hand.raised.fill",
                tint: .green)
            {
                Text(self.strings["onboarding.settings.privacy.body"])
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                OnboardingController.shared.continueFromSettings()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(self.strings["onboarding.settings.continue"])
                            .font(.headline)
                        Text(self.strings["onboarding.settings.continue.subtitle"])
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.16), in: Circle())
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .leading,
                        endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(StudioHoverButtonStyle())
        }
    }

    private func statusRow(
        title: String,
        detail: String,
        image: String,
        color: Color) -> some View
    {
        HStack(spacing: 12) {
            Image(systemName: image)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .font(.system(size: 18))
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
        }
    }
}
