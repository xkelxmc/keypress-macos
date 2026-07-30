import AppKit
import Foundation
import KeypressCore
import SwiftUI

enum PetSpriteMetrics {
    static let contentPixelWidth = 192
    static let canvasPixelWidth = 272
    static let canvasPixelHeight = 208

    static var aspectRatio: CGFloat {
        CGFloat(self.canvasPixelWidth) / CGFloat(self.canvasPixelHeight)
    }

    static var canvasToContentWidth: CGFloat {
        CGFloat(self.canvasPixelWidth) / CGFloat(self.contentPixelWidth)
    }

    static func canvasSize(contentWidth: CGFloat) -> CGSize {
        CGSize(
            width: contentWidth * self.canvasToContentWidth,
            height: contentWidth * CGFloat(self.canvasPixelHeight) / CGFloat(self.contentPixelWidth))
    }
}

struct PetClipDefinition: Codable, Equatable {
    let row: Int
    let start: Int
    let count: Int
    let fps: Double
    let loop: Bool
    let reversible: Bool
}

struct PetSpriteManifest: Codable, Equatable {
    let cellWidth: Int
    let cellHeight: Int
    let columns: Int
    let rows: Int
    let clips: [String: PetClipDefinition]

    func validate(atlasWidth: Int, atlasHeight: Int) throws {
        guard self.cellWidth == PetSpriteMetrics.canvasPixelWidth,
              self.cellHeight == PetSpriteMetrics.canvasPixelHeight,
              self.columns == 16,
              self.rows == 12,
              atlasWidth == self.cellWidth * self.columns,
              atlasHeight == self.cellHeight * self.rows
        else {
            throw PetSpriteError.invalidAtlasDimensions
        }

        for clip in self.clips.values {
            guard clip.row >= 0,
                  clip.row < self.rows,
                  clip.start >= 0,
                  clip.count >= 1,
                  clip.start + clip.count <= self.columns,
                  clip.fps > 0
            else {
                throw PetSpriteError.invalidClip
            }
        }

        let requiredClips = [
            "idle",
            "typing",
            "sleepTransition",
            "sleep",
            "pounceRight",
            "stretch",
            "groom",
            "playTail",
            "petReaction",
            "carried",
            "settle",
            "lookUpper",
            "lookLower",
        ]
        guard requiredClips.allSatisfy({ self.clips[$0] != nil }) else {
            throw PetSpriteError.missingClip
        }
        guard self.clips["lookUpper"]?.count == 8,
              self.clips["lookLower"]?.count == 8
        else {
            throw PetSpriteError.invalidClip
        }
    }
}

enum PetSpriteError: Error, Equatable {
    case missingResource
    case invalidImage
    case invalidAtlasDimensions
    case invalidClip
    case missingClip
}

@MainActor
final class PetSpriteSheet {
    static let shared = PetSpriteSheet()

    private(set) var loadError: Error?
    private var manifest: PetSpriteManifest?
    private var frames: [[NSImage]] = []

    var isAvailable: Bool {
        self.manifest != nil && !self.frames.isEmpty
    }

    private init() {
        do {
            try self.load()
        } catch {
            self.loadError = error
            print("[Keypress] Pet sprites could not be loaded: \(error)")
        }
    }

    func definition(for state: PetRuntimeState) -> PetClipDefinition? {
        guard let manifest = self.manifest else { return nil }
        return manifest.clips[self.clipName(for: state)]
    }

    func image(for state: PetRuntimeState, frameIndex: Int) -> NSImage? {
        guard let definition = self.definition(for: state) else { return nil }
        let localIndex: Int = switch state {
        case let .looking(direction):
            direction % 8
        default:
            min(max(frameIndex, 0), definition.count - 1)
        }
        let column = definition.start + localIndex
        guard self.frames.indices.contains(definition.row),
              self.frames[definition.row].indices.contains(column)
        else {
            return nil
        }
        return self.frames[definition.row][column]
    }

    private func clipName(for state: PetRuntimeState) -> String {
        switch state {
        case .hidden, .idle:
            "idle"
        case .typing:
            "typing"
        case .sleepTransition:
            "sleepTransition"
        case .sleeping:
            "sleep"
        case let .looking(direction):
            direction < 8 ? "lookUpper" : "lookLower"
        case let .ambient(activity):
            activity.rawValue
        case .pouncing:
            "pounceRight"
        case .petting:
            "petReaction"
        case .carried:
            "carried"
        case .settling:
            "settle"
        }
    }

    private func load() throws {
        guard let manifestURL = Self.resourceURL(name: "pet-manifest", extension: "json"),
              let atlasURL = Self.resourceURL(name: "pet-atlas", extension: "png")
        else {
            throw PetSpriteError.missingResource
        }

        let manifest = try JSONDecoder().decode(
            PetSpriteManifest.self,
            from: Data(contentsOf: manifestURL))
        guard let sourceImage = NSImage(contentsOf: atlasURL),
              let representation = sourceImage.representations.first,
              let source = sourceImage.cgImage(
                  forProposedRect: nil,
                  context: nil,
                  hints: nil)
        else {
            throw PetSpriteError.invalidImage
        }

        try manifest.validate(
            atlasWidth: representation.pixelsWide,
            atlasHeight: representation.pixelsHigh)

        var frames: [[NSImage]] = []
        frames.reserveCapacity(manifest.rows)
        for row in 0..<manifest.rows {
            var rowFrames: [NSImage] = []
            rowFrames.reserveCapacity(manifest.columns)
            for column in 0..<manifest.columns {
                let rect = CGRect(
                    x: column * manifest.cellWidth,
                    y: row * manifest.cellHeight,
                    width: manifest.cellWidth,
                    height: manifest.cellHeight)
                guard let cropped = source.cropping(to: rect) else {
                    throw PetSpriteError.invalidImage
                }
                rowFrames.append(
                    NSImage(
                        cgImage: cropped,
                        size: NSSize(
                            width: manifest.cellWidth,
                            height: manifest.cellHeight)))
            }
            frames.append(rowFrames)
        }

        self.manifest = manifest
        self.frames = frames
    }

    private static func resourceURL(name: String, extension fileExtension: String) -> URL? {
        self.resources.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Pet")
            ?? self.resources.url(forResource: name, withExtension: fileExtension)
    }

    private static var resources: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }
}

@MainActor
struct PetSpriteView: View {
    @Bindable var controller: PetController

    var body: some View {
        Group {
            if let image = PetSpriteSheet.shared.image(
                for: self.controller.state,
                frameIndex: self.controller.frameIndex)
            {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaleEffect(
                        x: self.controller.state.isMirrored ? -1 : 1,
                        y: 1)
            } else {
                Color.clear
            }
        }
        .aspectRatio(PetSpriteMetrics.aspectRatio, contentMode: .fit)
        .contentShape(Rectangle())
        .accessibilityLabel(self.controller.accessibilityLabel)
        .modifier(PetReactionAccessibilityModifier(controller: self.controller))
        .accessibilityAction(
            named: Text(self.controller.localizedString("pet.position.moveLeft")))
        {
            self.controller.moveForAccessibility(horizontal: -24, vertical: 0)
        }
        .accessibilityAction(
                named: Text(self.controller.localizedString("pet.position.moveRight")))
        {
            self.controller.moveForAccessibility(horizontal: 24, vertical: 0)
            }
            .accessibilityAction(
                    named: Text(self.controller.localizedString("pet.position.moveUp")))
            {
                self.controller.moveForAccessibility(horizontal: 0, vertical: 24)
                }
                .accessibilityAction(
                        named: Text(self.controller.localizedString("pet.position.moveDown")))
                {
                    self.controller.moveForAccessibility(horizontal: 0, vertical: -24)
                    }
    }
}

@MainActor
private struct PetReactionAccessibilityModifier: ViewModifier {
    let controller: PetController

    func body(content: Content) -> some View {
        if self.controller.supportsPetReaction {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    self.controller.performPetReaction()
                }
        } else {
            content
        }
    }
}

extension PetRuntimeState {
    fileprivate var isMirrored: Bool {
        if case let .pouncing(mirrored) = self {
            return mirrored
        }
        return false
    }
}
