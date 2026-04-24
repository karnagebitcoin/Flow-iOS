import XCTest
import SwiftUI
import UIKit
@testable import Flow

final class AppThemeOptionTests: XCTestCase {
    @MainActor
    func testSakuraThemeIsFreeAndUsesLightMode() {
        XCTAssertTrue(AppThemeOption.sakura.isEnabled)
        XCTAssertEqual(AppThemeOption.sakura.preferredColorScheme, .light)
        XCTAssertNil(AppThemeOption.sakura.fixedPrimaryColor)
        XCTAssertNil(AppThemeOption.sakura.fixedPrimaryGradient)
        XCTAssertEqual(AppThemeOption.sakura.qrShareBackgroundResourceName, "sakura-share-bg.json")
        assertColor(
            AppThemeOption.sakura.palette.mutedForeground,
            matches: UIColor(red: 0.992, green: 0.647, blue: 0.835, alpha: 1)
        )
        assertColor(AppThemeOption.sakura.palette.quoteBackground, matches: .white)
        assertColor(
            AppThemeOption.sakura.palette.separator,
            matches: UIColor(red: 1.0, green: 0.882, blue: 0.945, alpha: 1)
        )
        assertColor(AppThemeOption.sakura.palette.linkPreviewBackground, matches: .white)
        assertColor(
            AppThemeOption.sakura.palette.chromeBorder,
            matches: UIColor(red: 1.0, green: 0.882, blue: 0.945, alpha: 1)
        )
        assertColor(
            AppThemeOption.sakura.palette.linkPreviewBorder,
            matches: UIColor(red: 1.0, green: 0.882, blue: 0.945, alpha: 1)
        )
        assertColor(AppThemeOption.sakura.palette.articlePreviewBackgroundTop, matches: .white)
        assertColor(AppThemeOption.sakura.palette.articlePreviewBackgroundBottom, matches: .white)
        assertColor(
            AppThemeOption.sakura.palette.articlePreviewBorder,
            matches: UIColor(red: 1.0, green: 0.882, blue: 0.945, alpha: 1)
        )
        XCTAssertNotNil(AppThemeOption.sakura.palette.capsuleTabStyle)
        XCTAssertNotNil(AppThemeOption.sakura.palette.profileActionStyle)
        XCTAssertNotNil(AppThemeOption.sakura.palette.pollStyle)
    }

    @MainActor
    func testDraculaThemeIsFreeAndUsesDarkMode() {
        XCTAssertTrue(AppThemeOption.dracula.isEnabled)
        XCTAssertEqual(AppThemeOption.dracula.preferredColorScheme, .dark)
        XCTAssertNil(AppThemeOption.dracula.fixedPrimaryColor)
        XCTAssertNil(AppThemeOption.dracula.fixedPrimaryGradient)
        XCTAssertNil(AppThemeOption.dracula.qrShareBackgroundResourceName)
        assertColor(
            AppThemeOption.dracula.palette.background,
            matches: UIColor(red: 44.0 / 255.0, green: 45.0 / 255.0, blue: 60.0 / 255.0, alpha: 1)
        )
        assertColor(
            AppThemeOption.dracula.palette.chromeBackground,
            matches: UIColor(red: 43.0 / 255.0, green: 44.0 / 255.0, blue: 58.0 / 255.0, alpha: 1)
        )
        assertColor(
            AppThemeOption.dracula.palette.secondaryBackground,
            matches: UIColor(red: 0.204, green: 0.216, blue: 0.275, alpha: 1)
        )
        assertColor(
            AppThemeOption.dracula.palette.navigationBackground,
            matches: UIColor(red: 32.0 / 255.0, green: 32.0 / 255.0, blue: 43.0 / 255.0, alpha: 1)
        )
        assertColor(
            AppThemeOption.dracula.palette.sheetBackground,
            matches: UIColor(red: 44.0 / 255.0, green: 45.0 / 255.0, blue: 60.0 / 255.0, alpha: 1)
        )
        assertColor(
            AppThemeOption.dracula.palette.sheetCardBackground,
            matches: UIColor(red: 0.204, green: 0.216, blue: 0.275, alpha: 1)
        )
        assertColor(
            AppThemeOption.dracula.palette.chromeBorder,
            matches: UIColor(white: 1, alpha: 0.07)
        )
        assertColor(
            AppThemeOption.dracula.palette.separator,
            matches: UIColor(white: 1, alpha: 0.07)
        )
        assertColor(
            AppThemeOption.dracula.palette.mutedForeground,
            matches: UIColor(red: 0.537, green: 0.549, blue: 0.675, alpha: 1)
        )
        XCTAssertNotNil(AppThemeOption.dracula.palette.capsuleTabStyle)
        XCTAssertNotNil(AppThemeOption.dracula.palette.profileActionStyle)
        XCTAssertNotNil(AppThemeOption.dracula.palette.pollStyle)
        assertColor(
            AppThemeOption.dracula.palette.pollStyle!.optionWinningBackground,
            matches: UIColor(red: 0.773, green: 0.565, blue: 1.0, alpha: 0.22)
        )
        assertColor(
            AppThemeOption.dracula.palette.pollStyle!.optionWinningBorder,
            matches: UIColor(red: 0.773, green: 0.565, blue: 1.0, alpha: 0.60)
        )
    }

    @MainActor
    func testGamerThemeIsFreeAndUsesDarkMode() {
        XCTAssertTrue(AppThemeOption.gamer.isEnabled)
        XCTAssertEqual(AppThemeOption.gamer.preferredColorScheme, .dark)
        XCTAssertNil(AppThemeOption.gamer.fixedPrimaryColor)
        XCTAssertNil(AppThemeOption.gamer.fixedPrimaryGradient)
        XCTAssertNil(AppThemeOption.gamer.qrShareBackgroundResourceName)
        assertColor(
            AppThemeOption.gamer.palette.background,
            matches: UIColor(red: 0.035, green: 0.063, blue: 0.106, alpha: 1)
        )
        assertColor(
            AppThemeOption.gamer.palette.chromeBackground,
            matches: UIColor(red: 0.055, green: 0.086, blue: 0.141, alpha: 1)
        )
        assertColor(
            AppThemeOption.gamer.palette.secondaryBackground,
            matches: UIColor(red: 0.071, green: 0.114, blue: 0.188, alpha: 1)
        )
        assertColor(
            AppThemeOption.gamer.palette.mutedForeground,
            matches: UIColor(red: 0.592, green: 0.735, blue: 0.976, alpha: 1)
        )
        XCTAssertNotNil(AppThemeOption.gamer.palette.capsuleTabStyle)
        XCTAssertNotNil(AppThemeOption.gamer.palette.profileActionStyle)
        XCTAssertNotNil(AppThemeOption.gamer.palette.pollStyle)
        assertColor(
            AppThemeOption.gamer.palette.pollStyle!.optionWinningBorder,
            matches: UIColor(red: 0.561, green: 1.0, blue: 0.369, alpha: 0.56)
        )
    }

    @MainActor
    func testSkyThemeIsFreeAndUsesMinimalLightPalette() {
        XCTAssertTrue(AppThemeOption.holographicLight.isEnabled)
        XCTAssertEqual(AppThemeOption.holographicLight.preferredColorScheme, .light)
        XCTAssertEqual(AppThemeOption.holographicLight.title, "Sky")
        XCTAssertNil(AppThemeOption.holographicLight.fixedPrimaryColor)
        XCTAssertNil(AppThemeOption.holographicLight.fixedPrimaryGradient)
        XCTAssertNil(AppThemeOption.holographicLight.qrShareBackgroundResourceName)
        assertColor(
            AppThemeOption.holographicLight.palette.background,
            matches: UIColor(red: 0.992, green: 0.996, blue: 1.0, alpha: 1)
        )
        assertColor(
            AppThemeOption.holographicLight.palette.chromeBackground,
            matches: UIColor(red: 0.988, green: 0.994, blue: 1.0, alpha: 1)
        )
        assertColor(
            AppThemeOption.holographicLight.palette.secondaryBackground,
            matches: UIColor(red: 0.957, green: 0.982, blue: 1.0, alpha: 1)
        )
        assertColor(
            AppThemeOption.holographicLight.palette.linkPreviewBorder,
            matches: UIColor(red: 0.640, green: 0.875, blue: 1.0, alpha: 0.36)
        )
        XCTAssertNotNil(AppThemeOption.holographicLight.palette.capsuleTabStyle)
        XCTAssertNotNil(AppThemeOption.holographicLight.palette.profileActionStyle)
        XCTAssertNotNil(AppThemeOption.holographicLight.palette.pollStyle)
        XCTAssertNil(AppThemeOption.holographicLight.palette.feedCardStyle)
        assertColor(
            AppThemeOption.holographicLight.palette.profileActionStyle!.primaryForeground,
            matches: UIColor(red: 0.235, green: 0.612, blue: 1.0, alpha: 1)
        )
    }

    @MainActor
    func testLegacyHolographicDarkIsDisabledAndNormalizesToDark() {
        XCTAssertFalse(AppThemeOption.holographicDark.isEnabled)
        XCTAssertEqual(AppThemeOption.holographicDark.normalizedSelection, .dark)
        XCTAssertEqual(AppThemeOption.holographicDark.preferredColorScheme, .dark)
        XCTAssertEqual(AppThemeOption.holographicDark.title, "Dark")
        XCTAssertNil(AppThemeOption.holographicDark.fixedPrimaryColor)
        XCTAssertNil(AppThemeOption.holographicDark.fixedPrimaryGradient)
        XCTAssertNil(AppThemeOption.holographicDark.qrShareBackgroundResourceName)
    }

    @MainActor
    func testThemeIconAccentMatchesReactionChromeForVisibleThemes() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        for theme in AppThemeOption.appearanceOptions {
            settings.beginThemePreview(theme)

            assertColor(
                settings.themeIconAccentColor,
                matches: UIColor(settings.themePalette.mutedForeground),
                file: #filePath,
                line: #line
            )
        }
    }

    @MainActor
    func testButtonGradientOptionControlsProminentButtonsAcrossThemes() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        XCTAssertFalse(settings.usesPrimaryGradientForProminentButtons)
        XCTAssertNil(settings.activeButtonGradientOption)

        settings.theme = .dark
        settings.buttonGradientOption = .softHolographicSheen
        XCTAssertTrue(settings.usesPrimaryGradientForProminentButtons)
        XCTAssertEqual(settings.activeButtonGradientOption, .softHolographicSheen)
        XCTAssertNil(settings.activeHolographicGradientOption)

        settings.theme = .sakura
        XCTAssertTrue(settings.usesPrimaryGradientForProminentButtons)
        XCTAssertEqual(settings.activeButtonGradientOption, .softHolographicSheen)
        XCTAssertNil(settings.activeHolographicGradientOption)

        settings.theme = .holographicLight
        XCTAssertEqual(settings.activeHolographicGradientOption, .softHolographicSheen)

        settings.buttonGradientOption = nil
        XCTAssertFalse(settings.usesPrimaryGradientForProminentButtons)
        XCTAssertEqual(settings.activeHolographicGradientOption, .softHolographicSheen)
    }

    @MainActor
    func testButtonGradientSelectionPersistsAcrossStoreReload() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let pubkey = String(repeating: "b", count: 64)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        settings.configure(accountPubkey: pubkey)
        settings.theme = .gamer
        settings.primaryColor = .red
        settings.buttonGradientOption = .radialHolographicGlow

        let reloaded = AppSettingsStore(defaults: defaults, authStore: authStore)
        reloaded.configure(accountPubkey: pubkey)

        XCTAssertEqual(reloaded.theme, .gamer)
        XCTAssertEqual(reloaded.buttonGradientOption, .radialHolographicGlow)
        XCTAssertNil(reloaded.generatedButtonGradient)
        XCTAssertEqual(reloaded.activeButtonGradientOption, .radialHolographicGlow)
    }

    @MainActor
    func testGeneratedButtonGradientPersistsAndOverridesPresetGradient() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let pubkey = String(repeating: "e", count: 64)
        let generated = GeneratedButtonGradient(colors: [
            Color(red: 0.10, green: 0.20, blue: 0.90),
            Color(red: 0.90, green: 0.15, blue: 0.50),
            Color(red: 0.20, green: 0.85, blue: 0.70)
        ])
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        settings.configure(accountPubkey: pubkey)
        settings.buttonGradientOption = .softHolographicSheen
        settings.applyGeneratedButtonGradient(generated)

        let reloaded = AppSettingsStore(defaults: defaults, authStore: authStore)
        reloaded.configure(accountPubkey: pubkey)

        XCTAssertNil(reloaded.buttonGradientOption)
        XCTAssertEqual(reloaded.generatedButtonGradient, generated)
        XCTAssertTrue(reloaded.usesPrimaryGradientForProminentButtons)
        XCTAssertNil(reloaded.activeButtonGradientOption)
        XCTAssertEqual(reloaded.activeGeneratedButtonGradient, generated)
    }

    @MainActor
    func testGeneratedButtonGradientFactoryUsesTwoOrThreeColors() {
        for _ in 0..<20 {
            let gradient = GeneratedButtonGradient.random()
            XCTAssertTrue((2...3).contains(gradient.gradientColors.count))
        }
    }

    @MainActor
    func testButtonTextColorPersistsAcrossStoreReload() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let pubkey = String(repeating: "f", count: 64)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        settings.configure(accountPubkey: pubkey)
        settings.buttonTextColor = Color(red: 0.05, green: 0.10, blue: 0.15)

        let reloaded = AppSettingsStore(defaults: defaults, authStore: authStore)
        reloaded.configure(accountPubkey: pubkey)

        assertColor(
            reloaded.buttonTextColor,
            matches: UIColor(red: 0.05, green: 0.10, blue: 0.15, alpha: 1)
        )
    }

    @MainActor
    func testLegacyHolographicGradientSettingsMigrateToSingleButtonGradient() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let pubkey = String(repeating: "c", count: 64)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        settings.configure(accountPubkey: pubkey)
        settings.theme = .holographicLight
        settings.holographicLightGradientOption = .strongRainbowFoil

        XCTAssertEqual(settings.activeHolographicGradientOption, .strongRainbowFoil)

        let reloaded = AppSettingsStore(defaults: defaults, authStore: authStore)
        reloaded.configure(accountPubkey: pubkey)

        XCTAssertEqual(reloaded.buttonGradientOption, .strongRainbowFoil)
        XCTAssertEqual(reloaded.holographicDarkGradientOption, .strongRainbowFoil)
    }

    @MainActor
    func testHolographicSpotlightOnlyAppearsOnSkyScreens() {
        XCTAssertTrue(AppThemeBackgroundSpotlight.feed.isVisible(for: .holographicLight))
        XCTAssertTrue(AppThemeBackgroundSpotlight.profile.isVisible(for: .holographicLight))
        XCTAssertFalse(AppThemeBackgroundSpotlight.feed.isVisible(for: .holographicDark))
        XCTAssertFalse(AppThemeBackgroundSpotlight.none.isVisible(for: .holographicDark))
        XCTAssertFalse(AppThemeBackgroundSpotlight.feed.isVisible(for: .sakura))
        XCTAssertFalse(AppThemeBackgroundSpotlight.profile.isVisible(for: .gamer))
    }

    func testHolographicSpotlightLayoutStaysBottomAnchored() {
        let size = CGSize(width: 390, height: 844)
        let feedLayout = AppThemeBackgroundSpotlightLayout(placement: .feed, size: size)
        let profileLayout = AppThemeBackgroundSpotlightLayout(placement: .profile, size: size)

        XCTAssertGreaterThan(feedLayout.primaryOffset.height, 0)
        XCTAssertGreaterThan(feedLayout.secondaryOffset.height, 0)
        XCTAssertGreaterThan(profileLayout.primaryOffset.height, 0)
        XCTAssertGreaterThan(profileLayout.secondaryOffset.height, 0)
    }

    func testHolographicSpotlightFadesBeforeFrameEdges() {
        let layout = AppThemeBackgroundSpotlightLayout(
            placement: .feed,
            size: CGSize(width: 390, height: 844)
        )

        XCTAssertLessThan(layout.primaryRadius, min(layout.primarySize.width, layout.primarySize.height) / 2)
        XCTAssertLessThan(layout.secondaryRadius, min(layout.secondarySize.width, layout.secondarySize.height) / 2)
    }

    func testDarkGradientTreatmentUsesMagentaPurpleAccentColors() {
        let colors = AppThemeBackgroundSpotlightColors(theme: .dark)

        assertColor(
            colors.primaryStart,
            matches: UIColor(red: 0x8B / 255.0, green: 0x7D / 255.0, blue: 0xFF / 255.0, alpha: 1)
        )
        assertColor(
            colors.secondaryEnd,
            matches: UIColor(red: 0x8B / 255.0, green: 0x7D / 255.0, blue: 0xFF / 255.0, alpha: 1)
        )
    }

    @MainActor
    func testAppearanceThemesExposeCurrentFreeThemeList() {
        XCTAssertTrue(AppThemeOption.light.isEnabled)
        XCTAssertTrue(AppThemeOption.dark.isEnabled)
        XCTAssertTrue(AppThemeOption.black.isEnabled)
        XCTAssertEqual(
            AppThemeOption.appearanceOptions,
            [.light, .dark, .black, .system, .sakura, .dracula, .gamer, .holographicLight]
        )
        XCTAssertFalse(AppThemeOption.appearanceOptions.contains(.white))
        XCTAssertFalse(AppThemeOption.appearanceOptions.contains(.holographicDark))
    }

    @MainActor
    func testThemePreviewOverridesActiveTheme() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        settings.theme = .system
        settings.beginThemePreview(.sakura)

        XCTAssertEqual(settings.activeTheme, .sakura)
        XCTAssertEqual(settings.preferredColorScheme, .light)
        XCTAssertEqual(settings.previewTheme, .sakura)
    }

    @MainActor
    func testLegacyWhiteThemeSelectionNormalizesToLight() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        settings.theme = .white

        XCTAssertEqual(settings.theme, .light)
        XCTAssertEqual(settings.activeTheme, .light)
        XCTAssertEqual(settings.preferredColorScheme, .light)
    }

    @MainActor
    func testBlackThemeSelectionStaysBlack() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        settings.theme = .black

        XCTAssertEqual(settings.theme, .black)
        XCTAssertEqual(settings.activeTheme, .black)
        XCTAssertEqual(settings.preferredColorScheme, .dark)
    }

    @MainActor
    func testLegacyHolographicDarkSelectionNormalizesToDark() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        settings.theme = .holographicDark

        XCTAssertEqual(settings.theme, .dark)
        XCTAssertEqual(settings.activeTheme, .dark)
        XCTAssertEqual(settings.preferredColorScheme, .dark)
    }

    @MainActor
    func testVisibleThemesPersistWithoutUnlock() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        for theme in AppThemeOption.appearanceOptions {
            settings.theme = theme
            XCTAssertEqual(settings.theme, theme.normalizedSelection)
            XCTAssertEqual(settings.activeTheme, theme.normalizedSelection)
        }
    }

    @MainActor
    func testAllFontsAreEnabled() {
        for option in AppFontOption.allCases {
            XCTAssertTrue(option.isEnabled)
        }
    }

    @MainActor
    func testFontPreviewOverridesActiveFont() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        settings.fontOption = .system
        settings.beginFontPreview(.inter)

        XCTAssertEqual(settings.activeFontOption, .inter)
        XCTAssertEqual(settings.previewFontOption, .inter)
        XCTAssertEqual(settings.fontOption, .system)
    }

    @MainActor
    func testFontSelectionPersistsWithoutUnlock() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let pubkey = String(repeating: "d", count: 64)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        settings.configure(accountPubkey: pubkey)
        settings.fontOption = .ebGaramond

        let reloaded = AppSettingsStore(defaults: defaults, authStore: authStore)
        reloaded.configure(accountPubkey: pubkey)

        XCTAssertEqual(reloaded.fontOption, .ebGaramond)
        XCTAssertEqual(reloaded.activeFontOption, .ebGaramond)
    }

    @MainActor
    func testBundledCustomFontsExistInMainBundle() {
        let bundledFonts = [
            "DMSans.ttf",
            "EBGaramond.ttf",
            "ElmsSans.ttf",
            "GeistSans.ttf",
            "HubotSans.ttf",
            "Inter.ttf",
            "MonaSans.ttf",
            "Nacelle-Bold.otf",
            "Nacelle-Italic.otf",
            "Nacelle-Regular.otf",
            "Nacelle-SemiBold.otf",
            "Nunito.ttf",
            "PublicSans.ttf",
            "SpaceGrotesk.ttf"
        ]

        for fontFile in bundledFonts {
            let parts = fontFile.split(separator: ".", maxSplits: 1)
            XCTAssertEqual(parts.count, 2)
            XCTAssertNotNil(
                Bundle.main.url(
                    forResource: String(parts[0]),
                    withExtension: String(parts[1])
                ),
                "Missing bundled font: \(fontFile)"
            )
        }
    }

    @MainActor
    func testBlackThemeKeepsPureBlackBackgroundAndChrome() {
        assertColor(AppThemeOption.black.palette.background, matches: .black)
        assertColor(AppThemeOption.black.palette.chromeBackground, matches: .black)
        assertColor(
            AppThemeOption.black.palette.chromeBorder,
            matches: UIColor.white.withAlphaComponent(0.08)
        )
        assertColor(
            AppThemeOption.black.palette.separator,
            matches: UIColor.white.withAlphaComponent(0.13)
        )
        assertColor(
            AppThemeOption.black.palette.linkPreviewBorder,
            matches: UIColor.white.withAlphaComponent(0.13)
        )
        assertColor(
            AppThemeOption.black.palette.articlePreviewBorder,
            matches: UIColor.white.withAlphaComponent(0.15)
        )
    }

    @MainActor
    func testLightThemeUsesFormerWhitePalette() {
        assertColor(AppThemeOption.light.palette.background, matches: .white)
        assertColor(AppThemeOption.light.palette.chromeBackground, matches: .white)
        assertColor(
            AppThemeOption.light.palette.chromeBorder,
            matches: UIColor.black.withAlphaComponent(0.10)
        )
        XCTAssertNotNil(AppThemeOption.light.palette.capsuleTabStyle)
        XCTAssertNotNil(AppThemeOption.light.palette.profileActionStyle)
        XCTAssertNotNil(AppThemeOption.light.palette.pollStyle)
        assertColor(
            AppThemeOption.light.palette.capsuleTabStyle!.background,
            matches: UIColor(red: 0.965, green: 0.965, blue: 0.972, alpha: 1)
        )
        assertColor(
            AppThemeOption.light.palette.profileActionStyle!.primaryBackground,
            matches: .white
        )
        assertColor(
            AppThemeOption.light.palette.pollStyle!.cardBorder,
            matches: UIColor.black.withAlphaComponent(0.08)
        )
        XCTAssertEqual(AppThemeOption.white.normalizedSelection, .light)
        XCTAssertFalse(AppThemeOption.white.isEnabled)
    }

    @MainActor
    func testDarkThemeMatchesReferencePalette() {
        XCTAssertEqual(AppThemeOption.dark.preferredColorScheme, .dark)
        XCTAssertNil(AppThemeOption.dark.fixedPrimaryColor)
        XCTAssertNil(AppThemeOption.dark.fixedPrimaryGradient)
        assertColor(
            AppThemeOption.dark.palette.background,
            matches: UIColor(red: 23.0 / 255.0, green: 23.0 / 255.0, blue: 25.0 / 255.0, alpha: 1)
        )
        assertColor(
            AppThemeOption.dark.palette.navigationBackground,
            matches: UIColor(red: 19.0 / 255.0, green: 19.0 / 255.0, blue: 20.0 / 255.0, alpha: 1)
        )
        assertColor(
            AppThemeOption.dark.palette.secondaryBackground,
            matches: UIColor(red: 41.0 / 255.0, green: 41.0 / 255.0, blue: 41.0 / 255.0, alpha: 1)
        )
        assertColor(
            AppThemeOption.dark.palette.sheetBackground,
            matches: UIColor(red: 41.0 / 255.0, green: 41.0 / 255.0, blue: 41.0 / 255.0, alpha: 1)
        )
        assertColor(
            AppThemeOption.dark.palette.sheetCardBackground,
            matches: UIColor(red: 58.0 / 255.0, green: 58.0 / 255.0, blue: 58.0 / 255.0, alpha: 1)
        )
        assertColor(
            AppThemeOption.dark.palette.sheetCardBorder,
            matches: UIColor(red: 75.0 / 255.0, green: 75.0 / 255.0, blue: 75.0 / 255.0, alpha: 1)
        )
        assertColor(
            AppThemeOption.dark.palette.foreground,
            matches: UIColor(red: 226.0 / 255.0, green: 226.0 / 255.0, blue: 227.0 / 255.0, alpha: 1)
        )
        assertColor(
            AppThemeOption.dark.palette.mutedForeground,
            matches: UIColor(red: 125.0 / 255.0, green: 125.0 / 255.0, blue: 126.0 / 255.0, alpha: 1)
        )
        XCTAssertNotNil(AppThemeOption.dark.palette.capsuleTabStyle)
        XCTAssertNotNil(AppThemeOption.dark.palette.profileActionStyle)
        XCTAssertNotNil(AppThemeOption.dark.palette.pollStyle)
    }

    @MainActor
    func testSystemThemeSwitchesBetweenLightAndDarkPalettes() {
        assertColor(
            AppThemeOption.system.palette.background,
            matches: .white,
            style: .light
        )
        assertColor(
            AppThemeOption.system.palette.chromeBorder,
            matches: UIColor.black.withAlphaComponent(0.10),
            style: .light
        )
        assertColor(
            AppThemeOption.system.palette.sheetCardBackground,
            matches: .white,
            style: .light
        )
        assertColor(
            AppThemeOption.system.palette.background,
            matches: UIColor(red: 23.0 / 255.0, green: 23.0 / 255.0, blue: 25.0 / 255.0, alpha: 1),
            style: .dark
        )
        assertColor(
            AppThemeOption.system.palette.navigationBackground,
            matches: UIColor(red: 19.0 / 255.0, green: 19.0 / 255.0, blue: 20.0 / 255.0, alpha: 1),
            style: .dark
        )
        assertColor(
            AppThemeOption.system.palette.sheetCardBackground,
            matches: UIColor(red: 58.0 / 255.0, green: 58.0 / 255.0, blue: 58.0 / 255.0, alpha: 1),
            style: .dark
        )
        assertColor(
            AppThemeOption.system.palette.sheetCardBorder,
            matches: UIColor(red: 75.0 / 255.0, green: 75.0 / 255.0, blue: 75.0 / 255.0, alpha: 1),
            style: .dark
        )
    }

    @MainActor
    func testDefaultThemesKeepSharedQRCodePresentationBackground() {
        XCTAssertNil(AppThemeOption.system.qrShareBackgroundResourceName)
        XCTAssertNil(AppThemeOption.black.qrShareBackgroundResourceName)
        XCTAssertNil(AppThemeOption.light.qrShareBackgroundResourceName)
        XCTAssertNil(AppThemeOption.dark.qrShareBackgroundResourceName)
        XCTAssertEqual(
            ProfileQRCodePresentationBackground.resourceName(for: .system),
            ProfileQRCodePresentationBackground.defaultResourceName
        )
        XCTAssertEqual(
            ProfileQRCodePresentationBackground.resourceName(for: .black),
            ProfileQRCodePresentationBackground.defaultResourceName
        )
        XCTAssertEqual(
            ProfileQRCodePresentationBackground.resourceName(for: .light),
            ProfileQRCodePresentationBackground.defaultResourceName
        )
        XCTAssertEqual(
            ProfileQRCodePresentationBackground.resourceName(for: .dark),
            ProfileQRCodePresentationBackground.defaultResourceName
        )
    }

    @MainActor
    func testAdditionalThemesResolveCustomQRCodePresentationBackgrounds() {
        XCTAssertEqual(
            ProfileQRCodePresentationBackground.resourceName(for: .sakura),
            "sakura-share-bg.json"
        )
        XCTAssertEqual(
            ProfileQRCodePresentationBackground.resourceName(for: .dracula),
            ProfileQRCodePresentationBackground.defaultResourceName
        )
        XCTAssertEqual(
            ProfileQRCodePresentationBackground.resourceName(for: .gamer),
            ProfileQRCodePresentationBackground.defaultResourceName
        )
        XCTAssertEqual(
            ProfileQRCodePresentationBackground.resourceName(for: .holographicLight),
            ProfileQRCodePresentationBackground.defaultResourceName
        )
        XCTAssertEqual(
            ProfileQRCodePresentationBackground.resourceName(for: .holographicDark),
            ProfileQRCodePresentationBackground.defaultResourceName
        )
    }

    @MainActor
    func testBundledThemeAssetsExistInMainBundle() {
        XCTAssertNotNil(
            Bundle.main.url(forResource: "sakura-share-bg", withExtension: "json"),
            "Missing bundled Sakura QR share background"
        )
    }

    @MainActor
    func testFullWidthNoteRowsPersistsAcrossStoreReload() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let pubkey = String(repeating: "a", count: 64)

        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)
        settings.configure(accountPubkey: pubkey)
        settings.fullWidthNoteRows = true

        let reloaded = AppSettingsStore(defaults: defaults, authStore: authStore)
        reloaded.configure(accountPubkey: pubkey)

        XCTAssertTrue(reloaded.fullWidthNoteRows)
    }

    @MainActor
    func testFloatingComposeButtonPreferencePersistsAcrossStoreReload() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let pubkey = String(repeating: "a", count: 64)

        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)
        settings.configure(accountPubkey: pubkey)
        settings.floatingComposeButtonEnabled = true

        let reloaded = AppSettingsStore(defaults: defaults, authStore: authStore)
        reloaded.configure(accountPubkey: pubkey)

        XCTAssertTrue(reloaded.floatingComposeButtonEnabled)
    }

    func testFloatingComposePaddingClearsVisibleBottomBar() {
        let padding = FloatingComposeButtonLayout.bottomPadding(
            safeAreaBottom: 34,
            bottomTabBarHeight: 65,
            isBottomTabBarVisible: true
        )

        XCTAssertEqual(padding, 101)
    }

    func testFloatingComposePaddingSitsCloserWhenBottomBarIsHidden() {
        let hiddenPadding = FloatingComposeButtonLayout.bottomPadding(
            safeAreaBottom: 34,
            bottomTabBarHeight: 65,
            isBottomTabBarVisible: false
        )
        let visiblePadding = FloatingComposeButtonLayout.bottomPadding(
            safeAreaBottom: 34,
            bottomTabBarHeight: 65,
            isBottomTabBarVisible: true
        )

        XCTAssertEqual(hiddenPadding, 32)
        XCTAssertLessThan(hiddenPadding, visiblePadding)
    }

    func testBottomTabBarStaysVisibleOnHomeRoot() {
        XCTAssertTrue(
            ScrollChromeLayout.isBottomTabBarVisible(
                isHomeSideMenuPresented: false,
                selectedTabIsDirectMessages: false,
                isDirectMessagesRootVisible: true
            )
        )
    }

    func testBottomTabBarStillHidesBehindHomeSideMenu() {
        XCTAssertFalse(
            ScrollChromeLayout.isBottomTabBarVisible(
                isHomeSideMenuPresented: true,
                selectedTabIsDirectMessages: false,
                isDirectMessagesRootVisible: true
            )
        )
    }

    func testBottomTabBarStillHidesOnNestedDirectMessagesScreen() {
        XCTAssertFalse(
            ScrollChromeLayout.isBottomTabBarVisible(
                isHomeSideMenuPresented: false,
                selectedTabIsDirectMessages: true,
                isDirectMessagesRootVisible: false
            )
        )
    }

    func testHomeBottomBarUsesSafeAreaInsetInsteadOfOverlay() {
        XCTAssertFalse(
            ScrollChromeLayout.usesOverlayBottomTabBar(
                selectedTabIsHome: true,
                isHomeSideMenuPresented: false
            )
        )
    }

    func testVisibleBottomBarReservesInsetSpace() {
        XCTAssertTrue(
            ScrollChromeLayout.reservesBottomTabBarInsetSpace(
                isBottomTabBarVisible: true,
                usesOverlayBottomTabBar: false
            )
        )
    }

    func testHiddenBottomBarDoesNotReserveInsetSpace() {
        XCTAssertFalse(
            ScrollChromeLayout.reservesBottomTabBarInsetSpace(
                isBottomTabBarVisible: false,
                usesOverlayBottomTabBar: false
            )
        )
    }

    @MainActor
    func testMarkedSpamIsSharedAcrossAccountsAndNotSpamOverridesLocally() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let firstAccountPubkey = String(repeating: "a", count: 64)
        let secondAccountPubkey = String(repeating: "c", count: 64)
        let targetPubkey = String(repeating: "b", count: 64)

        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)
        settings.configure(accountPubkey: firstAccountPubkey)
        settings.addSpamFilterMarkedPubkey(targetPubkey)

        XCTAssertTrue(settings.isSpamFilterMarked(targetPubkey))
        XCTAssertTrue(settings.shouldHideSpamMarkedPubkey(targetPubkey))
        XCTAssertFalse(settings.isSpamReplySafelisted(targetPubkey))

        settings.addSpamReplySafelistedPubkey(targetPubkey)

        XCTAssertTrue(settings.isSpamFilterMarked(targetPubkey))
        XCTAssertTrue(settings.isSpamReplySafelisted(targetPubkey))
        XCTAssertFalse(settings.shouldHideSpamMarkedPubkey(targetPubkey))

        let reloaded = AppSettingsStore(defaults: defaults, authStore: authStore)
        reloaded.configure(accountPubkey: firstAccountPubkey)

        XCTAssertTrue(reloaded.isSpamFilterMarked(targetPubkey))
        XCTAssertTrue(reloaded.isSpamReplySafelisted(targetPubkey))
        XCTAssertFalse(reloaded.shouldHideSpamMarkedPubkey(targetPubkey))

        reloaded.configure(accountPubkey: secondAccountPubkey)

        XCTAssertTrue(reloaded.isSpamFilterMarked(targetPubkey))
        XCTAssertFalse(reloaded.isSpamReplySafelisted(targetPubkey))
        XCTAssertTrue(reloaded.shouldHideSpamMarkedPubkey(targetPubkey))
    }

    private func assertColor(
        _ color: Color,
        matches expected: UIColor,
        style: UIUserInterfaceStyle = .light,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let traitCollection = UITraitCollection(userInterfaceStyle: style)
        let actual = UIColor(color).resolvedColor(with: traitCollection)
        let expected = expected.resolvedColor(with: traitCollection)

        var actualRed: CGFloat = 0
        var actualGreen: CGFloat = 0
        var actualBlue: CGFloat = 0
        var actualAlpha: CGFloat = 0
        XCTAssertTrue(
            actual.getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha),
            file: file,
            line: line
        )

        var expectedRed: CGFloat = 0
        var expectedGreen: CGFloat = 0
        var expectedBlue: CGFloat = 0
        var expectedAlpha: CGFloat = 0
        XCTAssertTrue(
            expected.getRed(&expectedRed, green: &expectedGreen, blue: &expectedBlue, alpha: &expectedAlpha),
            file: file,
            line: line
        )

        XCTAssertEqual(actualRed, expectedRed, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualGreen, expectedGreen, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualBlue, expectedBlue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualAlpha, expectedAlpha, accuracy: 0.001, file: file, line: line)
    }
}
