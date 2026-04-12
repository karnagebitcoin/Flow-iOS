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
    private static let draculaBackground = Color(red: 44.0 / 255.0, green: 45.0 / 255.0, blue: 60.0 / 255.0) // #2C2D3C
    private static let draculaFloating = Color(red: 0.204, green: 0.216, blue: 0.275) // #343746
    private static let draculaRaised = Color(red: 0.259, green: 0.278, blue: 0.353) // #44475A
    private static let draculaBorder = Color.white.opacity(0.07) // rgba(255, 255, 255, 0.07)
    private static let draculaChrome = Color(red: 43.0 / 255.0, green: 44.0 / 255.0, blue: 58.0 / 255.0) // #2B2C3A
    private static let draculaNavigation = Color(red: 32.0 / 255.0, green: 32.0 / 255.0, blue: 43.0 / 255.0) // #20202B
    private static let draculaDarker = Color(red: 30.0 / 255.0, green: 30.0 / 255.0, blue: 40.0 / 255.0) // #1E1E28
    private static let draculaForeground = Color(red: 0.973, green: 0.973, blue: 0.949) // #F8F8F2
    private static let draculaComment = Color(red: 0.537, green: 0.549, blue: 0.675) // #898CAC
    private static let draculaGreen = Color(red: 0.314, green: 0.980, blue: 0.482) // #50FA7B
    private static let draculaCyan = Color(red: 0.545, green: 0.914, blue: 0.992) // #8BE9FD
    private static let draculaPurple = Color(red: 0.773, green: 0.565, blue: 1.0) // #C590FF
    private static let draculaPink = Color(red: 1.0, green: 0.475, blue: 0.776) // #FF79C6
    private static let draculaOrange = Color(red: 1.0, green: 0.722, blue: 0.424) // #FFB86C
    private static let gamerBackground = Color(red: 0.035, green: 0.063, blue: 0.106) // #09101B
    private static let gamerChrome = Color(red: 0.055, green: 0.086, blue: 0.141) // #0E1624
    private static let gamerFloating = Color(red: 0.071, green: 0.114, blue: 0.188) // #121D30
    private static let gamerRaised = Color(red: 0.094, green: 0.153, blue: 0.263) // #182743
    private static let gamerBorder = Color(red: 0.329, green: 0.920, blue: 0.996).opacity(0.18)
    private static let gamerForeground = Color(red: 0.933, green: 0.957, blue: 0.988) // #EEF4FC
    private static let gamerMuted = Color(red: 0.558, green: 0.640, blue: 0.776) // #8EA3C6
    private static let gamerPurple = Color(red: 0.553, green: 0.408, blue: 1.0) // #8D68FF
    private static let gamerCyan = Color(red: 0.329, green: 0.920, blue: 0.996) // #54EBFE
    private static let gamerGreen = Color(red: 0.561, green: 1.0, blue: 0.369) // #8FFF5E
    private static let gamerPink = Color(red: 1.0, green: 0.412, blue: 0.741) // #FF69BD
    private static let gamerOrange = Color(red: 1.0, green: 0.694, blue: 0.333) // #FFB155
    private static let blackSheet = Color(red: 0.082, green: 0.082, blue: 0.082) // #151515
    private static let blackSheetCard = Color(red: 0.137, green: 0.137, blue: 0.137) // #232323
    private static let blackSheetCardBorder = Color(red: 0.235, green: 0.235, blue: 0.235) // #3C3C3C
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

    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(
            UIColor { traits in
                traits.userInterfaceStyle == .dark ? dark : light
            }
        )
    }

    let background: Color
    let chromeBackground: Color
    let chromeBorder: Color
    let mutedForeground: Color
    let foreground: Color
    let secondaryForeground: Color
    let tertiaryForeground: Color
    let inverseForeground: Color
    let placeholderForeground: Color
    let iconForeground: Color
    let iconMutedForeground: Color
    let secondaryBackground: Color
    let quoteBackground: Color
    let groupedBackground: Color
    let secondaryGroupedBackground: Color
    let navigationBackground: Color
    let navigationControlBackground: Color
    let sheetBackground: Color
    let sheetCardBackground: Color
    let sheetCardBorder: Color
    let sheetInsetBackground: Color
    let modalBackground: Color
    let elevatedBackground: Color
    let overlayBackground: Color
    let secondaryFill: Color
    let tertiaryFill: Color
    let separator: Color
    let successForeground: Color
    let warningForeground: Color
    let errorForeground: Color
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
        foreground: Color(UIColor.label),
        secondaryForeground: Color(UIColor.secondaryLabel),
        tertiaryForeground: Color(UIColor.tertiaryLabel),
        inverseForeground: adaptiveColor(light: .white, dark: .black),
        placeholderForeground: Color(UIColor.placeholderText),
        iconForeground: Color(UIColor.label),
        iconMutedForeground: Color(UIColor.secondaryLabel),
        secondaryBackground: Color(.secondarySystemBackground),
        quoteBackground: Color(.secondarySystemBackground),
        groupedBackground: Color(.systemGroupedBackground),
        secondaryGroupedBackground: Color(.secondarySystemGroupedBackground),
        navigationBackground: Color(.systemBackground),
        navigationControlBackground: Color(.secondarySystemBackground),
        sheetBackground: adaptiveColor(
            light: .systemGroupedBackground,
            dark: .systemBackground
        ),
        sheetCardBackground: adaptiveColor(
            light: .white,
            dark: .secondarySystemGroupedBackground
        ),
        sheetCardBorder: adaptiveSeparator(darkAlpha: 0.14),
        sheetInsetBackground: Color(.secondarySystemBackground),
        modalBackground: adaptiveColor(
            light: .white,
            dark: .secondarySystemGroupedBackground
        ),
        elevatedBackground: Color(.secondarySystemBackground),
        overlayBackground: adaptiveColor(
            light: UIColor.black.withAlphaComponent(0.18),
            dark: UIColor.black.withAlphaComponent(0.30)
        ),
        secondaryFill: Color(.secondarySystemFill),
        tertiaryFill: Color(.tertiarySystemFill),
        separator: adaptiveSeparator(darkAlpha: 0.14),
        successForeground: .green,
        warningForeground: .orange,
        errorForeground: .red,
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
        foreground: Color.white.opacity(0.95),
        secondaryForeground: Color.white.opacity(0.58),
        tertiaryForeground: Color.white.opacity(0.42),
        inverseForeground: .black,
        placeholderForeground: Color.white.opacity(0.28),
        iconForeground: Color.white.opacity(0.95),
        iconMutedForeground: Color.white.opacity(0.58),
        secondaryBackground: Color(red: 0.11, green: 0.11, blue: 0.13),
        quoteBackground: Color(red: 0.11, green: 0.11, blue: 0.13),
        groupedBackground: .black,
        secondaryGroupedBackground: Self.blackSheet,
        navigationBackground: .black,
        navigationControlBackground: Self.blackSheetCard,
        sheetBackground: Self.blackSheet,
        sheetCardBackground: Self.blackSheetCard,
        sheetCardBorder: Self.blackSheetCardBorder,
        sheetInsetBackground: Self.blackSheet,
        modalBackground: Self.blackSheet,
        elevatedBackground: Color(red: 0.11, green: 0.11, blue: 0.13),
        overlayBackground: Color.black.opacity(0.34),
        secondaryFill: Color.white.opacity(0.10),
        tertiaryFill: Color.white.opacity(0.06),
        separator: Color.white.opacity(0.13),
        successForeground: .green,
        warningForeground: .orange,
        errorForeground: .red,
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
        foreground: Self.whitePrimary,
        secondaryForeground: Self.whiteMuted,
        tertiaryForeground: Color.black.opacity(0.34),
        inverseForeground: .white,
        placeholderForeground: Color.black.opacity(0.28),
        iconForeground: Self.whitePrimary,
        iconMutedForeground: Self.whiteMuted,
        secondaryBackground: Color(red: 0.96, green: 0.96, blue: 0.97),
        quoteBackground: Color(red: 0.96, green: 0.96, blue: 0.97),
        groupedBackground: Color(red: 0.98, green: 0.98, blue: 0.985),
        secondaryGroupedBackground: Color(red: 0.955, green: 0.955, blue: 0.965),
        navigationBackground: .white,
        navigationControlBackground: Color(red: 0.96, green: 0.96, blue: 0.97),
        sheetBackground: Self.whiteRaised,
        sheetCardBackground: .white,
        sheetCardBorder: Self.whiteBorder,
        sheetInsetBackground: Self.whiteSurface,
        modalBackground: .white,
        elevatedBackground: Color(red: 0.96, green: 0.96, blue: 0.97),
        overlayBackground: Color.black.opacity(0.18),
        secondaryFill: Color.black.opacity(0.08),
        tertiaryFill: Color.black.opacity(0.05),
        separator: Color.black.opacity(0.10),
        successForeground: .green,
        warningForeground: .orange,
        errorForeground: .red,
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
        foreground: Color.black.opacity(0.84),
        secondaryForeground: Self.sakuraPinkTint,
        tertiaryForeground: Self.sakuraPinkTint.opacity(0.72),
        inverseForeground: .white,
        placeholderForeground: Self.sakuraPinkTint.opacity(0.46),
        iconForeground: Color.black.opacity(0.84),
        iconMutedForeground: Self.sakuraPinkTint,
        secondaryBackground: Color(red: 0.998, green: 0.978, blue: 0.989),
        quoteBackground: .white,
        groupedBackground: Color(red: 0.999, green: 0.988, blue: 0.994),
        secondaryGroupedBackground: Color(red: 0.996, green: 0.972, blue: 0.985),
        navigationBackground: Color(red: 1.0, green: 0.996, blue: 0.998),
        navigationControlBackground: Color.white.opacity(0.88),
        sheetBackground: Color(red: 0.996, green: 0.972, blue: 0.985),
        sheetCardBackground: .white,
        sheetCardBorder: Self.sakuraBorder,
        sheetInsetBackground: Color(red: 0.998, green: 0.978, blue: 0.989),
        modalBackground: Color.white.opacity(0.96),
        elevatedBackground: Color(red: 0.998, green: 0.978, blue: 0.989),
        overlayBackground: Color.black.opacity(0.16),
        secondaryFill: Color(red: 0.968, green: 0.760, blue: 0.880).opacity(0.12),
        tertiaryFill: Color(red: 0.986, green: 0.878, blue: 0.942).opacity(0.16),
        separator: Self.sakuraBorder,
        successForeground: .green,
        warningForeground: .orange,
        errorForeground: .red,
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
        foreground: Self.draculaForeground,
        secondaryForeground: Self.draculaComment,
        tertiaryForeground: Self.draculaComment.opacity(0.78),
        inverseForeground: Self.draculaDarker,
        placeholderForeground: Self.draculaComment.opacity(0.66),
        iconForeground: Self.draculaForeground,
        iconMutedForeground: Self.draculaComment,
        secondaryBackground: Self.draculaFloating,
        quoteBackground: Self.draculaFloating,
        groupedBackground: Self.draculaDarker,
        secondaryGroupedBackground: Self.draculaChrome,
        navigationBackground: Self.draculaNavigation,
        navigationControlBackground: Self.draculaFloating,
        sheetBackground: Self.draculaBackground,
        sheetCardBackground: Self.draculaFloating,
        sheetCardBorder: Self.draculaBorder,
        sheetInsetBackground: Self.draculaChrome,
        modalBackground: Self.draculaFloating,
        elevatedBackground: Self.draculaRaised.opacity(0.86),
        overlayBackground: Self.draculaDarker.opacity(0.84),
        secondaryFill: Self.draculaRaised.opacity(0.86),
        tertiaryFill: Self.draculaComment.opacity(0.28),
        separator: Self.draculaBorder,
        successForeground: Self.draculaGreen,
        warningForeground: Self.draculaOrange,
        errorForeground: Self.draculaPink,
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

    static let gamer = AppThemePalette(
        background: Self.gamerBackground,
        chromeBackground: Self.gamerChrome,
        chromeBorder: Self.gamerBorder,
        mutedForeground: Self.gamerMuted,
        foreground: Self.gamerForeground,
        secondaryForeground: Self.gamerMuted,
        tertiaryForeground: Self.gamerMuted.opacity(0.78),
        inverseForeground: Self.gamerBackground,
        placeholderForeground: Self.gamerMuted.opacity(0.60),
        iconForeground: Self.gamerForeground,
        iconMutedForeground: Self.gamerMuted,
        secondaryBackground: Self.gamerFloating,
        quoteBackground: Self.gamerFloating,
        groupedBackground: Color(red: 0.024, green: 0.043, blue: 0.075),
        secondaryGroupedBackground: Self.gamerChrome,
        navigationBackground: Self.gamerBackground,
        navigationControlBackground: Self.gamerFloating,
        sheetBackground: Self.gamerBackground,
        sheetCardBackground: Self.gamerFloating,
        sheetCardBorder: Self.gamerBorder,
        sheetInsetBackground: Self.gamerChrome,
        modalBackground: Self.gamerFloating,
        elevatedBackground: Self.gamerRaised.opacity(0.90),
        overlayBackground: Color(red: 0.020, green: 0.031, blue: 0.055).opacity(0.88),
        secondaryFill: Self.gamerRaised.opacity(0.82),
        tertiaryFill: Self.gamerPurple.opacity(0.20),
        separator: Self.gamerBorder,
        successForeground: Self.gamerGreen,
        warningForeground: Self.gamerOrange,
        errorForeground: Self.gamerPink,
        linkPreviewBackground: Self.gamerFloating,
        linkPreviewBorder: Self.gamerBorder,
        articlePreviewBackgroundTop: Self.gamerFloating,
        articlePreviewBackgroundBottom: Self.gamerChrome,
        articlePreviewBorder: Self.gamerBorder,
        capsuleTabStyle: AppThemeCapsuleTabStyle(
            background: Self.gamerChrome,
            border: Self.gamerBorder,
            foreground: Self.gamerMuted,
            selectedBackground: Self.gamerPurple.opacity(0.18),
            selectedBorder: Self.gamerCyan.opacity(0.56),
            selectedForeground: Self.gamerForeground
        ),
        profileActionStyle: AppThemeProfileActionStyle(
            background: Self.gamerChrome,
            border: Self.gamerBorder,
            foreground: Self.gamerForeground.opacity(0.82),
            primaryBackground: Self.gamerPurple.opacity(0.22),
            primaryBorder: Self.gamerCyan.opacity(0.48),
            primaryForeground: Self.gamerForeground,
            bannerBackground: Self.gamerFloating.opacity(0.94),
            bannerBorder: Self.gamerBorder,
            bannerForeground: Self.gamerForeground
        ),
        pollStyle: AppThemePollStyle(
            cardBackground: Self.gamerFloating,
            cardBorder: Self.gamerBorder,
            metadataForeground: Self.gamerMuted,
            optionBackground: Self.gamerChrome,
            optionResultBackground: Self.gamerRaised.opacity(0.72),
            optionBorder: Self.gamerBorder.opacity(0.92),
            optionSelectedBackground: Self.gamerPurple.opacity(0.18),
            optionSelectedBorder: Self.gamerCyan.opacity(0.56),
            optionWinningBackground: Self.gamerGreen.opacity(0.16),
            optionWinningBorder: Self.gamerGreen.opacity(0.56),
            imagePlaceholderBackground: Self.gamerChrome,
            imagePlaceholderForeground: Self.gamerMuted,
            neutralBadgeBackground: Self.gamerRaised.opacity(0.86),
            neutralBadgeForeground: Self.gamerForeground.opacity(0.84),
            refreshButtonBackground: Self.gamerCyan.opacity(0.18),
            refreshButtonForeground: Self.gamerCyan
        )
    )
}
