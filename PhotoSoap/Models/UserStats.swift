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

    // MARK: - Media Stats
    // These counters are kept separately so the app can show useful video-specific stats
    // while the core counters above continue to drive shared streaks and achievements.
    var photosReviewed: Int = 0
    var photosDeleted: Int = 0
    var photosKept: Int = 0
    var photoStorageFreed: Int64 = 0
    var videosReviewed: Int = 0
    var videosDeleted: Int = 0
    var videosKept: Int = 0
    var videoStorageFreed: Int64 = 0
    var mediaStatsMigrationVersion: Int = 0

    private static let currentMediaStatsMigrationVersion = 1

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

        self.photosReviewed = 0
        self.photosDeleted = 0
        self.photosKept = 0
        self.photoStorageFreed = 0
        self.videosReviewed = 0
        self.videosDeleted = 0
        self.videosKept = 0
        self.videoStorageFreed = 0
        self.mediaStatsMigrationVersion = Self.currentMediaStatsMigrationVersion

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

    func incrementReviewed(mediaType: ReviewMediaType = .photo) {
        migrateLegacyMediaStatsIfNeeded()
        totalReviewed += 1

        switch mediaType {
        case .photo:
            photosReviewed += 1
        case .video:
            videosReviewed += 1
        }

        currentStreak += 1
        sessionReviewCount += 1
        lastReviewDate = Date()

        if currentStreak > bestStreak {
            bestStreak = currentStreak
        }

        updateDayTracking()
    }

    func decrementQueuedReview(mediaType: ReviewMediaType = .photo) {
        migrateLegacyMediaStatsIfNeeded()
        totalReviewed = max(0, totalReviewed - 1)

        switch mediaType {
        case .photo:
            photosReviewed = max(0, photosReviewed - 1)
        case .video:
            videosReviewed = max(0, videosReviewed - 1)
        }

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

    func incrementDeleted(fileSize: Int64 = 0, mediaType: ReviewMediaType = .photo) {
        migrateLegacyMediaStatsIfNeeded()
        totalDeleted += 1
        storageFreed += fileSize

        switch mediaType {
        case .photo:
            photosDeleted += 1
            photoStorageFreed += fileSize
        case .video:
            videosDeleted += 1
            videoStorageFreed += fileSize
        }
    }

    func incrementQueuedDeletionCommit(fileSize: Int64 = 0, mediaType: ReviewMediaType = .photo) {
        incrementDeleted(fileSize: fileSize, mediaType: mediaType)
    }

    func incrementKept(mediaType: ReviewMediaType = .photo) {
        migrateLegacyMediaStatsIfNeeded()
        totalKept += 1

        switch mediaType {
        case .photo:
            photosKept += 1
        case .video:
            videosKept += 1
        }
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
        storageFreed.formattedBytes
    }

    func migrateLegacyMediaStatsIfNeeded() {
        guard mediaStatsMigrationVersion < Self.currentMediaStatsMigrationVersion else { return }

        let hasMediaStats = photosReviewed > 0
            || photosDeleted > 0
            || photosKept > 0
            || photoStorageFreed > 0
            || videosReviewed > 0
            || videosDeleted > 0
            || videosKept > 0
            || videoStorageFreed > 0

        if !hasMediaStats {
            photosReviewed = max(0, totalReviewed)
            photosDeleted = max(0, totalDeleted)
            photosKept = max(0, totalKept)
            photoStorageFreed = max(0, storageFreed)
        }

        mediaStatsMigrationVersion = Self.currentMediaStatsMigrationVersion
    }

    static func fetchOrCreateSingleton(in context: ModelContext) throws -> UserStats {
        let descriptor = FetchDescriptor<UserStats>()
        let allStats = try context.fetch(descriptor)

        guard let primaryStats = allStats.first else {
            let newStats = UserStats()
            context.insert(newStats)
            return newStats
        }

        primaryStats.migrateLegacyMediaStatsIfNeeded()

        for duplicateStats in allStats.dropFirst() {
            primaryStats.mergeDuplicate(duplicateStats)
            context.delete(duplicateStats)
        }

        return primaryStats
    }

    private func mergeDuplicate(_ duplicate: UserStats) {
        migrateLegacyMediaStatsIfNeeded()
        duplicate.migrateLegacyMediaStatsIfNeeded()

        totalReviewed += duplicate.totalReviewed
        totalDeleted += duplicate.totalDeleted
        totalKept += duplicate.totalKept
        storageFreed += duplicate.storageFreed
        sessionReviewCount += duplicate.sessionReviewCount

        photosReviewed += duplicate.photosReviewed
        photosDeleted += duplicate.photosDeleted
        photosKept += duplicate.photosKept
        photoStorageFreed += duplicate.photoStorageFreed
        videosReviewed += duplicate.videosReviewed
        videosDeleted += duplicate.videosDeleted
        videosKept += duplicate.videosKept
        videoStorageFreed += duplicate.videoStorageFreed
        mediaStatsMigrationVersion = Self.currentMediaStatsMigrationVersion

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
