import AppKit
import KeypressCore
import Observation
import SwiftUI

@MainActor
@Observable
final class PetController {
    private static let ambientDelay: TimeInterval = 8
    private static let sleepDelay: TimeInterval = 30
    private static let huntDistance: CGFloat = 220
    private static let huntRearmDistance: CGFloat = 280
    private static let huntHorizontalDistance: CGFloat = 32
    static let dragThreshold: CGFloat = 4

    fileprivate let config: KeypressConfig
    private let keyboardFrame: () -> NSRect?
    private var activityScheduler = PetActivityScheduler()
    private var animationTask: Task<Void, Never>?
    private var behaviorTask: Task<Void, Never>?
    private var typingLifecycleTask: Task<Void, Never>?
    private var pointerReleaseTask: Task<Void, Never>?
    private var accessibilityObserver: NSObjectProtocol?
    private var runtimeIsActive = false
    private var typingTimestamps: [TimeInterval] = []
    private var lastPointerTime: TimeInterval?
    private var lastPointerLocation: CGPoint?
    private var lastInteractionTime = ProcessInfo.processInfo.systemUptime
    private var nextAmbientTime = ProcessInfo.processInfo.systemUptime + PetController.ambientDelay
    private var huntIsArmed = true
    private var secureInputEnabled = false
    private var dragStartLocation: CGPoint?
    private var dragStartOrigin: CGPoint?

    @ObservationIgnored private lazy var window = PetWindow(controller: self)

    private(set) var state = PetRuntimeState.hidden
    private(set) var frameIndex = 0
    private(set) var typingFramesPerSecond = PetTypingRate.minimumFPS

    var accessibilityLabel: String {
        self.localizedString("pet.title")
    }

    var supportsPetReaction: Bool {
        self.isEnabled
            && self.config.pet.visibility == .always
            && self.config.pet.petReaction
            && PetRuntimeState.petting.canInterrupt(self.state)
    }

    init(
        config: KeypressConfig,
        keyboardFrame: @escaping () -> NSRect?)
    {
        self.config = config
        self.keyboardFrame = keyboardFrame
    }

    func start() {
        guard self.config.general.enabled, self.config.pet.enabled else { return }
        guard PetSpriteSheet.shared.isAvailable else { return }
        self.refresh()
    }

    func stop() {
        let wasActive = self.runtimeIsActive
        self.deactivateRuntime()
        self.secureInputEnabled = false
        self.transition(to: .hidden)
        if wasActive {
            self.window.hide()
        }
    }

    func refresh() {
        guard self.isEnabled else {
            let wasActive = self.runtimeIsActive
            self.deactivateRuntime()
            self.transition(to: .hidden)
            if wasActive {
                self.window.hide()
            }
            return
        }

        self.activateRuntime()
        self.reconcileBehaviorLoop()
        self.window.updateSize()
        self.window.updatePosition(keyboardFrame: self.keyboardFrame())
        if !self.config.pet.watchCursor, case .looking = self.state {
            self.transition(to: .idle)
        }

        if self.config.pet.visibility == .typingOnly,
           self.state != .typing,
           self.state != .carried,
           self.state != .settling
        {
            self.transition(to: .hidden)
            self.window.hide()
        } else {
            if !self.config.pet.sleep {
                switch self.state {
                case .sleeping, .sleepTransition:
                    self.transition(to: .idle)
                default:
                    break
                }
            }
            if self.state == .hidden {
                self.noteInteraction(at: ProcessInfo.processInfo.systemUptime)
                self.transition(to: .idle)
            }
            self.window.show()
        }
    }

    func refreshInitialPosition() {
        guard self.isEnabled,
              self.config.pet.placement == nil,
              self.dragStartLocation == nil
        else {
            return
        }
        self.window.updatePosition(keyboardFrame: self.keyboardFrame())
    }

    func resetTransientState() {
        let now = ProcessInfo.processInfo.systemUptime
        self.typingLifecycleTask?.cancel()
        self.typingLifecycleTask = nil
        self.typingTimestamps.removeAll()
        self.lastPointerTime = nil
        self.lastPointerLocation = nil
        self.huntIsArmed = true
        self.cancelPointerInteraction()
        self.lastInteractionTime = now
        self.nextAmbientTime = now + Self.ambientDelay
        if self.config.pet.visibility == .typingOnly {
            self.transition(to: .hidden)
            if self.runtimeIsActive {
                self.window.hide()
            }
        } else if self.isEnabled {
            self.transition(to: .idle)
            self.window.show()
        }
    }

    func handleSecureInputChanged(_ enabled: Bool) {
        self.secureInputEnabled = enabled
        guard enabled else { return }
        self.resetTransientState()
    }

    func processKeyboard(
        _ event: KeyEvent,
        isRegisteredShortcut: Bool)
    {
        guard self.isEnabled,
              !self.secureInputEnabled,
              event.type == .keyDown,
              !isRegisteredShortcut,
              PetRuntimeState.typing.canInterrupt(self.state),
              !KeyCodeMapper.isModifier(event.keyCode)
        else {
            return
        }

        let now = event.monotonicTimestamp
        self.typingTimestamps.removeAll { now - $0 > PetTypingRate.sampleWindow }
        self.typingTimestamps.append(now)
        self.scheduleTypingLifecycle(after: now)
        self.noteInteraction(at: ProcessInfo.processInfo.systemUptime)
        self.typingFramesPerSecond = PetTypingRate.framesPerSecond(
            timestamps: self.typingTimestamps,
            now: now)

        self.window.updatePosition(keyboardFrame: self.keyboardFrame())
        if self.state != .typing {
            self.interrupt(with: .typing)
        }
        self.window.show()
    }

    func processPointer(_ event: PointerEvent) {
        guard self.isEnabled,
              self.config.pet.visibility == .always,
              self.config.pet.watchCursor || self.config.pet.huntCursor,
              self.state != .carried,
              self.state != .settling
        else {
            return
        }

        switch event.kind {
        case .moved, .dragged:
            self.processPointerMovement(event)
        case .buttonDown, .buttonUp, .scrolled:
            break
        }
    }

    func handlePointerDrag(at location: CGPoint) {
        guard self.isEnabled else { return }

        if self.dragStartLocation == nil {
            self.dragStartLocation = location
            self.dragStartOrigin = self.window.frame.origin
            self.startPointerReleaseWatchdog()
            return
        }

        guard let startLocation = self.dragStartLocation,
              let startOrigin = self.dragStartOrigin
        else {
            return
        }
        let distance = hypot(location.x - startLocation.x, location.y - startLocation.y)
        guard distance >= Self.dragThreshold || self.state == .carried else { return }

        if self.state != .carried {
            self.interrupt(with: .carried)
        }
        self.window.move(
            from: startOrigin,
            pointerStart: startLocation,
            pointerLocation: location)
        self.window.refreshPointerCursor()
    }

    func handlePointerRelease(at location: CGPoint) {
        self.pointerReleaseTask?.cancel()
        self.pointerReleaseTask = nil
        let hadPointerInteraction = self.dragStartLocation != nil
        defer {
            self.dragStartLocation = nil
            self.dragStartOrigin = nil
        }

        guard hadPointerInteraction else { return }

        if self.state == .carried {
            self.window.savePlacement()
            self.noteInteraction(at: ProcessInfo.processInfo.systemUptime)
            self.transition(to: .settling)
            self.window.refreshPointerCursor()
            return
        }

        self.performPetReaction()
    }

    func performPetReaction() {
        guard self.supportsPetReaction else { return }
        self.noteInteraction(at: ProcessInfo.processInfo.systemUptime)
        self.interrupt(with: .petting)
    }

    func moveForAccessibility(horizontal: CGFloat, vertical: CGFloat) {
        guard self.isEnabled else { return }
        self.window.moveBy(horizontal: horizontal, vertical: vertical)
        self.window.savePlacement()
        self.noteInteraction(at: ProcessInfo.processInfo.systemUptime)
    }

    func localizedString(_ key: String) -> String {
        StudioStrings(
            languageCode: self.config.general.language.studioLanguageCode)[key]
    }

    private var isEnabled: Bool {
        self.config.general.enabled
            && self.config.pet.enabled
            && PetSpriteSheet.shared.isAvailable
    }

    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func processPointerMovement(_ event: PointerEvent) {
        guard let previousLocation = self.lastPointerLocation,
              let previousTime = self.lastPointerTime
        else {
            self.lastPointerLocation = event.location
            self.lastPointerTime = event.timestamp
            return
        }

        guard event.timestamp > previousTime else {
            self.lastPointerLocation = event.location
            self.lastPointerTime = event.timestamp
            return
        }

        let delta = CGSize(
            width: event.location.x - previousLocation.x,
            height: event.location.y - previousLocation.y)
        let distance = hypot(delta.width, delta.height)
        guard distance >= 2 else { return }

        self.lastPointerLocation = event.location
        self.lastPointerTime = event.timestamp
        self.noteInteraction(at: event.timestamp)

        if self.state == .sleeping {
            self.transition(to: .sleepTransition(reverse: true))
            return
        }
        if case let .sleepTransition(reverse) = self.state {
            if !reverse {
                self.transition(to: .sleepTransition(reverse: true))
            }
            return
        }
        guard self.state.priority < PetRuntimeState.pouncing(mirrored: false).priority else { return }

        let catCenter = CGPoint(x: self.window.frame.midX, y: self.window.frame.midY)
        let targetDelta = CGSize(
            width: event.location.x - catCenter.x,
            height: event.location.y - catCenter.y)
        let targetDistance = hypot(targetDelta.width, targetDelta.height)

        if targetDistance >= Self.huntRearmDistance {
            self.huntIsArmed = true
        }

        if self.config.pet.huntCursor,
           self.huntIsArmed,
           targetDistance <= Self.huntDistance,
           abs(targetDelta.width) >= Self.huntHorizontalDistance
        {
            self.huntIsArmed = false
            self.transition(to: .pouncing(mirrored: targetDelta.width < 0))
            return
        }

        guard self.config.pet.watchCursor, targetDistance >= 12 else { return }
        let lookingState = PetRuntimeState.looking(direction: Self.lookDirection(for: targetDelta))
        guard self.state != lookingState else { return }
        self.transition(to: lookingState)
    }

    private static func lookDirection(for delta: CGSize) -> Int {
        let angle = atan2(delta.width, delta.height)
        let normalized = angle >= 0 ? angle : angle + .pi * 2
        return Int((normalized / (.pi * 2) * 16).rounded()) % 16
    }

    private func noteInteraction(at time: TimeInterval) {
        self.lastInteractionTime = time
        self.nextAmbientTime = time + Self.ambientDelay
    }

    private func activateRuntime() {
        guard !self.runtimeIsActive else { return }
        self.runtimeIsActive = true
        let now = ProcessInfo.processInfo.systemUptime
        self.typingTimestamps.removeAll()
        self.lastPointerTime = nil
        self.lastPointerLocation = nil
        self.huntIsArmed = true
        self.cancelPointerInteraction()
        self.noteInteraction(at: now)
        self.reconcileBehaviorLoop()
        self.startObservingAccessibility()
    }

    private func deactivateRuntime() {
        self.runtimeIsActive = false
        self.animationTask?.cancel()
        self.animationTask = nil
        self.typingLifecycleTask?.cancel()
        self.typingLifecycleTask = nil
        self.stopBehaviorLoop()
        self.typingTimestamps.removeAll()
        self.lastPointerTime = nil
        self.lastPointerLocation = nil
        self.huntIsArmed = true
        self.cancelPointerInteraction()
        self.typingFramesPerSecond = PetTypingRate.minimumFPS
        self.stopObservingAccessibility()
    }

    private func scheduleTypingLifecycle(after lastEventTime: TimeInterval) {
        self.typingLifecycleTask?.cancel()
        self.typingLifecycleTask = Task { @MainActor [weak self] in
            let now = ProcessInfo.processInfo.systemUptime
            let typingDelay = max(
                0,
                PetTypingRate.burstTimeout - (now - lastEventTime))
            try? await Task.sleep(for: .seconds(typingDelay))
            guard !Task.isCancelled, let self else { return }
            if self.state == .typing {
                self.returnToRest()
            }

            let pruneDelay = max(
                0,
                PetTypingRate.sampleWindow
                    - (ProcessInfo.processInfo.systemUptime - lastEventTime))
            try? await Task.sleep(for: .seconds(pruneDelay))
            guard !Task.isCancelled else { return }
            let pruneTime = ProcessInfo.processInfo.systemUptime
            self.typingTimestamps.removeAll {
                pruneTime - $0 >= PetTypingRate.sampleWindow
            }
            self.typingLifecycleTask = nil
        }
    }

    private func startPointerReleaseWatchdog() {
        self.pointerReleaseTask?.cancel()
        self.pointerReleaseTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled,
                      let self,
                      self.dragStartLocation != nil
                else {
                    return
                }
                guard NSEvent.pressedMouseButtons & 1 == 0 else { continue }
                self.handlePointerRelease(at: NSEvent.mouseLocation)
                return
            }
        }
    }

    private func reconcileBehaviorLoop() {
        if self.config.pet.visibility == .always {
            self.startBehaviorLoop()
        } else {
            self.stopBehaviorLoop()
        }
    }

    private func startBehaviorLoop() {
        guard self.behaviorTask == nil else { return }
        self.behaviorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                self.updateBehavior(at: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    private func stopBehaviorLoop() {
        self.behaviorTask?.cancel()
        self.behaviorTask = nil
    }

    private func updateBehavior(at now: TimeInterval) {
        guard self.isEnabled else { return }

        if case .looking = self.state,
           let lastPointerTime = self.lastPointerTime,
           now - lastPointerTime >= PetCursorTiming.lookTimeout
        {
            self.transition(to: .idle)
        }

        guard self.config.pet.visibility == .always,
              self.state == .idle
        else {
            return
        }

        if self.config.pet.sleep,
           now - self.lastInteractionTime >= Self.sleepDelay
        {
            self.transition(to: .sleepTransition(reverse: false))
            return
        }

        guard now >= self.nextAmbientTime else { return }
        self.nextAmbientTime = now + Self.ambientDelay
        let enabledActivities = PetAmbientActivity.allCases.filter(self.isEnabled)
        guard let activity = self.activityScheduler.next(
            mode: self.config.pet.activityMode,
            enabled: enabledActivities,
            randomValue: Int.random(in: 0...Int.max))
        else {
            return
        }
        self.transition(to: .ambient(activity))
    }

    private func startObservingAccessibility() {
        guard self.accessibilityObserver == nil else { return }
        self.accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.state != .hidden else { return }
                self.transition(to: self.state)
            }
        }
    }

    private func stopObservingAccessibility() {
        guard let accessibilityObserver = self.accessibilityObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        self.accessibilityObserver = nil
    }

    private func isEnabled(_ activity: PetAmbientActivity) -> Bool {
        switch activity {
        case .stretch: self.config.pet.stretch
        case .groom: self.config.pet.groom
        case .playTail: self.config.pet.playTail
        }
    }

    private func transition(to nextState: PetRuntimeState) {
        let previousState = self.state
        let previousFrameIndex = self.frameIndex
        self.animationTask?.cancel()
        self.animationTask = nil
        self.state = nextState

        if nextState == .hidden {
            self.frameIndex = 0
            return
        }

        guard let definition = PetSpriteSheet.shared.definition(for: nextState) else {
            self.frameIndex = 0
            return
        }

        let isReverse: Bool = if case let .sleepTransition(reverse) = nextState {
            reverse
        } else {
            false
        }
        let reversesCurrentSleepTransition: Bool =
            if case let .sleepTransition(previousReverse) = previousState,
            case let .sleepTransition(nextReverse) = nextState {
                !previousReverse && nextReverse
            } else {
                false
            }

        if case .looking = nextState {
            self.frameIndex = 0
            return
        }

        self.frameIndex = self.reduceMotion
            ? max(0, (definition.count - 1) / 2)
            : (
                isReverse
                    ? (
                        reversesCurrentSleepTransition
                            ? min(max(previousFrameIndex, 0), definition.count - 1)
                            : definition.count - 1)
                    : 0)

        if self.reduceMotion {
            guard !definition.loop else { return }
            self.animationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(
                    for: .seconds(PetAnimationTiming.reducedMotionOneShotDuration))
                guard !Task.isCancelled, let self, self.state == nextState else { return }
                self.complete(nextState)
            }
            return
        }

        self.animationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.state == nextState {
                let framesPerSecond = nextState == .typing
                    ? self.typingFramesPerSecond
                    : definition.fps
                try? await Task.sleep(
                    for: .seconds(1 / max(framesPerSecond, 1)))
                guard !Task.isCancelled, self.state == nextState else { return }

                let nextIndex = self.frameIndex + (isReverse ? -1 : 1)
                let reachedEnd = isReverse
                    ? nextIndex < 0
                    : nextIndex >= definition.count
                if !reachedEnd {
                    self.frameIndex = nextIndex
                    continue
                }

                if definition.loop {
                    self.frameIndex = isReverse ? definition.count - 1 : 0
                } else {
                    self.complete(nextState)
                    return
                }
            }
        }
    }

    private func interrupt(with nextState: PetRuntimeState) {
        guard nextState.canInterrupt(self.state) else { return }
        self.transition(to: nextState)
    }

    private func complete(_ completedState: PetRuntimeState) {
        guard self.state == completedState else { return }
        switch completedState {
        case let .sleepTransition(reverse):
            self.transition(to: reverse ? .idle : .sleeping)
        case .ambient, .pouncing, .petting, .settling:
            self.returnToRest()
        default:
            break
        }
    }

    private func returnToRest() {
        if self.config.pet.visibility == .typingOnly {
            self.transition(to: .hidden)
            self.window.hide()
        } else {
            self.transition(to: .idle)
            self.window.show()
        }
    }

    fileprivate func cancelPointerInteraction() {
        self.pointerReleaseTask?.cancel()
        self.pointerReleaseTask = nil
        self.dragStartLocation = nil
        self.dragStartOrigin = nil
    }
}

enum PetInitialPlacement {
    private static let keyboardSpacing: CGFloat = 12
    private static let fallbackMargin: CGFloat = 24
    private static let provisionalKeyboardRowHeight: CGFloat = 80

    static func origin(
        petSize: CGSize,
        keyboardFrame: CGRect?,
        visibleFrame: CGRect)
        -> CGPoint
    {
        guard let keyboardFrame,
              self.isVisible(keyboardFrame, inside: visibleFrame)
        else {
            return self.clamped(
                CGPoint(
                    x: visibleFrame.maxX - petSize.width - self.fallbackMargin,
                    y: visibleFrame.minY + self.fallbackMargin),
                petSize: petSize,
                to: visibleFrame)
        }

        let keyboardIsAbove = keyboardFrame.midY >= visibleFrame.midY
        let effectiveKeyboardFrame = keyboardFrame.isEmpty
            ? CGRect(
                x: keyboardFrame.minX,
                y: keyboardIsAbove
                    ? keyboardFrame.minY - self.provisionalKeyboardRowHeight
                    : keyboardFrame.minY,
                width: 0,
                height: self.provisionalKeyboardRowHeight)
            : keyboardFrame
        let x = effectiveKeyboardFrame.midX <= visibleFrame.midX
            ? effectiveKeyboardFrame.minX
            : effectiveKeyboardFrame.maxX - petSize.width
        let y = keyboardIsAbove
            ? effectiveKeyboardFrame.minY - petSize.height - self.keyboardSpacing
            : effectiveKeyboardFrame.maxY + self.keyboardSpacing
        return self.clamped(
            CGPoint(x: x, y: y),
            petSize: petSize,
            to: visibleFrame)
    }

    private static func isVisible(_ frame: CGRect, inside visibleFrame: CGRect) -> Bool {
        if !frame.isEmpty {
            return frame.intersects(visibleFrame)
        }
        return frame.minX >= visibleFrame.minX
            && frame.minX <= visibleFrame.maxX
            && frame.minY >= visibleFrame.minY
            && frame.minY <= visibleFrame.maxY
    }

    private static func clamped(
        _ origin: CGPoint,
        petSize: CGSize,
        to visibleFrame: CGRect)
        -> CGPoint
    {
        CGPoint(
            x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - petSize.width),
            y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - petSize.height))
    }
}

@MainActor
private final class PetWindow: NSPanel {
    private unowned let controller: PetController

    init(controller: PetController) {
        self.controller = controller
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 128, height: 139),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.isMovable = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]
        self.contentView = PetHostingView(controller: controller)
    }

    override var canBecomeKey: Bool {
        get { false }
        set {}
    }

    override var canBecomeMain: Bool {
        get { false }
        set {}
    }

    func show() {
        if !self.isVisible {
            self.orderFrontRegardless()
        }
        self.refreshPointerCursor()
    }

    func hide() {
        self.controller.cancelPointerInteraction()
        if let contentView = self.contentView {
            self.invalidateCursorRects(for: contentView)
        }
        self.orderOut(nil)
    }

    func updateSize() {
        let center = NSPoint(x: self.frame.midX, y: self.frame.midY)
        let size = PetSpriteMetrics.canvasSize(
            contentWidth: CGFloat(self.controller.config.pet.size))
        self.setFrame(
            NSRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height),
            display: true)
    }

    func updatePosition(keyboardFrame: NSRect?) {
        if let placement = self.controller.config.pet.placement {
            let frame =
                ConnectedDisplays.display(withID: placement.displayID)?.screen.visibleFrame
                    ?? ConnectedDisplays.main?.screen.visibleFrame
                    ?? self.resolvedDisplay().screen.visibleFrame
            let origin = CGPoint(
                x: frame.minX + CGFloat(placement.center.x) * frame.width - self.frame.width / 2,
                y: frame.minY + CGFloat(placement.center.y) * frame.height - self.frame.height / 2)
            self.setFrameOrigin(self.clamped(origin, to: frame))
            return
        }

        let display =
            keyboardFrame.flatMap { frame in
                ConnectedDisplays.display(
                    containing: CGPoint(x: frame.midX, y: frame.midY))
            }
            ?? self.resolvedDisplay()
        let visibleFrame = display.screen.visibleFrame
        let contentSize = CGSize(
            width: CGFloat(self.controller.config.pet.size),
            height: self.frame.height)
        let contentOrigin = PetInitialPlacement.origin(
            petSize: contentSize,
            keyboardFrame: keyboardFrame,
            visibleFrame: visibleFrame)
        self.setFrameOrigin(
            CGPoint(
                x: contentOrigin.x - self.horizontalContentInset,
                y: contentOrigin.y))
    }

    func move(
        from origin: CGPoint,
        pointerStart: CGPoint,
        pointerLocation: CGPoint)
    {
        let desired = CGPoint(
            x: origin.x + pointerLocation.x - pointerStart.x,
            y: origin.y + pointerLocation.y - pointerStart.y)
        let display = ConnectedDisplays.display(containing: pointerLocation)
            ?? self.resolvedDisplay()
        self.setFrameOrigin(self.clamped(desired, to: display.screen.visibleFrame))
    }

    func savePlacement() {
        let center = CGPoint(x: self.frame.midX, y: self.frame.midY)
        guard let display = ConnectedDisplays.display(containing: center) else { return }
        let visibleFrame = display.screen.visibleFrame
        self.controller.config.pet.placement = PetPlacement(
            displayID: display.id,
            center: NormalizedPoint(
                x: (center.x - visibleFrame.minX) / visibleFrame.width,
                y: (center.y - visibleFrame.minY) / visibleFrame.height))
    }

    func moveBy(horizontal: CGFloat, vertical: CGFloat) {
        let center = CGPoint(x: self.frame.midX, y: self.frame.midY)
        let display = ConnectedDisplays.display(containing: center)
            ?? self.resolvedDisplay()
        let origin = CGPoint(
            x: self.frame.origin.x + horizontal,
            y: self.frame.origin.y + vertical)
        self.setFrameOrigin(self.clamped(origin, to: display.screen.visibleFrame))
    }

    func refreshPointerCursor() {
        guard let contentView = self.contentView else { return }
        self.invalidateCursorRects(for: contentView)
        guard self.isVisible,
              self.controller.state != .hidden,
              self.interactionFrame.contains(NSEvent.mouseLocation)
        else {
            return
        }
        (self.controller.state == .carried ? NSCursor.closedHand : NSCursor.openHand).set()
    }

    private func resolvedDisplay() -> ConnectedDisplay {
        if let displayID = self.controller.config.pet.placement?.displayID,
           let display = ConnectedDisplays.display(withID: displayID)
        {
            return display
        }
        if self.controller.config.pet.placement != nil,
           let main = ConnectedDisplays.main
        {
            return main
        }
        return ConnectedDisplays.display(containing: NSEvent.mouseLocation)
            ?? ConnectedDisplays.main
            ?? ConnectedDisplays.all[0]
    }

    private func clamped(_ origin: CGPoint, to visibleFrame: CGRect) -> CGPoint {
        let contentWidth = CGFloat(self.controller.config.pet.size)
        let contentOriginX = origin.x + self.horizontalContentInset
        return CGPoint(
            x: min(
                max(contentOriginX, visibleFrame.minX),
                visibleFrame.maxX - contentWidth) - self.horizontalContentInset,
            y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - self.frame.height))
    }

    fileprivate var interactionFrame: NSRect {
        NSRect(
            x: self.frame.minX + self.horizontalContentInset,
            y: self.frame.minY,
            width: CGFloat(self.controller.config.pet.size),
            height: self.frame.height)
    }

    fileprivate var horizontalContentInset: CGFloat {
        (self.frame.width - CGFloat(self.controller.config.pet.size)) / 2
    }
}

@MainActor
private final class PetHostingView: NSHostingView<PetSpriteView> {
    private unowned let controller: PetController

    convenience init(controller: PetController) {
        self.init(rootView: PetSpriteView(controller: controller))
    }

    required init(rootView: PetSpriteView) {
        self.controller = rootView.controller
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        self.controller.handlePointerDrag(at: NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        self.controller.handlePointerDrag(at: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        self.controller.handlePointerRelease(at: NSEvent.mouseLocation)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard self.interactionRect.contains(point) else { return nil }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard self.controller.state != .hidden else { return }
        self.addCursorRect(
            self.interactionRect,
            cursor: self.controller.state == .carried ? .closedHand : .openHand)
    }

    private var interactionRect: NSRect {
        let width = CGFloat(self.controller.config.pet.size)
        return NSRect(
            x: (self.bounds.width - width) / 2,
            y: 0,
            width: width,
            height: self.bounds.height)
    }
}
