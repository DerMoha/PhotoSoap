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
class PhotoLibraryService: ObservableObject {
    @Published var authorizationStatus: PhotoLibraryAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    @Published var error: PhotoLibraryError?
    @Published var currentFilter: PhotoFilter = .all

    private let imageManager = PHCachingImageManager()
    private var cachedAssets: PHFetchResult<PHAsset>?
    
    // Use lazy random sampling - don't pre-filter everything
    private var totalAssetCount: Int = 0
    private var triedIndices: Set<Int> = []
    private let maxRetries = 50  // Max attempts to find an unreviewed photo

    private var cachedYears: [Int] = []
    private var cachedMonthsByYear: [Int: [Int]] = [:]

    private let excludedSmartAlbumSubtypes: Set<PHAssetCollectionSubtype> = [
        .smartAlbumAllHidden,
        .smartAlbumUserLibrary
    ]

    init() {
        checkAuthorizationStatus()
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
                triedIndices = []
                return
            }
            let options = makeFetchOptions(dateInterval: nil, includeMediaTypePredicate: true)
            cachedAssets = PHAsset.fetchAssets(in: collection, options: options)
        }

        totalAssetCount = cachedAssets?.count ?? 0
        triedIndices = []
    }

    /// Gets next photo using random sampling - O(1) memory instead of O(n)
    func getNextPhoto(excludingIDs: Set<String>) async throws -> Photo? {
        ensureAssetsFetched()
        
        guard let assets = cachedAssets, totalAssetCount > 0 else {
            return nil
        }
        
        // If we've tried too many indices, the library is likely exhausted
        if triedIndices.count >= totalAssetCount || triedIndices.count >= maxRetries * 10 {
            return nil
        }
        
        // Random sampling with retry
        for _ in 0..<maxRetries {
            let randomIndex = Int.random(in: 0..<totalAssetCount)
            
            // Skip if we've already tried this index
            if triedIndices.contains(randomIndex) {
                continue
            }
            
            triedIndices.insert(randomIndex)
            
            // Get the asset at this index (single access, not iteration)
            let asset = assets.object(at: randomIndex)
            
            // Check if excluded
            if excludingIDs.contains(asset.localIdentifier) {
                continue
            }
            
            // Found a valid photo - load and return it
            return try await loadPhoto(from: asset)
        }
        
        // Couldn't find an unreviewed photo after max retries
        // This likely means most photos have been reviewed
        return nil
    }

    func preloadPhotos(excludingIDs: Set<String>, count: Int = 3) async -> [Photo] {
        var photos: [Photo] = []

        for _ in 0..<count {
            if let photo = try? await getNextPhoto(excludingIDs: excludingIDs) {
                photos.append(photo)
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

                let resources = PHAssetResource.assetResources(for: asset)
                let fileSize = resources.first.flatMap { resource -> Int64? in
                    if let size = resource.value(forKey: "fileSize") as? Int64 {
                        return size
                    }
                    return nil
                } ?? 0

                let photo = Photo(asset: asset, image: image, fileSize: fileSize)
                continuation.resume(returning: photo)
            }
        }
    }

    func deletePhoto(_ photo: Photo) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([photo.asset] as NSFastEnumeration)
        }
    }

    /// Returns approximate count - doesn't iterate through all photos
    func getTotalPhotoCount(excludingIDs: Set<String> = []) -> Int {
        ensureAssetsFetched()
        // Return total count minus excluded (approximation - good enough for UI)
        return max(0, totalAssetCount - excludingIDs.count)
    }

    func refreshLibrary(excludingIDs: Set<String>) {
        cachedAssets = nil
        totalAssetCount = 0
        triedIndices = []
        ensureAssetsFetched()
    }

    func setFilter(_ filter: PhotoFilter) {
        guard filter != currentFilter else { return }
        currentFilter = filter
        cachedAssets = nil
        totalAssetCount = 0
        triedIndices = []
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
}
