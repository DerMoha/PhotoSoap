import XCTest
import Photos
@testable import PhotoSoap

final class ReviewSortOrderTests: XCTestCase {
    func testRandomCursorVisitsEveryAssetOnceAndStops() {
        var cursor = ReviewAssetCursor()
        var indices: [Int] = []
        while let index = cursor.nextIndex(count: 100, order: .random) {
            indices.append(index)
        }

        XCTAssertEqual(indices.count, 100)
        XCTAssertEqual(Set(indices), Set(0..<100))
        XCTAssertNil(cursor.nextIndex(count: 100, order: .random))
    }

    func testCursorResetSupportsChangedLibrarySizeAndOrder() {
        var cursor = ReviewAssetCursor()
        _ = cursor.nextIndex(count: 100, order: .random)
        cursor.reset()

        XCTAssertEqual(cursor.nextIndex(count: 2, order: .newestFirst), 0)
        XCTAssertEqual(cursor.nextIndex(count: 2, order: .newestFirst), 1)
        XCTAssertNil(cursor.nextIndex(count: 2, order: .newestFirst))
        cursor.reset()
        XCTAssertNil(cursor.nextIndex(count: 0, order: .random))
        XCTAssertEqual(cursor.nextIndex(count: 1, order: .random), 0)
        XCTAssertNil(cursor.nextIndex(count: 1, order: .random))
    }

    func testUnsetAndInvalidPreferencesDefaultToRandom() throws {
        let suiteName = "ReviewSortOrderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(ReviewSortOrder.stored(in: defaults), .random)
        defaults.set(false, forKey: "filterOldestFirst")
        XCTAssertEqual(ReviewSortOrder.stored(in: defaults), .random)
        defaults.set("invalid", forKey: UserDefaultsKeys.reviewSortOrder)
        XCTAssertEqual(ReviewSortOrder.stored(in: defaults), .random)
    }

    func testAllSelectedOrdersAreRestored() throws {
        let suiteName = "ReviewSortOrderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for order in ReviewSortOrder.allCases {
            defaults.set(order.rawValue, forKey: UserDefaultsKeys.reviewSortOrder)
            XCTAssertEqual(ReviewSortOrder.stored(in: defaults), order)
        }
    }

    func testChronologicalFetchOrdersUseCreationDate() throws {
        for oldestFirst in [false, true] {
            let options = PhotoLibraryService.makeFetchOptions(
                dateInterval: nil,
                mediaKind: .all,
                oldestFirst: oldestFirst
            )
            let descriptor = try XCTUnwrap(options.sortDescriptors?.first)
            XCTAssertEqual(descriptor.key, "creationDate")
            XCTAssertEqual(descriptor.ascending, oldestFirst)
        }
    }
}
