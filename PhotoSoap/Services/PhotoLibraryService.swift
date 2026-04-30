import Foundation
import Photos
import PhotosUI
import UIKit
import Combine

// MARK: - Error Types

enum PhotoLibraryError: Error, LocalizedError {
    case accessDenied
    case accessRestricted
    case noPhotosAvailable
    case deletionFailed
    case loadingFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return String(localized: "error.accessDenied", defaultValue: "Photo library access was denied. Please enable access in Settings.", table: "LocalizableShared")
        case .accessRestricted:
            return String(localized: "error.accessRestricted", defaultValue: "Photo library access is restricted.", table: "LocalizableShared")
        case .noPhotosAvailable:
            return String(localized: "error.noPhotosAvailable", defaultValue: "No photos available to review.", table: "LocalizableShared")
        case .deletionFailed:
            return String(localized: "error.deletionFailed", defaultValue: "Failed to delete the photo.", table: "LocalizableShared")
        case .loadingFailed:
            return String(localized: "error.loadingFailed", defaultValue: "Failed to load photo.", table: "LocalizableShared")
        }
    }
}

// MARK: - Authorization

enum PhotoLibraryAuthorizationStatus {
    case notDetermined
    case authorized
    case denied
    case restricted
    case limited

    var hasPhotoAccess: Bool {
        self == .authorized || self == .limited
    }
}

// MARK: - Supporting Types

struct FilterData {
    let albums: [AlbumInfo]
    let availableYears: [Int]
    let availableMonthsByYear: [Int: [Int]]
}

// MARK: - Constants

private enum Constants {
    static let sessionReviewedIDsLimit = 10000
    static let maxPreviewDimension: CGFloat = 800
    static let maxZoomPreviewDimension: CGFloat = 2800
    static let cachingThumbnailSize = CGSize(width: 400, height: 400)
}

// MARK: - PhotoLibraryService

@MainActor
class PhotoLibraryService: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    // MARK: - Published State
    @Published var authorizationStatus: PhotoLibraryAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    @Published var error: PhotoLibraryError?
    @Published var currentFilter: PhotoFilter = .all
    @Published private(set) var libraryRevision = 0
    @Published private(set) var isOldestFirst = false

    // MARK: - Private State
    private let imageManager = PHCachingImageManager()
    private var cachedAssets: PHFetchResult<PHAsset>?
    private var totalAssetCount: Int = 0

    private var cachedAlbums: [AlbumInfo] = []
    private var cachedYears: [Int] = []
    private var cachedMonthsByYear: [Int: [Int]] = [:]

    private let excludedSmartAlbumSubtypes: Set<PHAssetCollectionSubtype> = [
        .smartAlbumAllHidden,
        .smartAlbumUserLibrary
    ]

    private var sessionReviewedIDs: Set<String> = []
    private let fileSizeCache = NSCache<NSString, NSNumber>()
    private var cachedPreloadPhotos: [Photo] = []
    private var isObservingPhotoLibrary = false

    // MARK: - Initialization

    override init() {
        super.init()
        fileSizeCache.countLimit = 1000
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    // MARK: - Session Review Tracking

    func setSessionReviewedIDs(_ ids: Set<String>) {
        sessionReviewedIDs = ids
    }

    func markReviewed(_ id: String) {
        if sessionReviewedIDs.count >= Constants.sessionReviewedIDsLimit {
            let excessCount = Constants.sessionReviewedIDsLimit / 2
            let toRemove = Array(sessionReviewedIDs.prefix(excessCount))
            toRemove.forEach { sessionReviewedIDs.remove($0) }
        }
        sessionReviewedIDs.insert(id)
    }

    func unmarkReviewed(_ id: String) {
        sessionReviewedIDs.remove(id)
    }

    func isReviewed(_ id: String) -> Bool {
        sessionReviewedIDs.contains(id)
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
            self.cachedAlbums = []
            self.cachedYears = []
            self.cachedMonthsByYear = [:]
            self.libraryRevision &+= 1
        }
    }

    // MARK: - Authorization

    func checkAuthorizationStatus() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        updateAuthorizationStatus(status)
    }

    nonisolated static func mappedAuthorizationStatus(from status: PHAuthorizationStatus) -> PhotoLibraryAuthorizationStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .limited: return .limited
        @unknown default: return .denied
        }
    }

    private func updateAuthorizationStatus(_ status: PHAuthorizationStatus) {
        authorizationStatus = Self.mappedAuthorizationStatus(from: status)

        if authorizationStatus.hasPhotoAccess {
            startObservingPhotoLibraryIfNeeded()
        } else {
            stopObservingPhotoLibraryIfNeeded()
        }
    }

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        updateAuthorizationStatus(status)

        if authorizationStatus.hasPhotoAccess {
            refreshLibrary()
        } else {
            invalidateCaches()
        }

        return status == .authorized || status == .limited
    }

    func presentLimitedLibraryPicker() {
        guard authorizationStatus == .limited else {
            openAppSettings()
            return
        }

        guard let presenter = activeViewController() else {
            openAppSettings()
            return
        }

        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshLibraryAccessState()
                self?.libraryRevision &+= 1
            }
        }
    }

    func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(settingsURL)
    }

    // MARK: - Photo Fetching

    private func ensureAssetsFetched() {
        guard authorizationStatus.hasPhotoAccess else {
            cachedAssets = nil
            totalAssetCount = 0
            return
        }

        guard cachedAssets == nil else { return }

        switch currentFilter {
        case .all:
            let options = Self.makeFetchOptions(dateInterval: nil, includeMediaTypePredicate: false, oldestFirst: isOldestFirst)
            cachedAssets = PHAsset.fetchAssets(with: .image, options: options)
        case .year(let year):
            let interval = dateIntervalForYear(year)
            let options = Self.makeFetchOptions(dateInterval: interval, includeMediaTypePredicate: false, oldestFirst: isOldestFirst)
            cachedAssets = PHAsset.fetchAssets(with: .image, options: options)
        case .month(let year, let month):
            let interval = dateIntervalForMonth(year: year, month: month)
            let options = Self.makeFetchOptions(dateInterval: interval, includeMediaTypePredicate: false, oldestFirst: isOldestFirst)
            cachedAssets = PHAsset.fetchAssets(with: .image, options: options)
        case .album(let identifier, _):
            guard let collection = fetchAssetCollection(identifier: identifier) else {
                cachedAssets = nil
                totalAssetCount = 0
                return
            }
            let options = Self.makeFetchOptions(dateInterval: nil, includeMediaTypePredicate: true, oldestFirst: isOldestFirst)
            cachedAssets = PHAsset.fetchAssets(in: collection, options: options)
        }

        totalAssetCount = cachedAssets?.count ?? 0
    }

    func getNextPhoto(excluding excludedIDs: Set<String> = []) async throws -> Photo? {
        ensureAssetsFetched()

        guard let assets = cachedAssets, totalAssetCount > 0 else {
            return nil
        }

        var failedAssetIDs = Set<String>()

        for index in 0..<assets.count {
            let asset = assets.object(at: index)

            if sessionReviewedIDs.contains(asset.localIdentifier)
                || excludedIDs.contains(asset.localIdentifier)
                || failedAssetIDs.contains(asset.localIdentifier) {
                continue
            }

            do {
                return try await loadPhoto(from: asset)
            } catch {
                sessionReviewedIDs.insert(asset.localIdentifier)
                failedAssetIDs.insert(asset.localIdentifier)
                continue
            }
        }

        return nil
    }

    func preloadPhotos(count: Int = 3) async -> [Photo] {
        stopCachingAssets(for: cachedPreloadPhotos)

        var photos: [Photo] = []
        var temporaryExcluded = Set<String>()
        var attempts = 0
        let maxAttempts = count * 3

        while photos.count < count && attempts < maxAttempts {
            attempts += 1
            if let photo = try? await getNextPhoto() {
                if !temporaryExcluded.contains(photo.id) {
                    photos.append(photo)
                    temporaryExcluded.insert(photo.id)
                }
            } else {
                break
            }
        }

        cachedPreloadPhotos = photos
        startCachingAssets(for: photos)

        return photos
    }

    private func startCachingAssets(for photos: [Photo]) {
        guard !photos.isEmpty else { return }
        let assets = photos.map { $0.asset }
        imageManager.startCachingImages(for: assets, targetSize: Constants.cachingThumbnailSize, contentMode: .aspectFit, options: nil)
    }

    private func stopCachingAssets(for photos: [Photo]) {
        guard !photos.isEmpty else { return }
        let assets = photos.map { $0.asset }
        imageManager.stopCachingImages(for: assets, targetSize: Constants.cachingThumbnailSize, contentMode: .aspectFit, options: nil)
    }

    private func loadPhoto(from asset: PHAsset) async throws -> Photo {
        let maxDimension = Constants.maxPreviewDimension
        let scale = min(maxDimension / CGFloat(asset.pixelWidth), maxDimension / CGFloat(asset.pixelHeight), 1.0)
        let targetSize = CGSize(
            width: CGFloat(asset.pixelWidth) * scale,
            height: CGFloat(asset.pixelHeight) * scale
        )

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
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

                let isCancelled = info?[PHImageCancelledKey] as? Bool ?? false
                if isCancelled {
                    hasResumed = true
                    continuation.resume(throwing: PhotoLibraryError.loadingFailed)
                    return
                }

                if let error = info?[PHImageErrorKey] as? Error {
                    hasResumed = true
                    continuation.resume(throwing: error)
                    return
                }

                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                guard !isDegraded else { return }

                guard let image else {
                    hasResumed = true
                    continuation.resume(throwing: PhotoLibraryError.loadingFailed)
                    return
                }

                hasResumed = true
                continuation.resume(returning: Photo(asset: asset, image: image, fileSize: 0))
            }
        }
    }

    func fetchHighResolutionPreviewImage(for asset: PHAsset) async -> UIImage? {
        let targetSize = previewTargetSize(for: asset)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        options.resizeMode = .fast

        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            var hasResumed = false

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                let isCancelled = info?[PHImageCancelledKey] as? Bool ?? false
                if isCancelled {
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(returning: nil)
                    return
                }

                if let error = info?[PHImageErrorKey] as? Error {
                    print("PhotoSoap: Failed to load high-resolution preview: \(error.localizedDescription)")
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(returning: nil)
                    return
                }

                let isDegraded = info?[PHImageResultIsDegradedKey] as? Bool ?? false
                guard !isDegraded else { return }
                guard !hasResumed else { return }

                hasResumed = true
                continuation.resume(returning: image)
            }
        }
    }

    private func previewTargetSize(for asset: PHAsset) -> CGSize {
        let screenScale = UIScreen.main.scale
        let screenBounds = UIScreen.main.bounds
        let baseLongEdge = max(screenBounds.width, screenBounds.height) * screenScale * 2
        let assetLongEdge = CGFloat(max(asset.pixelWidth, asset.pixelHeight))
        let maxDimension = max(Constants.maxPreviewDimension, min(Constants.maxZoomPreviewDimension, baseLongEdge))
        let scale = min(maxDimension / assetLongEdge, 1.0)

        return CGSize(
            width: CGFloat(asset.pixelWidth) * scale,
            height: CGFloat(asset.pixelHeight) * scale
        )
    }

    // MARK: - File Size

    func fetchFileSize(for asset: PHAsset, allowNetworkAccess: Bool = false) async -> Int64 {
        let assetID = asset.localIdentifier

        if let cachedSize = fileSizeCache.object(forKey: assetID as NSString) {
            return cachedSize.int64Value
        }

        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = preferredResource(from: resources) else {
            return 0
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = allowNetworkAccess

        let fileSize: Int64 = await withCheckedContinuation { (continuation: CheckedContinuation<Int64, Never>) in
            var totalBytes: Int64 = 0

            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options
            ) { data in
                totalBytes += Int64(data.count)
            } completionHandler: { error in
                if let error {
                    print("PhotoSoap: Failed to fetch file size for asset: \(error.localizedDescription)")
                    continuation.resume(returning: 0)
                    return
                }

                continuation.resume(returning: totalBytes)
            }
        }

        if fileSize > 0 {
            fileSizeCache.setObject(NSNumber(value: fileSize), forKey: assetID as NSString)
        }

        return fileSize
    }

    func fetchAssets(withLocalIdentifiers identifiers: [String]) -> [String: PHAsset] {
        guard authorizationStatus.hasPhotoAccess, !identifiers.isEmpty else { return [:] }

        let fetchedAssets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var assetsByIdentifier: [String: PHAsset] = [:]

        fetchedAssets.enumerateObjects { asset, _, _ in
            assetsByIdentifier[asset.localIdentifier] = asset
        }

        return assetsByIdentifier
    }

    // MARK: - Deletion

    func deletePhoto(_ photo: Photo) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets([photo.asset] as NSFastEnumeration)
        }
    }

    func deletePhotos(_ photos: [Photo]) async throws {
        let assets = photos.map { $0.asset }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
        }
    }

    // MARK: - Library Refresh

    func getTotalPhotoCount() -> Int {
        ensureAssetsFetched()
        return totalAssetCount
    }

    func refreshLibrary() {
        invalidateCaches()
        guard authorizationStatus.hasPhotoAccess else { return }
        ensureAssetsFetched()
    }

    func refreshLibraryAccessState() {
        checkAuthorizationStatus()

        if authorizationStatus.hasPhotoAccess {
            refreshLibrary()
        } else {
            invalidateCaches()
        }
    }

    private func invalidateCaches() {
        cachedAssets = nil
        totalAssetCount = 0
        cachedAlbums = []
        cachedYears = []
        cachedMonthsByYear = [:]
    }

    private func startObservingPhotoLibraryIfNeeded() {
        guard !isObservingPhotoLibrary else { return }
        PHPhotoLibrary.shared().register(self)
        isObservingPhotoLibrary = true
    }

    private func stopObservingPhotoLibraryIfNeeded() {
        guard isObservingPhotoLibrary else { return }
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        isObservingPhotoLibrary = false
    }

    // MARK: - Filtering

    func setFilter(_ filter: PhotoFilter) {
        guard filter != currentFilter else { return }
        currentFilter = filter
        cachedAssets = nil
        totalAssetCount = 0
    }

    func setSortOrder(oldestFirst: Bool) {
        guard oldestFirst != isOldestFirst else { return }
        isOldestFirst = oldestFirst
        cachedAssets = nil
        totalAssetCount = 0
    }

    func loadFilterData() async -> FilterData {
        if !cachedAlbums.isEmpty && !cachedYears.isEmpty {
            return FilterData(
                albums: cachedAlbums,
                availableYears: cachedYears,
                availableMonthsByYear: cachedMonthsByYear
            )
        }

        let excludedSubtypes = excludedSmartAlbumSubtypes
        let filterData = await Task.detached(priority: .userInitiated) {
            Self.buildFilterData(excludedSmartAlbumSubtypes: excludedSubtypes)
        }.value

        cachedAlbums = filterData.albums
        cachedYears = filterData.availableYears
        cachedMonthsByYear = filterData.availableMonthsByYear
        return filterData
    }

    func fetchAlbums() -> [AlbumInfo] {
        Self.buildAlbums(excludedSmartAlbumSubtypes: excludedSmartAlbumSubtypes)
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

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            let options = Self.makeFetchOptions(dateInterval: nil, includeMediaTypePredicate: false)
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

            let sortedYears = years.sorted(by: >)
            let sortedMonths = monthsByYear.mapValues { $0.sorted() }

            await MainActor.run {
                self.cachedYears = sortedYears
                self.cachedMonthsByYear = sortedMonths
            }
        }
    }

    // MARK: - Static Helpers

    private nonisolated static func buildFilterData(excludedSmartAlbumSubtypes: Set<PHAssetCollectionSubtype>) -> FilterData {
        let albums = buildAlbums(excludedSmartAlbumSubtypes: excludedSmartAlbumSubtypes)
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

        return FilterData(
            albums: albums,
            availableYears: years.sorted(by: >),
            availableMonthsByYear: monthsByYear.mapValues { $0.sorted() }
        )
    }

    private nonisolated static func buildAlbums(excludedSmartAlbumSubtypes: Set<PHAssetCollectionSubtype>) -> [AlbumInfo] {
        var albums: [AlbumInfo] = []
        let options = makeFetchOptions(dateInterval: nil, includeMediaTypePredicate: true)

        let userAlbumCollections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbumCollections.enumerateObjects { collection, _, _ in
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

        let smartAlbumCollections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        smartAlbumCollections.enumerateObjects { collection, _, _ in
            guard !excludedSmartAlbumSubtypes.contains(collection.assetCollectionSubtype) else { return }
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

        let smartAlbums = albums.filter { $0.collectionType == .smartAlbum }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let userAlbums = albums.filter { $0.collectionType == .album }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        return smartAlbums + userAlbums
    }

    private nonisolated static func makeFetchOptions(
        dateInterval: DateInterval?,
        includeMediaTypePredicate: Bool,
        oldestFirst: Bool = false
    ) -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: oldestFirst)]
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

    // MARK: - Private Helpers

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

    private func preferredResource(from resources: [PHAssetResource]) -> PHAssetResource? {
        resources.first {
            $0.type == .fullSizePhoto || $0.type == .photo
        } ?? resources.first
    }

    // MARK: - View Controller Helpers

    private func activeViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first(where: \.isKeyWindow)
            .flatMap { topViewController(from: $0.rootViewController) }
    }

    private func topViewController(from viewController: UIViewController?) -> UIViewController? {
        if let navigationController = viewController as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }

        if let tabBarController = viewController as? UITabBarController {
            return topViewController(from: tabBarController.selectedViewController)
        }

        if let presentedViewController = viewController?.presentedViewController {
            return topViewController(from: presentedViewController)
        }

        return viewController
    }
}
