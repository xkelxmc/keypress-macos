import AppKit
import KeypressCore
import SwiftUI

struct StackedHistoryVisualizationView: View {
    var keyState: StackedHistoryState
    let config: KeypressConfig
    @ObservedObject var layoutState: OverlayLayoutState

    private var keyboardTheme: KeyboardTheme {
        self.config.effectiveTheme(isSystemDark: self.systemIsDark).keyboard
    }

    var body: some View {
        self.content
    }

    @ViewBuilder
    private var content: some View {
        if self.keyState.entries.isEmpty {
            self.anchorKeys
        } else {
            switch self.layoutState.stackedHistoryLayout.verticalAnchor {
            case .top:
                VStack(alignment: self.horizontalAlignment, spacing: 8) {
                    self.anchorKeys
                    self.historyRows(Array(self.keyState.entries.reversed()))
                }
            case .bottom:
                VStack(alignment: self.horizontalAlignment, spacing: 8) {
                    self.historyRows(self.keyState.entries)
                    self.anchorKeys
                }
            case .center:
                switch self.layoutState.stackedHistoryLayout.horizontalAnchor {
                case .leading:
                    HStack(alignment: .center, spacing: 10) {
                        self.anchorKeys
                        self.historyRows(self.keyState.entries)
                    }
                case .trailing:
                    HStack(alignment: .center, spacing: 10) {
                        self.historyRows(self.keyState.entries)
                        self.anchorKeys
                    }
                case .center:
                    self.centeredHistory
                }
            }
        }
    }

    private var anchorKeys: some View {
        KeyVisualizationContent(
            pressedKeys: self.keyState.pressedKeys,
            physicallyPressedKeys: self.keyState.physicallyPressedKeys,
            hasKeys: self.keyState.hasAnchorKeys,
            config: self.config)
    }

    private func historyRows(_ entries: [StackedHistoryEntry]) -> some View {
        VStack(alignment: self.horizontalAlignment, spacing: 8) {
            ForEach(entries) { entry in
                self.historyRow(entry)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func historyRow(_ entry: StackedHistoryEntry) -> some View {
        switch entry.kind {
        case .text:
            StackedHistoryTextRow(
                text: entry.text,
                theme: self.keyboardTheme)
        case .shortcut:
            KeyVisualizationContent(
                pressedKeys: entry.keys,
                physicallyPressedKeys: [],
                hasKeys: true,
                config: self.config)
        }
    }

    private var centeredHistory: some View {
        let newestFirst = Array(self.keyState.entries.reversed())
        let above = newestFirst.enumerated().compactMap { index, entry in
            index.isMultiple(of: 2) ? entry : nil
        }
        let below = newestFirst.enumerated().compactMap { index, entry in
            index.isMultiple(of: 2) ? nil : entry
        }
        let orderedAbove = Array(above.reversed())

        return VStack(alignment: self.horizontalAlignment, spacing: 8) {
            ZStack(alignment: Alignment(horizontal: self.horizontalAlignment, vertical: .bottom)) {
                self.historyRows(orderedAbove)
                self.historyRows(below)
                    .hidden()
            }
            self.anchorKeys
            ZStack(alignment: Alignment(horizontal: self.horizontalAlignment, vertical: .top)) {
                self.historyRows(below)
                self.historyRows(orderedAbove)
                    .hidden()
            }
        }
    }

    private var horizontalAlignment: HorizontalAlignment {
        switch self.layoutState.stackedHistoryLayout.horizontalAnchor {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    private var systemIsDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

struct StackedHistoryTextRow: View {
    let text: String
    let theme: KeyboardTheme

    var body: some View {
        Text(self.text)
            .font(self.textFont)
            .foregroundStyle(self.theme.textColor.color)
            .lineLimit(1)
            .frame(minWidth: 48, minHeight: Self.height(for: self.theme), alignment: .leading)
            .padding(.horizontal, 16)
            .background {
                HistoryTextSurface(theme: self.theme)
            }
    }

    static func height(for theme: KeyboardTheme) -> CGFloat {
        switch theme.material {
        case .minimal: 34
        case .monochrome: 42
        case .classic: 52
        case .graphite, .aluminum, .glass, .gaming, .neon: 48
        }
    }

    private var textFont: Font {
        let size = 22 * self.theme.fontScale
        return ThemeFont.font(
            family: self.theme.fontFamily,
            size: size,
            weight: self.theme.fontWeight)
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
