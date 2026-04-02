import XCTest
import SwiftData
import Photos
@testable import PhotoSoap

final class SmokeTests: XCTestCase {
    func testCompactCouponGenerationProducesEightUppercaseLetters() {
        let issuedAt = Date(timeIntervalSince1970: 1_774_700_800)
        let token = CouponService.generateToken(for: "TEST", now: issuedAt)

        XCTAssertEqual(token?.count, 8)
        XCTAssertEqual(token, token?.uppercased())
        XCTAssertEqual(token?.range(of: "^[A-Z]{8}$", options: .regularExpression) != nil, true)
        XCTAssertEqual(CouponService.validate(code: token ?? "", now: issuedAt), .success)
    }

    func testCompactCouponExpiresAfterThirtyDays() {
        let issuedAt = Date(timeIntervalSince1970: 1_774_700_800)
        let token = CouponService.generateToken(for: "TEST", now: issuedAt)
        let stillValidDate = issuedAt.addingTimeInterval(30 * 24 * 60 * 60)
        let expiredDate = issuedAt.addingTimeInterval(31 * 24 * 60 * 60)

        XCTAssertEqual(CouponService.validate(code: token ?? "", now: stillValidDate), .success)
        XCTAssertEqual(CouponService.validate(code: token ?? "", now: expiredDate), .expiredCode)
    }

    func testLegacyCouponValidationStillWorks() {
        let issuedAt = Date(timeIntervalSince1970: 1_774_700_800)
        let token = CouponService.generateLegacyToken(for: "TEST", now: issuedAt)

        XCTAssertEqual(CouponService.validate(code: token, now: issuedAt), .success)
    }

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
    func testAnalyticsServiceRecordsEventNameAndProperties() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let analyticsService = AnalyticsService(defaults: defaults, recorder: { _ in })
        analyticsService.setEnabled(true)

        analyticsService.track(.paywallOpened(source: "stats_card"))

        XCTAssertEqual(analyticsService.recordedEvents.count, 1)
        XCTAssertEqual(analyticsService.recordedEvents.first?.name, "paywall_opened")
        XCTAssertEqual(analyticsService.recordedEvents.first?.properties["source"], "stats_card")
    }

    @MainActor
    func testAnalyticsServiceSkipsEventsWhenDisabled() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let analyticsService = AnalyticsService(defaults: defaults, recorder: { _ in })

        analyticsService.track(.statsViewed())

        XCTAssertFalse(analyticsService.isEnabled)
        XCTAssertTrue(analyticsService.recordedEvents.isEmpty)
    }

    @MainActor
    func testAnalyticsPreferencePersistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let analyticsService = AnalyticsService(defaults: defaults, recorder: { _ in })
        analyticsService.setEnabled(true)

        let restoredService = AnalyticsService(defaults: defaults, recorder: { _ in })

        XCTAssertTrue(restoredService.isEnabled)
    }

    @MainActor
    func testHapticsServiceIsEnabledByDefault() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

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
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

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
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

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
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let service = AggregateMetricsService(
            defaults: defaults,
            sink: TestAggregateMetricsSink(isConfigured: false),
            allowsAutomaticFlush: false
        )

        service.registerInstallIfNeeded()
        service.registerInstallIfNeeded()

        XCTAssertEqual(service.pendingMetrics.installs, 1)
    }

    @MainActor
    func testAggregateMetricsTrackReviewsDeletesAndSpaceFreed() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let service = AggregateMetricsService(
            defaults: defaults,
            sink: TestAggregateMetricsSink(isConfigured: false),
            allowsAutomaticFlush: false
        )

        service.recordReview()
        service.recordDeletion(bytesFreed: 4_096)

        XCTAssertEqual(service.pendingMetrics.reviewedPhotos, 2)
        XCTAssertEqual(service.pendingMetrics.deletedPhotos, 1)
        XCTAssertEqual(service.pendingMetrics.keptPhotos, 1)
        XCTAssertEqual(service.pendingMetrics.bytesFreed, 4_096)
    }

    @MainActor
    func testAggregateMetricsDoesNotFlushOnEveryReview() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_776_000_000))
        let sink = TestAggregateMetricsSink()
        let service = AggregateMetricsService(
            defaults: defaults,
            sink: sink,
            allowsAutomaticFlush: true,
            now: { clock.now }
        )

        service.recordReview()
        await Task.yield()

        let payloads = await sink.payloads

        XCTAssertTrue(payloads.isEmpty)
        XCTAssertEqual(service.pendingMetrics.reviewedPhotos, 1)
    }

    @MainActor
    func testAggregateMetricsFlushesCumulativeDailyBucketAndRespectsDailyCadence() async {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_776_000_000))
        let sink = TestAggregateMetricsSink()
        let service = AggregateMetricsService(
            defaults: defaults,
            sink: sink,
            allowsAutomaticFlush: true,
            now: { clock.now }
        )

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

    @MainActor
    func testEarnedAdRemovalUnlockRequiresThreshold() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let analyticsService = AnalyticsService(defaults: defaults, recorder: { _ in })
        analyticsService.setEnabled(true)
        let service = AdRemovalPurchaseService(
            analyticsService: analyticsService,
            shouldObserveTransactions: false
        )
        let stats = UserStats()

        stats.totalDeleted = AdRemovalConfig.freeUnlockDeletedCount - 1
        service.refreshEarnedEntitlement(stats: stats)

        XCTAssertFalse(service.hasEarnedEntitlement)
        XCTAssertFalse(service.hasAdRemovalEntitlement)
        XCTAssertEqual(service.remainingDeletesForUnlock, 1)

        stats.totalDeleted = AdRemovalConfig.freeUnlockDeletedCount
        service.refreshEarnedEntitlement(stats: stats)

        XCTAssertTrue(service.hasEarnedEntitlement)
        XCTAssertTrue(service.hasAdRemovalEntitlement)
        XCTAssertEqual(service.unlockSource, .earned)
        XCTAssertEqual(service.remainingDeletesForUnlock, 0)
        XCTAssertEqual(service.deleteProgress, 1.0)
        XCTAssertTrue(analyticsService.recordedEvents.contains(where: { $0.name == "loyalty_unlock_earned" }))
    }

    @MainActor
    func testPurchasedEntitlementUnlocksAdRemoval() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let service = AdRemovalPurchaseService(
            analyticsService: AnalyticsService(defaults: defaults, recorder: { _ in }),
            shouldObserveTransactions: false
        )

        service.applyPurchasedEntitlement(true)

        XCTAssertTrue(service.hasPurchasedEntitlement)
        XCTAssertTrue(service.hasAdRemovalEntitlement)
        XCTAssertEqual(service.unlockSource, .purchased)
    }

    @MainActor
    func testDeleteProgressCapsAtOneHundredPercent() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let service = AdRemovalPurchaseService(
            analyticsService: AnalyticsService(defaults: defaults, recorder: { _ in }),
            shouldObserveTransactions: false
        )
        let stats = UserStats()

        stats.totalDeleted = AdRemovalConfig.freeUnlockDeletedCount + 250
        service.refreshEarnedEntitlement(stats: stats)

        XCTAssertEqual(service.currentDeletedCount, AdRemovalConfig.freeUnlockDeletedCount + 250)
        XCTAssertEqual(service.deleteProgress, 1.0)
        XCTAssertEqual(service.remainingDeletesForUnlock, 0)
    }

    @MainActor
    func testAdCoordinatorDisablesAdsWhenAdFreeIsUnlocked() {
        let configuration = AdMobRuntimeConfiguration(
            appID: AdMobConfig.productionAppID,
            unitIDsByPlacement: [
                .reviewBanner: AdMobConfig.productionReviewBannerUnitID
            ]
        )
        let coordinator = AdCoordinator(configuration: configuration)

        XCTAssertTrue(coordinator.adsEnabled)
        XCTAssertTrue(coordinator.shouldShowBanner(at: .reviewBanner))

        coordinator.updateEntitlement(hasAdRemovalEntitlement: true)

        XCTAssertFalse(coordinator.adsEnabled)
        XCTAssertFalse(coordinator.shouldShowBanner(at: .reviewBanner))
    }

    @MainActor
    func testAdCoordinatorFlagsIncompleteConfiguration() {
        let configuration = AdMobRuntimeConfiguration(
            appID: "",
            unitIDsByPlacement: [:]
        )
        let coordinator = AdCoordinator(configuration: configuration)

        XCTAssertFalse(coordinator.isConfigured)
        XCTAssertFalse(coordinator.adsEnabled)
        XCTAssertEqual(coordinator.statusSummary, "Banner ads are not configured yet.")
    }
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
