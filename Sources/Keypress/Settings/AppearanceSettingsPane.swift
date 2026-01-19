import AppKit
import KeypressCore
import SwiftUI

// MARK: - KeyStyleSettingsMetrics

private enum KeyStyleSettingsMetrics {
    static let sidebarWidth: CGFloat = 200
    static let sidebarCornerRadius: CGFloat = 10
    static let detailMaxWidth: CGFloat = 400
    static let iconSize: CGFloat = 16
    static let rowSpacing: CGFloat = 8
    static let sliderWidth: CGFloat = 180
}

// MARK: - AppearanceSettingsPane

@MainActor
struct AppearanceSettingsPane: View {
    @Bindable var config: KeypressConfig

    var body: some View {
        if self.config.appearanceMode == .custom {
            self.customModeLayout
        } else {
            self.standardLayout
        }
    }

    // MARK: - Standard Layout (non-custom modes)

    private var standardLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Preview
            KeyPreview(config: self.config)

            Divider()

            // Color Scheme
            SettingsRow("Color Scheme", subtitle: self.appearanceModeDescription) {
                Picker("", selection: self.$config.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            Spacer()
        }
        .padding(.top, 12)
        .padding(.horizontal, 12)
    }

    // MARK: - Custom Mode Layout (full-height master-detail)

    private var customModeLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Preview
            KeyPreview(config: self.config)

            Divider()

            // Color Scheme Picker
            SettingsRow("Color Scheme", subtitle: self.appearanceModeDescription) {
                Picker("", selection: self.$config.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            Divider()

            // Full-height Master-Detail
            KeyStyleEditor(config: self.config)
        }
        .padding(.top, 12)
        .padding(.horizontal, 12)
    }

    private var appearanceModeDescription: String {
        switch self.config.appearanceMode {
        case .auto: "Follows system light/dark mode."
        case .dark: "Dark keys with colored modifiers."
        case .monochrome: "All dark keys, no color."
        case .light: "Light keys with colored modifiers."
        case .custom: "Customize colors and styles for each key category."
        }
    }
}

// MARK: - KeyCapStyle Extension

extension KeyCapStyle {
    var displayName: String {
        switch self {
        case .mechanical: "Mechanical"
        case .flat: "Flat"
        case .minimal: "Minimal"
        }
    }

    var description: String {
        switch self {
        case .mechanical: "3D skeuomorphic keycaps with depth and shadows."
        case .flat: "Modern flat design with subtle shadows."
        case .minimal: "Compact pill-shaped keys with text."
        }
    }
}

// MARK: - KeyboardFrameStyle Extension

extension KeyboardFrameStyle {
    var displayName: String {
        switch self {
        case .frame: "Frame"
        case .overlay: "Overlay"
        case .none: "None"
        }
    }

    var description: String {
        switch self {
        case .frame: "3D keyboard frame with depth and materials."
        case .overlay: "Simple semi-transparent dark background."
        case .none: "No background, keys float freely."
        }
    }
}

// MARK: - KeyStyleEditor

@MainActor
struct KeyStyleEditor: View {
    @Bindable var config: KeypressConfig
    @State private var selectedCategory: KeyCategory = .command

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            CategorySidebarView(
                config: self.config,
                selection: self.$selectedCategory)

            CategoryDetailView(
                config: self.config,
                category: self.selectedCategory)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - CategorySidebarView

@MainActor
private struct CategorySidebarView: View {
    @Bindable var config: KeypressConfig
    @Binding var selection: KeyCategory

    var body: some View {
        List(selection: self.$selection) {
            ForEach(KeyCategory.allCases, id: \.self) { category in
                CategorySidebarRow(
                    config: self.config,
                    category: category)
                    .tag(category)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(
            RoundedRectangle(cornerRadius: KeyStyleSettingsMetrics.sidebarCornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: KeyStyleSettingsMetrics.sidebarCornerRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: KeyStyleSettingsMetrics.sidebarCornerRadius, style: .continuous))
        .frame(width: KeyStyleSettingsMetrics.sidebarWidth)
        .frame(maxHeight: .infinity)
    }
}

// MARK: - CategorySidebarRow

@MainActor
private struct CategorySidebarRow: View {
    @Bindable var config: KeypressConfig
    let category: KeyCategory

    private var hasOverride: Bool {
        self.config.hasStyleOverride(for: self.category)
    }

    private var color: Color {
        self.config.effectiveStyle(for: self.category).color.color
    }

    var body: some View {
        HStack(spacing: 10) {
            // Color indicator
            RoundedRectangle(cornerRadius: 4)
                .fill(self.color)
                .frame(width: KeyStyleSettingsMetrics.iconSize, height: KeyStyleSettingsMetrics.iconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.category.displayName)
                    .font(.subheadline.weight(.medium))

                Text(self.hasOverride ? "Custom" : "Default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            // Checkbox to toggle custom override
            Toggle("", isOn: Binding(
                get: { self.hasOverride },
                set: { enabled in
                    if enabled {
                        let style = self.config.effectiveStyle(for: self.category)
                        self.config.setStyleOverride(style, for: self.category)
                    } else {
                        self.config.setStyleOverride(nil, for: self.category)
                    }
                }))
                .toggleStyle(.checkbox)
                .labelsHidden()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

// MARK: - CategoryDetailView

@MainActor
private struct CategoryDetailView: View {
    @Bindable var config: KeypressConfig
    let category: KeyCategory

    private var style: KeyCategoryStyle {
        self.config.effectiveStyle(for: self.category)
    }

    private var hasOverride: Bool {
        self.config.hasStyleOverride(for: self.category)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            self.headerSection

            Divider()

            // Style Settings
            self.styleSettings

            Spacer()
        }
        .frame(maxWidth: KeyStyleSettingsMetrics.detailMaxWidth, alignment: .leading)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(self.style.color.color)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.category.displayName)
                    .font(.title3.weight(.semibold))

                Text(self.category.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Toggle("Custom", isOn: Binding(
                get: { self.hasOverride },
                set: { enabled in
                    if enabled {
                        // Create override from current effective style
                        self.config.setStyleOverride(self.style, for: self.category)
                    } else {
                        // Remove override
                        self.config.setStyleOverride(nil, for: self.category)
                    }
                }))
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    // MARK: - Style Settings

    @ViewBuilder
    private var styleSettings: some View {
        if self.hasOverride {
            VStack(alignment: .leading, spacing: 12) {
                // Color picker
                StyleSettingRow(label: "Color") {
                    ColorPicker(
                        "",
                        selection: self.colorBinding,
                        supportsOpacity: false)
                        .labelsHidden()
                }

                // Depth slider
                StyleSettingRow(label: "Depth") {
                    Slider(value: self.depthBinding, in: 0...1)
                        .frame(width: KeyStyleSettingsMetrics.sliderWidth)
                    Text(String(format: "%.0f%%", self.style.depth * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                // Corner radius slider
                StyleSettingRow(label: "Corners") {
                    Slider(value: self.cornerRadiusBinding, in: 0...1)
                        .frame(width: KeyStyleSettingsMetrics.sliderWidth)
                    Text(String(format: "%.0f%%", self.style.cornerRadius * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                // Shadow intensity slider
                StyleSettingRow(label: "Shadow") {
                    Slider(value: self.shadowBinding, in: 0...1)
                        .frame(width: KeyStyleSettingsMetrics.sliderWidth)
                    Text(String(format: "%.0f%%", self.style.shadowIntensity * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                // Keycap style picker
                StyleSettingRow(label: "Style") {
                    Picker("", selection: self.keyCapStyleBinding) {
                        ForEach(KeyCapStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Using default style from color scheme.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Enable \"Custom\" to customize this category.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Bindings

    private var colorBinding: Binding<Color> {
        Binding(
            get: { self.style.color.color },
            set: { newColor in
                var updated = self.style
                updated.color = KeyColor(newColor)
                self.config.setStyleOverride(updated, for: self.category)
            })
    }

    private var depthBinding: Binding<Double> {
        Binding(
            get: { self.style.depth },
            set: { newValue in
                var updated = self.style
                updated.depth = newValue
                self.config.setStyleOverride(updated, for: self.category)
            })
    }

    private var cornerRadiusBinding: Binding<Double> {
        Binding(
            get: { self.style.cornerRadius },
            set: { newValue in
                var updated = self.style
                updated.cornerRadius = newValue
                self.config.setStyleOverride(updated, for: self.category)
            })
    }

    private var shadowBinding: Binding<Double> {
        Binding(
            get: { self.style.shadowIntensity },
            set: { newValue in
                var updated = self.style
                updated.shadowIntensity = newValue
                self.config.setStyleOverride(updated, for: self.category)
            })
    }

    private var keyCapStyleBinding: Binding<KeyCapStyle> {
        Binding(
            get: { self.style.style },
            set: { newValue in
                var updated = self.style
                updated.style = newValue
                self.config.setStyleOverride(updated, for: self.category)
            })
    }
}

// MARK: - StyleSettingRow

private struct StyleSettingRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Text(self.label)
                .font(.subheadline)
                .frame(width: 60, alignment: .leading)

            self.content()
        }
    }
}

// MARK: - KeyCategory Extension

extension KeyCategory {
    var displayName: String {
        switch self {
        case .letter: "Letters & Digits"
        case .command: "Command ⌘"
        case .shift: "Shift ⇧"
        case .option: "Option ⌥"
        case .control: "Control ⌃"
        case .capsLock: "Caps Lock ⇪"
        case .escape: "Escape ⎋"
        case .function: "Function"
        case .navigation: "Navigation"
        case .editing: "Editing"
        }
    }

    var description: String {
        switch self {
        case .letter: "A-Z, 0-9"
        case .command: "Command modifier key"
        case .shift: "Shift modifier key"
        case .option: "Option/Alt modifier key"
        case .control: "Control modifier key"
        case .capsLock: "Caps Lock toggle"
        case .escape: "Escape key"
        case .function: "F1-F20 function keys"
        case .navigation: "Arrows, Page Up/Down, Home, End"
        case .editing: "Space, Tab, Return, Delete"
        }
    }
}

// MARK: - KeyPreview

@MainActor
struct KeyPreview: View {
    let config: KeypressConfig

    private let previewHeight: CGFloat = 160

    private var keysView: some View {
        HStack(spacing: 6) {
            KeyCapView(
                symbol: KeySymbol(id: "command-left", display: "⌘", isModifier: true),
                config: self.config)
            KeyCapView(
                symbol: KeySymbol(id: "shift-left", display: "⇧", isModifier: true),
                config: self.config)
            KeyCapView(
                symbol: KeySymbol(id: "k", display: "K"),
                config: self.config)
        }
    }

    private var styledKeysView: some View {
        Group {
            switch self.config.keyboardFrameStyle {
            case .frame:
                KeyboardFrameView(config: self.config) {
                    self.keysView
                }
            case .overlay:
                self.keysView
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.black.opacity(0.7))
                            .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8))
            case .none:
                self.keysView
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Wallpaper background
                WallpaperBackgroundView(
                    position: self.config.position,
                    containerSize: geometry.size)

                // Keys positioned according to config.position
                self.styledKeysView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: self.config.position.alignment)
                    .padding(16)
            }
        }
        .frame(height: self.previewHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

// MARK: - WallpaperBackgroundView

@MainActor
struct WallpaperBackgroundView: View {
    let position: OverlayPosition
    let containerSize: CGSize

    @State private var wallpaperImage: NSImage?
    @State private var refreshID = UUID()

    private var screenSize: CGSize {
        NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
    }

    var body: some View {
        GeometryReader { geometry in
            if let wallpaper = self.wallpaperImage {
                Image(nsImage: wallpaper)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: self.scaledWallpaperSize.width,
                        height: self.scaledWallpaperSize.height)
                    .offset(self.wallpaperOffset(containerSize: geometry.size))
                    .clipped()
            } else {
                // Fallback gradient
                LinearGradient(
                    colors: [Color(white: 0.15), Color(white: 0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
            }
        }
        .id(self.refreshID)
        .onAppear {
            self.loadWallpaper()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)) { _ in
            self.loadWallpaper()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            self.loadWallpaper()
        }
    }

    /// Loads the current wallpaper image from disk, bypassing any cache.
    private func loadWallpaper() {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen)
        else { return }

        // Load fresh, bypassing NSImage cache
        guard let imageData = try? Data(contentsOf: url),
              let image = NSImage(data: imageData)
        else { return }

        self.wallpaperImage = image
        self.refreshID = UUID()
    }

    private var scaledWallpaperSize: CGSize {
        let scale = self.containerSize.height / (self.screenSize.height * 0.25)
        return CGSize(
            width: self.screenSize.width * scale,
            height: self.screenSize.height * scale)
    }

    private func wallpaperOffset(containerSize: CGSize) -> CGSize {
        let wallpaperSize = self.scaledWallpaperSize
        let excessWidth = wallpaperSize.width - containerSize.width
        let excessHeight = wallpaperSize.height - containerSize.height

        switch self.position {
        case .topLeft:
            return CGSize(width: 0, height: 0)
        case .topCenter:
            return CGSize(width: -excessWidth / 2, height: 0)
        case .topRight:
            return CGSize(width: -excessWidth, height: 0)
        case .centerLeft:
            return CGSize(width: 0, height: -excessHeight / 2)
        case .centerRight:
            return CGSize(width: -excessWidth, height: -excessHeight / 2)
        case .bottomLeft:
            return CGSize(width: 0, height: -excessHeight)
        case .bottomCenter:
            return CGSize(width: -excessWidth / 2, height: -excessHeight)
        case .bottomRight:
            return CGSize(width: -excessWidth, height: -excessHeight)
        }
    }
}

// MARK: - OverlayPosition Alignment Extension

extension OverlayPosition {
    var alignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .topCenter: .top
        case .topRight: .topTrailing
        case .centerLeft: .leading
        case .centerRight: .trailing
        case .bottomLeft: .bottomLeading
        case .bottomCenter: .bottom
        case .bottomRight: .bottomTrailing
        }
    }
}
