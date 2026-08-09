import AppKit
import KeypressCore
import SwiftUI

// MARK: - Metrics

/// Slack reserved on every side of the content inside the window. SwiftUI draws
/// shadows outside a view's layout bounds and the window edge clips them, so the
/// content is inset and the window origin compensates for it — the visible
/// content ends up exactly where it would be without the inset.
/// Sized for the frame drop shadow (28pt) at the largest overlay scale (1.25).
///
/// It is also the only boundary anything animating inside the overlay can be clipped by, so
/// content that moves on its way out has to be gone before it reaches this far.
let overlayShadowInset: CGFloat = 48

private let initialOverlayWindowSize = NSSize(
    width: 600 + overlayShadowInset * 2,
    height: 120 + overlayShadowInset * 2)

/// How long the window stays up after the content empties, so the block's authored exit is
/// never cut off. Owned by the animation, not by the window.
private var overlayExitDuration: Duration {
    .seconds(KeypressTiming.scaled(KeypressTiming.windowExitDelay))
}

/// Transparent, click-through window for displaying key visualization.
@MainActor
final class OverlayWindow: NSPanel {
    // MARK: - Properties

    private let config: KeypressConfig
    private let layoutState = OverlayLayoutState()
    private var contentHostingView: NSHostingView<AnyView>?
    private var targetScreen: NSScreen?
    private var lastMeasuredContentSize = CGSize.zero

    /// Window size a shrink is waiting to apply, held back until the content settles.
    private var pendingWindowSize: NSSize?
    private var settleTask: Task<Void, Never>?

    /// True from the moment a graceful hide starts until the window is ordered out. The
    /// frame is untouchable for that whole stretch: the exit is content animating inside a
    /// window that does not move.
    private var isHiding = false
    private var hideTask: Task<Void, Never>?

    /// Nil in single-window modes; otherwise which zone this window carries, and therefore
    /// which stored placement positions it.
    private var overlayZone: OverlayZone?

    var visibleContentFrameDidChange: (() -> Void)?

    var visibleContentFrame: NSRect? {
        guard self.lastMeasuredContentSize != .zero else { return nil }
        return self.frame.insetBy(dx: overlayShadowInset, dy: overlayShadowInset)
    }

    // MARK: - Initialization (Single mode)

    init(singleKeyState: SingleKeyState, config: KeypressConfig) {
        self.config = config

        super.init(
            contentRect: NSRect(origin: .zero, size: initialOverlayWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        self.configureWindow()
        self.setupContentView(
            OverlayContainerView(
                keysView: AnyView(
                    SingleKeyVisualizationView(
                        keyState: singleKeyState,
                        config: config)),
                config: config,
                layoutState: self.layoutState,
                onContentSizeChange: { [weak self] size in
                    self?.updateContentSize(size)
                }))
        self.updatePosition()
    }

    // MARK: - Initialization (Horizontal History)

    init(horizontalHistoryState: HorizontalHistoryState, config: KeypressConfig) {
        self.config = config
        self.overlayZone = .primary

        super.init(
            contentRect: NSRect(origin: .zero, size: initialOverlayWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        self.configureWindow()
        self.setupZoneContent(
            AnyView(HorizontalHistoryRibbonView(state: horizontalHistoryState, config: config)))
    }

    // MARK: - Initialization (Text Echo)

    init(textEchoState: TextEchoState, config: KeypressConfig) {
        self.config = config
        self.overlayZone = .primary

        super.init(
            contentRect: NSRect(origin: .zero, size: initialOverlayWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        self.configureWindow()
        self.setupZoneContent(
            AnyView(TextEchoLinesView(
                state: textEchoState,
                config: config,
                layoutState: self.layoutState)))
    }

    // MARK: - Initialization (Command Zone)

    /// The command zone gets a window of its own in every mode that has one, driven by the one
    /// state those modes share — so both modes' second window really is the same window.
    init(commandZoneState: CommandZoneState, config: KeypressConfig) {
        self.config = config
        self.overlayZone = .commands

        super.init(
            contentRect: NSRect(origin: .zero, size: initialOverlayWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        self.configureWindow()
        self.setupZoneContent(
            AnyView(CommandZoneView(state: commandZoneState, config: config)))
    }

    /// One zone per window, so nothing this window draws can affect the other zone's size or
    /// position.
    private func setupZoneContent(_ zoneView: AnyView) {
        self.setupContentView(
            OverlayContainerView(
                keysView: zoneView,
                config: self.config,
                layoutState: self.layoutState,
                onContentSizeChange: { [weak self] size in
                    self?.updateContentSize(size)
                }))
        self.updatePosition()
    }

    // MARK: - Configuration

    private func configureWindow() {
        // Window level: above everything except screen saver
        self.level = .floating

        // Transparent and click-through
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = true
        self.hasShadow = false

        // Don't show in mission control or app switcher
        self.collectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]

        // Don't become key or main window
        self.canBecomeKey = false
        self.canBecomeMain = false
    }

    private func setupContentView(_ rootView: some View) {
        let hostingView = NSHostingView(rootView: AnyView(rootView))
        hostingView.frame = self.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]

        self.contentView?.addSubview(hostingView)
        self.contentHostingView = hostingView
    }

    // MARK: - Positioning

    /// Updates window position based on current config.
    /// - Parameter screen: The screen to position the overlay on. If nil, uses NSScreen.main.
    func updatePosition(on screen: NSScreen? = nil) {
        guard let targetScreen = screen ?? NSScreen.main else { return }
        self.targetScreen = targetScreen
        self.syncLayoutState(on: targetScreen)
        self.setFrameOrigin(self.origin(for: self.frame.size, on: targetScreen))
    }

    private func syncLayoutState(on screen: NSScreen) {
        let placement = self.placement(on: screen)
        let contentAnchor = OverlayContentAnchor(placement)
        if self.layoutState.anchor != contentAnchor {
            self.layoutState.anchor = contentAnchor
        }
        let stackedHistoryLayout = StackedHistoryLayout(placement)
        if self.layoutState.stackedHistoryLayout != stackedHistoryLayout {
            self.layoutState.stackedHistoryLayout = stackedHistoryLayout
        }
        let textEchoFlow = TextEchoFlow.resolve(placement: placement)
        if self.layoutState.textEchoFlow != textEchoFlow {
            self.layoutState.textEchoFlow = textEchoFlow
        }
    }

    /// Where a window of `windowSize` has to sit for its content to land on the placement.
    ///
    /// The content is aligned to the same corner the placement anchors to, so a window that
    /// is larger than its content still puts the content in the right place — which is what
    /// lets the frame stay frozen while the content shrinks inside it.
    private func origin(for windowSize: NSSize, on screen: NSScreen) -> NSPoint {
        let screenFrame = screen.visibleFrame
        let placement = self.placement(on: screen)

        // Offsets are measured from the screen edge to the visible content, so the
        // shadow inset is added back on whichever side the content is anchored to.
        let inset = overlayShadowInset
        let origin: NSPoint
        switch placement {
        case let .anchor(position, horizontalOffset, verticalOffset):
            let hOffset = CGFloat(horizontalOffset)
            let vOffset = CGFloat(verticalOffset)
            origin = switch position {
            case .topLeft:
                NSPoint(
                    x: screenFrame.minX + hOffset - inset,
                    y: screenFrame.maxY - windowSize.height - vOffset + inset)
            case .topCenter:
                NSPoint(
                    x: screenFrame.midX - windowSize.width / 2,
                    y: screenFrame.maxY - windowSize.height - vOffset + inset)
            case .topRight:
                NSPoint(
                    x: screenFrame.maxX - windowSize.width - hOffset + inset,
                    y: screenFrame.maxY - windowSize.height - vOffset + inset)
            case .centerLeft:
                NSPoint(
                    x: screenFrame.minX + hOffset - inset,
                    y: screenFrame.midY - windowSize.height / 2)
            case .centerRight:
                NSPoint(
                    x: screenFrame.maxX - windowSize.width - hOffset + inset,
                    y: screenFrame.midY - windowSize.height / 2)
            case .bottomLeft:
                NSPoint(
                    x: screenFrame.minX + hOffset - inset,
                    y: screenFrame.minY + vOffset - inset)
            case .bottomCenter:
                NSPoint(
                    x: screenFrame.midX - windowSize.width / 2,
                    y: screenFrame.minY + vOffset - inset)
            case .bottomRight:
                NSPoint(
                    x: screenFrame.maxX - windowSize.width - hOffset + inset,
                    y: screenFrame.minY + vOffset - inset)
            }
        case let .custom(center, _):
            let centerPoint = NSPoint(
                x: screenFrame.minX + CGFloat(center.x) * screenFrame.width,
                y: screenFrame.minY + CGFloat(center.y) * screenFrame.height)
            origin = NSPoint(
                x: centerPoint.x - windowSize.width / 2,
                y: centerPoint.y - windowSize.height / 2)
        }

        return self.clampedOrigin(origin, windowSize: windowSize, screenFrame: screenFrame)
    }

    /// Takes a freshly measured content size and decides what, if anything, the window frame
    /// should do about it.
    ///
    /// This runs once per animation frame while the content moves, so it deliberately does
    /// as little as possible: grow now, shrink later, and nothing at all during the exit.
    private func updateContentSize(_ measuredSize: CGSize) {
        guard measuredSize.width.isFinite,
              measuredSize.height.isFinite,
              measuredSize.width > 0,
              measuredSize.height > 0
        else {
            return
        }
        self.lastMeasuredContentSize = measuredSize

        guard let screen = self.targetScreen ?? NSScreen.main else { return }
        let targetSize = self.windowSize(forContent: measuredSize, on: screen)

        switch WindowFrameSizing.update(
            current: self.frame.size,
            target: targetSize,
            isHiding: self.isHiding)
        {
        case .frozen:
            // The overlay is fading out. Whatever the content does inside the window on its
            // way off screen, the window itself holds still.
            return
        case .grow:
            self.pendingWindowSize = nil
            self.applyWindowSize(targetSize, on: screen)
        case .deferShrink:
            self.pendingWindowSize = targetSize
        case .unchanged:
            self.pendingWindowSize = nil
        }

        self.scheduleSettle()
    }

    /// Applies a held-back shrink and tells the pet where the overlay ended up — both only
    /// once the content has stopped resizing, so neither happens per frame.
    private func scheduleSettle() {
        self.settleTask?.cancel()
        self.settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: KeypressTiming.windowShrinkSettleDelay)
            guard !Task.isCancelled, let self else { return }
            self.settleTask = nil
            self.applyPendingWindowSize()
            self.visibleContentFrameDidChange?()
        }
    }

    private func applyPendingWindowSize() {
        guard let pendingWindowSize = self.pendingWindowSize,
              let screen = self.targetScreen ?? NSScreen.main
        else {
            return
        }
        self.pendingWindowSize = nil
        self.applyWindowSize(pendingWindowSize, on: screen)
    }

    /// Moves and resizes the window in one window-server transaction.
    ///
    /// Sizing and positioning used to be two calls, and because a resize keeps the top-left
    /// corner fixed the window visibly hopped between them on every frame it was applied.
    private func applyWindowSize(_ size: NSSize, on screen: NSScreen) {
        self.syncLayoutState(on: screen)
        let frame = NSRect(origin: self.origin(for: size, on: screen), size: size)
        guard frame != self.frame else { return }
        self.setFrame(frame, display: true)
    }

    /// The window size that fits `contentSize`, with the overlay scaled down if the content
    /// would not otherwise fit the screen.
    private func windowSize(forContent measuredSize: CGSize, on screen: NSScreen?) -> NSSize {
        let maximumSize = screen.map {
            NSSize(
                width: $0.visibleFrame.width + overlayShadowInset * 2,
                height: $0.visibleFrame.height + overlayShadowInset * 2)
        } ?? measuredSize
        let availableContentSize = screen.map(self.availableContentSize(on:))
            ?? CGSize(
                width: max(1, maximumSize.width - overlayShadowInset * 2),
                height: max(1, maximumSize.height - overlayShadowInset * 2))
        let requestedScale = self.config.size.scaleFactor
        let layoutContentSize = CGSize(
            width: max(0, measuredSize.width - overlayShadowInset * 2),
            height: max(0, measuredSize.height - overlayShadowInset * 2))
        let fittedScale = min(
            requestedScale,
            availableContentSize.width > 0 && layoutContentSize.width > 0
                ? availableContentSize.width / layoutContentSize.width
                : requestedScale,
            availableContentSize.height > 0 && layoutContentSize.height > 0
                ? availableContentSize.height / layoutContentSize.height
                : requestedScale)
        if abs(self.layoutState.scale - fittedScale) >= 0.001 {
            self.layoutState.scale = fittedScale
        }
        let scaledSize = CGSize(
            width: layoutContentSize.width * fittedScale + overlayShadowInset * 2,
            height: layoutContentSize.height * fittedScale + overlayShadowInset * 2)
        return NSSize(
            width: min(maximumSize.width, max(overlayShadowInset * 2 + 1, ceil(scaledSize.width))),
            height: min(maximumSize.height, max(overlayShadowInset * 2 + 1, ceil(scaledSize.height))))
    }

    private func placement(on screen: NSScreen) -> DisplayPlacement {
        ConnectedDisplays.id(for: screen).map {
            self.placement(forDisplay: $0)
        } ?? .anchor(
            position: self.config.position,
            horizontalOffset: Double(self.config.horizontalOffset),
            verticalOffset: Double(self.config.verticalOffset))
    }

    /// A detached command zone follows its own stored placement; every other window follows
    /// the display's widget placement.
    private func placement(forDisplay displayID: UUID) -> DisplayPlacement {
        guard self.overlayZone == .commands,
              let commandZonePlacement = self.config.displays.commandZonePlacement(for: displayID)
        else {
            return self.config.displays.placement(for: displayID)
        }
        return commandZonePlacement
    }

    private func availableContentSize(on screen: NSScreen) -> CGSize {
        let frame = screen.visibleFrame
        guard case let .anchor(position, horizontalOffset, verticalOffset) = self.placement(on: screen) else {
            return frame.size
        }

        let reservesHorizontalEdge = switch position {
        case .topLeft, .topRight, .centerLeft, .centerRight, .bottomLeft, .bottomRight:
            true
        case .topCenter, .bottomCenter:
            false
        }
        let reservesVerticalEdge = switch position {
        case .topLeft, .topCenter, .topRight, .bottomLeft, .bottomCenter, .bottomRight:
            true
        case .centerLeft, .centerRight:
            false
        }

        return CGSize(
            width: max(1, frame.width - (reservesHorizontalEdge ? CGFloat(horizontalOffset) : 0)),
            height: max(1, frame.height - (reservesVerticalEdge ? CGFloat(verticalOffset) : 0)))
    }

    /// Re-applies the window frame after a settings change. Deliberate changes are not
    /// animation frames, so this one takes effect at once in either direction.
    func refreshContentSize() {
        guard self.lastMeasuredContentSize != .zero,
              let screen = self.targetScreen ?? NSScreen.main
        else {
            return
        }
        self.pendingWindowSize = nil
        self.applyWindowSize(
            self.windowSize(forContent: self.lastMeasuredContentSize, on: screen),
            on: screen)
        self.visibleContentFrameDidChange?()
    }

    /// Clamps origin so the visible content stays within screen bounds.
    /// The window itself is larger by the shadow inset on every side and is
    /// allowed to hang over the edge by exactly that much.
    private func clampedOrigin(_ origin: NSPoint, windowSize: NSSize, screenFrame: NSRect) -> NSPoint {
        let minX = screenFrame.minX - overlayShadowInset
        let maxX = screenFrame.maxX - windowSize.width + overlayShadowInset
        let minY = screenFrame.minY - overlayShadowInset
        let maxY = screenFrame.maxY - windowSize.height + overlayShadowInset

        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY))
    }

    // MARK: - Visibility

    /// Shows the overlay window, calling off a fade that was already under way.
    func showOverlay() {
        self.cancelGracefulHide()
        if let contentHostingView {
            contentHostingView.needsLayout = true
            contentHostingView.layoutSubtreeIfNeeded()
        }
        self.alphaValue = self.config.opacity
        self.orderFrontRegardless()
    }

    /// Takes the overlay off screen.
    ///
    /// A graceful hide leaves the window up until the content has finished fading, so the
    /// exit is not cut off half-way; every other reason orders out at once.
    func hideOverlay(_ style: OverlayHideStyle = .immediate) {
        switch style {
        case .immediate:
            self.cancelGracefulHide()
            self.orderOut(nil)
        case .graceful:
            self.beginGracefulHide()
        }
    }

    private func beginGracefulHide() {
        guard self.isVisible, !self.isHiding else { return }
        self.isHiding = true
        self.hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: overlayExitDuration)
            guard !Task.isCancelled, let self else { return }
            self.isHiding = false
            self.hideTask = nil
            self.orderOut(nil)
            // The window is off screen now, so the shrink the exit held back is free.
            self.applyPendingWindowSize()
        }
    }

    private func cancelGracefulHide() {
        self.hideTask?.cancel()
        self.hideTask = nil
        self.isHiding = false
    }

    // MARK: - NSPanel Overrides

    override var canBecomeKey: Bool {
        get { false }
        set {}
    }

    override var canBecomeMain: Bool {
        get { false }
        set {}
    }
}

// MARK: - Container View

enum OverlayContentAnchor: Equatable {
    case topLeading
    case top
    case topTrailing
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing

    init(_ placement: DisplayPlacement) {
        switch placement {
        case let .anchor(position, _, _):
            self = switch position {
            case .topLeft: .topLeading
            case .topCenter: .top
            case .topRight: .topTrailing
            case .centerLeft: .leading
            case .centerRight: .trailing
            case .bottomLeft: .bottomLeading
            case .bottomCenter: .bottom
            case .bottomRight: .bottomTrailing
            }
        case .custom:
            self = .center
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        }
    }

    var unitPoint: UnitPoint {
        switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        }
    }
}

@MainActor
final class OverlayLayoutState: ObservableObject {
    @Published var anchor = OverlayContentAnchor.center
    @Published var scale: CGFloat = 1
    @Published var stackedHistoryLayout = StackedHistoryLayout(.defaultPlacement)
    @Published var textEchoFlow = TextEchoFlow.resolve(placement: .defaultPlacement)
}

/// Adds the shadow-safe inset around the keyboard visualization, and owns the overlay size
/// scale for every mode — `layoutState.scale` is the configured size factor after it has
/// been fitted to the screen, so no visualization view scales itself.
@MainActor
private struct OverlayContainerView: View {
    let keysView: AnyView
    let config: KeypressConfig
    @ObservedObject var layoutState: OverlayLayoutState
    let onContentSizeChange: @MainActor (CGSize) -> Void

    var body: some View {
        self.keysView
            .fixedSize()
            .scaleEffect(
                self.layoutState.scale,
                anchor: self.layoutState.anchor.unitPoint)
            .padding(overlayShadowInset)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: OverlayContentSizePreferenceKey.self,
                        value: geometry.size)
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: self.layoutState.anchor.alignment)
            .onPreferenceChange(OverlayContentSizePreferenceKey.self) { size in
                self.onContentSizeChange(size)
            }
    }
}

// MARK: - Dynamic Content Measurement

private struct OverlayContentSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
