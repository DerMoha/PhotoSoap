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
                        TextField("Enter your code", text: $code)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit { redeemCode() }

                        Button {
                            redeemCode()
                        } label: {
                            Text("Redeem")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)

                    if result == .invalidCode {
                        Text("That code is not recognized. Please check and try again.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Redeem Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(result == .success ? "Done" : "Cancel") {
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
        case .invalidCode:
            return "xmark.circle"
        case nil:
            return "ticket"
        }
    }

    private var iconColor: Color {
        switch result {
        case .success, .alreadyRedeemed:
            return .green
        case .invalidCode:
            return .red
        case nil:
            return .blue
        }
    }

    private var titleText: String {
        switch result {
        case .success:
            return "Code Redeemed"
        case .alreadyRedeemed:
            return "Already Redeemed"
        case .invalidCode:
            return "Invalid Code"
        case nil:
            return "Redeem a Code"
        }
    }

    private var descriptionText: String {
        switch result {
        case .success:
            return "Ad-free access has been activated. Thank you for testing PhotoSoap!"
        case .alreadyRedeemed:
            return "You have already redeemed a code. Ad-free access is active."
        case .invalidCode:
            return "The code you entered is not valid."
        case nil:
            return "Enter a coupon code to unlock ad-free access."
        }
    }

    // MARK: - Actions

    private func redeemCode() {
        if adRemovalPurchaseService.hasCouponEntitlement {
            result = .alreadyRedeemed
            return
        }

        if CouponService.validate(code: code) {
            adRemovalPurchaseService.applyCouponEntitlement(true)
            result = .success
            isAnimatingSuccess = true
        } else {
            result = .invalidCode
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
