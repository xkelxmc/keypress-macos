import Foundation
import KeypressCore
import SwiftUI

struct StudioStrings: Equatable, Sendable {
    let languageCode: String?

    var locale: Locale {
        self.languageCode.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }

    subscript(key: String) -> String {
        #if SWIFT_PACKAGE
        if let value = Self.catalog[key]?[self.activeLanguageCode] {
            return value
        }
        #endif
        return self.bundle.localizedString(forKey: key, value: Self.english[key] ?? key, table: nil)
    }

    static var supportedKeys: Set<String> {
        Set(self.english.keys)
    }

    func hasLocalizedValue(for key: String) -> Bool {
        #if SWIFT_PACKAGE
        return Self.catalog[key]?[self.activeLanguageCode] != nil
        #else
        self.bundle.localizedString(forKey: key, value: nil, table: nil) != key
        #endif
    }

    private var activeLanguageCode: String {
        if let languageCode {
            return languageCode
        }
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"
        return ["en", "ru", "de", "es", "fr"]
            .first { preferredLanguage.hasPrefix($0) } ?? "en"
    }

    private var bundle: Bundle {
        guard let languageCode,
              let path = Self.resources.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return Self.resources
        }
        return bundle
    }

    private static var resources: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    #if SWIFT_PACKAGE
    private struct CatalogDocument: Decodable {
        let strings: [String: CatalogEntry]
    }

    private struct CatalogEntry: Decodable {
        let localizations: [String: CatalogLocalization]?
    }

    private struct CatalogLocalization: Decodable {
        let stringUnit: CatalogStringUnit
    }

    private struct CatalogStringUnit: Decodable {
        let value: String
    }

    private static let catalog: [String: [String: String]] = {
        guard let url = Bundle.module.url(
            forResource: "Localizable",
            withExtension: "xcstrings"),
            let data = try? Data(contentsOf: url),
            let document = try? JSONDecoder().decode(CatalogDocument.self, from: data)
        else {
            return [:]
        }

        return document.strings.mapValues { entry in
            entry.localizations?.mapValues(\.stringUnit.value) ?? [:]
        }
    }()
    #endif

    private static let english: [String: String] = [
        "about.copyright": "© 2025–2026 Ilya Zhidkov",
        "about.diagnostics.detail":
            "Export a local system and settings snapshot for support. It never includes input content, "
            + "pointer coordinates, paths, usernames, or display identifiers.",
        "about.diagnostics.export": "Export Diagnostic Report…",
        "about.diagnostics.failed": "The diagnostic report could not be saved.",
        "about.legal": "Legal",
        "about.link.community": "GitHub Community",
        "about.link.creator": "Created by xkelxmc",
        "about.link.issue": "Report an Issue",
        "about.link.review": "Review Keypress",
        "about.link.review.soon": "Coming Soon",
        "about.link.website": "Website",
        "about.links": "Links & Support",
        "about.onboarding.action": "Replay Onboarding",
        "about.onboarding.body":
            "Nothing is reset before you begin. Any choices you make are applied live.",
        "about.onboarding.title": "Welcome Tour",
        "about.privacy": "Privacy",
        "about.privacy.body": "Keyboard input is processed locally and is never recorded, stored, or transmitted.",
        "about.privacy.detail":
            "Keypress processes keyboard and pointer events only to draw its overlays. It does not record, "
            + "store, or transmit keystrokes, typed text, pointer positions, or usage analytics. "
            + "Everything runs on your Mac.",
        "about.product.description":
            "Keypress makes keyboard shortcuts and pointer actions easy to follow in tutorials, presentations, "
            + "live demos, and screen recordings. Everything is rendered locally, with customizable themes, "
            + "layouts, and display placement.",
        "about.product.subtitle": "Product information, privacy, release notes, and support.",
        "about.release.cursor.body":
            "Custom shapes, colors, glow, and responsive click, drag, motion, and scroll reactions.",
        "about.release.cursor.title": "Cursor Halo",
        "about.release.displays.body":
            "Show one keyboard state across selected displays with positions saved per screen.",
        "about.release.displays.title": "Multi-Display",
        "about.release.history.body":
            "Use stacked typing history and decide which modifiers, function, and special keys appear.",
        "about.release.history.title": "History & Filters",
        "about.release.position.body": "Drag the real keyboard overlay into place with snapping, reset, and cancel.",
        "about.release.position.title": "On-Screen Positioning",
        "about.release.reliability.body":
            "More resilient key, modifier, timeout, permission, and overlay state handling.",
        "about.release.reliability.title": "Reliable Input",
        "about.release.studio.body":
            "A resizable native sidebar, pinned live previews, and independent keyboard and pointer themes.",
        "about.release.studio.title": "Native Studio",
        "about.release.title": "What’s New in 2.0.0",
        "about.release.all": "View All Release Notes",
        "about.subtitle": "Version, privacy, and legal information.",
        "about.title": "About",
        "about.version": "Version %@ (%@)",
        "action.cancel": "Cancel",
        "action.done": "Done",
        "action.reset": "Reset",
        "appearance.accentColor": "Accent",
        "appearance.accents": "Pointer & HUD",
        "appearance.background": "Background",
        "appearance.backgroundColor": "Background",
        "appearance.border": "Border",
        "appearance.categoryStyle": "Style",
        "appearance.color": "Color",
        "appearance.core": "Core",
        "appearance.corners": "Corners",
        "appearance.custom": "Key Categories",
        "appearance.customize": "Edit Custom",
        "appearance.depth": "Depth",
        "appearance.fontFamily": "Font Family",
        "appearance.fontScale": "Font Scale",
        "appearance.fontWeight": "Font Weight",
        "appearance.hudColors": "HUD colors",
        "appearance.keycapStyle": "Keycap Style",
        "appearance.keyboardTheme": "Keyboard",
        "appearance.keySpacing": "Key Spacing",
        "appearance.opacity": "Opacity",
        "appearance.overlay": "Overlay",
        "appearance.override": "Override This Category",
        "appearance.override.disabled": "Enable Custom to override this category.",
        "appearance.pointerColors": "Pointer colors",
        "appearance.presetsImmutable": "Built-in themes are read-only. Your Custom theme is preserved.",
        "appearance.primary": "Primary",
        "appearance.resetCustom": "Reset Custom Theme",
        "appearance.resetCustom.confirm.message": "This restores all Custom theme colors and styles.",
        "appearance.resetCustom.confirm.title": "Reset Custom Theme?",
        "appearance.secondary": "Secondary",
        "appearance.shadow": "Shadow",
        "appearance.size": "Size",
        "appearance.subtitle": "Shape the keyboard, pointer, and status HUD.",
        "appearance.textColor": "Text",
        "appearance.theme": "Theme",
        "appearance.title": "Appearance",
        "background.frame": "Frame",
        "background.none": "None",
        "background.overlay": "Overlay",
        "category.capsLock": "Caps Lock",
        "category.command": "Command",
        "category.control": "Control",
        "category.editing": "Editing",
        "category.escape": "Escape",
        "category.function": "Function",
        "category.letter": "Letters & Digits",
        "category.navigation": "Navigation",
        "category.option": "Option",
        "category.shift": "Shift",
        "displays.configure": "Configure",
        "displays.connected": "Connected Displays",
        "displays.custom.help": "Drag the overlay directly on this display.",
        "displays.edit": "Position on Screen…",
        "displays.empty": "No Displays Found",
        "displays.main": "MAIN",
        "displays.offset": "Preset edge offset",
        "displays.placement": "Placement",
        "displays.position": "Position",
        "displays.position.subtitle": "Choose a preset or place the overlay directly.",
        "displays.subtitle": "Choose where each display shows the overlay.",
        "displays.target": "Display Target",
        "displays.target.fixed": "One Display",
        "displays.target.help": "Follow Pointer uses the display under the pointer. Placements stay saved per display.",
        "displays.target.pointer": "Follow Pointer",
        "displays.target.selected": "Selected Displays",
        "displays.title": "Displays & Position",
        "general.app": "Application",
        "general.enabled": "Keypress Enabled",
        "general.enabled.subtitle": "Master switch for keyboard and pointer overlays.",
        "general.hud": "Status HUD",
        "general.hud.duration": "Duration",
        "general.hud.duration.subtitle": "How long the On or Off confirmation remains visible.",
        "general.hud.enabled": "Show Status HUD",
        "general.hud.enabled.subtitle": "Confirm changes made from the menu bar or shortcut.",
        "general.language": "Language",
        "general.language.subtitle": "Changes the app language immediately.",
        "general.launchAtLogin": "Launch at Login",
        "general.launchAtLogin.subtitle": "Open Keypress automatically after signing in.",
        "general.permission": "Input Monitoring",
        "general.permission.check": "Check Again",
        "general.permission.granted": "Permission Granted",
        "general.permission.open": "Open System Settings",
        "general.permission.required": "Permission Required",
        "general.permission.subtitle": "Required to visualize keyboard input outside Keypress.",
        "general.reset": "Reset All Settings…",
        "general.reset.confirm.message": "This restores every setting to its default value.",
        "general.reset.confirm.title": "Reset All Settings?",
        "general.subtitle": "Control the app, language, permissions, and status feedback.",
        "general.title": "General",
        "font.monospaced": "Monospaced",
        "font.rounded": "Rounded",
        "font.system": "System",
        "font.weight.bold": "Bold",
        "font.weight.medium": "Medium",
        "font.weight.regular": "Regular",
        "font.weight.semibold": "Semibold",
        "hud.content.all": "All Keys",
        "hud.content.shortcuts": "Shortcuts Only",
        "hud.keypress.off": "Keypress Off",
        "hud.keypress.on": "Keypress On",
        "hud.pointer.off": "Pointer Off",
        "hud.pointer.on": "Pointer On",
        "hud.positionSaved": "Position Saved",
        "hud.secureInput": "Keyboard hidden — Secure Input",
        "hud.size": "Overlay Size: %@",
        "keyboard.animateKeys": "Regular Keys",
        "keyboard.animateKeys.subtitle": "Animate keys while they are physically pressed.",
        "keyboard.animateModifiers": "Modifier Keys",
        "keyboard.animateModifiers.subtitle": "Animate Command, Option, Control, and Shift.",
        "keyboard.animation": "Press Animation",
        "keyboard.appearance.subtitle": "Choose a visual style and refine the keyboard overlay.",
        "keyboard.appearance.title": "Keyboard Appearance",
        "keyboard.behavior": "Behavior",
        "keyboard.content": "Content",
        "keyboard.content.all": "All Keys",
        "keyboard.content.shortcuts": "Shortcuts Only",
        "keyboard.content.subtitle": "Show every key or only modified combinations.",
        "keyboard.duplicates": "Duplicate Letters",
        "keyboard.duplicates.subtitle": "Keep repeated letters in the history.",
        "keyboard.disabled.action": "Open Keyboard Settings",
        "keyboard.disabled.subtitle": "Turn on the keyboard overlay to configure its appearance and position.",
        "keyboard.disabled.title": "Keyboard Overlay Is Off",
        "keyboard.enabled": "Keyboard Overlay",
        "keyboard.enabled.subtitle": "Visualize keyboard input.",
        "keyboard.filter.functions": "Function Keys",
        "keyboard.filter.modifiers": "Standalone Modifiers",
        "keyboard.filter.modifiers.subtitle": "Show modifiers even when no regular key is pressed.",
        "keyboard.filter.special": "Special Keys",
        "keyboard.filters": "Filters",
        "keyboard.history": "History",
        "keyboard.historyLayout": "Layout",
        "keyboard.layout.horizontal": "Horizontal",
        "keyboard.layout.stacked": "Stacked",
        "keyboard.limitModifiers": "Limit Includes Modifiers",
        "keyboard.limitModifiers.subtitle": "Count modifier keys toward the history limit.",
        "keyboard.maxKeys": "Maximum Keys",
        "keyboard.maxKeys.subtitle": "Maximum number of visible history items.",
        "keyboard.mode": "Display Mode",
        "keyboard.mode.history": "History",
        "keyboard.mode.single": "Single",
        "keyboard.mode.subtitle": "Show the latest shortcut or a running history.",
        "keyboard.subtitle": "Choose which keys appear and how they behave.",
        "keyboard.timeout": "Key Timeout",
        "keyboard.timeout.subtitle": "How long released keys remain visible.",
        "keyboard.title": "Keyboard",
        "language.system": "System Default",
        "menu.enabled": "Enabled",
        "menu.quit": "Quit Keypress",
        "menu.settings": "Settings…",
        "onboarding.back": "Back",
        "onboarding.ceremony.skip": "Click or press Space to continue",
        "onboarding.ceremony.subtitle": "Your input, made visible.",
        "onboarding.ceremony.title": "Meet Keypress",
        "onboarding.keyboard.horizontal": "Horizontal History",
        "onboarding.keyboard.latest": "Latest",
        "onboarding.keyboard.replay": "Replay key press",
        "onboarding.keyboard.stacked": "Stacked History",
        "onboarding.keyboard.subtitle": "Choose how your keyboard story appears on screen.",
        "onboarding.keyboard.title": "Make every shortcut unmistakable",
        "onboarding.later": "Set Up Later",
        "onboarding.next": "Continue",
        "onboarding.permission.grant": "Grant Access",
        "onboarding.permission.local": "Keyboard events are processed only on this Mac.",
        "onboarding.permission.retry": "Try Again",
        "onboarding.permission.secure": "Secure Input automatically hides the keyboard overlay.",
        "onboarding.permission.storage": "Keystrokes are never recorded, stored, or transmitted.",
        "onboarding.permission.subtitle":
            "Keypress needs one macOS permission to visualize keys outside the app.",
        "onboarding.permission.success": "Input Monitoring is ready",
        "onboarding.permission.title": "Private by design",
        "onboarding.permission.waiting": "Waiting for access in System Settings…",
        "onboarding.pointer.disabled": "Halo is disabled — you can still finish setup",
        "onboarding.pointer.subtitle": "Give movement and actions their own visual rhythm.",
        "onboarding.pointer.title": "Let the pointer carry the audience",
        "onboarding.preview.clicks": "Clicks",
        "onboarding.preview.hint": "Try typing, moving the pointer, and clicking",
        "onboarding.preview.keyboard": "Keyboard",
        "onboarding.preview.pointer": "Pointer",
        "onboarding.preview.subtitle": "Everything here is local. No permission is needed for this preview.",
        "onboarding.preview.title": "See what your audience will see",
        "onboarding.product": "Keypress 2.0",
        "onboarding.progress": "Step %d of %d",
        "onboarding.settings.card.body":
            "Finish the short guided setup to enable Keypress and tailor its overlays.",
        "onboarding.settings.card.title": "Your setup is waiting",
        "onboarding.settings.continue": "Continue Setup",
        "onboarding.settings.continue.subtitle": "Return to the saved step",
        "onboarding.settings.privacy": "Private from the first key",
        "onboarding.settings.privacy.body":
            "Input is processed locally and never recorded, stored, or transmitted. "
            + "Keypress requests only Input Monitoring.",
        "onboarding.settings.progress": "Saved progress",
        "onboarding.settings.status": "Setup Status",
        "onboarding.settings.subtitle": "Complete the guided setup when you are ready.",
        "onboarding.settings.title": "Setup",
        "onboarding.sound.off": "Mute ceremony sound",
        "onboarding.sound.on": "Turn ceremony sound on",
        "onboarding.start": "Start Using Keypress",
        "onboarding.step.1": "Interactive Preview",
        "onboarding.step.2": "Input Monitoring",
        "onboarding.step.3": "Keyboard",
        "onboarding.step.4": "Cursor Halo",
        "pointer.behavior": "Behavior",
        "pointer.appearance.reset": "Reset Pointer Theme",
        "pointer.appearance.reset.confirm.message": "This restores the Custom pointer theme to its default values.",
        "pointer.appearance.reset.confirm.title": "Reset Pointer Theme?",
        "pointer.appearance.subtitle": "Choose the shape, glow, colors, and motion of the pointer halo.",
        "pointer.appearance.title": "Pointer Appearance",
        "pointer.drag": "Drag",
        "pointer.decoration": "Detail",
        "pointer.decoration.centerDot": "Center Dot",
        "pointer.decoration.cornerBrackets": "Corners",
        "pointer.decoration.crosshair": "Crosshair",
        "pointer.decoration.innerRing": "Inner Ring",
        "pointer.decoration.none": "None",
        "pointer.decoration.orbit": "Orbit",
        "pointer.disabled.action": "Open Pointer Settings",
        "pointer.disabled.subtitle": "Turn on the pointer overlay to configure its theme and effects.",
        "pointer.disabled.title": "Pointer Overlay Is Off",
        "pointer.effect": "Effect",
        "pointer.enabled": "Pointer Overlay",
        "pointer.enabled.subtitle": "Visualize pointer movement and mouse actions.",
        "pointer.events": "Events",
        "pointer.events.minimum": "Keep at least one event enabled for this visibility mode.",
        "pointer.glowIntensity": "Glow Intensity",
        "pointer.glowRadius": "Glow Radius",
        "pointer.idleDelay": "Idle Delay",
        "pointer.idleDelay.subtitle": "Hide the pointer effect after inactivity.",
        "pointer.leftClick": "Primary Click",
        "pointer.lineStyle": "Line Style",
        "pointer.lineStyle.aura": "Aura",
        "pointer.lineStyle.double": "Double",
        "pointer.lineStyle.neonDepth": "Neon Depth",
        "pointer.lineStyle.segmented": "Segmented",
        "pointer.lineStyle.solid": "Solid",
        "pointer.middleClick": "Middle Click",
        "pointer.motion": "Motion",
        "pointer.motionIntensity": "Motion Intensity",
        "pointer.movement": "Movement",
        "pointer.opacity": "Opacity",
        "pointer.preview.resting": "Resting",
        "pointer.preview.try": "Try pointer reactions",
        "pointer.rightClick": "Secondary Click",
        "pointer.scroll": "Scroll",
        "pointer.shape": "Shape",
        "pointer.shape.circle": "Circle",
        "pointer.shape.diamond": "Diamond",
        "pointer.shape.square": "Square",
        "pointer.shape.squircle": "Squircle",
        "pointer.size": "Size",
        "pointer.stroke": "Stroke",
        "pointer.subtitle": "Make movement, clicks, dragging, and scrolling easy to follow.",
        "pointer.title": "Pointer",
        "pointer.visibility": "Visibility",
        "pointer.visibility.actions": "Clicks & Actions",
        "pointer.visibility.activity": "On Activity",
        "pointer.visibility.always": "Always",
        "pointer.visibility.subtitle": "Show continuously, on any activity, or only for clicks and actions.",
        "preview.pressed": "Pressed",
        "preview.resting": "Resting",
        "position.bottomCenter": "Bottom Center",
        "position.bottomLeft": "Bottom Left",
        "position.bottomRight": "Bottom Right",
        "position.center": "Center",
        "position.centerLeft": "Center Left",
        "position.centerRight": "Center Right",
        "position.custom": "Custom…",
        "position.editor.subtitle": "%@ · Drag the keyboard overlay, then click Done.",
        "position.editor.title": "Positioning Keypress",
        "position.topCenter": "Top Center",
        "position.topLeft": "Top Left",
        "position.topRight": "Top Right",
        "shortcuts.conflictHint": "Conflicting shortcuts cannot be recorded.",
        "shortcuts.content": "Switch Content Mode",
        "shortcuts.content.subtitle": "Switch between all keys and shortcuts only.",
        "shortcuts.duplicateConflict": "Already assigned to another Keypress action.",
        "shortcuts.global": "Global Shortcuts",
        "shortcuts.hint": "Shortcuts use physical key positions and work in every app.",
        "shortcuts.invalidConflict": "Use a key with at least one modifier.",
        "shortcuts.reservedConflict": "This shortcut is reserved by macOS.",
        "shortcuts.pointer": "Toggle Pointer",
        "shortcuts.pointer.subtitle": "Enable or disable the pointer overlay.",
        "shortcuts.position": "Edit Position",
        "shortcuts.position.subtitle": "Open the on-screen positioning editor.",
        "shortcuts.size.decrease": "Decrease Overlay Size",
        "shortcuts.size.decrease.subtitle": "Move to the next smaller keyboard size.",
        "shortcuts.size.increase": "Increase Overlay Size",
        "shortcuts.size.increase.subtitle": "Move to the next larger keyboard size.",
        "shortcuts.subtitle": "Record shortcuts for commands you use anywhere.",
        "shortcuts.title": "Shortcuts",
        "shortcuts.toggle": "Toggle Keypress",
        "shortcuts.toggle.subtitle": "Enable or disable all visualization.",
        "sidebar.about": "About",
        "sidebar.appearance": "Appearance",
        "sidebar.displays": "Displays & Position",
        "sidebar.general": "General",
        "sidebar.keyboard": "Keyboard",
        "sidebar.pointer": "Pointer",
        "sidebar.section.keyboard": "Keyboard",
        "sidebar.section.pointer": "Pointer",
        "sidebar.setup": "Setup",
        "sidebar.settings": "Settings",
        "sidebar.shortcuts": "Shortcuts",
        "size.large": "Large",
        "size.medium": "Medium",
        "size.small": "Small",
        "style.flat": "Flat",
        "style.mechanical": "Mechanical",
        "style.minimal": "Minimal",
        "theme.classic": "Classic",
        "theme.custom": "Custom",
        "theme.dark": "Dark",
        "theme.default": "Default",
        "theme.gaming": "Gaming",
        "theme.light": "Light",
        "theme.minimal": "Minimal",
        "theme.modern": "Modern",
        "theme.mono": "Mono",
        "theme.neon": "Neon",
        "theme.system": "System",
        "unit.points": "pt",
        "unit.seconds": "s",
        "window.settings.title": "Keypress Settings",
    ]
}

extension AppLanguage {
    var studioLanguageCode: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .russian: "ru"
        case .german: "de"
        case .spanish: "es"
        case .french: "fr"
        }
    }
}

extension EnvironmentValues {
    @Entry var studioStrings: StudioStrings = .init(languageCode: nil)
}
