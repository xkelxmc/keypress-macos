import AppKit
import KeypressCore
import SwiftUI

enum CursorHaloShape: String, CaseIterable, Sendable {
    case circle
    case squircle
    case square
    case diamond
}

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
    var shape: CursorHaloShape
    var lineStyle: PointerLineStyle
    var decoration: PointerDecoration
    var reactionStyle: PointerReactionStyle
    var size: CGFloat
    var strokeWidth: CGFloat
    var opacity: Double
    var primaryColor: KeypressColor
    var secondaryColor: KeypressColor
    var coreColor: KeypressColor
    var glowRadius: CGFloat
    var glowIntensity: Double
    var motionIntensity: Double
    var staysVisible: Bool
    var idleDelay: TimeInterval

    static let system = CursorHaloStyle(
        settings: PointerSettings(),
        theme: PointerTheme())

    init(settings: PointerSettings, theme: PointerTheme) {
        self.shape = switch theme.shape {
        case .circle: .circle
        case .squircle: .squircle
        case .square: .square
        case .diamond: .diamond
        }
        self.lineStyle = theme.lineStyle
        self.decoration = theme.decoration
        self.reactionStyle = theme.reactionStyle
        self.size = CGFloat(settings.size)
        self.strokeWidth = CGFloat(theme.strokeWidth)
        self.opacity = settings.opacity
        self.primaryColor = KeypressColor(theme.primaryColor)
        self.secondaryColor = KeypressColor(theme.secondaryColor)
        self.coreColor = KeypressColor(theme.coreColor)
        self.glowRadius = CGFloat(theme.glowRadius)
        self.glowIntensity = theme.glowIntensity
        self.motionIntensity = settings.motionIntensity
        self.staysVisible = settings.visibility == .always
        self.idleDelay = settings.visibility == .actionsOnly
            ? settings.idleDelay / 2
            : settings.idleDelay
    }
}

struct KeypressColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ color: KeyColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    var color: Color {
        Color(red: self.red, green: self.green, blue: self.blue, opacity: self.alpha)
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
        let wasAlwaysVisible = self.presentationState.style.staysVisible
        if self.presentationState.style != style {
            self.presentationState.style = style
        }
        self.updatePosition(around: location)
        if style.staysVisible {
            self.idleTask?.cancel()
            self.idleTask = nil
            if !self.isVisible {
                self.orderFrontRegardless()
            }
        } else if wasAlwaysVisible {
            self.scheduleIdleIfNeeded()
        }
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

    private func scheduleIdleIfNeeded() {
        self.lastActivityAt = ProcessInfo.processInfo.systemUptime
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
        HaloMotionProfile(style: self.state.style.reactionStyle)
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

    private var glowColor: Color {
        self.state.reaction == .secondary
            ? self.state.style.secondaryColor.color
            : self.state.style.primaryColor.color
    }

    var body: some View {
        ZStack {
            self.lineArtwork
            self.decoration

            if self.state.reaction == .secondary {
                self.haloShape(
                    color: self.state.style.secondaryColor.color.opacity(0.72),
                    lineWidth: max(1.5, self.state.style.strokeWidth * 0.42),
                    scale: 1.16)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            if self.state.reaction == .middle {
                Circle()
                    .fill(self.state.style.coreColor.color)
                    .frame(width: 8, height: 8)
                    .shadow(color: self.state.style.coreColor.color, radius: 9)
                    .transition(.opacity.combined(with: .scale(scale: 0.4)))
            }

            if self.state.style.reactionStyle == .electric,
               self.state.reaction != .idle
            {
                self.haloShape(
                    color: self.state.style.secondaryColor.color.opacity(0.55),
                    lineWidth: max(1, self.state.style.strokeWidth * 0.5),
                    scale: 1.08 * self.accentScale)
                    .blur(radius: 2)

                HaloElectricArc(
                    color: self.state.style.coreColor.color,
                    lineWidth: max(1, self.state.style.strokeWidth * 0.34))
                    .frame(
                        width: self.state.style.size * 0.88,
                        height: self.state.style.size * 0.88)
                    .transition(.opacity.combined(with: .scale(scale: 0.82)))
            }
        }
        .frame(width: self.state.style.size, height: self.state.style.size)
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

    private var accentScale: CGFloat {
        switch self.state.reaction {
        case .idle, .movement:
            1
        case .primary:
            0.76
        case .secondary:
            1.08
        case .middle:
            0.66
        case .drag:
            0.82
        case .scroll:
            0.9
        }
    }

    private var decorationScale: CGFloat {
        switch self.state.reaction {
        case .idle:
            1
        case .movement:
            self.state.style.reactionStyle == .fluid ? 1.04 : 1
        case .primary:
            0.72
        case .secondary:
            1.12
        case .middle:
            0.58
        case .drag:
            0.78
        case .scroll:
            0.9
        }
    }

    private var decorationRotation: Double {
        guard self.state.style.decoration == .orbit else { return 0 }
        return switch self.state.reaction {
        case .idle:
            24
        case .movement:
            54
        case .primary:
            88
        case .secondary:
            -42
        case .middle:
            120
        case .drag:
            74
        case .scroll:
            -78
        }
    }

    @ViewBuilder
    private var lineArtwork: some View {
        switch self.state.style.lineStyle {
        case .aura:
            self.haloShape(
                color: self.glowColor.opacity(0.18 * self.state.style.glowIntensity),
                lineWidth: self.state.style.strokeWidth * 3.2)
                .blur(radius: max(4, self.state.style.glowRadius * 0.55))

            self.haloShape(
                color: self.glowColor.opacity(0.36 * self.state.style.glowIntensity),
                lineWidth: self.state.style.strokeWidth * 1.8)
                .blur(radius: max(2, self.state.style.glowRadius * 0.22))

            self.haloShape(
                color: self.glowColor,
                lineWidth: self.state.style.strokeWidth)
                .shadow(
                    color: self.glowColor.opacity(self.state.style.glowIntensity),
                    radius: self.state.style.glowRadius)

        case .solid:
            self.haloShape(
                color: self.glowColor,
                lineWidth: self.state.style.strokeWidth)
                .shadow(
                    color: self.glowColor.opacity(self.state.style.glowIntensity),
                    radius: self.state.style.glowRadius)

        case .double:
            self.haloShape(
                color: self.glowColor.opacity(0.2 * self.state.style.glowIntensity),
                lineWidth: self.state.style.strokeWidth * 2.2)
                .blur(radius: max(1, self.state.style.glowRadius * 0.35))

            self.haloShape(
                color: self.glowColor,
                lineWidth: self.state.style.strokeWidth)

            self.haloShape(
                color: self.state.style.secondaryColor.color.opacity(0.86),
                lineWidth: max(1, self.state.style.strokeWidth * 0.55),
                scale: 0.82 * self.accentScale)

        case .segmented:
            self.haloShape(
                color: self.glowColor.opacity(0.22 * self.state.style.glowIntensity),
                lineWidth: self.state.style.strokeWidth * 2)
                .blur(radius: max(1, self.state.style.glowRadius * 0.35))

            self.haloShape(
                color: self.glowColor,
                lineWidth: self.state.style.strokeWidth,
                dash: [
                    self.state.style.strokeWidth * 3,
                    self.state.style.strokeWidth * 2.2,
                ],
                dashPhase: self.state.reaction == .idle
                    ? 0
                    : self.state.style.strokeWidth * 1.35)

            self.haloShape(
                color: self.state.style.secondaryColor.color.opacity(0.82),
                lineWidth: max(1, self.state.style.strokeWidth * 0.45),
                scale: 0.84 * self.accentScale,
                dash: [
                    self.state.style.strokeWidth * 1.5,
                    self.state.style.strokeWidth * 2.6,
                ],
                dashPhase: self.state.style.strokeWidth * 1.2)

        case .neonDepth:
            self.haloShape(
                color: self.state.style.secondaryColor.color.opacity(0.72),
                lineWidth: self.state.style.strokeWidth * 1.45,
                scale: 0.98 * max(0.9, self.accentScale))
                .offset(y: 4)
                .blur(radius: 2.2)

            self.haloShape(
                color: self.glowColor.opacity(0.24 * self.state.style.glowIntensity),
                lineWidth: self.state.style.strokeWidth * 3.6)
                .blur(radius: max(5, self.state.style.glowRadius * 0.58))

            self.haloShape(
                color: self.glowColor,
                lineWidth: self.state.style.strokeWidth)
                .shadow(
                    color: self.glowColor.opacity(self.state.style.glowIntensity),
                    radius: self.state.style.glowRadius)

            self.haloShape(
                color: self.state.style.secondaryColor.color,
                lineWidth: max(1.2, self.state.style.strokeWidth * 0.62),
                scale: 0.82 * self.accentScale)
                .shadow(
                    color: self.state.style.secondaryColor.color.opacity(0.9),
                    radius: self.state.style.glowRadius * 0.5)

            self.haloShape(
                color: self.state.style.coreColor.color.opacity(0.72),
                lineWidth: max(0.75, self.state.style.strokeWidth * 0.22),
                scale: 0.91 * max(0.84, self.accentScale))
        }
    }

    private var decoration: some View {
        Group {
            switch self.state.style.decoration {
            case .none:
                EmptyView()

            case .centerDot:
                Circle()
                    .fill(self.state.style.coreColor.color)
                    .frame(
                        width: max(5, self.state.style.strokeWidth * 1.7),
                        height: max(5, self.state.style.strokeWidth * 1.7))
                    .shadow(
                        color: self.state.style.primaryColor.color.opacity(0.45),
                        radius: 4)

            case .innerRing:
                self.haloShape(
                    color: self.state.style.coreColor.color.opacity(0.7),
                    lineWidth: max(1, self.state.style.strokeWidth * 0.36),
                    scale: 0.58)

            case .crosshair:
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(self.state.style.coreColor.color.opacity(0.88))
                        .frame(
                            width: max(1.5, self.state.style.strokeWidth * 0.7),
                            height: self.state.style.size * 0.12)
                        .offset(y: -self.state.style.size * 0.43)
                        .rotationEffect(.degrees(Double(index) * 90))
                }

            case .cornerBrackets:
                HaloCornerBrackets(
                    color: self.state.style.secondaryColor.color,
                    lineWidth: max(1.5, self.state.style.strokeWidth * 0.62))

            case .orbit:
                ZStack {
                    Circle()
                        .fill(self.state.style.coreColor.color)
                        .frame(width: 5, height: 5)
                        .offset(y: -self.state.style.size * 0.46)
                    Circle()
                        .fill(self.state.style.secondaryColor.color)
                        .frame(width: 5, height: 5)
                        .offset(y: self.state.style.size * 0.46)
                }
            }
        }
        .scaleEffect(self.decorationScale)
        .rotationEffect(.degrees(self.decorationRotation))
    }

    @ViewBuilder
    private func haloShape(
        color: Color,
        lineWidth: CGFloat,
        scale: CGFloat = 1,
        dash: [CGFloat] = [],
        dashPhase: CGFloat = 0) -> some View
    {
        let strokeStyle = StrokeStyle(
            lineWidth: lineWidth,
            lineCap: dash.isEmpty ? .butt : .round,
            lineJoin: .round,
            dash: dash,
            dashPhase: dashPhase)

        switch self.state.style.shape {
        case .circle:
            Circle()
                .stroke(color, style: strokeStyle)
                .scaleEffect(scale)
        case .squircle:
            RoundedRectangle(cornerRadius: self.state.style.size * 0.28, style: .continuous)
                .stroke(color, style: strokeStyle)
                .scaleEffect(scale)
        case .square:
            RoundedRectangle(cornerRadius: self.state.style.size * 0.11, style: .continuous)
                .stroke(color, style: strokeStyle)
                .scaleEffect(scale)
        case .diamond:
            RoundedRectangle(cornerRadius: self.state.style.size * 0.09, style: .continuous)
                .stroke(color, style: strokeStyle)
                .scaleEffect(0.72 * scale)
                .rotationEffect(.degrees(45))
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

private struct HaloCornerBrackets: View {
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let inset = side * 0.08
            let length = side * 0.19
            let maxX = geometry.size.width - inset
            let maxY = geometry.size.height - inset

            Path { path in
                path.move(to: CGPoint(x: inset + length, y: inset))
                path.addLine(to: CGPoint(x: inset, y: inset))
                path.addLine(to: CGPoint(x: inset, y: inset + length))

                path.move(to: CGPoint(x: maxX - length, y: inset))
                path.addLine(to: CGPoint(x: maxX, y: inset))
                path.addLine(to: CGPoint(x: maxX, y: inset + length))

                path.move(to: CGPoint(x: inset, y: maxY - length))
                path.addLine(to: CGPoint(x: inset, y: maxY))
                path.addLine(to: CGPoint(x: inset + length, y: maxY))

                path.move(to: CGPoint(x: maxX, y: maxY - length))
                path.addLine(to: CGPoint(x: maxX, y: maxY))
                path.addLine(to: CGPoint(x: maxX - length, y: maxY))
            }
            .stroke(
                self.color,
                style: StrokeStyle(
                    lineWidth: self.lineWidth,
                    lineCap: .round,
                    lineJoin: .round))
        }
    }
}

private struct HaloElectricArc: View {
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            Path { path in
                path.move(to: CGPoint(x: width * 0.12, y: height * 0.28))
                path.addLine(to: CGPoint(x: width * 0.25, y: height * 0.20))
                path.addLine(to: CGPoint(x: width * 0.31, y: height * 0.28))
                path.addLine(to: CGPoint(x: width * 0.42, y: height * 0.15))

                path.move(to: CGPoint(x: width * 0.70, y: height * 0.80))
                path.addLine(to: CGPoint(x: width * 0.77, y: height * 0.70))
                path.addLine(to: CGPoint(x: width * 0.84, y: height * 0.77))
                path.addLine(to: CGPoint(x: width * 0.91, y: height * 0.64))
            }
            .stroke(
                self.color,
                style: StrokeStyle(
                    lineWidth: self.lineWidth,
                    lineCap: .round,
                    lineJoin: .round))
            .shadow(color: self.color, radius: 4)
        }
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
