import AppKit
import CoreGraphics

/// Runtime information for a currently connected display.
///
/// `id` is backed by Core Graphics' persistent display UUID and remains stable
/// across display reordering and reconnects.
@MainActor
struct ConnectedDisplay: Identifiable {
    let id: UUID
    let name: String
    let isMain: Bool
    let screen: NSScreen

    var visibleFrame: CGRect {
        self.screen.visibleFrame
    }
}

/// Resolves `NSScreen` instances without leaking their unstable array indexes
/// into persisted settings.
@MainActor
enum ConnectedDisplays {
    static var all: [ConnectedDisplay] {
        NSScreen.screens.compactMap { screen in
            guard let id = self.id(for: screen) else { return nil }
            return ConnectedDisplay(
                id: id,
                name: screen.localizedName,
                isMain: screen == NSScreen.main,
                screen: screen)
        }
    }

    static var main: ConnectedDisplay? {
        guard let screen = NSScreen.main,
              let id = self.id(for: screen)
        else {
            return self.all.first
        }

        return ConnectedDisplay(
            id: id,
            name: screen.localizedName,
            isMain: true,
            screen: screen)
    }

    static func display(withID id: UUID) -> ConnectedDisplay? {
        self.all.first { $0.id == id }
    }

    static func display(containing point: CGPoint) -> ConnectedDisplay? {
        self.all.first { $0.screen.frame.contains(point) } ?? self.main
    }

    static func id(for screen: NSScreen) -> UUID? {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[screenNumberKey] as? NSNumber else {
            return nil
        }

        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        guard let displayUUID = CGDisplayCreateUUIDFromDisplayID(displayID),
              let uuidString = CFUUIDCreateString(nil, displayUUID.takeRetainedValue())
        else {
            return nil
        }

        return UUID(uuidString: uuidString as String)
    }
}
