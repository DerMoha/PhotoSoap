import SwiftUI

struct SettingsView: View {
    @ObservedObject var analyticsService: AnalyticsService
    @ObservedObject var adRemovalPurchaseService: AdRemovalPurchaseService
    @ObservedObject var adCoordinator: AdCoordinator

    #if DEBUG
    @State private var isShowingDeveloperOptions = false
    #endif

    var body: some View {
        List {
            privacySection

            #if DEBUG
            developerSection
            #endif
        }
        .navigationTitle(String(localized: "settings.title", table: "LocalizableShared"))
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .sheet(isPresented: $isShowingDeveloperOptions) {
            DeveloperOptionsView(
                adRemovalPurchaseService: adRemovalPurchaseService,
                adCoordinator: adCoordinator
            )
        }
        #endif
    }

    private var privacySection: some View {
        Section(String(localized: "stats.privacy", table: "LocalizableStats")) {
            Toggle(isOn: analyticsToggleBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "stats.privacy.shareAnalytics", table: "LocalizableStats"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "stats.privacy.analyticsDescription", table: "LocalizableStats"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.blue)

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "stats.privacy.communityTotals", table: "LocalizableStats"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(analyticsService.isEnabled ? String(localized: "stats.analyticsOn", table: "LocalizableStats") : String(localized: "stats.analyticsOff", table: "LocalizableStats"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    #if DEBUG
    private var developerSection: some View {
        Section("Developer") {
            Button("Open Developer Options") {
                isShowingDeveloperOptions = true
            }
        }
    }
    #endif

    private var analyticsToggleBinding: Binding<Bool> {
        Binding(
            get: { analyticsService.isEnabled },
            set: { analyticsService.setEnabled($0) }
        )
    }
}

#Preview {
    NavigationStack {
        SettingsView(
            analyticsService: AnalyticsService(),
            adRemovalPurchaseService: AdRemovalPurchaseService(
                analyticsService: AnalyticsService(),
                shouldObserveTransactions: false
            ),
            adCoordinator: AdCoordinator()
        )
    }
}
