import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var hapticsService: HapticsService
    @Environment(\.openURL) private var openURL

    @ObservedObject var privacyCollectionService: PrivacyCollectionService

    @AppStorage(UserDefaultsKeys.deleteQueueEnabled) private var isDeleteQueueEnabled = true

    #if DEBUG
    @State private var isShowingDeveloperOptions = false
    #endif

    var body: some View {
        List {
            feedbackSection
            hapticsSection
            deletionSection
            privacySection
            legalSection

            #if DEBUG
            developerSection
            #endif

            appInfoSection
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
        Section(String(localized: "settings.feedback.title", table: "LocalizableShared")) {
            Button {
                privacyCollectionService.track(.feedbackOpened(source: "github"))
                openURL(ReleaseLinks.issuesURL)
            } label: {
                Label(String(localized: "settings.feedback.reportIssue", table: "LocalizableShared"), systemImage: "exclamationmark.bubble.fill")
            }
            .tint(.blue)

            Button {
                privacyCollectionService.track(.feedbackOpened(source: "email"))
                if let url = ReleaseLinks.feedbackMailtoURL {
                    openURL(url)
                }
            } label: {
                Label(String(localized: "settings.feedback.sendFeedback", table: "LocalizableShared"), systemImage: "envelope.fill")
            }
            .tint(.blue)
        }
    }

    private var hapticsSection: some View {
        Section(String(localized: "settings.haptics", table: "LocalizableShared")) {
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

    private var appInfoSection: some View {
        Section("PhotoSoap") {
            LabeledContent(String(localized: "settings.app.version", defaultValue: "Version", table: "LocalizableShared")) {
                Text(ReleaseLinks.versionDisplay)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
        }
    }

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
    static let issuesURL = URL(string: "https://github.com/DerMoha/PhotoSoap/issues/new")!
    static let feedbackEmail = "photosoap@brokenmoha.de"

    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }

    static var buildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
    }

    static var versionDisplay: String {
        String(
            format: String(localized: "settings.app.versionAndBuild", defaultValue: "%@ (Build %@)", table: "LocalizableShared"),
            appVersion,
            buildNumber
        )
    }

    static var feedbackMailtoURL: URL? {
        let systemVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let subject = "PhotoSoap Feedback"
        let body = "App Version \(appVersion) (\(buildNumber)) — \(systemVersion)\n\n"

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
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
