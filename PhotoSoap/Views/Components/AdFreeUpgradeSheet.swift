import SwiftUI
import SwiftData

struct AdFreeUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var hapticsService: HapticsService

    @Bindable var stats: UserStats
    @ObservedObject var adRemovalPurchaseService: AdRemovalPurchaseService
    @ObservedObject var adCoordinator: AdCoordinator
    @ObservedObject var analyticsService: AnalyticsService

    @State private var isShowingRedeemSheet = false
    @State private var previousUnlockSource: AdRemovalUnlockSource?
    @State private var previousErrorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroSection
                    if adRemovalPurchaseService.unlockSource != .coupon {
                        loyaltySection
                    }
                    couponSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "adfree.title", table: "LocalizableAdFree"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                analyticsService.track(.paywallOpened(source: "ad_free_sheet"))
                previousUnlockSource = adRemovalPurchaseService.unlockSource
                previousErrorMessage = adRemovalPurchaseService.errorMessage
            }
            .onChange(of: adRemovalPurchaseService.unlockSource) { _, newValue in
                defer { previousUnlockSource = newValue }

                guard let previousUnlockSource else { return }
                guard newValue != previousUnlockSource, newValue != .none else { return }

                switch newValue {
                case .purchased, .earned:
                    hapticsService.success()
                case .coupon, .none:
                    break
                }
            }
            .onChange(of: adRemovalPurchaseService.errorMessage) { _, newValue in
                defer { previousErrorMessage = newValue }

                guard newValue != previousErrorMessage else { return }
                guard let errorMessage = newValue, !errorMessage.isEmpty else { return }

                hapticsService.error()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done", table: "LocalizableShared")) {
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

                Button(String(localized: "adfree.restore", table: "LocalizableAdFree")) {
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
                Text(String(localized: "adfree.productUnavailable", table: "LocalizableAdFree"))
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
            Text(String(localized: "adfree.loyalty.title", table: "LocalizableAdFree"))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(String(localized: "adfree.loyalty.deleteMore", table: "LocalizableAdFree").replacingOccurrences(of: "%d", with: "\(adRemovalPurchaseService.remainingDeletesForUnlock)"))
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

    @ViewBuilder
    private var couponSection: some View {
        if !adRemovalPurchaseService.hasAdRemovalEntitlement {
            Button {
                isShowingRedeemSheet = true
            } label: {
                HStack {
                    Label(String(localized: "adfree.coupon.haveCode", table: "LocalizableAdFree"), systemImage: "ticket")
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
            return String(localized: "adfree.alreadyUnlocked", table: "LocalizableAdFree")
        case .earned:
            return String(localized: "adfree.loyalty", table: "LocalizableAdFree")
        case .coupon:
            return String(localized: "adfree.coupon", table: "LocalizableAdFree")
        case .none:
            return String(localized: "adfree.hero.title", table: "LocalizableAdFree")
        }
    }

    private var heroIcon: String {
        adRemovalPurchaseService.hasAdRemovalEntitlement ? "checkmark.seal.fill" : "sparkles"
    }

    private var heroMessage: String {
        switch adRemovalPurchaseService.unlockSource {
        case .purchased:
            return String(localized: "adfree.hero.purchased", table: "LocalizableAdFree")
        case .earned:
            return String(localized: "adfree.hero.loyalty", table: "LocalizableAdFree")
        case .coupon:
            return String(localized: "adfree.hero.coupon", table: "LocalizableAdFree")
        case .none:
            return String(localized: "adfree.hero.purchase", table: "LocalizableAdFree")
        }
    }

    private var primaryButtonTitle: String {
        adRemovalPurchaseService.hasAdRemovalEntitlement ? String(localized: "adfree.unlocked", table: "LocalizableAdFree") : String(localized: "adfree.buyFor", table: "LocalizableAdFree")
    }

    private var progressMessage: String {
        if adRemovalPurchaseService.hasEarnedEntitlement {
            return String(localized: "adfree.unlocked", defaultValue: "Unlocked", table: "LocalizableAdFree")
        }

        let remainingDeletes = adRemovalPurchaseService.remainingDeletesForUnlock
        return String(localized: "adfree.toGo", defaultValue: "\(remainingDeletes) to go", table: "LocalizableAdFree").replacingOccurrences(of: "%d", with: "\(remainingDeletes)")
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
    .environmentObject(HapticsService())
}
