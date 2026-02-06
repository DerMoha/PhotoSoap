import Foundation
import Photos
import UIKit

struct Photo: Identifiable {
    let id: String
    let asset: PHAsset
    var image: UIImage?
    var fileSize: Int64

    // MARK: - Cached Formatters (expensive to create)
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()

    // MARK: - Computed Properties

    var creationDate: Date? {
        asset.creationDate
    }

    var location: CLLocation? {
        asset.location
    }

    var formattedDate: String {
        guard let date = creationDate else { return "Unknown date" }
        return Self.dateFormatter.string(from: date)
    }

    var shortFormattedDate: String {
        guard let date = creationDate else { return "Unknown" }
        return Self.shortDateFormatter.string(from: date)
    }

    var formattedLocation: String? {
        guard let location = location else { return nil }
        return String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
    }

    var dimensions: String {
        "\(asset.pixelWidth) x \(asset.pixelHeight)"
    }

    var compactDimensions: String {
        let width = asset.pixelWidth
        let height = asset.pixelHeight
        if width >= 1000 || height >= 1000 {
            return "\(width/1000)K×\(height/1000)K"
        }
        return "\(width)×\(height)"
    }

    var fileSizeFormatted: String {
        guard fileSize > 0 else { return "Unknown size" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var mediaType: PHAssetMediaType {
        asset.mediaType
    }

    var isVideo: Bool {
        mediaType == .video
    }

    var duration: TimeInterval? {
        isVideo ? asset.duration : nil
    }

    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    init(asset: PHAsset, image: UIImage? = nil, fileSize: Int64 = 0) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.image = image
        self.fileSize = fileSize
    }
}

extension Photo: Equatable {
    static func == (lhs: Photo, rhs: Photo) -> Bool {
        lhs.id == rhs.id
    }
}

extension Photo: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
