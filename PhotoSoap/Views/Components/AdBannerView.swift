import SwiftUI

struct AdBannerSlot: View {
    static let reservedHeight: CGFloat = 64
    @AppStorage("showAds") private var showAds = true

    var body: some View {
        if showAds {
            VStack(spacing: 0) {
                Divider()

                AdBannerView()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .background(Color.secondary.opacity(0.08))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct AdBannerView: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Ad")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .clipShape(Capsule())

            Text("Banner placeholder")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Ad banner placeholder")
    }
}

#Preview {
    AdBannerView()
        .padding()
        .background(Color.secondary.opacity(0.08))
}
