import Foundation
import Combine

enum AdPlacement: String, CaseIterable, Identifiable {
    case statsBanner
    case achievementsBanner
    case reviewCompletionInterstitial

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .statsBanner:
            return "Stats banner"
        case .achievementsBanner:
            return "Achievements banner"
        case .reviewCompletionInterstitial:
            return "Review completion interstitial"
        }
    }

    var kind: AdPlacementKind {
        switch self {
        case .statsBanner, .achievementsBanner:
            return .banner
        case .reviewCompletionInterstitial:
            return .interstitial
        }
    }
}

enum AdPlacementKind {
    case banner
    case interstitial
}

enum AdMobConfig {
    static let appIDInfoKey = "GADApplicationIdentifier"
    static let usesTestIdentifiersInfoKey = "PhotoSoapUsesAdMobTestIdentifiers"
    static let statsBannerUnitIDInfoKey = "PhotoSoapAdMobStatsBannerUnitID"
    static let achievementsBannerUnitIDInfoKey = "PhotoSoapAdMobAchievementsBannerUnitID"
    static let reviewInterstitialUnitIDInfoKey = "PhotoSoapAdMobReviewInterstitialUnitID"

    static let testAppID = "ca-app-pub-3940256099942544~1458002511"
    static let testBannerUnitID = "ca-app-pub-3940256099942544/2435281174"
    static let testInterstitialUnitID = "ca-app-pub-3940256099942544/4411468910"
}

struct AdMobRuntimeConfiguration {
    let appID: String
    let usesTestIdentifiers: Bool
    let unitIDsByPlacement: [AdPlacement: String]
    let hasTrackingUsageDescription: Bool

    var isConfigured: Bool {
        !appID.isEmpty && AdPlacement.allCases.allSatisfy { unitIDsByPlacement[$0]?.isEmpty == false }
    }

    static func from(bundle: Bundle) -> AdMobRuntimeConfiguration {
        let info = bundle.infoDictionary ?? [:]
        let trackingDescription = info["NSUserTrackingUsageDescription"] as? String

        return AdMobRuntimeConfiguration(
            appID: info[AdMobConfig.appIDInfoKey] as? String ?? "",
            usesTestIdentifiers: info[AdMobConfig.usesTestIdentifiersInfoKey] as? Bool ?? false,
            unitIDsByPlacement: [
                .statsBanner: info[AdMobConfig.statsBannerUnitIDInfoKey] as? String ?? "",
                .achievementsBanner: info[AdMobConfig.achievementsBannerUnitIDInfoKey] as? String ?? "",
                .reviewCompletionInterstitial: info[AdMobConfig.reviewInterstitialUnitIDInfoKey] as? String ?? ""
            ],
            hasTrackingUsageDescription: trackingDescription?.isEmpty == false
        )
    }
}

@MainActor
final class AdCoordinator: ObservableObject {
    @Published private(set) var adsEnabled = false
    @Published private(set) var isConfigured = false
    @Published private(set) var usesTestIdentifiers = false
    @Published private(set) var hasTrackingUsageDescription = false

    private let configuration: AdMobRuntimeConfiguration
    private var hasAdRemovalEntitlement = false

    let bannerPlacements: [AdPlacement] = [.statsBanner, .achievementsBanner]
    let interstitialPlacements: [AdPlacement] = [.reviewCompletionInterstitial]

    init(configuration: AdMobRuntimeConfiguration? = nil) {
        self.configuration = configuration ?? AdMobRuntimeConfiguration.from(bundle: .main)
        refreshConfigurationState()
    }

    var statusSummary: String {
        if hasAdRemovalEntitlement {
            return "Ads are suppressed because ad-free access is unlocked."
        }

        if !isConfigured {
            return "Ad placements are scaffolded, but AdMob identifiers still need to be configured."
        }

        if usesTestIdentifiers {
            return "AdMob test identifiers are configured for development and review-safe wiring."
        }

        return "Production ad identifiers are configured and ready for SDK wiring."
    }

    var integrationChecklist: [String] {
        var items = [String]()

        if !isConfigured {
            items.append("Replace the AdMob identifiers in Info.plist before enabling production ads.")
        }

        if !hasTrackingUsageDescription {
            items.append("Add an App Tracking Transparency purpose string before requesting personalized ads.")
        }

        if usesTestIdentifiers {
            items.append("Keep using test identifiers in development and switch to production IDs before release.")
        }

        if items.isEmpty {
            items.append("Link the ad SDK and load placements through AdCoordinator.")
        }

        return items
    }

    func unitID(for placement: AdPlacement) -> String? {
        configuration.unitIDsByPlacement[placement]
    }

    func shouldShowBanner(at placement: AdPlacement) -> Bool {
        placement.kind == .banner && adsEnabled && unitID(for: placement)?.isEmpty == false
    }

    func canPresentInterstitial(at placement: AdPlacement) -> Bool {
        placement.kind == .interstitial && adsEnabled && unitID(for: placement)?.isEmpty == false
    }

    func updateEntitlement(hasAdRemovalEntitlement: Bool) {
        self.hasAdRemovalEntitlement = hasAdRemovalEntitlement
        refreshConfigurationState()
    }

    private func refreshConfigurationState() {
        isConfigured = configuration.isConfigured
        usesTestIdentifiers = configuration.usesTestIdentifiers
        hasTrackingUsageDescription = configuration.hasTrackingUsageDescription
        adsEnabled = isConfigured && !hasAdRemovalEntitlement
    }
}
