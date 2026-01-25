import Foundation
import SwiftData

@Model
class ReviewedPhoto {
    @Attribute(.unique) var id: String
    var reviewDate: Date

    init(id: String, reviewDate: Date = Date()) {
        self.id = id
        self.reviewDate = reviewDate
    }
}
