import XCTest
import SwiftData
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
        XCTAssertFalse(AnalyticsService.isEnabled(in: defaults))
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

    func testReviewMediaKindDefaultsToPhotosFirst() {
        XCTAssertEqual(ReviewMediaKind.allCases.map(\.rawValue), ["photos", "videos", "all"])
    }

    func testPhotoFileSizeDisplayTextTreatsNonPositiveSizesAsUnknown() {
        XCTAssertNil(Photo.formattedFileSizeText(0))
        XCTAssertNil(Photo.formattedFileSizeText(-1))
        XCTAssertEqual(Photo.formattedFileSizeText(4_096), Int64(4_096).formattedBytes)
    }

    func testReviewAnalyticsIncludesMediaTypeWithoutRenamingEvents() {
        let event = AnalyticsEvent.filterApplied(.all, mediaKind: .videos)

        XCTAssertEqual(event.name, "filter_applied")
        XCTAssertEqual(event.properties["filter"], "all")
        XCTAssertEqual(event.properties["media_type"], "video")
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
    func testAggregateMetricsTrackBatchDeletesByCount() {
        let defaults = makeTestDefaults()
        let service = AggregateMetricsService(
            defaults: defaults,
            sink: TestAggregateMetricsSink(isConfigured: false),
            allowsAutomaticFlush: false
        )
        service.setEnabled(true)

        service.recordDeletion(bytesFreed: 12_288, count: 3)

        XCTAssertEqual(service.pendingMetrics.reviewedPhotos, 3)
        XCTAssertEqual(service.pendingMetrics.deletedPhotos, 3)
        XCTAssertEqual(service.pendingMetrics.keptPhotos, 0)
        XCTAssertEqual(service.pendingMetrics.bytesFreed, 12_288)
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
        if let flushTask = service.flushPendingMetricsIfNeeded() {
            await flushTask.value
        }

        payloads = await sink.payloads
        XCTAssertEqual(payloads.count, 1)

        clock.now = clock.now.addingTimeInterval(24 * 60 * 60 + 1)
        if let flushTask = service.flushPendingMetricsIfNeeded() {
            await flushTask.value
        }

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
        service.setEnabled(false)

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
    func testAchievementUnlockShowsBannerState() throws {
        let schema = Schema([UserStats.self, ReviewedPhoto.self, UnlockedAchievement.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let stats = UserStats()
        stats.totalReviewed = 49
        context.insert(stats)

        let service = GamificationService()
        service.processPhotoReview(
            action: .keep,
            fileSize: 0,
            stats: stats,
            challengeType: .review,
            context: context
        )

        XCTAssertEqual(service.newlyUnlockedAchievement?.id, "first_steps")
        XCTAssertTrue(service.showAchievementBanner)
    }

    @MainActor
    func testQueuedDeletionReviewCountsReviewButNotDeletionUntilCommit() throws {
        let container = try makeInMemoryReviewContainer()
        let context = container.mainContext
        let stats = UserStats()
        stats.dailyChallengeType = DailyChallengeType.review.rawValue
        stats.dailyChallengeDate = Date()
        context.insert(stats)

        let service = GamificationService()
        try service.markPhotoReviewed(id: "queued-photo", context: context)
        service.processQueuedDeletionReview(
            stats: stats,
            challengeType: .review,
            context: context
        )
        try context.save()

        XCTAssertEqual(stats.totalReviewed, 1)
        XCTAssertEqual(stats.totalDeleted, 0)
        XCTAssertEqual(stats.storageFreed, 0)
        XCTAssertEqual(stats.dailyChallengeProgress, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewedPhoto>()), 1)

        service.processQueuedDeletionCommit(
            fileSize: 2_048,
            stats: stats,
            challengeType: .review,
            context: context
        )

        XCTAssertEqual(stats.totalReviewed, 1)
        XCTAssertEqual(stats.totalDeleted, 1)
        XCTAssertEqual(stats.storageFreed, 2_048)
        XCTAssertEqual(stats.dailyChallengeProgress, 1)
    }

    @MainActor
    func testQueuedDeletionCommitAdvancesDeleteChallengeOnlyOnCommit() throws {
        let container = try makeInMemoryReviewContainer()
        let context = container.mainContext
        let stats = UserStats()
        stats.dailyChallengeType = DailyChallengeType.delete.rawValue
        stats.dailyChallengeDate = Date()
        context.insert(stats)

        let service = GamificationService()
        try service.markPhotoReviewed(id: "queued-photo", context: context)
        service.processQueuedDeletionReview(
            stats: stats,
            challengeType: .delete,
            context: context
        )

        XCTAssertEqual(stats.totalReviewed, 1)
        XCTAssertEqual(stats.totalDeleted, 0)
        XCTAssertEqual(stats.dailyChallengeProgress, 0)

        service.processQueuedDeletionCommit(
            fileSize: 1_024,
            stats: stats,
            challengeType: .delete,
            context: context
        )

        XCTAssertEqual(stats.totalReviewed, 1)
        XCTAssertEqual(stats.totalDeleted, 1)
        XCTAssertEqual(stats.storageFreed, 1_024)
        XCTAssertEqual(stats.dailyChallengeProgress, 1)
    }

    @MainActor
    func testQueuedDeletionReviewRollbackRemovesReviewState() throws {
        let container = try makeInMemoryReviewContainer()
        let context = container.mainContext
        let stats = UserStats()
        stats.dailyChallengeType = DailyChallengeType.review.rawValue
        stats.dailyChallengeDate = Date()
        context.insert(stats)

        let service = GamificationService()
        try service.markPhotoReviewed(id: "queued-photo", context: context)
        service.processQueuedDeletionReview(
            stats: stats,
            challengeType: .review,
            context: context
        )
        try context.save()

        try service.rollbackQueuedDeletionReview(
            id: "queued-photo",
            stats: stats,
            challengeType: .review,
            context: context
        )
        try context.save()

        XCTAssertEqual(stats.totalReviewed, 0)
        XCTAssertEqual(stats.totalDeleted, 0)
        XCTAssertEqual(stats.currentStreak, 0)
        XCTAssertEqual(stats.sessionReviewCount, 0)
        XCTAssertEqual(stats.todayReviewCount, 0)
        XCTAssertEqual(stats.dailyChallengeProgress, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewedPhoto>()), 0)
    }

    @MainActor
    func testUserStatsFetchOrCreateSingletonCreatesOneStatsRecord() throws {
        let container = try ModelContainer(
            for: UserStats.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let stats = try UserStats.fetchOrCreateSingleton(in: context)
        try context.save()

        let allStats = try context.fetch(FetchDescriptor<UserStats>())

        XCTAssertEqual(allStats.count, 1)
        XCTAssertTrue(allStats.first === stats)
    }

    @MainActor
    func testUserStatsFetchOrCreateSingletonMergesDuplicateStatsRecords() throws {
        let container = try ModelContainer(
            for: UserStats.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let firstStats = UserStats()
        firstStats.totalReviewed = 3
        firstStats.totalDeleted = 1
        firstStats.storageFreed = 1_024
        let duplicateStats = UserStats()
        duplicateStats.totalReviewed = 2
        duplicateStats.totalKept = 2
        duplicateStats.storageFreed = 2_048

        context.insert(firstStats)
        context.insert(duplicateStats)
        try context.save()

        let stats = try UserStats.fetchOrCreateSingleton(in: context)
        try context.save()
        let allStats = try context.fetch(FetchDescriptor<UserStats>())

        XCTAssertEqual(allStats.count, 1)
        XCTAssertEqual(stats.totalReviewed, 5)
        XCTAssertEqual(stats.totalDeleted, 1)
        XCTAssertEqual(stats.totalKept, 2)
        XCTAssertEqual(stats.storageFreed, 3_072)
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

    func testPrivacyManifestDeclaresOptInAggregateMetricsCollection() throws {
        let manifestURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PhotoSoap/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: manifestURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let collectedTypes = try XCTUnwrap(plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let collectedTypeNames = Set(collectedTypes.compactMap { $0["NSPrivacyCollectedDataType"] as? String })

        XCTAssertFalse(collectedTypes.isEmpty)
        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
        XCTAssertTrue(collectedTypeNames.contains("NSPrivacyCollectedDataTypeProductInteraction"))
        XCTAssertTrue(collectedTypeNames.contains("NSPrivacyCollectedDataTypeUserID"))
        XCTAssertTrue(collectedTypes.allSatisfy { ($0["NSPrivacyCollectedDataTypeTracking"] as? Bool) == false })
    }

}

private func makeInMemoryReviewContainer() throws -> ModelContainer {
    let schema = Schema([UserStats.self, ReviewedPhoto.self, UnlockedAchievement.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

private func makeTestDefaults() -> UserDefaults {
    let suiteName = "PhotoSoapTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fatalError("Cannot create test UserDefaults for suite: \(suiteName)")
    }
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
