import CoreGraphics
import Foundation

// MARK: - PressedKey

/// Represents a currently pressed key with metadata.
public struct PressedKey: Identifiable, Equatable, Sendable {
    public let id: String
    public let symbol: KeySymbol
    public let pressedAt: Date

    public init(symbol: KeySymbol, pressedAt: Date = Date()) {
        self.id = symbol.id
        self.symbol = symbol
        self.pressedAt = pressedAt
    }
}

// MARK: - KeyState

/// Tracks currently pressed keys for visualization.
/// Modifiers stay until released, regular keys timeout after a delay.
@MainActor
@Observable
public final class KeyState {
    // MARK: - Constants

    /// Maximum number of keys to display.
    public static let maxDisplayedKeys = 6

    // MARK: - Properties

    /// Currently pressed keys, ordered for display.
    /// Modifiers first, then regular keys by press time.
    public private(set) var pressedKeys: [PressedKey] = []

    /// Whether any keys are currently pressed.
    public var hasKeys: Bool {
        !self.pressedKeys.isEmpty
    }

    /// Timeout duration for regular keys (from Settings).
    public var keyTimeout: TimeInterval = 1.5

    private var timeoutTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Initialization

    public init() {}

    // MARK: - Public Methods

    /// Processes a key event and updates state.
    public func processEvent(_ event: KeyEvent, symbol: KeySymbol?) {
        guard let symbol = symbol else { return }

        switch event.type {
        case .keyDown:
            self.handleKeyDown(symbol: symbol)
        case .keyUp:
            self.handleKeyUp(symbol: symbol)
        case .flagsChanged:
            self.handleFlagsChanged(keyCode: event.keyCode, symbol: symbol, flags: event.modifiers)
        }
    }

    /// Removes all pressed keys.
    public func clear() {
        for task in self.timeoutTasks.values {
            task.cancel()
        }
        self.timeoutTasks.removeAll()
        self.pressedKeys.removeAll()
    }

    // MARK: - Private Methods

    private func handleKeyDown(symbol: KeySymbol) {
        // Cancel existing timeout if key is re-pressed
        self.cancelTimeout(for: symbol.id)

        // Add key if not already present
        if !self.pressedKeys.contains(where: { $0.id == symbol.id }) {
            let key = PressedKey(symbol: symbol)
            self.addKey(key)
        }

        // Schedule timeout for non-modifier keys
        if !symbol.isModifier {
            self.scheduleTimeout(for: symbol.id)
        }
    }

    private func handleKeyUp(symbol: KeySymbol) {
        // For regular keys, the timeout handles removal
        // For modifiers, remove immediately on release
        if symbol.isModifier {
            self.removeKey(id: symbol.id)
        }
    }

    private func handleFlagsChanged(keyCode: Int64, symbol: KeySymbol, flags: CGEventFlags) {
        // Determine if this modifier is now pressed or released
        let isPressed = self.isModifierPressed(keyCode: keyCode, flags: flags)

        if isPressed {
            if !self.pressedKeys.contains(where: { $0.id == symbol.id }) {
                let key = PressedKey(symbol: symbol)
                self.addKey(key)
            }
        } else {
            self.removeKey(id: symbol.id)
        }
    }

    private func isModifierPressed(keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch keyCode {
        case 0x37, 0x36: // Command
            return flags.contains(.maskCommand)
        case 0x38, 0x3C: // Shift
            return flags.contains(.maskShift)
        case 0x3A, 0x3D: // Option
            return flags.contains(.maskAlternate)
        case 0x3B, 0x3E: // Control
            return flags.contains(.maskControl)
        case 0x39: // Caps Lock
            return flags.contains(.maskAlphaShift)
        case 0x3F: // Fn
            return flags.contains(.maskSecondaryFn)
        default:
            return false
        }
    }

    private func addKey(_ key: PressedKey) {
        self.pressedKeys.append(key)
        self.sortAndLimit()
    }

    private func removeKey(id: String) {
        self.cancelTimeout(for: id)
        self.pressedKeys.removeAll { $0.id == id }
    }

    private func sortAndLimit() {
        // Sort: modifiers first, then by press time
        self.pressedKeys.sort { lhs, rhs in
            if lhs.symbol.isModifier != rhs.symbol.isModifier {
                return lhs.symbol.isModifier
            }
            return lhs.pressedAt < rhs.pressedAt
        }

        // Limit to max displayed keys, keeping modifiers priority
        if self.pressedKeys.count > Self.maxDisplayedKeys {
            let modifiers = self.pressedKeys.filter { $0.symbol.isModifier }
            let regular = self.pressedKeys.filter { !$0.symbol.isModifier }

            let modifierCount = min(modifiers.count, Self.maxDisplayedKeys)
            let regularCount = Self.maxDisplayedKeys - modifierCount

            self.pressedKeys = Array(modifiers.prefix(modifierCount)) +
                Array(regular.prefix(regularCount))
        }
    }

    private func scheduleTimeout(for keyId: String) {
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.keyTimeout ?? 1.5))

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.removeKey(id: keyId)
            }
        }

        self.timeoutTasks[keyId] = task
    }

    private func cancelTimeout(for keyId: String) {
        self.timeoutTasks[keyId]?.cancel()
        self.timeoutTasks.removeValue(forKey: keyId)
    }
}
