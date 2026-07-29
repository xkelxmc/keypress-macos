import AppKit
import KeypressCore
import Observation
import SwiftUI

enum OnboardingPhase: Equatable {
    case ceremony
    case steps
    case finishing
}

enum OnboardingPermissionState: Equatable {
    case idle
    case requesting
    case denied
    case granted
}

@MainActor
@Observable
final class OnboardingSession {
    let config: KeypressConfig
    let progress: OnboardingProgressStore
    let isReplay: Bool

    var phase: OnboardingPhase = .steps
    var step: OnboardingStep
    var ceremonyStage = 0
    var permissionState: OnboardingPermissionState = .idle
    var previewSymbols = [
        KeySymbol(id: "command-left", display: "⌘", isModifier: true),
        KeySymbol(id: "key-40", display: "K"),
    ]
    var pressedKeyIDs: Set<String> = []
    var pointerLocation = CGPoint(x: 0.5, y: 0.5)
    var reduceMotion = false
    var reduceTransparency = false

    @ObservationIgnored var deferAction: () -> Void = {}
    @ObservationIgnored var skipCeremonyAction: () -> Void = {}
    @ObservationIgnored var backAction: () -> Void = {}
    @ObservationIgnored var nextAction: () -> Void = {}
    @ObservationIgnored var grantPermissionAction: () -> Void = {}
    @ObservationIgnored var openSystemSettingsAction: () -> Void = {}
    @ObservationIgnored var toggleSoundAction: () -> Void = {}

    init(
        config: KeypressConfig,
        progress: OnboardingProgressStore,
        isReplay: Bool = false)
    {
        self.config = config
        self.progress = progress
        self.isReplay = isReplay
        self.step = isReplay ? .preview : progress.currentStep
        self.refreshAccessibilityOptions()
    }

    var canMoveNext: Bool {
        self.step != .permission || self.permissionState == .granted
    }

    var isSoundMuted: Bool {
        self.progress.soundMuted
    }

    func refreshAccessibilityOptions() {
        self.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        self.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    func updatePointer(location: CGPoint) {
        self.pointerLocation = location
    }

    func handleLocalKeyEvent(_ event: NSEvent) {
        let symbol = KeyCodeMapper.symbol(
            for: Int64(event.keyCode),
            modifiers: event.cgEvent?.flags ?? [],
            event: event.cgEvent)

        switch event.type {
        case .keyDown:
            guard self.acceptsPreviewInput, let symbol else { return }
            guard !event.isARepeat else { return }
            self.pressedKeyIDs.insert(symbol.id)
            self.appendPreviewSymbol(symbol)
        case .keyUp:
            guard let symbol else { return }
            self.pressedKeyIDs.remove(symbol.id)
        case .flagsChanged:
            guard let symbol else { return }
            if self.modifierIsPressed(keyCode: event.keyCode, flags: event.modifierFlags) {
                guard self.acceptsPreviewInput else { return }
                self.pressedKeyIDs.insert(symbol.id)
                self.appendPreviewSymbol(symbol)
            } else {
                self.pressedKeyIDs.remove(symbol.id)
            }
        default:
            break
        }
    }

    func resetPressedKeys() {
        self.pressedKeyIDs.removeAll()
    }

    private var acceptsPreviewInput: Bool {
        self.phase == .steps
            && self.step == .preview
    }

    private func appendPreviewSymbol(_ symbol: KeySymbol) {
        self.previewSymbols.removeAll { $0.id == symbol.id }
        self.previewSymbols.append(symbol)
        if self.previewSymbols.count > 5 {
            self.previewSymbols.removeFirst(self.previewSymbols.count - 5)
        }
    }

    private func modifierIsPressed(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        switch keyCode {
        case 0x36, 0x37:
            flags.contains(.command)
        case 0x38, 0x3C:
            flags.contains(.shift)
        case 0x3A, 0x3D:
            flags.contains(.option)
        case 0x3B, 0x3E:
            flags.contains(.control)
        case 0x3F:
            flags.contains(.function)
        default:
            false
        }
    }
}

@MainActor
final class OnboardingController {
    private enum PresentationContext: Equatable {
        case setup
        case replay
    }

    static let shared = OnboardingController()

    private let config = KeypressConfig.shared
    private let progress = OnboardingProgressStore.shared
    private let soundPlayer = OnboardingSoundPlayer()
    private var panels: [OnboardingPanel] = []
    private var session: OnboardingSession?
    private var localKeyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var activeSpaceObserver: NSObjectProtocol?
    private var appActivationObserver: NSObjectProtocol?
    private var appDeactivationObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    private var ceremonyTask: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?
    private var permissionRefreshTask: Task<Void, Never>?
    private var completionTask: Task<Void, Never>?
    private var cursorScreenTask: Task<Void, Never>?
    private var interactiveDisplayID: CGDirectDisplayID?
    private var awaitingPermissionReturn = false
    private var permissionSettingsDidDeactivate = false
    private var isSuspendedForSystemSettings = false
    private var presentationContext = PresentationContext.setup
    private(set) var isPresenting = false
    private var presentAction: () -> Void = {}
    private var completionAction: () -> Void = {}
    private var deferredAction: () -> Void = {}

    private init() {}

    func configure(
        onPresent: @escaping () -> Void,
        onComplete: @escaping () -> Void,
        onDeferred: @escaping () -> Void)
    {
        self.presentAction = onPresent
        self.completionAction = onComplete
        self.deferredAction = onDeferred
    }

    func show(playCeremony: Bool) {
        guard !self.progress.isCompleted else { return }
        self.present(playCeremony: playCeremony, context: .setup)
    }

    func replay() {
        guard !self.isPresenting else { return }
        if self.progress.isCompleted {
            self.present(playCeremony: true, context: .replay)
        } else {
            self.progress.move(to: .preview)
            self.present(playCeremony: true, context: .setup)
        }
    }

    private func present(
        playCeremony: Bool,
        context: PresentationContext)
    {
        guard !self.isPresenting else { return }
        self.presentAction()
        SettingsWindowController.shared.closeSettings()
        self.stopTransientTasks()
        self.presentationContext = context
        if context == .setup {
            self.progress.resume()
        }
        self.progress.refreshPermission()

        let session = OnboardingSession(
            config: self.config,
            progress: self.progress,
            isReplay: context == .replay)
        session.phase =
            playCeremony && session.step == .preview
                ? .ceremony
                : .steps
        if session.phase == .ceremony, session.reduceMotion {
            session.ceremonyStage = 3
        }
        session.permissionState = self.progress.permissionGranted ? .granted : .idle
        self.connectActions(to: session)
        self.session = session
        self.isPresenting = true
        self.isSuspendedForSystemSettings = false
        self.refreshPermissionAccurately(for: session)
        self.startObserving()
        self.rebuildPanels()
        self.installLocalKeyMonitor()
        self.startCursorScreenTracking()

        if session.phase == .ceremony {
            self.startCeremony()
        }
    }

    func continueFromSettings() {
        self.show(playCeremony: false)
    }

    private func connectActions(to session: OnboardingSession) {
        session.deferAction = { [weak self] in self?.deferSetup() }
        session.skipCeremonyAction = { [weak self] in self?.skipCeremony() }
        session.backAction = { [weak self] in self?.moveBack() }
        session.nextAction = { [weak self] in self?.moveNext() }
        session.grantPermissionAction = { [weak self] in self?.requestPermission() }
        session.openSystemSettingsAction = { [weak self] in self?.openSystemSettings() }
        session.toggleSoundAction = { [weak self] in self?.toggleSound() }
    }

    private func startCeremony() {
        guard let session = self.session else { return }

        if !self.progress.soundMuted {
            self.soundPlayer.play()
        }

        self.ceremonyTask = Task { @MainActor [weak self, weak session] in
            guard let self, let session else { return }

            if session.reduceMotion {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                self.skipCeremony()
                return
            }

            for (delay, stage) in [
                (600, 1),
                (700, 2),
                (1250, 3),
                (1150, 4),
                (1100, 5),
            ] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                session.ceremonyStage = stage
            }
            self.skipCeremony()
        }
    }

    private func skipCeremony() {
        guard let session = self.session, session.phase == .ceremony else { return }
        self.ceremonyTask?.cancel()
        self.ceremonyTask = nil
        self.soundPlayer.stop(fadeOut: true)

        withAnimation(session.reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.62, dampingFraction: 0.86)) {
            session.phase = .steps
        }
    }

    private func toggleSound() {
        self.progress.soundMuted.toggle()
        if self.progress.soundMuted {
            self.soundPlayer.stop(fadeOut: true)
        }
    }

    private func moveBack() {
        guard let session = self.session,
              let index = OnboardingStep.allCases.firstIndex(of: session.step),
              index > OnboardingStep.allCases.startIndex
        else {
            return
        }

        let previous = OnboardingStep.allCases[index - 1]
        self.move(to: previous)
    }

    private func moveNext() {
        guard let session = self.session, session.canMoveNext else { return }

        if session.step == .pointer {
            self.complete()
            return
        }

        guard let index = OnboardingStep.allCases.firstIndex(of: session.step) else { return }
        self.move(to: OnboardingStep.allCases[index + 1])
    }

    private func move(to step: OnboardingStep) {
        guard let session = self.session else { return }
        session.resetPressedKeys()
        if self.presentationContext == .setup {
            self.progress.move(to: step)
        }

        withAnimation(session.reduceMotion ? .easeOut(duration: 0.18) : .spring(
            response: 0.48,
            dampingFraction: 0.88))
        {
            session.step = step
        }

        if step == .permission {
            self.progress.refreshPermission()
            session.permissionState = self.progress.permissionGranted ? .granted : .idle
            self.refreshPermissionAccurately(for: session)
        }
    }

    private func requestPermission() {
        guard let session = self.session else { return }
        session.permissionState = .requesting
        self.suspendForSystemSettings()

        let alreadyGranted = InputMonitoringPermission.request()
        if alreadyGranted {
            self.handlePermissionReturn(permissionGranted: true)
            return
        }

        self.permissionTask = Task { @MainActor [weak self] in
            let permissionGranted = await Task.detached(priority: .userInitiated) {
                InputMonitoringPermission.isReady()
            }.value
            guard !Task.isCancelled, let self else { return }
            self.permissionTask = nil

            if permissionGranted {
                self.handlePermissionReturn(permissionGranted: true)
            } else {
                self.awaitingPermissionReturn = true
                InputMonitoringPermission.openSettings()
                self.startPermissionReturnGracePolling()
            }
        }
    }

    private func openSystemSettings() {
        guard let session = self.session else { return }
        session.permissionState = .requesting
        self.suspendForSystemSettings()
        self.awaitingPermissionReturn = true
        InputMonitoringPermission.openSettings()
        self.startPermissionReturnGracePolling()
    }

    private func suspendForSystemSettings() {
        self.session?.resetPressedKeys()
        self.permissionRefreshTask?.cancel()
        self.permissionRefreshTask = nil
        self.stopCursorScreenTracking()
        self.permissionSettingsDidDeactivate = false
        self.isSuspendedForSystemSettings = true
        for panel in self.panels {
            panel.orderOut(nil)
        }
    }

    private func startPermissionReturnGracePolling() {
        self.permissionTask?.cancel()
        self.permissionTask = Task { @MainActor [weak self] in
            var activeCheckCount = 0
            var returnCheckCount = 0

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled, let self else { return }

                guard NSApp.isActive else {
                    self.permissionSettingsDidDeactivate = true
                    activeCheckCount = 0
                    continue
                }

                activeCheckCount += 1
                guard self.permissionSettingsDidDeactivate || activeCheckCount >= 18 else { continue }

                let permissionGranted = await Task.detached(priority: .userInitiated) {
                    InputMonitoringPermission.isReady()
                }.value
                guard !Task.isCancelled else { return }
                returnCheckCount += 1
                guard permissionGranted || returnCheckCount >= 6 else { continue }
                self.handlePermissionReturn(permissionGranted: permissionGranted)
                return
            }
        }
    }

    private func refreshPermissionAccurately(for session: OnboardingSession) {
        self.permissionRefreshTask?.cancel()
        self.permissionRefreshTask = Task { @MainActor [weak self, weak session] in
            let permissionGranted = await Task.detached(priority: .userInitiated) {
                InputMonitoringPermission.isReady()
            }.value
            guard !Task.isCancelled,
                  let self,
                  let session,
                  self.session === session
            else {
                return
            }

            self.progress.updatePermission(permissionGranted)
            if session.step == .permission,
               session.permissionState != .requesting
            {
                session.permissionState = permissionGranted ? .granted : .idle
            }
        }
    }

    private func handlePermissionReturn(permissionGranted: Bool) {
        guard self.isPresenting, let session = self.session else { return }
        self.permissionTask?.cancel()
        self.permissionTask = nil
        self.awaitingPermissionReturn = false
        self.permissionSettingsDidDeactivate = false
        self.isSuspendedForSystemSettings = false
        self.progress.updatePermission(permissionGranted)
        self.rebuildPanels()
        self.startCursorScreenTracking()

        if self.progress.permissionGranted {
            session.permissionState = .granted
        } else {
            session.permissionState = .denied
        }
    }

    private func deferSetup() {
        if self.presentationContext == .setup {
            self.progress.deferSetup(config: self.config)
        }
        self.dismiss()
        self.deferredAction()
    }

    private func complete() {
        guard let session = self.session else { return }
        session.phase = .finishing
        self.completionTask = Task { @MainActor [weak self, weak session] in
            let permissionGranted = await Task.detached(priority: .userInitiated) {
                InputMonitoringPermission.isReady()
            }.value
            guard !Task.isCancelled, let self, let session else { return }
            self.progress.updatePermission(permissionGranted)
            guard permissionGranted else {
                self.returnToDeniedPermissionStep(session)
                return
            }

            let delay = session.reduceMotion ? 240 : 900
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }

            let permissionStillGranted = await Task.detached(priority: .userInitiated) {
                InputMonitoringPermission.isReady()
            }.value
            guard !Task.isCancelled else { return }
            self.progress.updatePermission(permissionStillGranted)
            guard permissionStillGranted else {
                self.returnToDeniedPermissionStep(session)
                return
            }

            if self.presentationContext == .setup {
                self.progress.complete(config: self.config)
            }
            self.dismiss()
            self.completionAction()
        }
    }

    private func returnToDeniedPermissionStep(_ session: OnboardingSession) {
        self.completionTask?.cancel()
        self.completionTask = nil
        session.resetPressedKeys()
        session.permissionState = .denied
        if self.presentationContext == .setup {
            self.progress.move(to: .permission)
        }

        withAnimation(session.reduceMotion ? .easeOut(duration: 0.18) : .spring(
            response: 0.48,
            dampingFraction: 0.88))
        {
            session.phase = .steps
            session.step = .permission
        }
    }

    private func dismiss() {
        self.stopTransientTasks()
        self.stopObserving()
        self.session?.resetPressedKeys()
        for panel in self.panels {
            panel.orderOut(nil)
        }
        self.panels.removeAll()
        self.session = nil
        self.isPresenting = false
        self.isSuspendedForSystemSettings = false
        self.interactiveDisplayID = nil
        self.awaitingPermissionReturn = false
        self.permissionSettingsDidDeactivate = false
        self.presentationContext = .setup
        self.soundPlayer.stop(fadeOut: false)
    }

    private func stopTransientTasks() {
        self.ceremonyTask?.cancel()
        self.ceremonyTask = nil
        self.permissionTask?.cancel()
        self.permissionTask = nil
        self.permissionRefreshTask?.cancel()
        self.permissionRefreshTask = nil
        self.completionTask?.cancel()
        self.completionTask = nil
        self.stopCursorScreenTracking()
    }

    private func rebuildPanels() {
        guard self.isPresenting,
              !self.isSuspendedForSystemSettings,
              let session = self.session
        else {
            return
        }

        for panel in self.panels {
            panel.orderOut(nil)
        }
        self.panels.removeAll()

        let activeScreen = self.screenAtCursor()
        self.interactiveDisplayID = self.displayID(for: activeScreen)

        for screen in NSScreen.screens {
            let isInteractive = screen == activeScreen
            let panel = OnboardingPanel(
                screen: screen,
                isInteractive: isInteractive,
                session: session)
            self.panels.append(panel)

            if isInteractive {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFrontRegardless()
            }
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func startCursorScreenTracking() {
        self.stopCursorScreenTracking()
        self.cursorScreenTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                guard self.isPresenting, !self.isSuspendedForSystemSettings else { continue }

                let displayID = self.displayID(for: self.screenAtCursor())
                guard displayID != self.interactiveDisplayID else { continue }
                self.rebuildPanels()
            }
        }
    }

    private func stopCursorScreenTracking() {
        self.cursorScreenTask?.cancel()
        self.cursorScreenTask = nil
    }

    private func screenAtCursor() -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func displayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen?.deviceDescription[screenNumberKey] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    private func installLocalKeyMonitor() {
        guard self.localKeyMonitor == nil else { return }
        self.localKeyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged])
        { [weak self] event in
            let shouldConsume = MainActor.assumeIsolated {
                guard let self, let session = self.session else { return false }
                if event.type == .keyDown, event.keyCode == 0x35 {
                    if session.phase != .finishing {
                        self.deferSetup()
                    }
                    return true
                }
                if event.type == .keyDown,
                   event.keyCode == 0x31,
                   session.phase == .ceremony,
                   !event.modifierFlags.contains(.command),
                   !event.modifierFlags.contains(.control),
                   !event.modifierFlags.contains(.option),
                   !(NSWorkspace.shared.isVoiceOverEnabled
                       && event.modifierFlags.contains(.capsLock))
                {
                    self.skipCeremony()
                    return true
                }

                let consumesPreviewInput =
                    session.phase == .steps
                        && session.step == .preview
                session.handleLocalKeyEvent(event)
                return consumesPreviewInput
                    && !self.isPreviewNavigationEvent(event)
            }
            return shouldConsume ? nil : event
        }
    }

    private func isPreviewNavigationEvent(_ event: NSEvent) -> Bool {
        if event.type == .flagsChanged {
            return true
        }
        if (NSWorkspace.shared.isVoiceOverEnabled
            && event.modifierFlags.contains(.capsLock))
            || event.modifierFlags.contains([.control, .option])
        {
            return true
        }
        return [UInt16(0x24), 0x30, 0x31, 0x4C, 0x7B, 0x7C, 0x7D, 0x7E]
            .contains(event.keyCode)
    }

    private func startObserving() {
        guard self.screenObserver == nil else { return }

        self.screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildPanels() }
        }

        self.activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildPanels() }
        }

        self.appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.awaitingPermissionReturn else { return }
                self.startPermissionReturnGracePolling()
            }
        }

        self.appDeactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                if self?.awaitingPermissionReturn == true {
                    self?.permissionSettingsDidDeactivate = true
                }
                self?.session?.resetPressedKeys()
            }
        }

        self.accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.session?.refreshAccessibilityOptions()
            }
        }
    }

    private func stopObserving() {
        if let localKeyMonitor = self.localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let screenObserver = self.screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        if let activeSpaceObserver = self.activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
            self.activeSpaceObserver = nil
        }
        if let appActivationObserver = self.appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
            self.appActivationObserver = nil
        }
        if let appDeactivationObserver = self.appDeactivationObserver {
            NotificationCenter.default.removeObserver(appDeactivationObserver)
            self.appDeactivationObserver = nil
        }
        if let accessibilityObserver = self.accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
            self.accessibilityObserver = nil
        }
    }
}

@MainActor
private final class OnboardingPanel: NSPanel {
    private let interactive: Bool

    override var canBecomeKey: Bool {
        get { self.interactive }
        set {}
    }

    override var canBecomeMain: Bool {
        get { self.interactive }
        set {}
    }

    init(
        screen: NSScreen,
        isInteractive: Bool,
        session: OnboardingSession)
    {
        self.interactive = isInteractive
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)

        self.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.isMovable = false
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.ignoresMouseEvents = !isInteractive
        self.acceptsMouseMovedEvents = isInteractive
        self.animationBehavior = .none
        self.appearance = NSAppearance(named: .darkAqua)

        let strings = StudioStrings(languageCode: session.config.general.language.studioLanguageCode)
        self.contentView = NSHostingView(
            rootView: OnboardingRootView(
                session: session,
                isInteractive: isInteractive)
                .environment(\.studioStrings, strings)
                .environment(\.locale, strings.locale)
                .preferredColorScheme(.dark))
        self.setFrame(screen.frame, display: false)
    }
}
