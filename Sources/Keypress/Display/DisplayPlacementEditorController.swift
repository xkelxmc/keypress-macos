import AppKit
import KeypressCore
import SwiftUI

extension Notification.Name {
    static let displayPlacementEditorDidOpen = Notification.Name("displayPlacementEditorDidOpen")
    static let displayPlacementEditorDidClose = Notification.Name("displayPlacementEditorDidClose")
    static let displayPlacementEditorDidSave = Notification.Name("displayPlacementEditorDidSave")
}

@MainActor
final class DisplayPlacementEditorController {
    static let shared = DisplayPlacementEditorController()

    private var panel: DisplayPlacementEditorPanel?
    private var screenParametersObserver: NSObjectProtocol?
    private var appDeactivationObserver: NSObjectProtocol?
    private var editingDisplayID: UUID?

    private init() {}

    func show(for displayID: UUID? = nil) {
        self.close()

        guard let display = self.displayForEditing(requestedID: displayID) else { return }

        let config = KeypressConfig.shared
        let displaySettings = config.displays
        let initialPlacement = displaySettings.placement(for: display.id)
        let initialUsesFallback = displaySettings.placements[display.id] == nil
        let resetPlacement = displaySettings.fallbackPlacement
        let panel = DisplayPlacementEditorPanel(
            display: display,
            initialPlacement: initialPlacement,
            initialUsesFallback: initialUsesFallback,
            resetPlacement: resetPlacement,
            config: config,
            onDone: { [weak self] placement, usesFallback in
                if usesFallback {
                    config.displays.removePlacement(for: display.id)
                } else {
                    config.displays.setPlacement(placement, for: display.id)
                }
                NotificationCenter.default.post(name: .displayPlacementEditorDidSave, object: nil)
                self?.close()
            },
            onCancel: { [weak self] in
                self?.close()
            })

        self.panel = panel
        self.editingDisplayID = display.id
        self.startObservingEditorLifetime()
        NotificationCenter.default.post(name: .displayPlacementEditorDidOpen, object: nil)

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        let wasOpen = self.panel != nil
        self.stopObservingEditorLifetime()
        self.panel?.orderOut(nil)
        self.panel = nil
        self.editingDisplayID = nil
        if wasOpen {
            NotificationCenter.default.post(name: .displayPlacementEditorDidClose, object: nil)
        }
    }

    private func displayForEditing(requestedID: UUID?) -> ConnectedDisplay? {
        if let requestedID, let display = ConnectedDisplays.display(withID: requestedID) {
            return display
        }

        switch KeypressConfig.shared.displays.target {
        case .followPointer:
            return ConnectedDisplays.display(containing: NSEvent.mouseLocation)
        case let .fixed(displayID):
            return ConnectedDisplays.display(withID: displayID) ?? ConnectedDisplays.main
        case let .selected(displayIDs):
            return ConnectedDisplays.all.first { displayIDs.contains($0.id) } ?? ConnectedDisplays.main
        }
    }

    private func startObservingEditorLifetime() {
        self.screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let displayID = self.editingDisplayID,
                      ConnectedDisplays.display(withID: displayID) != nil
                else {
                    self?.close()
                    return
                }
            }
        }

        self.appDeactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.close()
            }
        }
    }

    private func stopObservingEditorLifetime() {
        if let observer = self.screenParametersObserver {
            NotificationCenter.default.removeObserver(observer)
            self.screenParametersObserver = nil
        }
        if let observer = self.appDeactivationObserver {
            NotificationCenter.default.removeObserver(observer)
            self.appDeactivationObserver = nil
        }
    }
}

// MARK: - Editor Panel

@MainActor
private final class DisplayPlacementEditorPanel: NSPanel {
    override var canBecomeKey: Bool {
        get { true }
        set {}
    }

    override var canBecomeMain: Bool {
        get { true }
        set {}
    }

    init(
        display: ConnectedDisplay,
        initialPlacement: DisplayPlacement,
        initialUsesFallback: Bool,
        resetPlacement: DisplayPlacement,
        config: KeypressConfig,
        onDone: @escaping @MainActor (DisplayPlacement, Bool) -> Void,
        onCancel: @escaping @MainActor () -> Void)
    {
        let screenFrame = display.screen.frame
        let visibleFrame = display.screen.visibleFrame
        let localVisibleFrame = CGRect(
            x: visibleFrame.minX - screenFrame.minX,
            y: screenFrame.maxY - visibleFrame.maxY,
            width: visibleFrame.width,
            height: visibleFrame.height)

        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)

        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.isMovable = false
        self.isReleasedWhenClosed = false

        let editorView = DisplayPlacementEditorView(
            displayName: display.name,
            availableFrame: localVisibleFrame,
            initialPlacement: initialPlacement,
            initialUsesFallback: initialUsesFallback,
            resetPlacement: resetPlacement,
            config: config,
            onDone: onDone,
            onCancel: onCancel)
        let strings = StudioStrings(languageCode: config.general.language.studioLanguageCode)
        self.contentView = NSHostingView(
            rootView: editorView
                .environment(\.studioStrings, strings)
                .environment(\.locale, strings.locale))
        self.setFrame(screenFrame, display: false)
    }
}

// MARK: - Editor View

@MainActor
private struct DisplayPlacementEditorView: View {
    @Environment(\.studioStrings) private var strings
    let displayName: String
    let availableFrame: CGRect
    let resetPlacement: DisplayPlacement
    @Bindable var config: KeypressConfig
    let onDone: @MainActor (DisplayPlacement, Bool) -> Void
    let onCancel: @MainActor () -> Void

    @State private var draftPlacement: DisplayPlacement
    @State private var usesFallback: Bool
    @State private var previewSize = CGSize(width: 250, height: 80)
    @State private var dragStartCenter: CGPoint?

    private let snapThreshold: CGFloat = 32
    private let visualMargin: CGFloat = 18

    init(
        displayName: String,
        availableFrame: CGRect,
        initialPlacement: DisplayPlacement,
        initialUsesFallback: Bool,
        resetPlacement: DisplayPlacement,
        config: KeypressConfig,
        onDone: @escaping @MainActor (DisplayPlacement, Bool) -> Void,
        onCancel: @escaping @MainActor () -> Void)
    {
        self.displayName = displayName
        self.availableFrame = availableFrame
        self.resetPlacement = resetPlacement
        self._config = Bindable(wrappedValue: config)
        self.onDone = onDone
        self.onCancel = onCancel
        self._draftPlacement = State(initialValue: initialPlacement)
        self._usesFallback = State(initialValue: initialUsesFallback)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            self.snapGuides

            self.preview
                .position(self.center(for: self.draftPlacement))
                .gesture(self.dragGesture)

            self.banner
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, max(18, self.availableFrame.minY + 18))
        }
        .coordinateSpace(name: "placement-editor")
    }

    private var banner: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.draw")
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.strings["position.editor.title"])
                    .font(.headline)
                Text(String(
                    format: self.strings["position.editor.subtitle"],
                    locale: self.strings.locale,
                    self.displayName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            Text(self.currentPlacementLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())

            Button(self.strings["action.reset"]) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    self.draftPlacement = self.resetPlacement
                    self.usesFallback = true
                }
            }

            Button(self.strings["action.cancel"], action: self.onCancel)
                .keyboardShortcut(.cancelAction)

            Button(self.strings["action.done"]) {
                self.onDone(self.placementForSaving, self.usesFallback)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 720)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        }
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }

    private var preview: some View {
        KeyboardThemeContainer(config: self.config, disableOuterShadow: true) {
            self.previewKeys
        }
        .scaleEffect(self.config.size.scaleFactor)
        .opacity(self.config.opacity)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: PlacementPreviewSizePreferenceKey.self,
                    value: geometry.size)
            }
        }
        .onPreferenceChange(PlacementPreviewSizePreferenceKey.self) { size in
            guard size.width > 0, size.height > 0 else { return }
            self.previewSize = CGSize(
                width: size.width * self.config.size.scaleFactor,
                height: size.height * self.config.size.scaleFactor)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    Color.accentColor,
                    lineWidth: self.snappedAnchor == nil && !self.isSnappedToCenter ? 1 : 3)
                .padding(-5)
        }
        .shadow(
            color: Color.accentColor.opacity(
                self.snappedAnchor == nil && !self.isSnappedToCenter ? 0.15 : 0.55),
            radius: 12)
        .onHover { isHovering in
            (isHovering ? NSCursor.openHand : NSCursor.arrow).set()
        }
    }

    private var previewKeys: some View {
        HStack(spacing: CGFloat(self.keyboardTheme.keySpacing)) {
            KeyCapView(
                symbol: KeySymbol(id: "command-left", display: "⌘", isModifier: true),
                config: self.config)
            KeyCapView(
                symbol: KeySymbol(id: "shift-left", display: "⇧", isModifier: true),
                config: self.config)
            KeyCapView(
                symbol: KeySymbol(id: "key-40", display: "K"),
                config: self.config)
        }
    }

    private var keyboardTheme: KeyboardTheme {
        let isSystemDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return self.config.effectiveTheme(isSystemDark: isSystemDark).keyboard
    }

    @ViewBuilder
    private var snapGuides: some View {
        ForEach(OverlayPosition.allCases, id: \.self) { position in
            let center = self.anchorCenter(for: position, placement: self.snapPlacement(for: position))
            let size: CGFloat = self.snappedAnchor == position ? 12 : 8

            Circle()
                .fill(self.snappedAnchor == position ? Color.accentColor : Color.white.opacity(0.45))
                .frame(width: size, height: size)
                .overlay {
                    Circle().strokeBorder(.black.opacity(0.25))
                }
                .position(center)
        }

        Circle()
            .fill(self.isSnappedToCenter ? Color.accentColor : Color.white.opacity(0.45))
            .frame(width: self.isSnappedToCenter ? 12 : 8, height: self.isSnappedToCenter ? 12 : 8)
            .overlay {
                Circle().strokeBorder(.black.opacity(0.25))
            }
            .position(self.availableFrameCenter)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("placement-editor"))
            .onChanged { value in
                NSCursor.closedHand.set()
                if self.dragStartCenter == nil {
                    self.dragStartCenter = self.center(for: self.draftPlacement)
                }
                guard let dragStartCenter = self.dragStartCenter else { return }
                self.usesFallback = false

                let candidate = CGPoint(
                    x: dragStartCenter.x + value.translation.width,
                    y: dragStartCenter.y + value.translation.height)
                self.draftPlacement = self.placement(forDraggedCenter: candidate)
            }
            .onEnded { _ in
                self.dragStartCenter = nil
                NSCursor.openHand.set()
            }
    }

    private var snappedAnchor: OverlayPosition? {
        guard case let .anchor(position, _, _) = self.draftPlacement else { return nil }
        return position
    }

    private var isSnappedToCenter: Bool {
        guard case let .custom(center, _) = self.draftPlacement else { return false }
        return abs(center.x - 0.5) < 0.001 && abs(center.y - 0.5) < 0.001
    }

    private var availableFrameCenter: CGPoint {
        CGPoint(x: self.availableFrame.midX, y: self.availableFrame.midY)
    }

    private var currentPlacementLabel: String {
        switch self.draftPlacement {
        case let .anchor(position, _, _):
            self.strings[position.localizationKey]
        case .custom where self.isSnappedToCenter:
            self.strings["position.center"]
        case .custom:
            self.strings["position.custom"]
        }
    }

    private var placementForSaving: DisplayPlacement {
        let displayedCenter = self.center(for: self.draftPlacement)
        switch self.draftPlacement {
        case let .custom(_, fallbackAnchor):
            return .custom(
                center: self.normalizedPoint(for: displayedCenter),
                fallbackAnchor: fallbackAnchor)
        case let .anchor(position, horizontalOffset, verticalOffset):
            let halfWidth = self.previewSize.width / 2
            let halfHeight = self.previewSize.height / 2
            let savedHorizontalOffset = switch position {
            case .topLeft, .centerLeft, .bottomLeft:
                displayedCenter.x - halfWidth - self.availableFrame.minX
            case .topRight, .centerRight, .bottomRight:
                self.availableFrame.maxX - displayedCenter.x - halfWidth
            case .topCenter, .bottomCenter:
                CGFloat(horizontalOffset)
            }
            let savedVerticalOffset = switch position {
            case .topLeft, .topCenter, .topRight:
                displayedCenter.y - halfHeight - self.availableFrame.minY
            case .bottomLeft, .bottomCenter, .bottomRight:
                self.availableFrame.maxY - displayedCenter.y - halfHeight
            case .centerLeft, .centerRight:
                CGFloat(verticalOffset)
            }
            return .anchor(
                position: position,
                horizontalOffset: Double(max(0, savedHorizontalOffset)),
                verticalOffset: Double(max(0, savedVerticalOffset)))
        }
    }

    private func placement(forDraggedCenter center: CGPoint) -> DisplayPlacement {
        let clampedCenter = self.clamped(center: center)

        if hypot(
            self.availableFrameCenter.x - clampedCenter.x,
            self.availableFrameCenter.y - clampedCenter.y) <= self.snapThreshold
        {
            return .custom(
                center: NormalizedPoint(x: 0.5, y: 0.5),
                fallbackAnchor: self.nearestAnchor(to: clampedCenter))
        }

        if let snappedPosition = OverlayPosition.allCases.first(where: { position in
            let snapPlacement = self.snapPlacement(for: position)
            let snapCenter = self.anchorCenter(for: position, placement: snapPlacement)
            return hypot(snapCenter.x - clampedCenter.x, snapCenter.y - clampedCenter.y) <= self.snapThreshold
        }) {
            return self.snapPlacement(for: snappedPosition)
        }

        return .custom(
            center: self.normalizedPoint(for: clampedCenter),
            fallbackAnchor: self.nearestAnchor(to: clampedCenter))
    }

    private func snapPlacement(for position: OverlayPosition) -> DisplayPlacement {
        let offsets = self.anchorOffsets
        return .anchor(
            position: position,
            horizontalOffset: offsets.horizontal,
            verticalOffset: offsets.vertical)
    }

    private var anchorOffsets: (horizontal: Double, vertical: Double) {
        if case let .anchor(_, horizontalOffset, verticalOffset) = self.resetPlacement {
            return (horizontalOffset, verticalOffset)
        }
        return (20, 20)
    }

    private func center(for placement: DisplayPlacement) -> CGPoint {
        switch placement {
        case let .anchor(position, _, _):
            self.anchorCenter(for: position, placement: placement)
        case let .custom(center, _):
            self.clamped(center: CGPoint(
                x: self.availableFrame.minX + CGFloat(center.x) * self.availableFrame.width,
                y: self.availableFrame.maxY - CGFloat(center.y) * self.availableFrame.height))
        }
    }

    private func nearestAnchor(to center: CGPoint) -> OverlayPosition {
        OverlayPosition.allCases.min { lhs, rhs in
            let lhsCenter = self.anchorCenter(for: lhs, placement: self.snapPlacement(for: lhs))
            let rhsCenter = self.anchorCenter(for: rhs, placement: self.snapPlacement(for: rhs))
            return hypot(lhsCenter.x - center.x, lhsCenter.y - center.y) <
                hypot(rhsCenter.x - center.x, rhsCenter.y - center.y)
        } ?? .bottomRight
    }

    private func anchorCenter(for position: OverlayPosition, placement: DisplayPlacement) -> CGPoint {
        let horizontalOffset: CGFloat
        let verticalOffset: CGFloat
        if case let .anchor(_, storedHorizontalOffset, storedVerticalOffset) = placement {
            horizontalOffset = CGFloat(storedHorizontalOffset)
            verticalOffset = CGFloat(storedVerticalOffset)
        } else {
            horizontalOffset = 20
            verticalOffset = 20
        }

        let halfWidth = self.previewSize.width / 2
        let halfHeight = self.previewSize.height / 2
        let left = self.availableFrame.minX + horizontalOffset + halfWidth
        let centerX = self.availableFrame.midX
        let right = self.availableFrame.maxX - horizontalOffset - halfWidth
        let top = self.availableFrame.minY + verticalOffset + halfHeight
        let centerY = self.availableFrame.midY
        let bottom = self.availableFrame.maxY - verticalOffset - halfHeight

        let center = switch position {
        case .topLeft: CGPoint(x: left, y: top)
        case .topCenter: CGPoint(x: centerX, y: top)
        case .topRight: CGPoint(x: right, y: top)
        case .centerLeft: CGPoint(x: left, y: centerY)
        case .centerRight: CGPoint(x: right, y: centerY)
        case .bottomLeft: CGPoint(x: left, y: bottom)
        case .bottomCenter: CGPoint(x: centerX, y: bottom)
        case .bottomRight: CGPoint(x: right, y: bottom)
        }
        return self.clamped(center: center)
    }

    private func clamped(center: CGPoint) -> CGPoint {
        let halfWidth = self.previewSize.width / 2 + self.visualMargin
        let halfHeight = self.previewSize.height / 2 + self.visualMargin
        guard self.availableFrame.width >= self.previewSize.width + self.visualMargin * 2,
              self.availableFrame.height >= self.previewSize.height + self.visualMargin * 2
        else {
            return CGPoint(x: self.availableFrame.midX, y: self.availableFrame.midY)
        }
        return CGPoint(
            x: min(
                max(center.x, self.availableFrame.minX + halfWidth),
                self.availableFrame.maxX - halfWidth),
            y: min(
                max(center.y, self.availableFrame.minY + halfHeight),
                self.availableFrame.maxY - halfHeight))
    }

    private func normalizedPoint(for center: CGPoint) -> NormalizedPoint {
        let x = (center.x - self.availableFrame.minX) / self.availableFrame.width
        let y = (self.availableFrame.maxY - center.y) / self.availableFrame.height
        return NormalizedPoint(x: Double(x), y: Double(y))
    }
}

extension OverlayPosition {
    fileprivate var localizationKey: String {
        switch self {
        case .topLeft: "position.topLeft"
        case .topCenter: "position.topCenter"
        case .topRight: "position.topRight"
        case .centerLeft: "position.centerLeft"
        case .centerRight: "position.centerRight"
        case .bottomLeft: "position.bottomLeft"
        case .bottomCenter: "position.bottomCenter"
        case .bottomRight: "position.bottomRight"
        }
    }
}

private struct PlacementPreviewSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
