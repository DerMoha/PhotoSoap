import SwiftUI
import SwiftData

struct StatsView: View {
    @Bindable var stats: UserStats
    @ObservedObject var gameificationService: GameificationService
    @ObservedObject var adRemovalPurchaseService: AdRemovalPurchaseService
    @ObservedObject var adCoordinator: AdCoordinator
    @ObservedObject var analyticsService: AnalyticsService
    @Query private var unlockedAchievements: [UnlockedAchievement]
    @State private var viewModel = StatsViewModel()
    @State private var isShowingAdFreeSheet = false
    #if DEBUG
    @State private var isShowingDevOptions = false
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    overviewSection
                    streaksSection
                    ratioSection
                    analyticsSection
                    adFreeSection
                    achievementsPreviewSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("stats.title")
            .onAppear {
                adRemovalPurchaseService.refreshEarnedEntitlement(stats: stats)
                adCoordinator.updateEntitlement(hasAdRemovalEntitlement: adRemovalPurchaseService.hasAdRemovalEntitlement)
                analyticsService.track(.statsViewed())
            }
            .sheet(isPresented: $isShowingAdFreeSheet) {
                AdFreeUpgradeSheet(
                    stats: stats,
                    adRemovalPurchaseService: adRemovalPurchaseService,
                    adCoordinator: adCoordinator,
                    analyticsService: analyticsService
                )
                .presentationDetents([.medium, .large])
            }
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingDevOptions = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $isShowingDevOptions) {
                DeveloperOptionsView(
                    adRemovalPurchaseService: adRemovalPurchaseService,
                    adCoordinator: adCoordinator
                )
            }
            #endif
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("stats.overview")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(viewModel.getMainStats(from: stats)) { stat in
                    StatCard(stat: stat)
                }
            }
        }
    }

    private var streaksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("stats.streaks")
                .font(.headline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(viewModel.getStreakStats(from: stats)) { stat in
                    StatCard(stat: stat)
                }
            }
        }
    }

    private var ratioSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("stats.keepDelete")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                HStack {
                    Text("stats.keepRate")
                    Spacer()
                    Text("\(Int(viewModel.getKeepRatio(from: stats) * 100))%")
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))

                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.green)
                                .frame(width: geometry.size.width * viewModel.getKeepRatio(from: stats))

                            RoundedRectangle(cornerRadius: 8)
                                .fill(.red)
                                .frame(width: geometry.size.width * viewModel.getDeleteRatio(from: stats))
                        }
                    }
                }
                .frame(height: 24)

                HStack {
                    Text("stats.deleteRate")
                    Spacer()
                    Text("\(Int(viewModel.getDeleteRatio(from: stats) * 100))%")
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var achievementsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("stats.achievements")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                let count = (unlocked: unlockedAchievements.count, total: Achievement.allAchievements.count)
                Text("\(count.unlocked)/\(count.total)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let progress = gameificationService.getAchievementProgress(stats: stats)
            let nextToUnlock = progress.filter { !$0.1 }.prefix(3)

            VStack(spacing: 12) {
                ForEach(Array(nextToUnlock), id: \.0.id) { achievement, _, progressValue in
                    HStack(spacing: 12) {
                        Image(systemName: achievement.iconName)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(achievement.title)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            ProgressView(value: progressValue)
                                .tint(.blue)
                        }

                        Text(String(localized: "achievements.progress", defaultValue: "\(Int(progressValue * 100))% Complete"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 40)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var adFreeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("stats.adFreeUnlock")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Label(adFreeTitle, systemImage: adFreeIcon)
                        .font(.title3.weight(.semibold))

                    Spacer()

                    Button("adfree.details") {
                        analyticsService.track(.paywallOpened(source: "stats_card"))
                        isShowingAdFreeSheet = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text(adFreeMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label(adCoordinator.statusSummary, systemImage: adCoordinator.adsEnabled ? "rectangle.bottomthird.inset.filled" : "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("adfree.loyalty.progress")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(stats.totalDeleted)/\(AdRemovalConfig.freeUnlockDeletedCount)")
                            .font(.caption.weight(.semibold))
                    }

                    ProgressView(value: adRemovalPurchaseService.deleteProgress)
                        .tint(.orange)

                    Text(progressMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = adRemovalPurchaseService.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 12) {
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
                    .disabled(adRemovalPurchaseService.hasAdRemovalEntitlement || adRemovalPurchaseService.isLoading || adRemovalPurchaseService.product == nil)

                    Button("adfree.restore") {
                        Task {
                            await adRemovalPurchaseService.restorePurchases()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(adRemovalPurchaseService.isLoading || adRemovalPurchaseService.hasEarnedEntitlement)
                }

                if adRemovalPurchaseService.product == nil && !adRemovalPurchaseService.hasAdRemovalEntitlement {
                    Text("adfree.productUnavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var analyticsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("stats.privacy")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: analyticsToggleBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("stats.privacy.shareAnalytics")
                            .font(.subheadline.weight(.semibold))
                        Text("stats.privacy.analyticsDescription")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)

                VStack(alignment: .leading, spacing: 6) {
                    Text("stats.privacy.communityTotals")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(analyticsService.isEnabled ? "stats.analyticsOn" : "stats.analyticsOff")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var analyticsToggleBinding: Binding<Bool> {
        Binding(
            get: { analyticsService.isEnabled },
            set: { analyticsService.setEnabled($0) }
        )
    }

    private var adFreeTitle: String {
        switch adRemovalPurchaseService.unlockSource {
        case .purchased:
            return "adfree.purchased"
        case .earned:
            return "adfree.loyalty"
        case .coupon:
            return "adfree.coupon"
        case .none:
            return "adfree.hero.title"
        }
    }

    private var adFreeIcon: String {
        switch adRemovalPurchaseService.unlockSource {
        case .none:
            return "sparkles"
        case .purchased, .earned, .coupon:
            return "checkmark.seal.fill"
        }
    }

    private var adFreeMessage: String {
        switch adRemovalPurchaseService.unlockSource {
        case .purchased:
            return "adfree.hero.purchased"
        case .earned:
            return "adfree.earned"
        case .coupon:
            return "adfree.hero.coupon"
        case .none:
            return "adfree.hero.purchase"
        }
    }

    private var progressMessage: String {
        if adRemovalPurchaseService.hasEarnedEntitlement {
            return "adfree.loyalty.active"
        }

        let remainingDeletes = adRemovalPurchaseService.remainingDeletesForUnlock
        return remainingDeletes == 1
            ? "adfree.loyalty.oneMore"
            : "adfree.loyalty.deleteMore"
    }

    private var primaryButtonTitle: String {
        adRemovalPurchaseService.hasAdRemovalEntitlement ? "adfree.unlocked" : "adfree.buyFor"
    }

}

struct StatCard: View {
    let stat: StatsViewModel.StatItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: stat.iconName)
                    .foregroundStyle(stat.color)
                Spacer()
            }

            Text(stat.value)
                .font(.title2)
                .fontWeight(.bold)

            Text(stat.title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    StatsView(
        stats: UserStats(),
        gameificationService: GameificationService(),
        adRemovalPurchaseService: AdRemovalPurchaseService(
            analyticsService: AnalyticsService(),
            shouldObserveTransactions: false
        ),
        adCoordinator: AdCoordinator(),
        analyticsService: AnalyticsService()
    )
}
