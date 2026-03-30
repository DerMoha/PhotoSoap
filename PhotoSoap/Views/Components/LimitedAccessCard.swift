import SwiftUI
import UIKit

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
        HStack(alignment: .top, spacing: 14) {
            iconBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            actionButton(controlSize: .small)
        }
        .padding(16)
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
            .fill(Color(uiColor: UIColor.secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.blue.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.blue.opacity(0.10), lineWidth: 1)
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
            message: "Choose more photos to expand what you can review, or manage access in Settings later.",
            buttonTitle: "Choose More",
            style: .stats,
            onManage: {}
        )

        LimitedAccessCard(
            title: "You finished your selected photos",
            message: "Add more photos from your library selection to keep reviewing.",
            buttonTitle: "Choose More",
            style: .completion,
            onManage: {}
        )
    }
    .padding()
    .background(Color(uiColor: UIColor.systemGroupedBackground))
}
