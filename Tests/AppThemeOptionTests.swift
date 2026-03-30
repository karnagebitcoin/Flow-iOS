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
            matches: UIColor(red: 0.992, green: 0.647, blue: 0.835, alpha: 0.34)
        )
        XCTAssertNotNil(AppThemeOption.sakura.palette.capsuleTabStyle)
        XCTAssertNotNil(AppThemeOption.sakura.palette.profileActionStyle)
        XCTAssertNotNil(AppThemeOption.sakura.palette.pollStyle)
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
            matches: UIColor.white.withAlphaComponent(0.10)
        )
    }

    @MainActor
    func testWhiteThemeKeepsPureWhiteBackgroundAndChrome() {
        assertColor(AppThemeOption.white.palette.background, matches: .white)
        assertColor(AppThemeOption.white.palette.chromeBackground, matches: .white)
        assertColor(
            AppThemeOption.white.palette.chromeBorder,
            matches: UIColor.black.withAlphaComponent(0.12)
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
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let expected = expected.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))

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
