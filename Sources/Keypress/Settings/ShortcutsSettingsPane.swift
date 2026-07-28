import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

@MainActor
struct ShortcutsSettingsPane: View {
    @Environment(\.studioStrings) private var strings
    @State private var conflict: ShortcutConflict?
    @State private var lastValidShortcuts: [ShortcutAction: KeyboardShortcuts.Shortcut] = [:]
    @State private var restoringActions: Set<ShortcutAction> = []
    private let controlColumnWidth: CGFloat = 224

    var body: some View {
        StudioPage(
            titleKey: "shortcuts.title",
            subtitleKey: "shortcuts.subtitle")
        {
            StudioCard("shortcuts.global", systemImage: "command", tint: .pink) {
                ForEach(Array(ShortcutAction.allCases.enumerated()), id: \.element) { index, action in
                    if index > 0 {
                        StudioDivider()
                    }
                    SettingsRow(action.titleKey, subtitleKey: action.subtitleKey) {
                        self.shortcutRecorder(for: action)
                    }
                }
            }

            StudioCard(systemImage: "info.circle", tint: .secondary) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        self.strings["shortcuts.hint"],
                        systemImage: "globe")
                    Label(
                        self.strings["shortcuts.conflictHint"],
                        systemImage: "exclamationmark.triangle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            self.rememberCurrentShortcuts()
        }
    }

    private func shortcutRecorder(for action: ShortcutAction) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                KeyboardShortcuts.Recorder(
                    for: action.name,
                    onChange: { shortcut in
                        self.validate(shortcut, for: action)
                    })
                    .frame(width: 180)
                    .accessibilityLabel(self.strings[action.titleKey])

                Button {
                    KeyboardShortcuts.reset(action.name)
                    self.rememberShortcut(for: action)
                    self.clearConflict(for: action)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help(self.strings["action.reset"])
                .accessibilityLabel(self.strings["action.reset"])
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            if let conflict, conflict.action == action {
                Label(
                    self.strings[conflict.messageKey],
                    systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: self.controlColumnWidth, alignment: .trailing)
    }

    private func validate(
        _ shortcut: KeyboardShortcuts.Shortcut?,
        for action: ShortcutAction)
    {
        if self.restoringActions.contains(action) {
            let previousShortcut = self.lastValidShortcuts[action]
            if shortcut == previousShortcut {
                self.restoringActions.remove(action)
                return
            }
            self.restoringActions.remove(action)
        }

        guard let shortcut else {
            self.lastValidShortcuts.removeValue(forKey: action)
            self.clearConflict(for: action)
            return
        }

        let isDuplicate = ShortcutAction.allCases.contains { otherAction in
            otherAction != action
                && KeyboardShortcuts.getShortcut(for: otherAction.name) == shortcut
        }
        let isInvalid = shortcut.key == nil || shortcut.modifiers.isEmpty
        let isReserved = self.isSystemReserved(shortcut)
        guard isDuplicate || isInvalid || isReserved else {
            self.lastValidShortcuts[action] = shortcut
            self.clearConflict(for: action)
            return
        }

        self.restoringActions.insert(action)
        KeyboardShortcuts.setShortcut(self.lastValidShortcuts[action], for: action.name)
        self.conflict = ShortcutConflict(
            action: action,
            kind: isDuplicate ? .duplicate : isReserved ? .reserved : .invalid)
    }

    private func isSystemReserved(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        guard let key = shortcut.key else { return false }
        let keyCode = Int(key.rawValue)
        let modifiers = shortcut.modifiers.intersection([
            .command,
            .option,
            .control,
            .shift,
        ])

        if keyCode == kVK_Tab, modifiers.contains(.command) {
            return true
        }
        if keyCode == kVK_Space,
           modifiers == [.command] || modifiers == [.control]
        {
            return true
        }
        if keyCode == kVK_Escape,
           modifiers == [.command, .option]
        {
            return true
        }
        if [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5].contains(keyCode),
           modifiers.contains([.command, .shift])
        {
            return true
        }
        return [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow]
            .contains(keyCode)
            && modifiers == [.control]
    }

    private func rememberCurrentShortcuts() {
        for action in ShortcutAction.allCases {
            self.rememberShortcut(for: action)
        }
    }

    private func rememberShortcut(for action: ShortcutAction) {
        if let shortcut = KeyboardShortcuts.getShortcut(for: action.name) {
            self.lastValidShortcuts[action] = shortcut
        } else {
            self.lastValidShortcuts.removeValue(forKey: action)
        }
    }

    private func clearConflict(for action: ShortcutAction) {
        if self.conflict?.action == action {
            self.conflict = nil
        }
    }
}

private enum ShortcutAction: CaseIterable, Hashable {
    case toggle
    case pointer
    case content
    case position
    case increaseSize
    case decreaseSize

    var name: KeyboardShortcuts.Name {
        switch self {
        case .toggle: .toggleOverlay
        case .pointer: .togglePointer
        case .content: .switchContentMode
        case .position: .editPosition
        case .increaseSize: .increaseOverlaySize
        case .decreaseSize: .decreaseOverlaySize
        }
    }

    var titleKey: String {
        switch self {
        case .toggle: "shortcuts.toggle"
        case .pointer: "shortcuts.pointer"
        case .content: "shortcuts.content"
        case .position: "shortcuts.position"
        case .increaseSize: "shortcuts.size.increase"
        case .decreaseSize: "shortcuts.size.decrease"
        }
    }

    var subtitleKey: String {
        "\(self.titleKey).subtitle"
    }
}

private struct ShortcutConflict: Equatable {
    let action: ShortcutAction
    let kind: Kind

    var messageKey: String {
        switch self.kind {
        case .duplicate: "shortcuts.duplicateConflict"
        case .invalid: "shortcuts.invalidConflict"
        case .reserved: "shortcuts.reservedConflict"
        }
    }

    enum Kind: Equatable {
        case duplicate
        case invalid
        case reserved
    }
}
