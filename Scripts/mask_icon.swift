// Masks full-bleed icon artwork into the macOS Big Sur icon template:
// an 824x824 rounded-rect tile centered on a transparent 1024x1024 canvas
// with the standard soft drop shadow.
// Usage: swift Scripts/mask_icon.swift <input.png> <output.png>

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: swift Scripts/mask_icon.swift <input.png> <output.png>\n", stderr)
    exit(1)
}

guard let source = NSImage(contentsOfFile: arguments[1]) else {
    fputs("Cannot read \(arguments[1])\n", stderr)
    exit(1)
}

let canvasSide: CGFloat = 1024
let tileSide: CGFloat = 824
let cornerRadius: CGFloat = 185.4

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSide),
    pixelsHigh: Int(canvasSide),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0)
else {
    fputs("Cannot create bitmap\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let tileRect = NSRect(
    x: (canvasSide - tileSide) / 2,
    y: (canvasSide - tileSide) / 2,
    width: tileSide,
    height: tileSide)
let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 12
shadow.shadowOffset = NSSize(width: 0, height: -8)
shadow.set()
NSColor.black.setFill()
tilePath.fill()

NSShadow().set()
tilePath.setClip()
source.draw(in: tileRect, from: .zero, operation: .sourceOver, fraction: 1)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Cannot encode PNG\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: arguments[2]))
    print("\(arguments[2]) — \(Int(canvasSide))x\(Int(canvasSide))")
} catch {
    fputs("Cannot write \(arguments[2]): \(error.localizedDescription)\n", stderr)
    exit(1)
}
