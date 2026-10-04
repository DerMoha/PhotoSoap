import Foundation
import SwiftData
import Combine

@MainActor
class GamificationService: ObservableObject {
    @Published var newlyUnlockedAchievement: Achievement?
    @Published var showAchievementBanner = false
    @Published var streakMilestoneReached: Int?
    @Published var showStreakCelebration = false

    private let streakMilestones = [5, 10, 25, 50, 100, 250, 500]

    func processPhotoReview(
        action: ReviewAction,
        fileSize: Int64,
        stats: UserStats,
        challengeType: DailyChallengeType,
        context: ModelContext,
        mediaType: ReviewMediaType = .photo
    ) {
        stats.incrementReviewed(mediaType: mediaType)

        switch action {
        case .keep:
            stats.incrementKept(mediaType: mediaType)
        case .delete:
            stats.incrementDeleted(fileSize: fileSize, mediaType: mediaType)
        }

        stats.updateDailyChallengeProgress(for: challengeType)

        checkStreakMilestone(currentStreak: stats.currentStreak)
        checkAchievements(stats: stats, context: context)
    }

    func processQueuedDeletionReview(
        stats: UserStats,
        challengeType: DailyChallengeType,
        context: ModelContext,
        mediaType: ReviewMediaType = .photo
    ) {
        stats.incrementReviewed(mediaType: mediaType)

        if challengeType == .review {
            stats.updateDailyChallengeProgress(for: .review)
        }

        checkStreakMilestone(currentStreak: stats.currentStreak)
        checkAchievements(stats: stats, context: context)
    }

    func processQueuedDeletionCommit(
        fileSize: Int64,
        stats: UserStats,
        challengeType: DailyChallengeType,
        context: ModelContext,
        mediaType: ReviewMediaType = .photo
    ) {
        stats.incrementQueuedDeletionCommit(fileSize: fileSize, mediaType: mediaType)

        if challengeType == .delete {
            stats.updateDailyChallengeProgress(for: .delete)
        }

        checkAchievements(stats: stats, context: context)
    }

    func rollbackQueuedDeletionReview(
        id: String,
        stats: UserStats,
        challengeType: DailyChallengeType,
        context: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<ReviewedPhoto>(predicate: #Predicate { $0.id == id })
        let reviewedPhotos = try context.fetch(descriptor)
        let mediaType = reviewedPhotos.first?.reviewMediaType ?? .photo

        for reviewedPhoto in reviewedPhotos {
            context.delete(reviewedPhoto)
        }

        stats.decrementQueuedReview(mediaType: mediaType)
        if challengeType == .review {
            stats.decrementDailyChallengeProgress(for: .review)
        }

        removeAchievementsNoLongerMet(stats: stats, context: context)
    }

    func processSkip(stats: UserStats) {
        stats.resetStreak()
    }

    // MARK: - Review History Management

    func markPhotoReviewed(id: String, context: ModelContext, mediaType: ReviewMediaType = .photo) throws {
        let descriptor = FetchDescriptor<ReviewedPhoto>(predicate: #Predicate { $0.id == id })
        if (try? context.fetchCount(descriptor)) == 0 {
            let review = ReviewedPhoto(id: id, mediaType: mediaType)
            context.insert(review)
        }
    }

    func isPhotoReviewed(id: String, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<ReviewedPhoto>(predicate: #Predicate { $0.id == id })
        return (try? context.fetchCount(descriptor)) ?? 0 > 0
    }

    func deleteAllReviewedPhotos(context: ModelContext) throws {
        let descriptor = FetchDescriptor<ReviewedPhoto>()
        let allReviewed = try context.fetch(descriptor)
        for review in allReviewed {
            context.delete(review)
        }
    }

    private func checkStreakMilestone(currentStreak: Int) {
        if streakMilestones.contains(currentStreak) {
            streakMilestoneReached = currentStreak
            showStreakCelebration = true

            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    self.showStreakCelebration = false
                    self.streakMilestoneReached = nil
                }
            }
        }
    }

    private func checkAchievements(stats: UserStats, context: ModelContext) {
        var firstUnlockedAchievement: Achievement?

        for achievement in Achievement.allAchievements {
            if !isAchievementUnlocked(achievement.id, context: context) && meetsRequirement(achievement, stats: stats) {
                let unlocked = UnlockedAchievement(achievementId: achievement.id)
                context.insert(unlocked)

                if firstUnlockedAchievement == nil {
                    firstUnlockedAchievement = achievement
                }
            }
        }

        if let firstUnlockedAchievement {
            presentAchievementBanner(for: firstUnlockedAchievement)
        }
    }

    private func removeAchievementsNoLongerMet(stats: UserStats, context: ModelContext) {
        guard let unlockedAchievements = try? context.fetch(FetchDescriptor<UnlockedAchievement>()) else { return }
        let achievementsByID = Dictionary(uniqueKeysWithValues: Achievement.allAchievements.map { ($0.id, $0) })

        for unlockedAchievement in unlockedAchievements {
            guard let achievement = achievementsByID[unlockedAchievement.achievementId] else { continue }
            if !meetsRequirement(achievement, stats: stats) {
                context.delete(unlockedAchievement)
            }
        }
    }

    private func presentAchievementBanner(for achievement: Achievement) {
        newlyUnlockedAchievement = achievement
        showAchievementBanner = true

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                guard self.newlyUnlockedAchievement?.id == achievement.id else { return }
                self.showAchievementBanner = false
                self.newlyUnlockedAchievement = nil
            }
        }
    }

    private func isAchievementUnlocked(_ achievementId: String, context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<UnlockedAchievement>(
            predicate: #Predicate { $0.achievementId == achievementId }
        )
        return (try? context.fetchCount(descriptor)) ?? 0 > 0
    }

    private func meetsRequirement(_ achievement: Achievement, stats: UserStats) -> Bool {
        switch achievement.id {
        case "first_steps":
            return stats.totalReviewed >= 50
        case "spring_cleaning":
            return stats.totalDeleted >= 200
        case "memory_keeper":
            return stats.totalKept >= 500
        case "streak_master":
            return stats.bestStreak >= 100
        case "daily_devotee":
            return stats.dayStreak >= 14
        case "storage_saver":
            return stats.storageFreed >= 5_000_000_000
        case "century_club":
            return stats.sessionReviewCount >= 500
        case "photo_pro":
            return stats.totalReviewed >= 5000
        case "decisive":
            return stats.bestStreak >= 200
        case "cleanup_champion":
            return stats.totalDeleted >= 2000
        default:
            return false
        }
    }

    func resetSessionStats(stats: UserStats) {
        stats.sessionReviewCount = 0
    }

    func ensureDailyChallengeIsSet(stats: UserStats) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let challengeDate = stats.dailyChallengeDate {
            let challengeDay = calendar.startOfDay(for: challengeDate)
            if challengeDay != today {
                stats.resetDailyChallenge()
            }
        } else {
            stats.resetDailyChallenge()
        }
    }

    func getCurrentDailyChallenge(stats: UserStats) -> DailyChallenge {
        ensureDailyChallengeIsSet(stats: stats)

        return DailyChallenge(
            id: UUID(),
            type: DailyChallengeType(rawValue: stats.dailyChallengeType) ?? .review,
            target: stats.dailyChallengeTarget,
            date: stats.dailyChallengeDate ?? Date()
        )
    }

    func getAchievementProgress(stats: UserStats, context: ModelContext) -> [(Achievement, Bool, Double)] {
        Achievement.allAchievements.map { achievement in
            let isUnlocked = isAchievementUnlocked(achievement.id, context: context)
            let progress = calculateProgress(for: achievement, stats: stats)
            return (achievement, isUnlocked, progress)
        }
    }

    private func calculateProgress(for achievement: Achievement, stats: UserStats) -> Double {
        switch achievement.id {
        case "first_steps":
            return min(1.0, Double(stats.totalReviewed) / 50.0)
        case "spring_cleaning":
            return min(1.0, Double(stats.totalDeleted) / 200.0)
        case "memory_keeper":
            return min(1.0, Double(stats.totalKept) / 500.0)
        case "streak_master":
            return min(1.0, Double(stats.bestStreak) / 100.0)
        case "daily_devotee":
            return min(1.0, Double(stats.dayStreak) / 14.0)
        case "storage_saver":
            return min(1.0, Double(stats.storageFreed) / 5_000_000_000.0)
        case "century_club":
            return min(1.0, Double(stats.sessionReviewCount) / 500.0)
        case "photo_pro":
            return min(1.0, Double(stats.totalReviewed) / 5000.0)
        case "decisive":
            return min(1.0, Double(stats.bestStreak) / 200.0)
        case "cleanup_champion":
            return min(1.0, Double(stats.totalDeleted) / 2000.0)
        default:
            return 0.0
        }
    }
}

enum ReviewAction {
    case keep
    case delete
}
