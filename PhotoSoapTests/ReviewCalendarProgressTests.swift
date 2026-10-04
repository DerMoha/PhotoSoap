import XCTest
@testable import PhotoSoap

final class ReviewCalendarProgressTests: XCTestCase {
    func testProgressGroupsByCreationMonthAndWeightsYearByItemCount() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let january = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 1, day: 1)))
        let december = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 12, day: 31)))
        var progress = ReviewCalendarProgress()
        progress.record(creationDate: january, isReviewed: true, calendar: calendar)
        progress.record(creationDate: january, isReviewed: false, calendar: calendar)
        progress.record(creationDate: december, isReviewed: true, calendar: calendar)
        progress.record(creationDate: nil, isReviewed: true, calendar: calendar)

        XCTAssertEqual(progress.progress(for: 2025).fraction, 0.5)
        XCTAssertEqual(progress.monthsByYear[2025]?[1]?.totalCount, 2)
        XCTAssertTrue(progress.progress(for: 2024).isComplete)
        XCTAssertFalse(progress.progress(for: 2026).isComplete)
        XCTAssertEqual(progress.progress(for: 2026).fraction, 0)
    }
}
