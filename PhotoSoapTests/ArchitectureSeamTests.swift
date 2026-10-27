import XCTest
import SwiftData
import Photos
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
    func testUndoRestoresLatestDecisionInMixedKeepAndDeleteSequence() async throws {
        let container = try makeArchitectureReviewContainer()
        let context = container.mainContext
        let stats = UserStats()
        context.insert(stats)
        let defaults = makeArchitectureTestDefaults()
        defaults.set(true, forKey: UserDefaultsKeys.deleteQueueEnabled)
        let library = PhotoLibraryService()
        let accounting = ReviewAccountingService(gamificationService: GamificationService())
        let privacy = PrivacyCollectionService(
            analyticsService: AnalyticsService(defaults: defaults, recorder: { _ in }),
            aggregateMetricsService: AggregateMetricsService(
                defaults: defaults,
                sink: ArchitectureTestAggregateMetricsSink(isConfigured: false),
                allowsAutomaticFlush: false
            )
        )
        let viewModel = PhotoReviewViewModel(
            photoLibraryService: library,
            reviewAccountingService: accounting,
            privacyCollectionService: privacy,
            hapticsService: HapticsService(defaults: defaults),
            defaults: defaults
        )
        viewModel.setModelContext(context)
        viewModel.setStats(stats)
        let keptPhoto = Photo(asset: ArchitectureTestPhotoAsset(identifier: "kept-photo"), fileSize: 1_024)
        let queuedPhoto = Photo(asset: ArchitectureTestPhotoAsset(identifier: "queued-photo"), fileSize: 2_048)
        viewModel.currentPhoto = keptPhoto
        await viewModel.performKeepAction()
        XCTAssertTrue(viewModel.canUndo)
        XCTAssertEqual(stats.totalKept, 1)

        viewModel.currentPhoto = queuedPhoto
        await viewModel.performDeleteAction()
        XCTAssertEqual(viewModel.pendingDeletionCount, 1)
        XCTAssertEqual(stats.totalReviewed, 2)

        viewModel.undoLastReview()
        XCTAssertEqual(viewModel.currentPhoto?.id, queuedPhoto.id)
        XCTAssertFalse(viewModel.noMorePhotos)
        XCTAssertEqual(viewModel.pendingDeletionCount, 0)
        XCTAssertEqual(stats.totalReviewed, 1)

        viewModel.undoLastReview()
        XCTAssertEqual(viewModel.currentPhoto?.id, keptPhoto.id)
        XCTAssertEqual(stats.totalKept, 0)
        XCTAssertEqual(viewModel.cycleKeptCount, 0)
        XCTAssertFalse(library.isReviewed(keptPhoto.id))
        XCTAssertFalse(viewModel.canUndo)

        await viewModel.performDeleteAction()
        XCTAssertEqual(viewModel.pendingDeletionItems.first?.id, keptPhoto.id)
        XCTAssertEqual(stats.totalReviewed, 1)
        XCTAssertEqual(stats.totalKept, 0)
    }

    @MainActor
    func testUndoKeepRestoresVideoStatsAndAllowsDeletionReview() throws {
        let container = try makeArchitectureReviewContainer()
        let context = container.mainContext
        let stats = UserStats()
        context.insert(stats)
        let service = ReviewAccountingService(gamificationService: GamificationService())
        let beforeKeep = service.makeSnapshot(for: ["video-1"], stats: stats, context: context)
        try service.recordKeep(photoID: "video-1", stats: stats, context: context, mediaType: .video)
        try service.save(context: context)
        XCTAssertEqual(stats.videosKept, 1)

        let beforeQueue = service.makeSnapshot(for: ["photo-2"], stats: stats, context: context)
        try service.recordQueuedDeletionReview(photoID: "photo-2", stats: stats, context: context)
        try service.save(context: context)
        _ = try service.restore(beforeQueue, affectedPhotoIDs: ["photo-2"], stats: stats, context: context)
        XCTAssertEqual(stats.totalReviewed, 1)
        XCTAssertEqual(stats.videosKept, 1)
        XCTAssertTrue(service.isPhotoReviewed(id: "video-1", context: context))

        _ = try service.restore(beforeKeep, affectedPhotoIDs: ["video-1"], stats: stats, context: context)
        XCTAssertEqual(stats.totalReviewed, 0)
        XCTAssertEqual(stats.totalKept, 0)
        XCTAssertEqual(stats.videosKept, 0)
        XCTAssertEqual(stats.todayReviewCount, 0)
        XCTAssertFalse(service.isPhotoReviewed(id: "video-1", context: context))

        try service.recordQueuedDeletionReview(photoID: "video-1", stats: stats, context: context, mediaType: .video)
        try service.save(context: context)
        XCTAssertEqual(stats.totalReviewed, 1)
        XCTAssertEqual(stats.videosReviewed, 1)
        XCTAssertEqual(stats.videosKept, 0)
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

private final class ArchitectureTestPhotoAsset: PHAsset {
    private let identifier: String

    init(identifier: String) {
        self.identifier = identifier
        super.init()
    }

    override var localIdentifier: String { identifier }
    override var mediaType: PHAssetMediaType { .image }
}
