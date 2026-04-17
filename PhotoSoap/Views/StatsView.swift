import SwiftUI
import SwiftData

struct StatsView: View {
    @Bindable var stats: UserStats
    @ObservedObject var photoLibraryService: PhotoLibraryService
    @ObservedObject var gameificationService: GameificationService
    @ObservedObject var analyticsService: AnalyticsService
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
                    streaksSection
                    ratioSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "stats.title", table: "LocalizableStats"))
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView(analyticsService: analyticsService)
            }
            .onAppear {
                analyticsService.track(.statsViewed())
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        analyticsService.track(.settingsOpened())
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
                analyticsService.track(.limitedLibraryPickerOpened())
                photoLibraryService.presentLimitedLibraryPicker()
            }
        )
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

#Preview {
    StatsView(
        stats: UserStats(),
        photoLibraryService: PhotoLibraryService(),
        gameificationService: GameificationService(),
        analyticsService: AnalyticsService()
    )
}
