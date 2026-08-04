import AppKit
import SwiftUI

/// Geometry shared by every App Store frame: 1440x900 pt rendered at 2x.
enum ScreenshotCanvas {
    static let size = CGSize(width: 1440, height: 900)
    static let renderScale: CGFloat = 2
    static let margin: CGFloat = 96

    /// Below the centered header block (kicker, headline, subline).
    static let contentRect = CGRect(x: 96, y: 310, width: 1248, height: 520)

    /// Hero fits the brand row above the kicker, so its content starts lower.
    static let heroContentRect = CGRect(x: 96, y: 366, width: 1248, height: 464)

    /// Taller box for the studio window frame.
    static let tallContentRect = CGRect(x: 96, y: 296, width: 1248, height: 540)
}

/// Exact layout size of a SwiftUI subtree, resolved synchronously so `ImageRenderer`
/// scenes can reserve space for `scaleEffect`-scaled content.
@MainActor
enum ViewMeasure {
    static func fittingSize(of view: some View) -> CGSize {
        let controller = NSHostingController(rootView: view)
        return controller.sizeThatFits(in: CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude))
    }
}

/// Scales a subtree and reserves its scaled footprint, which `scaleEffect` alone never does.
struct ScaledView<Content: View>: View {
    let scale: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        let natural = ViewMeasure.fittingSize(of: self.content())
        return self.content()
            .scaleEffect(self.scale)
            .frame(width: natural.width * self.scale, height: natural.height * self.scale)
    }
}
