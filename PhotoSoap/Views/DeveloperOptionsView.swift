#if DEBUG
import SwiftUI

struct DeveloperOptionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "developer.reset.title", defaultValue: "Reset Actions", table: "LocalizableShared")) {
                    Button(String(localized: "developer.reset.onboarding", defaultValue: "Reset Onboarding", table: "LocalizableShared")) {
                        UserDefaults.standard.set(false, forKey: "hasSeenQuickStartInfo")
                    }

                    Button(String(localized: "developer.reset.all", defaultValue: "Reset All Dev Overrides", table: "LocalizableShared"), role: .destructive) {
                        UserDefaults.standard.set(false, forKey: "hasSeenQuickStartInfo")
                    }
                }
            }
            .navigationTitle(String(localized: "developer.title", defaultValue: "Developer Options", table: "LocalizableShared"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done", table: "LocalizableShared")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    DeveloperOptionsView()
}
#endif
