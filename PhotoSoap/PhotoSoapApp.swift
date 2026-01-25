import SwiftUI
import SwiftData

@main
struct PhotoSoapApp: App {
    let modelContainer: ModelContainer

    init() {
        // Check if we need to clear corrupted data before initializing SwiftData
        Self.clearOversizedDatabaseIfNeeded()
        
        do {
            let schema = Schema([UserStats.self, ReviewedPhoto.self])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            
            // Migrate existing reviewed IDs to ReviewedPhoto entity
            migrateReviewedPhotosIfNeeded()
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }
    
    /// Clears the database if it's too large (prevents memory crash on startup)
    private static func clearOversizedDatabaseIfNeeded() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        
        // SwiftData default database location
        let storeURL = appSupport.appendingPathComponent("default.store")
        
        // Check if database file exists and is suspiciously large (> 50MB suggests bloated data)
        if let attributes = try? fileManager.attributesOfItem(atPath: storeURL.path),
           let fileSize = attributes[.size] as? Int64,
           fileSize > 50_000_000 {
            
            print("PhotoSoap: Database is \(fileSize / 1_000_000)MB - clearing to prevent memory crash")
            
            // Remove all SwiftData store files
            let storeFiles = [
                storeURL,
                storeURL.appendingPathExtension("shm"),
                storeURL.appendingPathExtension("wal")
            ]
            
            for file in storeFiles {
                try? fileManager.removeItem(at: file)
            }
            
            print("PhotoSoap: Database cleared successfully")
        }
    }
    
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
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
