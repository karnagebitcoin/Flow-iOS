import SwiftUI

struct AppThemeCapsuleTabStyle {
    let background: Color
    let border: Color
    let foreground: Color
    let selectedBackground: Color
    let selectedBorder: Color
    let selectedForeground: Color
}

struct AppThemeProfileActionStyle {
    let background: Color
    let border: Color
    let foreground: Color
    let primaryBackground: Color
    let primaryBorder: Color
    let primaryForeground: Color
    let bannerBackground: Color
    let bannerBorder: Color
    let bannerForeground: Color
}

struct AppThemePollStyle {
    let cardBackground: Color
    let cardBorder: Color
    let metadataForeground: Color
    let optionBackground: Color
    let optionResultBackground: Color
    let optionBorder: Color
    let optionSelectedBackground: Color
    let optionSelectedBorder: Color
    let optionWinningBackground: Color
    let optionWinningBorder: Color
    let imagePlaceholderBackground: Color
    let imagePlaceholderForeground: Color
    let neutralBadgeBackground: Color
    let neutralBadgeForeground: Color
    let refreshButtonBackground: Color
    let refreshButtonForeground: Color
}

struct AppThemePalette {
    private static let sakuraPinkTint = Color(red: 0.992, green: 0.647, blue: 0.835) // #FDA5D5
    private static let sakuraPrimary = Color(red: 1.0, green: 0.404, blue: 0.941)
    private static let sakuraBorder = Color(red: 1.0, green: 0.882, blue: 0.945) // #FFE1F1
    private static let sakuraSoftWhite = Color(red: 1.0, green: 0.985, blue: 0.992)
    private static let sakuraPetalWash = Color(red: 1.0, green: 0.947, blue: 0.979)

    private static func adaptiveSeparator(
        lightAlpha: CGFloat = 1,
        darkAlpha: CGFloat
    ) -> Color {
        Color(
            UIColor { traits in
                if traits.userInterfaceStyle == .dark {
                    return UIColor.white.withAlphaComponent(darkAlpha)
                }
                return UIColor.separator.withAlphaComponent(lightAlpha)
            }
        )
    }

    let background: Color
    let chromeBackground: Color
    let chromeBorder: Color
    let mutedForeground: Color
    let secondaryBackground: Color
    let quoteBackground: Color
    let groupedBackground: Color
    let secondaryGroupedBackground: Color
    let secondaryFill: Color
    let tertiaryFill: Color
    let separator: Color
    let linkPreviewBackground: Color
    let linkPreviewBorder: Color
    let articlePreviewBackgroundTop: Color
    let articlePreviewBackgroundBottom: Color
    let articlePreviewBorder: Color
    let capsuleTabStyle: AppThemeCapsuleTabStyle?
    let profileActionStyle: AppThemeProfileActionStyle?
    let pollStyle: AppThemePollStyle?

    static let system = AppThemePalette(
        background: Color(.systemBackground),
        chromeBackground: Color(.systemBackground),
        chromeBorder: adaptiveSeparator(darkAlpha: 0.08),
        mutedForeground: .secondary,
        secondaryBackground: Color(.secondarySystemBackground),
        quoteBackground: Color(.secondarySystemBackground),
        groupedBackground: Color(.systemGroupedBackground),
        secondaryGroupedBackground: Color(.secondarySystemGroupedBackground),
        secondaryFill: Color(.secondarySystemFill),
        tertiaryFill: Color(.tertiarySystemFill),
        separator: adaptiveSeparator(darkAlpha: 0.12),
        linkPreviewBackground: Color(.secondarySystemBackground),
        linkPreviewBorder: adaptiveSeparator(darkAlpha: 0.12),
        articlePreviewBackgroundTop: Color(.secondarySystemBackground),
        articlePreviewBackgroundBottom: Color(.systemBackground),
        articlePreviewBorder: adaptiveSeparator(lightAlpha: 0.24, darkAlpha: 0.14),
        capsuleTabStyle: nil,
        profileActionStyle: nil,
        pollStyle: nil
    )

    static let black = AppThemePalette(
        background: .black,
        chromeBackground: .black,
        chromeBorder: Color.white.opacity(0.06),
        mutedForeground: Color.white.opacity(0.58),
        secondaryBackground: Color(red: 0.11, green: 0.11, blue: 0.13),
        quoteBackground: Color(red: 0.11, green: 0.11, blue: 0.13),
        groupedBackground: .black,
        secondaryGroupedBackground: Color(red: 0.12, green: 0.12, blue: 0.14),
        secondaryFill: Color.white.opacity(0.10),
        tertiaryFill: Color.white.opacity(0.06),
        separator: Color.white.opacity(0.10),
        linkPreviewBackground: Color(red: 0.11, green: 0.11, blue: 0.13),
        linkPreviewBorder: Color.white.opacity(0.10),
        articlePreviewBackgroundTop: Color(red: 0.11, green: 0.11, blue: 0.13),
        articlePreviewBackgroundBottom: .black,
        articlePreviewBorder: Color.white.opacity(0.12),
        capsuleTabStyle: nil,
        profileActionStyle: nil,
        pollStyle: nil
    )

    static let white = AppThemePalette(
        background: Color.white,
        chromeBackground: Color.white,
        chromeBorder: Color.black.opacity(0.12),
        mutedForeground: Color.black.opacity(0.45),
        secondaryBackground: Color(red: 0.96, green: 0.96, blue: 0.97),
        quoteBackground: Color(red: 0.96, green: 0.96, blue: 0.97),
        groupedBackground: Color(red: 0.98, green: 0.98, blue: 0.985),
        secondaryGroupedBackground: Color(red: 0.955, green: 0.955, blue: 0.965),
        secondaryFill: Color.black.opacity(0.08),
        tertiaryFill: Color.black.opacity(0.05),
        separator: Color.black.opacity(0.12),
        linkPreviewBackground: Color(red: 0.96, green: 0.96, blue: 0.97),
        linkPreviewBorder: Color.black.opacity(0.12),
        articlePreviewBackgroundTop: Color(red: 0.96, green: 0.96, blue: 0.97),
        articlePreviewBackgroundBottom: .white,
        articlePreviewBorder: Color.black.opacity(0.12),
        capsuleTabStyle: nil,
        profileActionStyle: nil,
        pollStyle: nil
    )

    static let sakura = AppThemePalette(
        background: Color(red: 1.0, green: 0.994, blue: 0.997),
        chromeBackground: Color(red: 1.0, green: 0.996, blue: 0.998),
        chromeBorder: Self.sakuraBorder,
        mutedForeground: Self.sakuraPinkTint,
        secondaryBackground: Color(red: 0.998, green: 0.978, blue: 0.989),
        quoteBackground: .white,
        groupedBackground: Color(red: 0.999, green: 0.988, blue: 0.994),
        secondaryGroupedBackground: Color(red: 0.996, green: 0.972, blue: 0.985),
        secondaryFill: Color(red: 0.968, green: 0.760, blue: 0.880).opacity(0.12),
        tertiaryFill: Color(red: 0.986, green: 0.878, blue: 0.942).opacity(0.16),
        separator: Self.sakuraBorder,
        linkPreviewBackground: .white,
        linkPreviewBorder: Self.sakuraBorder,
        articlePreviewBackgroundTop: .white,
        articlePreviewBackgroundBottom: .white,
        articlePreviewBorder: Self.sakuraBorder,
        capsuleTabStyle: AppThemeCapsuleTabStyle(
            background: .white,
            border: Self.sakuraBorder,
            foreground: Self.sakuraPinkTint,
            selectedBackground: Self.sakuraPetalWash,
            selectedBorder: Self.sakuraBorder,
            selectedForeground: Self.sakuraPrimary
        ),
        profileActionStyle: AppThemeProfileActionStyle(
            background: .white,
            border: Self.sakuraBorder,
            foreground: Self.sakuraPinkTint,
            primaryBackground: Self.sakuraPetalWash,
            primaryBorder: Self.sakuraBorder,
            primaryForeground: Self.sakuraPrimary,
            bannerBackground: Color.white.opacity(0.90),
            bannerBorder: Self.sakuraBorder,
            bannerForeground: Self.sakuraPinkTint
        ),
        pollStyle: AppThemePollStyle(
            cardBackground: .white,
            cardBorder: Self.sakuraBorder,
            metadataForeground: Self.sakuraPinkTint,
            optionBackground: Self.sakuraSoftWhite,
            optionResultBackground: Self.sakuraPetalWash,
            optionBorder: Self.sakuraBorder,
            optionSelectedBackground: Self.sakuraPinkTint.opacity(0.16),
            optionSelectedBorder: Self.sakuraBorder,
            optionWinningBackground: Self.sakuraPrimary.opacity(0.12),
            optionWinningBorder: Self.sakuraBorder,
            imagePlaceholderBackground: Self.sakuraPetalWash,
            imagePlaceholderForeground: Self.sakuraPinkTint,
            neutralBadgeBackground: Self.sakuraPetalWash,
            neutralBadgeForeground: Self.sakuraPinkTint,
            refreshButtonBackground: Self.sakuraPetalWash,
            refreshButtonForeground: Self.sakuraPinkTint
        )
    )
}
