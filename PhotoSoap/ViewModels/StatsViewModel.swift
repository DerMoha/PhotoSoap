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

    struct MediaStatsItem: Identifiable {
        let mediaType: ReviewMediaType
        let reviewed: Int
        let deleted: Int
        let kept: Int
        let storageFreed: Int64

        var id: String { mediaType.rawValue }
        var title: String { mediaType.displayName }
        var iconName: String { mediaType.systemImage }
        var storageFreedFormatted: String { storageFreed.formattedBytes }
    }

    func getMainStats(from stats: UserStats) -> [StatItem] {
        stats.migrateLegacyMediaStatsIfNeeded()

        return [
            StatItem(
                title: String(localized: "stats.itemsReviewed", defaultValue: "Items Reviewed", table: "LocalizableStats"),
                value: "\(stats.totalReviewed)",
                iconName: "square.grid.2x2",
                color: .blue
            ),
            StatItem(
                title: String(localized: "stats.itemsDeleted", defaultValue: "Items Deleted", table: "LocalizableStats"),
                value: "\(stats.totalDeleted)",
                iconName: "trash",
                color: .red
            ),
            StatItem(
                title: String(localized: "stats.itemsKept", defaultValue: "Items Kept", table: "LocalizableStats"),
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

    func getMediaStats(from stats: UserStats) -> [MediaStatsItem] {
        stats.migrateLegacyMediaStatsIfNeeded()

        return [
            MediaStatsItem(
                mediaType: .photo,
                reviewed: stats.photosReviewed,
                deleted: stats.photosDeleted,
                kept: stats.photosKept,
                storageFreed: stats.photoStorageFreed
            ),
            MediaStatsItem(
                mediaType: .video,
                reviewed: stats.videosReviewed,
                deleted: stats.videosDeleted,
                kept: stats.videosKept,
                storageFreed: stats.videoStorageFreed
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
