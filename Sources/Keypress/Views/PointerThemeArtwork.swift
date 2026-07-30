import KeypressCore
import SwiftUI

enum PointerArtworkReaction: Equatable {
    case idle
    case movement
    case primary
    case secondary
    case middle
    case drag
    case scroll
}

struct PointerThemeArtwork: View {
    let theme: PointerTheme
    let size: CGFloat
    var primaryColor: Color?
    var reaction: PointerArtworkReaction

    init(
        theme: PointerTheme,
        size: CGFloat,
        primaryColor: Color? = nil,
        reaction: PointerArtworkReaction = .idle)
    {
        self.theme = theme
        self.size = size
        self.primaryColor = primaryColor
        self.reaction = reaction
    }

    private var primary: Color {
        if let primaryColor {
            return primaryColor
        }
        return self.reaction == .secondary
            ? self.theme.secondaryColor.color
            : self.theme.primaryColor.color
    }

    var body: some View {
        ZStack {
            self.lineArtwork
            self.decoration

            if self.reaction == .secondary {
                self.shape(
                    color: self.theme.secondaryColor.color.opacity(0.72),
                    lineWidth: max(1.5, CGFloat(self.theme.strokeWidth) * 0.42),
                    scale: 1.16)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            if self.reaction == .middle {
                Circle()
                    .fill(self.theme.coreColor.color)
                    .frame(width: 8, height: 8)
                    .shadow(color: self.theme.coreColor.color, radius: 9)
                    .transition(.opacity.combined(with: .scale(scale: 0.4)))
            }

            if self.theme.reactionStyle == .electric,
               self.reaction != .idle
            {
                self.shape(
                    color: self.theme.secondaryColor.color.opacity(0.55),
                    lineWidth: max(1, CGFloat(self.theme.strokeWidth) * 0.5),
                    scale: 1.08 * self.accentScale)
                    .blur(radius: 2)

                PointerHaloElectricArc(
                    color: self.theme.coreColor.color,
                    lineWidth: max(1, CGFloat(self.theme.strokeWidth) * 0.34))
                    .frame(
                        width: self.size * 0.88,
                        height: self.size * 0.88)
                    .transition(.opacity.combined(with: .scale(scale: 0.82)))
            }
        }
        .frame(width: self.size, height: self.size)
    }

    @ViewBuilder
    private var lineArtwork: some View {
        let stroke = CGFloat(self.theme.strokeWidth)
        let glow = CGFloat(self.theme.glowRadius)

        switch self.theme.lineStyle {
        case .aura:
            let bandWidth = min(self.size * 0.14, stroke * 2.5)
            let rimWidth = max(1, stroke * 0.55)

            self.shape(
                color: self.primary.opacity(0.18 * self.theme.glowIntensity),
                lineWidth: stroke * 3.2)
                .blur(radius: max(4, glow * 0.55))

            self.shapeBorder(
                color: self.primary.opacity(0.24),
                lineWidth: bandWidth)

            self.shape(
                color: self.primary,
                lineWidth: rimWidth)
                .shadow(
                    color: self.primary.opacity(self.theme.glowIntensity),
                    radius: glow)

        case .solid:
            let bandWidth = min(self.size * 0.18, stroke * 3.5)
            let rimWidth = max(1, stroke * 0.65)

            self.shape(
                color: self.primary.opacity(0.24 * self.theme.glowIntensity),
                lineWidth: bandWidth)
                .blur(radius: max(4, glow * 0.55))

            self.shapeBorder(
                color: self.primary.opacity(0.42),
                lineWidth: bandWidth)

            self.shape(
                color: self.primary,
                lineWidth: rimWidth)
                .shadow(
                    color: self.primary.opacity(self.theme.glowIntensity),
                    radius: glow)

        case .double:
            self.shape(
                color: self.primary.opacity(0.2 * self.theme.glowIntensity),
                lineWidth: stroke * 2.2)
                .blur(radius: max(1, glow * 0.35))

            self.shape(
                color: self.primary,
                lineWidth: stroke)

            self.shape(
                color: self.theme.secondaryColor.color.opacity(0.86),
                lineWidth: max(1, stroke * 0.55),
                scale: 0.82 * self.accentScale)

        case .segmented:
            self.shape(
                color: self.primary.opacity(0.22 * self.theme.glowIntensity),
                lineWidth: stroke * 2)
                .blur(radius: max(1, glow * 0.35))

            self.shape(
                color: self.primary,
                lineWidth: stroke,
                dash: [
                    stroke * 3,
                    stroke * 2.2,
                ],
                dashPhase: self.reaction == .idle
                    ? 0
                    : stroke * 1.35)

            self.shape(
                color: self.theme.secondaryColor.color.opacity(0.82),
                lineWidth: max(1, stroke * 0.45),
                scale: 0.84 * self.accentScale,
                dash: [
                    stroke * 1.5,
                    stroke * 2.6,
                ],
                dashPhase: stroke * 1.2)

        case .neonDepth:
            self.shape(
                color: self.theme.secondaryColor.color.opacity(0.72),
                lineWidth: stroke * 1.45,
                scale: 0.98 * max(0.9, self.accentScale))
                .offset(y: 4)
                .blur(radius: 2.2)

            self.shape(
                color: self.primary.opacity(0.24 * self.theme.glowIntensity),
                lineWidth: stroke * 3.6)
                .blur(radius: max(5, glow * 0.58))

            self.shape(
                color: self.primary,
                lineWidth: stroke)
                .shadow(
                    color: self.primary.opacity(self.theme.glowIntensity),
                    radius: glow)

            self.shape(
                color: self.theme.secondaryColor.color,
                lineWidth: max(1.2, stroke * 0.62),
                scale: 0.82 * self.accentScale)
                .shadow(
                    color: self.theme.secondaryColor.color.opacity(0.9),
                    radius: glow * 0.5)

            self.shape(
                color: self.theme.coreColor.color.opacity(0.72),
                lineWidth: max(0.75, stroke * 0.22),
                scale: 0.91 * max(0.84, self.accentScale))
        }
    }

    private var decoration: some View {
        Group {
            switch self.theme.decoration {
            case .none:
                EmptyView()

            case .centerDot:
                Circle()
                    .fill(self.theme.coreColor.color)
                    .frame(
                        width: max(5, CGFloat(self.theme.strokeWidth) * 1.7),
                        height: max(5, CGFloat(self.theme.strokeWidth) * 1.7))
                    .shadow(
                        color: self.theme.primaryColor.color.opacity(0.45),
                        radius: 4)

            case .innerRing:
                self.shape(
                    color: self.theme.coreColor.color.opacity(0.7),
                    lineWidth: max(1, CGFloat(self.theme.strokeWidth) * 0.36),
                    scale: 0.58)

            case .crosshair:
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(self.theme.coreColor.color.opacity(0.88))
                        .frame(
                            width: max(1.5, CGFloat(self.theme.strokeWidth) * 0.7),
                            height: self.size * 0.12)
                        .offset(y: -self.size * 0.43)
                        .rotationEffect(.degrees(Double(index) * 90))
                }

            case .cornerBrackets:
                PointerHaloCornerBrackets(
                    color: self.theme.secondaryColor.color,
                    lineWidth: max(1.5, CGFloat(self.theme.strokeWidth) * 0.62))

            case .orbit:
                ZStack {
                    Circle()
                        .fill(self.theme.coreColor.color)
                        .frame(width: 5, height: 5)
                        .offset(y: -self.size * 0.46)
                    Circle()
                        .fill(self.theme.secondaryColor.color)
                        .frame(width: 5, height: 5)
                        .offset(y: self.size * 0.46)
                }
            }
        }
        .scaleEffect(self.decorationScale)
        .rotationEffect(.degrees(self.decorationRotation))
    }

    private var accentScale: CGFloat {
        switch self.reaction {
        case .idle, .movement:
            1
        case .primary:
            0.76
        case .secondary:
            1.08
        case .middle:
            0.66
        case .drag:
            0.82
        case .scroll:
            0.9
        }
    }

    private var decorationScale: CGFloat {
        switch self.reaction {
        case .idle:
            1
        case .movement:
            self.theme.reactionStyle == .fluid ? 1.04 : 1
        case .primary:
            0.72
        case .secondary:
            1.12
        case .middle:
            0.58
        case .drag:
            0.78
        case .scroll:
            0.9
        }
    }

    private var decorationRotation: Double {
        guard self.theme.decoration == .orbit else { return 0 }
        return switch self.reaction {
        case .idle:
            24
        case .movement:
            54
        case .primary:
            88
        case .secondary:
            -42
        case .middle:
            120
        case .drag:
            74
        case .scroll:
            -78
        }
    }

    @ViewBuilder
    private func shape(
        color: Color,
        lineWidth: CGFloat,
        scale: CGFloat = 1,
        dash: [CGFloat] = [],
        dashPhase: CGFloat = 0) -> some View
    {
        let strokeStyle = StrokeStyle(
            lineWidth: lineWidth,
            lineCap: dash.isEmpty ? .butt : .round,
            lineJoin: .round,
            dash: dash,
            dashPhase: dashPhase)

        switch self.theme.shape {
        case .circle:
            Circle()
                .stroke(color, style: strokeStyle)
                .scaleEffect(scale)
        case .squircle:
            RoundedRectangle(cornerRadius: self.size * 0.28, style: .continuous)
                .stroke(color, style: strokeStyle)
                .scaleEffect(scale)
        case .square:
            RoundedRectangle(cornerRadius: self.size * 0.11, style: .continuous)
                .stroke(color, style: strokeStyle)
                .scaleEffect(scale)
        case .diamond:
            RoundedRectangle(cornerRadius: self.size * 0.09, style: .continuous)
                .stroke(color, style: strokeStyle)
                .scaleEffect(0.72 * scale)
                .rotationEffect(.degrees(45))
        }
    }

    @ViewBuilder
    private func shapeBorder(
        color: Color,
        lineWidth: CGFloat) -> some View
    {
        let strokeStyle = StrokeStyle(
            lineWidth: lineWidth,
            lineJoin: .round)

        switch self.theme.shape {
        case .circle:
            Circle()
                .strokeBorder(color, style: strokeStyle)
        case .squircle:
            RoundedRectangle(cornerRadius: self.size * 0.28, style: .continuous)
                .strokeBorder(color, style: strokeStyle)
        case .square:
            RoundedRectangle(cornerRadius: self.size * 0.11, style: .continuous)
                .strokeBorder(color, style: strokeStyle)
        case .diamond:
            RoundedRectangle(cornerRadius: self.size * 0.09, style: .continuous)
                .strokeBorder(color, style: strokeStyle)
                .scaleEffect(0.72)
                .rotationEffect(.degrees(45))
        }
    }
}

private struct PointerHaloCornerBrackets: View {
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let inset = side * 0.08
            let length = side * 0.19
            let maxX = geometry.size.width - inset
            let maxY = geometry.size.height - inset

            Path { path in
                path.move(to: CGPoint(x: inset + length, y: inset))
                path.addLine(to: CGPoint(x: inset, y: inset))
                path.addLine(to: CGPoint(x: inset, y: inset + length))

                path.move(to: CGPoint(x: maxX - length, y: inset))
                path.addLine(to: CGPoint(x: maxX, y: inset))
                path.addLine(to: CGPoint(x: maxX, y: inset + length))

                path.move(to: CGPoint(x: inset, y: maxY - length))
                path.addLine(to: CGPoint(x: inset, y: maxY))
                path.addLine(to: CGPoint(x: inset + length, y: maxY))

                path.move(to: CGPoint(x: maxX, y: maxY - length))
                path.addLine(to: CGPoint(x: maxX, y: maxY))
                path.addLine(to: CGPoint(x: maxX - length, y: maxY))
            }
            .stroke(
                self.color,
                style: StrokeStyle(
                    lineWidth: self.lineWidth,
                    lineCap: .round,
                    lineJoin: .round))
        }
    }
}

private struct PointerHaloElectricArc: View {
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            Path { path in
                path.move(to: CGPoint(x: width * 0.12, y: height * 0.28))
                path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.20))
                path.addLine(to: CGPoint(x: width * 0.31, y: height * 0.28))
                path.addLine(to: CGPoint(x: width * 0.42, y: height * 0.15))

                path.move(to: CGPoint(x: width * 0.70, y: height * 0.80))
                path.addLine(to: CGPoint(x: width * 0.77, y: height * 0.70))
                path.addLine(to: CGPoint(x: width * 0.84, y: height * 0.77))
                path.addLine(to: CGPoint(x: width * 0.91, y: height * 0.64))
            }
            .stroke(
                self.color,
                style: StrokeStyle(
                    lineWidth: self.lineWidth,
                    lineCap: .round,
                    lineJoin: .round))
            .shadow(color: self.color, radius: 4)
        }
    }
}
