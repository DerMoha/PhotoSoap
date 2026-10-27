import Foundation
import SwiftData

@Model
class ReviewedPhoto {
    @Attribute(.unique) var id: String
    var reviewDate: Date
    var mediaTypeRawValue: String = ReviewMediaType.photo.rawValue

    init(id: String, reviewDate: Date = Date(), mediaType: ReviewMediaType = .photo) {
        self.id = id
        self.reviewDate = reviewDate
        self.mediaTypeRawValue = mediaType.rawValue
    }

    var reviewMediaType: ReviewMediaType {
        ReviewMediaType(rawValue: mediaTypeRawValue) ?? .photo
    }
}
