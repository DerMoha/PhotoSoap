import Foundation

struct Achievement: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let iconName: String
    let requirement: (UserStats) -> Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Achievement, rhs: Achievement) -> Bool {
        lhs.id == rhs.id
    }

    static let allAchievements: [Achievement] = [
        Achievement(
            id: "first_steps",
            title: "First Steps",
            description: "Review 10 photos",
            iconName: "figure.walk",
            requirement: { $0.totalReviewed >= 10 }
        ),
        Achievement(
            id: "spring_cleaning",
            title: "Spring Cleaning",
            description: "Delete 50 photos",
            iconName: "leaf.fill",
            requirement: { $0.totalDeleted >= 50 }
        ),
        Achievement(
            id: "memory_keeper",
            title: "Memory Keeper",
            description: "Keep 100 photos",
            iconName: "heart.fill",
            requirement: { $0.totalKept >= 100 }
        ),
        Achievement(
            id: "streak_master",
            title: "Streak Master",
            description: "Achieve a 25 photo streak",
            iconName: "flame.fill",
            requirement: { $0.bestStreak >= 25 }
        ),
        Achievement(
            id: "daily_devotee",
            title: "Daily Devotee",
            description: "Maintain a 7-day login streak",
            iconName: "calendar.badge.checkmark",
            requirement: { $0.dailyStreak >= 7 }
        ),
        Achievement(
            id: "storage_saver",
            title: "Storage Saver",
            description: "Free 1GB of storage space",
            iconName: "externaldrive.fill",
            requirement: { $0.storageFreed >= 1_073_741_824 }
        ),
        Achievement(
            id: "century_club",
            title: "Century Club",
            description: "Review 100 photos in one session",
            iconName: "star.circle.fill",
            requirement: { $0.sessionReviewCount >= 100 }
        ),
        Achievement(
            id: "photo_pro",
            title: "Photo Pro",
            description: "Review 1000 total photos",
            iconName: "crown.fill",
            requirement: { $0.totalReviewed >= 1000 }
        ),
        Achievement(
            id: "decisive",
            title: "Decisive",
            description: "Review 50 photos without breaking streak",
            iconName: "bolt.fill",
            requirement: { $0.bestStreak >= 50 }
        ),
        Achievement(
            id: "cleanup_champion",
            title: "Cleanup Champion",
            description: "Delete 500 photos",
            iconName: "trophy.fill",
            requirement: { $0.totalDeleted >= 500 }
        )
    ]

    static func checkNewAchievements(for stats: UserStats) -> [Achievement] {
        var newAchievements: [Achievement] = []

        for achievement in allAchievements {
            if !stats.hasUnlockedAchievement(achievement.id) && achievement.requirement(stats) {
                newAchievements.append(achievement)
            }
        }

        return newAchievements
    }

    static func getAchievement(by id: String) -> Achievement? {
        allAchievements.first { $0.id == id }
    }
}
