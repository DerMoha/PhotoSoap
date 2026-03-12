import SwiftUI
import SwiftData

struct StatsView: View {
    @Bindable var stats: UserStats
    @ObservedObject var gameificationService: GameificationService
    @ObservedObject var adRemovalPurchaseService: AdRemovalPurchaseService
    @ObservedObject var adCoordinator: AdCoordinator
    @ObservedObject var analyticsService: AnalyticsService
    @StateObject private var viewModel = StatsViewModel()
    @State private var isShowingAdFreeSheet = false

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
            .navigationTitle("Statistics")
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
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Overview")
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
            Text("Streaks")
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
            Text("Keep vs Delete")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                HStack {
                    Text("Keep Rate")
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
                    Text("Delete Rate")
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
                Text("Achievements")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                let count = viewModel.getAchievementCount(from: stats)
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

                        Text("\(Int(progressValue * 100))%")
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
            Text("Ad-Free Unlock")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Label(adFreeTitle, systemImage: adFreeIcon)
                        .font(.title3.weight(.semibold))

                    Spacer()

                    Button("Details") {
                        analyticsService.track(.paywallOpened(source: "stats_card"))
                        isShowingAdFreeSheet = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text(adFreeMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label(adCoordinator.statusSummary, systemImage: adCoordinator.adsEnabled ? "play.circle.fill" : "wrench.and.screwdriver.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Loyalty progress")
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

                    Button("Restore") {
                        Task {
                            await adRemovalPurchaseService.restorePurchases()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(adRemovalPurchaseService.isLoading || adRemovalPurchaseService.hasEarnedEntitlement)
                }

                if adRemovalPurchaseService.product == nil && !adRemovalPurchaseService.hasAdRemovalEntitlement {
                    Text("Purchase option will appear when the App Store product is available.")
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
            Text("Privacy")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: analyticsToggleBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Share Anonymous Usage Analytics")
                            .font(.subheadline.weight(.semibold))
                        Text("Help improve PhotoSoap with lightweight product analytics that never include photo contents, asset IDs, or location data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.blue)

                Text(analyticsService.isEnabled ? "Anonymous analytics are currently on." : "Anonymous analytics are currently off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            return "Ad-free unlocked by purchase"
        case .earned:
            return "Ad-free unlocked by loyalty"
        case .none:
            return "Remove ads forever"
        }
    }

    private var adFreeIcon: String {
        switch adRemovalPurchaseService.unlockSource {
        case .none:
            return "sparkles"
        case .purchased, .earned:
            return "checkmark.seal.fill"
        }
    }

    private var adFreeMessage: String {
        switch adRemovalPurchaseService.unlockSource {
        case .purchased:
            return "Your purchase will keep the app ad-free on this account once ads are introduced."
        case .earned:
            return "You earned permanent ad-free access by deleting \(AdRemovalConfig.freeUnlockDeletedCount) photos."
        case .none:
            return "Buy ad-free now for \(adRemovalPurchaseService.displayPrice), or unlock it free after deleting \(AdRemovalConfig.freeUnlockDeletedCount) photos."
        }
    }

    private var progressMessage: String {
        if adRemovalPurchaseService.hasEarnedEntitlement {
            return "Your loyalty unlock is active."
        }

        let remainingDeletes = adRemovalPurchaseService.remainingDeletesForUnlock
        return remainingDeletes == 1
            ? "Delete 1 more photo to earn ad-free access for free."
            : "Delete \(remainingDeletes) more photos to earn ad-free access for free."
    }

    private var primaryButtonTitle: String {
        adRemovalPurchaseService.hasAdRemovalEntitlement ? "Unlocked" : "Buy for \(adRemovalPurchaseService.displayPrice)"
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
