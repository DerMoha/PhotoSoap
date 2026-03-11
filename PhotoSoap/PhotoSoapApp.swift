import SwiftUI
import SwiftData

@main
struct PhotoSoapApp: App {
    let modelContainer: ModelContainer
    let bootstrapErrorMessage: String?

    init() {
        do {
            let schema = Self.appSchema
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            bootstrapErrorMessage = nil

            // Migrate existing reviewed IDs to ReviewedPhoto entity
            migrateReviewedPhotosIfNeeded()
        } catch {
            print("PhotoSoap: Falling back to in-memory store after persistent store failure: \(error)")

            let schema = Self.appSchema
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

            do {
                modelContainer = try ModelContainer(
                    for: schema,
                    configurations: [fallbackConfiguration]
                )
                bootstrapErrorMessage = "PhotoSoap could not open your saved data and started in a temporary recovery mode. Your new changes may not persist until this is fixed."
            } catch {
                fatalError("Could not initialize fallback ModelContainer: \(error)")
            }
        }
    }

    private static let appSchema = Schema([UserStats.self, ReviewedPhoto.self])
    
    /// Migrates IDs from UserStats array to ReviewedPhoto entities
    private func migrateReviewedPhotosIfNeeded() {
        let context = modelContainer.mainContext
        
        do {
            let descriptor = FetchDescriptor<UserStats>()
            let allStats = try context.fetch(descriptor)
            
            var migrationCount = 0
            
            for stats in allStats {
                if !stats.reviewedPhotoIDs.isEmpty {
                    print("PhotoSoap: Migrating \(stats.reviewedPhotoIDs.count) reviewed photos...")
                    
                    // 1. Get all IDs to migrate
                    let idsToMigrate = Set(stats.reviewedPhotoIDs)
                    
                    // 2. Fetch ANY existing IDs from DB that match (to avoid duplicates)
                    // Efficiently: fetch only IDs
                    let allExistingDescriptor = FetchDescriptor<ReviewedPhoto>()
                    let allExistingPhotos = try context.fetch(allExistingDescriptor)
                    let existingIDSet = Set(allExistingPhotos.map { $0.id })
                    
                    for id in idsToMigrate {
                        if !existingIDSet.contains(id) {
                            let review = ReviewedPhoto(id: id)
                            context.insert(review)
                            migrationCount += 1
                        }
                    }
                    
                    if migrationCount > 0 {
                        try context.save()
                        print("PhotoSoap: Successfully migrated \(migrationCount) photos")
                        
                        // Clear the array ONLY after successful save to prevent data loss
                        stats.reviewedPhotoIDs.removeAll()
                    } else {
                        // If no migration needed (all duplicates), still clear array
                        stats.reviewedPhotoIDs.removeAll()
                    }
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
