import Carbon.HIToolbox
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut to toggle overlay on/off. Default: ⌘⇧K
    static let toggleOverlay = Self(
        "toggleOverlay",
        default: .init(carbonKeyCode: kVK_ANSI_K, carbonModifiers: cmdKey | shiftKey))
}

extension KeyboardShortcuts.Shortcut {
    /// Returns a display string using English key positions (layout-independent).
    var displayString: String {
        var parts: [String] = []

        // Modifiers in standard macOS order
        if self.modifiers.contains(.control) {
            parts.append("⌃")
        }
        if self.modifiers.contains(.option) {
            parts.append("⌥")
        }
        if self.modifiers.contains(.shift) {
            parts.append("⇧")
        }
        if self.modifiers.contains(.command) {
            parts.append("⌘")
        }

        // Key (always English based on physical position)
        if let key = self.key {
            parts.append(Self.keyDisplayString(for: key))
        }

        return parts.joined()
    }

    /// Maps KeyboardShortcuts.Key to English display string by physical position.
    static func keyDisplayString(for key: KeyboardShortcuts.Key) -> String {
        switch Int(key.rawValue) {
        // Letters A-Z
        case kVK_ANSI_A: "A"
        case kVK_ANSI_B: "B"
        case kVK_ANSI_C: "C"
        case kVK_ANSI_D: "D"
        case kVK_ANSI_E: "E"
        case kVK_ANSI_F: "F"
        case kVK_ANSI_G: "G"
        case kVK_ANSI_H: "H"
        case kVK_ANSI_I: "I"
        case kVK_ANSI_J: "J"
        case kVK_ANSI_K: "K"
        case kVK_ANSI_L: "L"
        case kVK_ANSI_M: "M"
        case kVK_ANSI_N: "N"
        case kVK_ANSI_O: "O"
        case kVK_ANSI_P: "P"
        case kVK_ANSI_Q: "Q"
        case kVK_ANSI_R: "R"
        case kVK_ANSI_S: "S"
        case kVK_ANSI_T: "T"
        case kVK_ANSI_U: "U"
        case kVK_ANSI_V: "V"
        case kVK_ANSI_W: "W"
        case kVK_ANSI_X: "X"
        case kVK_ANSI_Y: "Y"
        case kVK_ANSI_Z: "Z"
        // Numbers
        case kVK_ANSI_0: "0"
        case kVK_ANSI_1: "1"
        case kVK_ANSI_2: "2"
        case kVK_ANSI_3: "3"
        case kVK_ANSI_4: "4"
        case kVK_ANSI_5: "5"
        case kVK_ANSI_6: "6"
        case kVK_ANSI_7: "7"
        case kVK_ANSI_8: "8"
        case kVK_ANSI_9: "9"
        // Function keys
        case kVK_F1: "F1"
        case kVK_F2: "F2"
        case kVK_F3: "F3"
        case kVK_F4: "F4"
        case kVK_F5: "F5"
        case kVK_F6: "F6"
        case kVK_F7: "F7"
        case kVK_F8: "F8"
        case kVK_F9: "F9"
        case kVK_F10: "F10"
        case kVK_F11: "F11"
        case kVK_F12: "F12"
        // Special keys
        case kVK_Space: "Space"
        case kVK_Return: "⏎"
        case kVK_Tab: "⇥"
        case kVK_Delete: "⌫"
        case kVK_Escape: "⎋"
        case kVK_LeftArrow: "←"
        case kVK_RightArrow: "→"
        case kVK_UpArrow: "↑"
        case kVK_DownArrow: "↓"
        default: "?"
        }
    }
}
