import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import KeypressCore
import Observation

/// Manages the overlay window lifecycle and key monitoring.
@MainActor
final class OverlayController {
    // MARK: - Properties

    private let config: KeypressConfig
    private let permission = InputMonitoringPermission.shared
    private let pointerController: PointerOverlayController
    private let hudWindow = HUDWindow()
    private lazy var petController = PetController(
        config: self.config,
        keyboardFrame: { [weak self] in
            self?.preferredPetKeyboardFrame
        })
    private var keyMonitor: KeyMonitor?
    private var pointerInputMonitor: PointerInputMonitor?
    private var overlayWindows: [UUID: OverlayWindow] = [:]
    private var secureInputTask: Task<Void, Never>?
    private var monitorHealthTask: Task<Void, Never>?
    private var overlayShouldBeVisible = false
    private var secureInputEnabled = false
    private var placementEditorActive = false
    private var isObservingConfig = false
    private var isObservingKeyState = false
    private var configObservationGeneration: UInt64 = 0
    private var keyStateObservationGeneration: UInt64 = 0
    private var lastAppliedSettings: AppSettings?

    // Key state (one of these will be used based on display mode)
    private var historyKeyState: KeyState?
    private var singleKeyState: SingleKeyState?
    private var stackedHistoryState: StackedHistoryState?

    // Screen observers
    private var screenParametersObserver: Any?
    private var workspaceObserver: Any?
    private var activeSpaceObserver: Any?
    private var globalSwipeMonitor: Any?
    private var localSwipeMonitor: Any?
    private var sleepObserver: Any?
    private var wakeObserver: Any?
    private var placementEditorOpenObserver: Any?
    private var placementEditorCloseObserver: Any?
    private var placementEditorSaveObserver: Any?

    /// Runtime hook for pointer/HUD controllers that need to follow the same
    /// connected-display changes without sharing keyboard overlay windows.
    var displayTargetsDidChange: (([ConnectedDisplay]) -> Void)?

    private(set) var activeKeyboardDisplays: [ConnectedDisplay] = []

    var activeKeyboardFrames: [UUID: NSRect] {
        self.overlayWindows.mapValues { $0.frame }
    }

    func keyboardOverlayFrame(on displayID: UUID) -> NSRect? {
        self.overlayWindows[displayID]?.frame
    }

    /// Current key state protocol reference for common operations.
    private var currentKeyState: (any KeyStateProtocol)? {
        switch self.config.keyboard.presentation {
        case .latest:
            self.singleKeyState
        case .horizontalHistory:
            self.historyKeyState
        case .stackedHistory:
            self.stackedHistoryState
        }
    }

    var isRunning: Bool {
        self.keyMonitor?.isRunning ?? false
    }

    // MARK: - Initialization

    init(config: KeypressConfig = .shared) {
        self.config = config
        self.pointerController = PointerOverlayController(config: config)
    }

    deinit {
        self.secureInputTask?.cancel()
        self.monitorHealthTask?.cancel()
        // Note: stopObservingScreens() would require @MainActor, but deinit can't be async
        // The observers will be cleaned up automatically when the object is deallocated
    }

    // MARK: - Public Methods

    /// Starts key monitoring and shows overlay when keys are pressed.
    func start() {
        guard self.keyMonitor == nil else { return }

        // Clean up any existing overlay window (e.g., from delayed stop)
        self.hideAndRemoveOverlayWindows()
        self.overlayShouldBeVisible = false
        self.hudWindow.hide()
        self.pointerController.clear()
        self.pointerController.refresh()

        // Create appropriate key state based on display mode
        self.createKeyState()

        if self.config.keyboard.enabled {
            self.reconcileOverlayWindows()
        }
        self.petController.start()

        self.keyMonitor = self.makeKeyMonitor()

        // Start observing screen changes
        self.startObservingScreens()
        self.startObservingConfig()
        self.startObservingMonitorHealth()

        self.permission.onPermissionChange { [weak self] granted in
            print("[Keypress] Permission changed: \(granted)")
            if granted {
                self?.ensureKeyboardMonitoring()
                self?.ensurePointerMonitoring()
            }
        }

        self.ensureKeyboardMonitoring()
        self.ensurePointerMonitoring()
    }

    /// Stops key monitoring and hides overlay.
    func stop() {
        self.isObservingKeyState = false
        self.keyStateObservationGeneration &+= 1
        self.isObservingConfig = false
        self.configObservationGeneration &+= 1
        self.lastAppliedSettings = nil
        self.secureInputTask?.cancel()
        self.secureInputTask = nil
        self.monitorHealthTask?.cancel()
        self.monitorHealthTask = nil

        self.stopObservingScreens()
        DisplayPlacementEditorController.shared.close()
        self.placementEditorActive = false

        self.keyMonitor?.stop()
        self.keyMonitor = nil
        self.pointerInputMonitor?.stop()
        self.pointerInputMonitor = nil
        self.permission.stopPolling()

        self.hideAndRemoveOverlayWindows()
        self.overlayShouldBeVisible = false
        self.pointerController.clear()
        self.petController.stop()
        self.hudWindow.hide()

        self.currentKeyState?.clear()
        self.historyKeyState = nil
        self.singleKeyState = nil
        self.stackedHistoryState = nil
        self.secureInputEnabled = false
    }

    /// Stops key monitoring and clears keys, but keeps overlay window for hint.
    /// Call stop() later to fully clean up.
    func stopMonitoring() {
        self.isObservingConfig = false
        self.configObservationGeneration &+= 1
        self.lastAppliedSettings = nil
        self.isObservingKeyState = false
        self.keyStateObservationGeneration &+= 1
        self.secureInputTask?.cancel()
        self.secureInputTask = nil
        self.monitorHealthTask?.cancel()
        self.monitorHealthTask = nil
        self.stopObservingScreens()
        DisplayPlacementEditorController.shared.close()
        self.placementEditorActive = false

        self.keyMonitor?.stop()
        self.keyMonitor = nil
        self.stopPointerMonitoring()
        self.permission.stopPolling()
        self.currentKeyState?.clear()
        self.overlayShouldBeVisible = false
        self.hideOverlayWindows()
        self.pointerController.clear()
        self.petController.stop()
    }

    /// Updates overlay position based on current settings.
    func updatePosition() {
        self.reconcileOverlayWindows()
    }

    /// Re-resolves `.followPointer` only when a key is pressed. Pointer movement
    /// alone must not create keyboard overlay windows while the overlay is idle.
    private func refreshFollowPointerTarget() {
        guard case .followPointer = self.config.displays.target else { return }
        self.reconcileOverlayWindows()
    }

    /// Updates overlay opacity based on current settings.
    func updateOpacity() {
        for window in self.overlayWindows.values {
            window.alphaValue = self.config.opacity
        }
    }

    /// Updates key timeout based on current settings.
    func updateKeyTimeout() {
        self.historyKeyState?.keyTimeout = self.config.keyTimeout
        self.singleKeyState?.keyTimeout = self.config.keyTimeout
    }

    /// Updates history mode settings.
    func updateHistorySettings() {
        self.historyKeyState?.maxDisplayedKeys = self.config.maxKeys
        self.historyKeyState?.duplicateLetters = self.config.duplicateLetters
        self.historyKeyState?.limitIncludesModifiers = self.config.limitIncludesModifiers
        self.historyKeyState?.contentMode = self.config.keyboard.contentMode
        self.historyKeyState?.filters = self.config.keyboard.filters
        self.stackedHistoryState?.apply(self.config.keyboard)
    }

    /// Updates single mode settings.
    func updateSingleSettings() {
        self.singleKeyState?.contentMode = self.config.keyboard.contentMode
        self.singleKeyState?.filters = self.config.keyboard.filters
    }

    /// Compatibility entry point used by the existing menu toggle.
    func showToggleHint(isEnabled: Bool) {
        let shortcutText = KeyboardShortcuts.getShortcut(for: .toggleOverlay)?.displayString ?? ""
        self.showHUD(
            text: isEnabled ? "Keypress On" : "Keypress Off",
            shortcut: shortcutText,
            kind: isEnabled ? .positive : .negative)
    }

    func showHUD(text: String, shortcut: String? = nil, kind: HUDKind) {
        guard self.config.hud.enabled else { return }
        let display = self.hudDisplay
        self.hudWindow.show(
            text: text,
            shortcut: shortcut,
            kind: kind,
            palette: self.config.effectiveTheme(isSystemDark: self.systemIsDark).hud,
            on: display?.screen,
            near: display.flatMap { self.keyboardOverlayFrame(on: $0.id) },
            duration: self.config.hud.duration)
    }

    func refreshPointer() {
        self.pointerController.refresh()
    }

    func openPositionEditor(displayID: UUID? = nil) {
        DisplayPlacementEditorController.shared.show(for: displayID)
    }

    // MARK: - Private Methods

    private var hudDisplay: ConnectedDisplay? {
        let pointerDisplay = ConnectedDisplays.display(containing: NSEvent.mouseLocation)
        if let pointerDisplay,
           self.activeKeyboardDisplays.contains(where: { $0.id == pointerDisplay.id })
        {
            return pointerDisplay
        }
        return self.activeKeyboardDisplays.first ?? pointerDisplay ?? ConnectedDisplays.main
    }

    private var systemIsDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func makeKeyMonitor() -> KeyMonitor {
        KeyMonitor { [weak self] event, symbol in
            Task { @MainActor [weak self] in
                self?.processKeyboard(event, symbol: symbol)
            }
        }
    }

    private func processKeyboard(_ event: KeyEvent, symbol: KeySymbol?) {
        guard self.config.general.enabled else { return }

        let secureInputEnabled = IsSecureEventInputEnabled()
        if secureInputEnabled != self.secureInputEnabled {
            self.handleSecureInputChanged(secureInputEnabled)
        }
        guard !self.secureInputEnabled else { return }

        let isRegisteredShortcut = self.isRegisteredShortcut(event)
        if self.config.keyboard.enabled,
           !isRegisteredShortcut,
           event.type == .keyDown
        {
            self.refreshFollowPointerTarget()
        }
        self.petController.processKeyboard(
            event,
            isRegisteredShortcut: isRegisteredShortcut)

        guard self.config.keyboard.enabled else { return }

        if isRegisteredShortcut {
            self.currentKeyState?.clear()
            return
        }

        self.currentKeyState?.processEvent(event, symbol: symbol)
        self.updateOverlayVisibility()
    }

    private func ensurePointerMonitoring() {
        guard self.needsPointerMonitoring else {
            self.stopPointerMonitoring()
            return
        }
        guard self.pointerInputMonitor?.isRunning != true else { return }

        self.pointerInputMonitor?.stop()
        let monitor = PointerInputMonitor { [weak self] event in
            guard let self else { return }
            if self.config.pointer.enabled {
                self.pointerController.process(event)
            }
            self.petController.processPointer(event)
        }
        self.pointerInputMonitor = monitor
        if !monitor.start() {
            self.permission.startPolling()
        }
    }

    private func stopPointerMonitoring() {
        self.pointerInputMonitor?.stop()
        self.pointerInputMonitor = nil
        self.stopPermissionPollingIfUnused()
    }

    private func isRegisteredShortcut(_ event: KeyEvent) -> Bool {
        guard event.type != .flagsChanged else { return false }
        let names: [KeyboardShortcuts.Name] = [
            .toggleOverlay,
            .togglePointer,
            .switchContentMode,
            .editPosition,
            .increaseOverlaySize,
            .decreaseOverlaySize,
        ]

        return names.contains { name in
            guard let shortcut = KeyboardShortcuts.getShortcut(for: name),
                  let key = shortcut.key,
                  Int64(key.rawValue) == event.keyCode
            else {
                return false
            }

            let flags = event.modifiers
            return shortcut.modifiers.contains(.command) == flags.contains(.maskCommand)
                && shortcut.modifiers.contains(.option) == flags.contains(.maskAlternate)
                && shortcut.modifiers.contains(.control) == flags.contains(.maskControl)
                && shortcut.modifiers.contains(.shift) == flags.contains(.maskShift)
        }
    }

    private func reconcileOverlayWindows() {
        guard self.config.general.enabled, self.config.keyboard.enabled else {
            self.hideAndRemoveOverlayWindows()
            return
        }

        let displays = self.targetDisplays()
        let targetIDs = Set(displays.map(\.id))

        let staleDisplayIDs = self.overlayWindows.keys.filter { !targetIDs.contains($0) }
        for displayID in staleDisplayIDs {
            self.overlayWindows.removeValue(forKey: displayID)?.hideOverlay()
        }

        for display in displays {
            let window: OverlayWindow
            if let existingWindow = self.overlayWindows[display.id] {
                window = existingWindow
            } else {
                guard let newWindow = self.makeOverlayWindow() else { continue }
                newWindow.visibleContentFrameDidChange = { [weak self] in
                    self?.petController.refreshInitialPosition()
                }
                self.overlayWindows[display.id] = newWindow
                window = newWindow
            }

            window.updatePosition(on: display.screen)
            window.alphaValue = self.config.opacity
            if self.overlayShouldBeVisible, !self.placementEditorActive {
                window.showOverlay()
            }
        }

        let previousIDs = self.activeKeyboardDisplays.map(\.id)
        let newIDs = displays.map(\.id)
        self.activeKeyboardDisplays = displays
        if previousIDs != newIDs {
            self.displayTargetsDidChange?(displays)
        }
    }

    private func targetDisplays() -> [ConnectedDisplay] {
        let connected = ConnectedDisplays.all
        let fallback = ConnectedDisplays.main.map { [$0] } ?? []

        switch self.config.displays.target {
        case .followPointer:
            return ConnectedDisplays.display(containing: NSEvent.mouseLocation).map { [$0] } ?? fallback
        case let .fixed(displayID):
            return connected.first { $0.id == displayID }.map { [$0] } ?? fallback
        case let .selected(displayIDs):
            let selected = connected.filter { displayIDs.contains($0.id) }
            return selected.isEmpty ? fallback : selected
        }
    }

    private func makeOverlayWindow() -> OverlayWindow? {
        switch self.config.keyboard.presentation {
        case .latest:
            guard let singleState = self.singleKeyState else {
                print("[Keypress] ERROR: SingleKeyState not created - cannot create overlay")
                return nil
            }
            return OverlayWindow(
                singleKeyState: singleState,
                config: self.config)
        case .horizontalHistory:
            guard let historyState = self.historyKeyState else {
                print("[Keypress] ERROR: KeyState not created - cannot create overlay")
                return nil
            }
            return OverlayWindow(
                keyState: historyState,
                config: self.config)
        case .stackedHistory:
            guard let stackedHistoryState = self.stackedHistoryState else {
                print("[Keypress] ERROR: StackedHistoryState not created - cannot create overlay")
                return nil
            }
            return OverlayWindow(
                stackedHistoryState: stackedHistoryState,
                config: self.config)
        }
    }

    private func showOverlayWindows() {
        for window in self.overlayWindows.values {
            window.showOverlay()
        }
    }

    private func hideOverlayWindows() {
        for window in self.overlayWindows.values {
            window.hideOverlay()
        }
    }

    private func hideAndRemoveOverlayWindows() {
        self.hideOverlayWindows()
        self.overlayWindows.removeAll()
        if !self.activeKeyboardDisplays.isEmpty {
            self.activeKeyboardDisplays = []
            self.displayTargetsDidChange?([])
        }
    }

    private func createKeyState() {
        self.historyKeyState = nil
        self.singleKeyState = nil
        self.stackedHistoryState = nil

        switch self.config.keyboard.presentation {
        case .latest:
            let state = SingleKeyState()
            state.keyTimeout = self.config.keyTimeout
            state.contentMode = self.config.keyboard.contentMode
            state.filters = self.config.keyboard.filters
            self.singleKeyState = state
        case .horizontalHistory:
            let state = KeyState()
            state.keyTimeout = self.config.keyTimeout
            state.maxDisplayedKeys = self.config.maxKeys
            state.duplicateLetters = self.config.duplicateLetters
            state.limitIncludesModifiers = self.config.limitIncludesModifiers
            state.contentMode = self.config.keyboard.contentMode
            state.filters = self.config.keyboard.filters
            self.historyKeyState = state
        case .stackedHistory:
            self.stackedHistoryState = StackedHistoryState(settings: self.config.keyboard)
        }
    }

    private func startObservingKeyState() {
        self.isObservingKeyState = true
        self.keyStateObservationGeneration &+= 1
        let generation = self.keyStateObservationGeneration
        self.observeNextKeyStateChange(generation: generation)
        self.updateOverlayVisibility()
        self.startObservingSecureInput()
    }

    private func observeNextKeyStateChange(generation: UInt64) {
        guard self.isObservingKeyState,
              self.keyStateObservationGeneration == generation
        else {
            return
        }

        withObservationTracking {
            _ = self.currentKeyState?.hasKeys
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isObservingKeyState,
                      self.keyStateObservationGeneration == generation
                else {
                    return
                }
                self.updateOverlayVisibility()
                self.observeNextKeyStateChange(generation: generation)
            }
        }
    }

    private func updateOverlayVisibility() {
        let hasKeys = self.currentKeyState?.hasKeys ?? false
        let shouldBeVisible = self.config.general.enabled
            && self.config.keyboard.enabled
            && !self.secureInputEnabled
            && hasKeys
        guard shouldBeVisible != self.overlayShouldBeVisible else { return }

        self.overlayShouldBeVisible = shouldBeVisible
        if shouldBeVisible, !self.placementEditorActive {
            self.showOverlayWindows()
        } else if !shouldBeVisible {
            self.hideOverlayWindows()
        }
    }

    private func startObservingConfig() {
        self.isObservingConfig = true
        self.configObservationGeneration &+= 1
        let generation = self.configObservationGeneration
        self.lastAppliedSettings = self.config.snapshot
        self.observeNextConfigChange(generation: generation)
    }

    private func observeNextConfigChange(generation: UInt64) {
        guard self.isObservingConfig,
              self.configObservationGeneration == generation
        else {
            return
        }

        withObservationTracking {
            _ = self.config.snapshot
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isObservingConfig,
                      self.configObservationGeneration == generation
                else {
                    return
                }
                self.applyConfigChanges()
                self.observeNextConfigChange(generation: generation)
            }
        }
    }

    private func applyConfigChanges() {
        let settings = self.config.snapshot
        guard let previous = self.lastAppliedSettings, previous != settings else { return }
        self.lastAppliedSettings = settings

        let presentationChanged = previous.keyboard.presentation != settings.keyboard.presentation
        let keyboardAppearanceChanged =
            previous.appearance.keyboardThemeSelection
                != settings.appearance.keyboardThemeSelection
                || previous.appearance.customTheme.keyboard
                != settings.appearance.customTheme.keyboard
        let pointerAppearanceChanged =
            previous.appearance.pointerThemeSelection
                != settings.appearance.pointerThemeSelection
                || previous.appearance.customTheme.pointer
                != settings.appearance.customTheme.pointer

        if presentationChanged {
            self.currentKeyState?.clear()
            self.hideAndRemoveOverlayWindows()
            self.createKeyState()
            if self.keyMonitor?.isRunning == true {
                self.startObservingKeyState()
            }
        } else {
            self.updateKeyTimeout()
            self.updateHistorySettings()
            self.updateSingleSettings()
        }

        if previous.keyboard.enabled != settings.keyboard.enabled {
            self.currentKeyState?.clear()
            self.overlayShouldBeVisible = false
            self.updateOverlayVisibility()
        }

        if previous.displays != settings.displays
            || previous.keyboard.enabled != settings.keyboard.enabled
            || presentationChanged
        {
            self.reconcileOverlayWindows()
        }

        if previous.keyboard.opacity != settings.keyboard.opacity {
            self.updateOpacity()
        }

        if previous.keyboard.size != settings.keyboard.size
            || keyboardAppearanceChanged
        {
            for window in self.overlayWindows.values {
                window.refreshContentSize()
            }
        }

        if previous.pointer != settings.pointer
            || pointerAppearanceChanged
            || previous.pet != settings.pet
            || previous.general.enabled != settings.general.enabled
        {
            self.ensurePointerMonitoring()
            self.refreshPointer()
        }

        if previous.keyboard.enabled != settings.keyboard.enabled
            || previous.pet.enabled != settings.pet.enabled
            || previous.general.enabled != settings.general.enabled
        {
            self.ensureKeyboardMonitoring()
        }

        if previous.pet != settings.pet
            || previous.displays != settings.displays
            || previous.general.enabled != settings.general.enabled
        {
            self.petController.refresh()
        }
    }

    private func startObservingSecureInput() {
        self.secureInputTask?.cancel()
        self.secureInputTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let isEnabled = IsSecureEventInputEnabled()
                if isEnabled != self.secureInputEnabled {
                    self.handleSecureInputChanged(isEnabled)
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func startObservingMonitorHealth() {
        self.monitorHealthTask?.cancel()
        self.monitorHealthTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                guard self.config.general.enabled else {
                    self.stopPointerMonitoring()
                    continue
                }
                if self.needsKeyboardMonitoring,
                   self.keyMonitor?.isRunning != true
                {
                    self.resetTransientInputState()
                    let permissionReady = await Task.detached(priority: .utility) {
                        InputMonitoringPermission.isReady()
                    }.value
                    guard !Task.isCancelled else { return }
                    if permissionReady {
                        self.keyMonitor?.stop()
                        self.keyMonitor = self.makeKeyMonitor()
                        self.ensureKeyboardMonitoring()
                    } else {
                        self.permission.startPolling()
                    }
                } else if !self.needsKeyboardMonitoring,
                          self.keyMonitor?.isRunning == true
                {
                    self.stopKeyboardMonitoring()
                }
                self.ensurePointerMonitoring()
            }
        }
    }

    private func handleSecureInputChanged(_ isEnabled: Bool) {
        self.secureInputEnabled = isEnabled
        self.petController.handleSecureInputChanged(isEnabled)
        guard isEnabled else { return }

        self.currentKeyState?.clear()
        self.overlayShouldBeVisible = false
        self.hideOverlayWindows()
        let strings = StudioStrings(languageCode: self.config.general.language.studioLanguageCode)
        self.showHUD(text: strings["hud.secureInput"], kind: .privacy)
    }

    // MARK: - Screen Observation

    private func startObservingScreens() {
        // Observe screen parameter changes (monitor connect/disconnect)
        self.screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreensChanged()
            }
        }

        // Observe active app changes (for Auto mode)
        self.workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .followPointer = self.config.displays.target {
                    self.reconcileOverlayWindows()
                }
            }
        }

        self.activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pointerController.handleActiveSpaceChanged()
            }
        }

        self.globalSwipeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .swipe) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleNavigationSwipe(event)
            }
        }

        self.localSwipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleNavigationSwipe(event)
            }
            return event
        }

        self.placementEditorOpenObserver = NotificationCenter.default.addObserver(
            forName: .displayPlacementEditorDidOpen,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.placementEditorActive = true
                self?.hideOverlayWindows()
            }
        }

        self.placementEditorCloseObserver = NotificationCenter.default.addObserver(
            forName: .displayPlacementEditorDidClose,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.placementEditorActive = false
                guard self.overlayShouldBeVisible else { return }
                self.showOverlayWindows()
            }
        }

        self.placementEditorSaveObserver = NotificationCenter.default.addObserver(
            forName: .displayPlacementEditorDidSave,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let strings = StudioStrings(
                    languageCode: self.config.general.language.studioLanguageCode)
                self.showHUD(text: strings["hud.positionSaved"], kind: .positive)
            }
        }

        self.sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resetTransientInputState()
            }
        }

        self.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.resetTransientInputState()
                self.keyMonitor?.emitCurrentModifiers()
                self.stopPointerMonitoring()
                self.ensurePointerMonitoring()
            }
        }
    }

    private func stopObservingScreens() {
        if let observer = self.screenParametersObserver {
            NotificationCenter.default.removeObserver(observer)
            self.screenParametersObserver = nil
        }
        if let observer = self.workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.workspaceObserver = nil
        }
        if let observer = self.activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.activeSpaceObserver = nil
        }
        if let monitor = self.globalSwipeMonitor {
            NSEvent.removeMonitor(monitor)
            self.globalSwipeMonitor = nil
        }
        if let monitor = self.localSwipeMonitor {
            NSEvent.removeMonitor(monitor)
            self.localSwipeMonitor = nil
        }
        if let observer = self.placementEditorOpenObserver {
            NotificationCenter.default.removeObserver(observer)
            self.placementEditorOpenObserver = nil
        }
        if let observer = self.placementEditorCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            self.placementEditorCloseObserver = nil
        }
        if let observer = self.placementEditorSaveObserver {
            NotificationCenter.default.removeObserver(observer)
            self.placementEditorSaveObserver = nil
        }
        if let observer = self.sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.sleepObserver = nil
        }
        if let observer = self.wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.wakeObserver = nil
        }
    }

    private func handleScreensChanged() {
        self.reconcileOverlayWindows()
        self.petController.refresh()
    }

    private func handleNavigationSwipe(_ event: NSEvent) {
        guard abs(event.deltaX) > abs(event.deltaY), event.deltaX != 0 else { return }
        self.pointerController.handleNavigationSwipe(
            cancelled: event.phase.contains(.cancelled))
    }

    private func resetTransientInputState() {
        self.currentKeyState?.clear()
        self.pointerController.clear()
        self.pointerController.refresh()
        self.petController.resetTransientState()
        self.overlayShouldBeVisible = false
        self.hideOverlayWindows()
    }
}

extension OverlayController {
    private var preferredPetKeyboardFrame: NSRect? {
        if let pointerDisplay = ConnectedDisplays.display(containing: NSEvent.mouseLocation),
           let frame = self.overlayWindows[pointerDisplay.id]?.visibleContentFrame
        {
            return frame
        }
        if let frame = self.activeKeyboardDisplays.lazy
            .compactMap({ self.overlayWindows[$0.id]?.visibleContentFrame })
            .first
        {
            return frame
        }

        guard let display = self.targetDisplays().first else { return nil }
        let visibleFrame = display.screen.visibleFrame
        let placement = self.config.displays.placement(for: display.id)
        let point: CGPoint
        switch placement {
        case let .custom(center, _):
            point = CGPoint(
                x: visibleFrame.minX + CGFloat(center.x) * visibleFrame.width,
                y: visibleFrame.minY + CGFloat(center.y) * visibleFrame.height)
        case let .anchor(position, horizontalOffset, verticalOffset):
            let x = switch position {
            case .topLeft, .centerLeft, .bottomLeft:
                visibleFrame.minX + CGFloat(horizontalOffset)
            case .topCenter, .bottomCenter:
                visibleFrame.midX
            case .topRight, .centerRight, .bottomRight:
                visibleFrame.maxX - CGFloat(horizontalOffset)
            }
            let y = switch position {
            case .bottomLeft, .bottomCenter, .bottomRight:
                visibleFrame.minY + CGFloat(verticalOffset)
            case .centerLeft, .centerRight:
                visibleFrame.midY
            case .topLeft, .topCenter, .topRight:
                visibleFrame.maxY - CGFloat(verticalOffset)
            }
            point = CGPoint(x: x, y: y)
        }
        return NSRect(origin: point, size: .zero)
    }

    private var needsKeyboardMonitoring: Bool {
        self.config.general.enabled
            && (self.config.keyboard.enabled || self.config.pet.enabled)
    }

    private var needsPointerMonitoring: Bool {
        let petNeedsPointer = self.config.pet.enabled
            && self.config.pet.visibility == .always
            && (self.config.pet.watchCursor || self.config.pet.huntCursor)
        return self.config.general.enabled
            && (self.config.pointer.enabled || petNeedsPointer)
    }

    private func ensureKeyboardMonitoring() {
        guard self.needsKeyboardMonitoring else {
            self.stopKeyboardMonitoring()
            return
        }
        guard self.keyMonitor?.isRunning != true else { return }

        if self.keyMonitor == nil {
            self.keyMonitor = self.makeKeyMonitor()
        }
        let started = self.keyMonitor?.start() ?? false
        if started {
            print("[Keypress] KeyMonitor started successfully")
            self.keyMonitor?.emitCurrentModifiers()
            self.startObservingKeyState()
            return
        }

        if KeyMonitor.hasInputMonitoringPermission() {
            print(
                "[Keypress] ERROR: KeyMonitor.start() failed despite having permissions - system resource issue")
        } else {
            print("[Keypress] KeyMonitor.start() waiting for explicit Input Monitoring access")
        }
        self.permission.startPolling()
    }

    private func stopKeyboardMonitoring() {
        self.keyMonitor?.stop()
        self.isObservingKeyState = false
        self.keyStateObservationGeneration &+= 1
        self.secureInputTask?.cancel()
        self.secureInputTask = nil
        self.secureInputEnabled = false
        self.petController.handleSecureInputChanged(false)
        self.currentKeyState?.clear()
        self.overlayShouldBeVisible = false
        self.hideOverlayWindows()
        self.stopPermissionPollingIfUnused()
    }

    private func stopPermissionPollingIfUnused() {
        guard !self.needsKeyboardMonitoring, !self.needsPointerMonitoring else { return }
        self.permission.stopPolling()
    }
}
