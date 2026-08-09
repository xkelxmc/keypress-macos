import Foundation
import SwiftUI

// MARK: - OverlayPosition

/// Position of the key visualization overlay on screen.
/// 8 preset positions: 4 corners + 4 edge centers.
public enum OverlayPosition: String, CaseIterable, Codable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case centerLeft
    case centerRight
    case bottomLeft
    case bottomCenter
    case bottomRight
}

// MARK: - OverlaySize

/// Size presets for the key visualization.
public enum OverlaySize: String, CaseIterable, Codable, Sendable {
    case small
    case medium
    case large

    /// Scale factor relative to base size.
    public var scaleFactor: CGFloat {
        switch self {
        case .small: 0.75
        case .medium: 1.0
        case .large: 1.25
        }
    }
}

// MARK: - DisplayMode

/// Display mode for key visualization.
public enum DisplayMode: String, CaseIterable, Codable, Sendable {
    /// Only latest keystroke/combination visible. Each new key replaces previous.
    /// Best for shortcut demos, teaching.
    case single

    /// Queue of recent keystrokes. Keys accumulate and fade over time.
    /// Best for typing demos, streaming.
    case history
}

// MARK: - KeyCategory

/// Category of a key for color assignment.
public enum KeyCategory: String, CaseIterable, Codable, Sendable {
    case letter // A-Z, 0-9
    case command // ⌘
    case shift // ⇧
    case option // ⌥
    case control // ⌃
    case capsLock // ⇪
    case escape // ⎋
    case function // F1-F20
    case navigation // Arrows, Page Up/Down, Home, End
    case editing // Space, Tab, Return, Delete, Backspace
}

// MARK: - MonitorSelection

/// Selection for which monitor to display the overlay on.
public enum MonitorSelection: Codable, Sendable, Equatable, Hashable {
    /// Automatically follow active window (overlay appears on monitor where user is typing).
    case auto
    /// Fixed to a specific monitor by index (0-based into NSScreen.screens).
    case fixed(index: Int)
}

// MARK: - KeyboardFrameStyle

/// Style for the container around keys.
public enum KeyboardFrameStyle: String, CaseIterable, Codable, Sendable {
    /// 3D keyboard frame with depth and materials.
    case frame

    /// Simple semi-transparent overlay background.
    case overlay

    /// No background, keys float freely.
    case none
}

// MARK: - KeyCapStyle

/// Visual style for keycap rendering.
public enum KeyCapStyle: String, CaseIterable, Codable, Sendable {
    /// 3D mechanical keyboard style with depth and shadows.
    case mechanical

    /// Flat modern style with subtle shadows.
    case flat

    /// Minimal style with just text and background.
    case minimal
}

// MARK: - AppearanceMode

/// Appearance mode for color scheme selection.
public enum AppearanceMode: String, CaseIterable, Codable, Sendable {
    /// Follow system light/dark mode automatically.
    case auto

    /// Fixed dark scheme with colored modifiers.
    case dark

    /// Fixed monochrome dark scheme.
    case monochrome

    /// Fixed light scheme with colored modifiers.
    case light

    /// Custom user-defined colors for each category.
    case custom

    /// Display name for UI.
    public var displayName: String {
        switch self {
        case .auto: "Auto"
        case .dark: "Dark"
        case .monochrome: "Mono"
        case .light: "Light"
        case .custom: "Custom"
        }
    }
}

// MARK: - KeyColor

/// A color that can be stored in UserDefaults.
public struct KeyColor: Codable, Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(_ color: Color) {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor.gray
        self.red = Double(nsColor.redComponent)
        self.green = Double(nsColor.greenComponent)
        self.blue = Double(nsColor.blueComponent)
        self.alpha = Double(nsColor.alphaComponent)
    }

    public var color: Color {
        Color(red: self.red, green: self.green, blue: self.blue, opacity: self.alpha)
    }

    // MARK: - Preset Colors

    /// Dark charcoal for regular keys.
    public static let charcoal = KeyColor(red: 0.15, green: 0.15, blue: 0.17)

    /// Light aluminum for regular keys (light mode).
    public static let aluminum = KeyColor(red: 0.88, green: 0.88, blue: 0.90)

    /// Green for Command key.
    public static let commandGreen = KeyColor(red: 0.20, green: 0.70, blue: 0.45)

    /// Red/coral for Shift key.
    public static let shiftRed = KeyColor(red: 0.90, green: 0.30, blue: 0.25)

    /// Blue for Option key.
    public static let optionBlue = KeyColor(red: 0.25, green: 0.45, blue: 0.95)

    /// Orange for Control key.
    public static let controlOrange = KeyColor(red: 0.95, green: 0.55, blue: 0.20)

    /// Teal for Escape key.
    public static let escapeTeal = KeyColor(red: 0.20, green: 0.75, blue: 0.70)

    /// Purple for Function keys.
    public static let functionPurple = KeyColor(red: 0.60, green: 0.40, blue: 0.80)

    /// Gray for Caps Lock.
    public static let capsLockGray = KeyColor(red: 0.35, green: 0.35, blue: 0.38)
}

// MARK: - KeyCategoryStyle

/// Complete style configuration for a key category.
public struct KeyCategoryStyle: Codable, Sendable, Equatable {
    /// Base color for the keycap.
    public var color: KeyColor

    /// 3D depth effect intensity (0.0 = flat, 1.0 = full 3D).
    public var depth: Double

    /// Corner radius multiplier (0.0 = sharp, 1.0 = maximum rounded).
    public var cornerRadius: Double

    /// Shadow intensity (0.0 = no shadow, 1.0 = full shadow).
    public var shadowIntensity: Double

    /// Visual style for the keycap.
    public var style: KeyCapStyle

    public init(
        color: KeyColor,
        depth: Double = 1.0,
        cornerRadius: Double = 0.5,
        shadowIntensity: Double = 1.0,
        style: KeyCapStyle = .mechanical)
    {
        self.color = color
        self.depth = depth.clamped(to: 0.0...1.0)
        self.cornerRadius = cornerRadius.clamped(to: 0.0...1.0)
        self.shadowIntensity = shadowIntensity.clamped(to: 0.0...1.0)
        self.style = style
    }

    /// Creates a default style for a category based on a color scheme.
    public static func `default`(for category: KeyCategory, scheme: KeyColorScheme) -> KeyCategoryStyle {
        KeyCategoryStyle(
            color: scheme.color(for: category),
            depth: 1.0,
            cornerRadius: 0.5,
            shadowIntensity: 1.0,
            style: .mechanical)
    }
}

// MARK: - Double Extension

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - KeyColorScheme

/// Complete color scheme for all key categories.
public struct KeyColorScheme: Codable, Sendable, Equatable {
    public var letter: KeyColor
    public var command: KeyColor
    public var shift: KeyColor
    public var option: KeyColor
    public var control: KeyColor
    public var capsLock: KeyColor
    public var escape: KeyColor
    public var function: KeyColor
    public var navigation: KeyColor
    public var editing: KeyColor

    public init(
        letter: KeyColor = .charcoal,
        command: KeyColor = .commandGreen,
        shift: KeyColor = .shiftRed,
        option: KeyColor = .optionBlue,
        control: KeyColor = .controlOrange,
        capsLock: KeyColor = .capsLockGray,
        escape: KeyColor = .escapeTeal,
        function: KeyColor = .functionPurple,
        navigation: KeyColor = .charcoal,
        editing: KeyColor = .charcoal)
    {
        self.letter = letter
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
        self.capsLock = capsLock
        self.escape = escape
        self.function = function
        self.navigation = navigation
        self.editing = editing
    }

    /// Returns the color for a given category.
    public func color(for category: KeyCategory) -> KeyColor {
        switch category {
        case .letter: self.letter
        case .command: self.command
        case .shift: self.shift
        case .option: self.option
        case .control: self.control
        case .capsLock: self.capsLock
        case .escape: self.escape
        case .function: self.function
        case .navigation: self.navigation
        case .editing: self.editing
        }
    }

    // MARK: - Presets

    /// Default dark scheme with colored modifiers.
    public static let dark = KeyColorScheme()

    /// Monochrome dark scheme.
    public static let monochromeDark = KeyColorScheme(
        letter: .charcoal,
        command: .charcoal,
        shift: .charcoal,
        option: .charcoal,
        control: .charcoal,
        capsLock: .charcoal,
        escape: .charcoal,
        function: .charcoal,
        navigation: .charcoal,
        editing: .charcoal)

    /// Light scheme with colored modifiers.
    public static let light = KeyColorScheme(
        letter: .aluminum,
        command: .commandGreen,
        shift: .shiftRed,
        option: .optionBlue,
        control: .controlOrange,
        capsLock: KeyColor(red: 0.75, green: 0.75, blue: 0.78),
        escape: .escapeTeal,
        function: .functionPurple,
        navigation: .aluminum,
        editing: .aluminum)
}
