import SwiftUI

struct DeleteQueueTray: View {
    let queueCount: Int
    let bytesFreed: String
    let onUndo: () -> Void
    let onReviewQueue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label {
                Text(summaryText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "trash.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            trayButton(
                title: String(localized: "review.queue.undo", defaultValue: "Undo", table: "LocalizableReview"),
                systemImage: "arrow.uturn.backward"
            ) {
                onUndo()
            }

            trayButton(
                title: String(localized: "review.queue.shortTitle", defaultValue: "Queue", table: "LocalizableReview"),
                systemImage: "list.bullet"
            ) {
                onReviewQueue()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var summaryText: String {
        let countText = String(localized: "review.queue.count", defaultValue: "\(queueCount) queued", table: "LocalizableReview")
        let spaceText = String(localized: "review.queue.space", defaultValue: "\(bytesFreed) to free", table: "LocalizableReview")
        return "\(countText) - \(spaceText)"
    }

    private func trayButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack {
        Spacer()
        DeleteQueueTray(
            queueCount: 12,
            bytesFreed: "250 MB",
            onUndo: {},
            onReviewQueue: {}
        )
    }
}
