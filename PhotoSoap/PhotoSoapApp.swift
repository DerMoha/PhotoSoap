import SwiftUI
import SwiftData
import GoogleMobileAds

@main
struct PhotoSoapApp: App {
    let modelContainer: ModelContainer
    let bootstrapErrorMessage: String?

    init() {
        MobileAds.shared.start(completionHandler: nil)

        let bootstrap = Self.bootstrapContainer()
        modelContainer = bootstrap.modelContainer
        bootstrapErrorMessage = bootstrap.bootstrapErrorMessage

        if bootstrap.bootstrapErrorMessage == nil {
            // Migrate existing reviewed IDs to ReviewedPhoto entity
            migrateReviewedPhotosIfNeeded()
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
            print("PhotoSoap: Falling back to in-memory store after persistent store failure: \(error)")

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

    private nonisolated static let appSchema = Schema([UserStats.self, ReviewedPhoto.self])
    
    /// Migrates IDs from UserStats array to ReviewedPhoto entities
    private func migrateReviewedPhotosIfNeeded() {
        let context = modelContainer.mainContext
        
        do {
            let descriptor = FetchDescriptor<UserStats>()
            let allStats = try context.fetch(descriptor)

            for stats in allStats {
                if !stats.reviewedPhotoIDs.isEmpty {
                    print("PhotoSoap: Migrating \(stats.reviewedPhotoIDs.count) reviewed photos...")

                    let idsToMigrate = Set(stats.reviewedPhotoIDs)
                    var migrationCount = 0

                    for id in idsToMigrate {
                        let reviewDescriptor = FetchDescriptor<ReviewedPhoto>(predicate: #Predicate { $0.id == id })
                        if try context.fetchCount(reviewDescriptor) == 0 {
                            let review = ReviewedPhoto(id: id)
                            context.insert(review)
                            migrationCount += 1
                        }
                    }

                    if migrationCount > 0 {
                        try context.save()
                        print("PhotoSoap: Successfully migrated \(migrationCount) photos")
                    }

                    stats.reviewedPhotoIDs.removeAll()
                    try context.save()
                }
            }
        } catch {
            print("PhotoSoap: Migration failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(bootstrapErrorMessage: bootstrapErrorMessage)
        }
        .modelContainer(modelContainer)
    }
}

struct AppBootstrapResult {
    let modelContainer: ModelContainer
    let bootstrapErrorMessage: String?
}
