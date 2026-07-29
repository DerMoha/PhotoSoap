import Foundation
import Combine

@MainActor
final class PrivacyCollectionService: ObservableObject {
    @Published private(set) var isEnabled: Bool

    private let analyticsService: AnalyticsService
    private let aggregateMetricsService: AggregateMetricsService

    init(analyticsService: AnalyticsService, aggregateMetricsService: AggregateMetricsService) {
        self.analyticsService = analyticsService
        self.aggregateMetricsService = aggregateMetricsService
        self.isEnabled = analyticsService.isEnabled
    }

    static func requiresConsentChoice(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AnalyticsService.analyticsEnabledKey) == nil
    }

    func setEnabled(_ enabled: Bool) {
        analyticsService.setEnabled(enabled)
        aggregateMetricsService.setEnabled(enabled)
        isEnabled = analyticsService.isEnabled
    }

    func track(_ event: AnalyticsEvent) {
        analyticsService.track(event)
        isEnabled = analyticsService.isEnabled
    }

    func registerInstallIfNeeded() {
        aggregateMetricsService.registerInstallIfNeeded()
        isEnabled = aggregateMetricsService.isEnabled
    }

    func recordReview() {
        aggregateMetricsService.recordReview()
        isEnabled = aggregateMetricsService.isEnabled
    }

    func recordDeletion(bytesFreed: Int64, count: Int = 1) {
        aggregateMetricsService.recordDeletion(bytesFreed: bytesFreed, count: count)
        isEnabled = aggregateMetricsService.isEnabled
    }

    @discardableResult
    func flushPendingMetricsIfNeeded() -> Task<Void, Never>? {
        aggregateMetricsService.flushPendingMetricsIfNeeded()
    }

    func flushForTesting() async {
        await aggregateMetricsService.flushForTesting()
        isEnabled = aggregateMetricsService.isEnabled
    }
}
