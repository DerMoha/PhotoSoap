import SwiftUI
import SwiftData

struct StatsView: View {
    @Bindable var stats: UserStats
    @ObservedObject var photoLibraryService: PhotoLibraryService
    @ObservedObject var gamificationService: GamificationService
    @ObservedObject var privacyCollectionService: PrivacyCollectionService
    @State private var viewModel = StatsViewModel()
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if photoLibraryService.authorizationStatus == .limited {
                        limitedAccessSection
                    }

                    overviewSection
                    mediaBreakdownSection
                    streaksSection
                    ratioSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "stats.title", table: "LocalizableStats"))
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView(privacyCollectionService: privacyCollectionService)
            }
            .onAppear {
                privacyCollectionService.track(.statsViewed())
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        privacyCollectionService.track(.settingsOpened())
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "stats.overview", table: "LocalizableStats"))
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

    private var limitedAccessSection: some View {
        LimitedAccessCard(
            title: String(localized: "limitedAccess.title", table: "LocalizableShared"),
            message: String(localized: "limitedAccess.description", table: "LocalizableShared"),
            buttonTitle: String(localized: "limitedAccess.chooseMore", table: "LocalizableShared"),
            style: .stats,
            onManage: {
                privacyCollectionService.track(.limitedLibraryPickerOpened())
                photoLibraryService.presentLimitedLibraryPicker()
            }
        )
    }

    private var mediaBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "stats.mediaBreakdown", table: "LocalizableStats"))
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                ForEach(viewModel.getMediaStats(from: stats)) { mediaStats in
                    MediaStatsCard(item: mediaStats)
                }
            }
        }
    }

    private var streaksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "stats.streaks", table: "LocalizableStats"))
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
            Text(String(localized: "stats.keepDelete", table: "LocalizableStats"))
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                HStack {
                    Text(String(localized: "stats.keepRate", table: "LocalizableStats"))
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
                    Text(String(localized: "stats.deleteRate", table: "LocalizableStats"))
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

struct MediaStatsCard: View {
    let item: StatsViewModel.MediaStatsItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(item.title, systemImage: item.iconName)
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                metric(
                    value: item.reviewed,
                    label: String(localized: "stats.reviewed", defaultValue: "Reviewed", table: "LocalizableStats")
                )
                metric(
                    value: item.kept,
                    label: String(localized: "stats.kept", defaultValue: "Kept", table: "LocalizableStats")
                )
                metric(
                    value: item.deleted,
                    label: String(localized: "stats.deleted", defaultValue: "Deleted", table: "LocalizableStats")
                )
            }

            HStack(spacing: 6) {
                Image(systemName: "externaldrive.fill")
                    .foregroundStyle(.orange)
                Text(item.storageFreedFormatted)
                    .fontWeight(.semibold)
                Text(String(localized: "stats.storageFreed", defaultValue: "Storage Freed", table: "LocalizableStats"))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func metric(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    StatsView(
        stats: UserStats(),
        photoLibraryService: PhotoLibraryService(),
        gamificationService: GamificationService(),
        privacyCollectionService: PrivacyCollectionService(
            analyticsService: AnalyticsService(),
            aggregateMetricsService: AggregateMetricsService()
        )
    )
}
