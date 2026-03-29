import Foundation
import SwiftUI
import SwiftData
import Combine
import Photos

struct PendingDeletionItem: Identifiable, Equatable {
    let id: String
    let photo: Photo
    let queuedAt: Date
    var fileSize: Int64

    static func == (lhs: PendingDeletionItem, rhs: PendingDeletionItem) -> Bool {
        lhs.id == rhs.id
    }
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
    @Published var showFilterSheet = false
    @Published var showGoalSheet = false
    @Published var persistedReviewedIDs: Set<String> = []
    @Published var knownUnreviewedIDs: Set<String> = []
    @Published var hasTrackedReviewStart = false
    @Published var cycleKeptCount = 0
    @Published var cycleDeletedCount = 0
    @Published var showStartOverConfirmation = false
    @Published var showDailyGoalToast = false
    @Published var hasTriggeredSwipeThresholdFeedback = false
    @Published var lastCelebrationFeedbackDate = Date.distantPast

    @Published var pendingDeletionItems: [PendingDeletionItem] = []
    @Published var isShowingDeleteQueueSheet = false
    @Published var isShowingDeleteBatchExplainer = false
    @Published var isShowingRemoveFromQueueConfirmation = false
    @Published var isShowingClearQueueConfirmation = false
    @Published var photoPendingQueueRemoval: PendingDeletionItem? = nil
    @Published var isCommittingDeletionBatch = false
    @Published var showDeletionSuccessToast = false
    @Published var showDeletionCancelledToast = false

    var pendingDeletionCount: Int {
        pendingDeletionItems.count
    }

    var pendingDeletionIDs: Set<String> {
        Set(pendingDeletionItems.map { $0.id })
    }

    private var deletionStack: [PendingDeletionItem] = []

    let swipeActionThreshold: CGFloat = 100
    let swipeFeedbackDistance: CGFloat = 140
    let swipeOverlayThreshold: CGFloat = 12
    let cardCornerRadius: CGFloat = 16
    let celebrationFeedbackCooldown: TimeInterval = 0.75

    private let photoLibraryService: PhotoLibraryService
    private let gameificationService: GameificationService
    private let analyticsService: AnalyticsService
    private let aggregateMetricsService: AggregateMetricsService
    private let adCoordinator: AdCoordinator
    private let hapticsService: HapticsService
    private let defaults: UserDefaults
    private weak var modelContext: ModelContext?
    private var stats: UserStats?

    init(
        photoLibraryService: PhotoLibraryService,
        gameificationService: GameificationService,
        analyticsService: AnalyticsService,
        aggregateMetricsService: AggregateMetricsService,
        adCoordinator: AdCoordinator,
        hapticsService: HapticsService,
        defaults: UserDefaults = .standard
    ) {
        self.photoLibraryService = photoLibraryService
        self.gameificationService = gameificationService
        self.analyticsService = analyticsService
        self.aggregateMetricsService = aggregateMetricsService
        self.adCoordinator = adCoordinator
        self.hapticsService = hapticsService
        self.defaults = defaults
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
        analyticsService.track(.reviewStarted(filter: currentFilter))
        hasTrackedReviewStart = true
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

    func startOver() {
        guard let modelContext else { return }

        isLoading = true
        currentPhoto = nil
        nextPhoto = nil
        cycleKeptCount = 0
        cycleDeletedCount = 0

        do {
            try gameificationService.deleteAllReviewedPhotos(context: modelContext)
            try modelContext.save()
        } catch {
            presentError("Failed to clear review history: \(error.localizedDescription)")
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
        photoLibraryService.setFilter(filter)
        currentPhoto = nil
        nextPhoto = nil
        noMorePhotos = false
        analyticsService.track(.filterApplied(filter))

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
        cardRotation = 0

        let translation = value.translation.width
        let distance = abs(translation)
        let progress = min(distance / swipeFeedbackDistance, 1)

        if distance < swipeOverlayThreshold {
            swipeProgress = 0
            swipeDirection = nil
            hasTriggeredSwipeThresholdFeedback = false
        } else {
            swipeProgress = progress
            swipeDirection = translation > 0 ? .keep : .delete

            if distance >= swipeActionThreshold {
                if !hasTriggeredSwipeThresholdFeedback {
                    hapticsService.selection()
                    hasTriggeredSwipeThresholdFeedback = true
                }
            } else {
                hasTriggeredSwipeThresholdFeedback = false
            }
        }
    }

    func handleDragEnd(_ value: DragGesture.Value) async {
        guard !isProcessingAction else { return }

        if value.translation.width > swipeActionThreshold {
            withAnimation(.easeOut(duration: 0.3)) {
                cardOffset = CGSize(width: 500, height: 0)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            await keepPhoto()
        } else if value.translation.width < -swipeActionThreshold {
            withAnimation(.easeOut(duration: 0.3)) {
                cardOffset = CGSize(width: -500, height: 0)
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

    func refreshLibrary() {
        photoLibraryService.refreshLibrary()
        noMorePhotos = false

        Task {
            await loadInitialPhoto()
        }
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
        var attemptedIDs = excludedIDs
        let maxAttempts = 80

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

    private func keepPhoto() async {
        guard !isProcessingAction else { return }
        guard let photo = currentPhoto, let stats, let modelContext else { return }

        isProcessingAction = true
        defer { isProcessingAction = false }

        let challengeType = DailyChallengeType(rawValue: stats.dailyChallengeType) ?? .review

        do {
            try gameificationService.markPhotoReviewed(id: photo.id, context: modelContext)
            gameificationService.processPhotoReview(
                action: .keep,
                fileSize: 0,
                stats: stats,
                challengeType: challengeType,
                context: modelContext
            )
        } catch {
            presentError("Failed to update review history: \(error.localizedDescription)")
            return
        }

        guard persistReviewProgress(for: photo.id, cacheInSession: true) else {
            return
        }

        cycleKeptCount += 1
        analyticsService.track(.photoKept(filter: currentFilter))
        aggregateMetricsService.recordReview()
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
                resolvedFileSize = await photoLibraryService.fetchFileSize(for: photo.asset)
            }

            try await photoLibraryService.deletePhoto(photo)

            let challengeType = DailyChallengeType(rawValue: stats.dailyChallengeType) ?? .review

            do {
                try gameificationService.markPhotoReviewed(id: photo.id, context: modelContext)
                gameificationService.processPhotoReview(
                    action: .delete,
                    fileSize: resolvedFileSize,
                    stats: stats,
                    challengeType: challengeType,
                    context: modelContext
                )
            } catch {
                presentError("Failed to update review history: \(error.localizedDescription)")
                return
            }

            guard persistReviewProgress(for: photo.id, cacheInSession: false) else {
                return
            }

            cycleDeletedCount += 1
            analyticsService.track(.photoDeleted(filter: currentFilter))
            aggregateMetricsService.recordDeletion(bytesFreed: resolvedFileSize)
            hapticsService.impact(.rigid)

            await advanceToNextPhoto()
        } catch let error as NSError {
            if error.code == 3072 {
                aggregateMetricsService.recordReview()
                await advanceToNextPhoto()
            } else {
                presentError("Failed to delete photo: \(error.localizedDescription)")
            }
        }
    }

    func queueCurrentPhotoForDeletion() async {
        guard let photo = currentPhoto else { return }

        var resolvedFileSize: Int64 = photo.fileSize
        if resolvedFileSize == 0 {
            resolvedFileSize = await photoLibraryService.fetchFileSize(for: photo.asset)
        }

        let item = PendingDeletionItem(
            id: photo.id,
            photo: photo,
            queuedAt: Date(),
            fileSize: resolvedFileSize
        )
        pendingDeletionItems.append(item)
        deletionStack.append(item)

        hapticsService.impact(.rigid)
        await advanceToNextPhoto()
    }

    func undoLastQueuedDeletion() {
        guard !deletionStack.isEmpty else { return }

        let lastItem = deletionStack.removeLast()
        pendingDeletionItems.removeAll { $0.id == lastItem.id }
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

        pendingDeletionItems.removeAll { $0.id == item.id }
        deletionStack.removeAll { $0.id == item.id }

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
        pendingDeletionItems.removeAll()
        deletionStack.removeAll()

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
        isShowingDeleteBatchExplainer = true
    }

    func commitPendingDeletionBatch() async {
        guard !isCommittingDeletionBatch else { return }
        guard !pendingDeletionItems.isEmpty else { return }
        guard let stats, let modelContext else { return }

        isCommittingDeletionBatch = true
        defer {
            isCommittingDeletionBatch = false
            isShowingDeleteBatchExplainer = false
        }

        let photosToDelete = pendingDeletionItems.map { $0.photo }
        let totalBytes = pendingDeletionItems.reduce(0) { $0 + $1.fileSize }

        do {
            try await photoLibraryService.deletePhotos(photosToDelete)

            let challengeType = DailyChallengeType(rawValue: stats.dailyChallengeType) ?? .review

            for item in pendingDeletionItems {
                do {
                    try gameificationService.markPhotoReviewed(id: item.id, context: modelContext)
                    gameificationService.processPhotoReview(
                        action: .delete,
                        fileSize: item.fileSize,
                        stats: stats,
                        challengeType: challengeType,
                        context: modelContext
                    )
                } catch {
                    continue
                }

                _ = persistReviewProgress(for: item.id, cacheInSession: false)
            }

            try modelContext.save()

            let deletedCount = pendingDeletionItems.count
            cycleDeletedCount += deletedCount
            analyticsService.track(.photoDeleted(filter: currentFilter))
            aggregateMetricsService.recordDeletion(bytesFreed: totalBytes)

            pendingDeletionItems.removeAll()
            deletionStack.removeAll()

            showDeletionSuccessToast = true
            hapticsService.success()

            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    self.showDeletionSuccessToast = false
                }
            }
        } catch let error as NSError {
            if error.code == 3072 {
                showDeletionCancelledToast = true
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        self.showDeletionCancelledToast = false
                    }
                }
            } else {
                presentError("Failed to delete photos: \(error.localizedDescription)")
            }
        }
    }

    func dismissDeletionSuccessToast() {
        showDeletionSuccessToast = false
    }

    func dismissDeletionCancelledToast() {
        showDeletionCancelledToast = false
    }

    private func persistReviewProgress(for photoID: String, cacheInSession: Bool) -> Bool {
        guard let modelContext else { return false }

        do {
            try modelContext.save()
            persistedReviewedIDs.insert(photoID)
            knownUnreviewedIDs.remove(photoID)

            if cacheInSession {
                photoLibraryService.markReviewed(photoID)
            }

            return true
        } catch {
            modelContext.rollback()
            presentError("Failed to save your progress: \(error.localizedDescription)")
            return false
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

        let isReviewed = gameificationService.isPhotoReviewed(id: photoID, context: modelContext)
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
            analyticsService.track(.reviewBatchCompleted(filter: currentFilter))
        }
    }

    private func resetSwipeState() {
        cardOffset = .zero
        cardRotation = 0
        swipeProgress = 0
        swipeDirection = nil
        hasTriggeredSwipeThresholdFeedback = false
    }

    private func reloadPhotoAfterQueueChange() async {
        noMorePhotos = false
        if let photo = try? await nextAvailablePhoto(excluding: pendingDeletionIDs) {
            currentPhoto = photo
            await preloadNextPhoto()
        } else {
            noMorePhotos = true
        }
    }

    private func triggerCelebrationFeedbackIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastCelebrationFeedbackDate) > celebrationFeedbackCooldown else { return }

        lastCelebrationFeedbackDate = now
        hapticsService.success()
    }

    private func presentError(_ message: String) {
        error = message
        isShowingError = true
        hapticsService.error()
    }
}
