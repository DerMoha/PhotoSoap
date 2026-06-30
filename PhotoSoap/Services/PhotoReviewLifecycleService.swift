import Foundation

struct PendingDeletionItem: Identifiable, Equatable {
    let id: String
    let photo: Photo
    let queuedAt: Date
    var fileSize: Int64
    let createdReviewOnQueue: Bool

    static func == (lhs: PendingDeletionItem, rhs: PendingDeletionItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct PersistedPendingDeletionItem: Codable, Equatable {
    let id: String
    let queuedAt: Date
    let fileSize: Int64
    let createdReviewOnQueue: Bool

    init(id: String, queuedAt: Date, fileSize: Int64, createdReviewOnQueue: Bool) {
        self.id = id
        self.queuedAt = queuedAt
        self.fileSize = fileSize
        self.createdReviewOnQueue = createdReviewOnQueue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.queuedAt = try container.decode(Date.self, forKey: .queuedAt)
        self.fileSize = try container.decode(Int64.self, forKey: .fileSize)
        self.createdReviewOnQueue = try container.decodeIfPresent(Bool.self, forKey: .createdReviewOnQueue) ?? false
    }
}

final class DeleteQueueStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = UserDefaultsKeys.pendingDeletionQueue) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> [PersistedPendingDeletionItem] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        guard let items = try? JSONDecoder().decode([PersistedPendingDeletionItem].self, from: data) else {
            clear()
            return []
        }

        return items
    }

    func save(_ items: [PendingDeletionItem]) {
        guard !items.isEmpty else {
            clear()
            return
        }

        let persistedItems = items.map {
            PersistedPendingDeletionItem(
                id: $0.id,
                queuedAt: $0.queuedAt,
                fileSize: $0.fileSize,
                createdReviewOnQueue: $0.createdReviewOnQueue
            )
        }

        guard let encoded = try? JSONEncoder().encode(persistedItems) else { return }
        defaults.set(encoded, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

@MainActor
final class PhotoReviewLifecycleService {
    private let store: DeleteQueueStore
    private(set) var pendingDeletionItems: [PendingDeletionItem] = []
    private var deletionStack: [PendingDeletionItem] = []

    init(store: DeleteQueueStore) {
        self.store = store
    }

    var pendingDeletionCount: Int {
        pendingDeletionItems.count
    }

    var pendingDeletionIDs: Set<String> {
        Set(pendingDeletionItems.map(\.id))
    }

    func loadPersistedItems() -> [PersistedPendingDeletionItem] {
        store.load()
    }

    func restore(_ items: [PendingDeletionItem]) {
        pendingDeletionItems = items
        deletionStack = items
    }

    func enqueue(_ item: PendingDeletionItem) {
        pendingDeletionItems.append(item)
        deletionStack.append(item)
        persist()
    }

    func lastQueuedItem() -> PendingDeletionItem? {
        deletionStack.last
    }

    func removeLastQueuedItem() {
        guard let item = deletionStack.popLast() else { return }
        pendingDeletionItems.removeAll { $0.id == item.id }
        persist()
    }

    func remove(_ item: PendingDeletionItem) {
        pendingDeletionItems.removeAll { $0.id == item.id }
        deletionStack.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        pendingDeletionItems.removeAll()
        deletionStack.removeAll()
        store.clear()
    }

    func missingItems(availableIDs: Set<String>) -> [PendingDeletionItem] {
        pendingDeletionItems.filter { !availableIDs.contains($0.id) }
    }

    func pruneUnavailableItems(availableIDs: Set<String>) {
        pendingDeletionItems.removeAll { !availableIDs.contains($0.id) }
        deletionStack.removeAll { !availableIDs.contains($0.id) }
        persist()
    }

    func persist() {
        store.save(pendingDeletionItems)
    }
}
