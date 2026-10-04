import Foundation
import SwiftUI
import SwiftData
import Combine

private enum PendingDeleteBatchAction {
    case showExplainer
    case commit
}

@MainActor
final class PhotoReviewViewModel: ObservableObject {
    @Published var currentPhoto: Photo?
    @Published var nextPhoto: Photo?
    @Published var isLoading = false
    @Published var error: String?
    @Published var isShowingError = false
    @Published var noMorePhotos = false
    @Published var cardOffset: CGSize = .zero
    @Published var cardRotation: Double = 0
    @Published var swipeProgress: CGFloat = 0
    @Published var swipeDirection: SwipeDirection?

    @Published var isProcessingAction = false
    @Published var currentFilter: PhotoFilter = .all
    @Published var currentMediaKind: ReviewMediaKind = .photos
    @Published var showFilterSheet = false
    @Published var persistedReviewedIDs: Set<String> = []
    @Published var knownUnreviewedIDs: Set<String> = []
    @Published var hasTrackedReviewStart = false
    @Published var cycleKeptCount = 0
    @Published var cycleDeletedCount = 0
    @Published var showStartOverConfirmation = false
    @Published var showQueuedStartOverConfirmation = false
    @Published var showDailyGoalToast = false
    @Published var pendingDeletionItems: [PendingDeletionItem] = []
    @Published var isShowingDeleteQueueSheet = false
    @Published var isShowingDeleteBatchExplainer = false
    @Published var isShowingRemoveFromQueueConfirmation = false
    @Published var isShowingClearQueueConfirmation = false
    @Published var photoPendingQueueRemoval: PendingDeletionItem? = nil
    @Published var isCommittingDeletionBatch = false
    @Published var showDeletionSuccessToast = false
    @Published var showDeletionCancelledToast = false
    @Published var showDeleteListIntroToast = false
    @Published var showQueuePrunedToast = false

    var pendingDeletionCount: Int {
        pendingDeletionItems.count
    }

    var pendingDeletionIDs: Set<String> {
        Set(pendingDeletionItems.map { $0.id })
    }

    let swipeActionThreshold: CGFloat = 100
    let swipeFeedbackDistance: CGFloat = 140
    let swipeOverlayThreshold: CGFloat = 12
    let cardCornerRadius: CGFloat = 16

    private let photoLibraryService: PhotoLibraryService
    private let reviewAccountingService: ReviewAccountingService
    private let privacyCollectionService: PrivacyCollectionService
    private let hapticsService: HapticsService
    private let deleteQueueLifecycle: PhotoReviewLifecycleService
    private let feedbackController: ReviewFeedbackController
    private let defaults: UserDefaults
    private weak var modelContext: ModelContext?
    private var stats: UserStats?
    private var hasRestoredPendingDeletionQueue = false
    private var pendingDeleteBatchAction: PendingDeleteBatchAction?

    init(
        photoLibraryService: PhotoLibraryService,
        reviewAccountingService: ReviewAccountingService,
        privacyCollectionService: PrivacyCollectionService,
        hapticsService: HapticsService,
        defaults: UserDefaults = .standard
    ) {
        self.photoLibraryService = photoLibraryService
        self.reviewAccountingService = reviewAccountingService
        self.privacyCollectionService = privacyCollectionService
        self.hapticsService = hapticsService
        self.deleteQueueLifecycle = PhotoReviewLifecycleService(store: DeleteQueueStore(defaults: defaults))
        self.feedbackController = ReviewFeedbackController(hapticsService: hapticsService)
        self.defaults = defaults

        self.currentMediaKind = Self.storedMediaKind(in: defaults)
        self.photoLibraryService.setMediaKind(currentMediaKind)
        self.photoLibraryService.setHidesFavorites(defaults.object(forKey: UserDefaultsKeys.filterHideFavorites) as? Bool ?? true)
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func setStats(_ stats: UserStats) {
        self.stats = stats
    }

    func setCurrentFilter(_ filter: PhotoFilter) {
        self.currentFilter = filter
    }

    func onViewAppear() {
        guard !hasTrackedReviewStart else { return }
        privacyCollectionService.track(.reviewStarted(filter: currentFilter, mediaKind: currentMediaKind))
        hasTrackedReviewStart = true
    }

    func restorePendingDeletionQueueIfNeeded() {
        guard !hasRestoredPendingDeletionQueue else { return }
        hasRestoredPendingDeletionQueue = true

        let persistedItems = deleteQueueLifecycle.loadPersistedItems()
        guard !persistedItems.isEmpty else { return }

        let fileSizesByIdentifier = Dictionary(uniqueKeysWithValues: persistedItems.map { ($0.id, $0.fileSize) })
        let photosByIdentifier = photoLibraryService.photos(
            withLocalIdentifiers: persistedItems.map(\.id),
            fileSizesByIdentifier: fileSizesByIdentifier
        )
        let restoredItems: [PendingDeletionItem] = persistedItems.compactMap { item in
            guard let photo = photosByIdentifier[item.id] else { return nil }

            return PendingDeletionItem(
                id: item.id,
                photo: photo,
                queuedAt: item.queuedAt,
                fileSize: item.fileSize,
                createdReviewOnQueue: item.createdReviewOnQueue
            )
        }

        deleteQueueLifecycle.restore(restoredItems)
        syncPendingDeletionItems()

        if restoredItems.count != persistedItems.count {
            let restoredIDs = Set(restoredItems.map(\.id))
            let missingItems = persistedItems.filter { !restoredIDs.contains($0.id) }
            guard rollbackQueuedDeletionReviews(for: missingItems.filter(\.createdReviewOnQueue).map(\.id)) else { return }

            deleteQueueLifecycle.persist()
            showQueuePrunedFeedback()
        }
    }

    func onAchievementBannerChanged(_ isShowing: Bool) {
        guard isShowing else { return }
        triggerCelebrationFeedbackIfNeeded()
    }

    func onStreakCelebrationChanged(_ isShowing: Bool) {
        guard isShowing else { return }
        triggerCelebrationFeedbackIfNeeded()
    }

    func onDailyGoalToastChanged(_ isShowing: Bool) {
        guard isShowing else { return }
        triggerCelebrationFeedbackIfNeeded()
    }

    func dismissDailyGoalToast() {
        showDailyGoalToast = false
    }

    func requestStartOver() {
        if pendingDeletionCount > 0 {
            showQueuedStartOverConfirmation = true
        } else {
            showStartOverConfirmation = true
        }
    }

    func reviewPendingDeletionQueue() {
        showQueuedStartOverConfirmation = false
        isShowingDeleteQueueSheet = true
    }

    func startOver() {
        guard let modelContext else { return }

        showStartOverConfirmation = false
        showQueuedStartOverConfirmation = false

        isLoading = true
        currentPhoto = nil
        nextPhoto = nil
        cycleKeptCount = 0
        cycleDeletedCount = 0

        do {
            try reviewAccountingService.deleteAllReviewedPhotos(context: modelContext)
            try modelContext.save()
        } catch {
            presentError("Failed to clear review history: \(error.localizedDescription)")
            isLoading = false
            return
        }

        photoLibraryService.refreshLibrary()
        noMorePhotos = false
        persistedReviewedIDs.removeAll()
        knownUnreviewedIDs.removeAll()
        photoLibraryService.setSessionReviewedIDs(Set<String>())

        Task {
            await loadInitialPhoto()
        }
    }

    func loadInitialPhoto() async {
        isLoading = true
        error = nil
        noMorePhotos = false
        currentPhoto = nil
        nextPhoto = nil
        cycleKeptCount = 0
        cycleDeletedCount = 0
        persistedReviewedIDs.removeAll()
        knownUnreviewedIDs.removeAll()

        do {
            photoLibraryService.setSessionReviewedIDs(Set<String>())

            if let photo = try await nextAvailablePhoto(excluding: pendingDeletionIDs) {
                currentPhoto = photo
                await preloadNextPhoto()
            } else {
                noMorePhotos = true
            }
        } catch {
            presentError(error.localizedDescription)
        }

        isLoading = false
    }

    func applyFilter(_ filter: PhotoFilter) {
        currentFilter = filter
        syncSortOrderPreference()
        photoLibraryService.setFilter(filter)
        currentPhoto = nil
        nextPhoto = nil
        noMorePhotos = false
        privacyCollectionService.track(.filterApplied(filter, mediaKind: currentMediaKind))

        Task {
            await loadInitialPhoto()
        }
    }

    func applyMediaKind(_ mediaKind: ReviewMediaKind) {
        guard mediaKind != currentMediaKind else { return }

        currentMediaKind = mediaKind
        defaults.set(mediaKind.rawValue, forKey: UserDefaultsKeys.reviewMediaKind)
        syncSortOrderPreference()
        photoLibraryService.setMediaKind(mediaKind)
        currentPhoto = nil
        nextPhoto = nil
        noMorePhotos = false
        privacyCollectionService.track(.filterApplied(currentFilter, mediaKind: mediaKind))

        Task {
            await loadInitialPhoto()
        }
    }

    func applyFavoriteVisibility(hidesFavorites: Bool) {
        defaults.set(hidesFavorites, forKey: UserDefaultsKeys.filterHideFavorites)
        photoLibraryService.setHidesFavorites(hidesFavorites)
        currentPhoto = nil
        nextPhoto = nil
        noMorePhotos = false

        Task {
            await loadInitialPhoto()
        }
    }

    func applySortOrder(_ order: ReviewSortOrder) {
        defaults.set(order.rawValue, forKey: UserDefaultsKeys.reviewSortOrder)
        photoLibraryService.setSortOrder(order)
        currentPhoto = nil
        nextPhoto = nil
        noMorePhotos = false

        Task {
            await loadInitialPhoto()
        }
    }

    func handleDragGesture(_ value: DragGesture.Value) {
        guard !isProcessingAction else { return }

        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) {
            cardOffset = CGSize(width: value.translation.width, height: 0)
        }
        cardRotation = Double(max(-12.0, min(12.0, value.translation.width / 40)))

        let translation = value.translation.width
        let distance = abs(translation)
        let progress = min(distance / swipeFeedbackDistance, 1)

        if distance < swipeOverlayThreshold {
            swipeProgress = 0
            swipeDirection = nil
            feedbackController.resetSwipeFeedback()
        } else {
            swipeProgress = progress
            swipeDirection = translation > 0 ? .keep : .delete
            feedbackController.updateSwipeFeedback(
                distance: distance,
                overlayThreshold: swipeOverlayThreshold,
                actionThreshold: swipeActionThreshold
            )
        }
    }

    func handleDragEnd(_ value: DragGesture.Value) async {
        guard !isProcessingAction else { return }

        if value.translation.width > swipeActionThreshold {
            withAnimation(.easeOut(duration: 0.3)) {
                cardOffset = CGSize(width: 500, height: 0)
                cardRotation = 12
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            await keepPhoto()
        } else if value.translation.width < -swipeActionThreshold {
            withAnimation(.easeOut(duration: 0.3)) {
                cardOffset = CGSize(width: -500, height: 0)
                cardRotation = -12
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            if defaults.object(forKey: UserDefaultsKeys.deleteQueueEnabled) as? Bool ?? true {
                await queueCurrentPhotoForDeletion()
            } else {
                await deletePhoto()
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                resetSwipeState()
            }
        }
    }

    func performKeepAction() async {
        await keepPhoto()
    }

    func performDeleteAction() async {
        guard !isProcessingAction else { return }

        if defaults.object(forKey: UserDefaultsKeys.deleteQueueEnabled) as? Bool ?? true {
            await queueCurrentPhotoForDeletion()
        } else {
            await deletePhoto()
        }
    }

    func refreshLibrary() {
        photoLibraryService.refreshLibrary()
        noMorePhotos = false

        Task {
            await loadInitialPhoto()
        }
    }

    func handleLibraryRevisionChange() {
        guard !isLoading, !isProcessingAction else { return }
        guard noMorePhotos || currentPhoto == nil else { return }

        refreshLibrary()
    }

    var normalizedSwipeProgress: CGFloat {
        min(max(swipeProgress, 0), 1)
    }

    var decisionIconOpacity: Double {
        0.78 + (Double(normalizedSwipeProgress) * 0.22)
    }

    var decisionIconScale: CGFloat {
        0.82 + (normalizedSwipeProgress * 0.18)
    }

    func color(for direction: SwipeDirection?) -> Color {
        switch direction {
        case .keep:
            return .green
        case .delete:
            return .red
        case .none:
            return .clear
        }
    }

    func symbolName(for direction: SwipeDirection) -> String {
        switch direction {
        case .keep:
            return "checkmark"
        case .delete:
            return "trash"
        }
    }

    private func preloadNextPhoto() async {
        var excluded = currentPhoto.map { Set<String>([$0.id]) } ?? Set<String>()
        excluded.formUnion(pendingDeletionIDs)
        if let photo = try? await nextAvailablePhoto(excluding: excluded) {
            nextPhoto = photo
        }
    }

    private func nextAvailablePhoto(excluding excludedIDs: Set<String> = []) async throws -> Photo? {
        syncSortOrderPreference()

        var attemptedIDs = excludedIDs
        let maxAttempts = max(80, photoLibraryService.getTotalPhotoCount())

        for _ in 0..<maxAttempts {
            guard let photo = try await photoLibraryService.getNextPhoto(excluding: attemptedIDs) else {
                return nil
            }

            if isKnownReviewed(photo.id) {
                photoLibraryService.markReviewed(photo.id)
                attemptedIDs.insert(photo.id)
                continue
            }

            return photo
        }

        return nil
    }

    private func syncSortOrderPreference() {
        photoLibraryService.setSortOrder(ReviewSortOrder.stored(in: defaults))
    }

    private static func storedMediaKind(in defaults: UserDefaults) -> ReviewMediaKind {
        guard let rawValue = defaults.string(forKey: UserDefaultsKeys.reviewMediaKind),
              let mediaKind = ReviewMediaKind(rawValue: rawValue) else {
            return .photos
        }

        return mediaKind
    }

    private func keepPhoto() async {
        guard !isProcessingAction else { return }
        guard let photo = currentPhoto, let stats, let modelContext else { return }

        isProcessingAction = true
        defer { isProcessingAction = false }

        do {
            try reviewAccountingService.recordKeep(
                photoID: photo.id,
                stats: stats,
                context: modelContext,
                mediaType: photo.reviewMediaType
            )
        } catch {
            presentError("Failed to update review history: \(error.localizedDescription)")
            return
        }

        guard persistReviewProgress(for: photo.id, cacheInSession: true) else {
            return
        }

        cycleKeptCount += 1
        privacyCollectionService.track(.photoKept(filter: currentFilter, mediaKind: currentMediaKind))
        privacyCollectionService.recordReview()
        hapticsService.impact(.medium)

        await advanceToNextPhoto()
    }

    private func deletePhoto() async {
        guard !isProcessingAction else { return }
        guard let photo = currentPhoto, let stats, let modelContext else { return }

        isProcessingAction = true
        defer { isProcessingAction = false }

        do {
            let resolvedFileSize: Int64
            if photo.fileSize > 0 {
                resolvedFileSize = photo.fileSize
            } else {
                resolvedFileSize = await photoLibraryService.fetchFileSize(for: photo)
            }

            let snapshot = try reviewAccountingService.prepareImmediateDeletion(
                photoID: photo.id,
                fileSize: resolvedFileSize,
                stats: stats,
                context: modelContext,
                mediaType: photo.reviewMediaType
            )

            guard persistReviewProgress(for: photo.id, cacheInSession: false) else {
                return
            }

            do {
                try await photoLibraryService.deletePhoto(photo)
            } catch {
                restoreReviewPersistence(
                    snapshot,
                    for: [photo.id],
                    stats: stats,
                    context: modelContext
                )

                if isPhotosDeletionCancellation(error) {
                    showDeletionCancelledFeedback()
                } else {
                    presentError("Failed to delete item: \(error.localizedDescription)")
                }
                return
            }

            photoLibraryService.markReviewed(photo.id)
            cycleDeletedCount += 1
            privacyCollectionService.track(.photoDeleted(filter: currentFilter, mediaKind: currentMediaKind))
            privacyCollectionService.recordDeletion(bytesFreed: resolvedFileSize)
            hapticsService.impact(.rigid)

            await advanceToNextPhoto()
        } catch {
            modelContext.rollback()
            presentError("Failed to update review history: \(error.localizedDescription)")
        }
    }

    func queueCurrentPhotoForDeletion() async {
        guard !isProcessingAction else { return }
        guard let photo = currentPhoto else { return }

        isProcessingAction = true
        defer { isProcessingAction = false }

        var resolvedFileSize: Int64 = photo.fileSize
        if resolvedFileSize == 0 {
            resolvedFileSize = await photoLibraryService.fetchFileSize(for: photo)
        }

        let item = PendingDeletionItem(
            id: photo.id,
            photo: photo,
            queuedAt: Date(),
            fileSize: resolvedFileSize,
            createdReviewOnQueue: !isKnownReviewed(photo.id)
        )

        if item.createdReviewOnQueue {
            guard markQueuedDeletionAsReviewed(photo: photo) else {
                return
            }
        }

        deleteQueueLifecycle.enqueue(item)
        syncPendingDeletionItems()

        if !defaults.bool(forKey: UserDefaultsKeys.hasSeenDeleteListIntro) {
            defaults.set(true, forKey: UserDefaultsKeys.hasSeenDeleteListIntro)
            showDeleteListIntroToast = true

            Task {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                await MainActor.run {
                    self.showDeleteListIntroToast = false
                }
            }
        }

        hapticsService.impact(.rigid)
        await advanceToNextPhoto()
    }

    func undoLastQueuedDeletion() {
        guard let lastItem = deleteQueueLifecycle.lastQueuedItem() else { return }
        guard rollbackQueuedDeletionReviewIfNeeded(for: [lastItem]) else { return }

        deleteQueueLifecycle.removeLastQueuedItem()
        syncPendingDeletionItems()
        hapticsService.impact(.light)

        if noMorePhotos || currentPhoto == nil {
            Task { await reloadPhotoAfterQueueChange() }
        }
    }

    func requestRemoveFromQueue(_ item: PendingDeletionItem) {
        photoPendingQueueRemoval = item
        isShowingRemoveFromQueueConfirmation = true
    }

    func confirmRemoveFromQueue() {
        guard let item = photoPendingQueueRemoval else { return }
        guard rollbackQueuedDeletionReviewIfNeeded(for: [item]) else { return }

        deleteQueueLifecycle.remove(item)
        syncPendingDeletionItems()

        isShowingRemoveFromQueueConfirmation = false
        photoPendingQueueRemoval = nil
        hapticsService.impact(.light)

        if noMorePhotos || currentPhoto == nil {
            Task { await reloadPhotoAfterQueueChange() }
        }
    }

    func dismissRemoveFromQueueConfirmation() {
        isShowingRemoveFromQueueConfirmation = false
        photoPendingQueueRemoval = nil
    }

    func requestClearQueue() {
        isShowingClearQueueConfirmation = true
    }

    func confirmClearQueue() {
        guard rollbackQueuedDeletionReviewIfNeeded(for: pendingDeletionItems) else { return }

        deleteQueueLifecycle.clear()
        syncPendingDeletionItems()

        isShowingClearQueueConfirmation = false
        hapticsService.impact(.medium)

        if noMorePhotos || currentPhoto == nil {
            Task { await reloadPhotoAfterQueueChange() }
        }
    }

    func dismissClearQueueConfirmation() {
        isShowingClearQueueConfirmation = false
    }

    func requestCommitPendingDeletionBatch() {
        guard !pendingDeletionItems.isEmpty else { return }

        let action: PendingDeleteBatchAction = defaults.bool(forKey: UserDefaultsKeys.hasSeenDeleteBatchExplainer)
            ? .commit
            : .showExplainer

        if isShowingDeleteQueueSheet {
            pendingDeleteBatchAction = action
            isShowingDeleteQueueSheet = false
        } else {
            performPendingDeleteBatchAction(action)
        }
    }

    func handleDeleteQueueSheetDismissed() {
        guard let action = pendingDeleteBatchAction else { return }

        pendingDeleteBatchAction = nil
        performPendingDeleteBatchAction(action)
    }

    func confirmDeleteBatchExplainer() {
        defaults.set(true, forKey: UserDefaultsKeys.hasSeenDeleteBatchExplainer)

        Task {
            await commitPendingDeletionBatch()
        }
    }

    func commitPendingDeletionBatch() async {
        guard !isCommittingDeletionBatch else { return }
        guard !pendingDeletionItems.isEmpty else { return }
        guard let stats, let modelContext else { return }
        guard photoLibraryService.authorizationStatus.hasPhotoAccess else {
            presentError(String(localized: "error.accessDenied", defaultValue: "Photo library access was denied. Please enable access in Settings.", table: "LocalizableShared"))
            return
        }

        pruneUnavailablePendingDeletionItems()
        guard !pendingDeletionItems.isEmpty else {
            isShowingDeleteBatchExplainer = false
            return
        }

        isCommittingDeletionBatch = true
        defer {
            isCommittingDeletionBatch = false
            isShowingDeleteBatchExplainer = false
        }

        let itemsToDelete = pendingDeletionItems
        let photosToDelete = itemsToDelete.map { $0.photo }
        let totalBytes = itemsToDelete.reduce(0) { $0 + $1.fileSize }
        let photoIDs = itemsToDelete.map(\.id)
        do {
            let snapshot = try reviewAccountingService.prepareDeletionBatch(
                items: itemsToDelete,
                stats: stats,
                context: modelContext
            )

            guard savePreparedReviewProgress(for: photoIDs, cacheInSession: false) else {
                return
            }

            do {
                try await photoLibraryService.deletePhotos(photosToDelete)
            } catch {
                restoreReviewPersistence(
                    snapshot,
                    for: photoIDs,
                    stats: stats,
                    context: modelContext
                )

                if isPhotosDeletionCancellation(error) {
                    showDeletionCancelledFeedback()
                } else {
                    presentError("Failed to delete items: \(error.localizedDescription)")
                }
                return
            }

            let deletedCount = itemsToDelete.count
            cycleDeletedCount += deletedCount
            privacyCollectionService.track(.photoDeleted(filter: currentFilter, mediaKind: currentMediaKind))
            privacyCollectionService.recordDeletion(bytesFreed: totalBytes, count: deletedCount)
            photoIDs.forEach { photoLibraryService.markReviewed($0) }

            deleteQueueLifecycle.clear()
            syncPendingDeletionItems()

            showDeletionSuccessToast = true
            hapticsService.success()

            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    self.showDeletionSuccessToast = false
                }
            }
        } catch {
            modelContext.rollback()
            presentError("Failed to update review history: \(error.localizedDescription)")
        }
    }

    func dismissDeletionSuccessToast() {
        showDeletionSuccessToast = false
    }

    func dismissDeletionCancelledToast() {
        showDeletionCancelledToast = false
    }

    func dismissDeleteListIntroToast() {
        showDeleteListIntroToast = false
    }

    func dismissQueuePrunedToast() {
        showQueuePrunedToast = false
    }

    private func markQueuedDeletionAsReviewed(photo: Photo) -> Bool {
        guard let stats, let modelContext else { return false }

        do {
            try reviewAccountingService.recordQueuedDeletionReview(
                photoID: photo.id,
                stats: stats,
                context: modelContext,
                mediaType: photo.reviewMediaType
            )

            return persistReviewProgress(for: photo.id, cacheInSession: true)
        } catch {
            presentError("Failed to update review history: \(error.localizedDescription)")
            return false
        }
    }

    private func rollbackQueuedDeletionReviewIfNeeded(for items: [PendingDeletionItem]) -> Bool {
        rollbackQueuedDeletionReviews(for: items.filter(\.createdReviewOnQueue).map(\.id))
    }

    @discardableResult
    private func rollbackQueuedDeletionReviews(for photoIDs: [String]) -> Bool {
        let photoIDs = Array(Set(photoIDs))
        guard !photoIDs.isEmpty else { return true }
        guard let stats, let modelContext else { return false }

        do {
            try reviewAccountingService.rollbackQueuedDeletionReviews(
                photoIDs: photoIDs,
                stats: stats,
                context: modelContext
            )

            for photoID in photoIDs {
                persistedReviewedIDs.remove(photoID)
                knownUnreviewedIDs.insert(photoID)
                photoLibraryService.unmarkReviewed(photoID)
            }

            return true
        } catch {
            modelContext.rollback()
            presentError("Failed to update review history: \(error.localizedDescription)")
            return false
        }
    }

    private func persistReviewProgress(for photoID: String, cacheInSession: Bool) -> Bool {
        savePreparedReviewProgress(for: [photoID], cacheInSession: cacheInSession)
    }

    private func savePreparedReviewProgress(for photoIDs: [String], cacheInSession: Bool) -> Bool {
        guard let modelContext else { return false }

        do {
            try reviewAccountingService.save(context: modelContext)
            for photoID in photoIDs {
                persistedReviewedIDs.insert(photoID)
                knownUnreviewedIDs.remove(photoID)

                if cacheInSession {
                    photoLibraryService.markReviewed(photoID)
                }
            }

            return true
        } catch {
            modelContext.rollback()
            presentError("Failed to save your progress: \(error.localizedDescription)")
            return false
        }
    }

    private func restoreReviewPersistence(
        _ snapshot: ReviewAccountingSnapshot,
        for photoIDs: [String],
        stats: UserStats,
        context: ModelContext
    ) {
        do {
            let result = try reviewAccountingService.restore(
                snapshot,
                affectedPhotoIDs: photoIDs,
                stats: stats,
                context: context
            )

            for photoID in result.reviewedPhotoIDs {
                persistedReviewedIDs.insert(photoID)
                knownUnreviewedIDs.remove(photoID)
            }

            for photoID in result.unreviewedPhotoIDs {
                persistedReviewedIDs.remove(photoID)
                knownUnreviewedIDs.insert(photoID)
            }
        } catch {
            context.rollback()
            presentError("Failed to restore review progress: \(error.localizedDescription)")
        }
    }

    private func isPhotosDeletionCancellation(_ error: Error) -> Bool {
        PhotoLibraryService.isDeletionCancellation(error)
    }

    private func showDeletionCancelledFeedback() {
        showDeletionCancelledToast = true
        hapticsService.warning()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            resetSwipeState()
        }

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                self.showDeletionCancelledToast = false
            }
        }
    }

    private func isKnownReviewed(_ photoID: String) -> Bool {
        guard let modelContext else { return false }

        if persistedReviewedIDs.contains(photoID) || photoLibraryService.isReviewed(photoID) {
            return true
        }

        if knownUnreviewedIDs.contains(photoID) {
            return false
        }

        let isReviewed = reviewAccountingService.isPhotoReviewed(id: photoID, context: modelContext)
        if isReviewed {
            persistedReviewedIDs.insert(photoID)
        } else {
            knownUnreviewedIDs.insert(photoID)
        }

        return isReviewed
    }

    private func advanceToNextPhoto() async {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            resetSwipeState()
        }

        if let next = nextPhoto {
            currentPhoto = next
            nextPhoto = nil
            await preloadNextPhoto()
        } else {
            await loadNextPhoto()
        }
    }

    private func loadNextPhoto() async {
        if let photo = try? await nextAvailablePhoto(excluding: pendingDeletionIDs) {
            currentPhoto = photo
            await preloadNextPhoto()
        } else {
            currentPhoto = nil
            noMorePhotos = true
            privacyCollectionService.track(.reviewBatchCompleted(filter: currentFilter, mediaKind: currentMediaKind))
        }
    }

    private func resetSwipeState() {
        cardOffset = .zero
        cardRotation = 0
        swipeProgress = 0
        swipeDirection = nil
        feedbackController.resetSwipeFeedback()
    }

    private func reloadPhotoAfterQueueChange() async {
        noMorePhotos = false
        photoLibraryService.resetAssetCursor()

        if let photo = try? await nextAvailablePhoto(excluding: pendingDeletionIDs) {
            currentPhoto = photo
            await preloadNextPhoto()
        } else {
            noMorePhotos = true
        }
    }

    private func performPendingDeleteBatchAction(_ action: PendingDeleteBatchAction) {
        switch action {
        case .showExplainer:
            isShowingDeleteBatchExplainer = true
        case .commit:
            Task {
                await commitPendingDeletionBatch()
            }
        }
    }

    private func pruneUnavailablePendingDeletionItems() {
        guard photoLibraryService.authorizationStatus.hasPhotoAccess else { return }
        guard !pendingDeletionItems.isEmpty else { return }

        let availableIDs = photoLibraryService.availablePhotoIDs(withLocalIdentifiers: pendingDeletionItems.map(\.id))
        let missingItems = deleteQueueLifecycle.missingItems(availableIDs: availableIDs)
        guard !missingItems.isEmpty else { return }

        guard rollbackQueuedDeletionReviewIfNeeded(for: missingItems) else { return }

        deleteQueueLifecycle.pruneUnavailableItems(availableIDs: availableIDs)
        syncPendingDeletionItems()
        showQueuePrunedFeedback()
    }

    private func showQueuePrunedFeedback() {
        showQueuePrunedToast = true
        hapticsService.warning()

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                self.showQueuePrunedToast = false
            }
        }
    }

    private func triggerCelebrationFeedbackIfNeeded() {
        feedbackController.triggerCelebrationIfNeeded()
    }

    private func syncPendingDeletionItems() {
        pendingDeletionItems = deleteQueueLifecycle.pendingDeletionItems
    }

    private func presentError(_ message: String) {
        error = message
        isShowingError = true
        hapticsService.error()
    }
}
