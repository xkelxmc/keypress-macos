import AppKit
import KeypressCore
import SwiftUI

enum CursorButton: Hashable, Sendable {
    case primary
    case secondary
    case middle
}

enum CursorAction: Sendable {
    case movement(velocity: CGSize)
    case buttonDown(CursorButton)
    case buttonUp(CursorButton)
    case drag(velocity: CGSize, button: CursorButton)
    case scroll(delta: CGSize)
}

struct CursorHaloStyle: Equatable, Sendable {
    var theme: PointerTheme
    var size: CGFloat
    var opacity: Double
    var motionIntensity: Double
    var visibility: PointerVisibility
    var idleDelay: TimeInterval

    var staysVisible: Bool {
        self.visibility == .always
    }

    static let system = CursorHaloStyle(
        settings: PointerSettings(),
        theme: PointerTheme())

    init(settings: PointerSettings, theme: PointerTheme) {
        self.theme = theme
        self.size = CGFloat(settings.size)
        self.opacity = settings.opacity
        self.motionIntensity = settings.motionIntensity
        self.visibility = settings.visibility
        self.idleDelay = settings.visibility == .actionsOnly
            ? settings.idleDelay / 2
            : settings.idleDelay
    }
}

private enum HaloReaction: Equatable {
    case idle
    case movement(CGSize)
    case primary
    case secondary
    case middle
    case drag(CGSize)
    case scroll(CGSize)

    var artworkReaction: PointerArtworkReaction {
        switch self {
        case .idle: .idle
        case .movement: .movement
        case .primary: .primary
        case .secondary: .secondary
        case .middle: .middle
        case .drag: .drag
        case .scroll: .scroll
        }
    }
}

@MainActor
@Observable
private final class CursorHaloPresentationState {
    var style = CursorHaloStyle.system
    var reaction = HaloReaction.idle
    var sequence: UInt64 = 0
}

@MainActor
final class CursorHaloWindow: NSPanel {
    private static let canvasSize = NSSize(width: 320, height: 320)
    private static let visualMotionInterval: TimeInterval = 1 / 60

    private let presentationState = CursorHaloPresentationState()
    private var pressedButtons: Set<CursorButton> = []
    private var idleTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var lastActivityAt = ProcessInfo.processInfo.systemUptime
    private var lastContinuousReactionAt = ProcessInfo.processInfo.systemUptime
    private var lastVisualMotionAt: TimeInterval = 0

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = true
        self.hasShadow = false
        self.animationBehavior = .none
        self.collectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.canBecomeKey = false
        self.canBecomeMain = false

        let hostingView = NSHostingView(rootView: CursorHaloView(state: self.presentationState))
        hostingView.frame = self.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        self.contentView?.addSubview(hostingView)
    }

    func handle(_ action: CursorAction, location: NSPoint, style: CursorHaloStyle) {
        if self.presentationState.style != style {
            self.presentationState.style = style
        }
        self.updatePosition(around: location)
        if self.apply(action) {
            self.presentationState.sequence &+= 1
        }
        if !self.isVisible {
            self.orderFrontRegardless()
        }
        self.scheduleIdleIfNeeded()
    }

    func update(style: CursorHaloStyle, location: NSPoint) {
        let previousStyle = self.presentationState.style
        if self.presentationState.style != style {
            self.presentationState.style = style
        }
        self.updatePosition(around: location)

        guard previousStyle.visibility != style.visibility
            || previousStyle.idleDelay != style.idleDelay
        else {
            if style.staysVisible, !self.isVisible {
                self.orderFrontRegardless()
            }
            return
        }

        self.idleTask?.cancel()
        self.idleTask = nil

        switch style.visibility {
        case .always:
            if !self.isVisible {
                self.orderFrontRegardless()
            }
        case .actionsOnly:
            if previousStyle.visibility != .actionsOnly {
                if self.pressedButtons.isEmpty {
                    self.hideImmediately()
                } else if !self.isVisible {
                    self.orderFrontRegardless()
                }
            } else if self.isVisible {
                let elapsed = ProcessInfo.processInfo.systemUptime - self.lastActivityAt
                if self.pressedButtons.isEmpty, elapsed >= style.idleDelay {
                    self.hideImmediately()
                } else {
                    self.scheduleIdleIfNeeded(recordsActivity: false)
                }
            }
        case .onActivity:
            guard self.isVisible else { return }
            let elapsed = ProcessInfo.processInfo.systemUptime - self.lastActivityAt
            if self.pressedButtons.isEmpty, elapsed >= style.idleDelay {
                self.hideImmediately()
            } else {
                self.scheduleIdleIfNeeded(recordsActivity: false)
            }
        }
    }

    private func hideImmediately() {
        self.idleTask?.cancel()
        self.idleTask = nil
        if self.pressedButtons.isEmpty {
            self.presentationState.reaction = .idle
        }
        self.orderOut(nil)
    }

    func clear() {
        self.idleTask?.cancel()
        self.settleTask?.cancel()
        self.idleTask = nil
        self.settleTask = nil
        self.pressedButtons.removeAll()
        self.lastVisualMotionAt = 0
        self.presentationState.reaction = .idle
        self.orderOut(nil)
    }

    @discardableResult
    private func apply(_ action: CursorAction) -> Bool {
        switch action {
        case let .movement(velocity):
            if self.pressedButtons.contains(.primary) {
                self.updateContinuousReaction(.drag(velocity))
            } else {
                self.updateContinuousReaction(.movement(velocity))
                self.scheduleSettle(after: 0.048)
            }
            return false

        case let .buttonDown(button):
            self.settleTask?.cancel()
            self.settleTask = nil
            self.pressedButtons.insert(button)
            self.presentationState.reaction = switch button {
            case .primary: .primary
            case .secondary: .secondary
            case .middle: .middle
            }
            return true

        case let .buttonUp(button):
            self.settleTask?.cancel()
            self.settleTask = nil
            self.pressedButtons.remove(button)
            if let remainingButton = self.pressedButtons.first {
                self.presentationState.reaction = self.reaction(for: remainingButton)
            } else {
                self.presentationState.reaction = .idle
            }
            return true

        case let .drag(velocity, button):
            self.pressedButtons.insert(button)
            self.updateContinuousReaction(.drag(velocity))
            return false

        case let .scroll(delta):
            self.presentationState.reaction = .scroll(delta)
            self.scheduleSettle(after: 0.09)
            return true
        }
    }

    private func reaction(for button: CursorButton) -> HaloReaction {
        switch button {
        case .primary: .primary
        case .secondary: .secondary
        case .middle: .middle
        }
    }

    private func updateContinuousReaction(_ reaction: HaloReaction) {
        let now = ProcessInfo.processInfo.systemUptime
        self.lastContinuousReactionAt = now
        guard now - self.lastVisualMotionAt >= Self.visualMotionInterval else { return }
        self.lastVisualMotionAt = now
        self.presentationState.reaction = reaction
    }

    private func scheduleSettle(after delay: TimeInterval) {
        self.lastContinuousReactionAt = ProcessInfo.processInfo.systemUptime
        guard self.settleTask == nil else { return }

        self.settleTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let elapsed = ProcessInfo.processInfo.systemUptime - self.lastContinuousReactionAt
                if elapsed < delay {
                    try? await Task.sleep(for: .seconds(delay - elapsed))
                    continue
                }
                guard self.pressedButtons.isEmpty else {
                    self.settleTask = nil
                    return
                }
                self.presentationState.reaction = .idle
                self.settleTask = nil
                return
            }
        }
    }

    private func scheduleIdleIfNeeded(recordsActivity: Bool = true) {
        if recordsActivity {
            self.lastActivityAt = ProcessInfo.processInfo.systemUptime
        }
        guard !self.presentationState.style.staysVisible else { return }
        guard self.idleTask == nil else { return }

        self.idleTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let delay = self.presentationState.style.idleDelay
                let elapsed = ProcessInfo.processInfo.systemUptime - self.lastActivityAt
                if elapsed < delay {
                    try? await Task.sleep(for: .seconds(delay - elapsed))
                    continue
                }
                if !self.pressedButtons.isEmpty {
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }
                self.presentationState.reaction = .idle
                self.orderOut(nil)
                self.idleTask = nil
                return
            }
        }
    }

    private func updatePosition(around location: NSPoint) {
        let origin = NSPoint(
            x: location.x - Self.canvasSize.width / 2,
            y: location.y - Self.canvasSize.height / 2)
        guard abs(self.frame.minX - origin.x) >= 0.5
            || abs(self.frame.minY - origin.y) >= 0.5
        else {
            return
        }
        self.setFrameOrigin(origin)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    override var canBecomeKey: Bool {
        get { false }
        set {}
    }

    override var canBecomeMain: Bool {
        get { false }
        set {}
    }
}

private struct CursorHaloView: View {
    let state: CursorHaloPresentationState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var intensity: CGFloat {
        CGFloat(self.state.style.motionIntensity)
    }

    private var motionProfile: HaloMotionProfile {
        HaloMotionProfile(style: self.state.style.theme.reactionStyle)
    }

    private var transform: HaloTransform {
        guard !self.reduceMotion else {
            return HaloTransform(
                scaleX: self.state.reaction == .idle ? 1 : 0.94,
                scaleY: self.state.reaction == .idle ? 1 : 0.94,
                rotation: 0,
                xTilt: 0,
                yTilt: 0)
        }

        switch self.state.reaction {
        case .idle:
            return .identity
        case let .movement(velocity):
            return self.directionalTransform(
                velocity,
                stretch: self.motionProfile.movementStretch)
        case .primary:
            return HaloTransform(
                scaleX: self.motionProfile.primaryScale.width,
                scaleY: self.motionProfile.primaryScale.height,
                rotation: self.motionProfile.primaryRotation,
                xTilt: self.motionProfile.primaryTilt,
                yTilt: 0)
        case .secondary:
            return HaloTransform(
                scaleX: self.motionProfile.secondaryScale,
                scaleY: self.motionProfile.secondaryScale,
                rotation: self.motionProfile.secondaryRotation,
                xTilt: self.motionProfile.secondaryTilt,
                yTilt: 0)
        case .middle:
            return HaloTransform(
                scaleX: self.motionProfile.middleScale,
                scaleY: self.motionProfile.middleScale,
                rotation: 0,
                xTilt: 0,
                yTilt: 0)
        case let .drag(velocity):
            let directional = self.directionalTransform(
                velocity,
                stretch: self.motionProfile.dragStretch)
            return HaloTransform(
                scaleX: directional.scaleX,
                scaleY: directional.scaleY * self.motionProfile.dragCompression,
                rotation: directional.rotation,
                xTilt: self.motionProfile.dragTilt,
                yTilt: directional.yTilt)
        case let .scroll(delta):
            let horizontal = abs(delta.width) > abs(delta.height)
            let amount = min(
                max(abs(horizontal ? delta.width : delta.height) / 80, 0.08),
                0.28) * self.intensity * self.motionProfile.scrollCompression
            let compressedScale = max(0.66, 1 - amount)
            return HaloTransform(
                scaleX: horizontal ? compressedScale : 1 + self.motionProfile.scrollExpansion,
                scaleY: horizontal ? 1 + self.motionProfile.scrollExpansion : compressedScale,
                rotation: 0,
                xTilt: 0,
                yTilt: 0)
        }
    }

    var body: some View {
        PointerThemeArtwork(
            theme: self.state.style.theme,
            size: self.state.style.size,
            reaction: self.state.reaction.artworkReaction)
            .scaleEffect(x: self.transform.scaleX, y: self.transform.scaleY)
            .rotationEffect(.degrees(self.transform.rotation))
            .rotation3DEffect(.degrees(self.transform.xTilt), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
            .rotation3DEffect(.degrees(self.transform.yTilt), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
            .opacity(self.state.style.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(
                self.continuousReaction
                    ? nil
                    : self.reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(
                        response: self.motionProfile.springResponse,
                        dampingFraction: self.motionProfile.springDamping),
                value: self.state.sequence)
            .animation(
                self.continuousReaction
                    ? nil
                    : .spring(
                        response: self.motionProfile.springResponse + 0.04,
                        dampingFraction: self.motionProfile.springDamping),
                value: self.state.reaction)
    }

    private var continuousReaction: Bool {
        switch self.state.reaction {
        case .movement, .drag:
            true
        case .idle, .primary, .secondary, .middle, .scroll:
            false
        }
    }

    private func directionalTransform(_ velocity: CGSize, stretch: CGFloat) -> HaloTransform {
        let magnitude = min(hypot(velocity.width, velocity.height) / 900, 1) * self.intensity
        guard magnitude > 0.001 else { return .identity }

        let horizontal = abs(velocity.width) >= abs(velocity.height)
        let rotationLimit = 10 * self.motionProfile.rotationScale
        let rotation = min(
            max(velocity.width / 80 * self.motionProfile.rotationScale, -rotationLimit),
            rotationLimit) * self.intensity
        return HaloTransform(
            scaleX: horizontal ? 1 + magnitude * stretch : 1 - magnitude * stretch * 0.4,
            scaleY: horizontal ? 1 - magnitude * stretch * 0.4 : 1 + magnitude * stretch,
            rotation: rotation,
            xTilt: min(
                max(-velocity.height / 100 * self.motionProfile.tiltScale, -8),
                8) * self.intensity,
            yTilt: min(
                max(velocity.width / 100 * self.motionProfile.tiltScale, -8),
                8) * self.intensity)
    }
}

struct HaloMotionProfile {
    let movementStretch: CGFloat
    let dragStretch: CGFloat
    let primaryScale: CGSize
    let primaryRotation: Double
    let primaryTilt: Double
    let secondaryScale: CGFloat
    let secondaryRotation: Double
    let secondaryTilt: Double
    let middleScale: CGFloat
    let dragCompression: CGFloat
    let dragTilt: Double
    let scrollCompression: CGFloat
    let scrollExpansion: CGFloat
    let rotationScale: CGFloat
    let tiltScale: CGFloat
    let springResponse: Double
    let springDamping: Double

    // swiftlint:disable:next function_body_length
    init(style: PointerReactionStyle) {
        switch style {
        case .elastic:
            self.init(
                movementStretch: 0.035,
                dragStretch: 0.08,
                primaryScale: CGSize(width: 1.02, height: 0.79),
                primaryRotation: 0,
                primaryTilt: 10,
                secondaryScale: 1.12,
                secondaryRotation: 0,
                secondaryTilt: -5,
                middleScale: 0.82,
                dragCompression: 0.86,
                dragTilt: 8,
                scrollCompression: 1,
                scrollExpansion: 0.04,
                rotationScale: 1,
                tiltScale: 1,
                springResponse: 0.22,
                springDamping: 0.68)

        case .pulse:
            self.init(
                movementStretch: 0.018,
                dragStretch: 0.05,
                primaryScale: CGSize(width: 0.88, height: 0.88),
                primaryRotation: 0,
                primaryTilt: 0,
                secondaryScale: 1.16,
                secondaryRotation: 0,
                secondaryTilt: 0,
                middleScale: 0.76,
                dragCompression: 0.92,
                dragTilt: 0,
                scrollCompression: 1.1,
                scrollExpansion: 0.08,
                rotationScale: 0,
                tiltScale: 0,
                springResponse: 0.2,
                springDamping: 0.76)

        case .stepped:
            self.init(
                movementStretch: 0.008,
                dragStretch: 0.035,
                primaryScale: CGSize(width: 0.9, height: 0.9),
                primaryRotation: 0,
                primaryTilt: 0,
                secondaryScale: 1.08,
                secondaryRotation: 0,
                secondaryTilt: 0,
                middleScale: 0.84,
                dragCompression: 0.9,
                dragTilt: 0,
                scrollCompression: 0.75,
                scrollExpansion: 0,
                rotationScale: 0,
                tiltScale: 0,
                springResponse: 0.11,
                springDamping: 1)

        case .mechanical:
            self.init(
                movementStretch: 0.025,
                dragStretch: 0.065,
                primaryScale: CGSize(width: 1.02, height: 0.72),
                primaryRotation: 0,
                primaryTilt: 14,
                secondaryScale: 1.08,
                secondaryRotation: 0,
                secondaryTilt: -8,
                middleScale: 0.8,
                dragCompression: 0.74,
                dragTilt: 12,
                scrollCompression: 0.9,
                scrollExpansion: 0.025,
                rotationScale: 0.5,
                tiltScale: 1.15,
                springResponse: 0.18,
                springDamping: 0.78)

        case .fluid:
            self.init(
                movementStretch: 0.085,
                dragStretch: 0.14,
                primaryScale: CGSize(width: 0.94, height: 0.83),
                primaryRotation: 0,
                primaryTilt: 6,
                secondaryScale: 1.1,
                secondaryRotation: 2,
                secondaryTilt: -4,
                middleScale: 0.76,
                dragCompression: 0.84,
                dragTilt: 5,
                scrollCompression: 1.05,
                scrollExpansion: 0.07,
                rotationScale: 1.4,
                tiltScale: 0.8,
                springResponse: 0.28,
                springDamping: 0.58)

        case .subtle:
            self.init(
                movementStretch: 0.012,
                dragStretch: 0.025,
                primaryScale: CGSize(width: 0.95, height: 0.92),
                primaryRotation: 0,
                primaryTilt: 0,
                secondaryScale: 1.04,
                secondaryRotation: 0,
                secondaryTilt: 0,
                middleScale: 0.9,
                dragCompression: 0.94,
                dragTilt: 0,
                scrollCompression: 0.55,
                scrollExpansion: 0.015,
                rotationScale: 0.2,
                tiltScale: 0.15,
                springResponse: 0.16,
                springDamping: 0.88)

        case .tactical:
            self.init(
                movementStretch: 0.025,
                dragStretch: 0.09,
                primaryScale: CGSize(width: 0.9, height: 0.82),
                primaryRotation: -2,
                primaryTilt: 4,
                secondaryScale: 1.14,
                secondaryRotation: 3,
                secondaryTilt: -3,
                middleScale: 0.75,
                dragCompression: 0.8,
                dragTilt: 3,
                scrollCompression: 1.15,
                scrollExpansion: 0.02,
                rotationScale: 1.5,
                tiltScale: 0.55,
                springResponse: 0.14,
                springDamping: 0.72)

        case .electric:
            self.init(
                movementStretch: 0.065,
                dragStretch: 0.16,
                primaryScale: CGSize(width: 0.92, height: 0.72),
                primaryRotation: -2.5,
                primaryTilt: 12,
                secondaryScale: 1.2,
                secondaryRotation: 4,
                secondaryTilt: -10,
                middleScale: 0.7,
                dragCompression: 0.76,
                dragTilt: 10,
                scrollCompression: 1.3,
                scrollExpansion: 0.1,
                rotationScale: 1.8,
                tiltScale: 1.25,
                springResponse: 0.17,
                springDamping: 0.54)
        }
    }

    private init(
        movementStretch: CGFloat,
        dragStretch: CGFloat,
        primaryScale: CGSize,
        primaryRotation: Double,
        primaryTilt: Double,
        secondaryScale: CGFloat,
        secondaryRotation: Double,
        secondaryTilt: Double,
        middleScale: CGFloat,
        dragCompression: CGFloat,
        dragTilt: Double,
        scrollCompression: CGFloat,
        scrollExpansion: CGFloat,
        rotationScale: CGFloat,
        tiltScale: CGFloat,
        springResponse: Double,
        springDamping: Double)
    {
        self.movementStretch = movementStretch
        self.dragStretch = dragStretch
        self.primaryScale = primaryScale
        self.primaryRotation = primaryRotation
        self.primaryTilt = primaryTilt
        self.secondaryScale = secondaryScale
        self.secondaryRotation = secondaryRotation
        self.secondaryTilt = secondaryTilt
        self.middleScale = middleScale
        self.dragCompression = dragCompression
        self.dragTilt = dragTilt
        self.scrollCompression = scrollCompression
        self.scrollExpansion = scrollExpansion
        self.rotationScale = rotationScale
        self.tiltScale = tiltScale
        self.springResponse = springResponse
        self.springDamping = springDamping
    }
}

private struct HaloTransform {
    let scaleX: CGFloat
    let scaleY: CGFloat
    let rotation: Double
    let xTilt: Double
    let yTilt: Double

    static let identity = HaloTransform(scaleX: 1, scaleY: 1, rotation: 0, xTilt: 0, yTilt: 0)
}
