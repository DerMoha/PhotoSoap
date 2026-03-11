import Foundation
import Photos
import UIKit
import Combine

enum PhotoLibraryError: Error, LocalizedError {
    case accessDenied
    case accessRestricted
    case noPhotosAvailable
    case deletionFailed
    case loadingFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Photo library access was denied. Please enable access in Settings."
        case .accessRestricted:
            return "Photo library access is restricted."
        case .noPhotosAvailable:
            return "No photos available to review."
        case .deletionFailed:
            return "Failed to delete the photo."
        case .loadingFailed:
            return "Failed to load photo."
        }
    }
}

enum PhotoLibraryAuthorizationStatus {
    case notDetermined
    case authorized
    case denied
    case restricted
    case limited
}

@MainActor
class PhotoLibraryService: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var authorizationStatus: PhotoLibraryAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    @Published var error: PhotoLibraryError?
    @Published var currentFilter: PhotoFilter = .all

    private let imageManager = PHCachingImageManager()
    private var cachedAssets: PHFetchResult<PHAsset>?
    
    // Use lazy random sampling - don't pre-filter everything
    private var totalAssetCount: Int = 0
    private let baseMaxRetries = 50  // Base attempts to find an unreviewed photo

    private var cachedYears: [Int] = []
    private var cachedMonthsByYear: [Int: [Int]] = [:]

    private let excludedSmartAlbumSubtypes: Set<PHAssetCollectionSubtype> = [
        .smartAlbumAllHidden,
        .smartAlbumUserLibrary
    ]
    
    // Session cache for O(1) filtering of items already seen during this run.
    private var sessionReviewedIDs: Set<String> = []

    override init() {
        super.init()
        checkAuthorizationStatus()
        PHPhotoLibrary.shared().register(self)
    }
    
    func setSessionReviewedIDs(_ ids: Set<String>) {
        sessionReviewedIDs = ids
    }
    
    func markReviewed(_ id: String) {
        sessionReviewedIDs.insert(id)
    }
    
    func isReviewed(_ id: String) -> Bool {
        sessionReviewedIDs.contains(id)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: - PHPhotoLibraryChangeObserver

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            guard let assets = self.cachedAssets,
                  let changes = changeInstance.changeDetails(for: assets) else {
                return
            }
            self.cachedAssets = changes.fetchResultAfterChanges
            self.totalAssetCount = self.cachedAssets?.count ?? 0
        }
    }

    func checkAuthorizationStatus() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        updateAuthorizationStatus(status)
    }

    private func updateAuthorizationStatus(_ status: PHAuthorizationStatus) {
        switch status {
        case .notDetermined:
            authorizationStatus = .notDetermined
        case .authorized:
            authorizationStatus = .authorized
        case .denied:
            authorizationStatus = .denied
        case .restricted:
            authorizationStatus = .restricted
        case .limited:
            authorizationStatus = .limited
        @unknown default:
            authorizationStatus = .denied
        }
    }

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        updateAuthorizationStatus(status)
        return status == .authorized || status == .limited
    }

    /// Fetches assets lazily - only gets the count, doesn't iterate
    private func ensureAssetsFetched() {
        guard cachedAssets == nil else { return }

        switch currentFilter {
        case .all:
            let options = makeFetchOptions(dateInterval: nil, includeMediaTypePredicate: false)
            cachedAssets = PHAsset.fetchAssets(with: .image, options: options)
        case .year(let year):
            let interval = dateIntervalForYear(year)
            let options = makeFetchOptions(dateInterval: interval, includeMediaTypePredicate: false)
            cachedAssets = PHAsset.fetchAssets(with: .image, options: options)
        case .month(let year, let month):
            let interval = dateIntervalForMonth(year: year, month: month)
            let options = makeFetchOptions(dateInterval: interval, includeMediaTypePredicate: false)
            cachedAssets = PHAsset.fetchAssets(with: .image, options: options)
        case .album(let identifier, _):
            guard let collection = fetchAssetCollection(identifier: identifier) else {
                cachedAssets = nil
                totalAssetCount = 0
                return
            }
            let options = makeFetchOptions(dateInterval: nil, includeMediaTypePredicate: true)
            cachedAssets = PHAsset.fetchAssets(in: collection, options: options)
        }

        totalAssetCount = cachedAssets?.count ?? 0
    }

    /// Gets next photo using random sampling - O(1) memory instead of O(n)
    func getNextPhoto(excluding excludedIDs: Set<String> = []) async throws -> Photo? {
        ensureAssetsFetched()
        
        guard let assets = cachedAssets, totalAssetCount > 0 else {
            return nil
        }
        
        let reviewedCount = sessionReviewedIDs.count
        
        // Completion check removed to support deleted photos logic.
        // Even if reviewedCount >= totalAssetCount, some of those reviewedIDs might imply deleted photos.
        // We rely on the retry loop to find any remaining unreviewed photos.
        
        // Scale retries based on how many photos are excluded (more excluded = harder to find unreviewed)
        let excludedRatio = Double(reviewedCount) / Double(totalAssetCount)
        let scaledRetries = max(baseMaxRetries, Int(Double(baseMaxRetries) * (1.0 + excludedRatio * 4.0)))
        
        // Cap retries at a reasonable limit (e.g. 500) to prevent freezing
        let retries = min(500, scaledRetries)
        
        // Random sampling with retry
        for _ in 0..<retries {
            let randomIndex = Int.random(in: 0..<totalAssetCount)
            
            // Bounds check - totalAssetCount may briefly exceed actual count during observer update
            guard randomIndex < assets.count else { continue }
            
            // Get the asset at this index (single access, not iteration)
            let asset = assets.object(at: randomIndex)
            
            // Check if excluded (reviewed) - O(1) Set lookup
            if sessionReviewedIDs.contains(asset.localIdentifier) || excludedIDs.contains(asset.localIdentifier) {
                continue
            }
            
            // Found a valid photo - load and return it
            return try await loadPhoto(from: asset)
        }
        
        // Couldn't find an unreviewed photo after max retries
        return nil
    }


    func preloadPhotos(count: Int = 3) async -> [Photo] {
        var photos: [Photo] = []
        var temporaryExcluded = Set<String>()
        var attempts = 0
        let maxAttempts = count * 3 // Prevent infinite loops if library is small

        while photos.count < count && attempts < maxAttempts {
            attempts += 1
            if let photo = try? await getNextPhoto() {
                // Avoid preloading the same photo twice in one batch
                if !temporaryExcluded.contains(photo.id) {
                    photos.append(photo)
                    temporaryExcluded.insert(photo.id)
                }
            } else {
                // If getNextPhoto returns nil (no more photos), stop trying
                break
            }
        }
        
        return photos
    }

    private func loadPhoto(from asset: PHAsset) async throws -> Photo {
        // Use a reasonable preview size to avoid memory issues
        let maxDimension: CGFloat = 800
        let scale = min(maxDimension / CGFloat(asset.pixelWidth), maxDimension / CGFloat(asset.pixelHeight), 1.0)
        let targetSize = CGSize(
            width: CGFloat(asset.pixelWidth) * scale,
            height: CGFloat(asset.pixelHeight) * scale
        )

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat  // Always get high quality, not thumbnail
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .fast

        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard !hasResumed else { return }
                hasResumed = true

                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                let photo = Photo(asset: asset, image: image, fileSize: 0)
                continuation.resume(returning: photo)
            }
        }
    }

    func fetchFileSize(for asset: PHAsset, allowNetworkAccess: Bool = false) async -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = preferredResource(from: resources) else {
            return 0
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = allowNetworkAccess

        return await withCheckedContinuation { continuation in
            var totalBytes: Int64 = 0

            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options
            ) { data in
                totalBytes += Int64(data.count)
            } completionHandler: { error in
                if let error {
                    print("PhotoSoap: Failed to fetch file size for \(asset.localIdentifier): \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }

                continuation.resume(returning: totalBytes)
            }
        }
    }

    func deletePhoto(_ photo: Photo) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([photo.asset] as NSFastEnumeration)
        }
    }

    /// Returns approximate count - doesn't iterate through all photos
    func getTotalPhotoCount() -> Int {
        ensureAssetsFetched()
        return totalAssetCount
    }

    func refreshLibrary() {
        cachedAssets = nil
        totalAssetCount = 0
        ensureAssetsFetched()
    }

    func setFilter(_ filter: PhotoFilter) {
        guard filter != currentFilter else { return }
        currentFilter = filter
        cachedAssets = nil
        totalAssetCount = 0
    }

    func fetchAlbums() -> [AlbumInfo] {
        var albums: [AlbumInfo] = []
        let options = makeFetchOptions(dateInterval: nil, includeMediaTypePredicate: true)

        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let assets = PHAsset.fetchAssets(in: collection, options: options)
            guard assets.count > 0 else { return }
            let title = collection.localizedTitle ?? "Untitled Album"
            albums.append(
                AlbumInfo(
                    id: collection.localIdentifier,
                    title: title,
                    count: assets.count,
                    collectionType: collection.assetCollectionType,
                    collectionSubtype: collection.assetCollectionSubtype
                )
            )
        }

        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        smartAlbums.enumerateObjects { collection, _, _ in
            guard !self.excludedSmartAlbumSubtypes.contains(collection.assetCollectionSubtype) else { return }
            let assets = PHAsset.fetchAssets(in: collection, options: options)
            guard assets.count > 0 else { return }
            let title = collection.localizedTitle ?? "Untitled Album"
            albums.append(
                AlbumInfo(
                    id: collection.localIdentifier,
                    title: title,
                    count: assets.count,
                    collectionType: collection.assetCollectionType,
                    collectionSubtype: collection.assetCollectionSubtype
                )
            )
        }

        return albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func getAvailableYears() -> [Int] {
        buildYearMonthCacheIfNeeded()
        return cachedYears
    }

    func getAvailableMonths(for year: Int) -> [Int] {
        buildYearMonthCacheIfNeeded()
        return cachedMonthsByYear[year] ?? []
    }

    private func buildYearMonthCacheIfNeeded() {
        guard cachedYears.isEmpty else { return }

        let options = makeFetchOptions(dateInterval: nil, includeMediaTypePredicate: false)
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        let calendar = Calendar.current
        var years = Set<Int>()
        var monthsByYear: [Int: Set<Int>] = [:]

        assets.enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            years.insert(year)
            monthsByYear[year, default: []].insert(month)
        }

        cachedYears = years.sorted(by: >)
        cachedMonthsByYear = monthsByYear.mapValues { $0.sorted() }
    }

    private func fetchAssetCollection(identifier: String) -> PHAssetCollection? {
        let result = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil)
        return result.firstObject
    }

    private func dateIntervalForYear(_ year: Int) -> DateInterval? {
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = 1
        startComponents.day = 1

        var endComponents = DateComponents()
        endComponents.year = year + 1
        endComponents.month = 1
        endComponents.day = 1

        let calendar = Calendar.current
        guard let startDate = calendar.date(from: startComponents),
              let endDate = calendar.date(from: endComponents) else {
            return nil
        }

        return DateInterval(start: startDate, end: endDate)
    }

    private func dateIntervalForMonth(year: Int, month: Int) -> DateInterval? {
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = month
        startComponents.day = 1

        let calendar = Calendar.current
        guard let startDate = calendar.date(from: startComponents),
              let endDate = calendar.date(byAdding: .month, value: 1, to: startDate) else {
            return nil
        }

        return DateInterval(start: startDate, end: endDate)
    }

    private func makeFetchOptions(
        dateInterval: DateInterval?,
        includeMediaTypePredicate: Bool
    ) -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false

        var predicates: [NSPredicate] = []

        if includeMediaTypePredicate {
            predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue))
        }

        if let interval = dateInterval {
            predicates.append(
                NSPredicate(
                    format: "creationDate >= %@ AND creationDate < %@",
                    interval.start as NSDate,
                    interval.end as NSDate
                )
            )
        }

        if !predicates.isEmpty {
            fetchOptions.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        return fetchOptions
    }

    private func preferredResource(from resources: [PHAssetResource]) -> PHAssetResource? {
        resources.first {
            $0.type == .fullSizePhoto || $0.type == .photo
        } ?? resources.first
    }
}
