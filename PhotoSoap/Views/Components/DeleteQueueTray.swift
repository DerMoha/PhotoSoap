import SwiftUI

struct DeleteQueueTray: View {
    let queueCount: Int
    let bytesFreed: String
    let onUndo: () -> Void
    let onReviewQueue: () -> Void
    let onDeleteAll: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "review.queue.count", defaultValue: "\(queueCount) queued", table: "LocalizableReview"))
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(String(localized: "review.queue.space", defaultValue: "\(bytesFreed) to free", table: "LocalizableReview"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onUndo) {
                    Text(String(localized: "review.queue.undo", defaultValue: "Undo", table: "LocalizableReview"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: onReviewQueue) {
                    Text(String(localized: "review.queue.review", defaultValue: "Review", table: "LocalizableReview"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Button(action: onDeleteAll) {
                HStack {
                    Image(systemName: "trash.fill")

                    Text(String(localized: "review.queue.deleteAll", defaultValue: "Delete All", table: "LocalizableReview"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.red)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }
}

#Preview {
    VStack {
        Spacer()
        DeleteQueueTray(
            queueCount: 12,
            bytesFreed: "250 MB",
            onUndo: {},
            onReviewQueue: {},
            onDeleteAll: {}
        )
    }
}