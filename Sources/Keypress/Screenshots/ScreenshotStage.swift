import AppKit
import CoreGraphics
import SwiftUI

enum StageTone {
    case dark
    case light

    var colorScheme: ColorScheme {
        switch self {
        case .dark: .dark
        case .light: .light
        }
    }
}

/// "Neon Stage" palette — the onboarding backdrop family turned up for the store page.
enum StagePalette {
    static let accent = Color.stageHex(0x67E8F9)

    static let darkBase = Color.stageHex(0x08080D)
    static let darkGlowIndigo = Color.stageHex(0x312E81)
    static let darkGlowCyan = Color.stageHex(0x164E63)
    static let darkForeground = Color.stageHex(0xF2F0EC)

    static let lightBase = Color.stageHex(0xF4F2EE)
    static let lightForeground = Color.stageHex(0x16151A)

    static func foreground(for tone: StageTone) -> Color {
        switch tone {
        case .dark: self.darkForeground
        case .light: self.lightForeground
        }
    }

    static func surface(for tone: StageTone) -> Color {
        switch tone {
        case .dark: Color.white.opacity(0.035)
        case .light: Color.black.opacity(0.035)
        }
    }

    static func surfaceBorder(for tone: StageTone) -> Color {
        switch tone {
        case .dark: Color.white.opacity(0.09)
        case .light: Color.black.opacity(0.09)
        }
    }
}

struct StageBackgroundView: View {
    let tone: StageTone

    var body: some View {
        ZStack {
            Rectangle()
                .fill(self.tone == .dark ? StagePalette.darkBase : StagePalette.lightBase)

            RadialGradient(
                colors: [StagePalette.darkGlowIndigo.opacity(self.indigoOpacity), .clear],
                center: UnitPoint(x: 0.2, y: 0.16),
                startRadius: 0,
                endRadius: 950)

            RadialGradient(
                colors: [StagePalette.darkGlowCyan.opacity(self.cyanOpacity), .clear],
                center: UnitPoint(x: 0.84, y: 0.86),
                startRadius: 0,
                endRadius: 820)

            RadialGradient(
                colors: [.clear, Color.black.opacity(self.vignetteOpacity)],
                center: .center,
                startRadius: 430,
                endRadius: 1010)

            StageGrainView(tone: self.tone)
        }
        .frame(width: ScreenshotCanvas.size.width, height: ScreenshotCanvas.size.height)
        .clipped()
    }

    private var indigoOpacity: Double {
        self.tone == .dark ? 0.42 : 0.13
    }

    private var cyanOpacity: Double {
        self.tone == .dark ? 0.26 : 0.1
    }

    private var vignetteOpacity: Double {
        self.tone == .dark ? 0.55 : 0.04
    }
}

/// Seeded film grain — kills the banding a pure radial gradient shows at 2880 px wide.
private struct StageGrainView: View {
    let tone: StageTone

    var body: some View {
        Group {
            if let tile = StageGrain.tile {
                Image(nsImage: tile)
                    .resizable(resizingMode: .tile)
            }
        }
        .blendMode(self.tone == .dark ? .plusLighter : .multiply)
        .opacity(self.tone == .dark ? 0.035 : 0.02)
    }
}

@MainActor
private enum StageGrain {
    static let tile: NSImage? = Self.makeTile(side: 192, seed: 0x5EED_0BAD_C0FF_EE11)

    private static func makeTile(side: Int, seed: UInt64) -> NSImage? {
        var generator = SplitMix64(seed: seed)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let value = UInt8(generator.next() & 0xFF)
            pixels[index] = value
            pixels[index + 1] = value
            pixels[index + 2] = value
            pixels[index + 3] = value
        }

        let image: CGImage? = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else {
                return nil
            }
            return context.makeImage()
        }

        guard let image else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: side, height: side))
    }
}

/// Fixed-seed PRNG so grain is identical on every run.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        self.state &+= 0x9E37_79B9_7F4A_7C15
        var result = self.state
        result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
        result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
        return result ^ (result >> 31)
    }
}

extension Color {
    static func stageHex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
