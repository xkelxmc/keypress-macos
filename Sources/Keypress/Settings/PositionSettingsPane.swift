import AppKit
import KeypressCore
import SwiftUI

// MARK: - Desktop Wallpaper Helper

@MainActor
private func desktopWallpaper(for screen: NSScreen) -> NSImage? {
    guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
    return NSImage(contentsOf: url)
}

// MARK: - PositionSettingsPane

@MainActor
struct PositionSettingsPane: View {
    @Bindable var config: KeypressConfig

    var body: some View {
        VStack(spacing: 0) {
            // Monitor visualization area
            MonitorVisualization(config: self.config)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.top, 12)
                .padding(.horizontal, 12)

            // Monitor list
            MonitorListView(config: self.config)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

            // Offset controls
            PositionOffsetControls(config: self.config)
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
        }
    }
}

// MARK: - MonitorVisualization

@MainActor
private struct MonitorVisualization: View {
    @Bindable var config: KeypressConfig

    private var isAutoMode: Bool {
        if case .auto = self.config.monitorSelection {
            return true
        }
        return false
    }

    var body: some View {
        GeometryReader { geometry in
            if self.isAutoMode {
                // Auto mode: single abstract monitor
                AutoModeMonitorView(config: self.config, containerSize: geometry.size)
            } else {
                // Fixed mode: show all monitors
                let layout = MonitorLayout(screens: NSScreen.screens, containerSize: geometry.size)

                ZStack {
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        MonitorView(
                            config: self.config,
                            screen: screen,
                            index: index,
                            isSelected: self.isMonitorSelected(index),
                            frame: layout.frame(for: index))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
    }

    private func isMonitorSelected(_ index: Int) -> Bool {
        switch self.config.monitorSelection {
        case .auto:
            false
        case let .fixed(selectedIndex):
            index == selectedIndex
        }
    }
}

// MARK: - AutoModeMonitorView

@MainActor
private struct AutoModeMonitorView: View {
    @Bindable var config: KeypressConfig
    let containerSize: CGSize

    private var monitorSize: CGSize {
        // 16:10 aspect ratio, fit in container
        let aspectRatio: CGFloat = 16 / 10
        let padding: CGFloat = 60
        let maxWidth = self.containerSize.width - padding * 2
        let maxHeight = self.containerSize.height - padding * 2

        let widthFromHeight = maxHeight * aspectRatio
        let heightFromWidth = maxWidth / aspectRatio

        if widthFromHeight <= maxWidth {
            return CGSize(width: widthFromHeight, height: maxHeight)
        } else {
            return CGSize(width: maxWidth, height: heightFromWidth)
        }
    }

    private var mainScreen: NSScreen {
        NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    var body: some View {
        ZStack {
            // Monitor background with wallpaper
            Group {
                if let wallpaper = desktopWallpaper(for: self.mainScreen) {
                    Image(nsImage: wallpaper)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color(white: 0.25)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.4)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 2))

            // Position indicators only
            PositionIndicatorsView(
                config: self.config,
                monitorIndex: 0,
                isSelected: true,
                isAutoMode: true)
                .padding(12)
        }
        .frame(width: self.monitorSize.width, height: self.monitorSize.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - MonitorLayout

private struct MonitorLayout {
    let screens: [NSScreen]
    let containerSize: CGSize

    private var unionFrame: CGRect {
        self.screens.reduce(.null) { $0.union($1.frame) }
    }

    private var scale: CGFloat {
        let union = self.unionFrame
        let padding: CGFloat = 40
        let availableWidth = self.containerSize.width - padding * 2
        let availableHeight = self.containerSize.height - padding * 2

        guard union.width > 0, union.height > 0 else { return 0.1 }

        let scaleX = availableWidth / union.width
        let scaleY = availableHeight / union.height

        // Use smaller scale to fit, cap at 20% for reasonable size
        return min(scaleX, scaleY, 0.20)
    }

    func frame(for index: Int) -> CGRect {
        guard index < self.screens.count else { return .zero }

        let screen = self.screens[index]
        let union = self.unionFrame
        let scale = self.scale

        // Gap between monitors (in visualization pixels)
        let gap: CGFloat = 6

        // Convert screen frame to visualization coordinates
        // NSScreen origin is bottom-left, we need top-left
        var x = (screen.frame.minX - union.minX) * scale
        var y = (union.maxY - screen.frame.maxY) * scale
        let width = screen.frame.width * scale
        let height = screen.frame.height * scale

        // Add gap based on relative position
        if screen.frame.minX > union.minX {
            x += gap
        }
        if screen.frame.maxY < union.maxY {
            y += gap
        }

        // Center in container (account for gaps in total size)
        let totalWidth = union.width * scale + gap
        let totalHeight = union.height * scale + gap
        let offsetX = (self.containerSize.width - totalWidth) / 2
        let offsetY = (self.containerSize.height - totalHeight) / 2

        return CGRect(x: x + offsetX, y: y + offsetY, width: width, height: height)
    }
}

// MARK: - MonitorView

@MainActor
private struct MonitorView: View {
    @Bindable var config: KeypressConfig
    let screen: NSScreen
    let index: Int
    let isSelected: Bool
    let frame: CGRect

    var body: some View {
        ZStack {
            // Monitor background with wallpaper
            Group {
                if let wallpaper = desktopWallpaper(for: self.screen) {
                    Image(nsImage: wallpaper)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color(white: 0.25)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                // Dimming overlay for better visibility
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.4)))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(self.isSelected ? Color.accentColor : Color(white: 0.4), lineWidth: 2))

            // Position indicators (rectangles)
            PositionIndicatorsView(
                config: self.config,
                monitorIndex: self.index,
                isSelected: self.isSelected)
                .padding(8)

            // Monitor name centered
            Text(self.screen.localizedName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
        }
        .frame(width: self.frame.width, height: self.frame.height)
        .position(x: self.frame.midX, y: self.frame.midY)
        .onTapGesture {
            self.selectMonitor()
        }
    }

    private func selectMonitor() {
        withAnimation(.easeInOut(duration: 0.15)) {
            self.config.monitorSelection = .fixed(index: self.index)
        }
    }
}

// MARK: - PositionIndicatorsView

@MainActor
private struct PositionIndicatorsView: View {
    @Bindable var config: KeypressConfig
    let monitorIndex: Int
    let isSelected: Bool
    var isAutoMode: Bool = false

    // Dynamic size based on container - roughly 16% width, 10% height
    private func indicatorSize(for containerSize: CGSize) -> CGSize {
        let width = max(30, min(80, containerSize.width * 0.16))
        let height = max(14, min(32, containerSize.height * 0.10))
        return CGSize(width: width, height: height)
    }

    private func cornerRadius(for containerSize: CGSize) -> CGFloat {
        let size = self.indicatorSize(for: containerSize)
        return min(size.height * 0.3, 6)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = self.indicatorSize(for: geometry.size)
            let radius = self.cornerRadius(for: geometry.size)
            let positions = OverlayPosition.allCases

            ForEach(positions, id: \.self) { position in
                let isActivePosition = self.isSelected && self.config.position == position
                RoundedRectangle(cornerRadius: radius)
                    .fill(self.indicatorFillColor(for: position))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius)
                            .stroke(
                                self.indicatorStrokeColor(for: position),
                                lineWidth: isActivePosition ? 2 : 1))
                    .shadow(
                        color: isActivePosition ? Color.green.opacity(0.6) : Color.clear,
                        radius: 4,
                        x: 0,
                        y: 0)
                    .frame(width: size.width, height: size.height)
                    .position(self.indicatorPosition(for: position, in: geometry.size, indicatorSize: size))
                    .onTapGesture {
                        self.selectPosition(position)
                    }
            }
        }
    }

    private func indicatorFillColor(for position: OverlayPosition) -> Color {
        if self.isSelected, self.config.position == position {
            return Color.green.opacity(0.9)
        }
        return Color(white: 0.3).opacity(0.8)
    }

    private func indicatorStrokeColor(for position: OverlayPosition) -> Color {
        if self.isSelected, self.config.position == position {
            return Color.green
        }
        return Color(white: 0.6)
    }

    private func selectPosition(_ position: OverlayPosition) {
        withAnimation(.easeInOut(duration: 0.15)) {
            // Select this monitor if not in auto mode
            if !self.isAutoMode, NSScreen.screens.count > 1 {
                self.config.monitorSelection = .fixed(index: self.monitorIndex)
            }
            // Select position
            self.config.position = position
        }
    }

    private func indicatorPosition(
        for position: OverlayPosition,
        in containerSize: CGSize,
        indicatorSize: CGSize) -> CGPoint
    {
        let marginX: CGFloat = indicatorSize.width / 2 + 8
        let marginY: CGFloat = indicatorSize.height / 2 + 8

        switch position {
        case .topLeft:
            return CGPoint(x: marginX, y: marginY)
        case .topCenter:
            return CGPoint(x: containerSize.width / 2, y: marginY)
        case .topRight:
            return CGPoint(x: containerSize.width - marginX, y: marginY)
        case .centerLeft:
            return CGPoint(x: marginX, y: containerSize.height / 2)
        case .centerRight:
            return CGPoint(x: containerSize.width - marginX, y: containerSize.height / 2)
        case .bottomLeft:
            return CGPoint(x: marginX, y: containerSize.height - marginY)
        case .bottomCenter:
            return CGPoint(x: containerSize.width / 2, y: containerSize.height - marginY)
        case .bottomRight:
            return CGPoint(x: containerSize.width - marginX, y: containerSize.height - marginY)
        }
    }
}

// MARK: - MonitorListView

@MainActor
private struct MonitorListView: View {
    @Bindable var config: KeypressConfig

    private var isAutoMode: Bool {
        if case .auto = self.config.monitorSelection {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 12) {
            // Auto mode row (only show if multiple monitors)
            if NSScreen.screens.count > 1 {
                AutoModeRow(config: self.config)
            }

            // Individual monitor rows (always show)
            ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                MonitorRowView(
                    config: self.config,
                    screen: screen,
                    index: index,
                    isAutoMode: self.isAutoMode)
            }
        }
    }
}

// MARK: - AutoModeRow

@MainActor
private struct AutoModeRow: View {
    @Bindable var config: KeypressConfig

    private var isAutoMode: Bool {
        if case .auto = self.config.monitorSelection {
            return true
        }
        return false
    }

    var body: some View {
        HStack(spacing: 16) {
            // Selection indicator
            Image(systemName: self.isAutoMode ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(self.isAutoMode ? Color.green : Color.secondary)
                .font(.title2)

            // Description
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto")
                    .font(.body.weight(.medium))

                Text("Show on monitor with focused window")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Position picker
            if self.isAutoMode {
                VStack(alignment: .center, spacing: 2) {
                    Picker("", selection: self.$config.position) {
                        ForEach(OverlayPosition.allCases, id: \.self) { position in
                            Text(position.displayName).tag(position)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)

                    Text("Position")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .center, spacing: 2) {
                    Picker("", selection: self.$config.size) {
                        ForEach(OverlaySize.allCases, id: \.self) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 100)

                    Text("Size")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(self.isAutoMode ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                self.config.monitorSelection = .auto
            }
        }
    }
}

// MARK: - MonitorRowView

@MainActor
private struct MonitorRowView: View {
    @Bindable var config: KeypressConfig
    let screen: NSScreen
    let index: Int
    var isAutoMode: Bool = false

    private var isSelected: Bool {
        switch self.config.monitorSelection {
        case .auto:
            false
        case let .fixed(selectedIndex):
            self.index == selectedIndex
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Selection indicator
            Image(systemName: self.isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(self.isSelected ? Color.green : Color.secondary)
                .font(.title2)

            // Monitor name
            Text(self.screen.localizedName)
                .font(.body.weight(.medium))
                .frame(minWidth: 140, alignment: .leading)

            Spacer()

            // Position picker
            VStack(alignment: .center, spacing: 2) {
                Picker("", selection: self.$config.position) {
                    ForEach(OverlayPosition.allCases, id: \.self) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 140)
                .disabled(!self.isSelected)

                Text("Position")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Size picker
            VStack(alignment: .center, spacing: 2) {
                Picker("", selection: self.$config.size) {
                    ForEach(OverlaySize.allCases, id: \.self) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 100)
                .disabled(!self.isSelected)

                Text("Size")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(self.isSelected ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture {
            self.selectMonitor()
        }
    }

    private func selectMonitor() {
        withAnimation(.easeInOut(duration: 0.15)) {
            self.config.monitorSelection = .fixed(index: self.index)
        }
    }
}

// MARK: - PositionOffsetControls

@MainActor
private struct PositionOffsetControls: View {
    @Bindable var config: KeypressConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edge Offset")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                // Horizontal offset
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Slider(value: self.$config.horizontalOffset, in: 0...500, step: 10)
                    Text("\(Int(self.config.horizontalOffset))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)

                // Vertical offset
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Slider(value: self.$config.verticalOffset, in: 0...300, step: 10)
                    Text("\(Int(self.config.verticalOffset))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor)))
    }
}

// MARK: - OverlayPosition Extension

extension OverlayPosition {
    var displayName: String {
        switch self {
        case .topLeft: "Top Left"
        case .topCenter: "Top Center"
        case .topRight: "Top Right"
        case .centerLeft: "Center Left"
        case .centerRight: "Center Right"
        case .bottomLeft: "Bottom Left"
        case .bottomCenter: "Bottom Center"
        case .bottomRight: "Bottom Right"
        }
    }
}
