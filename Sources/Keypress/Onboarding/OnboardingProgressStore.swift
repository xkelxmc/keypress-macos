import Foundation
import KeypressCore
import Observation

enum OnboardingStep: Int, CaseIterable {
    case preview
    case permission
    case keyboard
    case pointer
}

@MainActor
@Observable
final class OnboardingProgressStore {
    static let shared = OnboardingProgressStore()
    static let currentVersion = 1

    private enum Key {
        static let completedVersion = "onboarding.completedVersion"
        static let currentStep = "onboarding.currentStep"
        static let deferred = "onboarding.deferred"
        static let soundMuted = "onboarding.soundMuted"
    }

    private let defaults: UserDefaults

    private(set) var completedVersion: Int {
        didSet { self.defaults.set(self.completedVersion, forKey: Key.completedVersion) }
    }

    var currentStep: OnboardingStep {
        didSet { self.defaults.set(self.currentStep.rawValue, forKey: Key.currentStep) }
    }

    private(set) var deferred: Bool {
        didSet { self.defaults.set(self.deferred, forKey: Key.deferred) }
    }

    var soundMuted: Bool {
        didSet { self.defaults.set(self.soundMuted, forKey: Key.soundMuted) }
    }

    private(set) var permissionGranted: Bool

    var isCompleted: Bool {
        self.completedVersion >= Self.currentVersion
    }

    var shouldPresentAutomatically: Bool {
        !self.isCompleted && !self.deferred
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.completedVersion = defaults.integer(forKey: Key.completedVersion)
        self.currentStep =
            OnboardingStep(rawValue: defaults.integer(forKey: Key.currentStep))
            ?? .preview
        self.deferred = defaults.bool(forKey: Key.deferred)
        self.soundMuted = defaults.bool(forKey: Key.soundMuted)
        self.permissionGranted = Self.inputMonitoringIsReady
    }

    func needsSetup(config: KeypressConfig) -> Bool {
        !self.isCompleted && !(self.permissionGranted && config.general.enabled)
    }

    func refreshPermission() {
        self.permissionGranted = InputMonitoringPermission.check()
    }

    func updatePermission(_ permissionGranted: Bool) {
        self.permissionGranted = permissionGranted
    }

    func reconcileReadyState(
        config: KeypressConfig,
        onboardingIsPresenting: Bool)
    {
        self.refreshPermission()
        guard !onboardingIsPresenting,
              !self.isCompleted,
              self.permissionGranted,
              config.general.enabled
        else {
            return
        }

        self.completedVersion = Self.currentVersion
        self.deferred = false
    }

    func resume() {
        self.deferred = false
    }

    func move(to step: OnboardingStep) {
        self.currentStep = step
    }

    func deferSetup(config: KeypressConfig) {
        self.deferred = true
        config.general.enabled = false
        config.flushPersistence()
    }

    func complete(config: KeypressConfig) {
        self.completedVersion = Self.currentVersion
        self.deferred = false
        config.general.enabled = true
        config.flushPersistence()
    }

    private static var inputMonitoringIsReady: Bool {
        InputMonitoringPermission.check()
    }
}
