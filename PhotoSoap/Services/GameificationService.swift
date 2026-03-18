import Foundation
import SwiftData
import Combine

@MainActor
class GameificationService: ObservableObject {
    @Published var newlyUnlockedAchievement: Achievement?
    @Published var showAchievementBanner = false
    @Published var streakMilestoneReached: Int?
    @Published var showStreakCelebration = false

    private let streakMilestones = [5, 10, 25, 50, 100, 250, 500]

    func processPhotoReview(
        action: ReviewAction,
        fileSize: Int64,
        stats: UserStats,
        challengeType: DailyChallengeType
    ) {
        stats.incrementReviewed()

        switch action {
        case .keep:
            stats.incrementKept()
        case .delete:
            stats.incrementDeleted(fileSize: fileSize)
        }

        stats.updateDailyChallengeProgress(for: challengeType)

        checkStreakMilestone(currentStreak: stats.currentStreak)
        checkAchievements(stats: stats)
    }

    func processSkip(stats: UserStats) {
        stats.resetStreak()
    }
    
    // MARK: - Review History Management
    
    func markPhotoReviewed(id: String, context: ModelContext) throws {
        let descriptor = FetchDescriptor<ReviewedPhoto>(predicate: #Predicate { $0.id == id })
        if (try? context.fetchCount(descriptor)) == 0 {
            let review = ReviewedPhoto(id: id)
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.showStreakCelebration = false
                self.streakMilestoneReached = nil
            }
        }
    }

    private func checkAchievements(stats: UserStats) {
        let newAchievements = Achievement.checkNewAchievements(for: stats)

        for achievement in newAchievements {
            stats.unlockAchievement(achievement.id)
        }

        if let firstNew = newAchievements.first {
            newlyUnlockedAchievement = firstNew
            showAchievementBanner = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                self.showAchievementBanner = false
                self.newlyUnlockedAchievement = nil
            }
        }
    }

    func updateDailyStreak(stats: UserStats) {
        stats.updateDailyStreak()
        checkAchievements(stats: stats)
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

    func getAchievementProgress(stats: UserStats) -> [(Achievement, Bool, Double)] {
        Achievement.allAchievements.map { achievement in
            let isUnlocked = stats.hasUnlockedAchievement(achievement.id)
            let progress = calculateProgress(for: achievement, stats: stats)
            return (achievement, isUnlocked, progress)
        }
    }

    private func calculateProgress(for achievement: Achievement, stats: UserStats) -> Double {
        switch achievement.id {
        case "first_steps":
            return min(1.0, Double(stats.totalReviewed) / 10.0)
        case "spring_cleaning":
            return min(1.0, Double(stats.totalDeleted) / 50.0)
        case "memory_keeper":
            return min(1.0, Double(stats.totalKept) / 100.0)
        case "streak_master":
            return min(1.0, Double(stats.bestStreak) / 25.0)
        case "daily_devotee":
            return min(1.0, Double(stats.dailyStreak) / 7.0)
        case "storage_saver":
            return min(1.0, Double(stats.storageFreed) / 1_073_741_824.0)
        case "century_club":
            return min(1.0, Double(stats.sessionReviewCount) / 100.0)
        case "photo_pro":
            return min(1.0, Double(stats.totalReviewed) / 1000.0)
        case "decisive":
            return min(1.0, Double(stats.bestStreak) / 50.0)
        case "cleanup_champion":
            return min(1.0, Double(stats.totalDeleted) / 500.0)
        default:
            return 0.0
        }
    }
}

enum ReviewAction {
    case keep
    case delete
}
