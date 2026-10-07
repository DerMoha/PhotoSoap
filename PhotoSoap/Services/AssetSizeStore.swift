import Foundation

/// Stores original media resource sizes, never estimates of local disk space.
final class AssetSizeStore {
    private struct Entry: Codable {
        let modificationDate: Date?
        let bytes: Int64
    }

    private let defaults: UserDefaults
    private let key = "originalAssetSizes.v1"
    private var entries: [String: Entry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    func size(for id: String, modificationDate: Date?) -> Int64? {
        guard let entry = entries[id], entry.modificationDate == modificationDate else { return nil }
        return entry.bytes
    }

    func set(_ bytes: Int64, for id: String, modificationDate: Date?) {
        guard bytes > 0 else { return }
        entries[id] = Entry(modificationDate: modificationDate, bytes: bytes)
    }

    func invalidate(_ ids: [String]) {
        for id in ids { entries.removeValue(forKey: id) }
        persist()
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}
