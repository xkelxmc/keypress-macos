import AppKit
import KeypressCore
import SwiftUI

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
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.configureWindow()
        self.setupContentView(
            OverlayContainerView(
                keysView: AnyView(KeyVisualizationView(keyState: keyState, config: config)),
                hintState: hintState,
                config: config
            )
        )
        self.updatePosition()
    }

    // MARK: - Initialization (Single mode)

    init(singleKeyState: SingleKeyState, hintState: HintState, config: KeypressConfig) {
        self.config = config

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.configureWindow()
        self.setupContentView(
            OverlayContainerView(
                keysView: AnyView(SingleKeyVisualizationView(keyState: singleKeyState, config: config)),
                hintState: hintState,
                config: config
            )
        )
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

    private func setupContentView<V: View>(_ rootView: V) {
        let hostingView = NSHostingView(rootView: AnyView(rootView))
        hostingView.frame = self.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height] as NSView.AutoresizingMask

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
        let margin: CGFloat = 20

        let origin: NSPoint
        switch self.config.position {
        case .topLeft:
            origin = NSPoint(
                x: screenFrame.minX + margin,
                y: screenFrame.maxY - windowSize.height - margin
            )
        case .topCenter:
            origin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.maxY - windowSize.height - margin
            )
        case .topRight:
            origin = NSPoint(
                x: screenFrame.maxX - windowSize.width - margin,
                y: screenFrame.maxY - windowSize.height - margin
            )
        case .centerLeft:
            origin = NSPoint(
                x: screenFrame.minX + margin,
                y: screenFrame.midY - windowSize.height / 2
            )
        case .centerRight:
            origin = NSPoint(
                x: screenFrame.maxX - windowSize.width - margin,
                y: screenFrame.midY - windowSize.height / 2
            )
        case .bottomLeft:
            origin = NSPoint(
                x: screenFrame.minX + margin,
                y: screenFrame.minY + margin
            )
        case .bottomCenter:
            origin = NSPoint(
                x: screenFrame.midX - windowSize.width / 2,
                y: screenFrame.minY + margin
            )
        case .bottomRight:
            origin = NSPoint(
                x: screenFrame.maxX - windowSize.width - margin,
                y: screenFrame.minY + margin
            )
        }

        self.setFrameOrigin(origin)
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
        set {} // swiftlint:disable:this unused_setter_value
    }

    override var canBecomeMain: Bool {
        get { false }
        set {} // swiftlint:disable:this unused_setter_value
    }
}

// MARK: - Container View

/// Container that holds both keys overlay and hint overlay.
private struct OverlayContainerView: View {
    let keysView: AnyView
    @Bindable var hintState: HintState
    let config: KeypressConfig

    private var hintPosition: HintPosition {
        HintPosition.from(overlayPosition: self.config.position)
    }

    private var isHorizontalLayout: Bool {
        self.hintPosition == .leading || self.hintPosition == .trailing
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
    }

    @ViewBuilder
    private var hintView: some View {
        if let hint = self.hintState.currentHint {
            ToggleHintView(hint: hint, config: self.config)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}
