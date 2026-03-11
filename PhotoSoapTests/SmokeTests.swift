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
        let service = AdRemovalPurchaseService(shouldObserveTransactions: false)
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
    }

    @MainActor
    func testPurchasedEntitlementUnlocksAdRemoval() {
        let service = AdRemovalPurchaseService(shouldObserveTransactions: false)

        service.applyPurchasedEntitlement(true)

        XCTAssertTrue(service.hasPurchasedEntitlement)
        XCTAssertTrue(service.hasAdRemovalEntitlement)
        XCTAssertEqual(service.unlockSource, .purchased)
    }

    @MainActor
    func testDeleteProgressCapsAtOneHundredPercent() {
        let service = AdRemovalPurchaseService(shouldObserveTransactions: false)
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
            appID: AdMobConfig.testAppID,
            usesTestIdentifiers: true,
            unitIDsByPlacement: [
                .statsBanner: AdMobConfig.testBannerUnitID,
                .achievementsBanner: AdMobConfig.testBannerUnitID,
                .reviewCompletionInterstitial: AdMobConfig.testInterstitialUnitID
            ],
            hasTrackingUsageDescription: true
        )
        let coordinator = AdCoordinator(configuration: configuration)

        XCTAssertTrue(coordinator.adsEnabled)
        XCTAssertTrue(coordinator.shouldShowBanner(at: .statsBanner))
        XCTAssertTrue(coordinator.canPresentInterstitial(at: .reviewCompletionInterstitial))

        coordinator.updateEntitlement(hasAdRemovalEntitlement: true)

        XCTAssertFalse(coordinator.adsEnabled)
        XCTAssertFalse(coordinator.shouldShowBanner(at: .statsBanner))
        XCTAssertFalse(coordinator.canPresentInterstitial(at: .reviewCompletionInterstitial))
    }

    @MainActor
    func testAdCoordinatorFlagsIncompleteConfiguration() {
        let configuration = AdMobRuntimeConfiguration(
            appID: "",
            usesTestIdentifiers: false,
            unitIDsByPlacement: [:],
            hasTrackingUsageDescription: false
        )
        let coordinator = AdCoordinator(configuration: configuration)

        XCTAssertFalse(coordinator.isConfigured)
        XCTAssertFalse(coordinator.adsEnabled)
        XCTAssertFalse(coordinator.integrationChecklist.isEmpty)
    }
}
