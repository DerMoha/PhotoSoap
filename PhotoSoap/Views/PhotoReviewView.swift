import SwiftUI
import SwiftData

struct PhotoReviewView: View {
    @ObservedObject var photoLibraryService: PhotoLibraryService
    @ObservedObject var gameificationService: GameificationService
    @Bindable var stats: UserStats
    @ObservedObject var analyticsService: AnalyticsService
    @ObservedObject var aggregateMetricsService: AggregateMetricsService
    @ObservedObject var adCoordinator: AdCoordinator
    
    @Environment(\.modelContext) private var modelContext

    @State private var currentPhoto: Photo?
    @State private var nextPhoto: Photo?
    @State private var isLoading = false
    @State private var error: String?
    @State private var showError = false
    @State private var noMorePhotos = false
    @State private var cardOffset: CGSize = .zero
    @State private var cardRotation: Double = 0
    @State private var swipeProgress: CGFloat = 0
    @State private var swipeDirection: SwipeDirection?
    
    @State private var isProcessingAction = false  // Prevents concurrent button presses
    @State private var currentFilter: PhotoFilter = .all
    @State private var showFilterSheet = false
    @State private var persistedReviewedIDs: Set<String> = []
    @State private var knownUnreviewedIDs: Set<String> = []
    @State private var hasTrackedReviewStart = false
    private let swipeActionThreshold: CGFloat = 100
    private let swipeFeedbackDistance: CGFloat = 140
    private let swipeOverlayThreshold: CGFloat = 12

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Compact header
                    compactHeaderSection
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // Photo card takes remaining space
                    if isLoading {
                        Spacer()
                        loadingView
                        Spacer()
                    } else if noMorePhotos {
                        Spacer()
                        noMorePhotosView
                        Spacer()
                    } else if let photo = currentPhoto {
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
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !hasTrackedReviewStart {
                    analyticsService.track(.reviewStarted(filter: currentFilter))
                    hasTrackedReviewStart = true
                }

                Task {
                    await loadInitialPhoto()
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(error ?? "error.unknown")
            }
            .sheet(isPresented: $showFilterSheet) {
                FilterSheet(
                    photoLibraryService: photoLibraryService,
                    currentFilter: currentFilter,
                    onSelect: { filter in
                        applyFilter(filter)
                    }
                )
            }
        }
    }

    private var compactHeaderSection: some View {
        let challenge = gameificationService.getCurrentDailyChallenge(stats: stats)
        let progress = Double(stats.dailyChallengeProgress) / Double(max(stats.dailyChallengeTarget, 1))

        return CompactHeader(
            currentStreak: stats.currentStreak,
            progress: progress,
            current: stats.dailyChallengeProgress,
            target: stats.dailyChallengeTarget,
            challengeTitle: challenge.title,
            isFilterActive: !currentFilter.isAll,
            onFilterTap: {
                showFilterSheet = true
            }
        )
    }

    private func photoCardSection(photo: Photo) -> some View {
        PhotoCardDisplay(
            photo: photo,
            photoLibraryService: photoLibraryService,
            offset: cardOffset,
            rotation: cardRotation,
            swipeProgress: swipeProgress,
            swipeDirection: swipeDirection
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    handleDragGesture(value)
                }
                .onEnded { value in
                    Task {
                        await handleDragEnd(value)
                    }
                }
        )
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
            Text("review.loading")
                .foregroundStyle(.secondary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("review.empty")
                .font(.title2)
                .fontWeight(.semibold)
            Text("review.empty.description")
                .foregroundStyle(.secondary)
        }
    }

    private var noMorePhotosView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("review.complete.title")
                .font(.title)
                .fontWeight(.bold)

            Text("review.complete.subtitle")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text(String(localized: "review.stats", defaultValue: "\(stats.totalReviewed) photos reviewed"))
                Text(String(localized: "review.statsDetail", defaultValue: "\(stats.totalDeleted) deleted • \(stats.totalKept) kept"))
                    .foregroundStyle(.secondary)
            }
            .padding(.top)

            Button {
                refreshLibrary()
            } label: {
                Label("review.startOver", systemImage: "arrow.counterclockwise")
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
                        Text("achievement.unlocked")
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

                    Text(String(localized: "streak.milestone", defaultValue: "\(milestone) Streak!"))
                        .font(.title)
                        .fontWeight(.bold)

                    Text("streak.fire")
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

    // MARK: - Actions

    private func loadInitialPhoto() async {
        isLoading = true
        error = nil
        noMorePhotos = false
        persistedReviewedIDs.removeAll()
        knownUnreviewedIDs.removeAll()

        do {
            photoLibraryService.setSessionReviewedIDs(Set<String>())

            if let photo = try await nextAvailablePhoto() {
                currentPhoto = photo
                await preloadNextPhoto()
            } else {
                noMorePhotos = true
            }
        } catch {
            self.error = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    private func preloadNextPhoto() async {
        let excluded = currentPhoto.map { Set<String>([$0.id]) } ?? Set<String>()
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
        guard let photo = currentPhoto else { return }
        
        isProcessingAction = true
        defer { isProcessingAction = false }

        let challengeType = DailyChallengeType(rawValue: stats.dailyChallengeType) ?? .review

        // 1. Mark in DB
        do {
            try gameificationService.markPhotoReviewed(id: photo.id, context: modelContext)
            gameificationService.processPhotoReview(
                action: .keep,
                fileSize: 0,
                stats: stats,
                challengeType: challengeType
            )
        } catch {
            self.error = "Failed to update review history: \(error.localizedDescription)"
            showError = true
            return
        }

        guard persistReviewProgress(for: photo.id, cacheInSession: true) else {
            return
        }

        analyticsService.track(.photoKept(filter: currentFilter))
        aggregateMetricsService.recordReview()

        await advanceToNextPhoto()
    }

    private func deletePhoto() async {
        guard !isProcessingAction else { return }
        guard let photo = currentPhoto else { return }
        
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
                    challengeType: challengeType
                )
            } catch {
                self.error = "Failed to update review history: \(error.localizedDescription)"
                showError = true
                return
            }

            guard persistReviewProgress(for: photo.id, cacheInSession: false) else {
                return
            }

            analyticsService.track(.photoDeleted(filter: currentFilter))
            aggregateMetricsService.recordDeletion(bytesFreed: resolvedFileSize)

            await advanceToNextPhoto()
        } catch let error as NSError {
            if error.code == 3072 {
                aggregateMetricsService.recordReview()
                await advanceToNextPhoto()
            } else {
                self.error = "Failed to delete photo: \(error.localizedDescription)"
                showError = true
            }
        }
    }

    private func persistReviewProgress(for photoID: String, cacheInSession: Bool) -> Bool {
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
            self.error = "Failed to save your progress: \(error.localizedDescription)"
            showError = true
            return false
        }
    }

    private func isKnownReviewed(_ photoID: String) -> Bool {
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
            cardOffset = .zero
            cardRotation = 0
            swipeProgress = 0
            swipeDirection = nil
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
        if let photo = try? await nextAvailablePhoto() {
            currentPhoto = photo
            await preloadNextPhoto()
        } else {
            currentPhoto = nil
            noMorePhotos = true
            analyticsService.track(.reviewBatchCompleted(filter: currentFilter))
        }
    }
    
    private func handleDragGesture(_ value: DragGesture.Value) {
        guard !isProcessingAction else { return }
        
        cardOffset = value.translation
        cardRotation = Double(value.translation.width / 18)

        let translation = value.translation.width
        let distance = abs(translation)
        let progress = min(distance / swipeFeedbackDistance, 1)

        if distance < swipeOverlayThreshold {
            swipeProgress = 0
            swipeDirection = nil
        } else {
            swipeProgress = progress
            swipeDirection = translation > 0 ? .keep : .delete
        }
    }

    private func handleDragEnd(_ value: DragGesture.Value) async {
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
            await deletePhoto()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                cardOffset = .zero
                cardRotation = 0
                swipeProgress = 0
                swipeDirection = nil
            }
        }
    }

    private func refreshLibrary() {
        photoLibraryService.refreshLibrary()
        noMorePhotos = false

        Task {
            await loadInitialPhoto()
        }
    }

    private func applyFilter(_ filter: PhotoFilter) {
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
}
