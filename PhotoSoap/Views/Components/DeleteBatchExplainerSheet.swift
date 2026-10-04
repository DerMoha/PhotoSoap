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

                    Text(String(localized: "review.queue.explainer.title", defaultValue: "Confirm in iOS", table: "LocalizableReview"))
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(String(localized: "review.queue.explainer.message", defaultValue: "PhotoSoap will ask iOS to delete \(itemCount) items. Nothing is removed until you confirm the next iOS prompt. Deleted items move to Recently Deleted.", table: "LocalizableReview"))
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

                            Text(String(localized: "review.queue.explainer.confirm", defaultValue: "Continue", table: "LocalizableReview"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)

                    }
                    .disabled(isCommitting)
                    .modifier(NativeGlassButtonStyle(isProminent: true))
                    .tint(.red)
                    .controlSize(.large)

                    Button(action: onCancel) {
                        Text(String(localized: "common.cancel", defaultValue: "Cancel", table: "LocalizableShared"))
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isCommitting)
                }
                .padding(16)
            }
            .navigationTitle(String(localized: "review.queue.explainer.title", defaultValue: "Confirm in iOS", table: "LocalizableReview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                    }
                    .disabled(isCommitting)
                    .accessibilityLabel(String(localized: "common.cancel", defaultValue: "Cancel", table: "LocalizableShared"))
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
