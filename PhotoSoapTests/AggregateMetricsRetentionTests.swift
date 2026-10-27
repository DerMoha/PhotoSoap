import XCTest
@testable import PhotoSoap

final class AggregateMetricsRetentionTests: XCTestCase {
    @MainActor
    func testPersistedMetricsOutsideServerRetentionWindowArePruned() throws {
        let defaults = UserDefaults(suiteName: "AggregateMetricsRetentionTests.\(UUID().uuidString)")!
        defaults.set(true, forKey: AnalyticsService.analyticsEnabledKey)

        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-29T12:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let buckets = try (0..<15).map { offset in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: -offset, to: now))
            return StoredBucket(
                metricDate: formatter.string(from: date),
                reviewedPhotos: 1,
                deletedPhotos: 0,
                keptPhotos: 1,
                bytesFreed: 0,
                updatedAt: date,
                isDirty: true
            )
        }
        let state = StoredState(dailyBuckets: buckets)
        defaults.set(try JSONEncoder().encode(state), forKey: AggregateMetricsService.pendingMetricsKey)

        let service = AggregateMetricsService(
            defaults: defaults,
            sink: UnconfiguredAggregateMetricsSink(),
            allowsAutomaticFlush: false,
            now: { now }
        )

        XCTAssertEqual(service.pendingMetrics.reviewedPhotos, 14)
        XCTAssertEqual(service.pendingMetrics.keptPhotos, 14)
    }
}

private struct StoredState: Encodable {
    var pendingInstallRegistration = false
    let dailyBuckets: [StoredBucket]
    var lastSuccessfulFlushAt: Date?
    var nextRetryAt: Date?
    var consecutiveTransientFailures = 0
}

private struct StoredBucket: Encodable {
    let metricDate: String
    let reviewedPhotos: Int
    let deletedPhotos: Int
    let keptPhotos: Int
    let bytesFreed: Int64
    let updatedAt: Date
    let isDirty: Bool
}
