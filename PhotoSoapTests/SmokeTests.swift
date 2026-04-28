import XCTest
import SwiftData
import Photos
@testable import PhotoSoap

final class SmokeTests: XCTestCase {
    func testIncrementReviewedUpdatesCoreStats() {
        let stats = UserStats()

        stats.incrementReviewed()
        stats.incrementKept()

        XCTAssertEqual(stats.totalReviewed, 1)
        XCTAssertEqual(stats.totalKept, 1)
        XCTAssertEqual(stats.totalDeleted, 0)
        XCTAssertEqual(stats.currentStreak, 1)
        XCTAssertEqual(stats.sessionReviewCount, 1)
    }

    @MainActor
    func testAnalyticsServiceIsDisabledByDefault() {
        let defaults = makeTestDefaults()

        let analyticsService = AnalyticsService(defaults: defaults, recorder: { _ in })

        XCTAssertFalse(analyticsService.isEnabled)
    }

    @MainActor
    func testAnalyticsServiceRecordsEventNameAndProperties() {
        let defaults = makeTestDefaults()

        let analyticsService = AnalyticsService(defaults: defaults, recorder: { _ in })
        analyticsService.setEnabled(true)

        analyticsService.track(.statsViewed())

        XCTAssertEqual(analyticsService.recordedEvents.count, 1)
        XCTAssertEqual(analyticsService.recordedEvents.first?.name, "stats_viewed")
        XCTAssertTrue(analyticsService.recordedEvents.first?.properties.isEmpty == true)
    }

    @MainActor
    func testAnalyticsServiceSkipsEventsWhenDisabled() {
        let defaults = makeTestDefaults()

        let analyticsService = AnalyticsService(defaults: defaults, recorder: { _ in })
        analyticsService.setEnabled(false)

        analyticsService.track(.statsViewed())

        XCTAssertFalse(analyticsService.isEnabled)
        XCTAssertTrue(analyticsService.recordedEvents.isEmpty)
    }

    @MainActor
    func testAnalyticsPreferencePersistsAcrossInstances() {
        let defaults = makeTestDefaults()

        let analyticsService = AnalyticsService(defaults: defaults, recorder: { _ in })
        analyticsService.setEnabled(true)

        let restoredService = AnalyticsService(defaults: defaults, recorder: { _ in })

        XCTAssertTrue(restoredService.isEnabled)
    }

    @MainActor
    func testHapticsServiceIsEnabledByDefault() {
        let defaults = makeTestDefaults()

        let hapticsService = HapticsService(defaults: defaults, performer: .init(
            impact: { _ in },
            success: {},
            error: {},
            warning: {},
            selection: {}
        ))

        XCTAssertTrue(hapticsService.isEnabled)
    }

    @MainActor
    func testHapticsServiceSkipsFeedbackWhenDisabled() {
        let defaults = makeTestDefaults()

        var feedbackEvents: [String] = []
        let performer = HapticsPerformer(
            impact: { _ in feedbackEvents.append("impact") },
            success: { feedbackEvents.append("success") },
            error: { feedbackEvents.append("error") },
            warning: { feedbackEvents.append("warning") },
            selection: { feedbackEvents.append("selection") }
        )
        let hapticsService = HapticsService(defaults: defaults, performer: performer)

        hapticsService.setEnabled(false)
        hapticsService.impact(.heavy)
        hapticsService.success()
        hapticsService.error()
        hapticsService.warning()
        hapticsService.selection()

        XCTAssertFalse(hapticsService.isEnabled)
        XCTAssertTrue(feedbackEvents.isEmpty)
    }

    @MainActor
    func testHapticsPreferencePersistsAcrossInstances() {
        let defaults = makeTestDefaults()

        let hapticsService = HapticsService(defaults: defaults, performer: .init(
            impact: { _ in },
            success: {},
            error: {},
            warning: {},
            selection: {}
        ))
        hapticsService.setEnabled(false)

        let restoredService = HapticsService(defaults: defaults, performer: .init(
            impact: { _ in },
            success: {},
            error: {},
            warning: {},
            selection: {}
        ))

        XCTAssertFalse(restoredService.isEnabled)
    }

    @MainActor
    func testAggregateMetricsRegistersInstallOnlyOnce() {
        let defaults = makeTestDefaults()
        let service = AggregateMetricsService(
            defaults: defaults,
            sink: TestAggregateMetricsSink(isConfigured: false),
            allowsAutomaticFlush: false
        )
        service.setEnabled(true)

        service.registerInstallIfNeeded()
        service.registerInstallIfNeeded()

        XCTAssertEqual(service.pendingMetrics.installs, 1)
    }

    @MainActor
    func testAggregateMetricsTrackReviewsDeletesAndSpaceFreed() {
        let defaults = makeTestDefaults()
        let service = AggregateMetricsService(
            defaults: defaults,
            sink: TestAggregateMetricsSink(isConfigured: false),
            allowsAutomaticFlush: false
        )
        service.setEnabled(true)

        service.recordReview()
        service.recordDeletion(bytesFreed: 4_096)

        XCTAssertEqual(service.pendingMetrics.reviewedPhotos, 2)
        XCTAssertEqual(service.pendingMetrics.deletedPhotos, 1)
        XCTAssertEqual(service.pendingMetrics.keptPhotos, 1)
        XCTAssertEqual(service.pendingMetrics.bytesFreed, 4_096)
    }

    @MainActor
    func testAggregateMetricsDoesNotFlushOnEveryReview() async {
        let defaults = makeTestDefaults()
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_776_000_000))
        let sink = TestAggregateMetricsSink()
        let service = AggregateMetricsService(
            defaults: defaults,
            sink: sink,
            allowsAutomaticFlush: true,
            now: { clock.now }
        )
        service.setEnabled(true)

        service.recordReview()
        await Task.yield()

        let payloads = await sink.payloads

        XCTAssertTrue(payloads.isEmpty)
        XCTAssertEqual(service.pendingMetrics.reviewedPhotos, 1)
    }

    @MainActor
    func testAggregateMetricsFlushesCumulativeDailyBucketAndRespectsDailyCadence() async {
        let defaults = makeTestDefaults()
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_776_000_000))
        let sink = TestAggregateMetricsSink()
        let service = AggregateMetricsService(
            defaults: defaults,
            sink: sink,
            allowsAutomaticFlush: true,
            now: { clock.now }
        )
        service.setEnabled(true)

        service.registerInstallIfNeeded()
        service.recordDeletion(bytesFreed: 2_048)
        await service.flushForTesting()

        var payloads = await sink.payloads
        XCTAssertEqual(payloads.count, 1)
        XCTAssertTrue(payloads.first?.registerInstall == true)
        XCTAssertEqual(payloads.first?.dailyBuckets.count, 1)
        XCTAssertEqual(payloads.first?.dailyBuckets.first?.reviewedPhotos, 1)
        XCTAssertEqual(payloads.first?.dailyBuckets.first?.deletedPhotos, 1)
        XCTAssertEqual(payloads.first?.dailyBuckets.first?.keptPhotos, 0)
        XCTAssertEqual(payloads.first?.dailyBuckets.first?.bytesFreed, 2_048)
        XCTAssertTrue(service.pendingMetrics.isEmpty)

        service.recordReview()
        service.flushPendingMetricsIfNeeded()
        await Task.yield()

        payloads = await sink.payloads
        XCTAssertEqual(payloads.count, 1)

        clock.now = clock.now.addingTimeInterval(24 * 60 * 60 + 1)
        service.flushPendingMetricsIfNeeded()
        await Task.yield()

        payloads = await sink.payloads
        XCTAssertEqual(payloads.count, 2)
        XCTAssertTrue(payloads.last?.registerInstall == false)
        XCTAssertEqual(payloads.last?.dailyBuckets.count, 1)
        XCTAssertEqual(payloads.last?.dailyBuckets.first?.reviewedPhotos, 2)
        XCTAssertEqual(payloads.last?.dailyBuckets.first?.deletedPhotos, 1)
        XCTAssertEqual(payloads.last?.dailyBuckets.first?.keptPhotos, 1)
        XCTAssertEqual(payloads.last?.dailyBuckets.first?.bytesFreed, 2_048)
        XCTAssertTrue(service.pendingMetrics.isEmpty)
    }

    @MainActor
    func testAggregateMetricsIgnoreCollectionWhenAnalyticsDisabled() async {
        let defaults = makeTestDefaults()
        let sink = TestAggregateMetricsSink()
        let service = AggregateMetricsService(
            defaults: defaults,
            sink: sink,
            allowsAutomaticFlush: false
        )

        service.registerInstallIfNeeded()
        service.recordReview()
        service.recordDeletion(bytesFreed: 1_024)
        await service.flushForTesting()

        let payloads = await sink.payloads

        XCTAssertFalse(service.isEnabled)
        XCTAssertTrue(service.pendingMetrics.isEmpty)
        XCTAssertTrue(payloads.isEmpty)
        XCTAssertNil(defaults.string(forKey: AggregateMetricsService.installIDKey))
    }

    func testIncrementDeletedTracksStorageFreed() {
        let stats = UserStats()

        stats.incrementReviewed()
        stats.incrementDeleted(fileSize: 2_048)

        XCTAssertEqual(stats.totalReviewed, 1)
        XCTAssertEqual(stats.totalDeleted, 1)
        XCTAssertEqual(stats.storageFreed, 2_048)
    }

    @MainActor
    func testReviewedPhotoPersistsInMemoryStore() throws {
        let container = try ModelContainer(
            for: ReviewedPhoto.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let review = ReviewedPhoto(id: "photo-1")

        context.insert(review)
        try context.save()

        let count = try context.fetchCount(FetchDescriptor<ReviewedPhoto>())

        XCTAssertEqual(count, 1)
        XCTAssertEqual(review.id, "photo-1")
    }

    @MainActor
    func testAuthorizationStatusMappingCoversPermissionEdges() {
        XCTAssertEqual(PhotoLibraryService.mappedAuthorizationStatus(from: .notDetermined), .notDetermined)
        XCTAssertEqual(PhotoLibraryService.mappedAuthorizationStatus(from: .authorized), .authorized)
        XCTAssertEqual(PhotoLibraryService.mappedAuthorizationStatus(from: .denied), .denied)
        XCTAssertEqual(PhotoLibraryService.mappedAuthorizationStatus(from: .restricted), .restricted)
        XCTAssertEqual(PhotoLibraryService.mappedAuthorizationStatus(from: .limited), .limited)
    }

    func testBootstrapFallsBackToRecoveryModeWhenPersistentStoreFails() throws {
        enum TestError: Error {
            case persistentStoreFailed
        }

        let result = PhotoSoapApp.bootstrapContainer { schema, configuration in
            if configuration.isStoredInMemoryOnly {
                return try ModelContainer(for: schema, configurations: [configuration])
            }

            throw TestError.persistentStoreFailed
        }

        XCTAssertNotNil(result.bootstrapErrorMessage)
        XCTAssertTrue(result.bootstrapErrorMessage?.contains("temporary recovery mode") == true)
        XCTAssertNotNil(result.modelContainer)
    }

}

private func makeTestDefaults() -> UserDefaults {
    let suiteName = "PhotoSoapTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private actor TestAggregateMetricsSink: AggregateMetricsSink {
    let isConfigured: Bool
    private(set) var payloads: [AggregateMetricsPayload] = []

    init(isConfigured: Bool = true) {
        self.isConfigured = isConfigured
    }

    func send(_ payload: AggregateMetricsPayload) async throws {
        guard isConfigured else {
            throw MetricsError.notConfigured
        }

        payloads.append(payload)
    }
}

private final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}
