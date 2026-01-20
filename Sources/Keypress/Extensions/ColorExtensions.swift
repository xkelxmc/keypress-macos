import SwiftUI

// MARK: - Color Brightness Extensions

extension Color {
    /// Returns a lighter version of the color by the given percentage (0.0-1.0).
    func lighter(by amount: Double) -> Color {
        self.adjusted(by: abs(amount))
    }

    /// Returns a darker version of the color by the given percentage (0.0-1.0).
    func darker(by amount: Double) -> Color {
        self.adjusted(by: -abs(amount))
    }

    private func adjusted(by amount: Double) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.deviceRGB) else {
            return self
        }

        rgbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let newBrightness = max(0, min(1, brightness + CGFloat(amount)))
        return Color(
            hue: Double(hue),
            saturation: Double(saturation),
            brightness: Double(newBrightness),
            opacity: Double(alpha))
    }
}
