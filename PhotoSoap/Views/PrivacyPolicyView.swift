import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(String(localized: "privacy.updated", table: "Privacy"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                policySection("privacy.design.title", "privacy.design.body")
                policySection("privacy.library.title", "privacy.library.body")
                policySection("privacy.device.title", "privacy.device.body")
                policySection("privacy.analytics.title", "privacy.analytics.body")
                policySection("privacy.tracking.title", "privacy.tracking.body")
                policySection("privacy.contact.title", "privacy.contact.body")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle(String(localized: "privacy.title", table: "Privacy"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "privacy.done", table: "Privacy")) {
                    dismiss()
                }
            }
        }
    }

    private func policySection(_ titleKey: String.LocalizationValue, _ bodyKey: String.LocalizationValue) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: titleKey, table: "Privacy"))
                .font(.headline)
            Text(String(localized: bodyKey, table: "Privacy"))
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack { PrivacyPolicyView() }
}
