import AppKit
import KeypressCore
import SwiftUI

@MainActor
struct PetSettingsPane: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig

    var body: some View {
        StudioPreviewPage(
            titleKey: "pet.title",
            subtitleKey: "pet.subtitle")
        {
            PetSettingsPreview(config: self.config)
        } content: {
            FeatureToggleCard(
                titleKey: "pet.enabled",
                subtitleKey: "pet.enabled.subtitle",
                systemImage: "cat.fill",
                tint: .orange,
                isOn: self.$config.pet.enabled)

            if self.config.pet.enabled {
                InputPermissionBanner()
            }

            StudioCard("pet.presentation", systemImage: "eye.fill", tint: .orange) {
                SettingsRow("pet.visibility", subtitleKey: "pet.visibility.subtitle") {
                    Picker(
                        self.strings["pet.visibility"],
                        selection: self.$config.pet.visibility)
                    {
                        Text(self.strings["pet.visibility.always"]).tag(PetVisibility.always)
                        Text(self.strings["pet.visibility.typing"]).tag(PetVisibility.typingOnly)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                StudioDivider()

                SettingsRow("pet.size", subtitleKey: "pet.size.subtitle") {
                    HStack(spacing: 8) {
                        Slider(value: self.$config.pet.size, in: 84...180, step: 4)
                            .frame(width: 150)
                            .accessibilityLabel(self.strings["pet.size"])
                            .accessibilityValue(
                                "\(Int(self.config.pet.size)) \(self.strings["unit.points"])")
                        Text(Int(self.config.pet.size), format: .number)
                            .font(.caption.monospacedDigit())
                            .frame(width: 28, alignment: .trailing)
                        Text(self.strings["unit.points"])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!self.config.pet.enabled)

            if self.config.pet.enabled, self.config.pet.visibility == .typingOnly {
                Label(
                    self.strings["pet.typingOnly.behaviorHint"],
                    systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            StudioCard("pet.routine", systemImage: "sparkles", tint: .purple) {
                SettingsRow("pet.activityMode", subtitleKey: "pet.activityMode.subtitle") {
                    Picker(
                        self.strings["pet.activityMode"],
                        selection: self.$config.pet.activityMode)
                    {
                        Text(self.strings["pet.activityMode.cycle"]).tag(PetActivityMode.cycle)
                        Text(self.strings["pet.activityMode.random"]).tag(PetActivityMode.random)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }

                StudioDivider()
                self.behaviorToggle("pet.sleep", "pet.sleep.subtitle", self.$config.pet.sleep)
                StudioDivider()
                self.behaviorToggle("pet.stretch", "pet.stretch.subtitle", self.$config.pet.stretch)
                StudioDivider()
                self.behaviorToggle("pet.groom", "pet.groom.subtitle", self.$config.pet.groom)
                StudioDivider()
                self.behaviorToggle("pet.playTail", "pet.playTail.subtitle", self.$config.pet.playTail)
            }
            .disabled(!self.config.pet.enabled || self.config.pet.visibility == .typingOnly)

            StudioCard("pet.cursor", systemImage: "cursorarrow.motionlines", tint: .cyan) {
                self.behaviorToggle(
                    "pet.watchCursor",
                    "pet.watchCursor.subtitle",
                    self.$config.pet.watchCursor)
                StudioDivider()
                self.behaviorToggle(
                    "pet.huntCursor",
                    "pet.huntCursor.subtitle",
                    self.$config.pet.huntCursor)
            }
            .disabled(!self.config.pet.enabled || self.config.pet.visibility == .typingOnly)

            StudioCard("pet.interaction", systemImage: "hand.tap.fill", tint: .pink) {
                self.behaviorToggle(
                    "pet.petReaction",
                    "pet.petReaction.subtitle",
                    self.$config.pet.petReaction)
                    .disabled(self.config.pet.visibility == .typingOnly)

                StudioDivider()

                SettingsRow("pet.position", subtitleKey: "pet.position.subtitle") {
                    Button(self.strings["pet.position.reset"]) {
                        self.config.pet.placement = nil
                    }
                    .disabled(self.config.pet.placement == nil)
                }
            }
            .disabled(!self.config.pet.enabled)
        }
    }

    private func behaviorToggle(
        _ titleKey: String,
        _ subtitleKey: String,
        _ binding: Binding<Bool>)
        -> some View
    {
        SettingsRow(titleKey, subtitleKey: subtitleKey) {
            Toggle(self.strings[titleKey], isOn: binding)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(self.strings[titleKey])
        }
    }
}

@MainActor
private struct PetSettingsPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.studioStrings) private var strings
    let config: KeypressConfig
    @State private var state = PetRuntimeState.idle
    @State private var stateStartedAt = Date()
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.06, blue: 0.08),
                    Color(red: 0.10, green: 0.075, blue: 0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)

            if self.config.pet.enabled, self.state != .hidden {
                if self.canReact {
                    Button {
                        self.playReaction()
                    } label: {
                        self.sprite
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(self.strings["pet.petReaction"])
                    .transition(.opacity)
                } else {
                    self.sprite
                        .transition(.opacity)
                }
            } else {
                Label(
                    self.strings[
                        self.config.pet.enabled
                            ? "pet.preview.typing"
                            : "pet.preview.off"
                    ],
                    systemImage: self.config.pet.enabled ? "keyboard" : "cat")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(height: 174)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        }
        .onAppear {
            self.startPreview()
        }
        .onDisappear {
            self.previewTask?.cancel()
            self.previewTask = nil
        }
        .onChange(of: self.config.pet) {
            self.startPreview()
        }
        .onChange(of: self.reduceMotion) {
            self.startPreview()
        }
    }

    @ViewBuilder
    private var sprite: some View {
        if self.reduceMotion {
            if let definition = PetSpriteSheet.shared.definition(for: self.state),
               let image = PetSpriteSheet.shared.image(
                   for: self.state,
                   frameIndex: max(0, (definition.count - 1) / 2))
            {
                self.spriteImage(image)
            }
        } else {
            TimelineView(.animation(minimumInterval: 1 / 18)) { context in
                if let image = PetSpriteSheet.shared.image(
                    for: self.state,
                    frameIndex: self.frameIndex(at: context.date))
                {
                    self.spriteImage(image)
                }
            }
        }
    }

    private func spriteImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(PetSpriteMetrics.aspectRatio, contentMode: .fit)
            .frame(
                width: CGFloat(self.config.pet.size)
                    * 5 / 6
                    * PetSpriteMetrics.canvasToContentWidth)
            .accessibilityHidden(true)
    }

    private func frameIndex(at date: Date) -> Int {
        guard let definition = PetSpriteSheet.shared.definition(for: self.state) else { return 0 }
        let elapsed = max(0, date.timeIntervalSince(self.stateStartedAt))
        let frame = Int(elapsed * definition.fps)
        return definition.loop
            ? frame % definition.count
            : min(frame, definition.count - 1)
    }

    private func startPreview() {
        self.previewTask?.cancel()
        self.previewTask = nil
        guard self.config.pet.enabled else {
            self.setState(.hidden)
            return
        }

        self.previewTask = Task { @MainActor in
            var scheduler = PetActivityScheduler()
            while !Task.isCancelled {
                for state in self.previewStates(scheduler: &scheduler) {
                    guard !Task.isCancelled else { return }
                    self.setState(state)
                    try? await Task.sleep(for: .seconds(self.previewDuration(for: state)))
                }
            }
        }
    }

    private func previewStates(
        scheduler: inout PetActivityScheduler)
        -> [PetRuntimeState]
    {
        guard self.config.pet.visibility == .always else {
            return [.typing, .hidden]
        }

        var states: [PetRuntimeState] = [.idle, .typing]
        if self.config.pet.watchCursor {
            states.append(.looking(direction: 2))
        }
        if self.config.pet.huntCursor {
            states.append(.pouncing(mirrored: false))
        }
        let activities = PetAmbientActivity.allCases.filter(self.activityIsEnabled)
        if let activity = scheduler.next(
            mode: self.config.pet.activityMode,
            enabled: activities,
            randomValue: Int.random(in: 0...Int.max))
        {
            states.append(.ambient(activity))
        }
        if self.config.pet.sleep {
            states.append(.sleeping)
        }
        return states
    }

    private func activityIsEnabled(_ activity: PetAmbientActivity) -> Bool {
        switch activity {
        case .stretch: self.config.pet.stretch
        case .groom: self.config.pet.groom
        case .playTail: self.config.pet.playTail
        }
    }

    private var canReact: Bool {
        self.config.pet.petReaction
            && self.config.pet.visibility == .always
            && PetRuntimeState.petting.canInterrupt(self.state)
    }

    private func playReaction() {
        guard self.config.pet.enabled,
              self.canReact
        else {
            return
        }
        self.previewTask?.cancel()
        self.setState(.petting)
        self.previewTask = Task { @MainActor in
            try? await Task.sleep(
                for: .seconds(self.previewDuration(for: .petting)))
            guard !Task.isCancelled else { return }
            self.startPreview()
        }
    }

    private func previewDuration(for state: PetRuntimeState) -> TimeInterval {
        guard state != .hidden else { return 1 }
        if state == .typing {
            return PetTypingRate.burstTimeout
        }
        if case .looking = state {
            return PetCursorTiming.lookTimeout
        }
        guard let definition = PetSpriteSheet.shared.definition(for: state) else {
            return 2.2
        }
        if self.reduceMotion, !definition.loop {
            return PetAnimationTiming.reducedMotionOneShotDuration
        }
        guard !definition.loop else { return 2.2 }
        return Double(definition.count) / definition.fps
    }

    private func setState(_ state: PetRuntimeState) {
        self.state = state
        self.stateStartedAt = Date()
    }
}
