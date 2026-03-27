import SwiftUI

struct DeleteBatchExplainerSheet: View {
    let itemCount: Int
    let isCommitting: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.orange)

                    Text(String(localized: "review.queue.explainer.title", defaultValue: "iOS Will Ask Once", table: "LocalizableReview"))
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(String(localized: "review.queue.explainer.message", defaultValue: "iOS will ask once to confirm deleting \(itemCount) photos. These photos will move to Recently Deleted.", table: "LocalizableReview"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button(action: onConfirm) {
                        HStack {
                            if isCommitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "trash.fill")
                            }

                            Text(String(localized: "review.queue.explainer.confirm", defaultValue: "Continue to Delete", table: "LocalizableReview"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isCommitting)
                    .buttonStyle(.plain)

                    Button(action: onCancel) {
                        Text(String(localized: "common.cancel", defaultValue: "Cancel", table: "LocalizableShared"))
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCommitting)
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                    }
                    .disabled(isCommitting)
                }
            }
        }
    }
}

#Preview {
    DeleteBatchExplainerSheet(
        itemCount: 12,
        isCommitting: false,
        onConfirm: {},
        onCancel: {}
    )
}