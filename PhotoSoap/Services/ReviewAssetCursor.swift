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
