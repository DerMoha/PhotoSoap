import SwiftUI
import SwiftData
import UIKit

struct ContentView: View {
    let bootstrapErrorMessage: String?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasSeenQuickStartInfo") private var hasSeenQuickStartInfo = false
    @Query private var statsArray: [UserStats]
    @StateObject private var analyticsService: AnalyticsService
    @StateObject private var aggregateMetricsService = AggregateMetricsService()
    @StateObject private var photoLibraryService = PhotoLibraryService()
    @StateObject private var gameificationService = GameificationService()
    @StateObject private var adRemovalPurchaseService: AdRemovalPurchaseService
    @StateObject private var adCoordinator = AdCoordinator()
    @State private var selectedTab = 0
    @State private var showBootstrapAlert = false
    @State private var showQuickStartSheet = false
    @State private var hasTrackedAppOpen = false

    init(bootstrapErrorMessage: String?, analyticsService: AnalyticsService = AnalyticsService()) {
        self.bootstrapErrorMessage = bootstrapErrorMessage
        _analyticsService = StateObject(wrappedValue: analyticsService)
        _adRemovalPurchaseService = StateObject(
            wrappedValue: AdRemovalPurchaseService(analyticsService: analyticsService)
        )
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
        Group {
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
        .alert(String(localized: "recoveryMode.title"), isPresented: $showBootstrapAlert) {
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
                    Label("review.tab", systemImage: "photo.stack")
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
                        Label("stats.tab", systemImage: "chart.bar")
                    }
                    .tag(1)

                AchievementsView(stats: stats, gameificationService: gameificationService)
                    .tabItem {
                        Label("achievements.tab", systemImage: "trophy")
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

            Text("permission.title")
                .font(.title)
                .fontWeight(.bold)

            Text("permission.description")
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
                Text("permission.allow")
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

            Text("permission.denied.title")
                .font(.title)
                .fontWeight(.bold)

            Text("permission.denied.description")
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
                Text("permission.denied.openSettings")
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
            Label("recoveryMode.title", systemImage: "externaldrive.badge.exclamationmark")
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

private struct LimitedAccessBanner: View {
    let onManage: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("limitedAccess.title")
                    .font(.subheadline.weight(.semibold))
                Text("limitedAccess.description")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("limitedAccess.chooseMore") {
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
                        Text("onboarding.headsUp")
                            .font(.title2.weight(.bold))
                        Text("onboarding.subtitle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    QuickStartCard(
                        title: "onboarding.card.anonymity.title",
                        systemImage: "chart.bar.xaxis",
                        tint: .blue,
                        message: "onboarding.card.anonymity.description"
                    )

                    QuickStartCard(
                        title: "onboarding.card.banner.title",
                        systemImage: "rectangle.bottomthird.inset.filled",
                        tint: .orange,
                        message: "onboarding.card.banner.description"
                    )

                    QuickStartCard(
                        title: "onboarding.card.loyalty.title",
                        systemImage: "sparkles",
                        tint: .green,
                        message: "onboarding.card.loyalty.description"
                    )
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("onboarding.welcome")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("onboarding.gotIt") {
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
    ContentView(bootstrapErrorMessage: nil)
        .modelContainer(for: UserStats.self, inMemory: true)
}
