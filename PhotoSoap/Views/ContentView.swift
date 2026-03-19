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
    @EnvironmentObject private var adRemovalPurchaseService: AdRemovalPurchaseService
    @EnvironmentObject private var adCoordinator: AdCoordinator
    @State private var selectedTab = 0
    @State private var showBootstrapAlert = false
    @State private var showQuickStartSheet = false
    @State private var hasTrackedAppOpen = false

    init(bootstrapErrorMessage: String?, migrationErrorMessage: String? = nil) {
        self.bootstrapErrorMessage = bootstrapErrorMessage
        self.migrationErrorMessage = migrationErrorMessage
    }

    private var stats: UserStats {
        if let existingStats = statsArray.first {
            return existingStats
        } else {
            let newStats = UserStats()
            modelContext.insert(newStats)
            return newStats
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if photoLibraryService.authorizationStatus == .notDetermined {
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
            photoLibraryService.refreshLibraryAccessState()
            aggregateMetricsService.registerInstallIfNeeded()
            adRemovalPurchaseService.refreshEarnedEntitlement(stats: stats)
            adCoordinator.updateEntitlement(hasAdRemovalEntitlement: adRemovalPurchaseService.hasAdRemovalEntitlement)
            showBootstrapAlert = bootstrapErrorMessage != nil
            updateQuickStartPresentation()
            analyticsService.track(.permissionStatusChanged(photoLibraryService.authorizationStatus))
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                photoLibraryService.refreshLibraryAccessState()
                aggregateMetricsService.flushPendingMetricsIfNeeded()
                adRemovalPurchaseService.refreshEarnedEntitlement(stats: stats)
                adCoordinator.updateEntitlement(hasAdRemovalEntitlement: adRemovalPurchaseService.hasAdRemovalEntitlement)
            case .inactive, .background:
                aggregateMetricsService.flushPendingMetricsIfNeeded()
            @unknown default:
                break
            }
        }
        .onChange(of: stats.totalDeleted) { _, _ in
            adRemovalPurchaseService.refreshEarnedEntitlement(stats: stats)
            adCoordinator.updateEntitlement(hasAdRemovalEntitlement: adRemovalPurchaseService.hasAdRemovalEntitlement)
        }
        .onChange(of: adRemovalPurchaseService.hasAdRemovalEntitlement) { _, hasEntitlement in
            adCoordinator.updateEntitlement(hasAdRemovalEntitlement: hasEntitlement)
        }
        .onChange(of: photoLibraryService.authorizationStatus) { _, status in
            updateQuickStartPresentation(for: status)
            analyticsService.track(.permissionStatusChanged(status))
        }
        .onChange(of: selectedTab) { _, newTab in
            analyticsService.track(.tabSelected(tabName(for: newTab)))
        }
        .alert(String(localized: "recoveryMode.title", table: "LocalizableShared"), isPresented: $showBootstrapAlert) {
            Button("OK") {}
        } message: {
            Text(bootstrapErrorMessage ?? "")
        }
        .sheet(isPresented: $showQuickStartSheet) {
            QuickStartInfoSheet()
                .presentationDetents([.medium, .large])
        }
    }

    private var mainTabView: some View {
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

            if photoLibraryService.authorizationStatus == .limited {
                LimitedAccessBanner {
                    analyticsService.track(.limitedLibraryPickerOpened())
                    photoLibraryService.presentLimitedLibraryPicker()
                }
                .padding(.horizontal)
                .padding(.top, bootstrapErrorMessage == nil ? 8 : 0)
            }

            TabView(selection: $selectedTab) {
                PhotoReviewView(
                    photoLibraryService: photoLibraryService,
                    gameificationService: gameificationService,
                    stats: stats,
                    analyticsService: analyticsService,
                    aggregateMetricsService: aggregateMetricsService,
                    adCoordinator: adCoordinator
                )
                .tabItem {
                    Label(String(localized: "review.tab", table: "LocalizableReview"), systemImage: "photo.stack")
                }
                .tag(0)

                StatsView(
                    stats: stats,
                    gameificationService: gameificationService,
                    adRemovalPurchaseService: adRemovalPurchaseService,
                    adCoordinator: adCoordinator,
                    analyticsService: analyticsService
                )
                    .tabItem {
                        Label(String(localized: "stats.tab", table: "LocalizableStats"), systemImage: "chart.bar")
                    }
                    .tag(1)

                AchievementsView(stats: stats, gameificationService: gameificationService)
                    .tabItem {
                        Label(String(localized: "achievements.tab", table: "LocalizableAchievements"), systemImage: "trophy")
                    }
                    .tag(2)
            }
        }
    }

    private func initializeStats() {
        gameificationService.updateDailyStreak(stats: stats, context: modelContext)
        gameificationService.ensureDailyChallengeIsSet(stats: stats)
    }

    private func tabName(for selection: Int) -> String {
        switch selection {
        case 0:
            return "review"
        case 1:
            return "stats"
        case 2:
            return "achievements"
        default:
            return "unknown"
        }
    }

    private func updateQuickStartPresentation(for status: PhotoLibraryAuthorizationStatus? = nil) {
        let currentStatus = status ?? photoLibraryService.authorizationStatus
        let canShowMainExperience = currentStatus == .authorized || currentStatus == .limited
        showQuickStartSheet = canShowMainExperience && !hasSeenQuickStartInfo
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

private struct LimitedAccessBanner: View {
    let onManage: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "limitedAccess.title", table: "LocalizableShared"))
                    .font(.subheadline.weight(.semibold))
                Text(String(localized: "limitedAccess.description", table: "LocalizableShared"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(String(localized: "limitedAccess.chooseMore", table: "LocalizableShared")) {
                onManage()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct QuickStartInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasSeenQuickStartInfo") private var hasSeenQuickStartInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "onboarding.headsUp", table: "LocalizableOnboarding"))
                            .font(.title2.weight(.bold))
                        Text(String(localized: "onboarding.subtitle", table: "LocalizableOnboarding"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    QuickStartCard(
                        title: String(localized: "onboarding.card.anonymity.title", table: "LocalizableOnboarding"),
                        systemImage: "chart.bar.xaxis",
                        tint: .blue,
                        message: String(localized: "onboarding.card.anonymity.description", table: "LocalizableOnboarding")
                    )

                    QuickStartCard(
                        title: String(localized: "onboarding.card.banner.title", table: "LocalizableOnboarding"),
                        systemImage: "rectangle.bottomthird.inset.filled",
                        tint: .orange,
                        message: String(localized: "onboarding.card.banner.description", table: "LocalizableOnboarding")
                    )

                    QuickStartCard(
                        title: String(localized: "onboarding.card.loyalty.title", table: "LocalizableOnboarding"),
                        systemImage: "sparkles",
                        tint: .green,
                        message: String(localized: "onboarding.card.loyalty.description", table: "LocalizableOnboarding")
                    )
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "onboarding.welcome", table: "LocalizableOnboarding"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(String(localized: "onboarding.gotIt", table: "LocalizableOnboarding")) {
                    hasSeenQuickStartInfo = true
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
        }
        .interactiveDismissDisabled()
    }
}

private struct QuickStartCard: View {
    let title: String
    let systemImage: String
    let tint: Color
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
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
        .environmentObject(AdRemovalPurchaseService(analyticsService: AnalyticsService(), shouldObserveTransactions: false))
        .environmentObject(AdCoordinator())
}
