import SwiftUI
import SwiftData

@main
struct BommelApp: App {
    let modelContainer: ModelContainer

    init() {
        // Check if we need to clear corrupted data before initializing SwiftData
        Self.clearOversizedDatabaseIfNeeded()
        
        do {
            let schema = Schema([UserStats.self])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            
            // Trim data to prevent future issues
            trimReviewedPhotoIDsIfNeeded()
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
            
            print("Bommel: Database is \(fileSize / 1_000_000)MB - clearing to prevent memory crash")
            
            // Remove all SwiftData store files
            let storeFiles = [
                storeURL,
                storeURL.appendingPathExtension("shm"),
                storeURL.appendingPathExtension("wal")
            ]
            
            for file in storeFiles {
                try? fileManager.removeItem(at: file)
            }
            
            print("Bommel: Database cleared successfully")
        }
    }
    
    /// Trims the reviewedPhotoIDs array to prevent future bloat
    private func trimReviewedPhotoIDsIfNeeded() {
        let context = modelContainer.mainContext
        
        do {
            let descriptor = FetchDescriptor<UserStats>()
            let allStats = try context.fetch(descriptor)
            
            for stats in allStats {
                let maxIDs = 10000
                if stats.reviewedPhotoIDs.count > maxIDs {
                    let excess = stats.reviewedPhotoIDs.count - maxIDs
                    stats.reviewedPhotoIDs.removeFirst(excess)
                }
            }
            
            try context.save()
        } catch {
            print("Bommel: Trim migration failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
