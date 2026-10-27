import Foundation

struct Achievement: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let iconName: String

    static let allAchievements: [Achievement] = [
        Achievement(
            id: "first_steps",
            title: "First Steps",
            description: "Review 50 items",
            iconName: "figure.walk"
        ),
        Achievement(
            id: "spring_cleaning",
            title: "Spring Cleaning",
            description: "Delete 200 items",
            iconName: "leaf.fill"
        ),
        Achievement(
            id: "memory_keeper",
            title: "Memory Keeper",
            description: "Keep 500 items",
            iconName: "heart.fill"
        ),
        Achievement(
            id: "streak_master",
            title: "Streak Master",
            description: "Achieve a 100-item streak",
            iconName: "flame.fill"
        ),
        Achievement(
            id: "daily_devotee",
            title: "Daily Devotee",
            description: "Review items 14 days in a row",
            iconName: "calendar.badge.checkmark"
        ),
        Achievement(
            id: "storage_saver",
            title: "Storage Saver",
            description: "Free 5GB of storage space",
            iconName: "externaldrive.fill"
        ),
        Achievement(
            id: "century_club",
            title: "Century Club",
            description: "Review 500 items in one session",
            iconName: "star.circle.fill"
        ),
        Achievement(
            id: "photo_pro",
            title: "Media Pro",
            description: "Review 5000 total items",
            iconName: "crown.fill"
        ),
        Achievement(
            id: "decisive",
            title: "Decisive",
            description: "Review 200 items without breaking streak",
            iconName: "bolt.fill"
        ),
        Achievement(
            id: "cleanup_champion",
            title: "Cleanup Champion",
            description: "Delete 2000 items",
            iconName: "trophy.fill"
        )
    ]

    static func getAchievement(by id: String) -> Achievement? {
        allAchievements.first { $0.id == id }
    }
}
