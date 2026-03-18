import Foundation
import SwiftUI

@MainActor
final class StatsViewModel {

    struct StatItem: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        let iconName: String
        let color: Color
    }

    func getMainStats(from stats: UserStats) -> [StatItem] {
        [
            StatItem(
                title: "Photos Reviewed",
                value: "\(stats.totalReviewed)",
                iconName: "photo.stack",
                color: .blue
            ),
            StatItem(
                title: "Photos Deleted",
                value: "\(stats.totalDeleted)",
                iconName: "trash",
                color: .red
            ),
            StatItem(
                title: "Photos Kept",
                value: "\(stats.totalKept)",
                iconName: "heart.fill",
                color: .green
            ),
            StatItem(
                title: "Storage Freed",
                value: stats.storageFreedFormatted,
                iconName: "externaldrive.fill",
                color: .orange
            )
        ]
    }

    func getStreakStats(from stats: UserStats) -> [StatItem] {
        [
            StatItem(
                title: "Current Streak",
                value: "\(stats.currentStreak)",
                iconName: "flame",
                color: .orange
            ),
            StatItem(
                title: "Best Streak",
                value: "\(stats.bestStreak)",
                iconName: "flame.fill",
                color: .red
            ),
            StatItem(
                title: "Daily Streak",
                value: "\(stats.dailyStreak) days",
                iconName: "calendar",
                color: .purple
            ),
            StatItem(
                title: "Session Reviews",
                value: "\(stats.sessionReviewCount)",
                iconName: "clock",
                color: .blue
            )
        ]
    }

    func getDeleteRatio(from stats: UserStats) -> Double {
        guard stats.totalReviewed > 0 else { return 0 }
        return Double(stats.totalDeleted) / Double(stats.totalReviewed)
    }

    func getKeepRatio(from stats: UserStats) -> Double {
        guard stats.totalReviewed > 0 else { return 0 }
        return Double(stats.totalKept) / Double(stats.totalReviewed)
    }

    func getFormattedLastReviewDate(from stats: UserStats) -> String {
        guard let date = stats.lastReviewDate else {
            return "Never"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
