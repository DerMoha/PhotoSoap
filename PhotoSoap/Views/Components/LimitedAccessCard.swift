import SwiftUI

struct LimitedAccessCard: View {
    enum Style {
        case stats
        case completion
    }

    let title: String
    let message: String
    let buttonTitle: String
    let style: Style
    let onManage: () -> Void

    var body: some View {
        Group {
            switch style {
            case .stats:
                statsCard
            case .completion:
                completionCard
            }
        }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                iconBadge

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            actionButton(controlSize: .small)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(statsBackground)
    }

    private var completionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                iconBadge

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            actionButton(controlSize: .regular)
        }
        .padding(18)
        .background(completionBackground)
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private var iconBadge: some View {
        Image(systemName: "photo.stack.fill")
            .font(.headline)
            .foregroundStyle(.blue)
            .frame(width: 36, height: 36)
            .background(Color.blue.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statsBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.blue.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.blue.opacity(0.08), lineWidth: 1)
            }
    }

    private var completionBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.blue.opacity(0.14), lineWidth: 1)
            }
    }

    private func actionButton(controlSize: ControlSize) -> some View {
        Button(buttonTitle) {
            onManage()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(controlSize)
    }
}

#Preview {
    VStack(spacing: 20) {
        LimitedAccessCard(
            title: "Reviewing selected photos only",
            message: "PhotoSoap can review only the photos you selected. You can add more anytime. Videos you choose will not appear.",
            buttonTitle: "Add More Photos",
            style: .stats,
            onManage: {}
        )

        LimitedAccessCard(
            title: "Add More Photos to Review",
            message: "PhotoSoap can review only the photos you selected. You can add more photos to keep going. Videos you choose will not appear.",
            buttonTitle: "Add More Photos",
            style: .completion,
            onManage: {}
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
