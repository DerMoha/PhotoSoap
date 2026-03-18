import SwiftUI
import SwiftData

struct AdFreeUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var stats: UserStats
    @ObservedObject var adRemovalPurchaseService: AdRemovalPurchaseService
    @ObservedObject var adCoordinator: AdCoordinator
    @ObservedObject var analyticsService: AnalyticsService

    @State private var isShowingRedeemSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroSection
                    loyaltySection
                    couponSection
                    bannerSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("adfree.title")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                analyticsService.track(.paywallOpened(source: "ad_free_sheet"))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingRedeemSheet) {
                RedeemCouponSheet(adRemovalPurchaseService: adRemovalPurchaseService)
                    .presentationDetents([.medium])
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

                Button("adfree.restore") {
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
                Text("adfree.productUnavailable")
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
            Text("adfree.loyalty.title")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("adfree.loyalty.deleteMore")
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

    private var bannerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("adfree.banner.title")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "rectangle.bottomthird.inset.filled")
                    .foregroundStyle(.blue)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("adfree.banner.title")
                        .font(.subheadline.weight(.semibold))
                    Text("adfree.banner.description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Label(adCoordinator.statusSummary, systemImage: adCoordinator.adsEnabled ? "play.circle.fill" : "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private var couponSection: some View {
        if !adRemovalPurchaseService.hasAdRemovalEntitlement {
            Button {
                isShowingRedeemSheet = true
            } label: {
                HStack {
                    Label("adfree.coupon.haveCode", systemImage: "ticket")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    private var heroTitle: String {
        switch adRemovalPurchaseService.unlockSource {
        case .purchased:
            return "adfree.alreadyUnlocked"
        case .earned:
            return "adfree.loyalty"
        case .coupon:
            return "adfree.coupon"
        case .none:
            return "adfree.hero.title"
        }
    }

    private var heroIcon: String {
        adRemovalPurchaseService.hasAdRemovalEntitlement ? "checkmark.seal.fill" : "sparkles"
    }

    private var heroMessage: String {
        switch adRemovalPurchaseService.unlockSource {
        case .purchased:
            return "adfree.hero.purchased"
        case .earned:
            return "adfree.hero.loyalty"
        case .coupon:
            return "adfree.hero.coupon"
        case .none:
            return "adfree.hero.purchase"
        }
    }

    private var primaryButtonTitle: String {
        adRemovalPurchaseService.hasAdRemovalEntitlement ? "adfree.unlocked" : "adfree.buyFor"
    }

    private var progressMessage: String {
        if adRemovalPurchaseService.hasEarnedEntitlement {
            return "adfree.unlocked"
        }

        let remainingDeletes = adRemovalPurchaseService.remainingDeletesForUnlock
        return remainingDeletes == 1 ? "1 to go" : "\(remainingDeletes) to go"
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
