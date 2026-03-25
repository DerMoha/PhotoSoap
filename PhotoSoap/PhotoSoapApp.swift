import SwiftUI
import SwiftData
import GoogleMobileAds

@main
struct PhotoSoapApp: App {
    let modelContainer: ModelContainer
    let bootstrapErrorMessage: String?
    let migrationErrorMessage: String?
    let serviceContainer: ServiceContainer

    init() {
        MobileAds.shared.start(completionHandler: nil)

        let bootstrap = Self.bootstrapContainer()
        modelContainer = bootstrap.modelContainer
        bootstrapErrorMessage = bootstrap.bootstrapErrorMessage
        migrationErrorMessage = nil

        serviceContainer = ServiceContainer(modelContext: bootstrap.modelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(bootstrapErrorMessage: bootstrapErrorMessage, migrationErrorMessage: migrationErrorMessage)
                .environmentObject(serviceContainer)
                .environmentObject(serviceContainer.photoLibraryService)
                .environmentObject(serviceContainer.gamificationService)
                .environmentObject(serviceContainer.adRemovalPurchaseService)
                .environmentObject(serviceContainer.adCoordinator)
                .environmentObject(serviceContainer.aggregateMetricsService)
                .environmentObject(serviceContainer.analyticsService)
                .environmentObject(serviceContainer.hapticsService)
        }
        .modelContainer(modelContainer)
    }

    private static func bootstrapContainer(
        makeContainer: (Schema, ModelConfiguration) throws -> ModelContainer = { schema, configuration in
            try ModelContainer(for: schema, configurations: [configuration])
        }
    ) -> AppBootstrapResult {
        do {
            let schema = Schema([UserStats.self, ReviewedPhoto.self, UnlockedAchievement.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

            return AppBootstrapResult(
                modelContainer: try makeContainer(schema, modelConfiguration),
                bootstrapErrorMessage: nil
            )
        } catch {
            print("PhotoSoap: Falling back to in-memory store after persistent store failure")

            let schema = Schema([UserStats.self, ReviewedPhoto.self, UnlockedAchievement.self])
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

            do {
                return AppBootstrapResult(
                    modelContainer: try makeContainer(schema, fallbackConfiguration),
                    bootstrapErrorMessage: "PhotoSoap could not open your saved data and started in a temporary recovery mode. Your new changes may not persist until this is fixed."
                )
            } catch {
                fatalError("Could not initialize fallback ModelContainer: \(error)")
            }
        }
    }
}

struct AppBootstrapResult {
    let modelContainer: ModelContainer
    let bootstrapErrorMessage: String?
}
