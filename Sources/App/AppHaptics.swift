import UIKit

enum AppHaptics {
    static func reactionTap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.8)
    }
}
