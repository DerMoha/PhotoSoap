import Foundation

enum DailyChallengeType: String, CaseIterable {
    case review = "review"
    case delete = "delete"
    case streak = "streak"

    var verb: String {
        switch self {
        case .review: return String(localized: "challenge.review", defaultValue: "Review", table: "LocalizableReview")
        case .delete: return String(localized: "challenge.delete", defaultValue: "Delete", table: "LocalizableReview")
        case .streak: return String(localized: "challenge.streak", defaultValue: "Maintain a streak of", table: "LocalizableReview")
        }
    }

    var unit: String {
        switch self {
        case .review, .delete: return String(localized: "common.photos", defaultValue: "photos", table: "LocalizableShared")
        case .streak: return String(localized: "common.photos", defaultValue: "photos", table: "LocalizableShared")
        }
    }
}

protocol DailyChallengeStats {
    var dailyChallengeProgress: Int { get }
    var dailyChallengeTarget: Int { get }
    var currentStreak: Int { get }
}

struct DailyChallenge: Identifiable {
    let id: UUID
    let type: DailyChallengeType
    let target: Int
    let date: Date

    var title: String {
        switch type {
        case .review, .delete:
            return "\(type.verb) \(target) \(type.unit)"
        case .streak:
            return String(localized: "challenge.streak.title", defaultValue: "%d-photo streak", table: "LocalizableReview")
                .replacingOccurrences(of: "%d", with: "\(target)")
        }
    }

    var compactTitle: String {
        switch type {
        case .review, .delete:
            return type.verb
        case .streak:
            return String(localized: "challenge.streak.short", defaultValue: "Streak", table: "LocalizableReview")
        }
    }

    var description: String {
        switch type {
        case .review:
            return String(localized: "challenge.description.review", defaultValue: "Review \(target) photos today to complete this challenge", table: "LocalizableReview").replacingOccurrences(of: "%d", with: "\(target)")
        case .delete:
            return String(localized: "challenge.description.delete", defaultValue: "Delete \(target) photos today to free up space", table: "LocalizableReview").replacingOccurrences(of: "%d", with: "\(target)")
        case .streak:
            return String(localized: "challenge.description.streak", defaultValue: "Maintain a streak of \(target) consecutive photo reviews", table: "LocalizableReview").replacingOccurrences(of: "%d", with: "\(target)")
        }
    }

    var iconName: String {
        switch type {
        case .review: return "photo.stack"
        case .delete: return "trash"
        case .streak: return "flame"
        }
    }

    static func generateForToday() -> DailyChallenge {
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: Date()) ?? 1

        let challengeTypes: [DailyChallengeType] = [.review, .delete, .streak]
        let typeIndex = dayOfYear % challengeTypes.count
        let type = challengeTypes[typeIndex]

        let target: Int
        switch type {
        case .review:
            let targets = [20, 30, 40, 50]
            target = targets[dayOfYear % targets.count]
        case .delete:
            let targets = [10, 15, 20, 25]
            target = targets[dayOfYear % targets.count]
        case .streak:
            let targets = [10, 15, 20, 25]
            target = targets[dayOfYear % targets.count]
        }

        return DailyChallenge(
            id: UUID(),
            type: type,
            target: target,
            date: Date()
        )
    }

    func progress(from stats: DailyChallengeStats) -> Int {
        switch type {
        case .review:
            return stats.dailyChallengeProgress
        case .delete:
            return stats.dailyChallengeProgress
        case .streak:
            return stats.currentStreak
        }
    }

    func isComplete(stats: DailyChallengeStats) -> Bool {
        progress(from: stats) >= target
    }

    var progressPercentage: (DailyChallengeStats) -> Double {
        { stats in
            min(1.0, Double(progress(from: stats)) / Double(target))
        }
    }
}
