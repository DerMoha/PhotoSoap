import SwiftUI
import SwiftData

struct PhotoReviewView: View {
    @ObservedObject var photoLibraryService: PhotoLibraryService
    @ObservedObject var gameificationService: GameificationService
    @Bindable var stats: UserStats

    @State private var currentPhoto: Photo?
    @State private var nextPhoto: Photo?
    @State private var isLoading = false
    @State private var error: String?
    @State private var showError = false
    @State private var noMorePhotos = false
    @State private var cardOffset: CGSize = .zero
    @State private var cardRotation: Double = 0
    @State private var showKeepOverlay = false
    @State private var showDeleteOverlay = false
    @State private var cachedExcludedIDs: Set<String> = []
    @State private var isProcessingAction = false  // Prevents concurrent button presses

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
                        photoCardSection(photo: photo)
                            .padding(.top, 8)
                            .padding(.horizontal, 12)
                    } else {
                        Spacer()
                        emptyStateView
                        Spacer()
                    }

                    // Action buttons with proper spacing from tab bar
                    if currentPhoto != nil && !isLoading {
                        ActionButtons(
                            onKeep: {
                                Task {
                                    await keepPhoto()
                                }
                            },
                            onDelete: {
                                Task {
                                    await deletePhoto()
                                }
                            }
                        )
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                    }
                }

                achievementBanner
                streakCelebration
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Clean my Photos!  ")
                        .font(.headline)
                }
            }
            .onAppear {
                Task {
                    await loadInitialPhoto()
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(error ?? "An unknown error occurred")
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
            challengeTitle: challenge.title
        )
    }

    private func photoCardSection(photo: Photo) -> some View {
        PhotoCard(
            photo: photo,
            offset: cardOffset,
            rotation: cardRotation,
            showKeepOverlay: showKeepOverlay,
            showDeleteOverlay: showDeleteOverlay
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

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading photos...")
                .foregroundStyle(.secondary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No photos to review")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Your photo library appears to be empty")
                .foregroundStyle(.secondary)
        }
    }

    private var noMorePhotosView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("All Done!")
                .font(.title)
                .fontWeight(.bold)

            Text("You've reviewed all your photos!")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("\(stats.totalReviewed) photos reviewed")
                Text("\(stats.totalDeleted) deleted • \(stats.totalKept) kept")
                    .foregroundStyle(.secondary)
            }
            .padding(.top)

            Button {
                refreshLibrary()
            } label: {
                Label("Start Over", systemImage: "arrow.counterclockwise")
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
                        Text("Achievement Unlocked!")
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

                    Text("\(milestone) Streak!")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Keep it up!")
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

        // Cache excluded IDs once per load operation
        cachedExcludedIDs = Set(stats.reviewedPhotoIDs)

        do {
            if let photo = try await photoLibraryService.getNextPhoto(excludingIDs: cachedExcludedIDs) {
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
        if let photo = try? await photoLibraryService.getNextPhoto(excludingIDs: cachedExcludedIDs) {
            nextPhoto = photo
        }
    }

    private func keepPhoto() async {
        guard !isProcessingAction else { return }
        guard let photo = currentPhoto else { return }
        
        isProcessingAction = true
        defer { isProcessingAction = false }

        let challengeType = DailyChallengeType(rawValue: stats.dailyChallengeType) ?? .review

        stats.markPhotoReviewed(photo.id)
        cachedExcludedIDs.insert(photo.id)
        gameificationService.processPhotoReview(
            action: .keep,
            fileSize: 0,
            stats: stats,
            challengeType: challengeType
        )

        await advanceToNextPhoto()
    }

    private func deletePhoto() async {
        guard !isProcessingAction else { return }
        guard let photo = currentPhoto else { return }
        
        isProcessingAction = true
        defer { isProcessingAction = false }

        do {
            try await photoLibraryService.deletePhoto(photo)

            let challengeType = DailyChallengeType(rawValue: stats.dailyChallengeType) ?? .review

            stats.markPhotoReviewed(photo.id)
            cachedExcludedIDs.insert(photo.id)
            gameificationService.processPhotoReview(
                action: .delete,
                fileSize: photo.fileSize,
                stats: stats,
                challengeType: challengeType
            )

            await advanceToNextPhoto()
        } catch {
            self.error = "Failed to delete photo: \(error.localizedDescription)"
            showError = true
        }
    }

    private func advanceToNextPhoto() async {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            cardOffset = .zero
            cardRotation = 0
            showKeepOverlay = false
            showDeleteOverlay = false
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
        if let photo = try? await photoLibraryService.getNextPhoto(excludingIDs: cachedExcludedIDs) {
            currentPhoto = photo
            await preloadNextPhoto()
        } else {
            currentPhoto = nil
            noMorePhotos = true
        }
    }

    private func handleDragGesture(_ value: DragGesture.Value) {
        guard !isProcessingAction else { return }
        
        cardOffset = value.translation
        cardRotation = Double(value.translation.width / 20)

        let threshold: CGFloat = 50
        showKeepOverlay = value.translation.width > threshold
        showDeleteOverlay = value.translation.width < -threshold
    }

    private func handleDragEnd(_ value: DragGesture.Value) async {
        guard !isProcessingAction else { return }
        
        let threshold: CGFloat = 100

        if value.translation.width > threshold {
            withAnimation(.easeOut(duration: 0.3)) {
                cardOffset = CGSize(width: 500, height: 0)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            await keepPhoto()
        } else if value.translation.width < -threshold {
            withAnimation(.easeOut(duration: 0.3)) {
                cardOffset = CGSize(width: -500, height: 0)
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            await deletePhoto()
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                cardOffset = .zero
                cardRotation = 0
                showKeepOverlay = false
                showDeleteOverlay = false
            }
        }
    }

    private func refreshLibrary() {
        cachedExcludedIDs = Set(stats.reviewedPhotoIDs)
        photoLibraryService.refreshLibrary(excludingIDs: cachedExcludedIDs)
        noMorePhotos = false

        Task {
            await loadInitialPhoto()
        }
    }
}

#Preview {
    PhotoReviewView(
        photoLibraryService: PhotoLibraryService(),
        gameificationService: GameificationService(),
        stats: UserStats()
    )
}
