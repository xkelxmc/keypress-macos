@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

public enum PointerButton: Sendable, Equatable, Hashable {
    case left
    case right
    case middle
    case other(Int64)

    public init(buttonNumber: Int64) {
        switch buttonNumber {
        case 0: self = .left
        case 1: self = .right
        case 2: self = .middle
        default: self = .other(buttonNumber)
        }
    }
}

public enum PointerEventKind: Sendable, Equatable {
    case moved
    case buttonDown(button: PointerButton, clickCount: Int)
    case buttonUp(button: PointerButton)
    case dragged(button: PointerButton)
    case scrolled(deltaX: Double, deltaY: Double, isPrecise: Bool)
}

public struct PointerEvent: Sendable, Equatable {
    public let kind: PointerEventKind

    /// AppKit global screen coordinates.
    public let location: CGPoint

    public let modifiers: CGEventFlags
    public let timestamp: TimeInterval

    public init(
        kind: PointerEventKind,
        location: CGPoint,
        modifiers: CGEventFlags,
        timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime)
    {
        self.kind = kind
        self.location = location
        self.modifiers = modifiers
        self.timestamp = timestamp
    }
}

public enum InputEvent: Sendable, Equatable {
    case keyboard(KeyEvent, KeySymbol?)
    case pointer(PointerEvent)
}

public struct InputEventMask: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let keyboard = InputEventMask(rawValue: 1 << 0)
    public static let pointerMovement = InputEventMask(rawValue: 1 << 1)
    public static let pointerButtons = InputEventMask(rawValue: 1 << 2)
    public static let pointerDrag = InputEventMask(rawValue: 1 << 3)
    public static let scroll = InputEventMask(rawValue: 1 << 4)

    public static let pointer: InputEventMask = [
        .pointerMovement,
        .pointerButtons,
        .pointerDrag,
        .scroll,
    ]

    public static let all: InputEventMask = [.keyboard, .pointer]
}

public enum KeyboardEventDisposition: Sendable, Equatable {
    case ignore
    case trackOnly
    case display
}

public enum KeyboardEventFilter {
    public static func disposition(
        for event: KeyEvent,
        symbol: KeySymbol,
        settings: KeyboardSettings) -> KeyboardEventDisposition
    {
        guard settings.enabled, settings.filters.includes(symbol) else {
            return .ignore
        }

        if symbol.isModifier {
            return settings.filters.showStandaloneModifiers ? .display : .trackOnly
        }

        guard settings.contentMode == .shortcutsOnly else {
            return .display
        }

        if symbol.isSpecial {
            return .display
        }

        let shortcutFlags: CGEventFlags = [
            .maskCommand,
            .maskAlternate,
            .maskControl,
            .maskShift,
        ]
        return event.modifiers.isDisjoint(with: shortcutFlags) ? .ignore : .display
    }
}
