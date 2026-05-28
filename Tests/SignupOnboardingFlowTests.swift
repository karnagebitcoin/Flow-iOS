import XCTest
@testable import Flow

final class SignupOnboardingFlowTests: XCTestCase {
    func testSignupStoresTrendingFeedPreferenceBeforeAnyPostLoginAwait() throws {
        let source = try Self.sourceText(at: "Sources/Onboarding/SignupOnboardingView.swift")
        let finishStart = try XCTUnwrap(source.range(of: "private func finishSignup() async"))
        let finishEnd = try XCTUnwrap(source.range(of: "private func applyThemePreview()"))
        let finishSource = source[finishStart.lowerBound..<finishEnd.lowerBound]

        let loginRange = try XCTUnwrap(finishSource.range(of: "let account = try auth.loginWithNsecOrHex"))
        let preferenceRange = try XCTUnwrap(finishSource.range(of: "HomePrimaryFeedSource.trending.storageValue"))

        XCTAssertLessThan(
            loginRange.upperBound,
            preferenceRange.lowerBound,
            "Signup should store the Trending preference after the account pubkey is known."
        )

        let postLoginBeforePreference = loginRange.upperBound..<preferenceRange.lowerBound
        XCTAssertNil(
            finishSource.range(of: "await", range: postLoginBeforePreference),
            "Signup must store Trending before any post-login suspension, otherwise the home shell can boot on Following."
        )
    }

    @MainActor
    func testHomeFeedLoadsPersistedOnboardingTrendingPreferenceAfterInterestsSeed() {
        let currentUserPubkey = String(repeating: "f", count: 64)
        let preferenceKey = HomeFeedViewModel.persistedFeedSourceKey(pubkey: currentUserPubkey)
        UserDefaults.standard.removeObject(forKey: preferenceKey)
        defer {
            UserDefaults.standard.removeObject(forKey: preferenceKey)
        }

        UserDefaults.standard.set(
            HomePrimaryFeedSource.trending.storageValue,
            forKey: preferenceKey
        )

        let viewModel = HomeFeedViewModel(relayURL: URL(string: "wss://relay.example.com")!)
        viewModel.updateInterestHashtags(["nostr", "art"])
        viewModel.updateCurrentUserPubkey(currentUserPubkey)

        XCTAssertEqual(viewModel.feedSource, HomePrimaryFeedSource.trending)
    }

    private static func sourceText(at relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryRootURL = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let sourceURL = repositoryRootURL.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
