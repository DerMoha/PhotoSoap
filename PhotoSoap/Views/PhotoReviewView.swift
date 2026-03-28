import SwiftUI
import SwiftData

struct PhotoReviewView: View {
    @EnvironmentObject private var hapticsService: HapticsService
    @Environment(\.modelContext) private var modelContext

    @StateObject private var viewModel: PhotoReviewViewModel
    @ObservedObject var photoLibraryService: PhotoLibraryService
    @ObservedObject var gameificationService: GameificationService
    @Bindable var stats: UserStats
    @ObservedObject var analyticsService: AnalyticsService
    @ObservedObject var aggregateMetricsService: AggregateMetricsService
    @ObservedObject var adCoordinator: AdCoordinator

    init(
        photoLibraryService: PhotoLibraryService,
        gameificationService: GameificationService,
        stats: UserStats,
        analyticsService: AnalyticsService,
        aggregateMetricsService: AggregateMetricsService,
        adCoordinator: AdCoordinator
    ) {
        self.photoLibraryService = photoLibraryService
        self.gameificationService = gameificationService
        self.stats = stats
        self.analyticsService = analyticsService
        self.aggregateMetricsService = aggregateMetricsService
        self.adCoordinator = adCoordinator
        self._viewModel = StateObject(wrappedValue: PhotoReviewViewModel(
            photoLibraryService: photoLibraryService,
            gameificationService: gameificationService,
            analyticsService: analyticsService,
            aggregateMetricsService: aggregateMetricsService,
            adCoordinator: adCoordinator,
            hapticsService: HapticsService(),
            defaults: UserDefaults.standard
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    compactHeaderSection
                        .padding(.horizontal)
                        .padding(.top, 8)

                    if viewModel.isLoading {
                        Spacer()
                        loadingView
                        Spacer()
                    } else if viewModel.noMorePhotos {
                        Spacer()
                        noMorePhotosView
                        Spacer()
                    } else if let photo = viewModel.currentPhoto {
                        reviewContent(photo: photo)
                            .padding(.top, 8)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
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

                if viewModel.pendingDeletionCount > 0 {
                    deleteQueueTray
                }

                if viewModel.showDeletionSuccessToast {
                    deletionSuccessToast
                }

                if viewModel.showDeletionCancelledToast {
                    deletionCancelledToast
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.setModelContext(modelContext)
                viewModel.setStats(stats)
                viewModel.onViewAppear()

                Task {
                    await viewModel.loadInitialPhoto()
                }
            }
            .onChange(of: gameificationService.showAchievementBanner) { _, isShowing in
                viewModel.onAchievementBannerChanged(isShowing)
            }
            .onChange(of: gameificationService.showStreakCelebration) { _, isShowing in
                viewModel.onStreakCelebrationChanged(isShowing)
            }
            .onChange(of: viewModel.showDailyGoalToast) { _, isShowing in
                viewModel.onDailyGoalToastChanged(isShowing)
            }
            .alert("Error", isPresented: $viewModel.isShowingError) {
                Button("OK") {}
            } message: {
                Text(viewModel.error ?? String(localized: "error.unknown", table: "LocalizableShared"))
            }
            .alert("Start Over?", isPresented: $viewModel.showStartOverConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Start Over", role: .destructive) {
                    viewModel.startOverWithClearing()
                }
            } message: {
                Text(String(localized: "review.startOver.confirmation", table: "LocalizableReview"))
            }
            .sheet(isPresented: $viewModel.showFilterSheet) {
                FilterSheet(
                    photoLibraryService: photoLibraryService,
                    currentFilter: viewModel.currentFilter,
                    onSelect: { filter in
                        viewModel.applyFilter(filter)
                    }
                )
            }
            .sheet(isPresented: $viewModel.showGoalSheet) {
                DailyGoalSettingSheet(
                    isPresented: $viewModel.showGoalSheet,
                    currentTarget: stats.dailyChallengeTarget,
                    onSelect: { newTarget in
                        stats.updateDailyChallengeTarget(newTarget)
                    }
                )
            }
            .sheet(isPresented: $viewModel.isShowingDeleteQueueSheet) {
                DeleteQueueSheet(
                    items: viewModel.pendingDeletionItems,
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
                        Task {
                            await viewModel.commitPendingDeletionBatch()
                        }
                    },
                    onCancel: {
                        viewModel.isShowingDeleteBatchExplainer = false
                    }
                )
                .interactiveDismissDisabled(viewModel.isCommittingDeletionBatch)
            }
            .alert(String(localized: "review.queue.remove.confirmation.title", defaultValue: "Remove from queue?", table: "LocalizableReview"), isPresented: $viewModel.isShowingRemoveFromQueueConfirmation) {
                Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "LocalizableShared"), role: .cancel) {
                    viewModel.dismissRemoveFromQueueConfirmation()
                }
                Button(String(localized: "common.remove", defaultValue: "Remove", table: "LocalizableShared")) {
                    viewModel.confirmRemoveFromQueue()
                }
            } message: {
                Text(String(localized: "review.queue.remove.confirmation.message", defaultValue: "This photo will stay in your library and won't be included in the next delete batch.", table: "LocalizableReview"))
            }
            .alert(String(localized: "review.queue.clear.confirmation.title", defaultValue: "Clear delete queue?", table: "LocalizableReview"), isPresented: $viewModel.isShowingClearQueueConfirmation) {
                Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "LocalizableShared"), role: .cancel) {
                    viewModel.dismissClearQueueConfirmation()
                }
                Button(String(localized: "common.clear", defaultValue: "Clear", table: "LocalizableShared"), role: .destructive) {
                    viewModel.confirmClearQueue()
                }
            } message: {
                Text(String(localized: "review.queue.clear.confirmation.message", defaultValue: "All queued photos will be kept. Nothing will be deleted from Photos.", table: "LocalizableReview"))
            }
        }
    }

    private var compactHeaderSection: some View {
        let challenge = gameificationService.getCurrentDailyChallenge(stats: stats)
        let progress = Double(stats.dailyChallengeProgress) / Double(max(stats.dailyChallengeTarget, 1))

        return CompactHeader(
            todayReviewCount: stats.todayReviewCount,
            progress: progress,
            current: stats.dailyChallengeProgress,
            target: stats.dailyChallengeTarget,
            challengeTitle: challenge.title,
            isFilterActive: !viewModel.currentFilter.isAll,
            onFilterTap: {
                viewModel.showFilterSheet = true
            },
            onGoalTap: {
                viewModel.showGoalSheet = true
            },
            onDailyGoalComplete: {
                viewModel.showDailyGoalToast = true
            }
        )
    }

    private func photoCardSection(photo: Photo) -> some View {
        GeometryReader { geometry in
            ZStack {
                swipeDecisionBackdrop(cardWidth: geometry.size.width)

                PhotoCardDisplay(
                    photo: photo,
                    photoLibraryService: photoLibraryService,
                    offset: viewModel.cardOffset,
                    rotation: viewModel.cardRotation,
                    swipeProgress: viewModel.swipeProgress,
                    swipeDirection: viewModel.swipeDirection
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
        VStack(spacing: 12) {
            photoCardSection(photo: photo)
                .frame(maxHeight: .infinity)

            if adCoordinator.shouldShowBanner(at: .reviewBanner),
               let unitID = adCoordinator.unitID(for: .reviewBanner) {
                ReviewBannerAdView(adUnitID: unitID)
                    .frame(height: 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: adCoordinator.adsEnabled)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(String(localized: "review.loading", table: "LocalizableReview"))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(String(localized: "review.empty", table: "LocalizableReview"))
                .font(.title2)
                .fontWeight(.semibold)
            Text(String(localized: "review.empty.description", table: "LocalizableReview"))
                .foregroundStyle(.secondary)
        }
    }

    private var noMorePhotosView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text(String(localized: "review.complete.title", table: "LocalizableReview"))
                .font(.title)
                .fontWeight(.bold)

            Text(String(localized: "review.complete.subtitle", table: "LocalizableReview"))
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("\(viewModel.persistedReviewedIDs.count) photos reviewed")
                    .foregroundStyle(.secondary)

                Text("\(viewModel.cycleDeletedCount) deleted • \(viewModel.cycleKeptCount) kept")
                    .foregroundStyle(.secondary)
            }
            .padding(.top)

            Button {
                viewModel.showStartOverConfirmation = true
            } label: {
                Label(String(localized: "review.startOver", table: "LocalizableReview"), systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top)
        }
        .padding()
    }

    @ViewBuilder
    private var achievementBanner: some View {
        if gameificationService.showAchievementBanner,
           let achievement = gameificationService.newlyUnlockedAchievement {
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
            .animation(.spring(), value: gameificationService.showAchievementBanner)
        }
    }

    @ViewBuilder
    private var streakCelebration: some View {
        if gameificationService.showStreakCelebration,
           let milestone = gameificationService.streakMilestoneReached {
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
            .animation(.spring(), value: gameificationService.showStreakCelebration)
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
        VStack {
            Spacer()
            DeleteQueueTray(
                queueCount: viewModel.pendingDeletionCount,
                bytesFreed: viewModel.pendingDeletionBytesFormatted,
                onUndo: {
                    viewModel.undoLastQueuedDeletion()
                },
                onReviewQueue: {
                    viewModel.isShowingDeleteQueueSheet = true
                },
                onDeleteAll: {
                    viewModel.requestCommitPendingDeletionBatch()
                }
            )
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
                    Text(String(localized: "review.queue.deletedSuccess.detail", defaultValue: "Photos removed from your library.", table: "LocalizableReview"))
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
                    Text(String(localized: "review.queue.cancelled.detail", defaultValue: "Your queued photos are still here.", table: "LocalizableReview"))
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
}

#Preview {
    PhotoReviewView(
        photoLibraryService: PhotoLibraryService(),
        gameificationService: GameificationService(),
        stats: UserStats(),
        analyticsService: AnalyticsService(),
        aggregateMetricsService: AggregateMetricsService(),
        adCoordinator: AdCoordinator()
    )
    .environmentObject(HapticsService())
}
