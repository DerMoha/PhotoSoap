import XCTest
import Photos
@testable import PhotoSoap

final class PhotoFilterTests: XCTestCase {
    func testFavoritesAreExcludedByDefaultForPhotosAndVideos() throws {
        for mediaKind in ReviewMediaKind.allCases {
            let options = PhotoLibraryService.makeFetchOptions(dateInterval: nil, mediaKind: mediaKind)
            let predicate = try XCTUnwrap(options.predicate)
            let mediaType = mediaKind == .videos ? PHAssetMediaType.video : .image

            XCTAssertFalse(predicate.evaluate(with: ["mediaType": mediaType.rawValue, "favorite": true]))
            XCTAssertTrue(predicate.evaluate(with: ["mediaType": mediaType.rawValue, "favorite": false]))
        }
    }

    func testIncludingFavoritesStillRespectsMediaTypeAndDateRange() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let options = PhotoLibraryService.makeFetchOptions(
            dateInterval: DateInterval(start: start, end: end),
            mediaKind: .videos,
            hidesFavorites: false
        )
        let predicate = try XCTUnwrap(options.predicate)
        let video: [String: Any] = ["mediaType": PHAssetMediaType.video.rawValue, "favorite": true, "creationDate": start]

        XCTAssertTrue(predicate.evaluate(with: video))
        XCTAssertFalse(predicate.evaluate(with: video.merging(["creationDate": end]) { _, new in new }))
        XCTAssertFalse(predicate.evaluate(with: video.merging(["mediaType": PHAssetMediaType.image.rawValue]) { _, new in new }))
    }
}
