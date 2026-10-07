import XCTest
@testable import PhotoSoap

final class AssetSizeStoreTests: XCTestCase {
    func testPersistsKnownSizesAndRejectsChangedAssets() throws {
        let suite = "AssetSizeStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSince1970: 100)
        let store = AssetSizeStore(defaults: defaults)
        XCTAssertNil(store.size(for: "video", modificationDate: date))
        store.set(4096, for: "video", modificationDate: date)
        store.persist()
        let restored = AssetSizeStore(defaults: defaults)
        XCTAssertEqual(restored.size(for: "video", modificationDate: date), 4096)
        XCTAssertNil(restored.size(for: "video", modificationDate: date.addingTimeInterval(1)))
        restored.invalidate(["video"])
        XCTAssertNil(AssetSizeStore(defaults: defaults).size(for: "video", modificationDate: date))
    }

    func testLegacyZeroQueueSizeBecomesUnknown() throws {
        let data = Data(#"{"id":"video","queuedAt":0,"fileSize":0}"#.utf8)
        let item = try JSONDecoder().decode(PersistedPendingDeletionItem.self, from: data)
        XCTAssertNil(item.fileSize)
        XCTAssertNil(try JSONDecoder().decode(PersistedPendingDeletionItem.self, from: JSONEncoder().encode(item)).fileSize)
    }
}
