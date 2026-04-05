import XCTest
import SwiftUI
import UIKit
@testable import Flow

final class AppThemeOptionTests: XCTestCase {
    @MainActor
    func testSakuraRequiresFlowPlusAndUsesLightMode() {
        XCTAssertTrue(AppThemeOption.sakura.requiresFlowPlus)
        XCTAssertEqual(AppThemeOption.sakura.preferredColorScheme, .light)
        XCTAssertNotNil(AppThemeOption.sakura.fixedPrimaryGradient)
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
    func testDraculaRequiresFlowPlusAndUsesDarkMode() {
        XCTAssertTrue(AppThemeOption.dracula.requiresFlowPlus)
        XCTAssertEqual(AppThemeOption.dracula.preferredColorScheme, .dark)
        XCTAssertNotNil(AppThemeOption.dracula.fixedPrimaryGradient)
        XCTAssertNil(AppThemeOption.dracula.qrShareBackgroundResourceName)
        assertColor(
            try! XCTUnwrap(AppThemeOption.dracula.fixedPrimaryColor),
            matches: UIColor(red: 0.773, green: 0.565, blue: 1.0, alpha: 1)
        )
        assertColor(
            AppThemeOption.dracula.palette.background,
            matches: UIColor(red: 0.157, green: 0.165, blue: 0.212, alpha: 1)
        )
        assertColor(
            AppThemeOption.dracula.palette.chromeBackground,
            matches: UIColor(red: 0.129, green: 0.133, blue: 0.173, alpha: 1)
        )
        assertColor(
            AppThemeOption.dracula.palette.secondaryBackground,
            matches: UIColor(red: 0.204, green: 0.216, blue: 0.275, alpha: 1)
        )
        assertColor(
            AppThemeOption.dracula.palette.sheetBackground,
            matches: UIColor(red: 0.157, green: 0.165, blue: 0.212, alpha: 1)
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
    func testGamerRequiresFlowPlusAndUsesDarkMode() {
        XCTAssertTrue(AppThemeOption.gamer.requiresFlowPlus)
        XCTAssertEqual(AppThemeOption.gamer.preferredColorScheme, .dark)
        XCTAssertNotNil(AppThemeOption.gamer.fixedPrimaryGradient)
        XCTAssertNil(AppThemeOption.gamer.qrShareBackgroundResourceName)
        assertColor(
            try! XCTUnwrap(AppThemeOption.gamer.fixedPrimaryColor),
            matches: UIColor(red: 0.553, green: 0.408, blue: 1.0, alpha: 1)
        )
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
            matches: UIColor(red: 0.558, green: 0.640, blue: 0.776, alpha: 1)
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
    func testComingSoonThemesRemainDisabled() {
        XCTAssertFalse(AppThemeOption.dark.isEnabled)
        XCTAssertFalse(AppThemeOption.light.isEnabled)
    }

    @MainActor
    func testPremiumThemePreviewOverridesActiveThemeWithoutUnlocking() {
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
    func testFlowPlusPreviewUnlocksPremiumCustomizationForCurrentSession() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        XCTAssertFalse(settings.hasFlowPlusCustomizationAccess)
        XCTAssertTrue(settings.canBeginFlowPlusPreview())
        XCTAssertTrue(settings.beginFlowPlusPreview())

        XCTAssertTrue(settings.isFlowPlusPreviewUnlocked)
        XCTAssertTrue(settings.hasUsedFlowPlusPreviewThisSession)
        XCTAssertTrue(settings.hasFlowPlusCustomizationAccess)
        XCTAssertEqual(settings.activeTheme, .system)
        XCTAssertNil(settings.previewTheme)
    }

    @MainActor
    func testUnlockingFlowPlusKeepsPreviewedPremiumThemeSelected() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        settings.beginThemePreview(.sakura)
        settings.updateFlowPlusAccess(true)

        XCTAssertNil(settings.previewTheme)
        XCTAssertEqual(settings.theme, .sakura)
        XCTAssertEqual(settings.activeTheme, .sakura)
    }

    @MainActor
    func testUnlockingFlowPlusClearsSessionPreviewGate() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        XCTAssertTrue(settings.beginFlowPlusPreview())
        settings.updateFlowPlusAccess(true)

        XCTAssertFalse(settings.isFlowPlusPreviewUnlocked)
        XCTAssertTrue(settings.hasFlowPlusCustomizationAccess)
    }

    @MainActor
    func testPremiumThemePreviewIsLimitedToOncePerSession() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        XCTAssertTrue(settings.canBeginThemePreview(.sakura))
        XCTAssertTrue(settings.beginThemePreview(.sakura))

        settings.endThemePreview()

        XCTAssertFalse(settings.canBeginThemePreview(.sakura))
        XCTAssertFalse(settings.beginThemePreview(.sakura))
        XCTAssertNil(settings.previewTheme)
    }

    @MainActor
    func testFlowPlusSessionPreviewCanSwitchBetweenPremiumThemes() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        XCTAssertTrue(settings.beginFlowPlusPreview())
        XCTAssertTrue(settings.beginThemePreview(.sakura))
        XCTAssertEqual(settings.activeTheme, .sakura)

        XCTAssertTrue(settings.canBeginThemePreview(.dracula))
        XCTAssertTrue(settings.beginThemePreview(.dracula))
        XCTAssertEqual(settings.previewTheme, .dracula)
        XCTAssertEqual(settings.activeTheme, .dracula)

        XCTAssertTrue(settings.canBeginThemePreview(.gamer))
        XCTAssertTrue(settings.beginThemePreview(.gamer))
        XCTAssertEqual(settings.previewTheme, .gamer)
        XCTAssertEqual(settings.activeTheme, .gamer)
    }

    @MainActor
    func testPremiumFontsRequireFlowPlusExceptSystem() {
        XCTAssertFalse(AppFontOption.system.requiresFlowPlus)
        XCTAssertTrue(AppFontOption.mono.requiresFlowPlus)
        XCTAssertTrue(AppFontOption.ebGaramond.requiresFlowPlus)
    }

    @MainActor
    func testPremiumFontPreviewOverridesActiveFontWithoutUnlocking() {
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
    func testUnlockingFlowPlusKeepsPreviewedPremiumFontSelected() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        settings.beginFontPreview(.ebGaramond)
        settings.updateFlowPlusAccess(true)

        XCTAssertNil(settings.previewFontOption)
        XCTAssertEqual(settings.fontOption, .ebGaramond)
        XCTAssertEqual(settings.activeFontOption, .ebGaramond)
    }

    @MainActor
    func testFlowPlusUsesSingleMonthlyProductID() {
        XCTAssertEqual(
            FlowPremiumStore.FlowPlusProduct.allCases.map(\.rawValue),
            ["com.21media.flow.flowplus.monthly"]
        )
    }

    @MainActor
    func testFlowPlusPurchaseButtonDefaultsToFreeTrialCopy() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)
        let premiumStore = FlowPremiumStore(appSettings: settings)

        XCTAssertEqual(premiumStore.flowPlusPurchaseButtonTitle, "Try it free for 7 days")
    }

    func testFlowPlusStoreKitConfigIncludesSevenDayFreeTrial() {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let storeKitURL = repoRoot.appendingPathComponent("StoreKit/FlowPlus.storekit")
        let data = try! Data(contentsOf: storeKitURL)
        let jsonObject = try! XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let subscriptionGroups = try! XCTUnwrap(jsonObject["subscriptionGroups"] as? [[String: Any]])
        let firstGroup = try! XCTUnwrap(subscriptionGroups.first)
        XCTAssertEqual(firstGroup["name"] as? String, "Halo Plus")

        let subscriptions = try! XCTUnwrap(firstGroup["subscriptions"] as? [[String: Any]])
        let monthlyProduct = try! XCTUnwrap(subscriptions.first)
        let introductoryOffer = try! XCTUnwrap(monthlyProduct["introductoryOffer"] as? [String: Any])

        XCTAssertEqual(introductoryOffer["paymentMode"] as? String, "freeTrial")
        XCTAssertEqual(introductoryOffer["subscriptionPeriod"] as? String, "P1W")
        XCTAssertEqual(introductoryOffer["numberOfPeriods"] as? Int, 1)
        XCTAssertEqual(introductoryOffer["type"] as? String, "introductory")
    }

    @MainActor
    func testBundledPremiumFontsExistInMainBundle() {
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
    func testWhiteThemeKeepsPureWhiteBackgroundAndChrome() {
        assertColor(AppThemeOption.white.palette.background, matches: .white)
        assertColor(AppThemeOption.white.palette.chromeBackground, matches: .white)
        assertColor(
            AppThemeOption.white.palette.chromeBorder,
            matches: UIColor.black.withAlphaComponent(0.10)
        )
        XCTAssertNotNil(AppThemeOption.white.palette.capsuleTabStyle)
        XCTAssertNotNil(AppThemeOption.white.palette.profileActionStyle)
        XCTAssertNotNil(AppThemeOption.white.palette.pollStyle)
        assertColor(
            AppThemeOption.white.palette.capsuleTabStyle!.background,
            matches: UIColor(red: 0.965, green: 0.965, blue: 0.972, alpha: 1)
        )
        assertColor(
            AppThemeOption.white.palette.profileActionStyle!.primaryBackground,
            matches: .white
        )
        assertColor(
            AppThemeOption.white.palette.pollStyle!.cardBorder,
            matches: UIColor.black.withAlphaComponent(0.08)
        )
    }

    @MainActor
    func testSystemThemePreservesNativeLightSeparatorsAndUsesTunedDarkBorders() {
        let lightTraits = UITraitCollection(userInterfaceStyle: .light)
        let darkTraits = UITraitCollection(userInterfaceStyle: .dark)
        let lightSeparator = UIColor.separator.resolvedColor(with: lightTraits)
        let lightArticleBorder = lightSeparator.withAlphaComponent(lightSeparator.cgColor.alpha * 0.24)

        assertColor(
            AppThemeOption.system.palette.chromeBorder,
            matches: lightSeparator,
            style: .light
        )
        assertColor(
            AppThemeOption.system.palette.separator,
            matches: lightSeparator,
            style: .light
        )
        assertColor(
            AppThemeOption.system.palette.linkPreviewBorder,
            matches: lightSeparator,
            style: .light
        )
        assertColor(
            AppThemeOption.system.palette.articlePreviewBorder,
            matches: lightArticleBorder,
            style: .light
        )

        XCTAssertLessThan(lightSeparator.cgColor.alpha, 1)

        assertColor(
            AppThemeOption.system.palette.chromeBorder,
            matches: UIColor.white.withAlphaComponent(0.10),
            style: .dark
        )
        assertColor(
            AppThemeOption.system.palette.separator,
            matches: UIColor.white.withAlphaComponent(0.14),
            style: .dark
        )
        assertColor(
            AppThemeOption.system.palette.linkPreviewBorder,
            matches: UIColor.white.withAlphaComponent(0.14),
            style: .dark
        )
        assertColor(
            AppThemeOption.system.palette.articlePreviewBorder,
            matches: UIColor.white.withAlphaComponent(0.16),
            style: .dark
        )
    }

    @MainActor
    func testDefaultThemesKeepSharedQRCodePresentationBackground() {
        XCTAssertNil(AppThemeOption.system.qrShareBackgroundResourceName)
        XCTAssertNil(AppThemeOption.black.qrShareBackgroundResourceName)
        XCTAssertNil(AppThemeOption.white.qrShareBackgroundResourceName)
        XCTAssertEqual(
            ProfileQRCodePresentationBackground.resourceName(for: .system),
            ProfileQRCodePresentationBackground.defaultResourceName
        )
        XCTAssertEqual(
            ProfileQRCodePresentationBackground.resourceName(for: .black),
            ProfileQRCodePresentationBackground.defaultResourceName
        )
        XCTAssertEqual(
            ProfileQRCodePresentationBackground.resourceName(for: .white),
            ProfileQRCodePresentationBackground.defaultResourceName
        )
    }

    @MainActor
    func testPremiumThemesResolveCustomQRCodePresentationBackgrounds() {
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
    }

    @MainActor
    func testBundledPremiumThemeAssetsExistInMainBundle() {
        XCTAssertNotNil(
            Bundle.main.url(forResource: "sakura-share-bg", withExtension: "json"),
            "Missing bundled Sakura QR share background"
        )
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
