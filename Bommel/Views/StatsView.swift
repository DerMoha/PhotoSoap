import SwiftUI
import SwiftData

struct StatsView: View {
    @Bindable var stats: UserStats
    @ObservedObject var gameificationService: GameificationService
    @StateObject private var viewModel = StatsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    overviewSection
                    streaksSection
                    ratioSection
                    achievementsPreviewSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Statistics")
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
