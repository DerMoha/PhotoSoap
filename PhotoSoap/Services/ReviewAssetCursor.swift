import Foundation

struct ReviewAssetCursor {
    private var position = 0
    private var shuffledIndices: [Int]?

    mutating func reset() {
        position = 0
        shuffledIndices = nil
    }

    mutating func nextIndex(count: Int, order: ReviewSortOrder) -> Int? {
        guard position < count else { return nil }
        if order == .random && shuffledIndices == nil {
            shuffledIndices = Array(0..<count).shuffled()
        }
        defer { position += 1 }
        return shuffledIndices?[position] ?? position
    }
}

struct AssetSizeOrdering {
    static func indices(for sizes: [Int64?]) -> [Int] {
        sizes.indices.sorted { left, right in
            switch (sizes[left], sizes[right]) {
            case let (lhs?, rhs?) where lhs != rhs: return lhs > rhs
            case (_?, nil): return true
            case (nil, _?): return false
            default: return left < right
            }
        }
    }
}
