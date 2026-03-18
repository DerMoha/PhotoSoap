import Foundation
import SwiftData

@Model
class UserStats: DailyChallengeStats {
    var totalReviewed: Int
    var totalDeleted: Int
    var totalKept: Int
    var currentStreak: Int
    var bestStreak: Int
    var dailyStreak: Int
    var lastReviewDate: Date?
    var lastLoginDate: Date?
    var storageFreed: Int64
    var reviewedPhotoIDs: [String]
    
    // Maximum number of photo IDs to retain (prevents unbounded memory growth)
    // Maximum number of photo IDs to retain (prevents unbounded memory growth)
    // @Transient private static let maxReviewedPhotoIDs = 20000 (Removed)
    var unlockedAchievements: [String]
    var dailyChallengeProgress: Int
    var dailyChallengeTarget: Int
    var dailyChallengeType: String
    var dailyChallengeDate: Date?
    var sessionReviewCount: Int

    init() {
        self.totalReviewed = 0
        self.totalDeleted = 0
        self.totalKept = 0
        self.currentStreak = 0
        self.bestStreak = 0
        self.dailyStreak = 0
        self.lastReviewDate = nil
        self.lastLoginDate = nil
        self.storageFreed = 0
        self.reviewedPhotoIDs = []
        self.unlockedAchievements = []
        self.dailyChallengeProgress = 0
        self.dailyChallengeTarget = 30
        self.dailyChallengeType = "review"
        self.dailyChallengeDate = nil
        self.sessionReviewCount = 0
    }

    func incrementReviewed() {
        totalReviewed += 1
        currentStreak += 1
        sessionReviewCount += 1
        lastReviewDate = Date()

        if currentStreak > bestStreak {
            bestStreak = currentStreak
        }
    }

    func incrementDeleted(fileSize: Int64 = 0) {
        totalDeleted += 1
        storageFreed += fileSize
    }

    func incrementKept() {
        totalKept += 1
    }

    func resetStreak() {
        currentStreak = 0
    }

    func updateDailyStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let lastLogin = lastLoginDate {
            let lastLoginDay = calendar.startOfDay(for: lastLogin)
            let daysDifference = calendar.dateComponents([.day], from: lastLoginDay, to: today).day ?? 0

            if daysDifference == 1 {
                dailyStreak += 1
            } else if daysDifference > 1 {
                dailyStreak = 1
            }
        } else {
            dailyStreak = 1
        }

        lastLoginDate = Date()
    }

    // MARK: - Legacy / Migration
    // Kept only for migration in PhotoSoapApp.swift. Do not use for new logic.
    // Logic moved to ReviewedPhoto model.
    @available(*, deprecated, message: "Use GameificationService.markPhotoReviewed instead")
    func markPhotoReviewed(_ photoID: String) {
        // No-op - moved to GameificationService & ReviewedPhoto
    }

    @available(*, deprecated, message: "Use PhotoLibraryService.isReviewed instead")
    func hasReviewedPhoto(_ photoID: String) -> Bool {
        // No-op - deprecated
        return false
    }

    func unlockAchievement(_ achievementID: String) {
        if !unlockedAchievements.contains(achievementID) {
            unlockedAchievements.append(achievementID)
        }
    }

    func hasUnlockedAchievement(_ achievementID: String) -> Bool {
        unlockedAchievements.contains(achievementID)
    }

    func updateDailyChallengeProgress(for type: DailyChallengeType) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let challengeDate = dailyChallengeDate {
            let challengeDay = calendar.startOfDay(for: challengeDate)
            if challengeDay != today {
                resetDailyChallenge()
            }
        } else {
            resetDailyChallenge()
        }

        if dailyChallengeType == type.rawValue {
            dailyChallengeProgress += 1
        }
    }

    func resetDailyChallenge() {
        dailyChallengeProgress = 0
        dailyChallengeDate = Date()
        let challenge = DailyChallenge.generateForToday()
        dailyChallengeTarget = challenge.target
        dailyChallengeType = challenge.type.rawValue
    }

    func isDailyChallengeComplete() -> Bool {
        dailyChallengeProgress >= dailyChallengeTarget
    }

    func updateDailyChallengeTarget(_ target: Int) {
        dailyChallengeTarget = target
    }

    var storageFreedFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: storageFreed)
    }
}
