import Foundation
import SwiftData
import Combine

@MainActor
final class ServiceContainer: ObservableObject {
    let photoLibraryService: PhotoLibraryService
    let gamificationService: GamificationService
    let aggregateMetricsService: AggregateMetricsService
    let analyticsService: AnalyticsService
    let hapticsService: HapticsService

    init(modelContext _: ModelContext) {
        self.analyticsService = AnalyticsService()
        self.hapticsService = HapticsService()
        self.aggregateMetricsService = AggregateMetricsService()
        self.photoLibraryService = PhotoLibraryService()
        self.gamificationService = GamificationService()
    }
}
