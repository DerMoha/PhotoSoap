import XCTest
import SwiftData
@testable import PhotoSoap

final class ArchitectureSeamTests: XCTestCase {
    @MainActor
    func testReviewAccountingRestoresImmediateDeletionSnapshot() throws {
        let container = try makeArchitectureReviewContainer()
        let context = container.mainContext
        let stats = UserStats()
        stats.dailyChallengeType = DailyChallengeType.delete.rawValue
        stats.dailyChallengeDate = Date()
        context.insert(stats)

        let service = ReviewAccountingService(gamificationService: GamificationService())
        let snapshot = try service.prepareImmediateDeletion(
            photoID: "photo-1",
            fileSize: 4_096,
            stats: stats,
            context: context
        )
        try service.save(context: context)

        XCTAssertEqual(stats.totalReviewed, 1)
        XCTAssertEqual(stats.totalDeleted, 1)
        XCTAssertEqual(stats.storageFreed, 4_096)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewedPhoto>()), 1)

        let restoreResult = try service.restore(
            snapshot,
            affectedPhotoIDs: ["photo-1"],
            stats: stats,
            context: context
        )

        XCTAssertTrue(restoreResult.unreviewedPhotoIDs.contains("photo-1"))
        XCTAssertEqual(stats.totalReviewed, 0)
        XCTAssertEqual(stats.totalDeleted, 0)
        XCTAssertEqual(stats.storageFreed, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReviewedPhoto>()), 0)
    }

    @MainActor
    func testPrivacyCollectionFacadeControlsEventsAndAggregateMetricsTogether() {
        let defaults = makeArchitectureTestDefaults()
        let analyticsService = AnalyticsService(defaults: defaults, recorder: { _ in })
        let aggregateMetricsService = AggregateMetricsService(
            defaults: defaults,
            sink: ArchitectureTestAggregateMetricsSink(isConfigured: false),
            allowsAutomaticFlush: false
        )
        let service = PrivacyCollectionService(
            analyticsService: analyticsService,
            aggregateMetricsService: aggregateMetricsService
        )

        service.setEnabled(true)
        service.track(.statsViewed())
        service.recordDeletion(bytesFreed: 2_048, count: 2)

        XCTAssertTrue(service.isEnabled)
        XCTAssertEqual(analyticsService.recordedEvents.map(\.name), ["stats_viewed"])
        XCTAssertEqual(aggregateMetricsService.pendingMetrics.reviewedPhotos, 2)
        XCTAssertEqual(aggregateMetricsService.pendingMetrics.deletedPhotos, 2)
        XCTAssertEqual(aggregateMetricsService.pendingMetrics.bytesFreed, 2_048)

        service.setEnabled(false)
        service.track(.appOpened())
        service.recordReview()

        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(analyticsService.recordedEvents.count, 1)
        XCTAssertTrue(aggregateMetricsService.pendingMetrics.isEmpty)
    }

    @MainActor
    func testStartupRoutingMapsQuickStartAndPermissionStates() {
        let service = StartupRoutingService()

        XCTAssertEqual(service.route(hasSeenQuickStartInfo: false, authorizationStatus: .authorized), .quickStart)
        XCTAssertEqual(service.route(hasSeenQuickStartInfo: true, authorizationStatus: .notDetermined), .permissionRequest)
        XCTAssertEqual(service.route(hasSeenQuickStartInfo: true, authorizationStatus: .denied), .permissionDenied)
        XCTAssertEqual(service.route(hasSeenQuickStartInfo: true, authorizationStatus: .restricted), .permissionDenied)
        XCTAssertEqual(service.route(hasSeenQuickStartInfo: true, authorizationStatus: .limited), .main)
        XCTAssertEqual(service.route(hasSeenQuickStartInfo: true, authorizationStatus: .authorized), .main)
    }

    func testDeleteQueueStoreLoadsLegacyPayloadAndClearsInvalidData() throws {
        let defaults = makeArchitectureTestDefaults()
        let store = DeleteQueueStore(defaults: defaults)
        let queuedAt = Date(timeIntervalSince1970: 1_776_000_000)
        let legacyItems = [LegacyPersistedPendingDeletionItem(id: "photo-1", queuedAt: queuedAt, fileSize: 1_024)]

        defaults.set(try JSONEncoder().encode(legacyItems), forKey: UserDefaultsKeys.pendingDeletionQueue)

        let loadedItems = store.load()
        XCTAssertEqual(loadedItems.count, 1)
        XCTAssertEqual(loadedItems.first?.id, "photo-1")
        XCTAssertEqual(loadedItems.first?.queuedAt, queuedAt)
        XCTAssertEqual(loadedItems.first?.fileSize, 1_024)
        XCTAssertEqual(loadedItems.first?.createdReviewOnQueue, false)

        defaults.set(Data([0xFF]), forKey: UserDefaultsKeys.pendingDeletionQueue)

        XCTAssertTrue(store.load().isEmpty)
        XCTAssertNil(defaults.data(forKey: UserDefaultsKeys.pendingDeletionQueue))
    }
}

private struct LegacyPersistedPendingDeletionItem: Encodable {
    let id: String
    let queuedAt: Date
    let fileSize: Int64
}

private func makeArchitectureReviewContainer() throws -> ModelContainer {
    let schema = Schema([UserStats.self, ReviewedPhoto.self, UnlockedAchievement.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

private func makeArchitectureTestDefaults() -> UserDefaults {
    let suiteName = "PhotoSoapArchitectureTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fatalError("Cannot create test UserDefaults for suite: \(suiteName)")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private actor ArchitectureTestAggregateMetricsSink: AggregateMetricsSink {
    let isConfigured: Bool

    init(isConfigured: Bool = true) {
        self.isConfigured = isConfigured
    }

    func send(_ payload: AggregateMetricsPayload) async throws {
        guard isConfigured else {
            throw MetricsError.notConfigured
        }
    }
}
