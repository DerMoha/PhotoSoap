import XCTest
@testable import PhotoSoap

final class ResourceSizeRequestTests: XCTestCase {
    func testSuccessfulReadCountsChunksAndCompletesOnlyOnce() {
        let completed = expectation(description: "size")
        completed.assertForOverFulfill = true
        let request = ResourceSizeRequest(completion: {
            XCTAssertEqual($0, 12)
            completed.fulfill()
        }, cancelRequest: { _ in XCTFail("Completed reads must not be cancelled") })
        request.setRequestID(42)
        request.receive(Data(count: 5))
        request.receive(Data(count: 7))
        request.finish(succeeded: true)
        request.cancel()
        request.finish(succeeded: true)
        wait(for: [completed], timeout: 1)
    }

    func testCancellationBeforeRequestIDArrivesCancelsUnderlyingRead() {
        let completed = expectation(description: "unknown")
        let cancelled = expectation(description: "cancelled")
        let request = ResourceSizeRequest(completion: {
            XCTAssertNil($0)
            completed.fulfill()
        }, cancelRequest: {
            XCTAssertEqual($0, 42)
            cancelled.fulfill()
        })
        request.receive(Data(count: 5))
        request.cancel()
        request.setRequestID(42)
        request.finish(succeeded: true)
        wait(for: [completed, cancelled], timeout: 1)
    }

    func testFailedReadDiscardsPartialBytes() {
        let completed = expectation(description: "unknown")
        let request = ResourceSizeRequest(completion: {
            XCTAssertNil($0)
            completed.fulfill()
        }, cancelRequest: { _ in })
        request.receive(Data(count: 5))
        request.finish(succeeded: false)
        wait(for: [completed], timeout: 1)
    }

    func testTaskCancellationBeforeInstallationIsPreserved() {
        let completed = expectation(description: "cancelled")
        let holder = ResourceSizeRequestHolder()
        holder.cancel()
        holder.install(ResourceSizeRequest(completion: {
            XCTAssertNil($0)
            completed.fulfill()
        }, cancelRequest: { _ in }))
        wait(for: [completed], timeout: 1)
    }
}
