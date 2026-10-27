import Foundation
import Combine

struct AggregateMetrics: Codable, Equatable {
    var installs: Int = 0
    var reviewedPhotos: Int = 0
    var deletedPhotos: Int = 0
    var keptPhotos: Int = 0
    var bytesFreed: Int64 = 0

    var isEmpty: Bool {
        installs == 0 && reviewedPhotos == 0 && deletedPhotos == 0 && keptPhotos == 0 && bytesFreed == 0
    }

    mutating func add(reviewedPhotos: Int, deletedPhotos: Int, keptPhotos: Int, bytesFreed: Int64) {
        self.reviewedPhotos += max(0, reviewedPhotos)
        self.deletedPhotos += max(0, deletedPhotos)
        self.keptPhotos += max(0, keptPhotos)
        self.bytesFreed += max(0, bytesFreed)
    }
}

struct AggregateMetricsPayload: Codable, Equatable {
    let installID: String
    let appVersion: String
    let buildNumber: String
    let platform: String
    let submittedAt: Date
    let registerInstall: Bool
    let dailyBuckets: [DailyMetricsBucketPayload]

    enum CodingKeys: String, CodingKey {
        case installID = "install_id"
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case platform
        case submittedAt = "submitted_at"
        case registerInstall = "register_install"
        case dailyBuckets = "daily_buckets"
    }
}

struct DailyMetricsBucketPayload: Codable, Equatable {
    let metricDate: String
    let reviewedPhotos: Int
    let deletedPhotos: Int
    let keptPhotos: Int
    let bytesFreed: Int64
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case metricDate = "metric_date"
        case reviewedPhotos = "reviewed_photos"
        case deletedPhotos = "deleted_photos"
        case keptPhotos = "kept_photos"
        case bytesFreed = "bytes_freed"
        case updatedAt = "updated_at"
    }
}

private struct PersistedDailyMetricsBucket: Codable, Equatable {
    let metricDate: String
    var reviewedPhotos: Int
    var deletedPhotos: Int
    var keptPhotos: Int
    var bytesFreed: Int64
    var updatedAt: Date
    var isDirty: Bool

    var payload: DailyMetricsBucketPayload {
        DailyMetricsBucketPayload(
            metricDate: metricDate,
            reviewedPhotos: reviewedPhotos,
            deletedPhotos: deletedPhotos,
            keptPhotos: keptPhotos,
            bytesFreed: bytesFreed,
            updatedAt: updatedAt
        )
    }

    mutating func merge(with other: PersistedDailyMetricsBucket) {
        reviewedPhotos = max(reviewedPhotos, other.reviewedPhotos)
        deletedPhotos = max(deletedPhotos, other.deletedPhotos)
        keptPhotos = max(keptPhotos, other.keptPhotos)
        bytesFreed = max(bytesFreed, other.bytesFreed)
        updatedAt = max(updatedAt, other.updatedAt)
        isDirty = isDirty || other.isDirty
        reviewedPhotos = max(reviewedPhotos, deletedPhotos + keptPhotos)
    }

    func sanitized() -> PersistedDailyMetricsBucket? {
        guard !metricDate.isEmpty else { return nil }

        return PersistedDailyMetricsBucket(
            metricDate: metricDate,
            reviewedPhotos: max(reviewedPhotos, max(0, deletedPhotos) + max(0, keptPhotos)),
            deletedPhotos: max(0, deletedPhotos),
            keptPhotos: max(0, keptPhotos),
            bytesFreed: max(0, bytesFreed),
            updatedAt: updatedAt,
            isDirty: isDirty
        )
    }
}

private struct PersistedAggregateMetricsState: Codable, Equatable {
    var pendingInstallRegistration = false
    var dailyBuckets: [PersistedDailyMetricsBucket] = []
    var lastSuccessfulFlushAt: Date?
    var nextRetryAt: Date?
    var consecutiveTransientFailures = 0
}

nonisolated protocol AggregateMetricsSink {
    var isConfigured: Bool { get }
    func send(_ payload: AggregateMetricsPayload) async throws
}

struct AggregateMetricsConfiguration {
    static let endpointURLInfoKey = "PhotoSoapAggregateMetricsEndpointURL"
    static let anonKeyInfoKey = "PhotoSoapAggregateMetricsAnonKey"

    let endpointURL: URL?
    let anonKey: String?

    static func from(bundle: Bundle) -> AggregateMetricsConfiguration {
        let rawValue = bundle.object(forInfoDictionaryKey: endpointURLInfoKey) as? String
        let endpointURL = rawValue.flatMap(URL.init(string:))
        let anonKey = bundle.object(forInfoDictionaryKey: anonKeyInfoKey) as? String
        return AggregateMetricsConfiguration(endpointURL: endpointURL, anonKey: anonKey)
    }
}

struct RemoteAggregateMetricsSink: AggregateMetricsSink {
    let endpointURL: URL
    let session: URLSession
    let anonKey: String

    var isConfigured: Bool { true }

    func send(_ payload: AggregateMetricsPayload) async throws {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(payload)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MetricsError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MetricsError.httpStatus(httpResponse.statusCode)
        }
    }
}

struct UnconfiguredAggregateMetricsSink: AggregateMetricsSink {
    var isConfigured: Bool { false }

    func send(_ payload: AggregateMetricsPayload) async throws {
        throw MetricsError.notConfigured
    }
}

enum MetricsError: LocalizedError, Equatable {
    case invalidResponse
    case notConfigured
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse, .httpStatus:
            return String(localized: "error.metrics.invalidResponse", defaultValue: "Metrics endpoint returned an invalid response.", table: "LocalizableShared")
        case .notConfigured:
            return String(localized: "error.metrics.notConfigured", defaultValue: "Metrics endpoint is not configured.", table: "LocalizableShared")
        }
    }

    var statusCode: Int? {
        guard case let .httpStatus(statusCode) = self else { return nil }
        return statusCode
    }

    var isPermanentFailure: Bool {
        switch self {
        case let .httpStatus(statusCode):
            return [400, 401, 403, 404, 422].contains(statusCode)
        case .invalidResponse, .notConfigured:
            return false
        }
    }
}

@MainActor
final class AggregateMetricsService: ObservableObject {
    static let installIDKey = "aggregateMetricsInstallID"
    static let installRegisteredKey = "aggregateMetricsInstallRegistered"
    static let pendingMetricsKey = "aggregateMetricsPendingPayload"

    private static let dailyFlushInterval: TimeInterval = 24 * 60 * 60
    private static let maxPendingDaysBeforeFlush = 3
    private static let maxRetainedMetricDays = 14
    private static let maxPendingReviewsBeforeFlush = 200
    private static let maxPendingBytesBeforeFlush: Int64 = 500_000_000
    private static let retrySchedule: [TimeInterval] = [15 * 60, 60 * 60, 6 * 60 * 60]
    private static let metricDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    @Published private(set) var pendingMetrics: AggregateMetrics
    @Published private(set) var isEnabled: Bool

    private let defaults: UserDefaults
    private let bundle: Bundle
    private let sink: AggregateMetricsSink
    private let allowsAutomaticFlush: Bool
    private let now: () -> Date
    private var state: PersistedAggregateMetricsState
    private var isFlushing = false
    private var shouldFlushAgain = false
    private var isFlushDisabledForSession = false

    init(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        sink: AggregateMetricsSink? = nil,
        session: URLSession = .shared,
        allowsAutomaticFlush: Bool = true,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.bundle = bundle
        self.allowsAutomaticFlush = allowsAutomaticFlush
        self.now = now
        self.isEnabled = AnalyticsService.isEnabled(in: defaults)

        let config = AggregateMetricsConfiguration.from(bundle: bundle)

        if let sink {
            self.sink = sink
        } else if let endpointURL = config.endpointURL, let anonKey = config.anonKey {
            self.sink = RemoteAggregateMetricsSink(endpointURL: endpointURL, session: session, anonKey: anonKey)
        } else {
            self.sink = UnconfiguredAggregateMetricsSink()
        }

        self.state = Self.loadState(from: defaults, now: now())
        self.pendingMetrics = Self.pendingMetrics(from: state)

        if isEnabled {
            pruneSyncedHistory(referenceDate: now())
            persistState()
        } else {
            clearCollectedMetrics()
        }
    }

    var isConfigured: Bool {
        sink.isConfigured
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        defaults.set(isEnabled, forKey: AnalyticsService.analyticsEnabledKey)

        if isEnabled {
            registerInstallIfNeeded()
        } else {
            clearCollectedMetrics()
        }
    }

    func registerInstallIfNeeded() {
        guard isMetricsCollectionEnabled else { return }
        guard !defaults.bool(forKey: Self.installRegisteredKey) else { return }

        defaults.set(true, forKey: Self.installRegisteredKey)
        state.pendingInstallRegistration = true
        persistState()
    }

    func recordReview() {
        guard isMetricsCollectionEnabled else { return }

        mutateCurrentBucket { bucket in
            bucket.reviewedPhotos += 1
            bucket.keptPhotos += 1
        }
    }

    func recordDeletion(bytesFreed: Int64, count: Int = 1) {
        guard isMetricsCollectionEnabled else { return }
        let sanitizedCount = max(0, count)
        guard sanitizedCount > 0 else { return }

        mutateCurrentBucket { bucket in
            bucket.reviewedPhotos += sanitizedCount
            bucket.deletedPhotos += sanitizedCount
            bucket.bytesFreed += max(0, bytesFreed)
        }
    }

    @discardableResult
    func flushPendingMetricsIfNeeded() -> Task<Void, Never>? {
        guard isMetricsCollectionEnabled else { return nil }
        guard shouldFlushNow(at: now()) else { return nil }

        let flushTask = Task {
            await flushPendingMetrics(force: false, ignoreRetryWindow: false)
        }
        return flushTask
    }

    func flushForTesting() async {
        guard isMetricsCollectionEnabled else { return }
        await flushPendingMetrics(force: true, ignoreRetryWindow: true)
    }

    private var isMetricsCollectionEnabled: Bool {
        let currentValue = AnalyticsService.isEnabled(in: defaults)
        if isEnabled != currentValue {
            isEnabled = currentValue
        }
        return currentValue
    }

    private func clearCollectedMetrics() {
        state = PersistedAggregateMetricsState()
        pendingMetrics = AggregateMetrics()
        isFlushDisabledForSession = false
        shouldFlushAgain = false

        defaults.removeObject(forKey: Self.pendingMetricsKey)
        defaults.removeObject(forKey: Self.installRegisteredKey)
        defaults.removeObject(forKey: Self.installIDKey)
    }

    private func mutateCurrentBucket(_ mutation: (inout PersistedDailyMetricsBucket) -> Void) {
        let currentDate = Self.metricDateString(from: now())
        let updatedAt = now()
        pruneExpiredBuckets(referenceDate: updatedAt)

        if let index = state.dailyBuckets.firstIndex(where: { $0.metricDate == currentDate }) {
            mutation(&state.dailyBuckets[index])
            state.dailyBuckets[index].reviewedPhotos = max(
                state.dailyBuckets[index].reviewedPhotos,
                state.dailyBuckets[index].deletedPhotos + state.dailyBuckets[index].keptPhotos
            )
            state.dailyBuckets[index].deletedPhotos = max(0, state.dailyBuckets[index].deletedPhotos)
            state.dailyBuckets[index].keptPhotos = max(0, state.dailyBuckets[index].keptPhotos)
            state.dailyBuckets[index].bytesFreed = max(0, state.dailyBuckets[index].bytesFreed)
            state.dailyBuckets[index].updatedAt = updatedAt
            state.dailyBuckets[index].isDirty = true
        } else {
            var bucket = PersistedDailyMetricsBucket(
                metricDate: currentDate,
                reviewedPhotos: 0,
                deletedPhotos: 0,
                keptPhotos: 0,
                bytesFreed: 0,
                updatedAt: updatedAt,
                isDirty: true
            )
            mutation(&bucket)
            bucket.reviewedPhotos = max(bucket.reviewedPhotos, bucket.deletedPhotos + bucket.keptPhotos)
            bucket.deletedPhotos = max(0, bucket.deletedPhotos)
            bucket.keptPhotos = max(0, bucket.keptPhotos)
            bucket.bytesFreed = max(0, bucket.bytesFreed)
            state.dailyBuckets.append(bucket)
        }

        sortBuckets()
        persistState()
        scheduleAutomaticFlushIfNeeded()
    }

    private func scheduleAutomaticFlushIfNeeded() {
        guard allowsAutomaticFlush else { return }
        guard shouldForceFlushForBacklog(at: now()) else { return }
        flushPendingMetricsIfNeeded()
    }

    private func flushPendingMetrics(force: Bool, ignoreRetryWindow: Bool) async {
        let referenceDate = now()
        if pruneExpiredBuckets(referenceDate: referenceDate) {
            persistState()
        }

        guard canAttemptFlush(at: referenceDate, ignoreRetryWindow: ignoreRetryWindow) else { return }
        guard force || shouldFlushNow(at: referenceDate) else { return }

        if isFlushing {
            shouldFlushAgain = true
            return
        }

        let dirtyBuckets = state.dailyBuckets
            .filter(\.isDirty)
            .sorted { $0.metricDate < $1.metricDate }

        guard state.pendingInstallRegistration || !dirtyBuckets.isEmpty else { return }

        isFlushing = true

        let payload = AggregateMetricsPayload(
            installID: installIDForUpload(),
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "unknown",
            platform: "ios",
            submittedAt: referenceDate,
            registerInstall: state.pendingInstallRegistration,
            dailyBuckets: dirtyBuckets.map(\.payload)
        )

        do {
            try await sink.send(payload)
            markFlushSuccess(sentMetricDates: Set(dirtyBuckets.map(\.metricDate)), sentInstallRegistration: state.pendingInstallRegistration, flushedAt: referenceDate)
        } catch {
            handleFlushFailure(error, at: referenceDate)
        }

        isFlushing = false

        if shouldFlushAgain {
            shouldFlushAgain = false
            await flushPendingMetrics(force: false, ignoreRetryWindow: false)
        }
    }

    private func markFlushSuccess(sentMetricDates: Set<String>, sentInstallRegistration: Bool, flushedAt: Date) {
        for index in state.dailyBuckets.indices {
            guard sentMetricDates.contains(state.dailyBuckets[index].metricDate) else { continue }
            state.dailyBuckets[index].isDirty = false
        }

        if sentInstallRegistration {
            state.pendingInstallRegistration = false
        }

        state.lastSuccessfulFlushAt = flushedAt
        state.nextRetryAt = nil
        state.consecutiveTransientFailures = 0

        pruneSyncedHistory(referenceDate: flushedAt)
        persistState()
    }

    private func handleFlushFailure(_ error: Error, at referenceDate: Date) {
        if let metricsError = error as? MetricsError, metricsError.isPermanentFailure {
            isFlushDisabledForSession = true
            state.nextRetryAt = nil
            state.consecutiveTransientFailures = 0
            persistState()

            if let statusCode = metricsError.statusCode {
#if DEBUG
                print("PhotoSoap: metrics flush disabled for this app launch after HTTP status \(statusCode)")
#endif
            } else {
#if DEBUG
                print("PhotoSoap: metrics flush disabled for this app launch after a permanent failure")
#endif
            }
            return
        }

        state.consecutiveTransientFailures += 1
        let retryIndex = min(state.consecutiveTransientFailures - 1, Self.retrySchedule.count - 1)
        let retryDelay = Self.retrySchedule[max(0, retryIndex)]
        state.nextRetryAt = referenceDate.addingTimeInterval(retryDelay)
        persistState()

#if DEBUG
        print("PhotoSoap: metrics flush deferred after failure: \(error.localizedDescription)")
#endif
    }

    private func shouldFlushNow(at referenceDate: Date) -> Bool {
        guard canAttemptFlush(at: referenceDate, ignoreRetryWindow: false) else { return false }

        if state.lastSuccessfulFlushAt == nil {
            return true
        }

        if hasClosedDirtyBucket(at: referenceDate) {
            return true
        }

        if shouldForceFlushForBacklog(at: referenceDate) {
            return true
        }

        guard let lastSuccessfulFlushAt = state.lastSuccessfulFlushAt else { return false }
        return referenceDate.timeIntervalSince(lastSuccessfulFlushAt) >= Self.dailyFlushInterval
    }

    private func installIDForUpload() -> String {
        if let existingInstallID = defaults.string(forKey: Self.installIDKey), !existingInstallID.isEmpty {
            return existingInstallID
        }

        let newInstallID = UUID().uuidString.lowercased()
        defaults.set(newInstallID, forKey: Self.installIDKey)
        return newInstallID
    }

    private func canAttemptFlush(at referenceDate: Date, ignoreRetryWindow: Bool) -> Bool {
        guard isMetricsCollectionEnabled else { return false }
        guard sink.isConfigured, !isFlushDisabledForSession, hasPendingUploads else { return false }

        if ignoreRetryWindow {
            return true
        }

        if let nextRetryAt = state.nextRetryAt, nextRetryAt > referenceDate {
            return false
        }

        return true
    }

    private func shouldForceFlushForBacklog(at referenceDate: Date) -> Bool {
        let dirtyBuckets = state.dailyBuckets.filter(\.isDirty)
        let dirtyMetrics = Self.pendingMetrics(from: state)

        return dirtyBuckets.count >= Self.maxPendingDaysBeforeFlush
            || dirtyMetrics.reviewedPhotos >= Self.maxPendingReviewsBeforeFlush
            || dirtyMetrics.bytesFreed >= Self.maxPendingBytesBeforeFlush
            || hasClosedDirtyBucket(at: referenceDate)
    }

    private var hasPendingUploads: Bool {
        state.pendingInstallRegistration || state.dailyBuckets.contains(where: \.isDirty)
    }

    private func hasClosedDirtyBucket(at referenceDate: Date) -> Bool {
        let currentDate = Self.metricDateString(from: referenceDate)
        return state.dailyBuckets.contains { $0.isDirty && $0.metricDate < currentDate }
    }

    private func pruneSyncedHistory(referenceDate: Date) {
        let currentDate = Self.metricDateString(from: referenceDate)
        state.dailyBuckets.removeAll { !$0.isDirty && $0.metricDate != currentDate }
        sortBuckets()
    }

    @discardableResult
    private func pruneExpiredBuckets(referenceDate: Date) -> Bool {
        let validRange = Self.retainedMetricDateRange(referenceDate: referenceDate)
        let previousCount = state.dailyBuckets.count
        state.dailyBuckets.removeAll {
            $0.metricDate < validRange.lowerBound || $0.metricDate > validRange.upperBound
        }
        sortBuckets()
        return state.dailyBuckets.count != previousCount
    }

    private func persistState() {
        pendingMetrics = Self.pendingMetrics(from: state)

        guard let encoded = try? JSONEncoder().encode(state) else { return }
        defaults.set(encoded, forKey: Self.pendingMetricsKey)
    }

    private func sortBuckets() {
        state.dailyBuckets.sort { $0.metricDate < $1.metricDate }
    }

    private static func pendingMetrics(from state: PersistedAggregateMetricsState) -> AggregateMetrics {
        var metrics = AggregateMetrics(installs: state.pendingInstallRegistration ? 1 : 0)

        for bucket in state.dailyBuckets where bucket.isDirty {
            metrics.add(
                reviewedPhotos: bucket.reviewedPhotos,
                deletedPhotos: bucket.deletedPhotos,
                keptPhotos: bucket.keptPhotos,
                bytesFreed: bucket.bytesFreed
            )
        }

        return metrics
    }

    private static func loadState(from defaults: UserDefaults, now: Date) -> PersistedAggregateMetricsState {
        guard let data = defaults.data(forKey: pendingMetricsKey) else {
            return PersistedAggregateMetricsState()
        }

        if let state = try? JSONDecoder().decode(PersistedAggregateMetricsState.self, from: data) {
            return sanitize(state: state, now: now)
        }

        if let legacyMetrics = try? JSONDecoder().decode(AggregateMetrics.self, from: data) {
            return migrateLegacyMetrics(legacyMetrics, now: now)
        }

        return PersistedAggregateMetricsState()
    }

    private static func sanitize(state: PersistedAggregateMetricsState, now: Date) -> PersistedAggregateMetricsState {
        var mergedBucketsByDate: [String: PersistedDailyMetricsBucket] = [:]
        let validRange = retainedMetricDateRange(referenceDate: now)

        for bucket in state.dailyBuckets {
            guard let sanitizedBucket = bucket.sanitized() else { continue }
            guard sanitizedBucket.metricDate >= validRange.lowerBound,
                  sanitizedBucket.metricDate <= validRange.upperBound,
                  let parsedDate = metricDateFormatter.date(from: sanitizedBucket.metricDate),
                  metricDateFormatter.string(from: parsedDate) == sanitizedBucket.metricDate else { continue }

            if var existingBucket = mergedBucketsByDate[sanitizedBucket.metricDate] {
                existingBucket.merge(with: sanitizedBucket)
                mergedBucketsByDate[sanitizedBucket.metricDate] = existingBucket
            } else {
                mergedBucketsByDate[sanitizedBucket.metricDate] = sanitizedBucket
            }
        }

        var sanitizedState = state
        sanitizedState.dailyBuckets = mergedBucketsByDate.values.sorted { $0.metricDate < $1.metricDate }
        sanitizedState.consecutiveTransientFailures = max(0, sanitizedState.consecutiveTransientFailures)

        if let nextRetryAt = sanitizedState.nextRetryAt, nextRetryAt <= now {
            sanitizedState.nextRetryAt = nil
        }

        return sanitizedState
    }

    private static func migrateLegacyMetrics(_ legacyMetrics: AggregateMetrics, now: Date) -> PersistedAggregateMetricsState {
        var state = PersistedAggregateMetricsState()
        state.pendingInstallRegistration = legacyMetrics.installs > 0

        let reviewedPhotos = max(legacyMetrics.reviewedPhotos, max(0, legacyMetrics.deletedPhotos) + max(0, legacyMetrics.keptPhotos))
        let deletedPhotos = max(0, legacyMetrics.deletedPhotos)
        let keptPhotos = max(0, legacyMetrics.keptPhotos)
        let bytesFreed = max(0, legacyMetrics.bytesFreed)

        if reviewedPhotos > 0 || deletedPhotos > 0 || keptPhotos > 0 || bytesFreed > 0 {
            state.dailyBuckets = [
                PersistedDailyMetricsBucket(
                    metricDate: metricDateString(from: now),
                    reviewedPhotos: reviewedPhotos,
                    deletedPhotos: deletedPhotos,
                    keptPhotos: keptPhotos,
                    bytesFreed: bytesFreed,
                    updatedAt: now,
                    isDirty: true
                )
            ]
        }

        return state
    }

    private static func metricDateString(from date: Date) -> String {
        metricDateFormatter.string(from: date)
    }

    private static func retainedMetricDateRange(referenceDate: Date) -> ClosedRange<String> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let earliestDate = calendar.date(
            byAdding: .day,
            value: -(maxRetainedMetricDays - 1),
            to: referenceDate
        ) ?? referenceDate
        return metricDateString(from: earliestDate)...metricDateString(from: referenceDate)
    }
}
