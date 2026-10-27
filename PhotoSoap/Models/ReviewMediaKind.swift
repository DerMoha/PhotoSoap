import Foundation

enum ReviewMediaKind: String, CaseIterable, Identifiable, Hashable {
    case photos
    case videos
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .photos:
            return String(localized: "filter.media.photos", defaultValue: "Photos", table: "LocalizableFilter")
        case .videos:
            return String(localized: "filter.media.videos", defaultValue: "Videos", table: "LocalizableFilter")
        case .all:
            return String(localized: "filter.media.all", defaultValue: "All", table: "LocalizableFilter")
        }
    }

    var allFilterTitle: String {
        switch self {
        case .photos:
            return String(localized: "filter.allPhotos", defaultValue: "All Photos", table: "LocalizableFilter")
        case .videos:
            return String(localized: "filter.allVideos", defaultValue: "All Videos", table: "LocalizableFilter")
        case .all:
            return String(localized: "filter.allMedia", defaultValue: "All Media", table: "LocalizableFilter")
        }
    }

    var libraryDescription: String {
        switch self {
        case .photos:
            return String(localized: "filter.entirePhotoLibrary", defaultValue: "Your photo library", table: "LocalizableFilter")
        case .videos:
            return String(localized: "filter.entireVideoLibrary", defaultValue: "Your video library", table: "LocalizableFilter")
        case .all:
            return String(localized: "filter.entireMediaLibrary", defaultValue: "Your photos and videos", table: "LocalizableFilter")
        }
    }
}

enum ReviewMediaType: String, CaseIterable, Identifiable, Hashable {
    case photo
    case video

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .photo:
            return String(localized: "filter.media.photos", defaultValue: "Photos", table: "LocalizableFilter")
        case .video:
            return String(localized: "filter.media.videos", defaultValue: "Videos", table: "LocalizableFilter")
        }
    }

    var systemImage: String {
        switch self {
        case .photo:
            return "photo.stack"
        case .video:
            return "video.fill"
        }
    }
}
