import SwiftUI
import PhotosUI
import Photos

struct DeleteQueueSheet: View {
    let items: [PendingDeletionItem]
    let onRemoveFromQueue: (PendingDeletionItem) -> Void
    let onClearQueue: () -> Void
    let onDeleteAll: () -> Void
    let onDismiss: () -> Void

    @State private var isShowingClearConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if items.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(items) { item in
                            DeleteQueueItemRow(item: item) {
                                onRemoveFromQueue(item)
                            }
                        }
                    }
                    .listStyle(.plain)

                    VStack(spacing: 12) {
                        Button(action: { isShowingClearConfirmation = true }) {
                            Text(String(localized: "review.queue.clear", defaultValue: "Clear Queue", table: "LocalizableReview"))
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 8)

                        Button(action: onDeleteAll) {
                            HStack {
                                Image(systemName: "trash.fill")

                                Text(String(localized: "review.queue.deleteInPhotos", defaultValue: "Delete in Photos", table: "LocalizableReview"))
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.red)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle(String(localized: "review.queue.title", defaultValue: "Delete Queue", table: "LocalizableReview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "LocalizableShared")) {
                        onDismiss()
                    }
                }
            }
            .alert(String(localized: "review.queue.clear.confirmation.title", defaultValue: "Clear delete queue?", table: "LocalizableReview"), isPresented: $isShowingClearConfirmation) {
                Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "LocalizableShared"), role: .cancel) {}
                Button(String(localized: "common.clear", defaultValue: "Clear", table: "LocalizableShared"), role: .destructive) {
                    onClearQueue()
                    onDismiss()
                }
            } message: {
                Text(String(localized: "review.queue.clear.confirmation.message", defaultValue: "All queued photos will be kept. Nothing will be deleted from Photos.", table: "LocalizableReview"))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text(String(localized: "review.queue.empty.title", defaultValue: "No photos in queue", table: "LocalizableReview"))
                .font(.title3)
                .fontWeight(.semibold)

            Text(String(localized: "reviewqueue.empty.description", defaultValue: "Swipe left on photos to queue them for deletion.", table: "LocalizableReview"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

struct DeleteQueueItemRow: View {
    let item: PendingDeletionItem
    let onRemove: () -> Void

    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 60, height: 60)
                    .overlay {
                        ProgressView()
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.photo.formattedDate)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(item.photo.fileSizeFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true

        let size = CGSize(width: 120, height: 120)
        PHImageManager.default().requestImage(
            for: item.photo.asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result = result {
                Task { @MainActor in
                    self.image = result
                }
            }
        }
    }
}

#Preview {
    DeleteQueueSheet(
        items: [],
        onRemoveFromQueue: { _ in },
        onClearQueue: {},
        onDeleteAll: {},
        onDismiss: {}
    )
}