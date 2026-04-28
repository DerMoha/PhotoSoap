import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    let bootstrapErrorMessage: String?
    let migrationErrorMessage: String?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasSeenQuickStartInfo") private var hasSeenQuickStartInfo = false
    @Query private var statsArray: [UserStats]
    @EnvironmentObject private var analyticsService: AnalyticsService
    @EnvironmentObject private var aggregateMetricsService: AggregateMetricsService
    @EnvironmentObject private var photoLibraryService: PhotoLibraryService
    @EnvironmentObject private var gameificationService: GameificationService
    @EnvironmentObject private var hapticsService: HapticsService
    @State private var selectedTab: MainTab = .review
    @State private var showBootstrapAlert = false
    @State private var hasTrackedAppOpen = false
    @State private var activeStats: UserStats?

    init(bootstrapErrorMessage: String?, migrationErrorMessage: String? = nil) {
        self.bootstrapErrorMessage = bootstrapErrorMessage
        self.migrationErrorMessage = migrationErrorMessage
    }

    private var resolvedStats: UserStats? {
        activeStats ?? statsArray.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if shouldShowQuickStart {
                QuickStartInfoView()
            } else if photoLibraryService.authorizationStatus == .notDetermined {
                PermissionRequestView(
                    photoLibraryService: photoLibraryService,
                    analyticsService: analyticsService
                )
            } else if photoLibraryService.authorizationStatus == .denied ||
                      photoLibraryService.authorizationStatus == .restricted {
                PermissionDeniedView(analyticsService: analyticsService)
            } else {
                mainTabView
            }
        }
        .onAppear {
            if !hasTrackedAppOpen {
                analyticsService.track(.appOpened())
                hasTrackedAppOpen = true
            }

            initializeStats()
            refreshPhotoLibraryStateIfNeeded()
            aggregateMetricsService.registerInstallIfNeeded()
            showBootstrapAlert = bootstrapErrorMessage != nil
            analyticsService.track(.permissionStatusChanged(photoLibraryService.authorizationStatus))
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                refreshPhotoLibraryStateIfNeeded()
                aggregateMetricsService.flushPendingMetricsIfNeeded()
            case .inactive, .background:
                aggregateMetricsService.flushPendingMetricsIfNeeded()
            @unknown default:
                break
            }
        }
        .onChange(of: photoLibraryService.authorizationStatus) { _, status in
            analyticsService.track(.permissionStatusChanged(status))
        }
        .onChange(of: hasSeenQuickStartInfo) { _, _ in
            refreshPhotoLibraryStateIfNeeded()
        }
        .onChange(of: selectedTab) { _, newTab in
            analyticsService.track(.tabSelected(tabName(for: newTab)))
        }
        .alert(String(localized: "recoveryMode.title", table: "LocalizableShared"), isPresented: $showBootstrapAlert) {
            Button(String(localized: "common.ok", defaultValue: "OK", table: "LocalizableShared")) {}
        } message: {
            Text(bootstrapErrorMessage ?? "")
        }
    }

    private var shouldShowQuickStart: Bool {
        !hasSeenQuickStartInfo
    }

    @ViewBuilder
    private var mainTabView: some View {
        if let stats = resolvedStats {
            mainTabContent(stats: stats)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    initializeStats()
                }
        }
    }

    private func mainTabContent(stats: UserStats) -> some View {
        VStack(spacing: 0) {
            if let bootstrapErrorMessage {
                RecoveryModeBanner(message: bootstrapErrorMessage)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            if let migrationErrorMessage {
                MigrationWarningBanner(message: migrationErrorMessage)
                    .padding(.horizontal)
                    .padding(.top, bootstrapErrorMessage == nil ? 8 : 0)
            }

            TabView(selection: $selectedTab) {
                StatsView(
                    stats: stats,
                    photoLibraryService: photoLibraryService,
                    gameificationService: gameificationService,
                    analyticsService: analyticsService,
                    aggregateMetricsService: aggregateMetricsService
                )
                .tabItem {
                    Label(String(localized: "stats.tab", table: "LocalizableStats"), systemImage: "chart.bar")
                }
                .tag(MainTab.stats)

                PhotoReviewView(
                    photoLibraryService: photoLibraryService,
                    gameificationService: gameificationService,
                    stats: stats,
                    analyticsService: analyticsService,
                    aggregateMetricsService: aggregateMetricsService,
                    hapticsService: hapticsService
                )
                .tabItem {
                    Label(String(localized: "review.tab", table: "LocalizableReview"), systemImage: "photo.stack")
                }
                .tag(MainTab.review)

                AchievementsView(stats: stats, gameificationService: gameificationService)
                .tabItem {
                    Label(String(localized: "achievements.tab", table: "LocalizableAchievements"), systemImage: "trophy")
                }
                .tag(MainTab.achievements)
            }
        }
    }

    private func initializeStats() {
        do {
            let stats = try UserStats.fetchOrCreateSingleton(in: modelContext)
            gameificationService.ensureDailyChallengeIsSet(stats: stats)
            try modelContext.save()
            activeStats = stats
        } catch {
            print("PhotoSoap: failed to initialize user stats: \(error.localizedDescription)")
            activeStats = resolvedStats
        }
    }

    private func refreshPhotoLibraryStateIfNeeded() {
        guard !shouldShowQuickStart else { return }
        photoLibraryService.refreshLibraryAccessState()
    }

    private func tabName(for selection: MainTab) -> String {
        selection.analyticsName
    }
}

private enum MainTab: Hashable {
    case stats
    case review
    case achievements

    var analyticsName: String {
        switch self {
        case .stats:
            return "stats"
        case .review:
            return "review"
        case .achievements:
            return "achievements"
        }
    }
}

struct PermissionRequestView: View {
    @ObservedObject var photoLibraryService: PhotoLibraryService
    @ObservedObject var analyticsService: AnalyticsService

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text(String(localized: "permission.title", table: "LocalizableOnboarding"))
                .font(.title)
                .fontWeight(.bold)

            Text(String(localized: "permission.description", table: "LocalizableOnboarding"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                analyticsService.track(.permissionRequestTapped())
                Task {
                    await photoLibraryService.requestAuthorization()
                }
            } label: {
                Text(String(localized: "permission.allow", table: "LocalizableOnboarding"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }
}

struct PermissionDeniedView: View {
    @ObservedObject var analyticsService: AnalyticsService

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 80))
                .foregroundStyle(.orange)

            Text(String(localized: "permission.denied.title", table: "LocalizableOnboarding"))
                .font(.title)
                .fontWeight(.bold)

            Text(String(localized: "permission.denied.description", table: "LocalizableOnboarding"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                analyticsService.track(.settingsOpened())
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            } label: {
                Text(String(localized: "permission.denied.openSettings", table: "LocalizableOnboarding"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
    }
}

private struct RecoveryModeBanner: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(String(localized: "recoveryMode.title", table: "LocalizableShared"), systemImage: "externaldrive.badge.exclamationmark")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct MigrationWarningBanner: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(String(localized: "migrationWarning.title", table: "LocalizableShared"), systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.yellow.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct QuickStartInfoView: View {
    @AppStorage("hasSeenQuickStartInfo") private var hasSeenQuickStartInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    onboardingHero

                    SwipeTutorialDemoCard()

                    VStack(spacing: 14) {
                        QuickStartCard(
                            title: String(localized: "onboarding.card.privacy.title", table: "LocalizableOnboarding"),
                            systemImage: "lock.shield.fill",
                            tint: .blue,
                            message: String(localized: "onboarding.card.privacy.description", table: "LocalizableOnboarding")
                        )

                        QuickStartCard(
                            title: String(localized: "onboarding.card.reward.title", table: "LocalizableOnboarding"),
                            systemImage: "sparkles",
                            tint: .green,
                            message: String(localized: "onboarding.card.reward.description", table: "LocalizableOnboarding")
                        )
                    }
                }
                .padding(20)
            }
            .background(backgroundGradient)
            .safeAreaInset(edge: .bottom) {
                Button(String(localized: "onboarding.cta", table: "LocalizableOnboarding")) {
                    hasSeenQuickStartInfo = true
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.10),
                Color(.systemGroupedBackground),
                Color.green.opacity(0.06)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var onboardingHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "onboarding.hero.eyebrow", table: "LocalizableOnboarding"))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.8)
                .foregroundStyle(.blue)

            Text(String(localized: "onboarding.hero.title", table: "LocalizableOnboarding"))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))

            Text(String(localized: "onboarding.hero.subtitle", table: "LocalizableOnboarding"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        }
    }
}

private struct QuickStartCard: View {
    let title: String
    let systemImage: String
    let tint: Color
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 38, height: 38)

                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct SwipeTutorialDemoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "onboarding.demo.title", table: "LocalizableOnboarding"))
                    .font(.headline)

                Text(String(localized: "onboarding.demo.description", table: "LocalizableOnboarding"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.red.opacity(0.08))
                    .rotationEffect(.degrees(-8))
                    .offset(x: -26, y: 14)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.green.opacity(0.08))
                    .rotationEffect(.degrees(8))
                    .offset(x: 26, y: 14)

                mockPhotoCard
            }
            .frame(height: 310)

            HStack(spacing: 12) {
                SwipeHintBadge(
                    direction: String(localized: "onboarding.demo.swipeLeft", table: "LocalizableOnboarding"),
                    outcome: String(localized: "onboarding.demo.delete", table: "LocalizableOnboarding"),
                    systemImage: "trash.fill",
                    tint: .red
                )

                SwipeHintBadge(
                    direction: String(localized: "onboarding.demo.swipeRight", table: "LocalizableOnboarding"),
                    outcome: String(localized: "onboarding.demo.keep", table: "LocalizableOnboarding"),
                    systemImage: "checkmark",
                    tint: .green
                )
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.32), lineWidth: 1)
        }
    }

    private var mockPhotoCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [
                        Color.indigo.opacity(0.88),
                        Color.blue.opacity(0.72),
                        Color.cyan.opacity(0.62)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 12) {
                    Spacer()

                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(.white)

                    HStack(spacing: 8) {
                        Capsule()
                            .fill(Color.white.opacity(0.86))
                            .frame(width: 62, height: 8)

                        Capsule()
                            .fill(Color.white.opacity(0.40))
                            .frame(width: 42, height: 8)
                    }
                    .padding(.bottom, 26)
                }

                HStack {
                    DemoOverlayBadge(
                        title: String(localized: "onboarding.demo.delete", table: "LocalizableOnboarding"),
                        systemImage: "trash.fill",
                        tint: .red
                    )

                    Spacer()

                    DemoOverlayBadge(
                        title: String(localized: "onboarding.demo.keep", table: "LocalizableOnboarding"),
                        systemImage: "checkmark",
                        tint: .green
                    )
                }
                .padding(16)
            }
            .frame(height: 228)

            HStack(spacing: 12) {
                Label("Jun 24", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("3.2 MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("4Kx3K")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 12)
    }
}

private struct DemoOverlayBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }
}

private struct SwipeHintBadge: View {
    let direction: String
    let outcome: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 34, height: 34)

                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(direction)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(outcome)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    let container = try! ModelContainer(for: UserStats.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    context.insert(UserStats())

    return ContentView(bootstrapErrorMessage: nil)
        .modelContainer(container)
        .environmentObject(AnalyticsService())
        .environmentObject(AggregateMetricsService())
        .environmentObject(PhotoLibraryService())
        .environmentObject(GameificationService())
}
