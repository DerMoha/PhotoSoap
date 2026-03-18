import Foundation
import SwiftData
import Combine

@MainActor
final class ServiceContainer: ObservableObject {
    let photoLibraryService: PhotoLibraryService
    let gamificationService: GameificationService
    let adRemovalPurchaseService: AdRemovalPurchaseService
    let adCoordinator: AdCoordinator
    let aggregateMetricsService: AggregateMetricsService
    let analyticsService: AnalyticsService

    init(modelContext: ModelContext) {
        self.analyticsService = AnalyticsService()
        self.aggregateMetricsService = AggregateMetricsService()
        self.photoLibraryService = PhotoLibraryService()
        self.gamificationService = GameificationService()
        self.adRemovalPurchaseService = AdRemovalPurchaseService(
            analyticsService: analyticsService,
            shouldObserveTransactions: true
        )
        self.adCoordinator = AdCoordinator()
    }

    func refreshEarnedEntitlement(stats: UserStats) {
        adRemovalPurchaseService.refreshEarnedEntitlement(stats: stats)
        adCoordinator.updateEntitlement(hasAdRemovalEntitlement: adRemovalPurchaseService.hasAdRemovalEntitlement)
    }
}
