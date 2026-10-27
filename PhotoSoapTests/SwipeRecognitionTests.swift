import XCTest
import SwiftUI
@testable import PhotoSoap

@MainActor
final class SwipeRecognitionTests: XCTestCase {
    func testLongDragsCommitInBothDirections() {
        XCTAssertEqual(decision(100, 0, 100), .keep)
        XCTAssertEqual(decision(-100, 0, -100), .delete)
    }

    func testShortFastFlicksCommitInBothDirections() {
        XCTAssertEqual(decision(35, 10, 160), .keep)
        XCTAssertEqual(decision(-35, -10, -160), .delete)
    }

    func testSlowShortDragsSnapBack() {
        XCTAssertNil(decision(60, 0, 80))
        XCTAssertNil(decision(-60, 0, -80))
    }

    func testTinyMovementsAndVerticalGesturesDoNotCommit() {
        XCTAssertNil(decision(10, 0, 200))
        XCTAssertNil(decision(40, 120, 200))
        XCTAssertNil(decision(-40, -120, -200))
    }

    func testReversedMomentumDoesNotCommitShortDrag() {
        XCTAssertNil(decision(40, 0, -160))
        XCTAssertNil(decision(-40, 0, 160))
    }

    private func decision(_ x: CGFloat, _ y: CGFloat, _ predictedX: CGFloat) -> SwipeDirection? {
        PhotoReviewViewModel.swipeDecision(
            translation: CGSize(width: x, height: y),
            predictedTranslation: CGSize(width: predictedX, height: y)
        )
    }
}
