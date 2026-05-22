import AVFoundation
import UIKit

enum AppHaptics {
    static func reactionTap() {
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: .rigid)
            generator.prepare()
            generator.impactOccurred(intensity: 1)
        }
    }

    static func reactionChargePulse(progress: CGFloat) {
        let clampedProgress = min(max(progress, 0), 1)
        let intensity = 0.24 + (clampedProgress * 0.58)

        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.prepare()
            generator.impactOccurred(intensity: intensity)
        }
    }

    static func reactionChargeCompleted() {
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred(intensity: 1)
        }
    }

    static func liveReactionTick() {
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.prepare()
            generator.impactOccurred(intensity: 0.4)
        }
    }
}

@MainActor
enum AppClickSoundPlayer {
    private static var players: [AppClickSoundEffect: AVAudioPlayer] = [:]

    static func playCurrentSelection() {
        play(AppSettingsStore.shared.clickSoundEffect)
    }

    static func play(_ effect: AppClickSoundEffect) {
        guard effect != .none, let player = audioPlayer(for: effect) else { return }
        player.stop()
        player.currentTime = 0
        player.play()
    }

    private static func audioPlayer(for effect: AppClickSoundEffect) -> AVAudioPlayer? {
        if let player = players[effect] {
            return player
        }

        guard let assetName = effect.dataAssetName,
              let asset = NSDataAsset(name: assetName),
              let player = try? AVAudioPlayer(data: asset.data) else {
            return nil
        }

        player.volume = 0.55
        player.prepareToPlay()
        players[effect] = player
        return player
    }
}
