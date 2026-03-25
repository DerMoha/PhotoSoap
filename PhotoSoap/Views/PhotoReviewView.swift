import SwiftUI
import SwiftData

struct PhotoReviewView: View {
    @EnvironmentObject private var hapticsService: HapticsService
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
    @State private var isShowingError = false
    @State private var noMorePhotos = false
    @State private var cardOffset: CGSize = .zero
    @State private var cardRotation: Double = 0
    @State private var swipeProgress: CGFloat = 0
    @State private var swipeDirection: SwipeDirection?
    
    @State private var isProcessingAction = false  // Prevents concurrent button presses
    @State private var currentFilter: PhotoFilter = .all
    @State private var showFilterSheet = false
    @State private var showGoalSheet = false
    @State private var persistedReviewedIDs: Set<String> = []
    @State private var knownUnreviewedIDs: Set<String> = []
    @State private var hasTrackedReviewStart = false
    @State private var cycleKeptCount = 0
    @State private var cycleDeletedCount = 0
    @State private var showStartOverConfirmation = false
    @State private var showDailyGoalToast = false
    @State private var hasTriggeredSwipeThresholdFeedback = false
    @State private var lastCelebrationFeedbackDate = Date.distantPast
    private let swipeActionThreshold: CGFloat = 100
    private let swipeFeedbackDistance: CGFloat = 140
    private let swipeOverlayThreshold: CGFloat = 12
    private let cardCornerRadius: CGFloat = 16
    private let celebrationFeedbackCooldown: TimeInterval = 0.75

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
                dailyGoalToast
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
            .onChange(of: gameificationService.showAchievementBanner) { _, isShowing in
                guard isShowing else { return }
                triggerCelebrationFeedbackIfNeeded()
            }
            .onChange(of: gameificationService.showStreakCelebration) { _, isShowing in
                guard isShowing else { return }
                triggerCelebrationFeedbackIfNeeded()
            }
            .onChange(of: showDailyGoalToast) { _, isShowing in
                guard isShowing else { return }
                triggerCelebrationFeedbackIfNeeded()
            }
            .alert("Error", isPresented: $isShowingError) {
                Button("OK") {}
            } message: {
                Text(error ?? String(localized: "error.unknown", table: "LocalizableShared"))
            }
            .alert("Start Over?", isPresented: $showStartOverConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Start Over", role: .destructive) {
                    startOverWithClearing()
                }
            } message: {
                Text(String(localized: "review.startOver.confirmation", table: "LocalizableReview"))
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
            .sheet(isPresented: $showGoalSheet) {
                DailyGoalSettingSheet(
                    isPresented: $showGoalSheet,
                    currentTarget: stats.dailyChallengeTarget,
                    onSelect: { newTarget in
                        stats.updateDailyChallengeTarget(newTarget)
                    }
                )
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
            isFilterActive: !currentFilter.isAll,
            onFilterTap: {
                showFilterSheet = true
            },
            onGoalTap: {
                showGoalSheet = true
            },
            onDailyGoalComplete: {
                showDailyGoalToast = true
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
                    offset: cardOffset,
                    rotation: cardRotation,
                    swipeProgress: swipeProgress,
                    swipeDirection: swipeDirection
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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

    private func swipeDecisionBackdrop(cardWidth: CGFloat) -> some View {
        Group {
            if let direction = swipeDirection {
                decisionIcon(direction: direction, cardWidth: cardWidth)
            }
        }
        .animation(.easeOut(duration: 0.18), value: swipeDirection)
        .allowsHitTesting(false)
    }

    private func decisionIcon(direction: SwipeDirection, cardWidth: CGFloat) -> some View {
        // The icon (86pt) is centered. It starts peeking out when the card edge
        // passes the center, i.e. offset > cardWidth/2 - iconRadius.
        // Color fill ramps from that reveal point to the action threshold.
        let iconRadius: CGFloat = 43
        let revealStart = cardWidth / 2
        let revealEnd = cardWidth / 2 + iconRadius * 2
        let absOffset = abs(cardOffset.width)
        let p = Double(min(max((absOffset - revealStart) / (revealEnd - revealStart), 0), 1))

        let actionColor = color(for: direction)
        let circleFillOpacity = p * 0.18
        let strokeOpacity = p * 0.45 + 0.1
        let iconBrightness = (1 - p) * 0.35
        let iconOpacity = 0.45 + p * 0.55
        let shadowOpacity = p * 0.25
        let shadowRadius: CGFloat = 12 + CGFloat(p) * 6

        return ZStack {
            // Circle that tints from gray toward the action color
            Circle()
                .fill(actionColor.opacity(circleFillOpacity))
                .background {
                    Circle().fill(Color(.systemGray5).opacity(0.94))
                }
                .overlay {
                    Circle()
                        .stroke(actionColor.opacity(strokeOpacity), lineWidth: 1.5)
                }

            // Single icon: starts desaturated/washed-out, fills with saturated color
            Image(systemName: symbolName(for: direction))
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(actionColor)
                .saturation(p)
                .brightness(iconBrightness)
                .opacity(iconOpacity)
        }
        .frame(width: 86, height: 86)
        .scaleEffect(decisionIconScale)
        .opacity(decisionIconOpacity)
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
                Text("\(persistedReviewedIDs.count) photos reviewed")
                Text("\(cycleDeletedCount) deleted • \(cycleKeptCount) kept")
                    .foregroundStyle(.secondary)
            }
            .padding(.top)

            Button {
                showStartOverConfirmation = true
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
        if showDailyGoalToast {
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
            .animation(.spring(), value: showDailyGoalToast)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showDailyGoalToast = false
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func startOverWithClearing() {
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

    private func loadInitialPhoto() async {
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

            if let photo = try await nextAvailablePhoto() {
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
            presentError("Failed to save your progress: \(error.localizedDescription)")
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
                resetSwipeState()
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

    private func presentError(_ message: String) {
        error = message
        isShowingError = true
        hapticsService.error()
    }

    private func resetSwipeState() {
        cardOffset = .zero
        cardRotation = 0
        swipeProgress = 0
        swipeDirection = nil
        hasTriggeredSwipeThresholdFeedback = false
    }

    private func triggerCelebrationFeedbackIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastCelebrationFeedbackDate) > celebrationFeedbackCooldown else { return }

        lastCelebrationFeedbackDate = now
        hapticsService.success()
    }

    private var normalizedSwipeProgress: CGFloat {
        min(max(swipeProgress, 0), 1)
    }

    private var decisionIconOpacity: Double {
        0.78 + (Double(normalizedSwipeProgress) * 0.22)
    }

    private var decisionIconScale: CGFloat {
        0.82 + (normalizedSwipeProgress * 0.18)
    }

    private func color(for direction: SwipeDirection?) -> Color {
        switch direction {
        case .keep:
            return .green
        case .delete:
            return .red
        case .none:
            return .clear
        }
    }

    private func symbolName(for direction: SwipeDirection) -> String {
        switch direction {
        case .keep:
            return "checkmark"
        case .delete:
            return "trash"
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
