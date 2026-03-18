import SwiftUI

struct RedeemCouponSheet: View {
    @Environment(\.dismiss) private var dismiss
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
                            Text("coupon.submit")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)

                    if result == .invalidCode {
                        Text("coupon.invalid.description")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("coupon.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(result == .success ? "common.done" : "common.cancel") {
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
            return "coupon.success"
        case .alreadyRedeemed:
            return "coupon.alreadyRedeemed"
        case .invalidCode:
            return "coupon.invalid"
        case .expiredCode:
            return "coupon.expired"
        case nil:
            return "Redeem a Code"
        }
    }

    private var descriptionText: String {
        switch result {
        case .success:
            return "coupon.success.description"
        case .alreadyRedeemed:
            return "coupon.alreadyRedeemed.description"
        case .invalidCode:
            return "coupon.invalid.description"
        case .expiredCode:
            return "coupon.expired.description"
        case nil:
            return "coupon.description"
        }
    }

    // MARK: - Actions

    private func redeemCode() {
        if adRemovalPurchaseService.hasCouponEntitlement {
            result = .alreadyRedeemed
            return
        }

        let validationResult = CouponService.validate(code: code)
        switch validationResult {
        case .success:
            adRemovalPurchaseService.applyCouponEntitlement(true)
            result = .success
            isAnimatingSuccess = true
        case .alreadyRedeemed:
            result = .alreadyRedeemed
        case .invalidCode:
            result = .invalidCode
        case .expiredCode:
            result = .expiredCode
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
}
