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
                title: String(localized: "stats.photosReviewed", defaultValue: "Photos Reviewed", table: "LocalizableStats"),
                value: "\(stats.totalReviewed)",
                iconName: "photo.stack",
                color: .blue
            ),
            StatItem(
                title: String(localized: "stats.photosDeleted", defaultValue: "Photos Deleted", table: "LocalizableStats"),
                value: "\(stats.totalDeleted)",
                iconName: "trash",
                color: .red
            ),
            StatItem(
                title: String(localized: "stats.photosKept", defaultValue: "Photos Kept", table: "LocalizableStats"),
                value: "\(stats.totalKept)",
                iconName: "heart.fill",
                color: .green
            ),
            StatItem(
                title: String(localized: "stats.storageFreed", defaultValue: "Storage Freed", table: "LocalizableStats"),
                value: stats.storageFreedFormatted,
                iconName: "externaldrive.fill",
                color: .orange
            )
        ]
    }

    func getStreakStats(from stats: UserStats) -> [StatItem] {
        [
            StatItem(
                title: String(localized: "stats.todayReviews", defaultValue: "Reviewed Today", table: "LocalizableStats"),
                value: "\(stats.todayReviewCount)",
                iconName: "flame",
                color: .orange
            ),
            StatItem(
                title: String(localized: "stats.dayStreak", defaultValue: "Reviewed Days in a Row", table: "LocalizableStats"),
                value: "\(stats.dayStreak)",
                iconName: "calendar",
                color: .purple
            ),
            StatItem(
                title: String(localized: "stats.bestDayReviews", defaultValue: "Most in a Day", table: "LocalizableStats"),
                value: "\(stats.bestDayReviewCount)",
                iconName: "trophy.fill",
                color: .yellow
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
            return String(localized: "common.never", defaultValue: "Never", table: "LocalizableStats")
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
