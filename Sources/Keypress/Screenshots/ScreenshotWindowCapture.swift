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
        // swiftlint:disable:previous function_body_length
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
        window.orderFrontRegardless()
        window.setFrameOrigin(self.parkingOrigin(for: window.frame.size))
        let center = NotificationCenter.default
        center.post(name: NSWindow.didBecomeMainNotification, object: window)
        center.post(name: NSWindow.didBecomeKeyNotification, object: window)
        self.pumpEvents(of: app, for: 1.2)

        var lastCapture: NSImage?
        for _ in 0..<6 {
            window.displayIfNeeded()
            self.pumpEvents(of: app, for: 0.4)

            guard let composited = self.compositedImage(of: window) else { continue }
            lastCapture = composited
            if self.hasAccentPixels(composited) {
                return composited
            }
        }

        if let lastCapture {
            fputs("warning: settings window captured without accent colours\n", stderr)
            return lastCapture
        }
        return self.cachedImage(of: hosting.view)
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

    /// True when the system accent blue is present anywhere — selected sidebar rows,
    /// toggles and segmented pickers only draw it when controls rendered active.
    private static func hasAccentPixels(_ image: NSImage) -> Bool {
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
        var matches = 0
        for row in 0..<cgImage.height {
            let rowStart = row * bytesPerRow
            for column in 0..<cgImage.width {
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

    private static func cachedImage(of view: NSView) -> NSImage? {
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: representation)

        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(representation)
        return image
    }
}

/// AppKit drags titled windows back onto a display; the capture window must stay parked.
/// With `pretendsActive` set it also claims key/main status, so chrome queried through
/// these getters draws in active colours without the app winning the real focus race.
private final class OffscreenWindow: NSWindow {
    var pretendsActive = false

    override var isKeyWindow: Bool { self.pretendsActive || super.isKeyWindow }
    override var isMainWindow: Bool { self.pretendsActive || super.isMainWindow }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
