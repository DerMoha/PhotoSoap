import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var hapticsService: HapticsService

    @ObservedObject var privacyCollectionService: PrivacyCollectionService

    @AppStorage(UserDefaultsKeys.deleteQueueEnabled) private var isDeleteQueueEnabled = true

    #if DEBUG
    @State private var isShowingDeveloperOptions = false
    #endif

    var body: some View {
        List {
            feedbackSection
            deletionSection
            privacySection
            legalSection

            #if DEBUG
            developerSection
            #endif
        }
        .navigationTitle(String(localized: "settings.title", table: "LocalizableShared"))
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .sheet(isPresented: $isShowingDeveloperOptions) {
            DeveloperOptionsView()
        }
        #endif
    }

    private var feedbackSection: some View {
        Section(String(localized: "settings.feedback", table: "LocalizableShared")) {
            Toggle(isOn: hapticsToggleBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "settings.feedback.haptics", table: "LocalizableShared"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "settings.feedback.hapticsDescription", table: "LocalizableShared"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.blue)
        }
    }

    private var deletionSection: some View {
        Section(String(localized: "settings.deletion.title", table: "LocalizableStats")) {
            Toggle(isOn: $isDeleteQueueEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "settings.deletion.useQueue", table: "LocalizableStats"))
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "settings.deletion.useQueueDescription", table: "LocalizableStats"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.blue)
        }
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

                Text(privacyCollectionService.isEnabled ? String(localized: "stats.analyticsOn", table: "LocalizableStats") : String(localized: "stats.analyticsOff", table: "LocalizableStats"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var legalSection: some View {
        Section(String(localized: "settings.legal.title", table: "LocalizableShared")) {
            NavigationLink(destination: PrivacyPolicyView()) {
                Label(String(localized: "settings.legal.privacyPolicy", table: "LocalizableShared"), systemImage: "hand.raised.fill")
            }
        }
    }

    #if DEBUG
    private var developerSection: some View {
        Section(String(localized: "settings.developer.title", defaultValue: "Developer", table: "LocalizableShared")) {
            Button(String(localized: "settings.developer.open", defaultValue: "Open Developer Options", table: "LocalizableShared")) {
                isShowingDeveloperOptions = true
            }
        }
    }
    #endif

    private var analyticsToggleBinding: Binding<Bool> {
        Binding(
            get: { privacyCollectionService.isEnabled },
            set: { privacyCollectionService.setEnabled($0) }
        )
    }

    private var hapticsToggleBinding: Binding<Bool> {
        Binding(
            get: { hapticsService.isEnabled },
            set: { hapticsService.setEnabled($0) }
        )
    }
}

private enum ReleaseLinks {
    static let privacyPolicyURL = URL(string: "https://github.com/DerMoha/PhotoSoap/blob/main/PRIVACY.md")!
    static let supportURL = URL(string: "https://github.com/DerMoha/PhotoSoap/issues")!
}

#Preview {
    NavigationStack {
        SettingsView(privacyCollectionService: PrivacyCollectionService(
            analyticsService: AnalyticsService(),
            aggregateMetricsService: AggregateMetricsService()
        ))
    }
    .environmentObject(HapticsService())
}
