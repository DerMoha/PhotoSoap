#if DEBUG
import SwiftUI

struct DeveloperOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var adRemovalPurchaseService: AdRemovalPurchaseService
    @ObservedObject var adCoordinator: AdCoordinator

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "developer.reset.title", defaultValue: "Reset Actions", table: "LocalizableShared")) {
                    Button(String(localized: "developer.reset.onboarding", defaultValue: "Reset Onboarding", table: "LocalizableShared")) {
                        UserDefaults.standard.set(false, forKey: "hasSeenQuickStartInfo")
                    }

                    Button(String(localized: "developer.reset.coupon", defaultValue: "Reset Coupon Redemption", table: "LocalizableShared")) {
                        adRemovalPurchaseService.applyCouponEntitlement(false)
                    }

                    Button(String(localized: "developer.reset.all", defaultValue: "Reset All Dev Overrides", table: "LocalizableShared"), role: .destructive) {
                        adRemovalPurchaseService.applyCouponEntitlement(false)
                        UserDefaults.standard.set(false, forKey: "hasSeenQuickStartInfo")
                    }
                }

                Section(String(localized: "developer.state.title", defaultValue: "Current State", table: "LocalizableShared")) {
                    StateRow(label: "hasPurchasedEntitlement", value: adRemovalPurchaseService.hasPurchasedEntitlement)
                    StateRow(label: "hasEarnedEntitlement", value: adRemovalPurchaseService.hasEarnedEntitlement)
                    StateRow(label: "hasCouponEntitlement", value: adRemovalPurchaseService.hasCouponEntitlement)
                    StateRow(label: "hasAdRemovalEntitlement", value: adRemovalPurchaseService.hasAdRemovalEntitlement)
                    StateRow(label: "adsEnabled", value: adCoordinator.adsEnabled)

                    HStack {
                        Text("totalDeleted")
                            .font(.caption.monospaced())
                        Spacer()
                        Text("\(adRemovalPurchaseService.currentDeletedCount)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("unlockSource")
                            .font(.caption.monospaced())
                        Spacer()
                        Text(String(describing: adRemovalPurchaseService.unlockSource))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
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

private struct StateRow: View {
    let label: String
    let value: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.caption.monospaced())
            Spacer()
            Image(systemName: value ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(value ? .green : .secondary)
        }
    }
}

#Preview {
    DeveloperOptionsView(
        adRemovalPurchaseService: AdRemovalPurchaseService(
            analyticsService: AnalyticsService(),
            shouldObserveTransactions: false
        ),
        adCoordinator: AdCoordinator()
    )
}
#endif
