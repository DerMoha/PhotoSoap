#if DEBUG
import SwiftUI

struct DeveloperOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var adRemovalPurchaseService: AdRemovalPurchaseService
    @ObservedObject var adCoordinator: AdCoordinator

    var body: some View {
        NavigationStack {
            List {
                Section("Reset Actions") {
                    Button("Reset Onboarding") {
                        UserDefaults.standard.set(false, forKey: "hasSeenQuickStartInfo")
                    }

                    Button("Reset Coupon Redemption") {
                        adRemovalPurchaseService.applyCouponEntitlement(false)
                    }

                    Button("Reset All Dev Overrides", role: .destructive) {
                        adRemovalPurchaseService.applyCouponEntitlement(false)
                        UserDefaults.standard.set(false, forKey: "hasSeenQuickStartInfo")
                    }
                }

                Section("Current State") {
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
            .navigationTitle("Developer Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
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
