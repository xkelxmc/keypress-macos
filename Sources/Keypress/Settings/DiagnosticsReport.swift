import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
import KeypressCore

@MainActor
enum DiagnosticsReport {
    static var suggestedFilename: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Keypress-Diagnostics-\(formatter.string(from: Date())).txt"
    }

    static func make(config: KeypressConfig = .shared) -> String {
        let snapshot = config.snapshot
        var lines: [String] = [
            "Keypress Diagnostic Report",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "",
            "PRIVACY",
            "This report was generated locally and is not uploaded by Keypress.",
            "It excludes keystrokes, typed text, pointer coordinates, file paths, usernames, and display identifiers.",
            "Review the report before sharing it.",
            "",
        ]

        self.appendApplicationSection(to: &lines, snapshot: snapshot)
        self.appendSystemSection(to: &lines)
        self.appendRuntimeSection(to: &lines, snapshot: snapshot)
        self.appendDisplaySection(to: &lines)
        self.appendSettingsSection(to: &lines, snapshot: snapshot)

        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendApplicationSection(
        to lines: inout [String],
        snapshot: AppSettings)
    {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = info?["CFBundleVersion"] as? String ?? "Unknown"

        lines.append(contentsOf: [
            "APPLICATION",
            "Version: \(version)",
            "Build: \(build)",
            "Bundle identifier: \(Bundle.main.bundleIdentifier ?? "Unknown")",
            "Settings schema: \(snapshot.schemaVersion)",
            "",
        ])
    }

    private static func appendSystemSection(to lines: inout [String]) {
        let processInfo = ProcessInfo.processInfo
        let memoryFormatter = ByteCountFormatter()
        memoryFormatter.countStyle = .memory

        lines.append(contentsOf: [
            "SYSTEM",
            "macOS: \(processInfo.operatingSystemVersionString)",
            "Architecture: \(self.architecture)",
            "Hardware model: \(self.sysctlString("hw.model") ?? "Unknown")",
            "Processor count: \(processInfo.processorCount)",
            "Active processor count: \(processInfo.activeProcessorCount)",
            "Physical memory: \(memoryFormatter.string(fromByteCount: Int64(processInfo.physicalMemory)))",
            "Thermal state: \(self.thermalStateDescription(processInfo.thermalState))",
            "Low Power Mode: \(self.yesNo(processInfo.isLowPowerModeEnabled))",
            "Reduce Motion: \(self.yesNo(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))",
            "",
        ])
    }

    private static func appendRuntimeSection(
        to lines: inout [String],
        snapshot: AppSettings)
    {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        lines.append(contentsOf: [
            "RUNTIME",
            "Application active: \(self.yesNo(NSApp.isActive))",
            "Application hidden: \(self.yesNo(NSApp.isHidden))",
            "Master visualization enabled: \(self.yesNo(snapshot.general.enabled))",
            "Keyboard visualization enabled: \(self.yesNo(snapshot.keyboard.enabled))",
            "Pointer visualization enabled: \(self.yesNo(snapshot.pointer.enabled))",
            "Pet enabled: \(self.yesNo(snapshot.pet.enabled))",
            "Input Monitoring permission: \(InputMonitoringPermission.check() ? "Granted" : "Required")",
            "Secure Input: \(IsSecureEventInputEnabled() ? "Active" : "Inactive")",
            "Effective appearance: \(isDark ? "Dark" : "Light")",
            "",
        ])
    }

    private static func appendDisplaySection(to lines: inout [String]) {
        let screens = NSScreen.screens
        lines.append("DISPLAYS")
        lines.append("Connected displays: \(screens.count)")

        for (index, screen) in screens.enumerated() {
            let scale = screen.backingScaleFactor
            lines.append("")
            lines.append("Display \(index + 1)")
            lines.append("Main display: \(self.yesNo(screen == NSScreen.main))")
            lines.append("Frame (points): \(self.rectDescription(screen.frame))")
            lines.append("Visible frame (points): \(self.rectDescription(screen.visibleFrame))")
            lines.append("Backing scale: \(self.number(Double(scale)))x")
            lines.append(
                "Pixel size: \(Int((screen.frame.width * scale).rounded())) × "
                    + "\(Int((screen.frame.height * scale).rounded()))")
        }

        lines.append("")
    }

    private static func appendSettingsSection(
        to lines: inout [String],
        snapshot: AppSettings)
    {
        let placements = snapshot.displays.placements.values
        let customPlacementCount = placements.reduce(into: 0) { count, placement in
            if case .custom = placement {
                count += 1
            }
        }

        let effectiveFilters = snapshot.keyboard.presentation == .latest
            ? snapshot.keyboard.filters
            : snapshot.keyboard.filters.ignoringKeyCategories
        let contentMode = self.withEffective(
            snapshot.keyboard.contentMode.rawValue,
            snapshot.keyboard.effectiveContentMode.rawValue)
        let functionKeys = self.withEffective(
            self.yesNo(snapshot.keyboard.filters.showFunctionKeys),
            self.yesNo(effectiveFilters.showFunctionKeys))
        let specialKeys = self.withEffective(
            self.yesNo(snapshot.keyboard.filters.showSpecialKeys),
            self.yesNo(effectiveFilters.showSpecialKeys))

        lines.append(contentsOf: [
            "SANITIZED SETTINGS",
            "Language: \(snapshot.general.language.rawValue)",
            "Launch at login: \(self.yesNo(snapshot.general.launchAtLogin))",
            "HUD enabled: \(self.yesNo(snapshot.hud.enabled))",
            "HUD duration: \(self.number(snapshot.hud.duration)) s",
            "",
            "Keyboard mode: \(snapshot.keyboard.displayMode.rawValue)",
            "Keyboard presentation: \(snapshot.keyboard.presentation.rawValue)",
            "Keyboard content: \(contentMode)",
            "History layout: \(snapshot.keyboard.historyLayout.rawValue)",
            "Keyboard size: \(snapshot.keyboard.size.rawValue)",
            "Keyboard opacity: \(self.number(snapshot.keyboard.opacity))",
            "Key timeout: \(self.number(snapshot.keyboard.timeout)) s",
            "Maximum history items: \(snapshot.keyboard.maxItems)",
            "Standalone modifiers: \(self.yesNo(snapshot.keyboard.filters.showStandaloneModifiers))",
            "Function keys: \(functionKeys)",
            "Special keys: \(specialKeys)",
            "Echo line lifetime: \(self.number(snapshot.keyboard.textLineLifetime)) s",
            "Echo idle timeout: \(self.number(snapshot.keyboard.textIdleTimeout)) s",
            "Input key width: \(snapshot.keyboard.inputKeys.widthMode.rawValue)",
            "Input key tint: \(self.yesNo(snapshot.keyboard.inputKeys.highlight))",
            "",
            "Pointer visibility: \(snapshot.pointer.visibility.rawValue)",
            "Pointer size: \(self.number(snapshot.pointer.size)) pt",
            "Pointer opacity: \(self.number(snapshot.pointer.opacity))",
            "Pointer motion intensity: \(self.number(snapshot.pointer.motionIntensity))",
            "Pointer movement response: \(self.yesNo(snapshot.pointer.showMovement))",
            "Pointer primary click response: \(self.yesNo(snapshot.pointer.showLeftClick))",
            "Pointer secondary click response: \(self.yesNo(snapshot.pointer.showRightClick))",
            "Pointer middle click response: \(self.yesNo(snapshot.pointer.showMiddleClick))",
            "Pointer drag response: \(self.yesNo(snapshot.pointer.showDrag))",
            "Pointer scroll response: \(self.yesNo(snapshot.pointer.showScroll))",
            "",
            "Pet visibility: \(snapshot.pet.visibility.rawValue)",
            "Pet activity order: \(snapshot.pet.activityMode.rawValue)",
            "Pet size: \(self.number(snapshot.pet.size)) pt",
            "Pet sleep: \(self.yesNo(snapshot.pet.sleep))",
            "Pet cursor watching: \(self.yesNo(snapshot.pet.watchCursor))",
            "Pet cursor hunting: \(self.yesNo(snapshot.pet.huntCursor))",
            "Pet stretching: \(self.yesNo(snapshot.pet.stretch))",
            "Pet grooming: \(self.yesNo(snapshot.pet.groom))",
            "Pet tail play: \(self.yesNo(snapshot.pet.playTail))",
            "Pet click reaction: \(self.yesNo(snapshot.pet.petReaction))",
            "",
            "Keyboard theme: \(snapshot.appearance.keyboardThemeSelection.rawValue)",
            "Pointer theme: \(snapshot.appearance.pointerThemeSelection.rawValue)",
            "Display target: \(self.displayTargetDescription(snapshot.displays.target))",
            "Saved display placements: \(placements.count)",
            "Custom display placements: \(customPlacementCount)",
            "Saved command zone placements: \(snapshot.displays.commandZonePlacements.count)",
            "Displays with a zone layout mode: \(snapshot.displays.zoneLayoutPresentations.count)",
            "",
        ])
    }

    private static func displayTargetDescription(_ target: DisplayTarget) -> String {
        switch target {
        case .followPointer:
            "Follow Pointer"
        case .fixed:
            "One Display"
        case let .selected(displayIDs):
            "Selected Displays (\(displayIDs.count))"
        }
    }

    private static func rectDescription(_ rect: CGRect) -> String {
        "x=\(self.number(Double(rect.origin.x))), y=\(self.number(Double(rect.origin.y))), "
            + "width=\(self.number(Double(rect.width))), height=\(self.number(Double(rect.height)))"
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    /// A stored setting, annotated with what the running mode actually uses when the two differ
    /// — the two-zone modes neutralize the content mode and both category filters, and a report
    /// showing only the stored value sends the reader after a setting that is doing nothing.
    private static func withEffective(_ stored: String, _ effective: String) -> String {
        stored == effective ? stored : "\(stored) (effective: \(effective))"
    }

    private static var architecture: String {
        #if arch(arm64)
        "Apple silicon (arm64)"
        #elseif arch(x86_64)
        "Intel (x86_64)"
        #else
        "Unknown"
        #endif
    }

    private static func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:
            "Nominal"
        case .fair:
            "Fair"
        case .serious:
            "Serious"
        case .critical:
            "Critical"
        @unknown default:
            "Unknown"
        }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
            return nil
        }

        let bytes = value.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
        return String(bytes: bytes, encoding: .utf8)
    }
}
