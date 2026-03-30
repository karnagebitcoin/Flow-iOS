import XCTest
@testable import Flow

final class AppThemeOptionTests: XCTestCase {
    @MainActor
    func testSakuraRequiresFlowPlusAndUsesLightMode() {
        XCTAssertTrue(AppThemeOption.sakura.requiresFlowPlus)
        XCTAssertEqual(AppThemeOption.sakura.preferredColorScheme, .light)
        XCTAssertNotNil(AppThemeOption.sakura.fixedPrimaryGradient)
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
    func testUnlockingFlowPlusKeepsPreviewedPremiumThemeSelected() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let authStore = AuthStore(defaults: defaults)
        let settings = AppSettingsStore(defaults: defaults, authStore: authStore)

        settings.beginThemePreview(.sakura)
        settings.updatePremiumThemesUnlocked(true)

        XCTAssertNil(settings.previewTheme)
        XCTAssertEqual(settings.theme, .sakura)
        XCTAssertEqual(settings.activeTheme, .sakura)
    }

    @MainActor
    func testFlowPlusUsesSingleMonthlyProductID() {
        XCTAssertEqual(
            FlowPremiumStore.FlowPlusProduct.allCases.map(\.rawValue),
            ["com.21media.flow.flowplus.monthly"]
        )
    }
}
