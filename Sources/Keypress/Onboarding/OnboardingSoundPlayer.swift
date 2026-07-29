import AVFoundation
import Foundation

@MainActor
final class OnboardingSoundPlayer {
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func play() {
        self.stop(fadeOut: false)

        guard let url = Self.resources.url(
            forResource: "onboarding-ceremony",
            withExtension: "wav")
        else {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.78
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            print("[Keypress] Onboarding sound could not be played: \(error)")
        }
    }

    func stop(fadeOut: Bool) {
        self.stopTask?.cancel()
        self.stopTask = nil

        guard let player = self.player else { return }
        guard fadeOut, player.isPlaying else {
            player.stop()
            self.player = nil
            return
        }

        player.setVolume(0, fadeDuration: 0.18)
        self.stopTask = Task { @MainActor [weak self, weak player] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            player?.stop()
            self?.player = nil
            self?.stopTask = nil
        }
    }

    private static var resources: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }
}
