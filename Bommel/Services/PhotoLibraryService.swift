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

    private let imageManager = PHCachingImageManager()
    private var cachedAssets: PHFetchResult<PHAsset>?
    
    // Use lazy random sampling - don't pre-filter everything
    private var totalAssetCount: Int = 0
    private var triedIndices: Set<Int> = []
    private let maxRetries = 50  // Max attempts to find an unreviewed photo

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
        
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.includeHiddenAssets = false

        cachedAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
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
}
