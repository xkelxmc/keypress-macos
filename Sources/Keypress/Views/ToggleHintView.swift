import KeypressCore
import SwiftUI

/// Position of the hint relative to the keys overlay.
enum HintPosition {
    case leading
    case trailing
    case top
    case bottom

    /// Determines hint position based on overlay position.
    static func from(overlayPosition: OverlayPosition) -> HintPosition {
        switch overlayPosition {
        case .topLeft, .centerLeft, .bottomLeft:
            return .trailing
        case .topRight, .centerRight, .bottomRight:
            return .leading
        case .topCenter:
            return .bottom
        case .bottomCenter:
            return .top
        }
    }
}

/// Toggle hint view showing status indicator and "Keypress On/Off (shortcut)".
struct ToggleHintView: View {
    let hint: ToggleHint
    let config: KeypressConfig

    private var statusText: String {
        let status = self.hint.isEnabled ? "Keypress On" : "Keypress Off"
        return self.hint.shortcutText.isEmpty ? status : "\(status) (\(self.hint.shortcutText))"
    }

    var body: some View {
        HStack(spacing: 10) {
            IndicatorLight(isOn: self.hint.isEnabled)

            Text(self.statusText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.7))
                .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
        )
        .scaleEffect(self.config.size.scaleFactor)
    }
}

/// Skeuomorphic indicator light with 3D effect and glow.
struct IndicatorLight: View {
    let isOn: Bool

    private var baseColor: Color {
        self.isOn ? Color(red: 0.2, green: 0.8, blue: 0.3) : Color(red: 0.9, green: 0.2, blue: 0.2)
    }

    private var glowColor: Color {
        self.isOn ? Color.green : Color.red
    }

    private let size: CGFloat = 12

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(self.glowColor.opacity(0.5))
                .frame(width: self.size + 10, height: self.size + 10)
                .blur(radius: 6)

            // Metal bezel (ring around the light)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.5),
                            Color(white: 0.2),
                            Color(white: 0.4),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: self.size + 4, height: self.size + 4)

            // Inner shadow (inset effect)
            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: self.size + 2, height: self.size + 2)

            // Main light body with gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            self.baseColor,
                            self.baseColor.opacity(0.7),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: self.size / 2
                    )
                )
                .frame(width: self.size, height: self.size)

            // Glass highlight (top-left reflection)
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.8),
                            Color.white.opacity(0.0),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: self.size * 0.5, height: self.size * 0.3)
                .offset(x: -self.size * 0.12, y: -self.size * 0.18)
        }
        .frame(width: self.size + 12, height: self.size + 12)
    }
}

// MARK: - Preview

#Preview("Toggle Hint") {
    VStack(spacing: 20) {
        ToggleHintView(
            hint: ToggleHint(isEnabled: true, shortcutText: "⇧⌘K"),
            config: .shared
        )
        ToggleHintView(
            hint: ToggleHint(isEnabled: false, shortcutText: "⇧⌘K"),
            config: .shared
        )
    }
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
