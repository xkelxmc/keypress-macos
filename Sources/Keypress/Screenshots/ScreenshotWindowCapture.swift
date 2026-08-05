import AppKit
import SwiftUI

/// Rasterizes AppKit-backed SwiftUI (NavigationSplitView, lists, materials) that
/// `ImageRenderer` refuses to draw, by hosting it in a real window and asking the
/// window server for the composited result — materials only exist once composited.
@MainActor
enum WindowCapture {
    static func image(
        of view: some View,
        contentSize: CGSize,
        appearance appearanceName: NSAppearance.Name) -> NSImage?
    {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()

        let hosting = NSHostingController(rootView: view)
        // Without this the split view's minimum height wins and the requested size is ignored.
        hosting.sizingOptions = []
        hosting.view.frame = CGRect(origin: .zero, size: contentSize)

        // No titlebar buttons: while the user works elsewhere this process can never win
        // the activation race (macOS cooperative activation), so traffic lights would
        // nondeterministically render gray. A clean titlebar sidesteps that entirely.
        let window = OffscreenWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.appearance = NSAppearance(named: appearanceName)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.title = ""
        window.toolbar = nil
        window.contentViewController = hosting
        window.contentMinSize = contentSize
        window.setContentSize(contentSize)
        window.setFrameOrigin(self.parkingOrigin(for: window.frame.size))

        defer { window.orderOut(nil) }

        // The window pretends to be key so any AppKit-side state that consults the
        // public getters draws active; SwiftUI controls are forced active through
        // `controlActiveState`. Every capture is verified by looking for the accent
        // colour and retried while SwiftUI settles its split view and previews.
        window.pretendsActive = true
        // Neither of those reaches the toggles, sliders and segmented pickers: they
        // draw gray unless this process is really the active one. Cooperative
        // activation declines when the generator is launched from a window that is
        // not frontmost, so the front-most claim has to be taken outright.
        app.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.setFrameOrigin(self.parkingOrigin(for: window.frame.size))
        let center = NotificationCenter.default
        center.post(name: NSWindow.didBecomeMainNotification, object: window)
        center.post(name: NSWindow.didBecomeKeyNotification, object: window)
        self.pumpEvents(of: app, for: 1.2)

        for _ in 0..<6 {
            window.displayIfNeeded()
            self.pumpEvents(of: app, for: 0.4)

            if let composited = self.compositedImage(of: window), self.hasActiveControls(composited) {
                return composited
            }

            // Another app can take the front-most claim back between attempts, and
            // the controls turn gray the moment it does.
            app.activate(ignoringOtherApps: true)
            center.post(name: NSWindow.didBecomeKeyNotification, object: window)
        }

        // A capture whose controls drew gray is a broken store asset, and it looks
        // enough like the real thing to ship by mistake. Fail the run instead.
        fputs("error: settings window captured with inactive controls\n", stderr)
        return nil
    }

    /// A spot beyond every attached display, so the window is composited — and therefore
    /// capturable — without ever being visible.
    private static func parkingOrigin(for size: CGSize) -> NSPoint {
        let union = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        return NSPoint(x: union.maxX + 4000, y: union.minY - size.height - 4000)
    }

    /// Drives the app event loop without owning it, so activation and layout complete.
    private static func pumpEvents(of app: NSApplication, for duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            guard let event = app.nextEvent(
                matching: .any,
                until: deadline,
                inMode: .default,
                dequeue: true)
            else {
                continue
            }
            app.sendEvent(event)
        }
    }

    /// The sidebar keeps its blue app icons whatever the activation state, so only
    /// the detail pane answers the question: its toggles, sliders, segmented
    /// pickers and selection rings carry the accent colour when — and only when —
    /// the controls rendered active.
    private static let paneStart = 0.3

    private static func hasActiveControls(_ image: NSImage) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = cgImage.dataProvider?.data as Data?
        else {
            return false
        }

        let bytesPerPixel = cgImage.bitsPerPixel / 8
        guard bytesPerPixel == 4 else { return false }

        // CGWindowListCreateImage returns BGRA (32-bit little-endian) on Apple silicon;
        // detect the layout instead of assuming it.
        let littleEndian = cgImage.bitmapInfo.contains(.byteOrder32Little)
        let (redIndex, greenIndex, blueIndex) = littleEndian ? (2, 1, 0) : (1, 2, 3)

        let bytesPerRow = cgImage.bytesPerRow
        let firstColumn = Int(Double(cgImage.width) * Self.paneStart)
        var matches = 0
        for row in 0..<cgImage.height {
            let rowStart = row * bytesPerRow
            for column in firstColumn..<cgImage.width {
                let pixel = rowStart + column * bytesPerPixel
                let red = data[pixel + redIndex]
                let green = data[pixel + greenIndex]
                let blue = data[pixel + blueIndex]
                if red < 120, green > 100, green < 190, blue > 210 {
                    matches += 1
                    if matches > 200 {
                        return true
                    }
                }
            }
        }
        return false
    }

    private static func compositedImage(of window: NSWindow) -> NSImage? {
        let windowID = CGWindowID(window.windowNumber)
        guard windowID > 0,
              let cgImage = CGWindowListCreateImage(
                  .null,
                  .optionIncludingWindow,
                  windowID,
                  [.boundsIgnoreFraming, .bestResolution]),
              cgImage.width > 1
        else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: window.frame.size)
    }
}

/// AppKit drags titled windows back onto a display; the capture window must stay parked.
/// With `pretendsActive` set it also claims key/main status, so chrome queried through
/// these getters draws in active colours without the app winning the real focus race.
private final class OffscreenWindow: NSWindow {
    var pretendsActive = false

    override var isKeyWindow: Bool {
        self.pretendsActive || super.isKeyWindow
    }

    override var isMainWindow: Bool {
        self.pretendsActive || super.isMainWindow
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
