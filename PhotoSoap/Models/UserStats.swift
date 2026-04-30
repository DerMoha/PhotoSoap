import Foundation
import SwiftData

@Model
class UserStats {
    // MARK: - Core Stats
    var totalReviewed: Int
    var totalDeleted: Int
    var totalKept: Int
    var storageFreed: Int64
    var sessionReviewCount: Int

    // MARK: - Streak Tracking
    var currentStreak: Int
    var bestStreak: Int
    var dayStreak: Int
    var lastReviewDate: Date?
    var todayReviewCount: Int
    var todayDate: Date?
    var bestDayReviewCount: Int

    // MARK: - Daily Challenge
    var dailyChallengeProgress: Int
    var dailyChallengeTarget: Int
    var dailyChallengeType: String
    var dailyChallengeDate: Date?

    init() {
        self.totalReviewed = 0
        self.totalDeleted = 0
        self.totalKept = 0
        self.storageFreed = 0
        self.sessionReviewCount = 0

        self.currentStreak = 0
        self.bestStreak = 0
        self.dayStreak = 0
        self.lastReviewDate = nil
        self.todayReviewCount = 0
        self.todayDate = nil
        self.bestDayReviewCount = 0

        self.dailyChallengeProgress = 0
        self.dailyChallengeTarget = 30
        self.dailyChallengeType = "review"
        self.dailyChallengeDate = nil
    }

    // MARK: - Core Actions

    func incrementReviewed() {
        totalReviewed += 1
        currentStreak += 1
        sessionReviewCount += 1
        lastReviewDate = Date()

        if currentStreak > bestStreak {
            bestStreak = currentStreak
        }

        updateDayTracking()
    }

    func decrementQueuedReview() {
        totalReviewed = max(0, totalReviewed - 1)
        currentStreak = max(0, currentStreak - 1)
        sessionReviewCount = max(0, sessionReviewCount - 1)

        if let todayDate, Calendar.current.isDateInToday(todayDate) {
            todayReviewCount = max(0, todayReviewCount - 1)
            if todayReviewCount == 0 {
                self.todayDate = nil
                dayStreak = max(0, dayStreak - 1)
            }
        }
    }

    func incrementDeleted(fileSize: Int64 = 0) {
        totalDeleted += 1
        storageFreed += fileSize
    }

    func incrementQueuedDeletionCommit(fileSize: Int64 = 0) {
        incrementDeleted(fileSize: fileSize)
    }

    func incrementKept() {
        totalKept += 1
    }

    func resetStreak() {
        currentStreak = 0
    }

    // MARK: - Day Tracking

    private func updateDayTracking() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let storedDate = todayDate {
            let storedDay = calendar.startOfDay(for: storedDate)
            if storedDay == today {
                todayReviewCount += 1
            } else {
                let daysDifference = calendar.dateComponents([.day], from: storedDay, to: today).day ?? 0
                if daysDifference == 1 {
                    dayStreak += 1
                } else if daysDifference > 1 {
                    dayStreak = 1
                }
                todayReviewCount = 1
                todayDate = Date()
            }
        } else {
            todayReviewCount = 1
            todayDate = Date()
            dayStreak = 1
        }

        if todayReviewCount > bestDayReviewCount {
            bestDayReviewCount = todayReviewCount
        }
    }

    // MARK: - Daily Challenge

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

    func decrementDailyChallengeProgress(for type: DailyChallengeType) {
        guard dailyChallengeType == type.rawValue else { return }
        dailyChallengeProgress = max(0, dailyChallengeProgress - 1)
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

    // MARK: - Formatting

    var storageFreedFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: storageFreed)
    }

    static func fetchOrCreateSingleton(in context: ModelContext) throws -> UserStats {
        let descriptor = FetchDescriptor<UserStats>()
        let allStats = try context.fetch(descriptor)

        guard let primaryStats = allStats.first else {
            let newStats = UserStats()
            context.insert(newStats)
            return newStats
        }

        for duplicateStats in allStats.dropFirst() {
            primaryStats.mergeDuplicate(duplicateStats)
            context.delete(duplicateStats)
        }

        return primaryStats
    }

    private func mergeDuplicate(_ duplicate: UserStats) {
        totalReviewed += duplicate.totalReviewed
        totalDeleted += duplicate.totalDeleted
        totalKept += duplicate.totalKept
        storageFreed += duplicate.storageFreed
        sessionReviewCount += duplicate.sessionReviewCount

        currentStreak = max(currentStreak, duplicate.currentStreak)
        bestStreak = max(bestStreak, duplicate.bestStreak)
        dayStreak = max(dayStreak, duplicate.dayStreak)
        lastReviewDate = latestDate(lastReviewDate, duplicate.lastReviewDate)

        if isSameDay(todayDate, duplicate.todayDate) {
            todayReviewCount += duplicate.todayReviewCount
        } else if isLaterDate(duplicate.todayDate, than: todayDate) {
            todayDate = duplicate.todayDate
            todayReviewCount = duplicate.todayReviewCount
        }
        bestDayReviewCount = max(max(bestDayReviewCount, duplicate.bestDayReviewCount), todayReviewCount)

        mergeDailyChallenge(from: duplicate)
    }

    private func mergeDailyChallenge(from duplicate: UserStats) {
        if isSameDay(dailyChallengeDate, duplicate.dailyChallengeDate), dailyChallengeType == duplicate.dailyChallengeType {
            dailyChallengeProgress = max(dailyChallengeProgress, duplicate.dailyChallengeProgress)
            dailyChallengeTarget = max(dailyChallengeTarget, duplicate.dailyChallengeTarget)
        } else if isLaterDate(duplicate.dailyChallengeDate, than: dailyChallengeDate) {
            dailyChallengeProgress = duplicate.dailyChallengeProgress
            dailyChallengeTarget = duplicate.dailyChallengeTarget
            dailyChallengeType = duplicate.dailyChallengeType
            dailyChallengeDate = duplicate.dailyChallengeDate
        }
    }

    private func isSameDay(_ lhs: Date?, _ rhs: Date?) -> Bool {
        guard let lhs, let rhs else { return false }
        return Calendar.current.isDate(lhs, inSameDayAs: rhs)
    }

    private func isLaterDate(_ lhs: Date?, than rhs: Date?) -> Bool {
        guard let lhs else { return false }
        guard let rhs else { return true }
        return lhs > rhs
    }

    private func latestDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return max(lhs, rhs)
    }
}

extension UserStats: DailyChallengeStats {}
