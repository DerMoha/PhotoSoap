import SwiftUI
import SwiftData

struct AchievementsView: View {
    @Bindable var stats: UserStats
    @ObservedObject var gameificationService: GameificationService
    @Environment(\.modelContext) private var modelContext
    @Query private var unlockedAchievements: [UnlockedAchievement]
    @State private var selectedAchievement: Achievement?

    init(stats: UserStats, gameificationService: GameificationService) {
        self.stats = stats
        self.gameificationService = gameificationService
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    progressHeader
                    achievementsGrid
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "achievements.title", table: "LocalizableAchievements"))
            .sheet(item: $selectedAchievement) { achievement in
                AchievementDetailSheet(
                    achievement: achievement,
                    isUnlocked: isAchievementUnlocked(achievement.id),
                    progress: getProgress(for: achievement),
                    unlockDate: getUnlockDate(for: achievement.id)
                )
                .presentationDetents([.medium])
            }
        }
    }

    private var progressHeader: some View {
        VStack(spacing: 16) {
            let unlockedCount = unlockedAchievements.count
            let totalCount = Achievement.allAchievements.count
            let progress = Double(unlockedCount) / Double(totalCount)

            ZStack {
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 12)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.blue, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(), value: progress)

                VStack(spacing: 2) {
                    Text("\(unlockedCount)")
                        .font(.title)
                        .fontWeight(.bold)
                    Text(String(localized: "achievements.of", defaultValue: "of \(totalCount)", table: "LocalizableAchievements"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(String(localized: "achievements.unlocked", table: "LocalizableAchievements"))
                .font(.headline)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var achievementsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            ForEach(Achievement.allAchievements) { achievement in
                AchievementCard(
                    achievement: achievement,
                    isUnlocked: isAchievementUnlocked(achievement.id),
                    progress: getProgress(for: achievement),
                    unlockDate: getUnlockDate(for: achievement.id)
                )
                .onTapGesture {
                    selectedAchievement = achievement
                }
            }
        }
    }

    private func isAchievementUnlocked(_ achievementId: String) -> Bool {
        unlockedAchievements.contains { $0.achievementId == achievementId }
    }

    private func getProgress(for achievement: Achievement) -> Double {
        let progressData = gameificationService.getAchievementProgress(stats: stats, context: modelContext)
        return progressData.first { $0.0.id == achievement.id }?.2 ?? 0
    }

    private func getUnlockDate(for achievementId: String) -> Date? {
        unlockedAchievements.first { $0.achievementId == achievementId }?.unlockDate
    }
}

struct AchievementCard: View {
    let achievement: Achievement
    let isUnlocked: Bool
    let progress: Double
    let unlockDate: Date?

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? .yellow.opacity(0.2) : Color(.systemGray5))
                    .frame(width: 60, height: 60)

                if !isUnlocked {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                }

                Image(systemName: achievement.iconName)
                    .font(.title2)
                    .foregroundStyle(isUnlocked ? .yellow : .secondary)
            }

            Text(achievement.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if isUnlocked, let date = unlockDate {
                Text(String(localized: "achievements.completedOn", defaultValue: "Completed on %@", table: "LocalizableAchievements").replacingOccurrences(of: "%@", with: date.formatted(.dateTime.month(.abbreviated).day())))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if !isUnlocked {
                Text(String(localized: "achievements.progress", defaultValue: "\(Int(progress * 100))% Complete", table: "LocalizableAchievements"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(isUnlocked ? 1 : 0.7)
    }
}

struct AchievementDetailSheet: View {
    let achievement: Achievement
    let isUnlocked: Bool
    let progress: Double
    let unlockDate: Date?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? .yellow.opacity(0.2) : Color(.systemGray5))
                    .frame(width: 100, height: 100)

                if !isUnlocked {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                }

                Image(systemName: achievement.iconName)
                    .font(.system(size: 40))
                    .foregroundStyle(isUnlocked ? .yellow : .secondary)
            }
            .padding(.top, 32)

            VStack(spacing: 8) {
                Text(achievement.title)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(achievement.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if isUnlocked {
                VStack(spacing: 4) {
                    Label(String(localized: "achievements.unlocked.status", table: "LocalizableAchievements"), systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)

                    if let date = unlockDate {
                        Text(String(localized: "achievements.completedOn", defaultValue: "Completed on %@", table: "LocalizableAchievements").replacingOccurrences(of: "%@", with: date.formatted(date: .abbreviated, time: .omitted)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(.blue)

                    Text(String(localized: "achievements.progress", defaultValue: "\(Int(progress * 100))% Complete", table: "LocalizableAchievements"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text(String(localized: "achievements.close", table: "LocalizableAchievements"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}

#Preview {
    AchievementsView(stats: UserStats(), gameificationService: GameificationService())
}
