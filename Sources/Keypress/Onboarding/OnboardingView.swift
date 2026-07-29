import AppKit
import KeypressCore
import SwiftUI

@MainActor
struct OnboardingRootView: View {
    @Bindable var session: OnboardingSession
    let isInteractive: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OnboardingBackdrop(
                    finishing: self.session.phase == .finishing,
                    reduceMotion: self.session.reduceMotion,
                    reduceTransparency: self.session.reduceTransparency)

                if self.isInteractive {
                    switch self.session.phase {
                    case .ceremony:
                        OnboardingCeremonyView(session: self.session)
                            .transition(.opacity)
                    case .steps:
                        OnboardingCard(session: self.session)
                            .frame(
                                width: max(0, min(860, proxy.size.width - 48)),
                                height: max(0, min(710, proxy.size.height - 48)))
                            .transition(
                                self.session.reduceMotion
                                    ? .opacity
                                    : .scale(scale: 0.88).combined(with: .opacity))
                    case .finishing:
                        OnboardingFinishingView(
                            session: self.session,
                            availableSize: proxy.size)
                            .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingBackdrop: View {
    let finishing: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(self.reduceTransparency ? 0.78 : 0.58)

            if !self.reduceTransparency {
                RadialGradient(
                    colors: [
                        Color.indigo.opacity(0.19),
                        Color.cyan.opacity(0.055),
                        .clear,
                    ],
                    center: .center,
                    startRadius: 40,
                    endRadius: 720)
            }
        }
        .opacity(self.finishing ? 0 : 1)
        .animation(
            .easeInOut(duration: self.reduceMotion ? 0.16 : 0.72),
            value: self.finishing)
    }
}

@MainActor
private struct OnboardingCeremonyView: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var session: OnboardingSession

    private var pointerTheme: PointerTheme {
        self.session.config
            .effectiveTheme(isSystemDark: true)
            .pointer
    }

    var body: some View {
        ZStack {
            PointerThemeArtwork(theme: self.pointerTheme, size: 330)
                .opacity(self.session.ceremonyStage >= 3 ? 0.9 : 0)
                .scaleEffect(self.session.ceremonyStage >= 3 ? 1 : 0.52)
                .rotationEffect(.degrees(self.session.ceremonyStage >= 4 ? 18 : -12))
                .shadow(
                    color: self.pointerTheme.primaryColor.color.opacity(0.35),
                    radius: 44)

            Group {
                if self.session.reduceTransparency {
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .frame(
                width: self.session.ceremonyStage >= 4 ? 720 : 250,
                height: self.session.ceremonyStage >= 4 ? 490 : 190)
            .opacity(self.session.ceremonyStage >= 4 ? 0.82 : 0)
            .overlay {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .stroke(Color.white.opacity(0.13))
                    .opacity(self.session.ceremonyStage >= 4 ? 1 : 0)
            }

            VStack(spacing: 34) {
                HStack(spacing: 22) {
                    self.ceremonyKey(
                        KeySymbol(id: "command-left", display: "⌘", isModifier: true),
                        leading: true)
                    self.ceremonyKey(
                        KeySymbol(id: "key-40", display: "K"),
                        leading: false)
                }

                VStack(spacing: 9) {
                    Text(self.strings["onboarding.ceremony.title"])
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(self.strings["onboarding.ceremony.subtitle"])
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .opacity(self.session.ceremonyStage >= 3 ? 1 : 0)
                .offset(y: self.session.ceremonyStage >= 3 ? 0 : 18)
            }

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    self.session.skipCeremonyAction()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(self.strings["onboarding.next"])
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    self.session.skipCeremonyAction()
                }

            VStack {
                HStack {
                    Spacer()
                    OnboardingSoundButton(session: self.session)
                }
                Spacer()
                Text(self.strings["onboarding.ceremony.skip"])
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.56))
                    .padding(.bottom, 34)
            }
            .padding(32)
        }
        .animation(
            self.session.reduceMotion
                ? .easeOut(duration: 0.18)
                : .spring(response: 0.78, dampingFraction: 0.78),
            value: self.session.ceremonyStage)
    }

    private func ceremonyKey(_ symbol: KeySymbol, leading: Bool) -> some View {
        KeyCapView(
            symbol: symbol,
            config: self.session.config,
            isPressed: self.session.ceremonyStage == 2,
            delayPressAnimation: false)
            .scaleEffect(2.05)
            .frame(width: 150, height: 120)
            .rotationEffect(
                .degrees(
                    self.session.ceremonyStage >= 1
                        ? 0
                        : (leading ? -16 : 18)))
            .offset(
                x: self.session.ceremonyStage >= 1
                    ? 0
                    : (leading ? -180 : 180),
                y: self.session.ceremonyStage >= 1
                    ? 0
                    : (leading ? -70 : 65))
            .opacity(self.session.ceremonyStage >= 1 ? 1 : 0)
    }
}

@MainActor
private struct OnboardingCard: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var session: OnboardingSession

    var body: some View {
        VStack(spacing: 0) {
            self.header

            Divider()
                .opacity(0.38)

            Group {
                switch self.session.step {
                case .preview:
                    OnboardingPreviewStep(session: self.session)
                case .permission:
                    OnboardingPermissionStep(session: self.session)
                case .keyboard:
                    OnboardingKeyboardStep(session: self.session)
                case .pointer:
                    OnboardingPointerStep(session: self.session)
                }
            }
            .id(self.session.step)
            .transition(
                self.session.reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider()
                .opacity(0.38)

            self.footer
        }
        .foregroundStyle(.primary)
        .background {
            if self.session.reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13))
        }
        .shadow(color: .black.opacity(0.34), radius: 60, y: 24)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.strings["onboarding.product"])
                    .font(.headline)
                Text(self.stepEyebrow)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(
                self.strings[
                    self.session.isReplay
                        ? "action.done"
                        : "onboarding.later"
                ]) {
                    self.session.deferAction()
                }
                .buttonStyle(StudioHoverButtonStyle())
                    .foregroundStyle(.secondary)

            OnboardingSoundButton(session: self.session)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 17)
    }

    private var footer: some View {
        HStack {
            Button {
                self.session.backAction()
            } label: {
                Label(self.strings["onboarding.back"], systemImage: "chevron.left")
                    .font(.callout.weight(.semibold))
                    .frame(width: 92, alignment: .leading)
            }
            .buttonStyle(StudioHoverButtonStyle())
            .opacity(self.session.step == .preview ? 0 : 1)
            .disabled(self.session.step == .preview)

            Spacer()

            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    Circle()
                        .fill(step == self.session.step ? Color.accentColor : Color.secondary.opacity(0.26))
                        .frame(
                            width: self.session.reduceMotion
                                ? 7
                                : (step == self.session.step ? 9 : 6),
                            height: self.session.reduceMotion
                                ? 7
                                : (step == self.session.step ? 9 : 6))
                        .shadow(
                            color: step == self.session.step ? Color.accentColor.opacity(0.55) : .clear,
                            radius: 7)
                }
            }
            .animation(
                self.session.reduceMotion
                    ? .easeOut(duration: 0.16)
                    : .spring(response: 0.35, dampingFraction: 0.75),
                value: self.session.step)
            .accessibilityLabel(
                String(
                    format: self.strings["onboarding.progress"],
                    self.session.step.rawValue + 1,
                    OnboardingStep.allCases.count))

            Spacer()

            Button {
                self.session.nextAction()
            } label: {
                if self.session.step == .pointer {
                    HStack(spacing: 9) {
                        Text(
                            self.strings[
                                self.session.isReplay
                                    ? "action.done"
                                    : "onboarding.start"
                            ])
                            .font(.callout.weight(.semibold))
                        Image(systemName: self.session.isReplay ? "checkmark" : "arrow.right")
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(Color.accentColor.gradient, in: Capsule())
                    .foregroundStyle(.white)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 46, height: 46)
                        .background(Color.accentColor.gradient, in: Circle())
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(StudioHoverButtonStyle(showsHoverSurface: false))
            .disabled(!self.session.canMoveNext)
            .opacity(self.session.canMoveNext ? 1 : 0.36)
            .frame(minWidth: 92, alignment: .trailing)
            .accessibilityLabel(
                self.session.step == .pointer
                    ? self.strings[
                        self.session.isReplay
                            ? "action.done"
                            : "onboarding.start"
                    ]
                    : self.strings["onboarding.next"])
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
    }

    private var stepEyebrow: String {
        self.strings["onboarding.step.\(self.session.step.rawValue + 1)"]
    }
}

@MainActor
private struct OnboardingPreviewStep: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var session: OnboardingSession

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                OnboardingStepHeading(
                    title: self.strings["onboarding.preview.title"],
                    subtitle: self.strings["onboarding.preview.subtitle"])

                ZStack {
                    OnboardingPreviewSurface()

                    VStack(spacing: 18) {
                        HStack(spacing: 10) {
                            ForEach(self.session.previewSymbols) { symbol in
                                KeyCapView(
                                    symbol: symbol,
                                    config: self.session.config,
                                    isPressed:
                                    !self.session.reduceMotion
                                        && self.session.pressedKeyIDs.contains(symbol.id))
                                    .transition(
                                        self.session.reduceMotion
                                            ? .opacity
                                            : .scale.combined(with: .opacity))
                            }
                        }
                        .opacity(
                            self.session.reduceMotion && !self.session.pressedKeyIDs.isEmpty
                                ? 0.7
                                : 1)
                        .animation(
                            self.session.reduceMotion
                                ? .easeOut(duration: 0.1)
                                : .spring(response: 0.3, dampingFraction: 0.72),
                            value: self.session.previewSymbols)
                        .animation(
                            .easeOut(duration: 0.1),
                            value: self.session.pressedKeyIDs)
                        .accessibilityHidden(true)

                        Text(self.strings["onboarding.preview.hint"])
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    OnboardingInteractivePointerPreview(session: self.session)
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 8) {
                    self.capability("keyboard.fill", "onboarding.preview.keyboard", .blue)
                    self.capability("cursorarrow.motionlines", "onboarding.preview.pointer", .orange)
                    self.capability("cursorarrow.click.2", "onboarding.preview.clicks", .pink)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 18)
        }
    }

    private func capability(_ image: String, _ key: String, _ color: Color) -> some View {
        Label(self.strings[key], systemImage: image)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(color.opacity(0.1), in: Capsule())
    }
}

@MainActor
private struct OnboardingInteractivePointerPreview: View {
    @Bindable var session: OnboardingSession
    @State private var pointerLocation = CGPoint(x: 0.5, y: 0.5)
    @State private var isPointerInside = false
    @State private var isPointerPressed = false
    @State private var pointerResetTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PointerThemeArtwork(theme: self.pointerTheme, size: 62)
                    .scaleEffect(
                        self.session.reduceMotion
                            ? 1
                            : (self.isPointerPressed ? 0.78 : 1))
                    .opacity(
                        self.isPointerInside
                            ? (self.session.reduceMotion && self.isPointerPressed ? 0.7 : 1)
                            : 0)
                    .animation(
                        self.session.reduceMotion
                            ? .easeOut(duration: 0.08)
                            : .spring(response: 0.26, dampingFraction: 0.66),
                        value: self.isPointerPressed)
                    .position(
                        x: self.pointerLocation.x * proxy.size.width,
                        y: self.pointerLocation.y * proxy.size.height)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case let .active(location):
                    self.pointerLocation = self.normalized(location, in: proxy.size)
                    self.isPointerInside = true
                case .ended:
                    self.pointerResetTask?.cancel()
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        self.isPointerPressed = false
                        self.isPointerInside = false
                    }
                    self.session.updatePointer(location: self.pointerLocation)
                }
            }
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                    self.pointerLocation = self.normalized(value.location, in: proxy.size)
                    self.session.updatePointer(location: self.pointerLocation)
                    self.playPointerPress()
                })
        }
        .onDisappear {
            self.pointerResetTask?.cancel()
        }
    }

    private var pointerTheme: PointerTheme {
        self.session.config
            .effectiveTheme(isSystemDark: true)
            .pointer
    }

    private func normalized(_ location: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(location.x / max(size.width, 1), 0), 1),
            y: min(max(location.y / max(size.height, 1), 0), 1))
    }

    private func playPointerPress() {
        self.pointerResetTask?.cancel()
        self.isPointerPressed = true
        self.pointerResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self.isPointerPressed = false
        }
    }
}

@MainActor
private struct OnboardingPermissionStep: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var session: OnboardingSession

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 22) {
                    OnboardingStepHeading(
                        title: self.strings["onboarding.permission.title"],
                        subtitle: self.strings["onboarding.permission.subtitle"])

                    Spacer(minLength: 0)

                    ZStack {
                        Circle()
                            .fill(self.statusColor.opacity(0.1))
                            .frame(width: 146, height: 146)
                        Circle()
                            .stroke(self.statusColor.opacity(0.22), lineWidth: 1)
                            .frame(width: 118, height: 118)
                        Image(systemName: self.statusImage)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(self.statusColor)
                            .font(.system(size: 52, weight: .medium))
                            .contentTransition(.symbolEffect(.replace))
                    }

                    VStack(alignment: .leading, spacing: 11) {
                        self.privacyLine("lock.shield.fill", "onboarding.permission.local")
                        self.privacyLine("externaldrive.badge.xmark", "onboarding.permission.storage")
                        self.privacyLine("eye.slash.fill", "onboarding.permission.secure")
                    }
                    .frame(maxWidth: 500)

                    self.permissionActions

                    Spacer(minLength: 0)
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: max(410, proxy.size.height - 40))
                .padding(.horizontal, 34)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private var permissionActions: some View {
        switch self.session.permissionState {
        case .idle:
            self.primaryPermissionButton(
                title: self.strings["onboarding.permission.grant"],
                image: "hand.raised.fill")
            {
                self.session.grantPermissionAction()
            }
        case .requesting:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(self.strings["onboarding.permission.waiting"])
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .frame(height: 42)
        case .denied:
            HStack(spacing: 10) {
                self.primaryPermissionButton(
                    title: self.strings["onboarding.permission.retry"],
                    image: "arrow.clockwise")
                {
                    self.session.grantPermissionAction()
                }

                Button(self.strings["general.permission.open"]) {
                    self.session.openSystemSettingsAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        case .granted:
            Label(
                self.strings["onboarding.permission.success"],
                systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
                .transition(
                    self.session.reduceMotion
                        ? .opacity
                        : .scale.combined(with: .opacity))
        }
    }

    private func privacyLine(_ image: String, _ key: String) -> some View {
        Label {
            Text(self.strings[key])
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: image)
                .foregroundStyle(.cyan)
                .frame(width: 22)
        }
        .font(.callout)
    }

    private func primaryPermissionButton(
        title: String,
        image: String,
        action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Label(title, systemImage: image)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 8)
                .frame(minWidth: 180, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var statusColor: Color {
        switch self.session.permissionState {
        case .idle, .requesting: .cyan
        case .denied: .orange
        case .granted: .green
        }
    }

    private var statusImage: String {
        switch self.session.permissionState {
        case .idle: "hand.raised.fill"
        case .requesting: "ellipsis.circle.fill"
        case .denied: "exclamationmark.shield.fill"
        case .granted: "checkmark.shield.fill"
        }
    }
}

extension KeyboardPresentation {
    var onboardingTitleKey: String {
        switch self {
        case .latest: "onboarding.keyboard.latest"
        case .horizontalHistory: "onboarding.keyboard.horizontal"
        case .stackedHistory: "onboarding.keyboard.stacked"
        }
    }
}

@MainActor
private struct OnboardingKeyboardStep: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var session: OnboardingSession

    private let themes = ThemeSelection.allCases.filter { $0 != .custom }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                OnboardingStepHeading(
                    title: self.strings["onboarding.keyboard.title"],
                    subtitle: self.strings["onboarding.keyboard.subtitle"])

                ZStack {
                    OnboardingPreviewSurface()
                    KeyboardPresentationDemo(
                        config: self.session.config,
                        reduceMotion: self.session.reduceMotion,
                        replayLabel: self.strings["onboarding.keyboard.replay"])
                }
                .frame(height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 10) {
                    ForEach(KeyboardPresentation.allCases, id: \.self) { presentation in
                        self.presentationCard(presentation)
                    }
                }

                HStack {
                    Text(self.strings["keyboard.content"])
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Picker(
                        self.strings["keyboard.content"],
                        selection: Binding(
                            get: { self.session.config.keyboard.contentMode },
                            set: { contentMode in
                                var keyboard = self.session.config.keyboard
                                keyboard.contentMode = contentMode
                                self.session.config.keyboard = keyboard
                            })) {
                        Text(self.strings["keyboard.content.all"])
                            .tag(KeyboardContentMode.allKeys)
                        Text(self.strings["keyboard.content.shortcuts"])
                            .tag(KeyboardContentMode.shortcutsOnly)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
                .padding(.horizontal, 3)

                VStack(alignment: .leading, spacing: 10) {
                    Text(self.strings["appearance.theme"])
                        .font(.callout.weight(.semibold))

                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 10) {
                            ForEach(self.themes, id: \.self) { selection in
                                ThemeCard(
                                    selection: selection,
                                    customTheme: self.session.config.appearance.customTheme,
                                    isSelected:
                                    self.session.config.appearance.keyboardThemeSelection == selection,
                                    isSystemDark: true,
                                    title: self.strings["theme.\(selection.rawValue)"])
                                {
                                    self.session.config.appearance.keyboardThemeSelection = selection
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.visible)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 18)
        }
    }

    private func presentationCard(_ presentation: KeyboardPresentation) -> some View {
        let selected = self.isSelected(presentation)

        return Button {
            var keyboard = self.session.config.keyboard
            keyboard.presentation = presentation
            self.session.config.keyboard = keyboard
        } label: {
            VStack(spacing: 9) {
                OnboardingPresentationArtwork(
                    presentation: presentation,
                    contentMode: self.session.config.keyboard.contentMode)
                    .frame(height: 54)
                    .accessibilityHidden(true)
                Text(self.strings[presentation.onboardingTitleKey])
                    .font(.caption.weight(selected ? .bold : .medium))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity)
            .background(
                selected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor : Color.primary.opacity(0.08),
                        lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(StudioHoverButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func isSelected(_ presentation: KeyboardPresentation) -> Bool {
        self.session.config.keyboard.presentation == presentation
    }
}

@MainActor
struct OnboardingPresentationArtwork: View {
    let presentation: KeyboardPresentation
    let contentMode: KeyboardContentMode

    private let shift = OnboardingMiniKey(label: "⇧", width: 31)
    private let command = OnboardingMiniKey(label: "⌘", width: 31)

    var body: some View {
        Group {
            switch self.presentation {
            case .latest:
                HStack(spacing: 4) {
                    self.shift
                    self.command
                    self.key
                }
            case .horizontalHistory:
                HStack(spacing: 4) {
                    self.shift
                    self.command
                    if self.contentMode == .allKeys {
                        OnboardingMiniKey(label: "H", width: 23)
                        OnboardingMiniKey(label: "I", width: 23)
                    } else {
                        OnboardingMiniKey(label: "C", width: 23)
                    }
                    self.key
                }
            case .stackedHistory:
                VStack(spacing: 3) {
                    if self.contentMode == .allKeys {
                        Text("HELLO")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 74, height: 17)
                            .background(
                                Color.primary.opacity(0.055),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    } else {
                        self.chord(key: OnboardingMiniKey(label: "C", width: 23))
                    }
                    self.chord(key: self.key)
                }
            }
        }
    }

    private func chord(key: OnboardingMiniKey) -> some View {
        HStack(spacing: 4) {
            self.shift
            self.command
            key
        }
    }

    private var key: OnboardingMiniKey {
        OnboardingMiniKey(
            label: self.contentMode == .allKeys ? "K" : "V",
            width: 23)
    }
}

private struct OnboardingMiniKey: View {
    let label: String
    let width: CGFloat

    var body: some View {
        Text(self.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: self.width, height: 22)
            .background(
                Color.primary.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.13))
            }
    }
}

@MainActor
private struct OnboardingPointerStep: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var session: OnboardingSession

    private let themes: [ThemeSelection] = [
        .dark,
        .mono,
        .classic,
        .modern,
        .minimal,
        .gaming,
        .neon,
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                OnboardingStepHeading(
                    title: self.strings["onboarding.pointer.title"],
                    subtitle: self.strings["onboarding.pointer.subtitle"])

                OnboardingPointerLivePreview(session: self.session)
                    .frame(height: 142)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.strings["pointer.enabled"])
                            .font(.headline)
                        Text(self.strings["pointer.enabled.subtitle"])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(
                        self.strings["pointer.enabled"],
                        isOn: Binding(
                            get: { self.session.config.pointer.enabled },
                            set: { self.session.config.pointer.enabled = $0 }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(14)
                .background(
                    Color.primary.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if self.session.config.pointer.enabled {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(self.strings["pointer.visibility"])
                            .font(.callout.weight(.semibold))

                        HStack(spacing: 8) {
                            self.visibilityButton(.onActivity, "pointer.visibility.activity")
                            self.visibilityButton(.actionsOnly, "pointer.visibility.actions")
                            self.visibilityButton(.always, "pointer.visibility.always")
                        }
                    }
                    .transition(
                        self.session.reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity))

                    VStack(alignment: .leading, spacing: 10) {
                        Text(self.strings["appearance.theme"])
                            .font(.callout.weight(.semibold))

                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 10) {
                                ForEach(self.themes, id: \.self) { selection in
                                    PointerThemeCard(
                                        selection: selection,
                                        customTheme: self.session.config.appearance.customTheme,
                                        isSelected:
                                        self.session.config.appearance.pointerThemeSelection == selection,
                                        isSystemDark: true,
                                        title: self.strings["theme.\(selection.rawValue)"])
                                    {
                                        self.session.config.appearance.pointerThemeSelection = selection
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollIndicators(.visible)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .animation(
                self.session.reduceMotion
                    ? .easeOut(duration: 0.16)
                    : .spring(response: 0.42, dampingFraction: 0.86),
                value: self.session.config.pointer.enabled)
        }
    }

    private func visibilityButton(_ value: PointerVisibility, _ key: String) -> some View {
        let selected = self.session.config.pointer.visibility == value

        return Button {
            self.session.config.pointer.visibility = value
        } label: {
            Text(self.strings[key])
                .font(.caption.weight(selected ? .bold : .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            selected ? Color.accentColor : Color.primary.opacity(0.08),
                            lineWidth: selected ? 1.5 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .buttonStyle(StudioHoverButtonStyle())
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}

@MainActor
private struct OnboardingPointerLivePreview: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var session: OnboardingSession
    @State private var pointerLocation = CGPoint(x: 0.5, y: 0.5)
    @State private var isPointerInside = false
    @State private var isPointerPressed = false
    @State private var pointerResetTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OnboardingPreviewSurface()

                if self.session.config.pointer.enabled {
                    PointerThemeArtwork(theme: self.pointerTheme, size: 76)
                        .scaleEffect(
                            self.session.reduceMotion
                                ? 1
                                : (self.isPointerPressed ? 0.76 : 1))
                        .opacity(
                            self.haloIsVisible
                                ? (self.session.reduceMotion && self.isPointerPressed ? 0.7 : 1)
                                : 0)
                        .position(
                            x: self.pointerLocation.x * proxy.size.width,
                            y: self.pointerLocation.y * proxy.size.height)
                        .animation(
                            self.session.reduceMotion
                                ? .easeOut(duration: 0.08)
                                : .spring(response: 0.24, dampingFraction: 0.62),
                            value: self.isPointerPressed)
                        .accessibilityHidden(true)

                    VStack {
                        HStack {
                            Text(self.strings[self.visibilityTitleKey])
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.74))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.28), in: Capsule())
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(10)
                } else {
                    Label(
                        self.strings["onboarding.pointer.disabled"],
                        systemImage: "cursorarrow.slash")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case let .active(location):
                    self.pointerLocation = self.normalized(location, in: proxy.size)
                    self.isPointerInside = true
                case .ended:
                    self.pointerResetTask?.cancel()
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        self.isPointerPressed = false
                        self.isPointerInside = false
                    }
                    self.session.updatePointer(location: self.pointerLocation)
                }
            }
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                    guard self.session.config.pointer.enabled else { return }
                    self.pointerLocation = self.normalized(value.location, in: proxy.size)
                    self.session.updatePointer(location: self.pointerLocation)
                    self.playPointerPress()
                })
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onDisappear {
            self.pointerResetTask?.cancel()
        }
    }

    private var haloIsVisible: Bool {
        guard self.session.config.pointer.enabled, self.isPointerInside else { return false }
        return switch self.session.config.pointer.visibility {
        case .onActivity:
            true
        case .actionsOnly:
            self.isPointerPressed
        case .always:
            true
        }
    }

    private var visibilityTitleKey: String {
        switch self.session.config.pointer.visibility {
        case .onActivity: "pointer.visibility.activity"
        case .actionsOnly: "pointer.visibility.actions"
        case .always: "pointer.visibility.always"
        }
    }

    private var pointerTheme: PointerTheme {
        self.session.config
            .effectiveTheme(isSystemDark: true)
            .pointer
    }

    private func normalized(_ location: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(location.x / max(size.width, 1), 0), 1),
            y: min(max(location.y / max(size.height, 1), 0), 1))
    }

    private func playPointerPress() {
        self.pointerResetTask?.cancel()
        self.isPointerPressed = true
        self.pointerResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self.isPointerPressed = false
        }
    }
}

@MainActor
private struct OnboardingFinishingView: View {
    @Bindable var session: OnboardingSession
    let availableSize: CGSize
    @State private var finished = false

    var body: some View {
        ZStack {
            KeyboardThemeContainer(config: self.session.config, disableOuterShadow: true) {
                HStack(spacing: CGFloat(self.keyboardTheme.keySpacing)) {
                    KeyCapView(
                        symbol: KeySymbol(id: "command-left", display: "⌘", isModifier: true),
                        config: self.session.config)
                    KeyCapView(
                        symbol: KeySymbol(id: "key-40", display: "K"),
                        config: self.session.config)
                }
            }
            .scaleEffect(
                self.session.reduceMotion
                    ? 1
                    : (self.finished ? 0.18 : 1))
            .opacity(self.finished ? 0 : 1)

            if self.session.config.pointer.enabled {
                PointerThemeArtwork(theme: self.pointerTheme, size: 92)
                    .position(
                        x: self.finished && !self.session.reduceMotion
                            ? self.session.pointerLocation.x * self.availableSize.width
                            : self.availableSize.width / 2,
                        y: self.finished && !self.session.reduceMotion
                            ? self.session.pointerLocation.y * self.availableSize.height
                            : self.availableSize.height / 2)
                    .scaleEffect(
                        self.session.reduceMotion
                            ? 1
                            : (self.finished ? 0.42 : 1))
                    .opacity(self.finished ? 0 : 1)
            }
        }
        .onAppear {
            withAnimation(
                self.session.reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .easeInOut(duration: 0.78))
            {
                self.finished = true
            }
        }
    }

    private var pointerTheme: PointerTheme {
        self.session.config
            .effectiveTheme(isSystemDark: true)
            .pointer
    }

    private var keyboardTheme: KeyboardTheme {
        self.session.config
            .effectiveTheme(isSystemDark: true)
            .keyboard
    }
}

private struct OnboardingStepHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text(self.title)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(self.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 590)
        }
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct OnboardingPreviewSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.045, green: 0.052, blue: 0.075),
                    Color(red: 0.085, green: 0.065, blue: 0.13),
                    Color(red: 0.035, green: 0.07, blue: 0.085),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)

            RadialGradient(
                colors: [Color.cyan.opacity(0.14), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 320)

            Canvas { context, size in
                let spacing: CGFloat = 28
                var path = Path()
                for x in stride(from: 0, through: size.width, by: spacing) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 0, through: size.height, by: spacing) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(.white.opacity(0.025)), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        }
        .accessibilityHidden(true)
    }
}

@MainActor
private struct OnboardingSoundButton: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var session: OnboardingSession

    var body: some View {
        Button {
            self.session.toggleSoundAction()
        } label: {
            Image(systemName: self.session.isSoundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(StudioHoverButtonStyle(showsHoverSurface: false))
        .help(
            self.session.isSoundMuted
                ? self.strings["onboarding.sound.on"]
                : self.strings["onboarding.sound.off"])
        .accessibilityLabel(
            self.session.isSoundMuted
                ? self.strings["onboarding.sound.on"]
                : self.strings["onboarding.sound.off"])
    }
}
