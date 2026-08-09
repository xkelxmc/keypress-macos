import AppKit
import KeypressCore
import SwiftUI

@MainActor
struct KeyboardAppearanceSettingsPane: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig
    let openSettings: () -> Void
    @State private var selectedCategory: KeyCategory = .command
    @State private var showsResetConfirmation = false

    var body: some View {
        Group {
            if self.config.keyboard.enabled {
                StudioPreviewPage(
                    titleKey: "keyboard.appearance.title",
                    subtitleKey: "keyboard.appearance.subtitle",
                    preview: { KeyPreview(config: self.config) },
                    content: { self.appearanceControls })
            } else {
                StudioPage(
                    titleKey: "keyboard.appearance.title",
                    subtitleKey: "keyboard.appearance.subtitle")
                {
                    DisabledFeatureView(
                        titleKey: "keyboard.disabled.title",
                        subtitleKey: "keyboard.disabled.subtitle",
                        buttonKey: "keyboard.disabled.action",
                        systemImage: "keyboard",
                        tint: .blue,
                        action: self.openSettings)
                }
            }
        }
        .alert(
            self.strings["appearance.resetCustom.confirm.title"],
            isPresented: self.$showsResetConfirmation)
        {
            Button(self.strings["action.cancel"], role: .cancel) {}
            Button(self.strings["appearance.resetCustom"], role: .destructive) {
                self.config.appearance.customTheme.keyboard = .init()
                self.config.appearance.customTheme.hud = .init()
            }
        } message: {
            Text(self.strings["appearance.resetCustom.confirm.message"])
        }
    }

    @ViewBuilder
    private var appearanceControls: some View {
        StudioCard("appearance.theme", systemImage: "paintpalette.fill", tint: .pink) {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(self.themeSelections, id: \.self) { selection in
                        ThemeCard(
                            selection: selection,
                            customTheme: self.config.appearance.customTheme,
                            isSelected: self.config.appearance.keyboardThemeSelection == selection,
                            isSystemDark: self.isSystemDark,
                            title: self.strings["theme.\(selection.rawValue)"])
                        {
                            self.config.appearance.keyboardThemeSelection = selection
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scrollIndicators(.visible)

            if self.config.appearance.keyboardThemeSelection != .custom {
                HStack {
                    Text(self.strings["appearance.presetsImmutable"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(self.strings["appearance.customize"]) {
                        self.config.beginCustomizingKeyboardTheme(isSystemDark: self.isSystemDark)
                    }
                }
            }
        }

        StudioCard("appearance.overlay", systemImage: "rectangle.inset.filled", tint: .purple) {
            SettingsRow("appearance.size") {
                Picker("", selection: self.$config.keyboard.size) {
                    Text(self.strings["size.small"]).tag(OverlaySize.small)
                    Text(self.strings["size.medium"]).tag(OverlaySize.medium)
                    Text(self.strings["size.large"]).tag(OverlaySize.large)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            StudioDivider()

            SettingsRow("appearance.opacity") {
                HStack(spacing: 8) {
                    Slider(value: self.$config.keyboard.opacity, in: 0.3...1)
                        .frame(width: 160)
                    Text("\(Int(round(self.config.keyboard.opacity * 100)))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
        if self.config.appearance.keyboardThemeSelection == .custom {
            CustomKeyboardThemeCard(config: self.config)
            CustomHUDThemeCard(config: self.config)

            StudioCard("appearance.custom", systemImage: "slider.horizontal.3", tint: .purple) {
                CategoryThemeEditor(
                    config: self.config,
                    selectedCategory: self.$selectedCategory)
            }
            DestructiveSettingsAction(
                titleKey: "appearance.resetCustom",
                subtitleKey: "appearance.resetCustom.confirm.message",
                systemImage: "trash.fill")
            {
                self.showsResetConfirmation = true
            }
        }
    }

    private var isSystemDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var themeSelections: [ThemeSelection] {
        [.custom] + ThemeSelection.allCases.filter { $0 != .custom }
    }
}

struct ThemeCard: View {
    let selection: ThemeSelection
    let customTheme: ThemeDefinition
    let isSelected: Bool
    let isSystemDark: Bool
    let title: String
    let action: () -> Void

    private var theme: ThemeDefinition {
        AppearanceSettings(
            keyboardThemeSelection: self.selection,
            pointerThemeSelection: .system,
            customTheme: self.customTheme)
            .resolvedTheme(isSystemDark: self.isSystemDark)
    }

    var body: some View {
        Button(action: self.action) {
            VStack(alignment: .leading, spacing: 9) {
                KeyboardThemeCardSample(theme: self.theme.keyboard)
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
        .accessibilityAddTraits(self.isSelected ? .isSelected : [])
    }
}

struct StudioHoverButtonStyle: ButtonStyle {
    var showsHoverSurface = true

    func makeBody(configuration: Configuration) -> some View {
        StudioHoverButtonBody(
            configuration: configuration,
            showsHoverSurface: self.showsHoverSurface)
    }
}

private struct StudioHoverButtonBody: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyleConfiguration
    let showsHoverSurface: Bool
    @State private var isHovered = false

    var body: some View {
        self.configuration.label
            .contentShape(Rectangle())
            .brightness(self.hasHover ? 0.085 : 0)
            .background {
                if self.showsHoverSurface {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(self.hasHover ? 0.045 : 0))
                }
            }
            .overlay {
                if self.showsHoverSurface {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(self.hasHover ? 0.12 : 0))
                }
            }
            .opacity(self.isEnabled && self.configuration.isPressed ? 0.72 : 1)
            .scaleEffect(
                !self.isEnabled || self.reduceMotion || !self.configuration.isPressed
                    ? 1
                    : 0.985)
            .animation(
                .easeOut(duration: self.reduceMotion ? 0.08 : 0.14),
                value: self.isHovered)
            .animation(
                .easeOut(duration: self.reduceMotion ? 0.08 : 0.1),
                value: self.configuration.isPressed)
            .onHover { self.isHovered = self.isEnabled && $0 }
            .onChange(of: self.isEnabled) { _, isEnabled in
                if !isEnabled {
                    self.isHovered = false
                }
            }
    }

    private var hasHover: Bool {
        self.isEnabled && self.isHovered
    }
}

private struct KeyboardThemeCardSample: View {
    let theme: KeyboardTheme

    var body: some View {
        ZStack {
            self.container

            HStack(spacing: self.keySpacing) {
                ForEach([KeyCategory.command, .shift, .letter], id: \.self) { category in
                    self.keySample(for: category)
                }
            }
        }
    }

    private func keySample(for category: KeyCategory) -> some View {
        ZStack {
            if self.theme.material == .neon {
                RoundedRectangle(cornerRadius: self.keyCornerRadius, style: .continuous)
                    .fill(Color(red: 0.015, green: 0.02, blue: 0.045))
                    .overlay {
                        RoundedRectangle(cornerRadius: self.keyCornerRadius, style: .continuous)
                            .strokeBorder(self.neonSecondaryColor.opacity(0.9), lineWidth: 1)
                    }
                    .offset(y: 3)
                    .shadow(color: self.neonSecondaryColor.opacity(0.55), radius: 4, y: 2)
            } else if self.theme.material == .gaming {
                RoundedRectangle(cornerRadius: self.keyCornerRadius, style: .continuous)
                    .fill(self.gamingDepthColor(for: category))
                    .offset(y: 3)
            }

            RoundedRectangle(cornerRadius: self.keyCornerRadius, style: .continuous)
                .fill(self.keyFill(for: category))
                .overlay {
                    if self.theme.material == .neon {
                        RoundedRectangle(cornerRadius: self.keyCornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        self.theme.borderColor.color,
                                        self.neonSecondaryColor,
                                        self.theme.borderColor.color,
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing),
                                lineWidth: 1.5)
                    } else {
                        RoundedRectangle(cornerRadius: self.keyCornerRadius, style: .continuous)
                            .strokeBorder(
                                self.keyBorderColor,
                                lineWidth: self.keyBorderWidth)
                    }
                }
                .overlay {
                    if self.theme.material == .neon {
                        RoundedRectangle(
                            cornerRadius: max(1, self.keyCornerRadius - 2),
                            style: .continuous)
                            .strokeBorder(self.neonSecondaryColor.opacity(0.82), lineWidth: 0.8)
                            .padding(2.5)
                    }
                }
                .shadow(
                    color: self.keyGlowColor(for: category),
                    radius: self.keyGlowRadius)
        }
        .frame(width: self.keyWidth, height: self.keyHeight + 3)
    }

    @ViewBuilder
    private var container: some View {
        switch self.theme.frameStyle {
        case .frame:
            RoundedRectangle(cornerRadius: self.containerCornerRadius, style: .continuous)
                .fill(self.frameColor)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: max(3, self.containerCornerRadius - 4),
                        style: .continuous)
                        .fill(self.wellColor)
                        .padding(self.theme.material == .classic ? 7 : 6)
                }
                .overlay {
                    if self.theme.material == .gaming {
                        RoundedRectangle(cornerRadius: self.containerCornerRadius, style: .continuous)
                            .strokeBorder(Color.green.opacity(0.7), lineWidth: 1)
                    }
                }
        case .overlay:
            RoundedRectangle(cornerRadius: self.containerCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: self.overlayColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: self.containerCornerRadius, style: .continuous)
                        .strokeBorder(self.theme.borderColor.color.opacity(0.7), lineWidth: 1)
                }
                .shadow(
                    color: self.theme.material == .neon
                        ? self.theme.borderColor.color.opacity(0.5)
                        : .clear,
                    radius: self.theme.material == .neon ? 7 : 0)
        case .none:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
    }

    private func keyFill(for category: KeyCategory) -> LinearGradient {
        let color = self.theme.colorScheme.color(for: category).color
        let colors: [Color] = switch self.theme.material {
        case .classic, .aluminum:
            [color.lighter(by: 0.14), color.darker(by: 0.08)]
        case .glass:
            [color.lighter(by: 0.12).opacity(0.9), color.opacity(0.72)]
        case .gaming:
            [color.lighter(by: 0.12), color.darker(by: 0.2)]
        case .neon:
            [color.lighter(by: 0.05), color.darker(by: 0.12)]
        case .graphite, .monochrome, .minimal:
            [color, color]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var frameColor: Color {
        switch self.theme.material {
        case .aluminum: Color(red: 0.82, green: 0.83, blue: 0.86)
        case .classic: Color(red: 0.34, green: 0.22, blue: 0.12)
        case .gaming: Color(red: 0.025, green: 0.032, blue: 0.045)
        case .graphite, .monochrome, .glass, .minimal, .neon:
            Color(red: 0.12, green: 0.12, blue: 0.14)
        }
    }

    private var wellColor: Color {
        switch self.theme.material {
        case .aluminum: Color(red: 0.66, green: 0.67, blue: 0.70)
        case .classic: Color(red: 0.15, green: 0.09, blue: 0.05)
        case .gaming: Color(red: 0.008, green: 0.012, blue: 0.02)
        case .graphite, .monochrome, .glass, .minimal, .neon:
            Color.black.opacity(0.82)
        }
    }

    private var overlayColors: [Color] {
        switch self.theme.material {
        case .glass:
            [Color.blue.opacity(0.24), Color.black.opacity(0.72)]
        case .neon:
            [Color.cyan.opacity(0.16), Color.pink.opacity(0.14), Color.black.opacity(0.86)]
        case .graphite, .aluminum, .monochrome, .classic, .minimal, .gaming:
            [Color.black.opacity(0.68), Color.black.opacity(0.8)]
        }
    }

    private var containerCornerRadius: CGFloat {
        switch self.theme.material {
        case .gaming: 5
        case .classic: 9
        case .glass: 13
        case .graphite, .aluminum, .monochrome, .minimal, .neon: 10
        }
    }

    private var keyCornerRadius: CGFloat {
        switch self.theme.material {
        case .gaming: 2
        case .classic: 6
        case .minimal: self.keyHeight / 2
        case .graphite, .aluminum, .monochrome, .glass, .neon: 5
        }
    }

    private var keyWidth: CGFloat {
        self.theme.keyCapStyle == .minimal ? 28 : 25
    }

    private var keyHeight: CGFloat {
        switch self.theme.material {
        case .minimal: 17
        case .classic: 27
        case .graphite, .aluminum, .monochrome, .glass, .gaming, .neon: 23
        }
    }

    private var keySpacing: CGFloat {
        self.theme.material == .glass ? 7 : 5
    }

    private var keyBorderColor: Color {
        switch self.theme.material {
        case .neon: self.theme.borderColor.color
        case .gaming: Color.green.opacity(0.7)
        case .graphite, .aluminum, .monochrome, .classic, .glass, .minimal:
            Color.white.opacity(0.12)
        }
    }

    private var keyBorderWidth: CGFloat {
        switch self.theme.material {
        case .neon: 1.5
        case .gaming: 1
        case .graphite, .aluminum, .monochrome, .classic, .glass, .minimal: 0.5
        }
    }

    private func keyGlowColor(for category: KeyCategory) -> Color {
        switch self.theme.material {
        case .neon:
            self.theme.borderColor.color.opacity(0.8)
        case .gaming:
            self.theme.colorScheme.color(for: category).color.opacity(0.65)
        case .graphite, .aluminum, .monochrome, .classic, .glass, .minimal:
            .clear
        }
    }

    private var keyGlowRadius: CGFloat {
        switch self.theme.material {
        case .neon: 7
        case .gaming: 3
        case .graphite, .aluminum, .monochrome, .classic, .glass, .minimal: 0
        }
    }

    private var neonSecondaryColor: Color {
        self.theme.colorScheme.shift.color.lighter(by: 0.28)
    }

    private func gamingDepthColor(for category: KeyCategory) -> Color {
        if category == .letter {
            return Color(red: 0.07, green: 0.2, blue: 0.055)
        }
        return self.theme.colorScheme.color(for: category).color.darker(by: 0.28)
    }
}

@MainActor
private struct CustomKeyboardThemeCard: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig

    var body: some View {
        StudioCard("appearance.keyboardTheme", systemImage: "keyboard.fill", tint: .blue) {
            SettingsRow("appearance.keycapStyle") {
                Picker("", selection: self.binding(\.keyCapStyle)) {
                    Text(self.strings["style.mechanical"]).tag(KeyCapStyle.mechanical)
                    Text(self.strings["style.flat"]).tag(KeyCapStyle.flat)
                    Text(self.strings["style.minimal"]).tag(KeyCapStyle.minimal)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 280)
            }

            StudioDivider()

            SettingsRow("appearance.background") {
                Picker("", selection: self.binding(\.frameStyle)) {
                    Text(self.strings["background.frame"]).tag(KeyboardFrameStyle.frame)
                    Text(self.strings["background.overlay"]).tag(KeyboardFrameStyle.overlay)
                    Text(self.strings["background.none"]).tag(KeyboardFrameStyle.none)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 280)
            }

            StudioDivider()

            SettingsRow("appearance.fontFamily") {
                FontFamilyComboBox(
                    selection: self.binding(\.fontFamily),
                    strings: self.strings)
                    .frame(width: 220)
            }

            StudioDivider()

            SettingsRow("appearance.fontWeight") {
                Picker("", selection: self.binding(\.fontWeight)) {
                    ForEach(ThemeFontWeight.allCases, id: \.self) { weight in
                        Text(self.strings["font.weight.\(weight.rawValue)"]).tag(weight)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            StudioDivider()

            SettingsRow("appearance.keySpacing") {
                Slider(value: self.binding(\.keySpacing), in: 0...18)
                    .frame(width: 180)
            }

            StudioDivider()

            SettingsRow("appearance.fontScale") {
                Slider(value: self.binding(\.fontScale), in: 0.7...1.4)
                    .frame(width: 180)
            }

            StudioDivider()

            SettingsRow("appearance.textColor") {
                ColorPicker("", selection: self.colorBinding(\.textColor), supportsOpacity: false)
                    .labelsHidden()
            }

            if self.config.appearance.customTheme.keyboard.keyCapStyle != .mechanical {
                StudioDivider()

                SettingsRow("appearance.border") {
                    HStack(spacing: 10) {
                        ColorPicker("", selection: self.colorBinding(\.borderColor), supportsOpacity: false)
                            .labelsHidden()
                        Slider(value: self.binding(\.borderWidth), in: 0...6)
                            .frame(width: 140)
                    }
                }
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<KeyboardTheme, Value>) -> Binding<Value> {
        Binding(
            get: { self.config.appearance.customTheme.keyboard[keyPath: keyPath] },
            set: { value in
                self.config.appearance.customTheme.keyboard[keyPath: keyPath] = value
            })
    }

    private func colorBinding(_ keyPath: WritableKeyPath<KeyboardTheme, KeyColor>) -> Binding<Color> {
        Binding(
            get: { self.config.appearance.customTheme.keyboard[keyPath: keyPath].color },
            set: { color in
                self.config.appearance.customTheme.keyboard[keyPath: keyPath] = KeyColor(color)
            })
    }
}

@MainActor
private struct CustomHUDThemeCard: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig

    var body: some View {
        StudioCard("appearance.hudColors", systemImage: "rectangle.and.text.magnifyingglass", tint: .orange) {
            self.colorRow("appearance.backgroundColor", hud: \.backgroundColor)
            StudioDivider()
            self.colorRow("appearance.textColor", hud: \.textColor)
            StudioDivider()
            self.colorRow("appearance.accentColor", hud: \.accentColor)
        }
    }

    private func colorRow(_ titleKey: String, hud keyPath: WritableKeyPath<HUDPalette, KeyColor>) -> some View {
        SettingsRow(titleKey) {
            ColorPicker(
                "",
                selection: Binding(
                    get: { self.config.appearance.customTheme.hud[keyPath: keyPath].color },
                    set: { color in
                        self.config.appearance.customTheme.hud[keyPath: keyPath] = KeyColor(color)
                    }),
                supportsOpacity: false)
                .labelsHidden()
        }
    }
}

@MainActor
private struct CategoryThemeEditor: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig
    @Binding var selectedCategory: KeyCategory

    private var style: KeyCategoryStyle {
        self.config.appearance.customTheme.keyboard.categoryStyles[self.selectedCategory]
            ?? KeyCategoryStyle.default(
                for: self.selectedCategory,
                scheme: self.config.appearance.customTheme.keyboard.colorScheme)
    }

    private var hasOverride: Bool {
        self.config.appearance.customTheme.keyboard.categoryStyles[self.selectedCategory] != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("", selection: self.$selectedCategory) {
                    ForEach(KeyCategory.allCases, id: \.self) { category in
                        Text(self.strings["category.\(category.rawValue)"]).tag(category)
                    }
                }
                .labelsHidden()
                .frame(width: 220)

                Spacer()

                Toggle(
                    self.strings["appearance.override"],
                    isOn: Binding(
                        get: { self.hasOverride },
                        set: { enabled in
                            if enabled {
                                self.config.appearance.customTheme.keyboard.categoryStyles[self.selectedCategory] =
                                    self.style
                            } else {
                                self.config.appearance.customTheme.keyboard.categoryStyles.removeValue(
                                    forKey: self.selectedCategory)
                            }
                        }))
                        .toggleStyle(.switch)
            }

            if self.hasOverride {
                ThemeValueRow(title: self.strings["appearance.color"]) {
                    ColorPicker("", selection: self.color, supportsOpacity: false)
                        .labelsHidden()
                }

                ThemeValueRow(title: self.strings["appearance.depth"]) {
                    Slider(value: self.depth, in: 0...1)
                    self.percentage(self.style.depth)
                }

                ThemeValueRow(title: self.strings["appearance.corners"]) {
                    Slider(value: self.corners, in: 0...1)
                    self.percentage(self.style.cornerRadius)
                }

                ThemeValueRow(title: self.strings["appearance.shadow"]) {
                    Slider(value: self.shadow, in: 0...1)
                    self.percentage(self.style.shadowIntensity)
                }

                ThemeValueRow(title: self.strings["appearance.categoryStyle"]) {
                    Picker("", selection: self.keyCapStyle) {
                        Text(self.strings["style.mechanical"]).tag(KeyCapStyle.mechanical)
                        Text(self.strings["style.flat"]).tag(KeyCapStyle.flat)
                        Text(self.strings["style.minimal"]).tag(KeyCapStyle.minimal)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            } else {
                Text(self.strings["appearance.override.disabled"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var color: Binding<Color> {
        Binding(
            get: { self.style.color.color },
            set: { color in
                self.updateStyle { $0.color = KeyColor(color) }
            })
    }

    private var depth: Binding<Double> {
        Binding(
            get: { self.style.depth },
            set: { value in
                self.updateStyle { $0.depth = value }
            })
    }

    private var corners: Binding<Double> {
        Binding(
            get: { self.style.cornerRadius },
            set: { value in
                self.updateStyle { $0.cornerRadius = value }
            })
    }

    private var shadow: Binding<Double> {
        Binding(
            get: { self.style.shadowIntensity },
            set: { value in
                self.updateStyle { $0.shadowIntensity = value }
            })
    }

    private var keyCapStyle: Binding<KeyCapStyle> {
        Binding(
            get: { self.style.style },
            set: { value in
                self.updateStyle { $0.style = value }
            })
    }

    private func updateStyle(_ update: (inout KeyCategoryStyle) -> Void) {
        var style = self.style
        update(&style)
        self.config.appearance.customTheme.keyboard.categoryStyles[self.selectedCategory] = style
    }

    private func percentage(_ value: Double) -> some View {
        Text("\(Int(round(value * 100)))%")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 38, alignment: .trailing)
    }
}

private struct ThemeValueRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Text(self.title)
                .frame(width: 90, alignment: .leading)
            self.content()
        }
    }
}

@MainActor
private struct FontFamilyComboBox: NSViewRepresentable {
    @Binding var selection: String?
    let strings: StudioStrings

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selection: self.$selection,
            presetNames: self.presetNames)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.isEditable = true
        comboBox.completes = true
        comboBox.usesDataSource = false
        comboBox.target = context.coordinator
        comboBox.action = #selector(Coordinator.selectionChanged(_:))
        self.updateItems(in: comboBox)
        comboBox.stringValue = self.displayName(for: self.selection)
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        context.coordinator.selection = self.$selection
        context.coordinator.presetNames = self.presetNames
        self.updateItems(in: comboBox)
        let displayName = self.displayName(for: self.selection)
        if comboBox.stringValue != displayName {
            comboBox.stringValue = displayName
        }
    }

    private func updateItems(in comboBox: NSComboBox) {
        var names = self.presetNames
        names.append(contentsOf: ThemeFont.availableFamilies)
        let selectedName = self.displayName(for: self.selection)
        if !names.contains(selectedName) {
            names.append(selectedName)
        }
        let currentNames = comboBox.objectValues.compactMap { $0 as? String }
        guard currentNames != names else { return }
        comboBox.removeAllItems()
        comboBox.addItems(withObjectValues: names)
    }

    private var presetNames: [String] {
        [
            self.strings["font.system"],
            self.strings["font.rounded"],
            self.strings["font.monospaced"],
        ]
    }

    private func displayName(for selection: String?) -> String {
        switch selection {
        case nil: self.strings["font.system"]
        case ThemeFont.rounded: self.strings["font.rounded"]
        case ThemeFont.monospaced: self.strings["font.monospaced"]
        case let family?: family
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<String?>
        var presetNames: [String]

        init(selection: Binding<String?>, presetNames: [String]) {
            self.selection = selection
            self.presetNames = presetNames
        }

        @objc func selectionChanged(_ sender: NSComboBox) {
            let selection: String? = switch sender.indexOfSelectedItem {
            case 0: nil
            case 1: ThemeFont.rounded
            case 2: ThemeFont.monospaced
            default:
                switch sender.stringValue {
                case self.presetNames[0]: nil
                case self.presetNames[1]: ThemeFont.rounded
                case self.presetNames[2]: ThemeFont.monospaced
                default: sender.stringValue
                }
            }
            self.selection.wrappedValue = selection
        }
    }
}

@MainActor
struct KeyPreview: View {
    @Environment(\.studioStrings) private var strings
    let config: KeypressConfig

    var body: some View {
        StudioPreviewSurface(height: 190) {
            HStack(spacing: 12) {
                self.specimen(
                    titleKey: "preview.resting",
                    isPressed: false)

                self.specimen(
                    titleKey: "preview.pressed",
                    isPressed: true)
            }
            .padding(12)
        }
    }

    private func specimen(titleKey: String, isPressed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(self.strings[titleKey])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer(minLength: 8)

                Text(self.contentModeTitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            KeyboardThemeContainer(config: self.config, disableOuterShadow: true) {
                self.keys(isPressed: isPressed)
            }
            .scaleEffect(self.previewScale)
            .opacity(self.config.keyboard.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 154)
        .background(
            Color.black.opacity(isPressed ? 0.22 : 0.14),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(isPressed ? 0.13 : 0.08))
        }
    }

    private func keys(isPressed: Bool) -> some View {
        HStack(spacing: CGFloat(self.keyboardTheme.keySpacing)) {
            ForEach(self.previewSymbols) { symbol in
                KeyCapView(
                    symbol: symbol,
                    config: self.config,
                    isPressed: isPressed && (
                        symbol.isModifier
                            ? self.config.keyboard.pressAnimationModifiers
                            : self.config.keyboard.pressAnimationRegularKeys))
            }
        }
    }

    private var previewSymbols: [KeySymbol] {
        [
            KeySymbol(id: "shift-left", display: "⇧", isModifier: true),
            KeySymbol(id: "command-left", display: "⌘", isModifier: true),
            self.config.keyboard.effectiveContentMode == .allKeys
                ? KeySymbol(id: "key-40", display: "K")
                : KeySymbol(id: "key-9", display: "V"),
        ]
    }

    private var contentModeTitle: String {
        switch self.config.keyboard.effectiveContentMode {
        case .allKeys:
            self.strings["keyboard.content.all"]
        case .shortcutsOnly:
            self.strings["keyboard.content.shortcuts"]
        }
    }

    private var previewScale: CGFloat {
        min(self.config.keyboard.size.scaleFactor * 0.74, 0.9)
    }

    private var keyboardTheme: KeyboardTheme {
        self.config.effectiveTheme(isSystemDark: self.isSystemDark).keyboard
    }

    private var isSystemDark: Bool {
        guard let appearance = NSApp?.effectiveAppearance else { return true }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
