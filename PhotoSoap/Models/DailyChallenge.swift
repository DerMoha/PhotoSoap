import Foundation

enum DailyChallengeType: String, CaseIterable {
    case review = "review"
    case delete = "delete"
    case streak = "streak"

    var verb: String {
        switch self {
        case .review: return "Review"
        case .delete: return "Delete"
        case .streak: return "Maintain a streak of"
        }
    }

    var unit: String {
        switch self {
        case .review, .delete: return "photos"
        case .streak: return "photos"
        }
    }
}

struct DailyChallenge: Identifiable {
    let id: UUID
    let type: DailyChallengeType
    let target: Int
    let date: Date

    var title: String {
        "\(type.verb) \(target) \(type.unit)"
    }

    var description: String {
        switch type {
        case .review:
            return "Review \(target) photos today to complete this challenge"
        case .delete:
            return "Delete \(target) photos today to free up space"
        case .streak:
            return "Maintain a streak of \(target) consecutive photo reviews"
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

    func progress(from stats: UserStats) -> Int {
        switch type {
        case .review:
            return stats.dailyChallengeProgress
        case .delete:
            return stats.dailyChallengeProgress
        case .streak:
            return stats.currentStreak
        }
    }

    func isComplete(stats: UserStats) -> Bool {
        progress(from: stats) >= target
    }

    var progressPercentage: (UserStats) -> Double {
        { stats in
            min(1.0, Double(progress(from: stats)) / Double(target))
        }
    }
}
