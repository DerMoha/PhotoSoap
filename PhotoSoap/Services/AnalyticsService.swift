import Foundation
import Combine

struct AnalyticsEvent: Equatable {
    let name: String
    let properties: [String: String]

    init(_ name: String, properties: [String: String] = [:]) {
        self.name = name
        self.properties = properties
    }

    static func appOpened() -> AnalyticsEvent {
        AnalyticsEvent("app_opened")
    }

    static func permissionStatusChanged(_ status: PhotoLibraryAuthorizationStatus) -> AnalyticsEvent {
        AnalyticsEvent("photo_permission_status_changed", properties: ["status": status.analyticsValue])
    }

    static func permissionRequestTapped() -> AnalyticsEvent {
        AnalyticsEvent("photo_permission_request_tapped")
    }

    static func settingsOpened() -> AnalyticsEvent {
        AnalyticsEvent("settings_opened")
    }

    static func limitedLibraryPickerOpened() -> AnalyticsEvent {
        AnalyticsEvent("limited_library_picker_opened")
    }

    static func tabSelected(_ tab: String) -> AnalyticsEvent {
        AnalyticsEvent("tab_selected", properties: ["tab": tab])
    }

    static func reviewStarted(filter: PhotoFilter) -> AnalyticsEvent {
        AnalyticsEvent("review_started", properties: ["filter": filter.analyticsValue])
    }

    static func photoKept(filter: PhotoFilter) -> AnalyticsEvent {
        AnalyticsEvent("photo_kept", properties: ["filter": filter.analyticsValue])
    }

    static func photoDeleted(filter: PhotoFilter) -> AnalyticsEvent {
        AnalyticsEvent("photo_deleted", properties: ["filter": filter.analyticsValue])
    }

    static func reviewBatchCompleted(filter: PhotoFilter) -> AnalyticsEvent {
        AnalyticsEvent("review_batch_completed", properties: ["filter": filter.analyticsValue])
    }

    static func filterApplied(_ filter: PhotoFilter) -> AnalyticsEvent {
        AnalyticsEvent("filter_applied", properties: ["filter": filter.analyticsValue])
    }

    static func statsViewed() -> AnalyticsEvent {
        AnalyticsEvent("stats_viewed")
    }
}

final class AnalyticsService: ObservableObject {
    static let analyticsEnabledKey = "isAnalyticsEnabled"
    static let defaultAnalyticsEnabled = true

    @Published private(set) var recordedEvents: [AnalyticsEvent] = []
    @Published private(set) var isEnabled: Bool

    private let recorder: (AnalyticsEvent) -> Void
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, recorder: ((AnalyticsEvent) -> Void)? = nil) {
        self.defaults = defaults
        self.isEnabled = Self.isEnabled(in: defaults)
        self.recorder = recorder ?? Self.defaultRecorder
    }

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: analyticsEnabledKey) as? Bool ?? defaultAnalyticsEnabled
    }

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }

        recordedEvents.append(event)
        recorder(event)
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        defaults.set(isEnabled, forKey: Self.analyticsEnabledKey)
    }

    nonisolated private static func defaultRecorder(event: AnalyticsEvent) {
        let properties = event.properties
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")

        if properties.isEmpty {
            print("PhotoSoap: analytics \(event.name)")
        } else {
            print("PhotoSoap: analytics \(event.name) [\(properties)]")
        }
    }
}

private extension PhotoLibraryAuthorizationStatus {
    var analyticsValue: String {
        switch self {
        case .notDetermined:
            return "not_determined"
        case .authorized:
            return "authorized"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .limited:
            return "limited"
        }
    }
}

private extension PhotoFilter {
    var analyticsValue: String {
        switch self {
        case .all:
            return "all"
        case .album:
            return "album"
        case .year:
            return "year"
        case .month:
            return "month"
        }
    }
}
