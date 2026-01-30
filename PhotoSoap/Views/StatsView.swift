import SwiftUI
import SwiftData

struct StatsView: View {
    @Bindable var stats: UserStats
    @ObservedObject var gameificationService: GameificationService
    @StateObject private var viewModel = StatsViewModel()
    @StateObject private var purchaseService = AdRemovalPurchaseService()
    @AppStorage("showAds") private var showAds = true
    @AppStorage("hasPurchasedRemoveAds") private var hasPurchasedRemoveAds = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    overviewSection
                    streaksSection
                    ratioSection
                    achievementsPreviewSection
                    adsSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Statistics")
        }
        .onAppear {
            enforceAdsVisibility()
        }
        .onChange(of: stats.totalDeleted) { _, _ in
            enforceAdsVisibility()
        }
        .onChange(of: hasPurchasedRemoveAds) { _, newValue in
            if newValue && showAds {
                showAds = false
            }
            enforceAdsVisibility()
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

    private var adsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ads")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Text(adsMessage)
                    .font(.subheadline)

                ProgressView(value: deleteProgress)
                    .tint(.blue)

                HStack {
                    Text("\(stats.totalDeleted.formatted()) / \(deleteGoal.formatted()) deleted")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !canRemoveAds {
                        Text("\(deleteRemaining.formatted()) to go")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if canRemoveAds {
                    if showAds {
                        Button {
                            showAds = false
                        } label: {
                            Label("Remove ads", systemImage: "nosign")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Ads removed")
                        }
                        .font(.subheadline)

                        Button("Show ads again") {
                            showAds = true
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        Task {
                            await purchaseService.purchase()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if purchaseService.isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Remove ads for \(purchaseService.displayPrice)")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(purchaseService.isLoading || purchaseService.product == nil)

                    Button("Restore Purchases") {
                        Task {
                            await purchaseService.restorePurchases()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text("Banner appears above the tab bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let error = purchaseService.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private var deleteGoal: Int {
        AdRemovalConfig.freeUnlockDeletedCount
    }

    private var deleteRemaining: Int {
        max(deleteGoal - stats.totalDeleted, 0)
    }

    private var deleteProgress: Double {
        min(Double(stats.totalDeleted) / Double(deleteGoal), 1)
    }

    private var canRemoveAds: Bool {
        hasPurchasedRemoveAds || stats.totalDeleted >= deleteGoal
    }

    private var adsMessage: String {
        if canRemoveAds {
            return "You can remove ads whenever you're ready."
        }

        return "Delete \(deleteGoal.formatted()) photos to remove ads for free, or remove now for \(purchaseService.displayPrice)."
    }

    private func enforceAdsVisibility() {
        if !canRemoveAds && !showAds {
            showAds = true
        }
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
    StatsView(stats: UserStats(), gameificationService: GameificationService())
}
