import SwiftUI
import SwiftData

struct PhotoReviewView: View {
    @EnvironmentObject private var hapticsService: HapticsService
    @Environment(\.modelContext) private var modelContext

    @AppStorage(UserDefaultsKeys.hasSeenPhotoPreviewHint) private var hasSeenPhotoPreviewHint = false

    @State private var previewPhoto: Photo?
    @State private var showPreviewHint = false
    @StateObject private var viewModel: PhotoReviewViewModel
    @ObservedObject var photoLibraryService: PhotoLibraryService
    @ObservedObject var gamificationService: GamificationService
    @Bindable var stats: UserStats
    @ObservedObject var reviewAccountingService: ReviewAccountingService
    @ObservedObject var privacyCollectionService: PrivacyCollectionService

    private let dailyGoalOptions = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

    init(
        photoLibraryService: PhotoLibraryService,
        gamificationService: GamificationService,
        stats: UserStats,
        reviewAccountingService: ReviewAccountingService,
        privacyCollectionService: PrivacyCollectionService,
        hapticsService: HapticsService
    ) {
        self.photoLibraryService = photoLibraryService
        self.gamificationService = gamificationService
        self.stats = stats
        self.reviewAccountingService = reviewAccountingService
        self.privacyCollectionService = privacyCollectionService
        self._viewModel = StateObject(wrappedValue: PhotoReviewViewModel(
            photoLibraryService: photoLibraryService,
            reviewAccountingService: reviewAccountingService,
            privacyCollectionService: privacyCollectionService,
            hapticsService: hapticsService,
            defaults: UserDefaults.standard
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                GeometryReader { geometry in
                    swipeDecisionBackdrop(cardWidth: geometry.size.width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    if !viewModel.noMorePhotos {
                        compactHeaderSection
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    if shouldShowLimitedAccessBanner {
                        limitedAccessBanner
                            .padding(.horizontal)
                            .padding(.top, 12)
                    }

                    if viewModel.isLoading {
                        Spacer()
                        loadingView
                        Spacer()
                    } else if viewModel.noMorePhotos {
                        ScrollView {
                            noMorePhotosView
                                .frame(maxWidth: .infinity)
                        }
                    } else if let photo = viewModel.currentPhoto {
                        reviewContent(photo: photo)
                            .padding(.top, 6)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 4)
                            .frame(maxHeight: .infinity)
                    } else {
                        Spacer()
                        emptyStateView
                        Spacer()
                    }

                }
                achievementBanner
                streakCelebration
                dailyGoalToast

                if viewModel.showDeletionSuccessToast {
                    deletionSuccessToast
                }

                if viewModel.showDeletionCancelledToast {
                    deletionCancelledToast
                }

                if viewModel.showDeleteListIntroToast {
                    deleteListIntroToast
                }

                if viewModel.showQueuePrunedToast {
                    queuePrunedToast
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                bottomChrome
            }
            .onAppear {
                viewModel.setModelContext(modelContext)
                viewModel.setStats(stats)
                viewModel.onViewAppear()
                viewModel.restorePendingDeletionQueueIfNeeded()

                Task {
                    await viewModel.loadInitialPhoto()
                }
            }
            .onChange(of: gamificationService.showAchievementBanner) { _, isShowing in
                viewModel.onAchievementBannerChanged(isShowing)
            }
            .onChange(of: gamificationService.showStreakCelebration) { _, isShowing in
                viewModel.onStreakCelebrationChanged(isShowing)
            }
            .onChange(of: viewModel.showDailyGoalToast) { _, isShowing in
                viewModel.onDailyGoalToastChanged(isShowing)
            }
            .onChange(of: photoLibraryService.libraryRevision) { _, _ in
                viewModel.handleLibraryRevisionChange()
            }
            .alert(String(localized: "error.title", table: "LocalizableShared"), isPresented: $viewModel.isShowingError) {
                Button(String(localized: "common.ok", defaultValue: "OK", table: "LocalizableShared")) {}
            } message: {
                Text(viewModel.error ?? String(localized: "error.unknown", table: "LocalizableShared"))
            }
            .alert(String(localized: "review.startOver.confirmation.title", defaultValue: "Review again?", table: "LocalizableReview"), isPresented: $viewModel.showStartOverConfirmation) {
                Button(String(localized: "common.cancel", table: "LocalizableShared"), role: .cancel) {}
                Button(String(localized: "review.startOver", table: "LocalizableReview"), role: .destructive) {
                    viewModel.startOver()
                }
            } message: {
                Text(String(localized: "review.startOver.confirmation", table: "LocalizableReview"))
            }
            .confirmationDialog(
                String(localized: "review.startOver.withQueue.title", defaultValue: "Review again with items in your Delete List?", table: "LocalizableReview"),
                isPresented: $viewModel.showQueuedStartOverConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "review.startOver", table: "LocalizableReview"), role: .destructive) {
                    viewModel.startOver()
                }

                Button(String(localized: "review.startOver.reviewQueue", defaultValue: "Review Delete List", table: "LocalizableReview")) {
                    viewModel.reviewPendingDeletionQueue()
                }

                Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "LocalizableShared"), role: .cancel) {}
            } message: {
                Text(String(localized: "review.startOver.withQueue.message", defaultValue: "Your Delete List stays saved. You can review again now or open the Delete List first.", table: "LocalizableReview"))
            }
            .sheet(isPresented: $viewModel.showFilterSheet) {
                FilterSheet(
                    photoLibraryService: photoLibraryService,
                    currentFilter: viewModel.currentFilter,
                    currentMediaKind: viewModel.currentMediaKind,
                    onSelect: { filter in
                        viewModel.applyFilter(filter)
                    },
                    onMediaKindChange: { mediaKind in
                        viewModel.applyMediaKind(mediaKind)
                    },
                    onSortOrderChange: { oldestFirst in
                        viewModel.applySortOrder(oldestFirst: oldestFirst)
                    }
                )
            }
            .sheet(isPresented: $viewModel.isShowingDeleteQueueSheet, onDismiss: {
                viewModel.handleDeleteQueueSheetDismissed()
            }) {
                DeleteQueueSheet(
                    items: viewModel.pendingDeletionItems,
                    photoLibraryService: photoLibraryService,
                    onRemoveFromQueue: { item in
                        viewModel.requestRemoveFromQueue(item)
                    },
                    onClearQueue: {
                        viewModel.requestClearQueue()
                    },
                    onDeleteAll: {
                        viewModel.requestCommitPendingDeletionBatch()
                    },
                    onDismiss: {
                        viewModel.isShowingDeleteQueueSheet = false
                    }
                )
                .interactiveDismissDisabled(viewModel.isCommittingDeletionBatch)
            }
            .sheet(isPresented: $viewModel.isShowingDeleteBatchExplainer) {
                DeleteBatchExplainerSheet(
                    itemCount: viewModel.pendingDeletionCount,
                    isCommitting: viewModel.isCommittingDeletionBatch,
                    onConfirm: {
                        viewModel.confirmDeleteBatchExplainer()
                    },
                    onCancel: {
                        viewModel.isShowingDeleteBatchExplainer = false
                    }
                )
                .interactiveDismissDisabled(viewModel.isCommittingDeletionBatch)
            }
            .fullScreenCover(item: $previewPhoto) { photo in
                PhotoPreviewSheet(
                    photo: photo,
                    photoLibraryService: photoLibraryService
                )
            }
            .alert(String(localized: "review.queue.remove.confirmation.title", defaultValue: "Remove from queue?", table: "LocalizableReview"), isPresented: $viewModel.isShowingRemoveFromQueueConfirmation) {
                Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "LocalizableShared"), role: .cancel) {
                    viewModel.dismissRemoveFromQueueConfirmation()
                }
                Button(String(localized: "common.remove", defaultValue: "Remove", table: "LocalizableShared")) {
                    viewModel.confirmRemoveFromQueue()
                }
            } message: {
                Text(String(localized: "review.queue.remove.confirmation.message", defaultValue: "This item will stay in your library and won't be included in the next delete batch.", table: "LocalizableReview"))
            }
            .alert(String(localized: "review.queue.clear.confirmation.title", defaultValue: "Clear Delete List?", table: "LocalizableReview"), isPresented: $viewModel.isShowingClearQueueConfirmation) {
                Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "LocalizableShared"), role: .cancel) {
                    viewModel.dismissClearQueueConfirmation()
                }
                Button(String(localized: "common.clear", defaultValue: "Clear", table: "LocalizableShared"), role: .destructive) {
                    viewModel.confirmClearQueue()
                }
            } message: {
                Text(String(localized: "review.queue.clear.confirmation.message", defaultValue: "All items will be removed from your Delete List and kept in Photos.", table: "LocalizableReview"))
            }
        }
    }

    private var compactHeaderSection: some View {
        let challenge = gamificationService.getCurrentDailyChallenge(stats: stats)
        let current = challenge.progress(from: stats)
        let progress = Double(current) / Double(max(stats.dailyChallengeTarget, 1))

        return CompactHeader(
            todayReviewCount: stats.todayReviewCount,
            progress: progress,
            current: current,
            target: stats.dailyChallengeTarget,
            isFilterActive: !viewModel.currentFilter.isAll || viewModel.currentMediaKind != .photos,
            goalOptions: dailyGoalOptions,
            onFilterTap: {
                viewModel.showFilterSheet = true
            },
            onGoalSelect: { newTarget in
                hapticsService.selection()
                stats.updateDailyChallengeTarget(newTarget)
            },
            onDailyGoalComplete: {
                viewModel.showDailyGoalToast = true
            }
        )
    }

    private func photoCardSection(photo: Photo) -> some View {
        ZStack(alignment: .bottom) {
            PhotoCardDisplay(
                photo: photo,
                photoLibraryService: photoLibraryService,
                offset: viewModel.cardOffset,
                rotation: viewModel.cardRotation,
                swipeProgress: viewModel.swipeProgress,
                swipeDirection: viewModel.swipeDirection
            )

            if shouldShowPreviewHint {
                previewHintChip
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(
            DragGesture()
                .onChanged { value in
                    viewModel.handleDragGesture(value)
                }
                .onEnded { value in
                    Task {
                        await viewModel.handleDragEnd(value)
                    }
                }
        )
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    presentPreview(for: photo)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: photo))
        .accessibilityHint(String(localized: "review.accessibility.hint", defaultValue: "Double-tap to preview. Swipe right to keep or swipe left to delete.", table: "LocalizableReview"))
        .accessibilityAction(named: Text(String(localized: "review.action.keep", defaultValue: "Keep photo", table: "LocalizableReview"))) {
            Task { await viewModel.performKeepAction() }
        }
        .accessibilityAction(named: Text(String(localized: "review.action.delete", defaultValue: "Delete photo", table: "LocalizableReview"))) {
            Task { await viewModel.performDeleteAction() }
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowPreviewHint)
    }

    private func accessibilityLabel(for photo: Photo) -> String {
        let mediaType = photo.isVideo
            ? String(localized: "review.preview.video", defaultValue: "Video", table: "LocalizableReview")
            : String(localized: "review.preview.photo", defaultValue: "Photo", table: "LocalizableReview")
        return "\(mediaType), \(photo.formattedDate), \(photo.compactDimensions)"
    }

    private func presentPreview(for photo: Photo) {
        guard !viewModel.isProcessingAction else { return }
        guard abs(viewModel.cardOffset.width) < 10, abs(viewModel.cardOffset.height) < 10 else { return }

        hasSeenPhotoPreviewHint = true
        showPreviewHint = false
        previewPhoto = photo
    }

    private var shouldShowPreviewHint: Bool {
        showPreviewHint
            && previewPhoto == nil
            && !viewModel.isProcessingAction
            && viewModel.swipeDirection == nil
            && abs(viewModel.cardOffset.width) < 8
    }

    private var previewHintChip: some View {
        Label(
            String(localized: "review.preview.tapHint", defaultValue: "Tap to preview", table: "LocalizableReview"),
            systemImage: "hand.tap"
        )
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        .allowsHitTesting(false)
    }

    private func swipeDecisionBackdrop(cardWidth: CGFloat) -> some View {
        Group {
            if let direction = viewModel.swipeDirection {
                decisionIcon(direction: direction, cardWidth: cardWidth)
            }
        }
        .animation(.easeOut(duration: 0.18), value: viewModel.swipeDirection)
        .allowsHitTesting(false)
    }

    private func decisionIcon(direction: SwipeDirection, cardWidth: CGFloat) -> some View {
        let iconRadius: CGFloat = 43
        let revealStart = cardWidth / 2
        let revealEnd = cardWidth / 2 + iconRadius * 2
        let absOffset = abs(viewModel.cardOffset.width)
        let p = Double(min(max((absOffset - revealStart) / (revealEnd - revealStart), 0), 1))

        let actionColor = viewModel.color(for: direction)
        let circleFillOpacity = p * 0.18
        let strokeOpacity = p * 0.45 + 0.1
        let iconBrightness = (1 - p) * 0.35
        let iconOpacity = 0.45 + p * 0.55
        let shadowOpacity = p * 0.25
        let shadowRadius: CGFloat = 12 + CGFloat(p) * 6

        return ZStack {
            Circle()
                .fill(actionColor.opacity(circleFillOpacity))
                .background {
                    Circle().fill(Color(.systemGray5).opacity(0.94))
                }
                .overlay {
                    Circle()
                        .stroke(actionColor.opacity(strokeOpacity), lineWidth: 1.5)
                }

            Image(systemName: viewModel.symbolName(for: direction))
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(actionColor)
                .saturation(p)
                .brightness(iconBrightness)
                .opacity(iconOpacity)
        }
        .frame(width: 86, height: 86)
        .scaleEffect(viewModel.decisionIconScale)
        .opacity(viewModel.decisionIconOpacity)
        .shadow(color: actionColor.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: 6)
    }

    @ViewBuilder
    private func reviewContent(photo: Photo) -> some View {
        photoCardSection(photo: photo)
            .frame(maxHeight: .infinity)
            .task(id: photo.id) {
                await schedulePreviewHintIfNeeded()
            }
    }

    private func schedulePreviewHintIfNeeded() async {
        guard !hasSeenPhotoPreviewHint else {
            await MainActor.run {
                showPreviewHint = false
            }
            return
        }

        await MainActor.run {
            showPreviewHint = false
        }

        try? await Task.sleep(nanoseconds: 700_000_000)
        guard !Task.isCancelled, previewPhoto == nil else { return }

        await MainActor.run {
            withAnimation(.easeOut(duration: 0.2)) {
                showPreviewHint = true
            }
        }

        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard !Task.isCancelled else { return }

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                showPreviewHint = false
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(loadingText)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyStateSymbolName)
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(emptyStateTitle)
                .font(.title2)
                .fontWeight(.semibold)
            Text(emptyStateDescription)
                .foregroundStyle(.secondary)
        }
    }

    private var noMorePhotosView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text(completionTitle)
                .font(.title)
                .fontWeight(.bold)

            Text(completionSubtitle)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Text(reviewedCountSummary)
                    .foregroundStyle(.secondary)

                Text(
                    String(localized: "review.statsDetail", defaultValue: "%d deleted • %d kept", table: "LocalizableReview")
                        .replacingOccurrences(of: "%d", with: "\(viewModel.cycleDeletedCount)", options: [], range: nil)
                        .replacingOccurrences(of: "%d", with: "\(viewModel.cycleKeptCount)", options: [], range: nil)
                )
                    .foregroundStyle(.secondary)
            }
            .padding(.top)

            if viewModel.pendingDeletionCount > 0 {
                deleteListSummaryCard
            }

            if photoLibraryService.authorizationStatus == .limited {
                LimitedAccessCard(
                    title: String(localized: "review.complete.limited.title", table: "LocalizableReview"),
                    message: String(localized: "review.complete.limited.description", table: "LocalizableReview"),
                    buttonTitle: String(localized: "limitedAccess.chooseMore", table: "LocalizableShared"),
                    style: .completion,
                    onManage: {
                        privacyCollectionService.track(.limitedLibraryPickerOpened())
                        photoLibraryService.presentLimitedLibraryPicker()
                    }
                )
            }

            VStack(spacing: 12) {
                if viewModel.pendingDeletionCount > 0 {
                    Button {
                        viewModel.isShowingDeleteQueueSheet = true
                    } label: {
                        Label(String(localized: "review.startOver.reviewQueue", defaultValue: "Review Delete List", table: "LocalizableReview"), systemImage: "list.bullet")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.red)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                Button {
                    viewModel.requestStartOver()
                } label: {
                    Label(String(localized: "review.startOver", table: "LocalizableReview"), systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.pendingDeletionCount > 0 ? Color(.secondarySystemGroupedBackground) : .blue)
                        .foregroundStyle(viewModel.pendingDeletionCount > 0 ? Color.primary : .white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.top)
        }
        .padding()
    }

    private var shouldShowLimitedAccessBanner: Bool {
        photoLibraryService.authorizationStatus == .limited
            && !viewModel.isLoading
            && !viewModel.noMorePhotos
            && viewModel.currentPhoto != nil
    }

    private var loadingText: String {
        switch viewModel.currentMediaKind {
        case .photos:
            return String(localized: "review.loading", defaultValue: "Loading photos...", table: "LocalizableReview")
        case .videos:
            return String(localized: "review.loading.videos", defaultValue: "Loading videos...", table: "LocalizableReview")
        case .all:
            return String(localized: "review.loading.media", defaultValue: "Loading your library...", table: "LocalizableReview")
        }
    }

    private var emptyStateSymbolName: String {
        switch viewModel.currentMediaKind {
        case .photos:
            return "photo.badge.plus"
        case .videos:
            return "video.badge.plus"
        case .all:
            return "rectangle.stack.badge.plus"
        }
    }

    private var emptyStateTitle: String {
        switch viewModel.currentMediaKind {
        case .photos:
            return String(localized: "review.empty", defaultValue: "No photos to review", table: "LocalizableReview")
        case .videos:
            return String(localized: "review.empty.videos", defaultValue: "No videos to review", table: "LocalizableReview")
        case .all:
            return String(localized: "review.empty.media", defaultValue: "No media to review", table: "LocalizableReview")
        }
    }

    private var emptyStateDescription: String {
        switch viewModel.currentMediaKind {
        case .photos:
            return String(localized: "review.empty.description", defaultValue: "Your photo library appears to be empty", table: "LocalizableReview")
        case .videos:
            return String(localized: "review.empty.videos.description", defaultValue: "Your video library appears to be empty", table: "LocalizableReview")
        case .all:
            return String(localized: "review.empty.media.description", defaultValue: "Your photo and video library appears to be empty", table: "LocalizableReview")
        }
    }

    private var limitedAccessBanner: some View {
        LimitedAccessCard(
            title: String(localized: "limitedAccess.title", table: "LocalizableShared"),
            message: String(localized: "limitedAccess.description", table: "LocalizableShared"),
            buttonTitle: String(localized: "limitedAccess.chooseMore", table: "LocalizableShared"),
            style: .stats,
            onManage: {
                privacyCollectionService.track(.limitedLibraryPickerOpened())
                photoLibraryService.presentLimitedLibraryPicker()
            }
        )
    }

    private var completionTitle: String {
        if photoLibraryService.authorizationStatus == .limited {
            switch viewModel.currentMediaKind {
            case .photos:
                return String(localized: "review.complete.title.limited", defaultValue: "Selected Photos Reviewed", table: "LocalizableReview")
            case .videos:
                return String(localized: "review.complete.title.limited.videos", defaultValue: "Selected Videos Reviewed", table: "LocalizableReview")
            case .all:
                return String(localized: "review.complete.title.limited.media", defaultValue: "Selected Media Reviewed", table: "LocalizableReview")
            }
        }

        return String(localized: "review.complete.title", table: "LocalizableReview")
    }

    private var completionSubtitle: String {
        if photoLibraryService.authorizationStatus == .limited {
            return String(localized: "review.complete.subtitle.limited", defaultValue: "You've reviewed everything in your current selection. Add more items if you want to keep going.", table: "LocalizableReview")
        }

        switch viewModel.currentMediaKind {
        case .photos:
            return String(localized: "review.complete.subtitle", defaultValue: "You've reviewed all available photos.", table: "LocalizableReview")
        case .videos:
            return String(localized: "review.complete.subtitle.videos", defaultValue: "You've reviewed all available videos.", table: "LocalizableReview")
        case .all:
            return String(localized: "review.complete.subtitle.media", defaultValue: "You've reviewed all available photos and videos.", table: "LocalizableReview")
        }
    }

    private var reviewedCountSummary: String {
        let count = viewModel.persistedReviewedIDs.count

        switch viewModel.currentMediaKind {
        case .photos:
            return String.localizedStringWithFormat(
                String(localized: "review.stats", defaultValue: "%d photos reviewed", table: "LocalizableReview"),
                count
            )
        case .videos:
            return String.localizedStringWithFormat(
                String(localized: "review.stats.videos", defaultValue: "%d videos reviewed", table: "LocalizableReview"),
                count
            )
        case .all:
            return String.localizedStringWithFormat(
                String(localized: "review.stats.media", defaultValue: "%d items reviewed", table: "LocalizableReview"),
                count
            )
        }
    }

    private var deleteListSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                String.localizedStringWithFormat(
                    String(localized: "review.queue.pendingSummary", defaultValue: "%lld items are in your Delete List", table: "LocalizableReview"),
                    viewModel.pendingDeletionCount
                )
            )
            .font(.headline)

            Text(String(localized: "review.queue.pendingSummary.detail", defaultValue: "These items stay in Photos until you confirm deletion in iOS.", table: "LocalizableReview"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var achievementBanner: some View {
        if gamificationService.showAchievementBanner,
           let achievement = gamificationService.newlyUnlockedAchievement {
            VStack {
                Spacer()

                HStack(spacing: 12) {
                    Image(systemName: achievement.iconName)
                        .font(.title2)
                        .foregroundStyle(.yellow)

                    VStack(alignment: .leading) {
                        Text(String(localized: "achievement.unlocked", table: "LocalizableAchievements"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(achievement.title)
                            .font(.headline)
                    }

                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 10)
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(.spring(), value: gamificationService.showAchievementBanner)
        }
    }

    @ViewBuilder
    private var streakCelebration: some View {
        if gamificationService.showStreakCelebration,
           let milestone = gamificationService.streakMilestoneReached {
            VStack {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.orange)

                    Text(String(localized: "streak.milestone", defaultValue: "\(milestone) Streak!", table: "LocalizableReview"))
                        .font(.title)
                        .fontWeight(.bold)

                    Text(String(localized: "streak.fire", table: "LocalizableReview"))
                        .foregroundStyle(.secondary)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(radius: 20)
                .transition(.scale.combined(with: .opacity))

                Spacer()
            }
            .animation(.spring(), value: gamificationService.showStreakCelebration)
        }
    }

    @ViewBuilder
    private var dailyGoalToast: some View {
        if viewModel.showDailyGoalToast {
            VStack {
                Spacer()

                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)

                    VStack(alignment: .leading) {
                        Text(String(localized: "dailyGoal.complete", defaultValue: "Daily Goal Complete!", table: "LocalizableReview"))
                            .font(.headline)
                        Text(String(localized: "dailyGoal.reward", defaultValue: "Great job!", table: "LocalizableReview"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 10)
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))

                Spacer()
            }
            .animation(.spring(), value: viewModel.showDailyGoalToast)
            .onAppear {
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        viewModel.dismissDailyGoalToast()
                    }
                }
            }
        }
    }

    private var deleteQueueTray: some View {
        DeleteQueueTray(
            queueCount: viewModel.pendingDeletionCount,
            onUndo: {
                viewModel.undoLastQueuedDeletion()
            },
            onReviewQueue: {
                viewModel.isShowingDeleteQueueSheet = true
            }
        )
    }

    @ViewBuilder
    private var bottomChrome: some View {
        if viewModel.pendingDeletionCount > 0 && !viewModel.noMorePhotos {
            VStack(spacing: 8) {
                deleteQueueTray
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background(Color(.systemGroupedBackground).opacity(0.96))
        }
    }

    private var deletionSuccessToast: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                VStack(alignment: .leading) {
                    Text(String(localized: "review.queue.deletedSuccess", defaultValue: "Deleted!", table: "LocalizableReview"))
                        .font(.headline)
                    Text(String(localized: "review.queue.deletedSuccess.detail", defaultValue: "Items removed from your library.", table: "LocalizableReview"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 10)
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        viewModel.dismissDeletionSuccessToast()
                    }
                }
            }
        }
    }

    private var deletionCancelledToast: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading) {
                    Text(String(localized: "review.queue.cancelled", defaultValue: "Deletion Cancelled", table: "LocalizableReview"))
                        .font(.headline)
                    Text(String(localized: "review.queue.cancelled.detail", defaultValue: "Your items are still in your Delete List.", table: "LocalizableReview"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 10)
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onAppear {
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        viewModel.dismissDeletionCancelledToast()
                    }
                }
            }
        }
    }

    private var deleteListIntroToast: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading) {
                    Text(String(localized: "review.queue.added.title", defaultValue: "Added to Delete List", table: "LocalizableReview"))
                        .font(.headline)
                    Text(String(localized: "review.queue.added.detail", defaultValue: "Nothing has been deleted yet. iOS will ask before anything is removed.", table: "LocalizableReview"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 10)
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onTapGesture {
                viewModel.dismissDeleteListIntroToast()
            }
        }
    }

    private var queuePrunedToast: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading) {
                    Text(String(localized: "review.queue.pruned.title", defaultValue: "Delete List Updated", table: "LocalizableReview"))
                        .font(.headline)
                    Text(String(localized: "review.queue.pruned.detail", defaultValue: "Some queued items were no longer available and were removed.", table: "LocalizableReview"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 10)
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onTapGesture {
                viewModel.dismissQueuePrunedToast()
            }
        }
    }
}

#Preview {
    let hapticsService = HapticsService()
    let gamificationService = GamificationService()

    PhotoReviewView(
        photoLibraryService: PhotoLibraryService(),
        gamificationService: gamificationService,
        stats: UserStats(),
        reviewAccountingService: ReviewAccountingService(gamificationService: gamificationService),
        privacyCollectionService: PrivacyCollectionService(
            analyticsService: AnalyticsService(),
            aggregateMetricsService: AggregateMetricsService()
        ),
        hapticsService: hapticsService
    )
    .environmentObject(hapticsService)
}
