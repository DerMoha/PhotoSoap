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

        if bootstrap.bootstrapErrorMessage == nil {
            migrationErrorMessage = Self.runMigrations(modelContainer: bootstrap.modelContainer)
        } else {
            migrationErrorMessage = nil
        }

        serviceContainer = ServiceContainer(modelContext: bootstrap.modelContainer.mainContext)
    }

    private static func runMigrations(modelContainer: ModelContainer) -> String? {
        var errors: [String] = []

        if let photoMigrationError = Self.migrateReviewedPhotosIfNeeded(container: modelContainer) {
            errors.append(photoMigrationError)
        }

        if let achievementMigrationError = Self.migrateUnlockedAchievementsIfNeeded(container: modelContainer) {
            errors.append(achievementMigrationError)
        }

        if errors.isEmpty {
            return nil
        } else if errors.count == 1 {
            return errors[0]
        } else {
            return "Some data migrations failed. Your stats may be incomplete."
        }
    }

    nonisolated static func bootstrapContainer(
        makeContainer: (Schema, ModelConfiguration) throws -> ModelContainer = { schema, configuration in
            try ModelContainer(for: schema, configurations: [configuration])
        }
    ) -> AppBootstrapResult {
        do {
            let schema = appSchema
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

            return AppBootstrapResult(
                modelContainer: try makeContainer(schema, modelConfiguration),
                bootstrapErrorMessage: nil
            )
        } catch {
            print("PhotoSoap: Falling back to in-memory store after persistent store failure")

            let schema = appSchema
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

    private nonisolated static let appSchema = Schema([UserStats.self, ReviewedPhoto.self, UnlockedAchievement.self])
    
    private static func migrateReviewedPhotosIfNeeded(container: ModelContainer) -> String? {
        let context = container.mainContext
        
        do {
            let descriptor = FetchDescriptor<UserStats>()
            let allStats = try context.fetch(descriptor)

            for stats in allStats {
                if !stats.reviewedPhotoIDs.isEmpty {
                    print("PhotoSoap: Migrating \(stats.reviewedPhotoIDs.count) reviewed photos...")

                    let existingDescriptor = FetchDescriptor<ReviewedPhoto>()
                    let existingReviews = try context.fetch(existingDescriptor)
                    let existingIDs = Set(existingReviews.map(\.id))

                    let idsToMigrate = stats.reviewedPhotoIDs.filter { !existingIDs.contains($0) }
                    var migrationCount = 0

                    for id in idsToMigrate {
                        let review = ReviewedPhoto(id: id)
                        context.insert(review)
                        migrationCount += 1
                    }

                    if migrationCount > 0 {
                        try context.save()
                        print("PhotoSoap: Successfully migrated \(migrationCount) photos")
                    }

                    stats.reviewedPhotoIDs.removeAll()
                    try context.save()
                }
            }
            return nil
        } catch {
            print("PhotoSoap: Migration failed")
            return "Photo review migration failed. Some photos may be re-reviewed."
        }
    }

    private static func migrateUnlockedAchievementsIfNeeded(container: ModelContainer) -> String? {
        let context = container.mainContext

        do {
            let descriptor = FetchDescriptor<UserStats>()
            let allStats = try context.fetch(descriptor)

            for stats in allStats {
                if !stats.unlockedAchievements.isEmpty {
                    print("PhotoSoap: Migrating \(stats.unlockedAchievements.count) unlocked achievements...")

                    for achievementId in stats.unlockedAchievements {
                        let unlockDescriptor = FetchDescriptor<UnlockedAchievement>(
                            predicate: #Predicate { $0.achievementId == achievementId }
                        )
                        if try context.fetchCount(unlockDescriptor) == 0 {
                            let unlocked = UnlockedAchievement(achievementId: achievementId)
                            context.insert(unlocked)
                        }
                    }

                    try context.save()
                    print("PhotoSoap: Successfully migrated \(stats.unlockedAchievements.count) unlocked achievements")
                }
            }
            return nil
        } catch {
            print("PhotoSoap: Achievement migration failed")
            return "Achievement migration failed. Some achievements may need to be re-earned."
        }
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
        }
        .modelContainer(modelContainer)
    }
}

struct AppBootstrapResult {
    let modelContainer: ModelContainer
    let bootstrapErrorMessage: String?
}
