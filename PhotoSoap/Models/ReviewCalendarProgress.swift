import Foundation

nonisolated struct ReviewCalendarProgress: Sendable {
    private(set) var monthsByYear: [Int: [Int: ReviewMonthProgress]] = [:]

    mutating func record(creationDate: Date?, isReviewed: Bool, calendar: Calendar = .current) {
        guard let creationDate else { return }
        let year = calendar.component(.year, from: creationDate)
        let month = calendar.component(.month, from: creationDate)
        var progress = monthsByYear[year]?[month] ?? ReviewMonthProgress()
        progress.totalCount += 1
        if isReviewed {
            progress.reviewedCount += 1
        }
        monthsByYear[year, default: [:]][month] = progress
    }

    func progress(for year: Int) -> ReviewMonthProgress {
        (monthsByYear[year] ?? [:]).values.reduce(ReviewMonthProgress()) { total, month in
            ReviewMonthProgress(
                totalCount: total.totalCount + month.totalCount,
                reviewedCount: total.reviewedCount + month.reviewedCount
            )
        }
    }
}

nonisolated struct ReviewMonthProgress: Sendable, Equatable {
    var totalCount = 0
    var reviewedCount = 0

    var fraction: Double {
        totalCount > 0 ? Double(reviewedCount) / Double(totalCount) : 0
    }

    var displayFraction: Double {
        isComplete ? 1 : min(0.99, fraction)
    }

    var isComplete: Bool {
        totalCount > 0 && reviewedCount == totalCount
    }
}
