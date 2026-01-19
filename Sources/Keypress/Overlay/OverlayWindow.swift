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

    init(keyState: KeyState, config: KeypressConfig) {
        self.config = config

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.configureWindow()
        self.setupContentView(KeyVisualizationView(keyState: keyState, config: config))
        self.updatePosition()
    }

    // MARK: - Initialization (Single mode)

    init(singleKeyState: SingleKeyState, config: KeypressConfig) {
        self.config = config

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.configureWindow()
        self.setupContentView(SingleKeyVisualizationView(keyState: singleKeyState, config: config))
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
    func updatePosition() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
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
