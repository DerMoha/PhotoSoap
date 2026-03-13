import Foundation
import Combine

struct AggregateMetrics: Codable, Equatable {
    var installs: Int = 0
    var reviewedPhotos: Int = 0
    var deletedPhotos: Int = 0
    var bytesFreed: Int64 = 0

    var isEmpty: Bool {
        installs == 0 && reviewedPhotos == 0 && deletedPhotos == 0 && bytesFreed == 0
    }

    mutating func subtract(_ other: AggregateMetrics) {
        installs = max(0, installs - other.installs)
        reviewedPhotos = max(0, reviewedPhotos - other.reviewedPhotos)
        deletedPhotos = max(0, deletedPhotos - other.deletedPhotos)
        bytesFreed = max(0, bytesFreed - other.bytesFreed)
    }
}

struct AggregateMetricsPayload: Codable, Equatable {
    let installID: String
    let appVersion: String
    let buildNumber: String
    let platform: String
    let submittedAt: Date
    let metrics: AggregateMetrics
}

protocol AggregateMetricsSink {
    var isConfigured: Bool { get }
    func send(_ payload: AggregateMetricsPayload) async throws
}

struct AggregateMetricsConfiguration {
    static let endpointURLInfoKey = "PhotoSoapAggregateMetricsEndpointURL"

    let endpointURL: URL?

    static func from(bundle: Bundle) -> AggregateMetricsConfiguration {
        let rawValue = bundle.object(forInfoDictionaryKey: endpointURLInfoKey) as? String
        let endpointURL = rawValue.flatMap(URL.init(string:))
        return AggregateMetricsConfiguration(endpointURL: endpointURL)
    }
}

struct RemoteAggregateMetricsSink: AggregateMetricsSink {
    let endpointURL: URL
    let session: URLSession

    var isConfigured: Bool { true }

    func send(_ payload: AggregateMetricsPayload) async throws {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw MetricsError.invalidResponse
        }
    }
}

struct UnconfiguredAggregateMetricsSink: AggregateMetricsSink {
    var isConfigured: Bool { false }

    func send(_ payload: AggregateMetricsPayload) async throws {
        throw MetricsError.notConfigured
    }
}

enum MetricsError: LocalizedError {
    case invalidResponse
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Metrics endpoint returned an invalid response."
        case .notConfigured:
            return "Metrics endpoint is not configured."
        }
    }
}

@MainActor
final class AggregateMetricsService: ObservableObject {
    static let installIDKey = "aggregateMetricsInstallID"
    static let installRegisteredKey = "aggregateMetricsInstallRegistered"
    static let pendingMetricsKey = "aggregateMetricsPendingPayload"

    @Published private(set) var pendingMetrics: AggregateMetrics

    let installID: String

    private let defaults: UserDefaults
    private let bundle: Bundle
    private let sink: AggregateMetricsSink
    private var isFlushing = false
    private var shouldFlushAgain = false

    init(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        sink: AggregateMetricsSink? = nil,
        session: URLSession = .shared
    ) {
        self.defaults = defaults
        self.bundle = bundle
        self.pendingMetrics = Self.loadPendingMetrics(from: defaults)

        if let existingInstallID = defaults.string(forKey: Self.installIDKey), !existingInstallID.isEmpty {
            self.installID = existingInstallID
        } else {
            let newInstallID = UUID().uuidString.lowercased()
            defaults.set(newInstallID, forKey: Self.installIDKey)
            self.installID = newInstallID
        }

        if let sink {
            self.sink = sink
        } else if let endpointURL = AggregateMetricsConfiguration.from(bundle: bundle).endpointURL {
            self.sink = RemoteAggregateMetricsSink(endpointURL: endpointURL, session: session)
        } else {
            self.sink = UnconfiguredAggregateMetricsSink()
        }
    }

    var isConfigured: Bool {
        sink.isConfigured
    }

    func registerInstallIfNeeded() {
        guard !defaults.bool(forKey: Self.installRegisteredKey) else { return }

        defaults.set(true, forKey: Self.installRegisteredKey)
        pendingMetrics.installs += 1
        persistPendingMetrics()
        scheduleAutomaticFlushIfNeeded()
    }

    func recordReview() {
        pendingMetrics.reviewedPhotos += 1
        persistPendingMetrics()
        scheduleAutomaticFlushIfNeeded()
    }

    func recordDeletion(bytesFreed: Int64) {
        pendingMetrics.reviewedPhotos += 1
        pendingMetrics.deletedPhotos += 1
        pendingMetrics.bytesFreed += max(0, bytesFreed)
        persistPendingMetrics()
        scheduleAutomaticFlushIfNeeded()
    }

    func flushPendingMetricsIfNeeded() {
        guard sink.isConfigured, !pendingMetrics.isEmpty else { return }
        Task {
            await flushPendingMetrics()
        }
    }

    private func scheduleAutomaticFlushIfNeeded() {
        guard sink.isConfigured else { return }

        if pendingMetrics.installs > 0 || pendingMetrics.deletedPhotos >= 10 || pendingMetrics.reviewedPhotos >= 25 || pendingMetrics.bytesFreed >= 100_000_000 {
            flushPendingMetricsIfNeeded()
        }
    }

    private func flushPendingMetrics() async {
        guard sink.isConfigured, !pendingMetrics.isEmpty else { return }

        if isFlushing {
            shouldFlushAgain = true
            return
        }

        isFlushing = true
        let snapshot = pendingMetrics
        let payload = AggregateMetricsPayload(
            installID: installID,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: bundle.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "unknown",
            platform: "ios",
            submittedAt: Date(),
            metrics: snapshot
        )

        do {
            try await sink.send(payload)
            pendingMetrics.subtract(snapshot)
            persistPendingMetrics()
        } catch {
            print("PhotoSoap: metrics flush failed: \(error.localizedDescription)")
        }

        isFlushing = false

        if shouldFlushAgain {
            shouldFlushAgain = false
            await flushPendingMetrics()
        }
    }

    private func persistPendingMetrics() {
        guard let encoded = try? JSONEncoder().encode(pendingMetrics) else { return }
        defaults.set(encoded, forKey: Self.pendingMetricsKey)
    }

    private static func loadPendingMetrics(from defaults: UserDefaults) -> AggregateMetrics {
        guard let data = defaults.data(forKey: pendingMetricsKey),
              let metrics = try? JSONDecoder().decode(AggregateMetrics.self, from: data) else {
            return AggregateMetrics()
        }

        return metrics
    }
}
