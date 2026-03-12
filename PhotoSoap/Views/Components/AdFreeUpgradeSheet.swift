import SwiftUI
import SwiftData

struct AdFreeUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var stats: UserStats
    @ObservedObject var adRemovalPurchaseService: AdRemovalPurchaseService
    @ObservedObject var adCoordinator: AdCoordinator
    @ObservedObject var analyticsService: AnalyticsService

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroSection
                    loyaltySection
                    futureAdsSection
                    readinessSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ad-Free")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                analyticsService.track(.paywallOpened(source: "ad_free_sheet"))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(heroTitle, systemImage: heroIcon)
                .font(.title2.weight(.bold))

            Text(heroMessage)
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Button {
                    Task {
                        await adRemovalPurchaseService.purchase()
                    }
                } label: {
                    if adRemovalPurchaseService.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(primaryButtonTitle)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    adRemovalPurchaseService.hasAdRemovalEntitlement ||
                    adRemovalPurchaseService.isLoading ||
                    adRemovalPurchaseService.product == nil
                )

                Button("Restore Purchases") {
                    Task {
                        await adRemovalPurchaseService.restorePurchases()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(adRemovalPurchaseService.isLoading || adRemovalPurchaseService.hasEarnedEntitlement)
            }

            if let errorMessage = adRemovalPurchaseService.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if adRemovalPurchaseService.product == nil && !adRemovalPurchaseService.hasAdRemovalEntitlement {
                Text("The App Store product is not available yet, so buying is disabled for now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var loyaltySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Loyalty Unlock")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Delete \(AdRemovalConfig.freeUnlockDeletedCount) photos to earn permanent ad-free access without paying.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView(value: adRemovalPurchaseService.deleteProgress)
                .tint(.orange)

            HStack {
                Text("\(stats.totalDeleted) deleted")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(progressMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var futureAdsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Planned Ad Placements")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(adCoordinator.bannerPlacements + adCoordinator.interstitialPlacements) { placement in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: placement.kind == .banner ? "rectangle.bottomthird.inset.filled" : "sparkles.rectangle.stack")
                        .foregroundStyle(.blue)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(placement.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(placementDescription(for: placement))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AdMob Readiness")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(adCoordinator.statusSummary)
                .font(.subheadline)

            ForEach(adCoordinator.integrationChecklist, id: \.self) { item in
                Label(item, systemImage: "checklist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var heroTitle: String {
        switch adRemovalPurchaseService.unlockSource {
        case .purchased:
            return "You already unlocked ad-free access"
        case .earned:
            return "Your loyalty unlocked ad-free access"
        case .none:
            return "Keep PhotoSoap ad-free forever"
        }
    }

    private var heroIcon: String {
        adRemovalPurchaseService.hasAdRemovalEntitlement ? "checkmark.seal.fill" : "sparkles"
    }

    private var heroMessage: String {
        switch adRemovalPurchaseService.unlockSource {
        case .purchased:
            return "Your StoreKit purchase will suppress future ads on supported placements across the app."
        case .earned:
            return "Your cleanup streak earned permanent ad-free access once ads are introduced."
        case .none:
            return "Pay once for ad-free access, or keep deleting photos until you hit the free loyalty unlock."
        }
    }

    private var primaryButtonTitle: String {
        adRemovalPurchaseService.hasAdRemovalEntitlement ? "Unlocked" : "Buy for \(adRemovalPurchaseService.displayPrice)"
    }

    private var progressMessage: String {
        if adRemovalPurchaseService.hasEarnedEntitlement {
            return "Unlocked"
        }

        let remainingDeletes = adRemovalPurchaseService.remainingDeletesForUnlock
        return remainingDeletes == 1 ? "1 to go" : "\(remainingDeletes) to go"
    }

    private func placementDescription(for placement: AdPlacement) -> String {
        switch placement {
        case .statsBanner:
            return "Reserved for a lightweight banner below your stats cards."
        case .achievementsBanner:
            return "Reserved for a secondary banner on the achievements screen."
        case .reviewCompletionInterstitial:
            return "Reserved for natural pauses after a review batch, never during active swiping."
        }
    }
}

#Preview {
    AdFreeUpgradeSheet(
        stats: UserStats(),
        adRemovalPurchaseService: AdRemovalPurchaseService(
            analyticsService: AnalyticsService(),
            shouldObserveTransactions: false
        ),
        adCoordinator: AdCoordinator(),
        analyticsService: AnalyticsService()
    )
}
