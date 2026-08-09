import AppKit
import KeypressCore
import SwiftUI

// MARK: - TypedTextPlaqueStyle

/// The metrics of one line's plaque.
///
/// A plaque is deliberately not the keyboard container: keycaps belong to keys, and a keyboard
/// frame drawn under a sentence reads as a keyboard that has swallowed a paragraph. Each line
/// carries its own neutral surface instead, and the lines stack with a gap between them.
enum TypedTextPlaqueStyle {
    /// Wide enough that a two-character line is still a plaque rather than a speck.
    static let minimumWidth: CGFloat = 48

    static let horizontalPadding: CGFloat = 16

    /// How tall a plaque is under a theme, at the reference type size.
    static func height(for theme: KeyboardTheme) -> CGFloat {
        switch theme.material {
        case .minimal: 34
        case .monochrome: 42
        case .classic: 52
        case .graphite, .aluminum, .glass, .gaming, .neon: 48
        }
    }
}

// MARK: - TypedTextPlaque

/// One line of typed text on a surface of its own.
///
/// The content is a caller's `Text` rather than a string, because the live echo draws one
/// styled run per line — its Enter and Tab marks are dimmed in place, inside the same line.
struct TypedTextPlaque<Content: View>: View {
    let theme: KeyboardTheme

    /// Overrides the theme's plaque height, for type larger than the reference size.
    var minimumHeight: CGFloat?

    @ViewBuilder let content: () -> Content

    var body: some View {
        self.content()
            .lineLimit(1)
            .frame(
                minWidth: TypedTextPlaqueStyle.minimumWidth,
                minHeight: self.minimumHeight ?? TypedTextPlaqueStyle.height(for: self.theme),
                alignment: .leading)
            .padding(.horizontal, TypedTextPlaqueStyle.horizontalPadding)
            .background {
                HistoryTextSurface(theme: self.theme)
            }
    }
}

// MARK: - TypedTextRow

/// A line of plain typed text on its plaque, at the reference type size.
///
/// What the marketing screenshots, the promo film and the settings preview use to stand in for
/// typed text without driving a real state machine.
struct TypedTextRow: View {
    let text: String
    let theme: KeyboardTheme

    var body: some View {
        TypedTextPlaque(theme: self.theme) {
            Text(self.text)
                .font(self.textFont)
                .foregroundStyle(self.theme.textColor.color)
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
