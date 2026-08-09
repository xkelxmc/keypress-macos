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
            initialCommandZonePlacement: displaySettings.commandZonePlacement(for: display.id),
            resetPlacement: resetPlacement,
            config: config,
            onDone: { [weak self] result in
                if result.usesFallback {
                    config.displays.removePlacement(for: display.id)
                } else {
                    config.displays.setPlacement(result.placement, for: display.id)
                }
                // Whatever the user dropped is now this mode's layout, so it is stamped as
                // such: the running mode leaves its own layout alone, drags included.
                if let commandZonePlacement = result.commandZonePlacement {
                    config.displays.setCommandZonePlacement(commandZonePlacement, for: display.id)
                    config.displays.setZoneLayoutPresentation(
                        config.keyboard.presentation,
                        for: display.id)
                } else {
                    config.displays.removeCommandZonePlacement(for: display.id)
                    config.displays.removeZoneLayoutPresentation(for: display.id)
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

// MARK: - Editor Result

/// What the editor hands back when the user clicks Done.
struct DisplayPlacementEditorResult {
    let placement: DisplayPlacement
    let usesFallback: Bool

    /// Placement for the horizontal-history command zone, or nil while it stays stacked
    /// under the text ribbon.
    let commandZonePlacement: DisplayPlacement?
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
        initialCommandZonePlacement: DisplayPlacement?,
        resetPlacement: DisplayPlacement,
        config: KeypressConfig,
        onDone: @escaping @MainActor (DisplayPlacementEditorResult) -> Void,
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
            initialCommandZonePlacement: initialCommandZonePlacement,
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
    let onDone: @MainActor (DisplayPlacementEditorResult) -> Void
    let onCancel: @MainActor () -> Void

    @State private var draftPlacement: DisplayPlacement
    @State private var usesFallback: Bool
    @State private var commandZoneDraft: DisplayPlacement?
    @State private var previewSize: CGSize
    @State private var commandZonePreviewSize: CGSize
    @State private var dragSession = ZoneDragSession()
    @State private var commandZoneDragSession = ZoneDragSession()

    /// Gap the live overlay leaves between the ribbon and the command zone.
    private static let zoneSpacing: CGFloat = 10

    private var geometry: PlacementZoneGeometry {
        PlacementZoneGeometry(
            availableFrame: self.availableFrame,
            resetPlacement: self.resetPlacement)
    }

    init(
        displayName: String,
        availableFrame: CGRect,
        initialPlacement: DisplayPlacement,
        initialUsesFallback: Bool,
        initialCommandZonePlacement: DisplayPlacement?,
        resetPlacement: DisplayPlacement,
        config: KeypressConfig,
        onDone: @escaping @MainActor (DisplayPlacementEditorResult) -> Void,
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
        self._commandZoneDraft = State(initialValue: initialCommandZonePlacement)

        // Both zones are laid out and snapped by their real size from the first frame, so
        // the sizes are measured up front rather than guessed and corrected later.
        let scale = config.size.scaleFactor
        let widgetKind = PlacementZoneKind(config.keyboard.presentation)
        self._previewSize = State(
            initialValue: Self.fittingSize(of: widgetKind, config: config, scale: scale))
        self._commandZonePreviewSize = State(
            initialValue: Self.fittingSize(of: .commands, config: config, scale: scale))
    }

    private static func fittingSize(
        of kind: PlacementZoneKind,
        config: KeypressConfig,
        scale: CGFloat) -> CGSize
    {
        let size = ViewMeasure.fittingSize(of: PlacementZonePreview(kind: kind, config: config))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// The two-zone modes place their own zone and a command zone, each dragged on its own.
    private var editsCommandZone: Bool {
        self.config.keyboard.presentation.usesSeparateCommandZoneWindow
    }

    private var widgetKind: PlacementZoneKind {
        PlacementZoneKind(self.config.keyboard.presentation)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            self.snapGuides

            self.zonePreview(self.widgetKind, size: self.$previewSize)
                .modifier(PlacementPreviewChrome(isSnapped: self.isSnapped(self.draftPlacement)))
                .position(self.geometry.center(
                    for: self.draftPlacement,
                    previewSize: self.previewSize))
                .gesture(self.dragGesture)

            if self.editsCommandZone {
                self.zonePreview(.commands, size: self.$commandZonePreviewSize)
                    .modifier(PlacementPreviewChrome(isSnapped: self.commandZoneIsSnapped))
                    .position(self.commandZoneCenter)
                    .gesture(self.commandZoneDragGesture)
            }

            self.banner
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, max(18, self.availableFrame.minY + 18))
        }
        .coordinateSpace(name: "placement-editor")
    }

    /// Returns both zones to the default the mode derives for this display — the command
    /// zone on the display's own placement and the ribbon clear of it — rather than to a
    /// single widget position the two zones would have to share.
    private func reset() {
        withAnimation(.easeInOut(duration: 0.18)) {
            guard self.editsCommandZone else {
                self.draftPlacement = self.resetPlacement
                self.usesFallback = true
                self.commandZoneDraft = nil
                return
            }

            let placements = HorizontalHistoryZonePlacements.derived(
                from: self.resetPlacement,
                scale: self.config.size.scaleFactor,
                visibleHeight: self.availableFrame.height,
                primaryZoneHeight: self.config.keyboard.presentation.primaryZoneNominalHeight)
            self.draftPlacement = placements.ribbon
            self.usesFallback = false
            self.commandZoneDraft = placements.commandZone
        }
    }

    private func zonePreview(_ kind: PlacementZoneKind, size: Binding<CGSize>) -> some View {
        PlacementZonePreview(kind: kind, config: self.config)
            .scaleEffect(self.config.size.scaleFactor)
            .opacity(self.config.opacity)
            .measured(into: size, scale: self.config.size.scaleFactor)
    }

    /// Where the command zone is drawn: its own placement once the user has dragged it,
    /// otherwise the derived spot directly under the ribbon that the live overlay uses.
    private var commandZoneCenter: CGPoint {
        guard let commandZoneDraft = self.commandZoneDraft else {
            return self.geometry.stackedCommandZoneCenter(
                ribbonCenter: self.geometry.center(
                    for: self.draftPlacement,
                    previewSize: self.previewSize),
                ribbonSize: self.previewSize,
                commandZoneSize: self.commandZonePreviewSize,
                side: self.zoneSide,
                spacing: Self.zoneSpacing)
        }
        return self.geometry.center(
            for: commandZoneDraft,
            previewSize: self.commandZonePreviewSize)
    }

    private var commandZoneIsSnapped: Bool {
        self.commandZoneDraft.map(self.isSnapped) ?? false
    }

    /// The zones only see each other in mode 2, and only so that a drag can stick one beside
    /// the other. Neither follows the other once dropped.
    private var commandZoneNeighbour: PlacementZoneNeighbour? {
        guard self.editsCommandZone else { return nil }
        return PlacementZoneNeighbour(
            center: self.commandZoneCenter,
            size: self.commandZonePreviewSize)
    }

    private var ribbonNeighbour: PlacementZoneNeighbour? {
        guard self.editsCommandZone else { return nil }
        return PlacementZoneNeighbour(
            center: self.geometry.center(for: self.draftPlacement, previewSize: self.previewSize),
            size: self.previewSize)
    }

    /// Mirrors how the live overlay lines the command zone up under the ribbon: on whichever
    /// side the ribbon's own anchor sits, and centred when it has none.
    private var zoneSide: PlacementZoneSide {
        guard case let .anchor(position, _, _) = self.draftPlacement else { return .center }
        return switch position {
        case .topLeft, .centerLeft, .bottomLeft: .leading
        case .topRight, .centerRight, .bottomRight: .trailing
        case .topCenter, .bottomCenter: .center
        }
    }

    private var banner: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.draw")
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.strings["position.editor.title"])
                    .font(.headline)
                Text(String(
                    format: self.strings[
                        self.editsCommandZone
                            ? "position.editor.subtitle.zones"
                            : "position.editor.subtitle"
                    ],
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

            Button(self.strings["action.reset"], action: self.reset)

            Button(self.strings["action.cancel"], action: self.onCancel)
                .keyboardShortcut(.cancelAction)

            Button(self.strings["action.done"]) {
                self.onDone(DisplayPlacementEditorResult(
                    placement: self.placementForSaving,
                    usesFallback: self.usesFallback,
                    commandZonePlacement: self.commandZonePlacementForSaving))
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

    @ViewBuilder
    private var snapGuides: some View {
        ForEach(OverlayPosition.allCases, id: \.self) { position in
            let center = self.geometry.anchorCenter(
                for: position,
                placement: self.geometry.snapPlacement(for: position),
                previewSize: self.previewSize)
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
                self.usesFallback = false
                self.draftPlacement = self.dragSession.placement(
                    startLocation: value.startLocation,
                    currentCenter: self.geometry.center(
                        for: self.draftPlacement,
                        previewSize: self.previewSize),
                    translation: value.translation,
                    previewSize: self.previewSize,
                    geometry: self.geometry,
                    neighbour: self.commandZoneNeighbour)
            }
            .onEnded { _ in
                self.dragSession.end()
                NSCursor.openHand.set()
            }
    }

    /// Drags the command zone. The first drag gives it a placement of its own; until then it
    /// simply rides along under the ribbon.
    private var commandZoneDragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("placement-editor"))
            .onChanged { value in
                NSCursor.closedHand.set()
                self.commandZoneDraft = self.commandZoneDragSession.placement(
                    startLocation: value.startLocation,
                    currentCenter: self.commandZoneCenter,
                    translation: value.translation,
                    previewSize: self.commandZonePreviewSize,
                    geometry: self.geometry,
                    neighbour: self.ribbonNeighbour)
            }
            .onEnded { _ in
                self.commandZoneDragSession.end()
                NSCursor.openHand.set()
            }
    }

    private var snappedAnchor: OverlayPosition? {
        guard case let .anchor(position, _, _) = self.draftPlacement else { return nil }
        return position
    }

    private var isSnappedToCenter: Bool {
        self.isSnappedToCenter(self.draftPlacement)
    }

    private func isSnappedToCenter(_ placement: DisplayPlacement) -> Bool {
        guard case let .custom(center, _) = placement else { return false }
        return abs(center.x - 0.5) < 0.001 && abs(center.y - 0.5) < 0.001
    }

    private func isSnapped(_ placement: DisplayPlacement) -> Bool {
        if case .anchor = placement {
            return true
        }
        return self.isSnappedToCenter(placement)
    }

    private var availableFrameCenter: CGPoint {
        self.geometry.availableFrameCenter
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
        self.placementForSaving(self.draftPlacement, previewSize: self.previewSize)
    }

    private var commandZonePlacementForSaving: DisplayPlacement? {
        guard self.editsCommandZone, let commandZoneDraft = self.commandZoneDraft else { return nil }
        return self.placementForSaving(commandZoneDraft, previewSize: self.commandZonePreviewSize)
    }

    private func placementForSaving(
        _ placement: DisplayPlacement,
        previewSize: CGSize) -> DisplayPlacement
    {
        self.geometry.placementForSaving(placement, previewSize: previewSize)
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

/// Which widget a draggable preview stands for.
private enum PlacementZoneKind {
    /// Latest: one row of keys.
    case widget

    /// Horizontal history: the text ribbon.
    case ribbon

    /// Text echo: three lines of typed text, always all three. A preview one line tall would
    /// have the user park the command zone exactly where lines two and three will land.
    case textEcho

    /// The command zone, in either two-zone mode.
    case commands

    init(_ presentation: KeyboardPresentation) {
        self = switch presentation {
        case .latest: .widget
        case .horizontalHistory: .ribbon
        case .stackedHistory: .textEcho
        }
    }
}

/// A stand-in for one placeable widget, drawn in the current theme so its footprint matches
/// what the overlay will occupy.
@MainActor
private struct PlacementZonePreview: View {
    let kind: PlacementZoneKind
    let config: KeypressConfig

    var body: some View {
        // The echo wears no keyboard frame — its lines carry their own plaques.
        if self.kind == .textEcho {
            TextEchoPreviewLines(lines: Self.echoLines, config: self.config)
        } else {
            KeyboardThemeContainer(config: self.config, disableOuterShadow: true) {
                HStack(spacing: CGFloat(self.theme.keySpacing)) {
                    ForEach(self.symbols, id: \.id) { symbol in
                        KeyCapView(symbol: symbol, config: self.config)
                    }
                }
            }
        }
    }

    /// A full three-line block, so the preview's footprint is the one the echo will take.
    private static let echoLines = [
        "the quick brown fox",
        "jumps over the lazy",
        "dog while typing",
    ]

    private var symbols: [KeySymbol] {
        switch self.kind {
        case .widget:
            [
                KeySymbol(id: "command-left", display: "⌘", isModifier: true),
                KeySymbol(id: "shift-left", display: "⇧", isModifier: true),
                KeySymbol(id: "key-40", display: "K"),
            ]
        case .ribbon, .textEcho:
            [
                KeySymbol(id: "h", display: "h"),
                KeySymbol(id: "e", display: "e"),
                KeySymbol(id: "y", display: "y"),
            ]
        case .commands:
            [
                KeySymbol(id: "command-left", display: "⌘", isModifier: true),
                KeySymbol(id: "key-40", display: "K"),
            ]
        }
    }

    private var theme: KeyboardTheme {
        let isSystemDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return self.config.effectiveTheme(isSystemDark: isSystemDark).keyboard
    }
}

/// Selection outline every draggable zone preview wears.
private struct PlacementPreviewChrome: ViewModifier {
    let isSnapped: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: self.isSnapped ? 3 : 1)
                    .padding(-5)
            }
            .shadow(color: Color.accentColor.opacity(self.isSnapped ? 0.55 : 0.15), radius: 12)
            .onHover { isHovering in
                (isHovering ? NSCursor.openHand : NSCursor.arrow).set()
            }
    }
}

extension View {
    /// Reports the view's laid-out size, scaled by the overlay size factor, into a binding.
    fileprivate func measured(into size: Binding<CGSize>, scale: CGFloat) -> some View {
        self.background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: PlacementPreviewSizePreferenceKey.self,
                    value: geometry.size)
            }
        }
        .onPreferenceChange(PlacementPreviewSizePreferenceKey.self) { measured in
            guard measured.width > 0, measured.height > 0 else { return }
            size.wrappedValue = CGSize(
                width: measured.width * scale,
                height: measured.height * scale)
        }
    }
}
