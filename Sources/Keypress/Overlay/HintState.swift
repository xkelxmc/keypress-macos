import Foundation

/// Toggle hint state for showing "Keypress On/Off (shortcut)".
struct ToggleHint: Equatable {
    let isEnabled: Bool
    let shortcutText: String
}

/// Observable state for the toggle hint overlay.
@MainActor
@Observable
final class HintState {
    /// Current hint to display (nil = hidden).
    private(set) var currentHint: ToggleHint?

    private var hideTask: Task<Void, Never>?

    /// Shows a hint for 2 seconds, then hides it.
    func show(isEnabled: Bool, shortcutText: String) {
        self.hideTask?.cancel()
        self.currentHint = ToggleHint(isEnabled: isEnabled, shortcutText: shortcutText)

        self.hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled else { return }
            self?.currentHint = nil
        }
    }

    /// Hides the hint immediately.
    func hide() {
        self.hideTask?.cancel()
        self.hideTask = nil
        self.currentHint = nil
    }
}
