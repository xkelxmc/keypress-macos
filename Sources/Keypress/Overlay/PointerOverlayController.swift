import AppKit
@preconcurrency import ApplicationServices
import KeypressCore

@MainActor
final class PointerOverlayController {
    private static let spaceCompletionSettleDuration = Duration.milliseconds(140)
    private static let spaceTransitionFallbackDuration = Duration.seconds(2)

    private let config: KeypressConfig
    private let window = CursorHaloWindow()

    private var cachedStyle: CursorHaloStyle?
    private var lastLocation: NSPoint?
    private var lastTimestamp: TimeInterval?
    private var pressedButtons: Set<PointerButton> = []
    private var releaseRecoveryTask: Task<Void, Never>?
    private var spaceRecoveryTask: Task<Void, Never>?
    private var spaceTransitionActive = false
    private var spaceTransitionGeneration: UInt64 = 0

    init(config: KeypressConfig) {
        self.config = config
    }

    func process(_ event: PointerEvent) {
        guard self.config.general.enabled, self.config.pointer.enabled else {
            self.clear()
            return
        }

        guard !self.spaceTransitionActive else { return }

        let location = event.location
        let velocity = self.velocity(to: location, at: event.timestamp)
        let style = self.style

        switch event.kind {
        case .moved:
            self.recoverReleasedButtons(at: location, style: style)
            guard self.config.pointer.visibility != .actionsOnly,
                  self.config.pointer.showMovement
            else {
                if self.window.isVisible {
                    self.window.update(style: style, location: location)
                }
                return
            }
            self.window.handle(.movement(velocity: velocity), location: location, style: style)

        case let .buttonDown(button, _):
            self.recoverReleasedButtons(at: location, style: style)
            guard let cursorButton = self.cursorButton(for: button) else { return }
            guard self.shows(button) else {
                self.window.update(style: style, location: location)
                return
            }
            self.pressedButtons.insert(button)
            self.startReleaseRecoveryIfNeeded()
            self.window.handle(.buttonDown(cursorButton), location: location, style: style)

        case let .buttonUp(button):
            self.recoverReleasedButtons(excluding: button, at: location, style: style)
            guard let cursorButton = self.cursorButton(for: button) else { return }
            let wasTracked = self.pressedButtons.remove(button) != nil
            self.stopReleaseRecoveryIfIdle()
            guard self.shows(button) || wasTracked else {
                self.window.update(style: style, location: location)
                return
            }
            self.window.handle(.buttonUp(cursorButton), location: location, style: style)

        case let .dragged(button):
            self.recoverReleasedButtons(excluding: button, at: location, style: style)
            guard self.config.pointer.showDrag else {
                self.window.update(style: style, location: location)
                return
            }
            guard let cursorButton = self.cursorButton(for: button) else { return }
            self.pressedButtons.insert(button)
            self.startReleaseRecoveryIfNeeded()
            self.window.handle(
                .drag(velocity: velocity, button: cursorButton),
                location: location,
                style: style)

        case let .scrolled(deltaX, deltaY, _):
            self.recoverReleasedButtons(at: location, style: style)
            guard self.config.pointer.showScroll else { return }
            self.window.handle(
                .scroll(delta: CGSize(width: deltaX, height: deltaY)),
                location: location,
                style: style)
        }
    }

    func refresh() {
        guard self.config.general.enabled, self.config.pointer.enabled else {
            self.clear()
            return
        }
        self.cachedStyle = self.makeStyle()
        guard !self.spaceTransitionActive else {
            self.window.clear()
            return
        }
        self.window.update(style: self.style, location: NSEvent.mouseLocation)
    }

    func clear() {
        self.releaseRecoveryTask?.cancel()
        self.releaseRecoveryTask = nil
        self.spaceRecoveryTask?.cancel()
        self.spaceRecoveryTask = nil
        self.spaceTransitionGeneration &+= 1
        self.spaceTransitionActive = false
        self.cachedStyle = nil
        self.pressedButtons.removeAll()
        self.lastLocation = nil
        self.lastTimestamp = nil
        self.window.clear()
    }

    func handleNavigationSwipe(cancelled: Bool) {
        self.beginSpaceTransition()
        self.scheduleSpaceRecovery(
            after: cancelled
                ? Self.spaceCompletionSettleDuration
                : Self.spaceTransitionFallbackDuration)
    }

    func handleActiveSpaceChanged() {
        self.beginSpaceTransition()
        self.scheduleSpaceRecovery(after: Self.spaceCompletionSettleDuration)
    }

    private func beginSpaceTransition() {
        guard !self.spaceTransitionActive else { return }

        self.releaseRecoveryTask?.cancel()
        self.releaseRecoveryTask = nil
        self.spaceRecoveryTask?.cancel()
        self.spaceRecoveryTask = nil
        self.spaceTransitionGeneration &+= 1
        self.spaceTransitionActive = true
        self.pressedButtons.removeAll()
        self.lastLocation = nil
        self.lastTimestamp = nil
        self.window.clear()
    }

    private func scheduleSpaceRecovery(after delay: Duration) {
        self.spaceRecoveryTask?.cancel()
        let generation = self.spaceTransitionGeneration
        self.spaceRecoveryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled,
                  let self,
                  self.spaceTransitionActive,
                  self.spaceTransitionGeneration == generation
            else {
                return
            }
            self.spaceRecoveryTask = nil
            self.spaceTransitionActive = false
            self.lastLocation = nil
            self.lastTimestamp = nil
            self.refresh()
        }
    }

    private var style: CursorHaloStyle {
        if let cachedStyle {
            return cachedStyle
        }
        let style = self.makeStyle()
        self.cachedStyle = style
        return style
    }

    private func makeStyle() -> CursorHaloStyle {
        let theme = self.config.effectiveTheme(isSystemDark: self.systemIsDark)
        return CursorHaloStyle(settings: self.config.pointer, theme: theme.pointer)
    }

    private var systemIsDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func velocity(to location: NSPoint, at timestamp: TimeInterval) -> CGSize {
        defer {
            self.lastLocation = location
            self.lastTimestamp = timestamp
        }

        guard let previousLocation = self.lastLocation,
              let previousTimestamp = self.lastTimestamp
        else {
            return .zero
        }

        let elapsed = timestamp - previousTimestamp
        guard elapsed > 0, elapsed < 0.25 else { return .zero }
        return CGSize(
            width: (location.x - previousLocation.x) / elapsed,
            height: (location.y - previousLocation.y) / elapsed)
    }

    private func shows(_ button: PointerButton) -> Bool {
        switch button {
        case .left: self.config.pointer.showLeftClick
        case .right: self.config.pointer.showRightClick
        case .middle: self.config.pointer.showMiddleClick
        case .other: false
        }
    }

    private func cursorButton(for button: PointerButton) -> CursorButton? {
        switch button {
        case .left: .primary
        case .right: .secondary
        case .middle: .middle
        case .other: nil
        }
    }

    private func recoverReleasedButtons(
        excluding excludedButton: PointerButton? = nil,
        at location: NSPoint,
        style: CursorHaloStyle)
    {
        for button in Array(self.pressedButtons)
            where button != excludedButton && !Self.isPressed(button)
        {
            self.pressedButtons.remove(button)
            guard let cursorButton = self.cursorButton(for: button) else { continue }
            self.window.handle(.buttonUp(cursorButton), location: location, style: style)
        }
        self.stopReleaseRecoveryIfIdle()
    }

    private func startReleaseRecoveryIfNeeded() {
        guard !self.pressedButtons.isEmpty, self.releaseRecoveryTask == nil else { return }

        self.releaseRecoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }
                self.recoverReleasedButtons(
                    at: NSEvent.mouseLocation,
                    style: self.style)
                if self.pressedButtons.isEmpty {
                    self.releaseRecoveryTask = nil
                    return
                }
            }
        }
    }

    private func stopReleaseRecoveryIfIdle() {
        guard self.pressedButtons.isEmpty else { return }
        self.releaseRecoveryTask?.cancel()
        self.releaseRecoveryTask = nil
    }

    private static func isPressed(_ button: PointerButton) -> Bool {
        let cgButton: CGMouseButton
        switch button {
        case .left:
            cgButton = .left
        case .right:
            cgButton = .right
        case .middle:
            cgButton = .center
        case let .other(number):
            guard let otherButton = CGMouseButton(rawValue: UInt32(number)) else {
                return false
            }
            cgButton = otherButton
        }
        return CGEventSource.buttonState(.combinedSessionState, button: cgButton)
    }
}
