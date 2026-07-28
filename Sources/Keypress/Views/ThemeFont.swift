import AppKit
import KeypressCore
import SwiftUI

@MainActor
enum ThemeFont {
    static let rounded = "dev.keypress.font.rounded"
    static let monospaced = "dev.keypress.font.monospaced"
    static let availableFamilies = NSFontManager.shared.availableFontFamilies.sorted()

    private static let availableFamilySet = Set(availableFamilies)

    static func font(family: String?, size: CGFloat, weight: ThemeFontWeight) -> Font {
        switch family {
        case self.rounded:
            .system(size: size, weight: weight.swiftUIWeight, design: .rounded)
        case self.monospaced:
            .system(size: size, weight: weight.swiftUIWeight, design: .monospaced)
        case let family? where self.availableFamilySet.contains(family):
            .custom(family, size: size).weight(weight.swiftUIWeight)
        default:
            .system(size: size, weight: weight.swiftUIWeight)
        }
    }
}

extension ThemeFontWeight {
    var swiftUIWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}
