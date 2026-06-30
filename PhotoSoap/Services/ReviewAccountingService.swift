import Foundation
import Combine
import SwiftData

struct ReviewAccountingSnapshot {
    let stats: UserStatsSnapshot
    let reviewedPhotoIDs: Set<String>
    let unlockedAchievementIDs: Set<String>
    let feedback: GamificationFeedbackSnapshot
}

struct ReviewAccountingRestoreResult {
    let reviewedPhotoIDs: Set<String>
    let unreviewedPhotoIDs: Set<String>
}

struct GamificationFeedbackSnapshot {
    let newlyUnlockedAchievement: Achievement?
    let showAchievementBanner: Bool
    let streakMilestoneReached: Int?
    let showStreakCelebration: Bool

    init(service: GamificationService) {
        self.newlyUnlockedAchievement = service.newlyUnlockedAchievement
        self.showAchievementBanner = service.showAchievementBanner
        self.streakMilestoneReached = service.streakMilestoneReached
        self.showStreakCelebration = service.showStreakCelebration
    }

    func restore(to service: GamificationService) {
        service.newlyUnlockedAchievement = newlyUnlockedAchievement
        service.showAchievementBanner = showAchievementBanner
        service.streakMilestoneReached = streakMilestoneReached
        service.showStreakCelebration = showStreakCelebration
    }
}

struct UserStatsSnapshot {
    let totalReviewed: Int
    let totalDeleted: Int
    let totalKept: Int
    let storageFreed: Int64
    let sessionReviewCount: Int
    let currentStreak: Int
    let bestStreak: Int
    let dayStreak: Int
    let lastReviewDate: Date?
    let todayReviewCount: Int
    let todayDate: Date?
    let bestDayReviewCount: Int
    let dailyChallengeProgress: Int
    let dailyChallengeTarget: Int
    let dailyChallengeType: String
    let dailyChallengeDate: Date?

    init(stats: UserStats) {
        self.totalReviewed = stats.totalReviewed
        self.totalDeleted = stats.totalDeleted
        self.totalKept = stats.totalKept
        self.storageFreed = stats.storageFreed
        self.sessionReviewCount = stats.sessionReviewCount
        self.currentStreak = stats.currentStreak
        self.bestStreak = stats.bestStreak
        self.dayStreak = stats.dayStreak
        self.lastReviewDate = stats.lastReviewDate
        self.todayReviewCount = stats.todayReviewCount
        self.todayDate = stats.todayDate
        self.bestDayReviewCount = stats.bestDayReviewCount
        self.dailyChallengeProgress = stats.dailyChallengeProgress
        self.dailyChallengeTarget = stats.dailyChallengeTarget
        self.dailyChallengeType = stats.dailyChallengeType
        self.dailyChallengeDate = stats.dailyChallengeDate
    }

    func restore(to stats: UserStats) {
        stats.totalReviewed = totalReviewed
        stats.totalDeleted = totalDeleted
        stats.totalKept = totalKept
        stats.storageFreed = storageFreed
        stats.sessionReviewCount = sessionReviewCount
        stats.currentStreak = currentStreak
        stats.bestStreak = bestStreak
        stats.dayStreak = dayStreak
        stats.lastReviewDate = lastReviewDate
        stats.todayReviewCount = todayReviewCount
        stats.todayDate = todayDate
        stats.bestDayReviewCount = bestDayReviewCount
        stats.dailyChallengeProgress = dailyChallengeProgress
        stats.dailyChallengeTarget = dailyChallengeTarget
        stats.dailyChallengeType = dailyChallengeType
        stats.dailyChallengeDate = dailyChallengeDate
    }
}

@MainActor
final class ReviewAccountingService: ObservableObject {
    private let gamificationService: GamificationService

    init(gamificationService: GamificationService) {
        self.gamificationService = gamificationService
    }

    func recordKeep(photoID: String, stats: UserStats, context: ModelContext) throws {
        let challengeType = DailyChallengeType(rawValue: stats.dailyChallengeType) ?? .review
        try gamificationService.markPhotoReviewed(id: photoID, context: context)
        gamificationService.processPhotoReview(
            action: .keep,
            fileSize: 0,
            stats: stats,
            challengeType: challengeType,
            context: context
        )
    }

    func prepareImmediateDeletion(photoID: String, fileSize: Int64, stats: UserStats, context: ModelContext) throws -> ReviewAccountingSnapshot {
        let snapshot = makeSnapshot(for: [photoID], stats: stats, context: context)
        guard !snapshot.reviewedPhotoIDs.contains(photoID) else { return snapshot }

        let challengeType = DailyChallengeType(rawValue: stats.dailyChallengeType) ?? .review
        try gamificationService.markPhotoReviewed(id: photoID, context: context)
        gamificationService.processPhotoReview(
            action: .delete,
            fileSize: fileSize,
            stats: stats,
            challengeType: challengeType,
            context: context
        )

        return snapshot
    }

    func recordQueuedDeletionReview(photoID: String, stats: UserStats, context: ModelContext) throws {
        let challengeType = DailyChallengeType(rawValue: stats.dailyChallengeType) ?? .review
        try gamificationService.markPhotoReviewed(id: photoID, context: context)
        gamificationService.processQueuedDeletionReview(
            stats: stats,
            challengeType: challengeType,
            context: context
        )
    }

    func prepareDeletionBatch(items: [PendingDeletionItem], stats: UserStats, context: ModelContext) throws -> ReviewAccountingSnapshot {
        let photoIDs = items.map(\.id)
        let snapshot = makeSnapshot(for: photoIDs, stats: stats, context: context)
        let challengeType = DailyChallengeType(rawValue: stats.dailyChallengeType) ?? .review

        for item in items {
            if snapshot.reviewedPhotoIDs.contains(item.id) {
                gamificationService.processQueuedDeletionCommit(
                    fileSize: item.fileSize,
                    stats: stats,
                    challengeType: challengeType,
                    context: context
                )
            } else {
                try gamificationService.markPhotoReviewed(id: item.id, context: context)
                gamificationService.processPhotoReview(
                    action: .delete,
                    fileSize: item.fileSize,
                    stats: stats,
                    challengeType: challengeType,
                    context: context
                )
            }
        }

        return snapshot
    }

    func rollbackQueuedDeletionReviews(photoIDs: [String], stats: UserStats, context: ModelContext) throws {
        let photoIDs = Array(Set(photoIDs))
        guard !photoIDs.isEmpty else { return }

        let challengeType = DailyChallengeType(rawValue: stats.dailyChallengeType) ?? .review
        for photoID in photoIDs {
            try gamificationService.rollbackQueuedDeletionReview(
                id: photoID,
                stats: stats,
                challengeType: challengeType,
                context: context
            )
        }
        try context.save()
    }

    func save(context: ModelContext) throws {
        try context.save()
    }

    func makeSnapshot(for photoIDs: [String], stats: UserStats, context: ModelContext) -> ReviewAccountingSnapshot {
        let reviewedPhotoIDs = Set(photoIDs.filter { gamificationService.isPhotoReviewed(id: $0, context: context) })
        let unlockedAchievementIDs = (try? context.fetch(FetchDescriptor<UnlockedAchievement>())) ?? []

        return ReviewAccountingSnapshot(
            stats: UserStatsSnapshot(stats: stats),
            reviewedPhotoIDs: reviewedPhotoIDs,
            unlockedAchievementIDs: Set(unlockedAchievementIDs.map(\.achievementId)),
            feedback: GamificationFeedbackSnapshot(service: gamificationService)
        )
    }

    func restore(
        _ snapshot: ReviewAccountingSnapshot,
        affectedPhotoIDs: [String],
        stats: UserStats,
        context: ModelContext
    ) throws -> ReviewAccountingRestoreResult {
        snapshot.stats.restore(to: stats)
        snapshot.feedback.restore(to: gamificationService)

        for photoID in affectedPhotoIDs where !snapshot.reviewedPhotoIDs.contains(photoID) {
            if let reviewedPhoto = try fetchReviewedPhoto(id: photoID, context: context) {
                context.delete(reviewedPhoto)
            }
        }

        let unlockedAchievements = try context.fetch(FetchDescriptor<UnlockedAchievement>())
        for unlockedAchievement in unlockedAchievements where !snapshot.unlockedAchievementIDs.contains(unlockedAchievement.achievementId) {
            context.delete(unlockedAchievement)
        }

        try context.save()

        let affectedPhotoIDs = Set(affectedPhotoIDs)
        return ReviewAccountingRestoreResult(
            reviewedPhotoIDs: snapshot.reviewedPhotoIDs,
            unreviewedPhotoIDs: affectedPhotoIDs.subtracting(snapshot.reviewedPhotoIDs)
        )
    }

    func isPhotoReviewed(id: String, context: ModelContext) -> Bool {
        gamificationService.isPhotoReviewed(id: id, context: context)
    }

    func deleteAllReviewedPhotos(context: ModelContext) throws {
        try gamificationService.deleteAllReviewedPhotos(context: context)
    }

    private func fetchReviewedPhoto(id: String, context: ModelContext) throws -> ReviewedPhoto? {
        var descriptor = FetchDescriptor<ReviewedPhoto>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
