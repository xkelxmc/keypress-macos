@preconcurrency import ApplicationServices
@preconcurrency import CoreFoundation
import Foundation
import KeypressCore

final class PointerInputMonitor: @unchecked Sendable {
    private static let continuousDeliveryInterval = Duration.milliseconds(8)

    private static let eventTypes: [CGEventType] = [
        .mouseMoved,
        .leftMouseDown,
        .leftMouseUp,
        .rightMouseDown,
        .rightMouseUp,
        .otherMouseDown,
        .otherMouseUp,
        .leftMouseDragged,
        .rightMouseDragged,
        .otherMouseDragged,
        .scrollWheel,
    ]

    private static let eventMask = eventTypes.reduce(CGEventMask(0)) { mask, eventType in
        mask | (CGEventMask(1) << eventType.rawValue)
    }

    private let handler: @MainActor @Sendable (PointerEvent) -> Void
    private let lock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var monitorThread: Thread?
    private var generation: UInt64 = 0
    private var running = false
    private var pendingMotionEvent: PointerEvent?
    private var pendingScrollEvent: PointerEvent?
    private var continuousDeliveryScheduled = false

    init(handler: @escaping @MainActor @Sendable (PointerEvent) -> Void) {
        self.handler = handler
    }

    deinit {
        self.stop()
    }

    var isRunning: Bool {
        self.lock.withLock {
            guard self.running, let eventTap = self.eventTap else { return false }
            return CGEvent.tapIsEnabled(tap: eventTap)
        }
    }

    @discardableResult
    func start() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }

        guard !self.running else { return true }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: Self.eventMask,
            callback: Self.eventCallback,
            userInfo: refcon)
        else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        self.eventTap = tap
        self.runLoopSource = source
        self.running = true
        self.generation &+= 1
        self.pendingMotionEvent = nil
        self.pendingScrollEvent = nil
        self.continuousDeliveryScheduled = false
        let generation = self.generation

        let thread = Thread { [weak self] in
            guard let self else { return }

            let runLoop = CFRunLoopGetCurrent()
            let shouldRun = self.lock.withLock {
                guard self.running, self.generation == generation else {
                    return false
                }
                self.runLoop = runLoop
                CFRunLoopAddSource(runLoop, source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                return true
            }
            guard shouldRun else { return }

            CFRunLoopRun()
            CFRunLoopRemoveSource(runLoop, source, .commonModes)

            self.lock.withLock {
                guard self.generation == generation else { return }
                self.running = false
                self.eventTap = nil
                self.runLoopSource = nil
                self.runLoop = nil
                self.monitorThread = nil
                self.pendingMotionEvent = nil
                self.pendingScrollEvent = nil
                self.continuousDeliveryScheduled = false
            }
        }

        thread.name = "PointerInputMonitor"
        thread.qualityOfService = .userInteractive
        self.monitorThread = thread
        thread.start()
        return true
    }

    func stop() {
        self.lock.lock()
        guard self.running else {
            self.lock.unlock()
            return
        }

        self.running = false
        self.generation &+= 1
        let tap = self.eventTap
        let runLoop = self.runLoop

        self.eventTap = nil
        self.runLoopSource = nil
        self.runLoop = nil
        self.monitorThread = nil
        self.pendingMotionEvent = nil
        self.pendingScrollEvent = nil
        self.continuousDeliveryScheduled = false
        self.lock.unlock()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<PointerInputMonitor>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            monitor.reenableEventTap()
            let recoveryEvent = PointerEvent(
                kind: .moved,
                location: PointerInputMonitor.appKitLocation(event),
                modifiers: event.flags,
                timestamp: TimeInterval(event.timestamp) / 1_000_000_000)
            monitor.enqueueContinuous(recoveryEvent)
            return Unmanaged.passUnretained(event)
        }

        guard let pointerEvent = PointerInputMonitor.pointerEvent(type: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }

        switch pointerEvent.kind {
        case .moved, .dragged, .scrolled:
            monitor.enqueueContinuous(pointerEvent)
        case .buttonDown, .buttonUp:
            monitor.enqueueDiscrete(pointerEvent)
        }
        return Unmanaged.passUnretained(event)
    }

    private func reenableEventTap() {
        let tap = self.lock.withLock {
            self.running ? self.eventTap : nil
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private static func pointerEvent(type: CGEventType, event: CGEvent) -> PointerEvent? {
        let kind: PointerEventKind

        switch type {
        case .mouseMoved:
            kind = .moved
        case .leftMouseDown:
            kind = .buttonDown(button: .left, clickCount: self.clickCount(event))
        case .rightMouseDown:
            kind = .buttonDown(button: .right, clickCount: self.clickCount(event))
        case .otherMouseDown:
            kind = .buttonDown(button: self.button(event), clickCount: self.clickCount(event))
        case .leftMouseUp:
            kind = .buttonUp(button: .left)
        case .rightMouseUp:
            kind = .buttonUp(button: .right)
        case .otherMouseUp:
            kind = .buttonUp(button: self.button(event))
        case .leftMouseDragged:
            kind = .dragged(button: .left)
        case .rightMouseDragged:
            kind = .dragged(button: .right)
        case .otherMouseDragged:
            kind = .dragged(button: self.button(event))
        case .scrollWheel:
            let isPrecise = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            kind = .scrolled(
                deltaX: self.scrollDelta(event, axis: 2, isPrecise: isPrecise),
                deltaY: self.scrollDelta(event, axis: 1, isPrecise: isPrecise),
                isPrecise: isPrecise)
        default:
            return nil
        }

        return PointerEvent(
            kind: kind,
            location: self.appKitLocation(event),
            modifiers: event.flags,
            timestamp: TimeInterval(event.timestamp) / 1_000_000_000)
    }

    private func enqueueContinuous(_ event: PointerEvent) {
        let delivery: (generation: UInt64, shouldSchedule: Bool)? = self.lock.withLock {
            guard self.running else { return nil }

            switch event.kind {
            case .moved, .dragged:
                self.pendingMotionEvent = event
            case .scrolled:
                self.pendingScrollEvent = Self.mergingScroll(self.pendingScrollEvent, with: event)
            case .buttonDown, .buttonUp:
                return nil
            }

            let shouldSchedule = !self.continuousDeliveryScheduled
            self.continuousDeliveryScheduled = true
            return (self.generation, shouldSchedule)
        }

        guard let delivery, delivery.shouldSchedule else { return }
        let generation = delivery.generation
        Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self else { return }
            while !Task.isCancelled {
                guard let events = self.takeContinuousEvents(generation: generation) else {
                    return
                }
                if events.isEmpty {
                    if self.finishContinuousDeliveryIfIdle(generation: generation) {
                        return
                    }
                    continue
                }
                for event in events {
                    self.handler(event)
                }
                try? await Task.sleep(for: Self.continuousDeliveryInterval)
            }
        }
    }

    private func enqueueDiscrete(_ event: PointerEvent) {
        let delivery: (generation: UInt64, pending: [PointerEvent])? = self.lock.withLock {
            guard self.running else { return nil }
            let pending = [self.pendingMotionEvent, self.pendingScrollEvent].compactMap(\.self)
            self.pendingMotionEvent = nil
            self.pendingScrollEvent = nil
            return (self.generation, pending)
        }

        guard let delivery else { return }
        Task { @MainActor [weak self] in
            guard let self, self.accepts(generation: delivery.generation) else { return }
            for pendingEvent in delivery.pending {
                self.handler(pendingEvent)
            }
            self.handler(event)
        }
    }

    private func takeContinuousEvents(generation: UInt64) -> [PointerEvent]? {
        self.lock.withLock {
            guard self.running, self.generation == generation else {
                if self.generation == generation {
                    self.continuousDeliveryScheduled = false
                }
                return nil
            }

            let events = [self.pendingMotionEvent, self.pendingScrollEvent].compactMap(\.self)
            self.pendingMotionEvent = nil
            self.pendingScrollEvent = nil
            return events
        }
    }

    private func finishContinuousDeliveryIfIdle(generation: UInt64) -> Bool {
        self.lock.withLock {
            guard self.running, self.generation == generation else {
                return true
            }
            guard self.pendingMotionEvent == nil, self.pendingScrollEvent == nil else {
                return false
            }
            self.continuousDeliveryScheduled = false
            return true
        }
    }

    private func accepts(generation: UInt64) -> Bool {
        self.lock.withLock {
            self.running && self.generation == generation
        }
    }

    private static func mergingScroll(
        _ pending: PointerEvent?,
        with event: PointerEvent)
        -> PointerEvent
    {
        guard let pending,
              case let .scrolled(pendingX, pendingY, pendingPrecise) = pending.kind,
              case let .scrolled(deltaX, deltaY, isPrecise) = event.kind
        else {
            return event
        }

        return PointerEvent(
            kind: .scrolled(
                deltaX: pendingX + deltaX,
                deltaY: pendingY + deltaY,
                isPrecise: pendingPrecise || isPrecise),
            location: event.location,
            modifiers: event.modifiers,
            timestamp: event.timestamp)
    }

    private static func appKitLocation(_ event: CGEvent) -> CGPoint {
        event.unflippedLocation
    }

    private static func clickCount(_ event: CGEvent) -> Int {
        Int(event.getIntegerValueField(.mouseEventClickState))
    }

    private static func button(_ event: CGEvent) -> PointerButton {
        PointerButton(buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber))
    }

    private static func scrollDelta(
        _ event: CGEvent,
        axis: Int,
        isPrecise: Bool) -> Double
    {
        let fixedField: CGEventField = axis == 1
            ? .scrollWheelEventFixedPtDeltaAxis1
            : .scrollWheelEventFixedPtDeltaAxis2
        let pointField: CGEventField = axis == 1
            ? .scrollWheelEventPointDeltaAxis1
            : .scrollWheelEventPointDeltaAxis2

        if isPrecise {
            return event.getDoubleValueField(fixedField)
        }
        return Double(event.getIntegerValueField(pointField))
    }
}
