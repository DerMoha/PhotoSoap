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
            description: "Review 10 photos",
            iconName: "figure.walk"
        ),
        Achievement(
            id: "spring_cleaning",
            title: "Spring Cleaning",
            description: "Delete 50 photos",
            iconName: "leaf.fill"
        ),
        Achievement(
            id: "memory_keeper",
            title: "Memory Keeper",
            description: "Keep 100 photos",
            iconName: "heart.fill"
        ),
        Achievement(
            id: "streak_master",
            title: "Streak Master",
            description: "Achieve a 25 photo streak",
            iconName: "flame.fill"
        ),
        Achievement(
            id: "daily_devotee",
            title: "Daily Devotee",
            description: "Maintain a 7-day login streak",
            iconName: "calendar.badge.checkmark"
        ),
        Achievement(
            id: "storage_saver",
            title: "Storage Saver",
            description: "Free 1GB of storage space",
            iconName: "externaldrive.fill"
        ),
        Achievement(
            id: "century_club",
            title: "Century Club",
            description: "Review 100 photos in one session",
            iconName: "star.circle.fill"
        ),
        Achievement(
            id: "photo_pro",
            title: "Photo Pro",
            description: "Review 1000 total photos",
            iconName: "crown.fill"
        ),
        Achievement(
            id: "decisive",
            title: "Decisive",
            description: "Review 50 photos without breaking streak",
            iconName: "bolt.fill"
        ),
        Achievement(
            id: "cleanup_champion",
            title: "Cleanup Champion",
            description: "Delete 500 photos",
            iconName: "trophy.fill"
        )
    ]

    static func getAchievement(by id: String) -> Achievement? {
        allAchievements.first { $0.id == id }
    }
}
