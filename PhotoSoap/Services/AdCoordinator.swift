import Foundation
import Combine

enum AdPlacement: String, CaseIterable, Identifiable {
    case reviewBanner

    var id: String { rawValue }

    var displayName: String {
        "Review banner"
    }

    var kind: AdPlacementKind {
        .banner
    }
}

enum AdPlacementKind {
    case banner
}

enum AdMobConfig {
    static let appIDInfoKey = "GADApplicationIdentifier"
    static let reviewBannerUnitIDInfoKey = "PhotoSoapAdMobReviewBannerUnitID"
}

struct AdMobRuntimeConfiguration {
    let appID: String
    let unitIDsByPlacement: [AdPlacement: String]

    var isConfigured: Bool {
        !appID.isEmpty && unitIDsByPlacement[.reviewBanner]?.isEmpty == false
    }

    static func from(bundle: Bundle) -> AdMobRuntimeConfiguration {
        let info = bundle.infoDictionary ?? [:]

        return AdMobRuntimeConfiguration(
            appID: info[AdMobConfig.appIDInfoKey] as? String ?? "",
            unitIDsByPlacement: [
                .reviewBanner: info[AdMobConfig.reviewBannerUnitIDInfoKey] as? String ?? ""
            ]
        )
    }
}

@MainActor
final class AdCoordinator: ObservableObject {
    @Published private(set) var adsEnabled = false
    @Published private(set) var isConfigured = false

    private let configuration: AdMobRuntimeConfiguration
    private var hasAdRemovalEntitlement = false

    init(configuration: AdMobRuntimeConfiguration? = nil) {
        self.configuration = configuration ?? AdMobRuntimeConfiguration.from(bundle: .main)
        refreshConfigurationState()
    }

    var statusSummary: String {
        if hasAdRemovalEntitlement {
            return "Ad-free is active, so the review banner stays hidden."
        }

        if !isConfigured {
            return "Banner ads are not configured yet."
        }

        return "One banner can appear below the current photo while you review."
    }

    func unitID(for placement: AdPlacement) -> String? {
        configuration.unitIDsByPlacement[placement]
    }

    func shouldShowBanner(at placement: AdPlacement) -> Bool {
        placement.kind == .banner && adsEnabled && unitID(for: placement)?.isEmpty == false
    }

    func updateEntitlement(hasAdRemovalEntitlement: Bool) {
        self.hasAdRemovalEntitlement = hasAdRemovalEntitlement
        refreshConfigurationState()
    }

    private func refreshConfigurationState() {
        isConfigured = configuration.isConfigured
        adsEnabled = isConfigured && !hasAdRemovalEntitlement
    }
}
