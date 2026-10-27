import Foundation
import Combine
import SwiftData
import SwiftUI

enum StartupRoute: Equatable {
    case quickStart
    case permissionRequest
    case permissionDenied
    case main
}

@MainActor
final class StartupRoutingService: ObservableObject {
    func route(hasSeenQuickStartInfo: Bool, authorizationStatus: PhotoLibraryAuthorizationStatus) -> StartupRoute {
        guard hasSeenQuickStartInfo else { return .quickStart }

        switch authorizationStatus {
        case .notDetermined:
            return .permissionRequest
        case .denied, .restricted:
            return .permissionDenied
        case .authorized, .limited:
            return .main
        }
    }

    func initializeStats(context: ModelContext, currentStats: UserStats?, gamificationService: GamificationService) -> UserStats? {
        do {
            let stats = try UserStats.fetchOrCreateSingleton(in: context)
            gamificationService.ensureDailyChallengeIsSet(stats: stats)
            try context.save()
            return stats
        } catch {
#if DEBUG
            print("PhotoSoap: failed to initialize user stats: \(error.localizedDescription)")
#endif
            return currentStats
        }
    }

    func refreshPhotoLibraryStateIfNeeded(hasSeenQuickStartInfo: Bool, photoLibraryService: PhotoLibraryService) {
        guard hasSeenQuickStartInfo else { return }
        photoLibraryService.refreshLibraryAccessState()
    }

    func trackAppOpenIfNeeded(hasTrackedAppOpen: inout Bool, privacyCollectionService: PrivacyCollectionService) {
        guard !hasTrackedAppOpen else { return }
        privacyCollectionService.track(.appOpened())
        hasTrackedAppOpen = true
    }

    func handleScenePhase(
        _ scenePhase: ScenePhase,
        hasSeenQuickStartInfo: Bool,
        photoLibraryService: PhotoLibraryService,
        privacyCollectionService: PrivacyCollectionService
    ) {
        switch scenePhase {
        case .active:
            refreshPhotoLibraryStateIfNeeded(
                hasSeenQuickStartInfo: hasSeenQuickStartInfo,
                photoLibraryService: photoLibraryService
            )
            privacyCollectionService.flushPendingMetricsIfNeeded()
        case .inactive, .background:
            privacyCollectionService.flushPendingMetricsIfNeeded()
        @unknown default:
            break
        }
    }

    func trackPermissionStatus(_ status: PhotoLibraryAuthorizationStatus, privacyCollectionService: PrivacyCollectionService) {
        privacyCollectionService.track(.permissionStatusChanged(status))
    }

    func trackTabSelection(_ tabName: String, privacyCollectionService: PrivacyCollectionService) {
        privacyCollectionService.track(.tabSelected(tabName))
    }

    func requestAuthorization(photoLibraryService: PhotoLibraryService, privacyCollectionService: PrivacyCollectionService) async {
        privacyCollectionService.track(.permissionRequestTapped())
        _ = await photoLibraryService.requestAuthorization()
    }

    func openSettings(photoLibraryService: PhotoLibraryService, privacyCollectionService: PrivacyCollectionService) {
        privacyCollectionService.track(.settingsOpened())
        photoLibraryService.openAppSettings()
    }
}
