import Foundation

enum AppFontOption: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case system
    case mono
    case ebGaramond
    case dmSans
    case inter
    case monaSans
    case hubotSans
    case publicSans
    case spaceGrotesk
    case geistSans
    case nacelle
    case elmsSans
    case nunito

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .mono:
            return "Mono"
        case .ebGaramond:
            return "EB Garamond"
        case .dmSans:
            return "DM Sans"
        case .inter:
            return "Inter"
        case .monaSans:
            return "Mona Sans"
        case .hubotSans:
            return "Hubot Sans"
        case .publicSans:
            return "Public Sans"
        case .spaceGrotesk:
            return "Space Grotesk"
        case .geistSans:
            return "Geist Sans"
        case .nacelle:
            return "Nacelle"
        case .elmsSans:
            return "Elms Sans"
        case .nunito:
            return "Nunito"
        }
    }

    var subtitle: String {
        switch self {
        case .system:
            return "Default Apple typography"
        case .mono:
            return "Apple's monospaced system"
        case .ebGaramond:
            return "Editorial serif"
        case .dmSans:
            return "Rounded geometric sans"
        case .inter:
            return "Modern UI sans"
        case .monaSans:
            return "GitHub's expressive sans"
        case .hubotSans:
            return "GitHub's friendly grotesk"
        case .publicSans:
            return "Neutral public-service sans"
        case .spaceGrotesk:
            return "Geometric display sans"
        case .geistSans:
            return "Vercel's sharp sans"
        case .nacelle:
            return "Neo-grotesk sans"
        case .elmsSans:
            return "Utilitarian geometric sans"
        case .nunito:
            return "Soft rounded sans"
        }
    }

    var sampleText: String {
        switch self {
        case .system:
            return "Flow"
        case .mono:
            return "flow://"
        case .ebGaramond:
            return "Sakura"
        case .dmSans:
            return "Moments"
        case .inter:
            return "Signals"
        case .monaSans:
            return "Context"
        case .hubotSans:
            return "Replies"
        case .publicSans:
            return "Updates"
        case .spaceGrotesk:
            return "Culture"
        case .geistSans:
            return "Velocity"
        case .nacelle:
            return "Journal"
        case .elmsSans:
            return "Index"
        case .nunito:
            return "Friends"
        }
    }

    var previewWord: String {
        switch self {
        case .system:
            return "System"
        case .mono:
            return "Mono"
        case .ebGaramond:
            return "Garamond"
        case .dmSans:
            return "DM"
        case .inter:
            return "Inter"
        case .monaSans:
            return "Mona"
        case .hubotSans:
            return "Hubot"
        case .publicSans:
            return "Public"
        case .spaceGrotesk:
            return "Space"
        case .geistSans:
            return "Geist"
        case .nacelle:
            return "Nacelle"
        case .elmsSans:
            return "Elms"
        case .nunito:
            return "Nunito"
        }
    }

    var familyName: String? {
        switch self {
        case .system, .mono:
            return nil
        case .ebGaramond:
            return "EB Garamond"
        case .dmSans:
            return "DM Sans"
        case .inter:
            return "Inter"
        case .monaSans:
            return "Mona Sans VF"
        case .hubotSans:
            return "Hubot Sans VF"
        case .publicSans:
            return "Public Sans"
        case .spaceGrotesk:
            return "Space Grotesk"
        case .geistSans:
            return "Geist"
        case .nacelle:
            return "Nacelle"
        case .elmsSans:
            return "Elms Sans"
        case .nunito:
            return "Nunito"
        }
    }

    var requiresFlowPlus: Bool {
        switch self {
        case .system:
            return false
        case .mono,
             .ebGaramond,
             .dmSans,
             .inter,
             .monaSans,
             .hubotSans,
             .publicSans,
             .spaceGrotesk,
             .geistSans,
             .nacelle,
             .elmsSans,
             .nunito:
            return true
        }
    }

    var isEnabled: Bool {
        true
    }

    var usesSystemMonospacedDesign: Bool {
        self == .mono
    }

    func isSelectable(with hasFlowPlus: Bool) -> Bool {
        isEnabled && (!requiresFlowPlus || hasFlowPlus)
    }
}
