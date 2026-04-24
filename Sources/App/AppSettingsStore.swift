import Foundation
import NostrSDK
import SwiftUI
import UIKit
import UserNotifications

enum AppThemeOption: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case system
    case black
    case white
    case sakura
    case dracula
    case gamer
    case holographicLight
    case holographicDark
    case dark
    case light

    var id: String { rawValue }

    static let appearanceOptions: [AppThemeOption] = [
        .light,
        .dark,
        .black,
        .system,
        .sakura,
        .dracula,
        .gamer,
        .holographicLight
    ]

    var normalizedSelection: AppThemeOption {
        switch self {
        case .white:
            return .light
        case .holographicDark:
            return .dark
        case .system, .black, .sakura, .dracula, .gamer, .holographicLight, .dark, .light:
            return self
        }
    }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .black:
            return "Black"
        case .white:
            return "Light"
        case .sakura:
            return "Sakura"
        case .dracula:
            return "Dracula"
        case .gamer:
            return "Gamer"
        case .holographicLight:
            return "Sky"
        case .holographicDark:
            return "Dark"
        case .dark:
            return "Dark"
        case .light:
            return "Light"
        }
    }

    var iconName: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .black:
            return "moon.fill"
        case .white:
            return "sun.haze.fill"
        case .sakura:
            return "leaf.fill"
        case .dracula:
            return "moon.stars.fill"
        case .gamer:
            return "gamecontroller.fill"
        case .holographicLight, .holographicDark:
            return "sparkles"
        case .dark:
            return "moon.stars.fill"
        case .light:
            return "sun.haze.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .system:
            return "Switches between Light and Dark"
        case .black:
            return "Pure black appearance"
        case .white:
            return "Bright appearance"
        case .sakura:
            return "Paper whites with gradient blossom pinks"
        case .dracula:
            return "Moody shadows with classic violet and neon accents"
        case .gamer:
            return "Carbon black with neon violet, cyan, and energy-green accents"
        case .holographicLight:
            return "Clean light theme with soft sky highlights"
        case .holographicDark:
            return "Legacy dark appearance"
        case .dark:
            return "Dark appearance"
        case .light:
            return "Bright appearance"
        }
    }

    var isEnabled: Bool {
        switch self {
        case .system, .black, .sakura, .dracula, .gamer, .holographicLight, .dark, .light:
            return true
        case .white, .holographicDark:
            return false
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .black, .dark, .dracula, .gamer, .holographicDark:
            return .dark
        case .white, .light, .sakura, .holographicLight:
            return .light
        }
    }

    var fixedPrimaryColor: Color? {
        nil
    }

    var fixedPrimaryGradient: LinearGradient? {
        nil
    }

    var qrShareBackgroundResourceName: String? {
        switch self {
        case .sakura:
            return "sakura-share-bg.json"
        case .system, .black, .white, .dracula, .gamer, .holographicLight, .holographicDark, .dark, .light:
            return nil
        }
    }

    var palette: AppThemePalette {
        switch self {
        case .system:
            return AppThemePalette.system
        case .black:
            return AppThemePalette.black
        case .white:
            return AppThemePalette.white
        case .sakura:
            return AppThemePalette.sakura
        case .dracula:
            return AppThemePalette.dracula
        case .gamer:
            return AppThemePalette.gamer
        case .holographicLight:
            return AppThemePalette.holographicLight
        case .holographicDark:
            return AppThemePalette.holographicDark
        case .dark:
            return AppThemePalette.dark
        case .light:
            return AppThemePalette.white
        }
    }

    var usesDarkGradientTreatment: Bool {
        switch normalizedSelection {
        case .black, .dark, .dracula, .gamer:
            return true
        case .system, .white, .sakura, .holographicLight, .holographicDark, .light:
            return false
        }
    }
}

enum HolographicGradientOption: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case softHolographicSheen
    case iridescentPastelFilm
    case holographicChromeLook
    case neonHolographicBlend
    case pearlHolographicGradient
    case strongRainbowFoil
    case multiLayerHolographicFoil
    case radialHolographicGlow

    struct AccentPalette {
        let primary: Color
        let secondary: Color
        let tertiary: Color
        let shadow: Color
    }

    enum PreviewEffect {
        case none
        case sheen
        case radialGlow
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .softHolographicSheen:
            return "Soft holographic sheen"
        case .iridescentPastelFilm:
            return "Iridescent pastel film"
        case .holographicChromeLook:
            return "Holographic chrome look"
        case .neonHolographicBlend:
            return "Neon holographic blend"
        case .pearlHolographicGradient:
            return "Pearl holographic gradient"
        case .strongRainbowFoil:
            return "Strong rainbow foil"
        case .multiLayerHolographicFoil:
            return "Multi-layer holographic foil"
        case .radialHolographicGlow:
            return "Radial holographic glow"
        }
    }

    var previewEffect: PreviewEffect {
        switch self {
        case .multiLayerHolographicFoil:
            return .sheen
        case .radialHolographicGlow:
            return .radialGlow
        case .softHolographicSheen,
             .iridescentPastelFilm,
             .holographicChromeLook,
             .neonHolographicBlend,
             .pearlHolographicGradient,
             .strongRainbowFoil:
            return .none
        }
    }

    var buttonGradient: LinearGradient {
        LinearGradient(
            stops: buttonStops,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var uiGradient: LinearGradient {
        LinearGradient(
            stops: uiStops,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func borderColor(for theme: AppThemeOption) -> Color {
        switch self {
        case .softHolographicSheen:
            return theme.usesDarkGradientTreatment
                ? Self.rgba(154, 178, 224, 0.26)
                : Self.rgba(122, 138, 170, 0.26)
        case .iridescentPastelFilm:
            return theme.usesDarkGradientTreatment
                ? Self.rgba(186, 191, 214, 0.24)
                : Self.rgba(151, 157, 179, 0.22)
        case .holographicChromeLook:
            return theme.usesDarkGradientTreatment
                ? Self.rgba(180, 175, 167, 0.24)
                : Self.rgba(142, 139, 134, 0.24)
        case .neonHolographicBlend:
            return theme.usesDarkGradientTreatment
                ? Self.rgba(131, 162, 208, 0.28)
                : Self.rgba(96, 122, 162, 0.26)
        case .pearlHolographicGradient:
            return theme.usesDarkGradientTreatment
                ? Self.rgba(196, 196, 206, 0.22)
                : Self.rgba(161, 162, 174, 0.20)
        case .strongRainbowFoil:
            return theme.usesDarkGradientTreatment
                ? Self.rgba(166, 154, 190, 0.28)
                : Self.rgba(125, 117, 150, 0.26)
        case .multiLayerHolographicFoil:
            return theme.usesDarkGradientTreatment
                ? Self.rgba(162, 176, 196, 0.26)
                : Self.rgba(124, 137, 157, 0.24)
        case .radialHolographicGlow:
            return theme.usesDarkGradientTreatment
                ? Self.rgba(155, 177, 206, 0.24)
                : Self.rgba(118, 136, 164, 0.22)
        }
    }

    func accentPalette(for theme: AppThemeOption) -> AccentPalette {
        switch self {
        case .softHolographicSheen:
            if theme.usesDarkGradientTreatment {
                return AccentPalette(
                    primary: Self.hex(0x8B7DFF),
                    secondary: Self.hex(0xFF8FCF),
                    tertiary: Self.hex(0x6FD6FF),
                    shadow: Self.hex(0xFF8FCF)
                )
            }
            return AccentPalette(
                primary: Self.hex(0x6FD6FF),
                secondary: Self.hex(0x8B7DFF),
                tertiary: Self.hex(0x8FE3B0),
                shadow: Self.hex(0xFF8FCF)
            )
        case .iridescentPastelFilm:
            if theme.usesDarkGradientTreatment {
                return AccentPalette(
                    primary: Self.hex(0xF6DCFB),
                    secondary: Self.hex(0xD9D6FF),
                    tertiary: Self.hex(0xE2EDFF),
                    shadow: Self.hex(0xF6DCFB)
                )
            }
            return AccentPalette(
                primary: Self.hex(0xE2EDFF),
                secondary: Self.hex(0xF6DCFB),
                tertiary: Self.hex(0xEEF7D8),
                shadow: Self.hex(0xD9D6FF)
            )
        case .holographicChromeLook:
            if theme.usesDarkGradientTreatment {
                return AccentPalette(
                    primary: Self.hex(0xD8D4EE),
                    secondary: Self.hex(0xF4B5B2),
                    tertiary: Self.hex(0xC8ECB2),
                    shadow: Self.hex(0xF0D9A2)
                )
            }
            return AccentPalette(
                primary: Self.hex(0xF4B5B2),
                secondary: Self.hex(0xD8D4EE),
                tertiary: Self.hex(0xC8ECB2),
                shadow: Self.hex(0xF0D9A2)
            )
        case .neonHolographicBlend:
            if theme.usesDarkGradientTreatment {
                return AccentPalette(
                    primary: Self.hex(0x5D6BFF),
                    secondary: Self.hex(0xFF56C8),
                    tertiary: Self.hex(0x47D8FF),
                    shadow: Self.hex(0xFF56C8)
                )
            }
            return AccentPalette(
                primary: Self.hex(0x47D8FF),
                secondary: Self.hex(0x5D6BFF),
                tertiary: Self.hex(0x57EFB7),
                shadow: Self.hex(0xFF56C8)
            )
        case .pearlHolographicGradient:
            if theme.usesDarkGradientTreatment {
                return AccentPalette(
                    primary: Self.hex(0xF3EBFF),
                    secondary: Self.hex(0xE2EFFF),
                    tertiary: Self.hex(0xFFF2DA),
                    shadow: Self.hex(0xF3EBFF)
                )
            }
            return AccentPalette(
                primary: Self.hex(0xE2EFFF),
                secondary: Self.hex(0xF3EBFF),
                tertiary: Self.hex(0xECF8DF),
                shadow: Self.hex(0xF3EBFF)
            )
        case .strongRainbowFoil:
            if theme.usesDarkGradientTreatment {
                return AccentPalette(
                    primary: Self.hex(0xD97CFF),
                    secondary: Self.hex(0x69A6FF),
                    tertiary: Self.hex(0xFF5D72),
                    shadow: Self.hex(0xD97CFF)
                )
            }
            return AccentPalette(
                primary: Self.hex(0x69A6FF),
                secondary: Self.hex(0xD97CFF),
                tertiary: Self.hex(0x57DCB5),
                shadow: Self.hex(0xFF5D72)
            )
        case .multiLayerHolographicFoil:
            if theme.usesDarkGradientTreatment {
                return AccentPalette(
                    primary: Self.hex(0xD59CFF),
                    secondary: Self.hex(0xFF94DC),
                    tertiary: Self.hex(0x7FDFFF),
                    shadow: Self.hex(0xFF94DC)
                )
            }
            return AccentPalette(
                primary: Self.hex(0x7FDFFF),
                secondary: Self.hex(0xD59CFF),
                tertiary: Self.hex(0x8BE8C3),
                shadow: Self.hex(0xFF94DC)
            )
        case .radialHolographicGlow:
            if theme.usesDarkGradientTreatment {
                return AccentPalette(
                    primary: Self.hex(0x7CA7FF),
                    secondary: Self.hex(0xF0B7EC),
                    tertiary: Self.hex(0xABF0CD),
                    shadow: Self.hex(0xF0B7EC)
                )
            }
            return AccentPalette(
                primary: Self.hex(0x7CA7FF),
                secondary: Self.hex(0xF0B7EC),
                tertiary: Self.hex(0xABF0CD),
                shadow: Self.hex(0xF0B7EC)
            )
        }
    }

    var defaultLinkColor: Color {
        switch self {
        case .softHolographicSheen:
            return Self.hex(0xFF6EC4)
        case .iridescentPastelFilm:
            return Self.hex(0xC76BFF)
        case .holographicChromeLook:
            return Self.hex(0xF97376)
        case .neonHolographicBlend:
            return Self.hex(0xFF00CC)
        case .pearlHolographicGradient:
            return Self.hex(0x8B5CF6)
        case .strongRainbowFoil:
            return Self.hex(0xFF4FD8)
        case .multiLayerHolographicFoil:
            return Self.hex(0xC77DFF)
        case .radialHolographicGlow:
            return Self.hex(0x5B8CFF)
        }
    }

    private var buttonStops: [Gradient.Stop] {
        switch self {
        case .softHolographicSheen:
            return [
                Self.stop(0xFF6EC4, 0.00),
                Self.stop(0x7873F5, 0.20),
                Self.stop(0x4ADEFF, 0.40),
                Self.stop(0x7CF29C, 0.60),
                Self.stop(0xFFF275, 0.80),
                Self.stop(0xFF8FAB, 1.00)
            ]
        case .iridescentPastelFilm:
            return [
                Self.stop(0xFDFBFB, 0.00),
                Self.stop(0xEBEDEE, 0.08),
                Self.stop(0xD6EAFF, 0.22),
                Self.stop(0xFFD6F6, 0.38),
                Self.stop(0xD8FFD6, 0.55),
                Self.stop(0xFFF0C2, 0.72),
                Self.stop(0xD9D6FF, 0.88),
                Self.stop(0xFFFFFF, 1.00)
            ]
        case .holographicChromeLook:
            return [
                Self.stop(0xCFD9DF, 0.00),
                Self.stop(0xE2EBF0, 0.12),
                Self.stop(0xF6D365, 0.24),
                Self.stop(0xFDA085, 0.36),
                Self.stop(0xC3CFE2, 0.48),
                Self.stop(0xFBC2EB, 0.62),
                Self.stop(0xA1C4FD, 0.78),
                Self.stop(0xD4FC79, 1.00)
            ]
        case .neonHolographicBlend:
            return [
                Self.stop(0xFF00CC, 0.00),
                Self.stop(0x3333FF, 0.18),
                Self.stop(0x00E5FF, 0.36),
                Self.stop(0x00FF99, 0.54),
                Self.stop(0xFFEE00, 0.72),
                Self.stop(0xFF4D6D, 1.00)
            ]
        case .pearlHolographicGradient:
            return [
                Self.stop(0xFFFFFF, 0.00),
                Self.stop(0xF3E8FF, 0.18),
                Self.stop(0xDBEAFE, 0.34),
                Self.stop(0xDCFCE7, 0.50),
                Self.stop(0xFEF3C7, 0.68),
                Self.stop(0xFDE2E4, 0.84),
                Self.stop(0xFFFFFF, 1.00)
            ]
        case .strongRainbowFoil:
            return [
                Self.stop(0xFF003C, 0.00),
                Self.stop(0xFF8A00, 0.16),
                Self.stop(0xFFE600, 0.32),
                Self.stop(0x00D084, 0.48),
                Self.stop(0x00C2FF, 0.64),
                Self.stop(0x7A5CFF, 0.82),
                Self.stop(0xFF4FD8, 1.00)
            ]
        case .multiLayerHolographicFoil:
            return [
                Self.stop(0xFF7AD9, 0.00),
                Self.stop(0x7AFCFF, 0.20),
                Self.stop(0x7AFFB3, 0.40),
                Self.stop(0xFFF47A, 0.60),
                Self.stop(0xC77DFF, 0.80),
                Self.stop(0xFF7A7A, 1.00)
            ]
        case .radialHolographicGlow:
            return [
                Self.stop(0x5B8CFF, 0.00),
                Self.stop(0x9BFFB0, 0.25),
                Self.stop(0xFFF3A3, 0.50),
                Self.stop(0xFFB3E6, 0.75),
                Self.stop(0xBFA6FF, 1.00)
            ]
        }
    }

    private var uiStops: [Gradient.Stop] {
        switch self {
        case .softHolographicSheen:
            return [
                Self.stop(0xFF8FCF, 0.00),
                Self.stop(0x8B7DFF, 0.28),
                Self.stop(0x6FD6FF, 0.58),
                Self.stop(0x8FE3B0, 0.78),
                Self.stop(0xFFD7A3, 1.00)
            ]
        case .iridescentPastelFilm:
            return [
                Self.stop(0xFBF7FF, 0.00),
                Self.stop(0xE2EDFF, 0.30),
                Self.stop(0xF6DCFB, 0.58),
                Self.stop(0xEEF7D8, 0.82),
                Self.stop(0xFFF8E2, 1.00)
            ]
        case .holographicChromeLook:
            return [
                Self.stop(0xDBE3E8, 0.00),
                Self.stop(0xF0D9A2, 0.32),
                Self.stop(0xF4B5B2, 0.58),
                Self.stop(0xD8D4EE, 0.82),
                Self.stop(0xC8ECB2, 1.00)
            ]
        case .neonHolographicBlend:
            return [
                Self.stop(0xFF56C8, 0.00),
                Self.stop(0x5D6BFF, 0.30),
                Self.stop(0x47D8FF, 0.58),
                Self.stop(0x57EFB7, 0.82),
                Self.stop(0xFFD36E, 1.00)
            ]
        case .pearlHolographicGradient:
            return [
                Self.stop(0xFFFEFE, 0.00),
                Self.stop(0xF3EBFF, 0.30),
                Self.stop(0xE2EFFF, 0.56),
                Self.stop(0xECF8DF, 0.80),
                Self.stop(0xFFF2DA, 1.00)
            ]
        case .strongRainbowFoil:
            return [
                Self.stop(0xFF5D72, 0.00),
                Self.stop(0xFFB14F, 0.24),
                Self.stop(0xFFE27A, 0.46),
                Self.stop(0x57DCB5, 0.68),
                Self.stop(0x69A6FF, 0.86),
                Self.stop(0xD97CFF, 1.00)
            ]
        case .multiLayerHolographicFoil:
            return [
                Self.stop(0xFF94DC, 0.00),
                Self.stop(0x7FDFFF, 0.30),
                Self.stop(0x8BE8C3, 0.58),
                Self.stop(0xF7E38C, 0.80),
                Self.stop(0xD59CFF, 1.00)
            ]
        case .radialHolographicGlow:
            return [
                Self.stop(0x7CA7FF, 0.00),
                Self.stop(0xABF0CD, 0.34),
                Self.stop(0xFFF0A8, 0.66),
                Self.stop(0xF0B7EC, 1.00)
            ]
        }
    }

    private static func stop(_ hex: Int, _ location: Double) -> Gradient.Stop {
        Gradient.Stop(color: self.hex(hex), location: location)
    }

    private static func hex(_ value: Int, opacity: Double = 1) -> Color {
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue).opacity(opacity)
    }

    private static func rgba(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double) -> Color {
        Color(red: red / 255.0, green: green / 255.0, blue: blue / 255.0).opacity(alpha)
    }
}

struct StoredColor: Codable, Hashable, Sendable {
    let archivedData: Data

    init(color: Color) {
        let uiColor = UIColor(color)
        archivedData = (try? NSKeyedArchiver.archivedData(withRootObject: uiColor, requiringSecureCoding: true)) ?? Data()
    }

    var color: Color {
        color(fallback: AppSettingsStore.defaultPrimaryColor)
    }

    func color(fallback: Color) -> Color {
        guard !archivedData.isEmpty,
              let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: archivedData) else {
            return fallback
        }
        return Color(uiColor)
    }
}

struct GeneratedButtonGradient: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let colors: [StoredColor]

    init(id: UUID = UUID(), colors: [Color]) {
        self.id = id
        self.colors = Array(colors.prefix(3)).map(StoredColor.init(color:))
    }

    var gradient: LinearGradient {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var gradientColors: [Color] {
        let decodedColors = colors.map(\.color)
        if decodedColors.count >= 2 {
            return Array(decodedColors.prefix(3))
        }
        return [
            AppSettingsStore.defaultPrimaryColor,
            AppSettingsStore.defaultPrimaryColor
        ]
    }

    static func random() -> GeneratedButtonGradient {
        let colorCount = Int.random(in: 2...3)
        let colors = (0..<colorCount).map { index in
            randomColor(index: index, count: colorCount)
        }
        return GeneratedButtonGradient(colors: colors)
    }

    private static func randomColor(index: Int, count: Int) -> Color {
        let baseHue = Double.random(in: 0...1)
        let offset = Double(index) / Double(max(count, 1))
        let hue = (baseHue + offset).truncatingRemainder(dividingBy: 1)
        let saturation = Double.random(in: 0.58...0.86)
        let brightness = Double.random(in: 0.72...0.98)
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

enum AppFontSize: Int, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case small
    case medium
    case large
    case extraLarge

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .small:
            return "Small"
        case .medium:
            return "Default"
        case .large:
            return "Large"
        case .extraLarge:
            return "XL"
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small:
            return .small
        case .medium:
            return .medium
        case .large:
            return .large
        case .extraLarge:
            return .xLarge
        }
    }
}

enum BreakReminderInterval: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case off
    case twentyMinutes
    case fortyMinutes
    case oneHour
    case twoHours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .twentyMinutes:
            return "20 Minutes"
        case .fortyMinutes:
            return "40 Minutes"
        case .oneHour:
            return "1 Hour"
        case .twoHours:
            return "2 Hours"
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .off:
            return nil
        case .twentyMinutes:
            return 20 * 60
        case .fortyMinutes:
            return 40 * 60
        case .oneHour:
            return 60 * 60
        case .twoHours:
            return 2 * 60 * 60
        }
    }
}

struct CustomFeedDefinition: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var iconSystemName: String
    var hashtags: [String]
    var authorPubkeys: [String]
    var phrases: [String]

    init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        iconSystemName: String = CustomFeedIconCatalog.defaultIcon,
        hashtags: [String] = [],
        authorPubkeys: [String] = [],
        phrases: [String] = []
    ) {
        self.id = id
        self.name = name
        self.iconSystemName = iconSystemName
        self.hashtags = hashtags
        self.authorPubkeys = authorPubkeys
        self.phrases = phrases
    }

    var hasSources: Bool {
        !hashtags.isEmpty || !authorPubkeys.isEmpty || !phrases.isEmpty
    }

    var cacheSignature: String {
        [
            name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            iconSystemName.lowercased(),
            hashtags.joined(separator: ","),
            authorPubkeys.joined(separator: ","),
            phrases.map { $0.lowercased() }.joined(separator: ",")
        ].joined(separator: "|")
    }
}

enum CustomFeedIconCatalog {
    static let defaultIcon = "square.stack.3d.up.fill"

    static let availableIcons: [String] = [
        "square.stack.3d.up.fill",
        "magnifyingglass",
        "newspaper.fill",
        "sparkles",
        "bolt.fill",
        "waveform.path.ecg",
        "soccerball",
        "trophy.fill",
        "figure.run",
        "globe.americas.fill",
        "chart.line.uptrend.xyaxis",
        "music.note",
        "headphones",
        "mic.fill",
        "film.fill",
        "camera.fill",
        "gamecontroller.fill",
        "leaf.fill",
        "flame.fill",
        "moon.stars.fill",
        "sun.max.fill",
        "flag.fill",
        "bird.fill",
        "book.fill",
        "heart.text.square.fill",
        "person.3.fill"
    ]

    static func normalizedIcon(_ iconSystemName: String?) -> String {
        guard let iconSystemName, availableIcons.contains(iconSystemName) else {
            return defaultIcon
        }
        return iconSystemName
    }

    static func randomIconName() -> String {
        availableIcons.randomElement() ?? defaultIcon
    }
}

enum AppSettingsError: LocalizedError {
    case invalidNewsRelayURL
    case newsRelayRequired
    case invalidNewsAuthorIdentifier
    case invalidNewsHashtag
    case invalidCustomFeedName
    case customFeedRequiresContent

    var errorDescription: String? {
        switch self {
        case .invalidNewsRelayURL:
            return "Enter a valid News relay URL (wss://...)."
        case .newsRelayRequired:
            return "Keep at least one News relay."
        case .invalidNewsAuthorIdentifier:
            return "Enter a valid hex pubkey, npub, or nprofile for News people."
        case .invalidNewsHashtag:
            return "Enter a valid hashtag for the News feed."
        case .invalidCustomFeedName:
            return "Give your feed a name."
        case .customFeedRequiresContent:
            return "Add at least one hashtag, person, or phrase to save this feed."
        }
    }
}

@MainActor
final class AppSettingsStore: ObservableObject {
    static let shared = AppSettingsStore()
    nonisolated static let slowModeRelayURL = URL(string: "wss://relay.damus.io/")!
    nonisolated static let defaultNewsRelayURLs = [URL(string: "wss://news.utxo.one")!]
    nonisolated static var defaultPrimaryColor: Color {
        Color(red: 0.843, green: 0.663, blue: 0.463)
    }
    nonisolated static var defaultButtonTextColor: Color {
        Color.white
    }
    nonisolated static let legacyStorageKey = "x21.app.settings"
    nonisolated static let legacyScopedStorageKeyPrefix = "x21.app.settings.v2"
    nonisolated static let storageKeyPrefix = "flow.app.settings.v2"
    nonisolated static let legacyMigrationAccountKey = "flow.app.settings.legacyMigratedAccount"
    nonisolated static let sharedSpamFilterMarkedPubkeysKey = "flow.app.spamFilter.markedPubkeys.v1"

    private struct MentionMetadataDecoder: MetadataCoding {}

    @Published private var persistedSettings: PersistedSettings
    @Published private(set) var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var previewTheme: AppThemeOption?
    @Published private(set) var previewFontOption: AppFontOption?
    @Published private var sharedSpamFilterMarkedPubkeys: [String]

    private let defaults: UserDefaults
    private let authStore: AuthStore
    private var currentAccountStorageID: String?
    private var notificationAuthorizationTask: Task<Void, Never>?

    private struct PersistedSettings: Codable, Sendable {
        private enum CodingKeys: String, CodingKey {
            case primaryColor
            case theme
            case buttonGradientOption
            case generatedButtonGradient
            case buttonTextColor
            case holographicLightGradientOption
            case holographicDarkGradientOption
            case fontOption
            case fontSize
            case breakReminderInterval
            case liveReactsEnabled
            case hideNSFWContent
            case spamReplyFilterEnabled
            case spamFilterMarkedPubkeys
            case spamReplyFilterSafelistedPubkeys
            case autoplayVideos
            case autoplayVideoSoundEnabled
            case blurMediaFromUnfollowedAuthors
            case mediaEfficiencyEnabled
            case mediaFileSizeLimitsEnabled
            case largeGIFAutoplayLimitEnabled
            case floatingComposeButtonEnabled
            case fullWidthNoteRows
            case textOnlyMode
            case slowConnectionMode
            case notificationsEnabled
            case activityMentionNotificationsEnabled
            case activityReactionNotificationsEnabled
            case activityReplyNotificationsEnabled
            case activityReshareNotificationsEnabled
            case activityQuoteShareNotificationsEnabled
            case mediaUploadProvider
            case newsRelayURLs
            case newsAuthorPubkeys
            case newsHashtags
            case pollsFeedVisible
            case customFeeds
            case webOfTrustHops
        }

        var primaryColor: StoredColor?
        var theme: AppThemeOption = .system
        var buttonGradientOption: HolographicGradientOption?
        var generatedButtonGradient: GeneratedButtonGradient?
        var buttonTextColor: StoredColor?
        var fontOption: AppFontOption = .system
        var fontSize: AppFontSize = .medium
        var breakReminderInterval: BreakReminderInterval = .fortyMinutes
        var liveReactsEnabled: Bool = true
        var hideNSFWContent: Bool = true
        var spamReplyFilterEnabled: Bool = true
        var spamFilterMarkedPubkeys: [String] = []
        var spamReplyFilterSafelistedPubkeys: [String] = []
        var autoplayVideos: Bool = true
        var autoplayVideoSoundEnabled: Bool = false
        var blurMediaFromUnfollowedAuthors: Bool = true
        var mediaEfficiencyEnabled: Bool = true
        var mediaFileSizeLimitsEnabled: Bool = true
        var largeGIFAutoplayLimitEnabled: Bool = true
        var floatingComposeButtonEnabled: Bool = false
        var fullWidthNoteRows: Bool = false
        var textOnlyMode: Bool = false
        var slowConnectionMode: Bool = false
        var notificationsEnabled: Bool = false
        var activityMentionNotificationsEnabled: Bool = true
        var activityReactionNotificationsEnabled: Bool = true
        var activityReplyNotificationsEnabled: Bool = true
        var activityReshareNotificationsEnabled: Bool = true
        var activityQuoteShareNotificationsEnabled: Bool = true
        var mediaUploadProvider: MediaUploadProvider = .blossom
        var newsRelayURLs: [URL] = AppSettingsStore.defaultNewsRelayURLs
        var newsAuthorPubkeys: [String] = []
        var newsHashtags: [String] = []
        var pollsFeedVisible: Bool = true
        var customFeeds: [CustomFeedDefinition] = []
        var webOfTrustHops: Int = 3

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            primaryColor = try container.decodeIfPresent(StoredColor.self, forKey: .primaryColor)
            let decodedTheme = (try? container.decode(AppThemeOption.self, forKey: .theme)) ?? .system
            theme = decodedTheme.normalizedSelection
            buttonGradientOption = try container.decodeIfPresent(HolographicGradientOption.self, forKey: .buttonGradientOption)
            generatedButtonGradient = try container.decodeIfPresent(GeneratedButtonGradient.self, forKey: .generatedButtonGradient)
            buttonTextColor = try container.decodeIfPresent(StoredColor.self, forKey: .buttonTextColor)
            if buttonGradientOption == nil {
                switch decodedTheme {
                case .holographicLight:
                    buttonGradientOption = try container.decodeIfPresent(
                        HolographicGradientOption.self,
                        forKey: .holographicLightGradientOption
                    )
                case .holographicDark:
                    buttonGradientOption = try container.decodeIfPresent(
                        HolographicGradientOption.self,
                        forKey: .holographicDarkGradientOption
                    )
                case .system, .black, .white, .sakura, .dracula, .gamer, .dark, .light:
                    break
                }
            }
            fontOption = (try? container.decode(AppFontOption.self, forKey: .fontOption)) ?? .system
            fontSize = (try? container.decode(AppFontSize.self, forKey: .fontSize)) ?? .medium
            breakReminderInterval = (try? container.decode(BreakReminderInterval.self, forKey: .breakReminderInterval)) ?? .fortyMinutes
            liveReactsEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveReactsEnabled) ?? true
            hideNSFWContent = try container.decodeIfPresent(Bool.self, forKey: .hideNSFWContent) ?? true
            spamReplyFilterEnabled = try container.decodeIfPresent(Bool.self, forKey: .spamReplyFilterEnabled) ?? true
            spamFilterMarkedPubkeys = AppSettingsStore.normalizedNewsAuthorPubkeys(
                try container.decodeIfPresent([String].self, forKey: .spamFilterMarkedPubkeys) ?? []
            )
            spamReplyFilterSafelistedPubkeys = AppSettingsStore.normalizedNewsAuthorPubkeys(
                try container.decodeIfPresent([String].self, forKey: .spamReplyFilterSafelistedPubkeys) ?? []
            )
            autoplayVideos = try container.decodeIfPresent(Bool.self, forKey: .autoplayVideos) ?? true
            autoplayVideoSoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoplayVideoSoundEnabled) ?? false
            blurMediaFromUnfollowedAuthors = try container.decodeIfPresent(Bool.self, forKey: .blurMediaFromUnfollowedAuthors) ?? true
            mediaEfficiencyEnabled = try container.decodeIfPresent(Bool.self, forKey: .mediaEfficiencyEnabled) ?? true
            mediaFileSizeLimitsEnabled = try container.decodeIfPresent(Bool.self, forKey: .mediaFileSizeLimitsEnabled) ?? true
            largeGIFAutoplayLimitEnabled = try container.decodeIfPresent(Bool.self, forKey: .largeGIFAutoplayLimitEnabled) ?? true
            floatingComposeButtonEnabled = try container.decodeIfPresent(Bool.self, forKey: .floatingComposeButtonEnabled) ?? false
            fullWidthNoteRows = try container.decodeIfPresent(Bool.self, forKey: .fullWidthNoteRows) ?? false
            textOnlyMode = try container.decodeIfPresent(Bool.self, forKey: .textOnlyMode) ?? false
            slowConnectionMode = try container.decodeIfPresent(Bool.self, forKey: .slowConnectionMode) ?? false
            notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
            activityMentionNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .activityMentionNotificationsEnabled) ?? true
            activityReactionNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .activityReactionNotificationsEnabled) ?? true
            activityReplyNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .activityReplyNotificationsEnabled) ?? true
            activityReshareNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .activityReshareNotificationsEnabled) ?? true
            activityQuoteShareNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .activityQuoteShareNotificationsEnabled) ?? true
            mediaUploadProvider = (try? container.decode(MediaUploadProvider.self, forKey: .mediaUploadProvider)) ?? .blossom
            newsRelayURLs = AppSettingsStore.normalizedRelayURLs(
                (try? container.decode([URL].self, forKey: .newsRelayURLs)) ?? AppSettingsStore.defaultNewsRelayURLs,
                fallback: AppSettingsStore.defaultNewsRelayURLs
            )
            newsAuthorPubkeys = AppSettingsStore.normalizedNewsAuthorPubkeys(
                try container.decodeIfPresent([String].self, forKey: .newsAuthorPubkeys) ?? []
            )
            newsHashtags = AppSettingsStore.normalizedNewsHashtags(
                try container.decodeIfPresent([String].self, forKey: .newsHashtags) ?? []
            )
            pollsFeedVisible = try container.decodeIfPresent(Bool.self, forKey: .pollsFeedVisible) ?? true
            customFeeds = AppSettingsStore.normalizedCustomFeeds(
                try container.decodeIfPresent([CustomFeedDefinition].self, forKey: .customFeeds) ?? []
            )
            webOfTrustHops = AppSettingsStore.clampedWebOfTrustHops(
                try container.decodeIfPresent(Int.self, forKey: .webOfTrustHops) ?? 3
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(primaryColor, forKey: .primaryColor)
            try container.encode(theme, forKey: .theme)
            try container.encodeIfPresent(buttonGradientOption, forKey: .buttonGradientOption)
            try container.encodeIfPresent(generatedButtonGradient, forKey: .generatedButtonGradient)
            try container.encodeIfPresent(buttonTextColor, forKey: .buttonTextColor)
            try container.encode(fontOption, forKey: .fontOption)
            try container.encode(fontSize, forKey: .fontSize)
            try container.encode(breakReminderInterval, forKey: .breakReminderInterval)
            try container.encode(liveReactsEnabled, forKey: .liveReactsEnabled)
            try container.encode(hideNSFWContent, forKey: .hideNSFWContent)
            try container.encode(spamReplyFilterEnabled, forKey: .spamReplyFilterEnabled)
            try container.encode(spamFilterMarkedPubkeys, forKey: .spamFilterMarkedPubkeys)
            try container.encode(spamReplyFilterSafelistedPubkeys, forKey: .spamReplyFilterSafelistedPubkeys)
            try container.encode(autoplayVideos, forKey: .autoplayVideos)
            try container.encode(autoplayVideoSoundEnabled, forKey: .autoplayVideoSoundEnabled)
            try container.encode(blurMediaFromUnfollowedAuthors, forKey: .blurMediaFromUnfollowedAuthors)
            try container.encode(mediaEfficiencyEnabled, forKey: .mediaEfficiencyEnabled)
            try container.encode(mediaFileSizeLimitsEnabled, forKey: .mediaFileSizeLimitsEnabled)
            try container.encode(largeGIFAutoplayLimitEnabled, forKey: .largeGIFAutoplayLimitEnabled)
            try container.encode(floatingComposeButtonEnabled, forKey: .floatingComposeButtonEnabled)
            try container.encode(fullWidthNoteRows, forKey: .fullWidthNoteRows)
            try container.encode(textOnlyMode, forKey: .textOnlyMode)
            try container.encode(slowConnectionMode, forKey: .slowConnectionMode)
            try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
            try container.encode(activityMentionNotificationsEnabled, forKey: .activityMentionNotificationsEnabled)
            try container.encode(activityReactionNotificationsEnabled, forKey: .activityReactionNotificationsEnabled)
            try container.encode(activityReplyNotificationsEnabled, forKey: .activityReplyNotificationsEnabled)
            try container.encode(activityReshareNotificationsEnabled, forKey: .activityReshareNotificationsEnabled)
            try container.encode(activityQuoteShareNotificationsEnabled, forKey: .activityQuoteShareNotificationsEnabled)
            try container.encode(mediaUploadProvider, forKey: .mediaUploadProvider)
            try container.encode(newsRelayURLs, forKey: .newsRelayURLs)
            try container.encode(newsAuthorPubkeys, forKey: .newsAuthorPubkeys)
            try container.encode(newsHashtags, forKey: .newsHashtags)
            try container.encode(pollsFeedVisible, forKey: .pollsFeedVisible)
            try container.encode(customFeeds, forKey: .customFeeds)
            try container.encode(webOfTrustHops, forKey: .webOfTrustHops)
        }
    }

    init(defaults: UserDefaults = .standard, authStore: AuthStore = .shared) {
        self.defaults = defaults
        self.authStore = authStore
        self.sharedSpamFilterMarkedPubkeys = Self.loadSharedSpamFilterMarkedPubkeys(defaults: defaults)
        let authState = authStore.load()
        let initialAccountStorageID = Self.normalizedSettingsAccountID(
            authState.accounts.first(where: { $0.id == authState.currentAccountID })?.pubkey
        )
        let allowLegacyGlobalMigration = authState.accounts.count <= 1
        self.currentAccountStorageID = initialAccountStorageID

        if let initialAccountStorageID,
           let migratedSettings = Self.migrateLegacySettingsIfNeeded(
               defaults: defaults,
               accountStorageID: initialAccountStorageID,
               allowLegacyGlobalMigration: allowLegacyGlobalMigration
           ) {
            persistedSettings = migratedSettings
        } else if let initialAccountStorageID {
            persistedSettings = Self.loadPersistedSettings(
                defaults: defaults,
                accountStorageID: initialAccountStorageID,
                allowLegacyFallback: false
            )
        } else {
            persistedSettings = PersistedSettings()
        }
        migrateScopedSpamFilterMarkedPubkeysIfNeeded()
    }

    deinit {
        notificationAuthorizationTask?.cancel()
    }

    func configure(accountPubkey: String?) {
        let normalizedAccountStorageID = Self.normalizedSettingsAccountID(accountPubkey)
        guard currentAccountStorageID != normalizedAccountStorageID else { return }
        let allowLegacyGlobalMigration = authStore.hasSingleAccountHint()

        currentAccountStorageID = normalizedAccountStorageID

        guard let normalizedAccountStorageID else {
            persistedSettings = PersistedSettings()
            return
        }

        if let migratedSettings = Self.migrateLegacySettingsIfNeeded(
            defaults: defaults,
            accountStorageID: normalizedAccountStorageID,
            allowLegacyGlobalMigration: allowLegacyGlobalMigration
        ) {
            persistedSettings = migratedSettings
            migrateScopedSpamFilterMarkedPubkeysIfNeeded()
            return
        }

        persistedSettings = Self.loadPersistedSettings(
            defaults: defaults,
            accountStorageID: normalizedAccountStorageID,
            allowLegacyFallback: false
        )
        migrateScopedSpamFilterMarkedPubkeysIfNeeded()
    }

    var primaryColor: Color {
        get { persistedSettings.primaryColor?.color ?? Self.defaultPrimaryColor }
        set {
            persistedSettings.primaryColor = StoredColor(color: newValue)
            persist()
        }
    }

    var buttonGradientOption: HolographicGradientOption? {
        get { persistedSettings.buttonGradientOption }
        set {
            persistedSettings.buttonGradientOption = newValue
            persistedSettings.generatedButtonGradient = nil
            persist()
        }
    }

    var generatedButtonGradient: GeneratedButtonGradient? {
        get { persistedSettings.generatedButtonGradient }
        set {
            persistedSettings.generatedButtonGradient = newValue
            if newValue != nil {
                persistedSettings.buttonGradientOption = nil
            }
            persist()
        }
    }

    var buttonTextColor: Color {
        get { Self.buttonTextColor(for: persistedSettings) }
        set {
            persistedSettings.buttonTextColor = StoredColor(color: newValue)
            persist()
        }
    }

    func applyGeneratedButtonGradient(_ gradient: GeneratedButtonGradient) {
        generatedButtonGradient = gradient
    }

    func clearButtonGradient() {
        persistedSettings.buttonGradientOption = nil
        persistedSettings.generatedButtonGradient = nil
        persist()
    }

    var holographicLightGradientOption: HolographicGradientOption {
        get { persistedSettings.buttonGradientOption ?? .softHolographicSheen }
        set { buttonGradientOption = newValue }
    }

    var holographicDarkGradientOption: HolographicGradientOption {
        get { persistedSettings.buttonGradientOption ?? .softHolographicSheen }
        set { buttonGradientOption = newValue }
    }

    var activeButtonGradientOption: HolographicGradientOption? {
        buttonGradientOption
    }

    var activeGeneratedButtonGradient: GeneratedButtonGradient? {
        generatedButtonGradient
    }

    var activeHolographicGradientOption: HolographicGradientOption? {
        activeTheme == .holographicLight ? (buttonGradientOption ?? .softHolographicSheen) : nil
    }

    var themeIconAccentColor: Color {
        themePalette.mutedForeground
    }

    var usesPrimaryGradientForProminentButtons: Bool {
        activeButtonGradientOption != nil || activeGeneratedButtonGradient != nil
    }

    var primaryGradient: LinearGradient {
        Self.primaryGradient(for: persistedSettings)
    }

    func avatarFallbackGradient(forAccountPubkey accountPubkey: String?) -> LinearGradient {
        Self.primaryGradient(for: persistedSettings(forAccountPubkey: accountPubkey))
    }

    func avatarFallbackForeground(forAccountPubkey accountPubkey: String?) -> Color {
        Self.buttonTextColor(for: persistedSettings(forAccountPubkey: accountPubkey))
    }

    var theme: AppThemeOption {
        get { persistedSettings.theme.normalizedSelection }
        set {
            previewTheme = nil
            persistedSettings.theme = newValue.normalizedSelection
            persist()
        }
    }

    var fontSize: AppFontSize {
        get { persistedSettings.fontSize }
        set {
            persistedSettings.fontSize = newValue
            persist()
        }
    }

    var fontOption: AppFontOption {
        get { persistedSettings.fontOption }
        set {
            previewFontOption = nil
            persistedSettings.fontOption = newValue
            persist()
        }
    }

    var breakReminderInterval: BreakReminderInterval {
        get { persistedSettings.breakReminderInterval }
        set {
            persistedSettings.breakReminderInterval = newValue
            persist()
        }
    }

    var liveReactsEnabled: Bool {
        get { persistedSettings.liveReactsEnabled }
        set {
            persistedSettings.liveReactsEnabled = newValue
            persist()
        }
    }

    var textOnlyMode: Bool {
        get { persistedSettings.textOnlyMode }
        set {
            persistedSettings.textOnlyMode = newValue
            persist()
        }
    }

    var hideNSFWContent: Bool {
        get { persistedSettings.hideNSFWContent }
        set {
            persistedSettings.hideNSFWContent = newValue
            persist()
        }
    }

    var spamReplyFilterEnabled: Bool {
        get { persistedSettings.spamReplyFilterEnabled }
        set {
            persistedSettings.spamReplyFilterEnabled = newValue
            persist()
        }
    }

    var spamReplyFilterSafelistedPubkeys: [String] {
        persistedSettings.spamReplyFilterSafelistedPubkeys
    }

    var spamFilterMarkedPubkeys: [String] {
        sharedSpamFilterMarkedPubkeys
    }

    var spamFilterLabelSignature: String {
        [
            spamFilterMarkedPubkeys.joined(separator: "|"),
            spamReplyFilterSafelistedPubkeys.joined(separator: "|")
        ]
        .joined(separator: "-")
    }

    func isSpamReplySafelisted(_ pubkey: String) -> Bool {
        let normalized = pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return persistedSettings.spamReplyFilterSafelistedPubkeys.contains(normalized)
    }

    func isSpamFilterMarked(_ pubkey: String) -> Bool {
        let normalized = pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return sharedSpamFilterMarkedPubkeys.contains(normalized)
    }

    func shouldHideSpamMarkedPubkey(_ pubkey: String) -> Bool {
        isSpamFilterMarked(pubkey) && !isSpamReplySafelisted(pubkey)
    }

    func addSpamReplySafelistedPubkey(_ pubkey: String) {
        guard let normalized = Self.normalizedNewsAuthorPubkey(from: pubkey) else { return }
        if !persistedSettings.spamReplyFilterSafelistedPubkeys.contains(normalized) {
            persistedSettings.spamReplyFilterSafelistedPubkeys.append(normalized)
            persistedSettings.spamReplyFilterSafelistedPubkeys.sort()
            persist()
        }
    }

    func removeSpamReplySafelistedPubkey(_ pubkey: String) {
        let normalized = pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        let updated = persistedSettings.spamReplyFilterSafelistedPubkeys.filter { $0 != normalized }
        guard updated.count != persistedSettings.spamReplyFilterSafelistedPubkeys.count else { return }
        persistedSettings.spamReplyFilterSafelistedPubkeys = updated
        persist()
    }

    func addSpamFilterMarkedPubkey(_ pubkey: String) {
        guard let normalized = Self.normalizedNewsAuthorPubkey(from: pubkey) else { return }
        if persistedSettings.spamReplyFilterSafelistedPubkeys.contains(normalized) {
            persistedSettings.spamReplyFilterSafelistedPubkeys.removeAll { $0 == normalized }
            persist()
        }
        if !sharedSpamFilterMarkedPubkeys.contains(normalized) {
            sharedSpamFilterMarkedPubkeys.append(normalized)
            sharedSpamFilterMarkedPubkeys.sort()
            persistSharedSpamFilterMarkedPubkeys()
        }
    }

    func removeSpamFilterMarkedPubkey(_ pubkey: String) {
        let normalized = pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        let updated = sharedSpamFilterMarkedPubkeys.filter { $0 != normalized }
        guard updated.count != sharedSpamFilterMarkedPubkeys.count else { return }
        sharedSpamFilterMarkedPubkeys = updated
        persistSharedSpamFilterMarkedPubkeys()
    }

    var autoplayVideos: Bool {
        get { persistedSettings.autoplayVideos }
        set {
            persistedSettings.autoplayVideos = newValue
            persist()
        }
    }

    var autoplayVideoSoundEnabled: Bool {
        get { persistedSettings.autoplayVideoSoundEnabled }
        set {
            persistedSettings.autoplayVideoSoundEnabled = newValue
            persist()
        }
    }

    var blurMediaFromUnfollowedAuthors: Bool {
        get { persistedSettings.blurMediaFromUnfollowedAuthors }
        set {
            persistedSettings.blurMediaFromUnfollowedAuthors = newValue
            persist()
        }
    }

    var mediaEfficiencyEnabled: Bool {
        get { persistedSettings.mediaEfficiencyEnabled }
        set {
            persistedSettings.mediaEfficiencyEnabled = newValue
            persist()
        }
    }

    var mediaFileSizeLimitsEnabled: Bool {
        get { persistedSettings.mediaFileSizeLimitsEnabled }
        set {
            persistedSettings.mediaFileSizeLimitsEnabled = newValue
            persist()
        }
    }

    var largeGIFAutoplayLimitEnabled: Bool {
        get { persistedSettings.largeGIFAutoplayLimitEnabled }
        set {
            persistedSettings.largeGIFAutoplayLimitEnabled = newValue
            persist()
        }
    }

    var floatingComposeButtonEnabled: Bool {
        get { persistedSettings.floatingComposeButtonEnabled }
        set {
            persistedSettings.floatingComposeButtonEnabled = newValue
            persist()
        }
    }

    var mediaFileSizeLimitsEffective: Bool {
        mediaEfficiencyEnabled && mediaFileSizeLimitsEnabled
    }

    var largeGIFAutoplayLimitEffective: Bool {
        mediaEfficiencyEnabled && largeGIFAutoplayLimitEnabled
    }

    var fullWidthNoteRows: Bool {
        get { persistedSettings.fullWidthNoteRows }
        set {
            persistedSettings.fullWidthNoteRows = newValue
            persist()
        }
    }

    var slowConnectionMode: Bool {
        get { persistedSettings.slowConnectionMode }
        set {
            persistedSettings.slowConnectionMode = newValue
            persist()
        }
    }

    var notificationsEnabled: Bool {
        get { persistedSettings.notificationsEnabled }
        set {
            persistedSettings.notificationsEnabled = newValue
            persist()

            if newValue {
                scheduleNotificationAuthorizationCheck()
            } else {
                notificationAuthorizationTask?.cancel()
                notificationAuthorizationTask = nil
            }
        }
    }

    var activityMentionNotificationsEnabled: Bool {
        get { persistedSettings.activityMentionNotificationsEnabled }
        set {
            persistedSettings.activityMentionNotificationsEnabled = newValue
            persist()
        }
    }

    var activityReactionNotificationsEnabled: Bool {
        get { persistedSettings.activityReactionNotificationsEnabled }
        set {
            persistedSettings.activityReactionNotificationsEnabled = newValue
            persist()
        }
    }

    var activityReplyNotificationsEnabled: Bool {
        get { persistedSettings.activityReplyNotificationsEnabled }
        set {
            persistedSettings.activityReplyNotificationsEnabled = newValue
            persist()
        }
    }

    var activityReshareNotificationsEnabled: Bool {
        get { persistedSettings.activityReshareNotificationsEnabled }
        set {
            persistedSettings.activityReshareNotificationsEnabled = newValue
            persist()
        }
    }

    var activityQuoteShareNotificationsEnabled: Bool {
        get { persistedSettings.activityQuoteShareNotificationsEnabled }
        set {
            persistedSettings.activityQuoteShareNotificationsEnabled = newValue
            persist()
        }
    }

    var mediaUploadProvider: MediaUploadProvider {
        get { persistedSettings.mediaUploadProvider }
        set {
            persistedSettings.mediaUploadProvider = newValue
            persist()
        }
    }

    var newsRelayURLs: [URL] {
        get { persistedSettings.newsRelayURLs }
        set {
            persistedSettings.newsRelayURLs = Self.normalizedRelayURLs(
                newValue,
                fallback: Self.defaultNewsRelayURLs
            )
            persist()
        }
    }

    var newsAuthorPubkeys: [String] {
        get { persistedSettings.newsAuthorPubkeys }
        set {
            persistedSettings.newsAuthorPubkeys = Self.normalizedNewsAuthorPubkeys(newValue)
            persist()
        }
    }

    var newsHashtags: [String] {
        get { persistedSettings.newsHashtags }
        set {
            persistedSettings.newsHashtags = Self.normalizedNewsHashtags(newValue)
            persist()
        }
    }

    var pollsFeedVisible: Bool {
        get { persistedSettings.pollsFeedVisible }
        set {
            persistedSettings.pollsFeedVisible = newValue
            persist()
        }
    }

    var webOfTrustHops: Int {
        get { persistedSettings.webOfTrustHops }
        set {
            persistedSettings.webOfTrustHops = Self.clampedWebOfTrustHops(newValue)
            persist()
        }
    }

    var customFeeds: [CustomFeedDefinition] {
        get { persistedSettings.customFeeds }
        set {
            persistedSettings.customFeeds = Self.normalizedCustomFeeds(newValue)
            persist()
        }
    }

    func addNewsRelay(_ relayInput: String) throws {
        guard let relayURL = Self.normalizedRelayURL(from: relayInput) else {
            throw AppSettingsError.invalidNewsRelayURL
        }

        setNewsRelayURLs(newsRelayURLs + [relayURL])
    }

    func removeNewsRelay(_ relayURL: URL) throws {
        guard newsRelayURLs.count > 1 else {
            throw AppSettingsError.newsRelayRequired
        }

        let normalizedRelayURL = Self.normalizedRelayURL(relayURL) ?? relayURL
        let updatedRelayURLs = newsRelayURLs.filter { $0.absoluteString != normalizedRelayURL.absoluteString }

        guard updatedRelayURLs.count < newsRelayURLs.count else { return }
        setNewsRelayURLs(updatedRelayURLs)
    }

    func setNewsRelayURLs(_ relayURLs: [URL]) {
        newsRelayURLs = relayURLs
    }

    func addNewsAuthor(_ rawIdentifier: String) throws {
        guard let pubkey = Self.normalizedNewsAuthorPubkey(from: rawIdentifier) else {
            throw AppSettingsError.invalidNewsAuthorIdentifier
        }
        setNewsAuthorPubkeys(newsAuthorPubkeys + [pubkey])
    }

    func removeNewsAuthor(_ pubkey: String) {
        let normalizedPubkey = pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedPubkey.isEmpty else { return }
        newsAuthorPubkeys = newsAuthorPubkeys.filter { $0 != normalizedPubkey }
    }

    func setNewsAuthorPubkeys(_ pubkeys: [String]) {
        newsAuthorPubkeys = pubkeys
    }

    func addNewsHashtag(_ rawHashtag: String) throws {
        guard let hashtag = Self.normalizedNewsHashtag(rawHashtag) else {
            throw AppSettingsError.invalidNewsHashtag
        }
        setNewsHashtags(newsHashtags + [hashtag])
    }

    func removeNewsHashtag(_ hashtag: String) {
        let normalizedHashtag = Self.normalizedNewsHashtag(hashtag) ?? hashtag
        newsHashtags = newsHashtags.filter { $0 != normalizedHashtag }
    }

    func setNewsHashtags(_ hashtags: [String]) {
        newsHashtags = hashtags
    }

    func saveCustomFeed(_ feed: CustomFeedDefinition) throws {
        let normalizedFeed = try Self.normalizedCustomFeed(feed)
        var updatedFeeds = customFeeds

        if let existingIndex = updatedFeeds.firstIndex(where: { $0.id == normalizedFeed.id }) {
            updatedFeeds[existingIndex] = normalizedFeed
        } else {
            updatedFeeds.append(normalizedFeed)
        }

        customFeeds = updatedFeeds
    }

    func removeCustomFeed(id: String) {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedID.isEmpty else { return }
        customFeeds = customFeeds.filter { $0.id != normalizedID }
    }

    func customFeed(withID id: String) -> CustomFeedDefinition? {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedID.isEmpty else { return nil }
        return customFeeds.first { $0.id == normalizedID }
    }

    var activeTheme: AppThemeOption {
        if let previewTheme, previewTheme.isEnabled {
            return previewTheme
        }
        let requestedTheme = persistedSettings.theme.normalizedSelection
        return requestedTheme.isEnabled ? requestedTheme : .system
    }

    var themePalette: AppThemePalette {
        activeTheme.palette
    }

    var settingsCardBorder: Color {
        activeTheme == .gamer ? themePalette.chromeBorder : themePalette.sheetCardBorder
    }

    func themeSeparator(defaultOpacity: Double) -> Color {
        activeTheme == .gamer ? themePalette.separator : themePalette.separator.opacity(defaultOpacity)
    }

    var activeFontOption: AppFontOption {
        if let previewFontOption, previewFontOption.isEnabled {
            return previewFontOption
        }
        let requestedFontOption = persistedSettings.fontOption
        return requestedFontOption.isEnabled ? requestedFontOption : .system
    }

    var canCustomizePrimaryColor: Bool {
        true
    }

    func canBeginThemePreview(_ theme: AppThemeOption) -> Bool {
        theme.isEnabled
    }

    @discardableResult
    func beginThemePreview(_ theme: AppThemeOption) -> Bool {
        guard canBeginThemePreview(theme) else { return false }
        previewTheme = theme
        return true
    }

    func endThemePreview() {
        previewTheme = nil
    }

    func beginFontPreview(_ option: AppFontOption) {
        guard option.isEnabled else { return }
        previewFontOption = option
    }

    func endFontPreview() {
        previewFontOption = nil
    }

    var preferredColorScheme: ColorScheme? {
        activeTheme.preferredColorScheme
    }

    var dynamicTypeSize: DynamicTypeSize {
        fontSize.dynamicTypeSize
    }

    var reactionsVisibleInFeeds: Bool {
        !slowConnectionMode
    }

    func effectiveReadRelayURLs(from relayURLs: [URL]) -> [URL] {
        if slowConnectionMode {
            return [Self.slowModeRelayURL]
        }
        let normalized = Self.normalizedRelayURLs(relayURLs)
        return normalized.isEmpty ? [Self.slowModeRelayURL] : normalized
    }

    func effectiveWriteRelayURLs(from relayURLs: [URL], fallbackReadRelayURLs: [URL] = []) -> [URL] {
        if slowConnectionMode {
            return [Self.slowModeRelayURL]
        }

        let normalizedWrite = Self.normalizedRelayURLs(relayURLs)
        if !normalizedWrite.isEmpty {
            return normalizedWrite
        }

        let normalizedFallback = Self.normalizedRelayURLs(fallbackReadRelayURLs)
        return normalizedFallback.isEmpty ? [Self.slowModeRelayURL] : normalizedFallback
    }

    var notificationsStatusDescription: String {
        switch notificationAuthorizationStatus {
        case .notDetermined:
            return notificationsEnabled
                ? "Waiting for iOS to ask for permission."
                : "Turn this on to request permission."
        case .authorized, .provisional, .ephemeral:
            return notificationsEnabled
                ? "Notifications are enabled on this device."
                : "Notifications are allowed, but this app setting is off."
        case .denied:
            return "Notifications are blocked in iOS Settings."
        @unknown default:
            return "Notification status is unavailable."
        }
    }

    var activityNotificationPreferenceSignature: String {
        [
            activityMentionNotificationsEnabled,
            activityReactionNotificationsEnabled,
            activityReplyNotificationsEnabled,
            activityReshareNotificationsEnabled,
            activityQuoteShareNotificationsEnabled
        ]
        .map { $0 ? "1" : "0" }
        .joined(separator: "-")
    }

    var spamReplyFilterSignature: String {
        [
            spamReplyFilterEnabled ? "1" : "0",
            spamFilterMarkedPubkeys.joined(separator: "|"),
            spamReplyFilterSafelistedPubkeys.joined(separator: "|")
        ]
        .joined(separator: "-")
    }

    func isActivityNotificationEnabled(for preference: ActivityNotificationPreference) -> Bool {
        switch preference {
        case .mentions:
            return activityMentionNotificationsEnabled
        case .reactions:
            return activityReactionNotificationsEnabled
        case .replies:
            return activityReplyNotificationsEnabled
        case .reshares:
            return activityReshareNotificationsEnabled
        case .quoteShares:
            return activityQuoteShareNotificationsEnabled
        }
    }

    func refreshNotificationAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorizationStatus = settings.authorizationStatus

        if settings.authorizationStatus == .denied {
            if persistedSettings.notificationsEnabled {
                persistedSettings.notificationsEnabled = false
                persist()
            }
        }
    }

    private func scheduleNotificationAuthorizationCheck() {
        notificationAuthorizationTask?.cancel()
        notificationAuthorizationTask = Task { [weak self] in
            guard let self else { return }
            await self.resolveNotificationAuthorization()
        }
    }

    private func resolveNotificationAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationAuthorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .denied:
            if persistedSettings.notificationsEnabled {
                persistedSettings.notificationsEnabled = false
                persist()
            }
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            let refreshed = await center.notificationSettings()
            notificationAuthorizationStatus = refreshed.authorizationStatus

            if !granted || !(refreshed.authorizationStatus == .authorized || refreshed.authorizationStatus == .provisional || refreshed.authorizationStatus == .ephemeral) {
                if persistedSettings.notificationsEnabled {
                    persistedSettings.notificationsEnabled = false
                    persist()
                }
            }
        @unknown default:
            if persistedSettings.notificationsEnabled {
                persistedSettings.notificationsEnabled = false
                persist()
            }
        }

        notificationAuthorizationTask = nil
    }

    private func persist() {
        guard currentAccountStorageID != nil else { return }
        guard let data = try? JSONEncoder().encode(persistedSettings) else { return }
        defaults.set(data, forKey: Self.storageKey(for: currentAccountStorageID))
    }

    private func persistSharedSpamFilterMarkedPubkeys() {
        defaults.set(sharedSpamFilterMarkedPubkeys, forKey: Self.sharedSpamFilterMarkedPubkeysKey)
    }

    private func persistedSettings(forAccountPubkey accountPubkey: String?) -> PersistedSettings {
        guard let normalizedAccountStorageID = Self.normalizedSettingsAccountID(accountPubkey) else {
            return persistedSettings
        }

        if normalizedAccountStorageID == currentAccountStorageID {
            return persistedSettings
        }

        return Self.loadPersistedSettings(
            defaults: defaults,
            accountStorageID: normalizedAccountStorageID,
            allowLegacyFallback: false
        )
    }

    private static func primaryGradient(for settings: PersistedSettings) -> LinearGradient {
        if let generatedButtonGradient = settings.generatedButtonGradient {
            return generatedButtonGradient.gradient
        }

        if let buttonGradientOption = settings.buttonGradientOption {
            return buttonGradientOption.buttonGradient
        }

        let color = settings.primaryColor?.color ?? defaultPrimaryColor
        return LinearGradient(
            colors: [color, color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private static func buttonTextColor(for settings: PersistedSettings) -> Color {
        settings.buttonTextColor?.color(fallback: defaultButtonTextColor) ?? defaultButtonTextColor
    }

    private func migrateScopedSpamFilterMarkedPubkeysIfNeeded() {
        guard !persistedSettings.spamFilterMarkedPubkeys.isEmpty else { return }
        let merged = Self.normalizedNewsAuthorPubkeys(
            sharedSpamFilterMarkedPubkeys + persistedSettings.spamFilterMarkedPubkeys
        )
        if merged != sharedSpamFilterMarkedPubkeys {
            sharedSpamFilterMarkedPubkeys = merged
            persistSharedSpamFilterMarkedPubkeys()
        }
        persistedSettings.spamFilterMarkedPubkeys = []
        persist()
    }

    nonisolated private static func storageKey(for accountStorageID: String?) -> String {
        "\(storageKeyPrefix).\(accountStorageID ?? "anonymous")"
    }

    nonisolated private static func legacyScopedStorageKey(for accountStorageID: String?) -> String {
        "\(legacyScopedStorageKeyPrefix).\(accountStorageID ?? "anonymous")"
    }

    nonisolated private static func decodeSettings(from data: Data?) -> PersistedSettings? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(PersistedSettings.self, from: data)
    }

    nonisolated private static func loadSharedSpamFilterMarkedPubkeys(defaults: UserDefaults) -> [String] {
        normalizedNewsAuthorPubkeys(defaults.stringArray(forKey: sharedSpamFilterMarkedPubkeysKey) ?? [])
    }

    nonisolated private static func loadPersistedSettings(
        defaults: UserDefaults,
        accountStorageID: String?,
        allowLegacyFallback: Bool
    ) -> PersistedSettings {
        if let scopedSettings = decodeSettings(from: defaults.data(forKey: storageKey(for: accountStorageID))) {
            return scopedSettings
        }

        if let legacyScopedSettings = decodeSettings(from: defaults.data(forKey: legacyScopedStorageKey(for: accountStorageID))) {
            if let encoded = try? JSONEncoder().encode(legacyScopedSettings) {
                defaults.set(encoded, forKey: storageKey(for: accountStorageID))
            }
            return legacyScopedSettings
        }

        if allowLegacyFallback,
           let legacySettings = decodeSettings(from: defaults.data(forKey: legacyStorageKey)) {
            return legacySettings
        }

        return PersistedSettings()
    }

    nonisolated private static func migrateLegacySettingsIfNeeded(
        defaults: UserDefaults,
        accountStorageID: String,
        allowLegacyGlobalMigration: Bool
    ) -> PersistedSettings? {
        guard defaults.data(forKey: storageKey(for: accountStorageID)) == nil else { return nil }
        if let legacyScopedSettings = decodeSettings(from: defaults.data(forKey: legacyScopedStorageKey(for: accountStorageID))) {
            guard let encoded = try? JSONEncoder().encode(legacyScopedSettings) else { return legacyScopedSettings }
            defaults.set(encoded, forKey: storageKey(for: accountStorageID))
            return legacyScopedSettings
        }

        guard allowLegacyGlobalMigration else { return nil }
        guard defaults.string(forKey: legacyMigrationAccountKey) == nil else { return nil }
        guard let legacySettings = decodeSettings(from: defaults.data(forKey: legacyStorageKey)) else {
            return nil
        }
        guard let encoded = try? JSONEncoder().encode(legacySettings) else { return legacySettings }

        defaults.set(encoded, forKey: storageKey(for: accountStorageID))
        defaults.set(accountStorageID, forKey: legacyMigrationAccountKey)
        return legacySettings
    }

    nonisolated private static func normalizedSettingsAccountID(_ pubkey: String?) -> String? {
        let normalized = pubkey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }

    nonisolated private static func normalizedRelayURL(_ relayURL: URL) -> URL? {
        guard var components = URLComponents(url: relayURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.query = nil
        components.fragment = nil
        if components.path == "/" {
            components.path = ""
        }

        return components.url
    }

    nonisolated private static func normalizedRelayURL(from relayInput: String) -> URL? {
        let trimmedInput = relayInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty, let relayURL = URL(string: trimmedInput) else {
            return nil
        }
        return normalizedRelayURL(relayURL)
    }

    nonisolated static func clampedWebOfTrustHops(_ value: Int) -> Int {
        min(max(value, 1), 5)
    }

    nonisolated private static func normalizedRelayURLs(_ relayURLs: [URL], fallback: [URL] = []) -> [URL] {
        var seen = Set<String>()
        var ordered: [URL] = []

        for relayURL in relayURLs {
            guard let normalized = normalizedRelayURL(relayURL) else { continue }
            let normalizedKey = normalized.absoluteString
            guard seen.insert(normalizedKey).inserted else { continue }
            ordered.append(normalized)
        }

        if ordered.isEmpty, !fallback.isEmpty {
            return normalizedRelayURLs(fallback)
        }

        return ordered
    }

    nonisolated private static func normalizedNewsAuthorPubkeys(_ pubkeys: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for pubkey in pubkeys {
            let normalized = pubkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalized.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { continue }
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }

    nonisolated static func normalizedNewsAuthorPubkey(from rawIdentifier: String) -> String? {
        let normalized = normalizedIdentifier(rawIdentifier)
        guard !normalized.isEmpty else { return nil }

        if normalized.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil {
            return normalized
        }

        if normalized.hasPrefix("npub1") {
            return PublicKey(npub: normalized)?.hex.lowercased()
        }

        if normalized.hasPrefix("nprofile1") {
            let decoder = MentionMetadataDecoder()
            let metadata = try? decoder.decodedMetadata(from: normalized)
            return metadata?.pubkey?.lowercased()
        }

        return nil
    }

    nonisolated private static func normalizedNewsHashtags(_ hashtags: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for hashtag in hashtags {
            guard let normalized = normalizedNewsHashtag(hashtag) else { continue }
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }

    nonisolated static func normalizedNewsHashtag(_ rawHashtag: String) -> String? {
        let normalized = rawHashtag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .lowercased()
        guard !normalized.isEmpty else { return nil }
        return normalized
    }

    nonisolated static func normalizedCustomFeedName(_ rawName: String) -> String? {
        let normalized = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return normalized
    }

    nonisolated static func normalizedCustomFeedPhrase(_ rawPhrase: String) -> String? {
        let normalized = rawPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return normalized
    }

    nonisolated private static func normalizedCustomFeedPhrases(_ phrases: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for phrase in phrases {
            guard let normalized = normalizedCustomFeedPhrase(phrase) else { continue }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { continue }
            ordered.append(normalized)
        }

        return ordered
    }

    nonisolated private static func normalizedCustomFeed(_ feed: CustomFeedDefinition) throws -> CustomFeedDefinition {
        guard let normalizedName = normalizedCustomFeedName(feed.name) else {
            throw AppSettingsError.invalidCustomFeedName
        }

        let normalizedHashtags = normalizedNewsHashtags(feed.hashtags)
        let normalizedAuthors = normalizedNewsAuthorPubkeys(feed.authorPubkeys)
        let normalizedPhrases = normalizedCustomFeedPhrases(feed.phrases)

        guard !normalizedHashtags.isEmpty || !normalizedAuthors.isEmpty || !normalizedPhrases.isEmpty else {
            throw AppSettingsError.customFeedRequiresContent
        }

        let normalizedID = feed.id
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return CustomFeedDefinition(
            id: normalizedID.isEmpty ? UUID().uuidString.lowercased() : normalizedID,
            name: normalizedName,
            iconSystemName: CustomFeedIconCatalog.normalizedIcon(feed.iconSystemName),
            hashtags: normalizedHashtags,
            authorPubkeys: normalizedAuthors,
            phrases: normalizedPhrases
        )
    }

    nonisolated private static func normalizedCustomFeeds(_ feeds: [CustomFeedDefinition]) -> [CustomFeedDefinition] {
        var seen = Set<String>()
        var ordered: [CustomFeedDefinition] = []

        for feed in feeds {
            guard let normalizedFeed = try? normalizedCustomFeed(feed) else { continue }
            guard seen.insert(normalizedFeed.id).inserted else { continue }
            ordered.append(normalizedFeed)
        }

        return ordered
    }

    nonisolated private static func normalizedIdentifier(_ raw: String) -> String {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if trimmed.hasPrefix("nostr:") {
            return String(trimmed.dropFirst("nostr:".count))
        }

        return trimmed
    }
}
