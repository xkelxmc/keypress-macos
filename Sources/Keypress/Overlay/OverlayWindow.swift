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

private let initialOverlayWindowSize = NSSize(
    width: 600 + overlayShadowInset * 2,
    height: 120 + overlayShadowInset * 2)

/// Transparent, click-through window for displaying key visualization.
@MainActor
final class OverlayWindow: NSPanel {
    // MARK: - Properties

    private let config: KeypressConfig
    private let layoutState = OverlayLayoutState()
    private var contentHostingView: NSHostingView<AnyView>?
    private var targetScreen: NSScreen?
    private var lastMeasuredContentSize = CGSize.zero

    var visibleContentFrameDidChange: (() -> Void)?

    var visibleContentFrame: NSRect? {
        guard self.lastMeasuredContentSize != .zero else { return nil }
        return self.frame.insetBy(dx: overlayShadowInset, dy: overlayShadowInset)
    }

    // MARK: - Initialization (History mode)

    init(keyState: KeyState, config: KeypressConfig) {
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
                    KeyVisualizationView(
                        keyState: keyState,
                        config: config,
                        appliesSizeScale: false)),
                config: config,
                layoutState: self.layoutState,
                onContentSizeChange: { [weak self] size in
                    self?.updateContentSize(size)
                }))
        self.updatePosition()
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
                        config: config,
                        appliesSizeScale: false)),
                config: config,
                layoutState: self.layoutState,
                onContentSizeChange: { [weak self] size in
                    self?.updateContentSize(size)
                }))
        self.updatePosition()
    }

    // MARK: - Initialization (Stacked History)

    init(stackedHistoryState: StackedHistoryState, config: KeypressConfig) {
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
                    StackedHistoryVisualizationView(
                        keyState: stackedHistoryState,
                        config: config,
                        layoutState: self.layoutState,
                        appliesSizeScale: false)),
                config: config,
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

        let screenFrame = targetScreen.visibleFrame
        let windowSize = self.frame.size
        let placement = self.placement(on: targetScreen)
        let contentAnchor = OverlayContentAnchor(placement)
        if self.layoutState.anchor != contentAnchor {
            self.layoutState.anchor = contentAnchor
        }
        let stackedHistoryLayout = StackedHistoryLayout(placement)
        if self.layoutState.stackedHistoryLayout != stackedHistoryLayout {
            self.layoutState.stackedHistoryLayout = stackedHistoryLayout
        }

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

        let finalOrigin = self.clampedOrigin(origin, windowSize: windowSize, screenFrame: screenFrame)
        self.setFrameOrigin(finalOrigin)
    }

    /// Resizes the panel to the SwiftUI view's ideal size, then reapplies its
    /// screen-relative placement so anchored content does not drift as it grows.
    private func updateContentSize(_ measuredSize: CGSize) {
        guard measuredSize.width.isFinite,
              measuredSize.height.isFinite,
              measuredSize.width > 0,
              measuredSize.height > 0
        else {
            return
        }
        self.lastMeasuredContentSize = measuredSize

        let screen = self.targetScreen ?? NSScreen.main
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
        let newSize = NSSize(
            width: min(maximumSize.width, max(overlayShadowInset * 2 + 1, ceil(scaledSize.width))),
            height: min(maximumSize.height, max(overlayShadowInset * 2 + 1, ceil(scaledSize.height))))

        guard abs(self.frame.width - newSize.width) >= 0.5 ||
            abs(self.frame.height - newSize.height) >= 0.5
        else {
            return
        }

        self.setContentSize(newSize)
        self.updatePosition(on: screen)
        self.visibleContentFrameDidChange?()
    }

    private func placement(on screen: NSScreen) -> DisplayPlacement {
        ConnectedDisplays.id(for: screen).map {
            self.config.displays.placement(for: $0)
        } ?? .anchor(
            position: self.config.position,
            horizontalOffset: Double(self.config.horizontalOffset),
            verticalOffset: Double(self.config.verticalOffset))
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

    func refreshContentSize() {
        guard self.lastMeasuredContentSize != .zero else { return }
        self.updateContentSize(self.lastMeasuredContentSize)
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
        if let contentHostingView {
            contentHostingView.needsLayout = true
            contentHostingView.layoutSubtreeIfNeeded()
        }
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
}

/// Adds the shadow-safe inset around the keyboard visualization.
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
