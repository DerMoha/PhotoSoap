import Foundation

/// Counts streamed bytes with a deadline, without retaining the resource contents.
nonisolated final class ResourceSizeRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Int64 = 0
    private var isFinished = false
    private var requestID: Int32?
    private var didCancel = false
    private let completion: @Sendable (Int64?) -> Void
    private let cancelRequest: @Sendable (Int32) -> Void

    init(completion: @escaping @Sendable (Int64?) -> Void, cancelRequest: @escaping @Sendable (Int32) -> Void) {
        self.completion = completion
        self.cancelRequest = cancelRequest
    }

    func setRequestID(_ id: Int32) {
        lock.lock()
        requestID = id
        let shouldCancel = didCancel
        lock.unlock()
        if shouldCancel { cancelRequest(id) }
    }

    func receive(_ data: Data) {
        lock.lock()
        if !isFinished { bytes += Int64(data.count) }
        lock.unlock()
    }

    func finish(succeeded: Bool) {
        resolve(succeeded: succeeded, cancelled: false)
    }

    func cancel() {
        resolve(succeeded: false, cancelled: true)
    }

    private func resolve(succeeded: Bool, cancelled: Bool) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        didCancel = cancelled
        let id = requestID
        let result = succeeded && bytes > 0 ? bytes : nil
        lock.unlock()
        if cancelled, let id { cancelRequest(id) }
        completion(result)
    }
}

nonisolated final class ResourceSizeRequestHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var request: ResourceSizeRequest?
    private var isCancelled = false

    func install(_ request: ResourceSizeRequest) {
        lock.lock()
        self.request = request
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel { request.cancel() }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let request = request
        lock.unlock()
        request?.cancel()
    }
}
