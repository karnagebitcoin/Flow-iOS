import StoreKit
import SwiftUI

struct FlowPlusPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettingsStore
    @EnvironmentObject private var premiumStore: FlowPremiumStore
    @State private var purchasingProductID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroCard
                    featureCard
                    pricingSection
                }
                .padding(16)
            }
            .background(AppThemePalette.sakura.groupedBackground.ignoresSafeArea())
            .navigationTitle("Halo Plus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await premiumStore.refreshProducts()
            await premiumStore.refreshEntitlements()
        }
        .onChange(of: premiumStore.isFlowPlusActive) { _, isActive in
            guard isActive else { return }
            dismiss()
        }
        .onChange(of: appSettings.hasFlowPlusCustomizationAccess) { _, hasAccess in
            guard hasAccess else { return }
            dismiss()
        }
    }

    private var sakuraAccentGradient: LinearGradient {
        AppThemeOption.sakura.fixedPrimaryGradient ?? LinearGradient(
            colors: [
                Color(red: 0.976, green: 0.659, blue: 1.0),
                Color(red: 1.0, green: 0.404, blue: 0.941)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var sakuraPrimaryColor: Color {
        AppThemeOption.sakura.fixedPrimaryColor ?? Color(red: 1.0, green: 0.404, blue: 0.941)
    }

    private var monthlyPriceText: String {
        premiumStore.flowPlusMonthlyPriceText
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unlock premium themes and custom fonts for Halo.")
                        .font(appSettings.appFont(size: 30, weight: .bold))
                        .foregroundStyle(Color(red: 0.33, green: 0.18, blue: 0.25))

                    Text("Halo Plus includes premium themes like Sakura and Dracula, plus curated mono, serif, and sans font choices for the whole app.")
                        .font(appSettings.appFont(.body))
                        .foregroundStyle(Color(red: 0.45, green: 0.27, blue: 0.35))
                }

                Spacer(minLength: 12)

                Label("Sakura", systemImage: "sparkles")
                    .font(appSettings.appFont(.caption1, weight: .semibold))
                    .foregroundStyle(sakuraPrimaryColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.72), in: Capsule())
            }

            Label("Try it free for 7 days. Then \(monthlyPriceText)/month.", systemImage: "gift.fill")
                .font(appSettings.appFont(.subheadline, weight: .semibold))
                .foregroundStyle(Color(red: 0.45, green: 0.21, blue: 0.32))

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.985, blue: 0.992),
                            Color(red: 0.990, green: 0.936, blue: 0.958),
                            Color(red: 0.956, green: 0.802, blue: 0.871)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 190)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 34, height: 34)

                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.82))
                                .frame(width: 120, height: 34)
                        }

                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.76))
                            .frame(height: 88)

                        HStack(spacing: 10) {
                            Capsule()
                                .fill(Color.white.opacity(0.9))
                                .frame(width: 82, height: 28)

                            Capsule()
                                .fill(sakuraAccentGradient)
                                .frame(width: 96, height: 28)
                        }
                    }
                    .padding(18)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.82), lineWidth: 1)
                }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.986, blue: 0.992),
                    Color(red: 0.995, green: 0.958, blue: 0.974)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.88), lineWidth: 1)
        }
    }

    private var featureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What’s included", systemImage: "wand.and.stars")
                .font(appSettings.appFont(.headline, weight: .semibold))
                .foregroundStyle(Color(red: 0.45, green: 0.21, blue: 0.32))

            flowPlusFeature("Sakura and Dracula each ship with a dedicated palette, accent treatment, and premium look.")
            flowPlusFeature("A premium font library with mono, serif, and modern sans options that can restyle the feed, composer, and settings.")
            flowPlusFeature("Try it free for 7 days before billing begins.")
            flowPlusFeature("After the free trial ends, Halo Plus renews at \(monthlyPriceText)/month until canceled.")
            flowPlusFeature("Future premium looks will unlock automatically with the same monthly Halo Plus subscription.")
            flowPlusFeature("Theme access stays tied to your App Store subscription and restores with Apple.")

            if let error = premiumStore.lastErrorMessage, !error.isEmpty {
                Text(error)
                    .font(appSettings.appFont(.footnote))
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        }
    }

    private var pricingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if premiumStore.isFlowPlusActive {
                Label("Halo Plus is active", systemImage: "checkmark.seal.fill")
                    .font(appSettings.appFont(.headline, weight: .semibold))
                    .foregroundStyle(Color(red: 0.33, green: 0.55, blue: 0.41))

                Link(destination: manageSubscriptionsURL) {
                    primaryPaywallButtonLabel("Manage Subscription")
                }
                .buttonStyle(.plain)
            } else if premiumStore.isLoadingProducts && premiumStore.flowPlusProduct == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading Halo Plus pricing…")
                        .font(appSettings.appFont(.body))
                        .foregroundStyle(.secondary)
                }
            } else if premiumStore.flowPlusProduct == nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Couldn't load Halo Plus pricing right now. Please try again in a moment.")
                        .font(appSettings.appFont(.footnote))
                        .foregroundStyle(.secondary)

                    temporaryTestingUnlockButton
                }
            } else {
                Text("Try it free for 7 days")
                    .font(appSettings.appFont(.headline, weight: .semibold))
                    .foregroundStyle(Color(red: 0.45, green: 0.21, blue: 0.32))

                Text("No charge today. Then \(monthlyPriceText)/month after the 7-day free trial.")
                    .font(appSettings.appFont(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let product = premiumStore.flowPlusProduct {
                    planButton(for: product)
                }

                temporaryTestingUnlockButton
            }

            Button {
                Task {
                    await premiumStore.restorePurchases()
                }
            } label: {
                Group {
                    if premiumStore.isRestoringPurchases {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Restore Purchases")
                            .font(appSettings.appFont(.subheadline, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(Color(red: 0.73, green: 0.30, blue: 0.50))
        }
        .padding(18)
        .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
        }
    }

    private func flowPlusFeature(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(sakuraPrimaryColor.opacity(0.16))
                .frame(width: 24, height: 24)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(sakuraPrimaryColor)
                }

            Text(text)
                .font(appSettings.appFont(.subheadline))
                .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var temporaryTestingUnlockButton: some View {
        #if DEBUG
        if !premiumStore.isFlowPlusActive && !appSettings.hasFlowPlusCustomizationAccess {
            Button {
                _ = appSettings.beginFlowPlusPreview()
                premiumStore.lastErrorMessage = nil
            } label: {
                Text("Temporarily Unlock for Testing")
                    .font(appSettings.appFont(.subheadline, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(Color(red: 0.73, green: 0.30, blue: 0.50))
        }
        #endif
    }

    private var manageSubscriptionsURL: URL {
        URL(string: "https://apps.apple.com/account/subscriptions")!
    }

    private func primaryPaywallButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(appSettings.appFont(.subheadline, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                sakuraAccentGradient,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .foregroundStyle(.white)
    }

    private func planButton(for product: Product) -> some View {
        let isPurchasing = purchasingProductID == product.id

        return Button {
            guard !isPurchasing else { return }
            purchasingProductID = product.id
            Task {
                _ = await premiumStore.purchase(product)
                purchasingProductID = nil
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(appSettings.appFont(.headline, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(
                        product.flowPlusPlanSubtitle(
                            eligibleIntroOffer: premiumStore.isEligibleForFlowPlusIntroOffer
                        ) ?? "Monthly subscription"
                    )
                        .font(appSettings.appFont(.footnote))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                if isPurchasing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(
                            premiumStore.isEligibleForFlowPlusIntroOffer && product.hasFreeTrialIntroOffer
                                ? "Free"
                                : product.displayPrice
                        )
                            .font(appSettings.appFont(.headline, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(
                            product.flowPlusPriceCaption(
                                eligibleIntroOffer: premiumStore.isEligibleForFlowPlusIntroOffer
                            )
                        )
                            .font(appSettings.appFont(.caption2, weight: .medium))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
            }
            .padding(16)
            .background(
                sakuraAccentGradient,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

}

private extension Product {
    var subscriptionPeriodDescription: String? {
        subscription?.subscriptionPeriod.flowPlusDisplayString
    }

    var hasFreeTrialIntroOffer: Bool {
        subscription?.introductoryOffer?.paymentMode == .freeTrial
    }

    func flowPlusPlanSubtitle(eligibleIntroOffer: Bool) -> String? {
        guard eligibleIntroOffer, let trialText = subscription?.introductoryOffer?.flowPlusTrialMarketingText else {
            return subscriptionPeriodDescription
        }
        return "\(trialText.capitalized), then \(pricePerPeriodDescription)"
    }

    func flowPlusPricingDetail(eligibleIntroOffer: Bool) -> String? {
        guard eligibleIntroOffer, let trialText = subscription?.introductoryOffer?.flowPlusTrialMarketingText else {
            return nil
        }
        return "\(trialText.capitalized), then \(displayPrice) per \(subscription?.subscriptionPeriod.flowPlusUnitLabel ?? "period"). Cancel anytime."
    }

    func flowPlusPriceCaption(eligibleIntroOffer: Bool) -> String {
        guard eligibleIntroOffer, hasFreeTrialIntroOffer else { return pricePerPeriodDescription }
        return "then \(pricePerPeriodDescription)"
    }

    var pricePerPeriodDescription: String {
        guard let period = subscription?.subscriptionPeriod else { return "Billed by Apple" }
        return "per \(period.flowPlusUnitLabel)"
    }
}

private extension Product.SubscriptionOffer {
    var flowPlusTrialMarketingText: String? {
        guard paymentMode == .freeTrial else { return nil }

        switch period.unit {
        case .week where period.value * max(periodCount, 1) == 1:
            return "7-day free trial"
        default:
            let totalValue = period.value * max(periodCount, 1)
            let unitLabel = period.flowPlusUnitLabel
            let durationText = totalValue == 1 ? "1 \(unitLabel)" : "\(totalValue) \(unitLabel)s"
            return "\(durationText) free trial"
        }
    }
}

private extension Product.SubscriptionPeriod {
    var flowPlusDisplayString: String {
        value == 1 ? flowPlusUnitLabel.capitalized : "\(value) \(flowPlusUnitLabel)s"
    }

    var flowPlusUnitLabel: String {
        switch unit {
        case .day:
            return "day"
        case .week:
            return "week"
        case .month:
            return "month"
        case .year:
            return "year"
        @unknown default:
            return "period"
        }
    }
}
