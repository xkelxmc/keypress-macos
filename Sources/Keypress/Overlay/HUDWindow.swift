import AppKit
import KeypressCore
import SwiftUI

enum HUDKind: Sendable {
    case positive
    case negative
    case mode
    case position
    case privacy

    var symbolName: String {
        switch self {
        case .positive: "checkmark.circle.fill"
        case .negative: "power.circle.fill"
        case .mode: "keyboard.fill"
        case .position: "arrow.up.and.down.and.arrow.left.and.right"
        case .privacy: "lock.shield.fill"
        }
    }
}

private struct HUDPresentation: Equatable {
    let sequence: UInt64
    let text: String
    let shortcut: String?
    let kind: HUDKind
    let palette: HUDPalette

    static func == (lhs: HUDPresentation, rhs: HUDPresentation) -> Bool {
        lhs.sequence == rhs.sequence
    }
}

@MainActor
@Observable
private final class HUDPresentationState {
    var current: HUDPresentation?
}

@MainActor
final class HUDWindow: NSPanel {
    private static let windowSize = NSSize(width: 380, height: 104)

    private let presentationState = HUDPresentationState()
    private var sequence: UInt64 = 0
    private var hideTask: Task<Void, Never>?

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = true
        self.hasShadow = false
        self.collectionBehavior = [
            .canJoinAllApplications,
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]
        self.canBecomeKey = false
        self.canBecomeMain = false

        let rootView = HUDContentView(state: self.presentationState)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = self.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        self.contentView?.addSubview(hostingView)
    }

    func show(
        text: String,
        shortcut: String? = nil,
        kind: HUDKind,
        palette: HUDPalette,
        on screen: NSScreen?,
        near anchorFrame: NSRect? = nil,
        duration: TimeInterval = 1.6)
    {
        self.hideTask?.cancel()
        self.sequence &+= 1
        self.presentationState.current = HUDPresentation(
            sequence: self.sequence,
            text: text,
            shortcut: shortcut,
            kind: kind,
            palette: palette)

        self.position(on: screen ?? NSScreen.main, near: anchorFrame)
        self.alphaValue = 1
        self.orderFrontRegardless()

        self.hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            self.presentationState.current = nil
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self.orderOut(nil)
        }
    }

    func hide() {
        self.hideTask?.cancel()
        self.hideTask = nil
        self.presentationState.current = nil
        self.orderOut(nil)
    }

    private func position(on screen: NSScreen?, near anchorFrame: NSRect?) {
        guard let screen else { return }
        let visibleFrame = screen.visibleFrame
        let size = Self.windowSize
        let gap: CGFloat = 12

        let origin: NSPoint
        if let anchorFrame {
            let centeredX = anchorFrame.midX - size.width / 2
            let aboveY = anchorFrame.maxY + gap
            let belowY = anchorFrame.minY - size.height - gap
            let y = aboveY + size.height <= visibleFrame.maxY ? aboveY : belowY
            origin = NSPoint(x: centeredX, y: y)
        } else {
            origin = NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.maxY - size.height - 28)
        }

        self.setFrameOrigin(NSPoint(
            x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)))
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

private struct HUDContentView: View {
    @Bindable var state: HUDPresentationState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let presentation = self.state.current {
                HStack(spacing: 12) {
                    Image(systemName: presentation.kind.symbolName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(presentation.palette.accentColor.color)
                        .frame(width: 30, height: 30)
                        .background(presentation.palette.accentColor.color.opacity(0.14), in: Circle())

                    Text(presentation.text)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(presentation.palette.textColor.color)
                        .lineLimit(1)

                    if let shortcut = presentation.shortcut, !shortcut.isEmpty {
                        Text(shortcut)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(presentation.palette.textColor.color.opacity(0.72))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(presentation.palette.textColor.color.opacity(0.1), in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    presentation.palette.backgroundColor.color,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.13), lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
                .transition(
                    self.reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.94)))
                .id(presentation.sequence)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.18), value: self.state.current)
    }
}
