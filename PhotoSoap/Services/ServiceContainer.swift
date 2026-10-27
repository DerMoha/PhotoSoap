import Foundation
import SwiftData
import Combine

@MainActor
final class ServiceContainer: ObservableObject {
    let photoLibraryService: PhotoLibraryService
    let gamificationService: GamificationService
    let aggregateMetricsService: AggregateMetricsService
    let analyticsService: AnalyticsService
    let privacyCollectionService: PrivacyCollectionService
    let reviewAccountingService: ReviewAccountingService
    let startupRoutingService: StartupRoutingService
    let hapticsService: HapticsService

    init(modelContext _: ModelContext) {
        let analyticsService = AnalyticsService()
        let aggregateMetricsService = AggregateMetricsService()
        let gamificationService = GamificationService()

        self.analyticsService = analyticsService
        self.hapticsService = HapticsService()
        self.aggregateMetricsService = aggregateMetricsService
        self.photoLibraryService = PhotoLibraryService()
        self.gamificationService = gamificationService
        self.privacyCollectionService = PrivacyCollectionService(
            analyticsService: analyticsService,
            aggregateMetricsService: aggregateMetricsService
        )
        self.reviewAccountingService = ReviewAccountingService(gamificationService: gamificationService)
        self.startupRoutingService = StartupRoutingService()
    }
}
