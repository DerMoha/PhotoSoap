import SwiftUI

struct RedeemCouponSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var hapticsService: HapticsService
    @ObservedObject var adRemovalPurchaseService: AdRemovalPurchaseService

    @State private var code = ""
    @State private var result: CouponRedemptionResult?
    @State private var isAnimatingSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 48))
                    .foregroundStyle(iconColor)
                    .symbolEffect(.bounce, value: isAnimatingSuccess)

                VStack(spacing: 8) {
                    Text(titleText)
                        .font(.title2.weight(.bold))

                    Text(descriptionText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if result != .success {
                    VStack(spacing: 12) {
                        TextField("coupon.enter", text: $code)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit { redeemCode() }

                        Button {
                            redeemCode()
                        } label: {
                            Text(String(localized: "coupon.submit", table: "LocalizableCoupon"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)

                    if result == .invalidCode {
                        Text(String(localized: "coupon.invalid.description", table: "LocalizableCoupon"))
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle(String(localized: "coupon.title", table: "LocalizableCoupon"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(result == .success ? String(localized: "common.done", table: "LocalizableShared") : String(localized: "common.cancel", table: "LocalizableShared")) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Display Helpers

    private var iconName: String {
        switch result {
        case .success, .alreadyRedeemed:
            return "checkmark.seal.fill"
        case .invalidCode, .expiredCode:
            return "xmark.circle"
        case nil:
            return "ticket"
        }
    }

    private var iconColor: Color {
        switch result {
        case .success, .alreadyRedeemed:
            return .green
        case .invalidCode, .expiredCode:
            return .red
        case nil:
            return .blue
        }
    }

    private var titleText: String {
        switch result {
        case .success:
            return String(localized: "coupon.success", table: "LocalizableCoupon")
        case .alreadyRedeemed:
            return String(localized: "coupon.alreadyRedeemed", table: "LocalizableCoupon")
        case .invalidCode:
            return String(localized: "coupon.invalid", table: "LocalizableCoupon")
        case .expiredCode:
            return String(localized: "coupon.expired", table: "LocalizableCoupon")
        case nil:
            return String(localized: "coupon.redeemTitle", table: "LocalizableCoupon")
        }
    }

    private var descriptionText: String {
        switch result {
        case .success:
            return String(localized: "coupon.success.description", table: "LocalizableCoupon")
        case .alreadyRedeemed:
            return String(localized: "coupon.alreadyRedeemed.description", table: "LocalizableCoupon")
        case .invalidCode:
            return String(localized: "coupon.invalid.description", table: "LocalizableCoupon")
        case .expiredCode:
            return String(localized: "coupon.expired.description", table: "LocalizableCoupon")
        case nil:
            return String(localized: "coupon.description", table: "LocalizableCoupon")
        }
    }

    // MARK: - Actions

    private func redeemCode() {
        if adRemovalPurchaseService.hasCouponEntitlement {
            result = .alreadyRedeemed
            hapticsService.warning()
            return
        }

        let validationResult = CouponService.validate(code: code)
        switch validationResult {
        case .success:
            adRemovalPurchaseService.applyCouponEntitlement(true)
            result = .success
            isAnimatingSuccess = true
            hapticsService.success()
        case .alreadyRedeemed:
            result = .alreadyRedeemed
            hapticsService.warning()
        case .invalidCode:
            result = .invalidCode
            hapticsService.error()
        case .expiredCode:
            result = .expiredCode
            hapticsService.error()
        }
    }
}

#Preview {
    RedeemCouponSheet(
        adRemovalPurchaseService: AdRemovalPurchaseService(
            analyticsService: AnalyticsService(),
            shouldObserveTransactions: false
        )
    )
    .environmentObject(HapticsService())
}
