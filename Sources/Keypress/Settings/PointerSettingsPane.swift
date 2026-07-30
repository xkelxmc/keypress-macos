import AppKit
import KeypressCore
import SwiftUI

@MainActor
struct PointerSettingsPane: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig

    var body: some View {
        StudioPage(
            titleKey: "pointer.title",
            subtitleKey: "pointer.subtitle")
        {
            FeatureToggleCard(
                titleKey: "pointer.enabled",
                subtitleKey: "pointer.enabled.subtitle",
                systemImage: "cursorarrow.motionlines",
                tint: .orange,
                isOn: self.$config.pointer.enabled)

            if self.config.pointer.enabled {
                InputPermissionBanner()

                StudioCard("pointer.behavior", systemImage: "eye.fill", tint: .orange) {
                    SettingsRow("pointer.visibility", subtitleKey: "pointer.visibility.subtitle") {
                        Picker("", selection: self.visibilityBinding) {
                            Text(self.strings["pointer.visibility.activity"]).tag(PointerVisibility.onActivity)
                            Text(self.strings["pointer.visibility.actions"]).tag(PointerVisibility.actionsOnly)
                            Text(self.strings["pointer.visibility.always"]).tag(PointerVisibility.always)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(minWidth: 300)
                    }

                    if self.config.pointer.visibility != .always {
                        StudioDivider()

                        SettingsRow("pointer.idleDelay", subtitleKey: "pointer.idleDelay.subtitle") {
                            SliderValue(
                                value: self.idleDelayBinding,
                                range: self.idleDelayRange,
                                step: 0.1,
                                suffix: self.strings["unit.seconds"])
                        }
                    }
                }

                StudioCard("pointer.events", systemImage: "computermouse.fill", tint: .blue) {
                    PointerEventToggles(config: self.config)
                }
            }
        }
    }

    private var hasActionEvents: Bool {
        self.config.pointer.showLeftClick
            || self.config.pointer.showRightClick
            || self.config.pointer.showMiddleClick
            || self.config.pointer.showDrag
            || self.config.pointer.showScroll
    }

    private var visibilityBinding: Binding<PointerVisibility> {
        Binding(
            get: { self.config.pointer.visibility },
            set: { visibility in
                if visibility == .actionsOnly, !self.hasActionEvents {
                    self.config.pointer.showLeftClick = true
                }
                if visibility == .onActivity, !self.hasAnyEvents {
                    self.config.pointer.showMovement = true
                }
                self.config.pointer.visibility = visibility
            })
    }

    private var hasAnyEvents: Bool {
        self.hasActionEvents || self.config.pointer.showMovement
    }

    private var idleDelayBinding: Binding<Double> {
        Binding(
            get: { self.config.pointer.visibility == .actionsOnly
                ? self.config.pointer.idleDelay / 2
                : self.config.pointer.idleDelay
            },
            set: { value in
                self.config.pointer.idleDelay = self.config.pointer.visibility == .actionsOnly
                    ? value * 2
                    : value
            })
    }

    private var idleDelayRange: ClosedRange<Double> {
        self.config.pointer.visibility == .actionsOnly ? 0.05...5 : 0.1...10
    }
}

@MainActor
struct PointerAppearanceSettingsPane: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig
    let openSettings: () -> Void
    @State private var showsResetConfirmation = false

    var body: some View {
        Group {
            if self.config.pointer.enabled {
                StudioPreviewPage(
                    titleKey: "pointer.appearance.title",
                    subtitleKey: "pointer.appearance.subtitle",
                    preview: {
                        StudioPreviewSurface(height: self.previewSurfaceHeight) {
                            PointerSettingsPreview(config: self.config)
                        }
                    },
                    content: { self.appearanceControls })
            } else {
                StudioPage(
                    titleKey: "pointer.appearance.title",
                    subtitleKey: "pointer.appearance.subtitle")
                {
                    DisabledFeatureView(
                        titleKey: "pointer.disabled.title",
                        subtitleKey: "pointer.disabled.subtitle",
                        buttonKey: "pointer.disabled.action",
                        systemImage: "cursorarrow.motionlines",
                        tint: .orange,
                        action: self.openSettings)
                }
            }
        }
        .alert(
            self.strings["pointer.appearance.reset.confirm.title"],
            isPresented: self.$showsResetConfirmation)
        {
            Button(self.strings["action.cancel"], role: .cancel) {}
            Button(self.strings["pointer.appearance.reset"], role: .destructive) {
                self.config.appearance.customTheme.pointer = .init()
            }
        } message: {
            Text(self.strings["pointer.appearance.reset.confirm.message"])
        }
    }

    private var previewSurfaceHeight: CGFloat {
        max(200, CGFloat(self.config.pointer.size) + 160)
    }

    @ViewBuilder
    private var appearanceControls: some View {
        StudioCard("appearance.theme") {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(self.themeSelections, id: \.self) { selection in
                        PointerThemeCard(
                            selection: selection,
                            customTheme: self.config.appearance.customTheme,
                            isSelected: self.config.appearance.pointerThemeSelection == selection,
                            isSystemDark: self.isSystemDark,
                            title: self.themeTitle(selection))
                        {
                            self.config.appearance.pointerThemeSelection = selection
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.visible)
            .frame(maxWidth: .infinity)

            if self.config.appearance.pointerThemeSelection != .custom {
                HStack {
                    Text(self.strings["appearance.presetsImmutable"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(self.strings["appearance.customize"]) {
                        self.config.beginCustomizingPointerTheme(isSystemDark: self.isSystemDark)
                    }
                }
            }
        }

        StudioCard("pointer.effect") {
            VStack(alignment: .leading, spacing: 8) {
                Text(self.strings["pointer.shape"])
                    .font(.callout.weight(.medium))
                PointerShapePicker(
                    selection: self.themeBinding(\.shape),
                    strings: self.strings)
            }

            StudioDivider()

            SettingsRow("pointer.lineStyle") {
                Picker("", selection: self.themeBinding(\.lineStyle)) {
                    Text(self.strings["pointer.lineStyle.aura"]).tag(PointerLineStyle.aura)
                    Text(self.strings["pointer.lineStyle.solid"]).tag(PointerLineStyle.solid)
                    Text(self.strings["pointer.lineStyle.double"]).tag(PointerLineStyle.double)
                    Text(self.strings["pointer.lineStyle.segmented"]).tag(PointerLineStyle.segmented)
                    Text(self.strings["pointer.lineStyle.neonDepth"]).tag(PointerLineStyle.neonDepth)
                }
                .labelsHidden()
                .frame(width: 190)
            }

            StudioDivider()

            SettingsRow("pointer.decoration") {
                Picker("", selection: self.themeBinding(\.decoration)) {
                    Text(self.strings["pointer.decoration.none"]).tag(PointerDecoration.none)
                    Text(self.strings["pointer.decoration.centerDot"]).tag(PointerDecoration.centerDot)
                    Text(self.strings["pointer.decoration.innerRing"]).tag(PointerDecoration.innerRing)
                    Text(self.strings["pointer.decoration.crosshair"]).tag(PointerDecoration.crosshair)
                    Text(self.strings["pointer.decoration.cornerBrackets"]).tag(PointerDecoration.cornerBrackets)
                    Text(self.strings["pointer.decoration.orbit"]).tag(PointerDecoration.orbit)
                }
                .labelsHidden()
                .frame(width: 190)
            }

            StudioDivider()

            SettingsRow("pointer.size") {
                SliderValue(
                    value: self.$config.pointer.size,
                    range: 24...160,
                    step: 2,
                    suffix: self.strings["unit.points"])
            }

            StudioDivider()

            SettingsRow("pointer.stroke") {
                SliderValue(
                    value: self.themeBinding(\.strokeWidth),
                    range: 1...16,
                    step: 0.5,
                    suffix: self.strings["unit.points"])
            }

            StudioDivider()

            SettingsRow("pointer.opacity") {
                PercentageSlider(value: self.$config.pointer.opacity)
            }

            StudioDivider()

            SettingsRow("appearance.primary") {
                ColorPicker(
                    "",
                    selection: self.themeColorBinding(\.primaryColor),
                    supportsOpacity: false)
                    .labelsHidden()
            }

            if self.usesSecondaryColor {
                StudioDivider()
                SettingsRow("appearance.secondary") {
                    ColorPicker(
                        "",
                        selection: self.themeColorBinding(\.secondaryColor),
                        supportsOpacity: false)
                        .labelsHidden()
                }
            }

            if self.usesCoreColor {
                StudioDivider()
                SettingsRow("appearance.core") {
                    ColorPicker(
                        "",
                        selection: self.themeColorBinding(\.coreColor),
                        supportsOpacity: false)
                        .labelsHidden()
                }
            }
        }

        StudioCard("pointer.motion") {
            SettingsRow("pointer.glowIntensity") {
                PercentageSlider(value: self.themeBinding(\.glowIntensity))
            }

            if self.effectivePointerTheme.glowIntensity > 0 {
                StudioDivider()
                SettingsRow("pointer.glowRadius") {
                    SliderValue(
                        value: self.themeBinding(\.glowRadius),
                        range: 0...40,
                        step: 1,
                        suffix: self.strings["unit.points"])
                }
            }

            if self.hasMotionEvents {
                StudioDivider()
                SettingsRow("pointer.motionIntensity") {
                    PercentageSlider(value: self.$config.pointer.motionIntensity)
                }
            }
        }

        if self.config.appearance.pointerThemeSelection == .custom {
            DestructiveSettingsAction(
                titleKey: "pointer.appearance.reset",
                subtitleKey: "pointer.appearance.reset.confirm.message",
                systemImage: "trash.fill")
            {
                self.showsResetConfirmation = true
            }
        }
    }

    private var themeSelections: [ThemeSelection] {
        [.dark, .mono, .classic, .modern, .minimal, .gaming, .neon, .custom]
    }

    private func themeTitle(_ selection: ThemeSelection) -> String {
        selection == .dark
            ? self.strings["theme.default"]
            : self.strings["theme.\(selection.rawValue)"]
    }

    private var isSystemDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var effectivePointerTheme: PointerTheme {
        self.config.effectiveTheme(isSystemDark: self.isSystemDark).pointer
    }

    private var hasMotionEvents: Bool {
        self.config.pointer.showMovement
            || self.config.pointer.showDrag
            || self.config.pointer.showScroll
    }

    private var usesSecondaryColor: Bool {
        if self.config.pointer.showRightClick {
            return true
        }

        switch self.effectivePointerTheme.lineStyle {
        case .double, .segmented, .neonDepth:
            return true
        case .aura, .solid:
            break
        }

        return self.effectivePointerTheme.decoration == .cornerBrackets
            || self.effectivePointerTheme.decoration == .orbit
    }

    private var usesCoreColor: Bool {
        if self.config.pointer.showMiddleClick
            || self.effectivePointerTheme.lineStyle == .neonDepth
        {
            return true
        }

        return self.effectivePointerTheme.decoration != .none
            && self.effectivePointerTheme.decoration != .cornerBrackets
    }

    private func themeBinding<Value>(_ keyPath: WritableKeyPath<PointerTheme, Value>) -> Binding<Value> {
        Binding(
            get: {
                self.config.effectiveTheme(isSystemDark: self.isSystemDark).pointer[keyPath: keyPath]
            },
            set: { value in
                self.config.beginCustomizingPointerTheme(isSystemDark: self.isSystemDark)
                self.config.appearance.customTheme.pointer[keyPath: keyPath] = value
            })
    }

    private func themeColorBinding(_ keyPath: WritableKeyPath<PointerTheme, KeyColor>) -> Binding<Color> {
        Binding(
            get: {
                self.config.effectiveTheme(isSystemDark: self.isSystemDark).pointer[keyPath: keyPath].color
            },
            set: { color in
                self.config.beginCustomizingPointerTheme(isSystemDark: self.isSystemDark)
                self.config.appearance.customTheme.pointer[keyPath: keyPath] = KeyColor(color)
            })
    }
}

private struct PointerShapePicker: View {
    @Binding var selection: PointerShape
    let strings: StudioStrings

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PointerShape.allCases, id: \.self) { shape in
                Button {
                    self.selection = shape
                } label: {
                    VStack(spacing: 7) {
                        self.sample(shape)
                            .frame(width: 30, height: 30)
                        Text(self.strings["pointer.shape.\(shape.rawValue)"])
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
                    .contentShape(Rectangle())
                    .background(
                        self.selection == shape
                            ? Color.accentColor.opacity(0.14)
                            : Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                self.selection == shape
                                    ? Color.accentColor
                                    : Color.primary.opacity(0.09),
                                lineWidth: self.selection == shape ? 2 : 1)
                    }
                }
                .buttonStyle(.plain)
                .help(self.strings["pointer.shape.\(shape.rawValue)"])
                .accessibilityLabel(self.strings["pointer.shape.\(shape.rawValue)"])
                .accessibilityAddTraits(self.selection == shape ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func sample(_ shape: PointerShape) -> some View {
        switch shape {
        case .circle:
            Circle().stroke(Color.accentColor, lineWidth: 2)
        case .squircle:
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 2)
        case .square:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 2)
        case .diamond:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 2)
                .scaleEffect(0.72)
                .rotationEffect(.degrees(45))
        }
    }
}

struct PointerThemeCard: View {
    let selection: ThemeSelection
    let customTheme: ThemeDefinition
    let isSelected: Bool
    let isSystemDark: Bool
    let title: String
    let action: () -> Void

    private var theme: PointerTheme {
        AppearanceSettings(
            keyboardThemeSelection: .system,
            pointerThemeSelection: self.selection,
            customTheme: self.customTheme)
            .resolvedTheme(isSystemDark: self.isSystemDark)
            .pointer
    }

    var body: some View {
        Button(action: self.action) {
            VStack(alignment: .leading, spacing: 9) {
                ZStack {
                    PointerContrastBackdrop(cornerRadius: 10)
                    self.sample
                }
                .frame(maxWidth: .infinity)
                .frame(height: 62)

                HStack(spacing: 5) {
                    Text(self.title)
                        .font(.callout.weight(self.isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if self.isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .padding(9)
            .frame(width: 150)
            .background(.quaternary.opacity(self.isSelected ? 0.8 : 0.35))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        self.isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                        lineWidth: self.isSelected ? 2 : 1)
            }
        }
        .buttonStyle(StudioHoverButtonStyle())
        .help(self.title)
        .accessibilityLabel(self.title)
        .accessibilityAddTraits(self.isSelected ? .isSelected : [])
    }

    private var sample: some View {
        PointerThemeArtwork(theme: self.theme, size: 40)
    }
}

private struct PointerContrastBackdrop: View {
    let cornerRadius: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Color(red: 0.94, green: 0.95, blue: 0.97)
            Color(red: 0.055, green: 0.065, blue: 0.085)
        }
        .overlay {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.16),
                    Color.clear,
                    Color.black.opacity(0.1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
    }
}

@MainActor
private struct PointerEventToggles: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(self.events.enumerated()), id: \.offset) { index, event in
                if index > 0 {
                    StudioDivider()
                }
                SettingsRow(event.titleKey) {
                    Toggle(
                        self.strings[event.titleKey],
                        isOn: event.binding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(
                            self.config.pointer.visibility != .always
                                && event.binding.wrappedValue
                                && self.enabledEventCount == 1)
                        .accessibilityLabel(self.strings[event.titleKey])
                }
            }

            if self.config.pointer.visibility != .always,
               self.enabledEventCount == 1
            {
                Label(
                    self.strings["pointer.events.minimum"],
                    systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var events: [(titleKey: String, binding: Binding<Bool>)] {
        var events = [
            ("pointer.leftClick", self.binding(\.showLeftClick)),
            ("pointer.rightClick", self.binding(\.showRightClick)),
            ("pointer.middleClick", self.binding(\.showMiddleClick)),
            ("pointer.drag", self.binding(\.showDrag)),
            ("pointer.scroll", self.binding(\.showScroll)),
        ]
        if self.config.pointer.visibility != .actionsOnly {
            events.insert(
                ("pointer.movement", self.binding(\.showMovement)),
                at: 3)
        }
        return events
    }

    private var enabledEventCount: Int {
        self.events.map(\.binding.wrappedValue).filter(\.self).count
    }

    private func binding(_ keyPath: WritableKeyPath<PointerSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { self.config.pointer[keyPath: keyPath] },
            set: { self.config.pointer[keyPath: keyPath] = $0 })
    }
}

@MainActor
private struct PointerSettingsPreview: View {
    @Environment(\.studioStrings) private var strings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let config: KeypressConfig
    @State private var reaction = PointerPreviewReaction.idle

    private var theme: PointerTheme {
        let isSystemDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return self.config.effectiveTheme(isSystemDark: isSystemDark).pointer
    }

    var body: some View {
        ZStack {
            PointerContrastBackdrop(cornerRadius: 18)
                .frame(
                    width: max(250, CGFloat(self.config.pointer.size) + 96),
                    height: max(116, CGFloat(self.config.pointer.size) + 34))
                .shadow(color: Color.black.opacity(0.16), radius: 12, y: 6)

            PointerThemeArtwork(
                theme: self.theme,
                size: CGFloat(self.config.pointer.size),
                reaction: self.reaction.artworkReaction)
                .opacity(self.config.pointer.opacity)
                .scaleEffect(
                    x: self.previewTransform.scaleX,
                    y: self.previewTransform.scaleY)
                .rotationEffect(.degrees(self.previewTransform.rotation))
                .rotation3DEffect(
                    .degrees(self.previewTransform.xTilt),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.35)
                .rotation3DEffect(
                    .degrees(self.previewTransform.yTilt),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.35)
                .animation(
                    .spring(
                        response: self.motionProfile.springResponse,
                        dampingFraction: self.motionProfile.springDamping),
                    value: self.reaction)

            Image(systemName: "cursorarrow")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(radius: 3)
                .accessibilityHidden(true)

            VStack {
                HStack {
                    Label(
                        self.strings["pointer.preview.try"],
                        systemImage: "hand.tap")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer()
                }
                .padding(14)

                Spacer()
                HStack(spacing: 6) {
                    ForEach(PointerPreviewReaction.allCases, id: \.self) { reaction in
                        Button {
                            self.reaction = reaction
                        } label: {
                            Image(systemName: reaction.systemImage)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(
                                    self.reaction == reaction
                                        ? Color.white
                                        : Color.primary.opacity(0.82))
                                .background(
                                    self.reaction == reaction
                                        ? Color.accentColor
                                        : Color.primary.opacity(0.055),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!self.isAvailable(reaction))
                        .help(self.strings[reaction.titleKey])
                        .accessibilityLabel(self.strings[reaction.titleKey])
                        .accessibilityAddTraits(self.reaction == reaction ? .isSelected : [])
                    }

                    Divider()
                        .frame(height: 18)

                    Text(self.strings[self.reaction.titleKey])
                        .font(.caption.weight(.medium))
                        .frame(minWidth: 92, alignment: .leading)
                }
                .padding(6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.bottom, 12)
            }
        }
        .onChange(of: self.config.pointer) { _, _ in
            if !self.isAvailable(self.reaction) {
                self.reaction = .idle
            }
        }
    }

    private var motionProfile: HaloMotionProfile {
        HaloMotionProfile(style: self.theme.reactionStyle)
    }

    private var previewTransform: PointerPreviewTransform {
        if self.reduceMotion {
            return self.reaction == .idle
                ? .identity
                : PointerPreviewTransform(scaleX: 0.94, scaleY: 0.94)
        }

        switch self.reaction {
        case .idle:
            return .identity
        case .movement:
            return PointerPreviewTransform(
                scaleX: 1 + self.motionProfile.movementStretch,
                scaleY: 1 - self.motionProfile.movementStretch * 0.4,
                rotation: 6 * Double(self.motionProfile.rotationScale),
                xTilt: -4 * Double(self.motionProfile.tiltScale),
                yTilt: 5 * Double(self.motionProfile.tiltScale))
        case .primary:
            return PointerPreviewTransform(
                scaleX: self.motionProfile.primaryScale.width,
                scaleY: self.motionProfile.primaryScale.height,
                rotation: self.motionProfile.primaryRotation,
                xTilt: self.motionProfile.primaryTilt)
        case .secondary:
            return PointerPreviewTransform(
                scaleX: self.motionProfile.secondaryScale,
                scaleY: self.motionProfile.secondaryScale,
                rotation: self.motionProfile.secondaryRotation,
                xTilt: self.motionProfile.secondaryTilt)
        case .middle:
            return PointerPreviewTransform(
                scaleX: self.motionProfile.middleScale,
                scaleY: self.motionProfile.middleScale)
        case .drag:
            return PointerPreviewTransform(
                scaleX: 1 + self.motionProfile.dragStretch,
                scaleY: self.motionProfile.dragCompression,
                rotation: 5 * Double(self.motionProfile.rotationScale),
                xTilt: self.motionProfile.dragTilt,
                yTilt: 4 * Double(self.motionProfile.tiltScale))
        case .scroll:
            return PointerPreviewTransform(
                scaleX: 1 + self.motionProfile.scrollExpansion,
                scaleY: max(0.66, 1 - 0.18 * self.motionProfile.scrollCompression))
        }
    }

    private func isAvailable(_ reaction: PointerPreviewReaction) -> Bool {
        switch reaction {
        case .idle: true
        case .movement:
            self.config.pointer.visibility != .actionsOnly
                && self.config.pointer.showMovement
        case .primary: self.config.pointer.showLeftClick
        case .secondary: self.config.pointer.showRightClick
        case .middle: self.config.pointer.showMiddleClick
        case .drag: self.config.pointer.showDrag
        case .scroll: self.config.pointer.showScroll
        }
    }
}

private enum PointerPreviewReaction: CaseIterable, Hashable {
    case idle
    case movement
    case primary
    case secondary
    case middle
    case drag
    case scroll

    var artworkReaction: PointerArtworkReaction {
        switch self {
        case .idle: .idle
        case .movement: .movement
        case .primary: .primary
        case .secondary: .secondary
        case .middle: .middle
        case .drag: .drag
        case .scroll: .scroll
        }
    }

    var systemImage: String {
        switch self {
        case .idle: "cursorarrow"
        case .movement: "cursorarrow.motionlines"
        case .primary: "cursorarrow.click"
        case .secondary: "computermouse"
        case .middle: "smallcircle.filled.circle"
        case .drag: "hand.draw"
        case .scroll: "scroll"
        }
    }

    var titleKey: String {
        switch self {
        case .idle: "pointer.preview.resting"
        case .movement: "pointer.movement"
        case .primary: "pointer.leftClick"
        case .secondary: "pointer.rightClick"
        case .middle: "pointer.middleClick"
        case .drag: "pointer.drag"
        case .scroll: "pointer.scroll"
        }
    }
}

private struct PointerPreviewTransform {
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var rotation: Double = 0
    var xTilt: Double = 0
    var yTilt: Double = 0

    static let identity = PointerPreviewTransform()
}

private struct SliderValue: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: self.$value, in: self.range, step: self.step)
                .frame(width: 150)
            Text(self.value, format: .number.precision(.fractionLength(self.fractionDigits)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
            Text(self.suffix)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var fractionDigits: Int {
        self.step < 1 ? 1 : 0
    }
}

private struct PercentageSlider: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: self.$value, in: 0...1)
                .frame(width: 150)
            Text("\(Int(round(self.value * 100)))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }
}
