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

private struct PersistedPendingDeletionItem: Codable {
    let id: String
    let queuedAt: Date
    let fileSize: Int64
}

private enum PendingDeleteBatchAction {
    case showExplainer
    case commit
}

private struct ReviewPersistenceSnapshot {
    let stats: UserStatsSnapshot
    let reviewedPhotoIDs: Set<String>
    let unlockedAchievementIDs: Set<String>
    let feedback: GameificationFeedbackSnapshot
}

private struct GameificationFeedbackSnapshot {
    let newlyUnlockedAchievement: Achievement?
    let showAchievementBanner: Bool
    let streakMilestoneReached: Int?
    let showStreakCelebration: Bool

    init(service: GameificationService) {
        self.newlyUnlockedAchievement = service.newlyUnlockedAchievement
        self.showAchievementBanner = service.showAchievementBanner
        self.streakMilestoneReached = service.streakMilestoneReached
        self.showStreakCelebration = service.showStreakCelebration
    }

    func restore(to service: GameificationService) {
        service.newlyUnlockedAchievement = newlyUnlockedAchievement
        service.showAchievementBanner = showAchievementBanner
        service.streakMilestoneReached = streakMilestoneReached
        service.showStreakCelebration = showStreakCelebration
    }
}

private struct UserStatsSnapshot {
    let totalReviewed: Int
    let totalDeleted: Int
    let totalKept: Int
    let storageFreed: Int64
    let sessionReviewCount: Int
    let currentStreak: Int
    let bestStreak: Int
    let dayStreak: Int
    let lastReviewDate: Date?
    let todayReviewCount: Int
    let todayDate: Date?
    let bestDayReviewCount: Int
    let dailyChallengeProgress: Int
    let dailyChallengeTarget: Int
    let dailyChallengeType: String
    let dailyChallengeDate: Date?

    init(stats: UserStats) {
        self.totalReviewed = stats.totalReviewed
        self.totalDeleted = stats.totalDeleted
        self.totalKept = stats.totalKept
        self.storageFreed = stats.storageFreed
        self.sessionReviewCount = stats.sessionReviewCount
        self.currentStreak = stats.currentStreak
        self.bestStreak = stats.bestStreak
        self.dayStreak = stats.dayStreak
        self.lastReviewDate = stats.lastReviewDate
        self.todayReviewCount = stats.todayReviewCount
        self.todayDate = stats.todayDate
        self.bestDayReviewCount = stats.bestDayReviewCount
        self.dailyChallengeProgress = stats.dailyChallengeProgress
        self.dailyChallengeTarget = stats.dailyChallengeTarget
        self.dailyChallengeType = stats.dailyChallengeType
        self.dailyChallengeDate = stats.dailyChallengeDate
    }

    func restore(to stats: UserStats) {
        stats.totalReviewed = totalReviewed
        stats.totalDeleted = totalDeleted
        stats.totalKept = totalKept
        stats.storageFreed = storageFreed
        stats.sessionReviewCount = sessionReviewCount
        stats.currentStreak = currentStreak
        stats.bestStreak = bestStreak
        stats.dayStreak = dayStreak
        stats.lastReviewDate = lastReviewDate
        stats.todayReviewCount = todayReviewCount
        stats.todayDate = todayDate
        stats.bestDayReviewCount = bestDayReviewCount
        stats.dailyChallengeProgress = dailyChallengeProgress
        stats.dailyChallengeTarget = dailyChallengeTarget
        stats.dailyChallengeType = dailyChallengeType
        stats.dailyChallengeDate = dailyChallengeDate
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
    @Published var persistedReviewedIDs: Set<String> = []
    @Published var knownUnreviewedIDs: Set<String> = []
    @Published var hasTrackedReviewStart = false
    @Published var cycleKeptCount = 0
    @Published var cycleDeletedCount = 0
    @Published var showStartOverConfirmation = false
    @Published var showQueuedStartOverConfirmation = false
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
    @Published var showDeleteListIntroToast = false

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
    private let hapticsService: HapticsService
    private let defaults: UserDefaults
    private weak var modelContext: ModelContext?
    private var stats: UserStats?
    private var hasRestoredPendingDeletionQueue = false
    private var pendingDeleteBatchAction: PendingDeleteBatchAction?

    init(
        photoLibraryService: PhotoLibraryService,
        gameificationService: GameificationService,
        analyticsService: AnalyticsService,
        aggregateMetricsService: AggregateMetricsService,
        hapticsService: HapticsService,
        defaults: UserDefaults = .standard
    ) {
        self.photoLibraryService = photoLibraryService
        self.gameificationService = gameificationService
        self.analyticsService = analyticsService
        self.aggregateMetricsService = aggregateMetricsService
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

    func restorePendingDeletionQueueIfNeeded() {
        guard !hasRestoredPendingDeletionQueue else { return }
        hasRestoredPendingDeletionQueue = true

        let persistedItems = loadPersistedPendingDeletionItems()
        guard !persistedItems.isEmpty else { return }

        let assetsByIdentifier = photoLibraryService.fetchAssets(withLocalIdentifiers: persistedItems.map(\.id))
        let restoredItems: [PendingDeletionItem] = persistedItems.compactMap { item in
            guard let asset = assetsByIdentifier[item.id] else { return nil }

            return PendingDeletionItem(
                id: item.id,
                photo: Photo(asset: asset, fileSize: item.fileSize),
                queuedAt: item.queuedAt,
                fileSize: item.fileSize
            )
        }

        pendingDeletionItems = restoredItems
        deletionStack = restoredItems

        if restoredItems.count != persistedItems.count {
            persistPendingDeletionQueue()
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
            try gameificationService.deleteAllReviewedPhotos(context: modelContext)
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
        analyticsService.track(.filterApplied(filter))

        Task {
            await loadInitialPhoto()
        }
    }

    func applySortOrder(oldestFirst: Bool) {
        defaults.set(oldestFirst, forKey: UserDefaultsKeys.filterOldestFirst)
        photoLibraryService.setSortOrder(oldestFirst: oldestFirst)
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
        photoLibraryService.setSortOrder(oldestFirst: defaults.bool(forKey: UserDefaultsKeys.filterOldestFirst))
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

            let snapshot = makeReviewPersistenceSnapshot(
                for: [photo.id],
                stats: stats,
                context: modelContext
            )
            let challengeType = DailyChallengeType(rawValue: stats.dailyChallengeType) ?? .review

            if !snapshot.reviewedPhotoIDs.contains(photo.id) {
                try gameificationService.markPhotoReviewed(id: photo.id, context: modelContext)
                gameificationService.processPhotoReview(
                    action: .delete,
                    fileSize: resolvedFileSize,
                    stats: stats,
                    challengeType: challengeType,
                    context: modelContext
                )
            }

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
                    presentError("Failed to delete photo: \(error.localizedDescription)")
                }
                return
            }

            photoLibraryService.markReviewed(photo.id)
            cycleDeletedCount += 1
            analyticsService.track(.photoDeleted(filter: currentFilter))
            aggregateMetricsService.recordDeletion(bytesFreed: resolvedFileSize)
            hapticsService.impact(.rigid)

            await advanceToNextPhoto()
        } catch {
            modelContext.rollback()
            presentError("Failed to update review history: \(error.localizedDescription)")
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
        persistPendingDeletionQueue()

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
        guard !deletionStack.isEmpty else { return }

        let lastItem = deletionStack.removeLast()
        pendingDeletionItems.removeAll { $0.id == lastItem.id }
        persistPendingDeletionQueue()
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
        persistPendingDeletionQueue()

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
        clearPersistedPendingDeletionQueue()

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

        isCommittingDeletionBatch = true
        defer {
            isCommittingDeletionBatch = false
            isShowingDeleteBatchExplainer = false
        }

        let itemsToDelete = pendingDeletionItems
        let photosToDelete = itemsToDelete.map { $0.photo }
        let totalBytes = itemsToDelete.reduce(0) { $0 + $1.fileSize }
        let photoIDs = itemsToDelete.map(\.id)
        let snapshot = makeReviewPersistenceSnapshot(
            for: photoIDs,
            stats: stats,
            context: modelContext
        )

        do {
            let challengeType = DailyChallengeType(rawValue: stats.dailyChallengeType) ?? .review

            for item in itemsToDelete where !snapshot.reviewedPhotoIDs.contains(item.id) {
                try gameificationService.markPhotoReviewed(id: item.id, context: modelContext)
                gameificationService.processPhotoReview(
                    action: .delete,
                    fileSize: item.fileSize,
                    stats: stats,
                    challengeType: challengeType,
                    context: modelContext
                )
            }

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
                    presentError("Failed to delete photos: \(error.localizedDescription)")
                }
                return
            }

            let deletedCount = itemsToDelete.count
            cycleDeletedCount += deletedCount
            analyticsService.track(.photoDeleted(filter: currentFilter))
            aggregateMetricsService.recordDeletion(bytesFreed: totalBytes, count: deletedCount)
            photoIDs.forEach { photoLibraryService.markReviewed($0) }

            pendingDeletionItems.removeAll()
            deletionStack.removeAll()
            clearPersistedPendingDeletionQueue()

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

    private func persistReviewProgress(for photoID: String, cacheInSession: Bool) -> Bool {
        savePreparedReviewProgress(for: [photoID], cacheInSession: cacheInSession)
    }

    private func savePreparedReviewProgress(for photoIDs: [String], cacheInSession: Bool) -> Bool {
        guard let modelContext else { return false }

        do {
            try modelContext.save()
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

    private func makeReviewPersistenceSnapshot(
        for photoIDs: [String],
        stats: UserStats,
        context: ModelContext
    ) -> ReviewPersistenceSnapshot {
        let reviewedPhotoIDs = Set(photoIDs.filter { gameificationService.isPhotoReviewed(id: $0, context: context) })
        let unlockedAchievementIDs = (try? context.fetch(FetchDescriptor<UnlockedAchievement>())) ?? []

        return ReviewPersistenceSnapshot(
            stats: UserStatsSnapshot(stats: stats),
            reviewedPhotoIDs: reviewedPhotoIDs,
            unlockedAchievementIDs: Set(unlockedAchievementIDs.map(\.achievementId)),
            feedback: GameificationFeedbackSnapshot(service: gameificationService)
        )
    }

    private func restoreReviewPersistence(
        _ snapshot: ReviewPersistenceSnapshot,
        for photoIDs: [String],
        stats: UserStats,
        context: ModelContext
    ) {
        do {
            snapshot.stats.restore(to: stats)
            snapshot.feedback.restore(to: gameificationService)

            for photoID in photoIDs where !snapshot.reviewedPhotoIDs.contains(photoID) {
                if let reviewedPhoto = try fetchReviewedPhoto(id: photoID, context: context) {
                    context.delete(reviewedPhoto)
                }
            }

            let unlockedAchievements = try context.fetch(FetchDescriptor<UnlockedAchievement>())
            for unlockedAchievement in unlockedAchievements where !snapshot.unlockedAchievementIDs.contains(unlockedAchievement.achievementId) {
                context.delete(unlockedAchievement)
            }

            try context.save()

            for photoID in photoIDs {
                if snapshot.reviewedPhotoIDs.contains(photoID) {
                    persistedReviewedIDs.insert(photoID)
                    knownUnreviewedIDs.remove(photoID)
                } else {
                    persistedReviewedIDs.remove(photoID)
                    knownUnreviewedIDs.insert(photoID)
                }
            }
        } catch {
            context.rollback()
            presentError("Failed to restore review progress: \(error.localizedDescription)")
        }
    }

    private func fetchReviewedPhoto(id: String, context: ModelContext) throws -> ReviewedPhoto? {
        var descriptor = FetchDescriptor<ReviewedPhoto>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func isPhotosDeletionCancellation(_ error: Error) -> Bool {
        (error as NSError).code == 3072
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

    private func persistPendingDeletionQueue() {
        guard !pendingDeletionItems.isEmpty else {
            clearPersistedPendingDeletionQueue()
            return
        }

        let persistedItems = pendingDeletionItems.map {
            PersistedPendingDeletionItem(id: $0.id, queuedAt: $0.queuedAt, fileSize: $0.fileSize)
        }

        guard let encoded = try? JSONEncoder().encode(persistedItems) else { return }
        defaults.set(encoded, forKey: UserDefaultsKeys.pendingDeletionQueue)
    }

    private func clearPersistedPendingDeletionQueue() {
        defaults.removeObject(forKey: UserDefaultsKeys.pendingDeletionQueue)
    }

    private func loadPersistedPendingDeletionItems() -> [PersistedPendingDeletionItem] {
        guard let data = defaults.data(forKey: UserDefaultsKeys.pendingDeletionQueue) else {
            return []
        }

        guard let items = try? JSONDecoder().decode([PersistedPendingDeletionItem].self, from: data) else {
            clearPersistedPendingDeletionQueue()
            return []
        }

        return items
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
