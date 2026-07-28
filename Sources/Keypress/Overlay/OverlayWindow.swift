import AppKit
import KeypressCore
import SwiftUI

// MARK: - Metrics

/// Slack reserved on every side of the content inside the window. SwiftUI draws
/// shadows outside a view's layout bounds and the window edge clips them, so the
/// content is inset and the window origin compensates for it — the visible
/// content ends up exactly where it would be without the inset.
/// Sized for the frame drop shadow (28pt) at the largest overlay scale (1.25).
private let overlayShadowInset: CGFloat = 48

/// Space available to the content itself, excluding the shadow inset.
private let overlayContentSize = NSSize(width: 600, height: 120)

private let overlayWindowSize = NSSize(
    width: overlayContentSize.width + overlayShadowInset * 2,
    height: overlayContentSize.height + overlayShadowInset * 2)

/// Transparent, click-through window for displaying key visualization.
@MainActor
final class OverlayWindow: NSPanel {
    // MARK: - Properties

    private let config: KeypressConfig
    private var contentHostingView: NSHostingView<AnyView>?

    // MARK: - Initialization (History mode)

    init(keyState: KeyState, hintState: HintState, config: KeypressConfig) {
        self.config = config

        super.init(
            contentRect: NSRect(origin: .zero, size: overlayWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        self.configureWindow()
        self.setupContentView(
            OverlayContainerView(
                keysView: AnyView(KeyVisualizationView(keyState: keyState, config: config)),
                hintState: hintState,
                config: config))
        self.updatePosition()
    }

    // MARK: - Initialization (Single mode)

    init(singleKeyState: SingleKeyState, hintState: HintState, config: KeypressConfig) {
        self.config = config

        super.init(
            contentRect: NSRect(origin: .zero, size: overlayWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        self.configureWindow()
        self.setupContentView(
            OverlayContainerView(
                keysView: AnyView(SingleKeyVisualizationView(keyState: singleKeyState, config: config)),
                hintState: hintState,
                config: config))
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
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

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

        let screenFrame = targetScreen.visibleFrame
        let windowSize = self.frame.size
        let hOffset = self.config.horizontalOffset
        let vOffset = self.config.verticalOffset

        // Offsets are measured from the screen edge to the visible content, so the
        // shadow inset is added back on whichever side the content is anchored to.
        let inset = overlayShadowInset
        let origin = switch self.config.position {
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

        let finalOrigin = self.clampedOrigin(origin, windowSize: windowSize, screenFrame: screenFrame)
        self.setFrameOrigin(finalOrigin)
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

    /// Shows the overlay window.
    func showOverlay() {
        self.alphaValue = self.config.opacity
        self.orderFrontRegardless()
    }

    /// Hides the overlay window.
    func hideOverlay() {
        self.orderOut(nil)
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

/// Container that holds both keys overlay and hint overlay.
private struct OverlayContainerView: View {
    let keysView: AnyView
    @Bindable var hintState: HintState
    @Bindable var config: KeypressConfig

    private var hintPosition: HintPosition {
        HintPosition.from(overlayPosition: self.config.position)
    }

    private var isHorizontalLayout: Bool {
        self.hintPosition == .leading || self.hintPosition == .trailing
    }

    /// Alignment based on overlay position (so content sticks to the correct edge).
    private var contentAlignment: Alignment {
        switch self.config.position {
        case .topLeft: .topLeading
        case .topCenter: .top
        case .topRight: .topTrailing
        case .centerLeft: .leading
        case .centerRight: .trailing
        case .bottomLeft: .bottomLeading
        case .bottomCenter: .bottom
        case .bottomRight: .bottomTrailing
        }
    }

    var body: some View {
        Group {
            if self.isHorizontalLayout {
                HStack(spacing: 12) {
                    if self.hintPosition == .leading {
                        self.hintView
                    }
                    self.keysView
                    if self.hintPosition == .trailing {
                        self.hintView
                    }
                }
            } else {
                VStack(spacing: 12) {
                    if self.hintPosition == .top {
                        self.hintView
                    }
                    self.keysView
                    if self.hintPosition == .bottom {
                        self.hintView
                    }
                }
            }
        }
        .padding(overlayShadowInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: self.contentAlignment)
    }

    @ViewBuilder
    private var hintView: some View {
        if let hint = self.hintState.currentHint {
            ToggleHintView(hint: hint, config: self.config)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}
