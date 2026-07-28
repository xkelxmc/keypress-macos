import AppKit
import KeypressCore
import SwiftUI

@MainActor
struct PositionSettingsPane: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig
    let openSettings: () -> Void
    @State private var selectedDisplayID: UUID?
    @State private var displayConfigurationID = UUID()

    private var displays: [ConnectedDisplay] {
        _ = self.displayConfigurationID
        return ConnectedDisplays.all
    }

    var body: some View {
        StudioPage(
            titleKey: "displays.title",
            subtitleKey: "displays.subtitle")
        {
            if self.config.keyboard.enabled {
                StudioCard("displays.target", systemImage: "scope", tint: .cyan) {
                    Picker("", selection: self.targetMode) {
                        Text(self.strings["displays.target.pointer"]).tag(DisplayTargetMode.followPointer)
                        Text(self.strings["displays.target.fixed"]).tag(DisplayTargetMode.fixed)
                        Text(self.strings["displays.target.selected"]).tag(DisplayTargetMode.selected)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    Text(self.strings["displays.target.help"])
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let display = self.selectedDisplay {
                    DisplayPlacementCard(config: self.config, display: display)
                }

                DisplayTopologyPreview(
                    displays: self.displays,
                    target: self.config.displays.target,
                    selectedDisplayID: self.effectiveSelectedDisplayID,
                    select: { self.selectedDisplayID = $0 })

                StudioCard("displays.connected", systemImage: "display.2", tint: .blue) {
                    if self.displays.isEmpty {
                        ContentUnavailableView(
                            self.strings["displays.empty"],
                            systemImage: "display.trianglebadge.exclamationmark")
                    } else {
                        ForEach(Array(self.displays.enumerated()), id: \.element.id) { index, display in
                            if index > 0 {
                                StudioDivider()
                            }
                            DisplaySettingsRow(
                                config: self.config,
                                display: display,
                                isSelected: self.effectiveSelectedDisplayID == display.id,
                                select: {
                                    self.selectedDisplayID = display.id
                                },
                                edit: {
                                    self.selectedDisplayID = display.id
                                    DisplayPlacementEditorController.shared.show(for: display.id)
                                })
                        }
                    }
                }
            } else {
                DisabledFeatureView(
                    titleKey: "keyboard.disabled.title",
                    subtitleKey: "keyboard.disabled.subtitle",
                    buttonKey: "keyboard.disabled.action",
                    systemImage: "keyboard",
                    tint: .blue,
                    action: self.openSettings)
            }
        }
        .onAppear {
            if self.selectedDisplayID == nil {
                self.selectedDisplayID = self.initialSelectedDisplayID
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification))
        { _ in
            self.displayConfigurationID = UUID()
            if let selectedDisplayID,
               !self.displays.contains(where: { $0.id == selectedDisplayID })
            {
                self.selectedDisplayID = self.initialSelectedDisplayID
            }
        }
    }

    private var targetMode: Binding<DisplayTargetMode> {
        Binding(
            get: {
                switch self.config.displays.target {
                case .followPointer: .followPointer
                case .fixed: .fixed
                case .selected: .selected
                }
            },
            set: { mode in
                let displayID = self.effectiveSelectedDisplayID ?? self.displays.first?.id
                switch mode {
                case .followPointer:
                    self.config.displays.target = .followPointer
                case .fixed:
                    if let displayID {
                        self.config.displays.target = .fixed(displayID)
                    }
                case .selected:
                    if let displayID {
                        let connectedIDs = Set(self.displays.map(\.id))
                        let rememberedIDs = self.config.displays.rememberedSelectedDisplayIDs
                            .intersection(connectedIDs)
                        let selectedIDs = rememberedIDs.isEmpty ? [displayID] : rememberedIDs
                        self.config.displays.rememberedSelectedDisplayIDs = selectedIDs
                        self.config.displays.target = .selected(selectedIDs)
                    }
                }
            })
    }

    private var initialSelectedDisplayID: UUID? {
        switch self.config.displays.target {
        case .followPointer:
            ConnectedDisplays.main?.id
        case let .fixed(id):
            id
        case let .selected(ids):
            self.displays.first { ids.contains($0.id) }?.id ?? ids.first
        }
    }

    private var effectiveSelectedDisplayID: UUID? {
        self.selectedDisplayID ?? self.initialSelectedDisplayID
    }

    private var selectedDisplay: ConnectedDisplay? {
        guard let id = self.effectiveSelectedDisplayID else { return nil }
        return self.displays.first { $0.id == id }
    }
}

private enum DisplayTargetMode: Hashable {
    case followPointer
    case fixed
    case selected
}

@MainActor
private struct DisplaySettingsRow: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig
    let display: ConnectedDisplay
    let isSelected: Bool
    let select: () -> Void
    let edit: () -> Void

    private var isTargeted: Bool {
        switch self.config.displays.target {
        case .followPointer:
            false
        case let .fixed(id):
            id == self.display.id
        case let .selected(ids):
            ids.contains(self.display.id)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            switch self.config.displays.target {
            case .followPointer:
                Image(systemName: "cursorarrow.rays")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            case .fixed:
                Button(action: self.toggleTarget) {
                    Image(systemName: self.isTargeted ? "record.circle.fill" : "circle")
                        .foregroundStyle(self.isTargeted ? Color.accentColor : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(self.display.name)
                .accessibilityAddTraits(self.isTargeted ? .isSelected : [])
            case .selected:
                Toggle(
                    self.display.name,
                    isOn: Binding(
                        get: { self.isTargeted },
                        set: { _ in self.toggleTarget() }))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .disabled(self.isTargeted && self.selectedTargetCount == 1)
                    .accessibilityLabel(self.display.name)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(self.display.name)
                        .fontWeight(.medium)
                    if self.display.isMain {
                        Text(self.strings["displays.main"])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(self.placementSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(self.strings["displays.edit"], action: self.edit)
                .buttonStyle(.bordered)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: self.select)
        .padding(.vertical, 2)
        .background {
            if self.isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.10))
                    .padding(-8)
            }
        }
    }

    private var selectedTargetCount: Int {
        guard case let .selected(ids) = self.config.displays.target else { return 0 }
        return ids.count
    }

    private var placementSummary: String {
        switch self.config.displays.placement(for: self.display.id) {
        case let .anchor(position, _, _):
            self.strings["position.\(position.rawValue)"]
        case .custom:
            self.strings["position.custom"]
        }
    }

    private func toggleTarget() {
        switch self.config.displays.target {
        case .followPointer:
            break
        case .fixed:
            self.config.displays.target = .fixed(self.display.id)
        case var .selected(ids):
            if ids.contains(self.display.id) {
                guard ids.count > 1 else { return }
                ids.remove(self.display.id)
            } else {
                ids.insert(self.display.id)
            }
            self.config.displays.rememberedSelectedDisplayIDs = ids
            self.config.displays.target = .selected(ids)
        }
    }
}

@MainActor
private struct DisplayPlacementCard: View {
    @Environment(\.studioStrings) private var strings
    @Bindable var config: KeypressConfig
    let display: ConnectedDisplay

    var body: some View {
        StudioCard("displays.placement", systemImage: "arrow.up.left.and.arrow.down.right", tint: .green) {
            Button {
                DisplayPlacementEditorController.shared.show(for: self.display.id)
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: "hand.draw.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.green)
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(
                            Color.green.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(self.strings["displays.edit"])
                            .font(.headline)
                        Text(self.strings["displays.custom.help"])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 16)

                    Text(self.currentPlacementLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(13)
                .contentShape(Rectangle())
                .background(
                    Color.green.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.16))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var currentPlacementLabel: String {
        switch self.config.displays.placement(for: self.display.id) {
        case let .anchor(position, _, _):
            self.strings["position.\(position.rawValue)"]
        case .custom:
            self.strings["position.custom"]
        }
    }
}

@MainActor
private struct DisplayTopologyPreview: View {
    let displays: [ConnectedDisplay]
    let target: DisplayTarget
    let selectedDisplayID: UUID?
    let select: (UUID) -> Void

    var body: some View {
        StudioPreviewSurface(height: 210) {
            GeometryReader { geometry in
                ZStack {
                    ForEach(self.displays) { display in
                        let rect = self.drawingRect(
                            for: display.screen.frame,
                            in: geometry.size)
                        Button {
                            self.select(display.id)
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        self.isTargeted(display.id)
                                            ? Color.accentColor.opacity(0.24)
                                            : Color.black.opacity(0.34))

                                VStack(spacing: 3) {
                                    Image(systemName: display.isMain ? "display" : "display.2")
                                        .font(.title3)
                                    Text(display.name)
                                        .font(.caption2.weight(.medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.white.opacity(0.88))
                                .padding(8)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(
                                        display.id == self.selectedDisplayID
                                            ? Color.cyan
                                            : Color.white.opacity(0.18),
                                        lineWidth: display.id == self.selectedDisplayID ? 2.5 : 1)
                            }
                            .frame(width: rect.width, height: rect.height)
                        }
                        .buttonStyle(.plain)
                        .position(x: rect.midX, y: rect.midY)
                        .accessibilityAddTraits(
                            display.id == self.selectedDisplayID ? .isSelected : [])
                    }
                }
            }
            .padding(14)
        }
    }

    private var unionFrame: CGRect {
        guard let first = self.displays.first?.screen.frame else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return self.displays.dropFirst().reduce(first) { result, display in
            result.union(display.screen.frame)
        }
    }

    private func drawingRect(for displayFrame: CGRect, in size: CGSize) -> CGRect {
        let unionFrame = self.unionFrame
        let availableWidth = max(1, size.width - 36)
        let availableHeight = max(1, size.height - 36)
        let scale = min(
            availableWidth / max(1, unionFrame.width),
            availableHeight / max(1, unionFrame.height))
        let drawingWidth = unionFrame.width * scale
        let drawingHeight = unionFrame.height * scale
        let originX = (size.width - drawingWidth) / 2
        let originY = (size.height - drawingHeight) / 2

        return CGRect(
            x: originX + (displayFrame.minX - unionFrame.minX) * scale,
            y: originY + (unionFrame.maxY - displayFrame.maxY) * scale,
            width: displayFrame.width * scale,
            height: displayFrame.height * scale)
    }

    private func isTargeted(_ displayID: UUID) -> Bool {
        switch self.target {
        case .followPointer:
            false
        case let .fixed(id):
            id == displayID
        case let .selected(ids):
            ids.contains(displayID)
        }
    }
}
