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
    private static let draculaBackground = Color(red: 0.157, green: 0.165, blue: 0.212) // #282A36
    private static let draculaFloating = Color(red: 0.204, green: 0.216, blue: 0.275) // #343746
    private static let draculaRaised = Color(red: 0.259, green: 0.278, blue: 0.353) // #44475A
    private static let draculaBorder = Color.white.opacity(0.07) // rgba(255, 255, 255, 0.07)
    private static let draculaChrome = Color(red: 0.129, green: 0.133, blue: 0.173) // #21222C
    private static let draculaDarker = Color(red: 0.098, green: 0.102, blue: 0.129) // #191A21
    private static let draculaForeground = Color(red: 0.973, green: 0.973, blue: 0.949) // #F8F8F2
    private static let draculaComment = Color(red: 0.537, green: 0.549, blue: 0.675) // #898CAC
    private static let draculaGreen = Color(red: 0.314, green: 0.980, blue: 0.482) // #50FA7B
    private static let draculaCyan = Color(red: 0.545, green: 0.914, blue: 0.992) // #8BE9FD
    private static let draculaPurple = Color(red: 0.773, green: 0.565, blue: 1.0) // #C590FF
    private static let draculaPink = Color(red: 1.0, green: 0.475, blue: 0.776) // #FF79C6
    private static let draculaOrange = Color(red: 1.0, green: 0.722, blue: 0.424) // #FFB86C
    private static let whiteSurface = Color(red: 0.965, green: 0.965, blue: 0.972)
    private static let whiteRaised = Color(red: 0.945, green: 0.945, blue: 0.955)
    private static let whiteBorder = Color.black.opacity(0.08)
    private static let whiteStrongBorder = Color.black.opacity(0.14)
    private static let whiteMuted = Color.black.opacity(0.58)
    private static let whitePrimary = Color.black.opacity(0.88)

    private static func adaptiveSeparator(
        lightMultiplier: CGFloat = 1,
        darkAlpha: CGFloat
    ) -> Color {
        Color(
            UIColor { traits in
                let resolvedSeparator = UIColor.separator.resolvedColor(with: traits)
                if traits.userInterfaceStyle == .dark {
                    return UIColor.white.withAlphaComponent(darkAlpha)
                }
                let scaledAlpha = min(max(resolvedSeparator.cgColor.alpha * lightMultiplier, 0), 1)
                return resolvedSeparator.withAlphaComponent(scaledAlpha)
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
        chromeBorder: adaptiveSeparator(darkAlpha: 0.10),
        mutedForeground: .secondary,
        secondaryBackground: Color(.secondarySystemBackground),
        quoteBackground: Color(.secondarySystemBackground),
        groupedBackground: Color(.systemGroupedBackground),
        secondaryGroupedBackground: Color(.secondarySystemGroupedBackground),
        secondaryFill: Color(.secondarySystemFill),
        tertiaryFill: Color(.tertiarySystemFill),
        separator: adaptiveSeparator(darkAlpha: 0.14),
        linkPreviewBackground: Color(.secondarySystemBackground),
        linkPreviewBorder: adaptiveSeparator(darkAlpha: 0.14),
        articlePreviewBackgroundTop: Color(.secondarySystemBackground),
        articlePreviewBackgroundBottom: Color(.systemBackground),
        articlePreviewBorder: adaptiveSeparator(lightMultiplier: 0.24, darkAlpha: 0.16),
        capsuleTabStyle: nil,
        profileActionStyle: nil,
        pollStyle: nil
    )

    static let black = AppThemePalette(
        background: .black,
        chromeBackground: .black,
        chromeBorder: Color.white.opacity(0.08),
        mutedForeground: Color.white.opacity(0.58),
        secondaryBackground: Color(red: 0.11, green: 0.11, blue: 0.13),
        quoteBackground: Color(red: 0.11, green: 0.11, blue: 0.13),
        groupedBackground: .black,
        secondaryGroupedBackground: Color(red: 0.12, green: 0.12, blue: 0.14),
        secondaryFill: Color.white.opacity(0.10),
        tertiaryFill: Color.white.opacity(0.06),
        separator: Color.white.opacity(0.13),
        linkPreviewBackground: Color(red: 0.11, green: 0.11, blue: 0.13),
        linkPreviewBorder: Color.white.opacity(0.13),
        articlePreviewBackgroundTop: Color(red: 0.11, green: 0.11, blue: 0.13),
        articlePreviewBackgroundBottom: .black,
        articlePreviewBorder: Color.white.opacity(0.15),
        capsuleTabStyle: nil,
        profileActionStyle: nil,
        pollStyle: nil
    )

    static let white = AppThemePalette(
        background: Color.white,
        chromeBackground: Color.white,
        chromeBorder: Color.black.opacity(0.10),
        mutedForeground: Color.black.opacity(0.45),
        secondaryBackground: Color(red: 0.96, green: 0.96, blue: 0.97),
        quoteBackground: Color(red: 0.96, green: 0.96, blue: 0.97),
        groupedBackground: Color(red: 0.98, green: 0.98, blue: 0.985),
        secondaryGroupedBackground: Color(red: 0.955, green: 0.955, blue: 0.965),
        secondaryFill: Color.black.opacity(0.08),
        tertiaryFill: Color.black.opacity(0.05),
        separator: Color.black.opacity(0.10),
        linkPreviewBackground: Color(red: 0.96, green: 0.96, blue: 0.97),
        linkPreviewBorder: Color.black.opacity(0.10),
        articlePreviewBackgroundTop: Color(red: 0.96, green: 0.96, blue: 0.97),
        articlePreviewBackgroundBottom: .white,
        articlePreviewBorder: Color.black.opacity(0.10),
        capsuleTabStyle: AppThemeCapsuleTabStyle(
            background: Self.whiteSurface,
            border: Self.whiteBorder,
            foreground: Self.whiteMuted,
            selectedBackground: .white,
            selectedBorder: Self.whiteStrongBorder,
            selectedForeground: Self.whitePrimary
        ),
        profileActionStyle: AppThemeProfileActionStyle(
            background: Self.whiteSurface,
            border: Self.whiteBorder,
            foreground: Self.whitePrimary,
            primaryBackground: .white,
            primaryBorder: Self.whiteStrongBorder,
            primaryForeground: .black,
            bannerBackground: Color.white.opacity(0.96),
            bannerBorder: Self.whiteBorder,
            bannerForeground: Self.whitePrimary
        ),
        pollStyle: AppThemePollStyle(
            cardBackground: .white,
            cardBorder: Self.whiteBorder,
            metadataForeground: Self.whiteMuted,
            optionBackground: Self.whiteSurface,
            optionResultBackground: Self.whiteRaised,
            optionBorder: Color.black.opacity(0.07),
            optionSelectedBackground: Color.black.opacity(0.06),
            optionSelectedBorder: Color.black.opacity(0.12),
            optionWinningBackground: Color.black.opacity(0.08),
            optionWinningBorder: Self.whiteStrongBorder,
            imagePlaceholderBackground: Self.whiteRaised,
            imagePlaceholderForeground: Self.whiteMuted,
            neutralBadgeBackground: Self.whiteRaised,
            neutralBadgeForeground: Self.whiteMuted,
            refreshButtonBackground: Self.whiteSurface,
            refreshButtonForeground: Self.whitePrimary
        )
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

    static let dracula = AppThemePalette(
        background: Self.draculaBackground,
        chromeBackground: Self.draculaChrome,
        chromeBorder: Self.draculaBorder,
        mutedForeground: Self.draculaComment,
        secondaryBackground: Self.draculaFloating,
        quoteBackground: Self.draculaFloating,
        groupedBackground: Self.draculaDarker,
        secondaryGroupedBackground: Self.draculaChrome,
        secondaryFill: Self.draculaRaised.opacity(0.86),
        tertiaryFill: Self.draculaComment.opacity(0.28),
        separator: Self.draculaBorder,
        linkPreviewBackground: Self.draculaFloating,
        linkPreviewBorder: Self.draculaBorder,
        articlePreviewBackgroundTop: Self.draculaFloating,
        articlePreviewBackgroundBottom: Self.draculaChrome,
        articlePreviewBorder: Self.draculaBorder,
        capsuleTabStyle: AppThemeCapsuleTabStyle(
            background: Self.draculaChrome,
            border: Self.draculaBorder,
            foreground: Self.draculaComment,
            selectedBackground: Self.draculaPurple.opacity(0.20),
            selectedBorder: Self.draculaPurple.opacity(0.54),
            selectedForeground: Self.draculaForeground
        ),
        profileActionStyle: AppThemeProfileActionStyle(
            background: Self.draculaChrome,
            border: Self.draculaBorder,
            foreground: Self.draculaForeground.opacity(0.82),
            primaryBackground: Self.draculaPurple.opacity(0.22),
            primaryBorder: Self.draculaPurple.opacity(0.56),
            primaryForeground: Self.draculaForeground,
            bannerBackground: Self.draculaFloating.opacity(0.94),
            bannerBorder: Self.draculaBorder,
            bannerForeground: Self.draculaForeground
        ),
        pollStyle: AppThemePollStyle(
            cardBackground: Self.draculaFloating,
            cardBorder: Self.draculaBorder,
            metadataForeground: Self.draculaComment,
            optionBackground: Self.draculaChrome,
            optionResultBackground: Self.draculaRaised.opacity(0.72),
            optionBorder: Self.draculaBorder,
            optionSelectedBackground: Self.draculaPurple.opacity(0.18),
            optionSelectedBorder: Self.draculaPurple.opacity(0.56),
            optionWinningBackground: Self.draculaPurple.opacity(0.22),
            optionWinningBorder: Self.draculaPurple.opacity(0.60),
            imagePlaceholderBackground: Self.draculaChrome,
            imagePlaceholderForeground: Self.draculaComment,
            neutralBadgeBackground: Self.draculaRaised.opacity(0.86),
            neutralBadgeForeground: Self.draculaForeground.opacity(0.82),
            refreshButtonBackground: Self.draculaPink.opacity(0.18),
            refreshButtonForeground: Self.draculaPink
        )
    )
}
