import AppKit
import KeypressCore
import SwiftUI

// MARK: - CommandZoneSnapshot

/// Everything the command zone draws in one comparable value.
private struct CommandZoneSnapshot: Equatable {
    var keys: [PressedKey] = []
    var repeatCount: Int = 0
    var repeatKeyID: String?
    var pressedIDs: Set<String> = []
}

// MARK: - CommandZoneView

/// The command zone: everything that produces no text — held modifiers, shortcuts, arrows,
/// Escape, Backspace — displayed as one combination, like Latest mode.
///
/// One view for both two-zone modes, driven by the one state they share, so there is nowhere
/// for the two of them to drift apart.
struct CommandZoneView: View {
    var state: CommandZoneState
    let config: KeypressConfig
    @Environment(\.blockPhase) private var blockPhase

    private var keyboardTheme: KeyboardTheme {
        self.config.effectiveTheme(isSystemDark: self.systemIsDark).keyboard
    }

    /// Everything the zone draws, gathered so the exit can keep drawing it after the state
    /// has moved on — including the badge, which would otherwise blink out a moment before
    /// the keycap it belongs to.
    private var snapshot: CommandZoneSnapshot {
        CommandZoneSnapshot(
            keys: self.state.keys,
            repeatCount: self.state.repeatCount,
            repeatKeyID: self.state.repeatKeyID,
            pressedIDs: self.state.pressedKeyIDs)
    }

    var body: some View {
        BlockPresentationView(value: self.snapshot, isPresent: self.state.hasKeys) { snapshot in
            KeyboardThemeContainer(config: self.config) {
                HStack(spacing: CGFloat(self.keyboardTheme.keySpacing)) {
                    // Keyed by symbol id, not entry id: `PressedKey.id` is timestamped for
                    // regular keys, so ⌘V ×N would recreate the keycap on every press.
                    ForEach(snapshot.keys, id: \.symbol.id) { key in
                        KeyCapView(
                            symbol: key.symbol,
                            config: self.config,
                            isPressed: self.isPressed(key, in: snapshot))
                            .overlay(alignment: .topTrailing) {
                                self.repeatBadge(for: key, in: snapshot)
                            }
                            // The badge belongs to the keycap, so they move as one rigid
                            // thing rather than as a keycap and a label chasing it.
                            .geometryGroup()
                    }
                }
            }
        }
    }

    /// The ×N badge hangs off the keycap corner as an overlay, so it can never shift a
    /// neighbour. The count comes from the same snapshot as the keys, so it keeps changing
    /// live while the zone is on screen and holds still with them while it leaves.
    @ViewBuilder
    private func repeatBadge(for key: PressedKey, in snapshot: CommandZoneSnapshot) -> some View {
        if snapshot.repeatCount > 1, key.id == snapshot.repeatKeyID {
            RepeatCountBadge(
                count: snapshot.repeatCount,
                theme: self.keyboardTheme,
                keyColor: self.config.effectiveStyle(
                    for: KeyCodeMapper.category(for: key.symbol)).color)
                .offset(x: 4, y: -4)
        }
    }

    private func isPressed(_ key: PressedKey, in snapshot: CommandZoneSnapshot) -> Bool {
        let isPhysicallyPressed = snapshot.pressedIDs.contains(key.id)

        if key.symbol.isModifier {
            return isPhysicallyPressed && self.config.pressAnimationModifiers
        } else {
            return isPhysicallyPressed && self.config.pressAnimationRegularKeys
        }
    }

    private var systemIsDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

// MARK: - RepeatCountBadge

/// Small ×N capsule for a command pressed several times in a row.
private struct RepeatCountBadge: View {
    let count: Int
    let theme: KeyboardTheme
    let keyColor: KeyColor

    /// The number only animates once the block is settled — while the block is arriving or
    /// leaving, the badge rides along with its keycap instead of running its own show.
    @Environment(\.blockPhase) private var blockPhase

    private var fill: Color {
        self.keyColor.color.darker(by: 0.16)
    }

    /// Brightness of the darkened fill, approximated from the source color so the label
    /// stays readable on light themes without round-tripping through NSColor.
    private var textColor: Color {
        let brightness = (self.keyColor.red + self.keyColor.green + self.keyColor.blue) / 3
        return brightness - 0.16 > 0.5 ? .black : .white
    }

    private var font: Font {
        .system(size: 9 * self.theme.fontScale, weight: .semibold, design: .rounded)
    }

    /// Only a settled block lets the count pop; otherwise the trigger never changes.
    private var popTrigger: Int {
        self.blockPhase == .shown ? self.count : 0
    }

    var body: some View {
        Text(verbatim: "×\(self.count)")
            .font(self.font)
            .monospacedDigit()
            .foregroundStyle(self.textColor)
            .contentTransition(self.blockPhase == .shown ? .numericText() : .identity)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background {
                Capsule(style: .continuous)
                    .fill(self.fill)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(self.theme.borderColor.color, lineWidth: 0.75)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            }
            .fixedSize()
            .keyframeAnimator(initialValue: 1.0, trigger: self.popTrigger) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(
                    1.2,
                    duration: KeypressTiming.badgePopRise,
                    spring: KeypressTiming.badgePopSpring)
                SpringKeyframe(
                    1.0,
                    duration: KeypressTiming.badgePopSettle,
                    spring: KeypressTiming.badgePopSpring)
            }
    }
}
