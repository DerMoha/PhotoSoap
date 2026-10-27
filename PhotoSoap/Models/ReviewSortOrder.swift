import Foundation

enum ReviewSortOrder: String, CaseIterable {
    case random
    case newestFirst
    case oldestFirst
    case largestFirst

    static func stored(in defaults: UserDefaults) -> ReviewSortOrder {
        guard let rawValue = defaults.string(forKey: UserDefaultsKeys.reviewSortOrder),
              let order = ReviewSortOrder(rawValue: rawValue) else {
            return .random
        }
        return order
    }
}
