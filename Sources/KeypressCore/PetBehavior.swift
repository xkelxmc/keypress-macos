import Foundation

public enum PetAmbientActivity: String, CaseIterable, Sendable {
    case stretch
    case groom
    case playTail
}

public enum PetRuntimeState: Sendable, Equatable {
    case hidden
    case idle
    case sleepTransition(reverse: Bool)
    case sleeping
    case looking(direction: Int)
    case ambient(PetAmbientActivity)
    case pouncing(mirrored: Bool)
    case petting
    case typing
    case carried
    case settling

    public var priority: Int {
        switch self {
        case .hidden: 0
        case .idle, .sleeping: 1
        case .sleepTransition: 2
        case .ambient: 3
        case .looking: 4
        case .pouncing: 5
        case .petting: 6
        case .settling: 7
        case .typing: 8
        case .carried: 9
        }
    }

    public func canInterrupt(_ state: PetRuntimeState) -> Bool {
        if case .pouncing = state {
            return self == .typing || self == .carried
        }
        return self.priority >= state.priority
    }
}

public enum PetTypingRate {
    public static let sampleWindow: TimeInterval = 1.5
    public static let burstTimeout: TimeInterval = 0.5
    public static let minimumFPS = 6.0
    public static let maximumFPS = 18.0

    public static func framesPerSecond(
        timestamps: [TimeInterval],
        now: TimeInterval)
        -> Double
    {
        let recentCount = timestamps.lazy.count(where: {
            now - $0 >= 0 && now - $0 <= self.sampleWindow
        })
        let keysPerSecond = Double(recentCount) / self.sampleWindow
        let normalizedRate = ((keysPerSecond - 1) / 7).clamped(to: 0...1)
        return self.minimumFPS + normalizedRate * (self.maximumFPS - self.minimumFPS)
    }
}

public enum PetCursorTiming {
    public static let lookTimeout: TimeInterval = 1.2
}

public enum PetAnimationTiming {
    public static let reducedMotionOneShotDuration: TimeInterval = 0.24
}

public struct PetActivityScheduler: Sendable {
    private var cycleIndex = 0
    private var lastRandomActivity: PetAmbientActivity?

    public init() {}

    public mutating func next(
        mode: PetActivityMode,
        enabled: [PetAmbientActivity],
        randomValue: Int)
        -> PetAmbientActivity?
    {
        let available = PetAmbientActivity.allCases.filter(enabled.contains)
        guard !available.isEmpty else { return nil }

        switch mode {
        case .cycle:
            let activity = available[self.cycleIndex % available.count]
            self.cycleIndex = (self.cycleIndex + 1) % available.count
            return activity
        case .random:
            let candidates = available.count > 1
                ? available.filter { $0 != self.lastRandomActivity }
                : available
            let index = ((randomValue % candidates.count) + candidates.count) % candidates.count
            let activity = candidates[index]
            self.lastRandomActivity = activity
            return activity
        }
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
