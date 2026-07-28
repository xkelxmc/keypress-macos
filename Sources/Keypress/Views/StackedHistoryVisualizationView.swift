import AppKit
import KeypressCore
import SwiftUI

struct StackedHistoryVisualizationView: View {
    var keyState: StackedHistoryState
    let config: KeypressConfig
    var appliesSizeScale = true

    private var keyboardTheme: KeyboardTheme {
        self.config.effectiveTheme(isSystemDark: self.systemIsDark).keyboard
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(self.keyState.entries) { entry in
                StackedHistoryRow(
                    entry: entry,
                    physicallyPressedKeys: self.keyState.physicallyPressedKeys,
                    config: self.config,
                    keyboardTheme: self.keyboardTheme)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .scaleEffect(self.appliesSizeScale ? self.config.size.scaleFactor : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: self.keyState.entries)
    }

    private var systemIsDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

private struct StackedHistoryRow: View {
    let entry: StackedHistoryEntry
    let physicallyPressedKeys: Set<String>
    let config: KeypressConfig
    let keyboardTheme: KeyboardTheme

    var body: some View {
        switch self.entry.content {
        case let .text(keys):
            Text(self.displayText(keys))
                .font(self.textFont)
                .foregroundStyle(self.keyboardTheme.textColor.color)
                .lineLimit(1)
                .frame(minWidth: 48, minHeight: self.textRowHeight, alignment: .leading)
                .padding(.horizontal, 16)
                .background {
                    HistoryTextSurface(theme: self.keyboardTheme)
                }
        case let .chord(keys):
            self.chord(keys)
        }
    }

    @ViewBuilder
    private func chord(_ keys: [PressedKey]) -> some View {
        let keycaps = HStack(spacing: CGFloat(self.keyboardTheme.keySpacing)) {
            ForEach(keys) { key in
                KeyCapView(
                    symbol: key.symbol,
                    config: self.config,
                    isPressed: self.isPressed(key))
            }
        }

        KeyboardThemeContainer(config: self.config) {
            keycaps
        }
    }

    private func isPressed(_ key: PressedKey) -> Bool {
        let isPhysicallyPressed = self.physicallyPressedKeys.contains(key.symbol.id)
        if key.symbol.isModifier {
            return isPhysicallyPressed && self.config.keyboard.pressAnimationModifiers
        }
        return isPhysicallyPressed && self.config.keyboard.pressAnimationRegularKeys
    }

    private var textRowHeight: CGFloat {
        switch self.keyboardTheme.material {
        case .minimal: 34
        case .monochrome: 42
        case .classic: 52
        case .graphite, .aluminum, .glass, .gaming, .neon: 48
        }
    }

    private var textFont: Font {
        let size = 22 * self.keyboardTheme.fontScale
        return ThemeFont.font(
            family: self.keyboardTheme.fontFamily,
            size: size,
            weight: self.keyboardTheme.fontWeight)
    }

    private func displayText(_ keys: [PressedKey]) -> String {
        keys.map { key in
            key.symbol.id == "space" ? " " : key.symbol.display
        }.joined()
    }
}

private struct HistoryTextSurface: View {
    let theme: KeyboardTheme

    var body: some View {
        ZStack {
            if self.theme.material == .neon {
                RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                    .fill(self.neonSecondaryColor.darker(by: 0.36))
                    .overlay {
                        RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                            .strokeBorder(self.neonSecondaryColor.opacity(0.82), lineWidth: 1)
                    }
                    .offset(y: 4)
                    .shadow(color: self.neonSecondaryColor.opacity(0.48), radius: 8, y: 3)
            }

            RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                .fill(self.fill)
                .overlay {
                    RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                        .strokeBorder(self.borderGradient, lineWidth: self.borderWidth)
                }
                .overlay {
                    if self.theme.material == .neon {
                        RoundedRectangle(
                            cornerRadius: max(3, self.cornerRadius - 4),
                            style: .continuous)
                            .strokeBorder(self.neonSecondaryColor.opacity(0.78), lineWidth: 0.9)
                            .padding(5)
                    }
                }
                .shadow(color: self.shadowColor, radius: self.shadowRadius, y: self.shadowOffset)
        }
    }

    private var cornerRadius: CGFloat {
        switch self.theme.material {
        case .gaming: 5
        case .classic: 10
        case .minimal: 17
        case .graphite, .aluminum, .monochrome, .glass, .neon: 13
        }
    }

    private var fill: LinearGradient {
        let letter = self.theme.colorScheme.color(for: .letter).color
        let colors: [Color] = switch self.theme.material {
        case .classic:
            [letter.lighter(by: 0.12), letter.darker(by: 0.12)]
        case .glass:
            [letter.lighter(by: 0.1).opacity(0.9), letter.opacity(0.72)]
        case .gaming:
            [letter.lighter(by: 0.08), letter.darker(by: 0.22)]
        case .neon:
            [letter.lighter(by: 0.04), letter.darker(by: 0.1)]
        case .graphite, .aluminum, .monochrome, .minimal:
            [letter, letter]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var borderGradient: LinearGradient {
        let colors: [Color] = switch self.theme.material {
        case .neon:
            [
                self.theme.borderColor.color,
                self.neonSecondaryColor,
                self.theme.borderColor.color,
            ]
        case .gaming:
            [
                KeyColor(red: 0.48, green: 1, blue: 0.18).color.opacity(0.62),
                KeyColor.pointerCyan.color.opacity(0.35),
            ]
        case .classic:
            [Color.white.opacity(0.18), Color.black.opacity(0.2)]
        case .graphite, .aluminum, .monochrome, .glass, .minimal:
            [self.theme.borderColor.color, self.theme.borderColor.color]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var borderWidth: CGFloat {
        switch self.theme.material {
        case .gaming: 1.5
        case .neon: max(1.5, CGFloat(self.theme.borderWidth))
        case .classic: 1
        case .graphite, .aluminum, .monochrome, .glass, .minimal:
            CGFloat(self.theme.borderWidth)
        }
    }

    private var shadowColor: Color {
        switch self.theme.material {
        case .gaming:
            KeyColor(red: 0.48, green: 1, blue: 0.18).color.opacity(0.25)
        case .neon:
            self.theme.borderColor.color.opacity(0.58)
        case .graphite, .aluminum, .monochrome, .classic, .glass, .minimal:
            Color.black.opacity(0.28)
        }
    }

    private var shadowRadius: CGFloat {
        switch self.theme.material {
        case .neon: 14
        case .gaming: 9
        case .minimal, .monochrome: 4
        case .graphite, .aluminum, .classic, .glass: 10
        }
    }

    private var shadowOffset: CGFloat {
        switch self.theme.material {
        case .minimal, .monochrome: 2
        case .graphite, .aluminum, .classic, .glass, .gaming, .neon: 5
        }
    }

    private var neonSecondaryColor: Color {
        self.theme.colorScheme.shift.color.lighter(by: 0.28)
    }
}
