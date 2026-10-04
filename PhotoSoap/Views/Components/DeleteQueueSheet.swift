import SwiftUI
import UIKit

struct DeleteQueueSheet: View {
    let items: [PendingDeletionItem]
    @ObservedObject var photoLibraryService: PhotoLibraryService
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
                            DeleteQueueItemRow(item: item, photoLibraryService: photoLibraryService) {
                                onRemoveFromQueue(item)
                            }
                        }
                    }
                    .listStyle(.plain)

                    VStack(spacing: 12) {
                        Text(String(localized: "review.queue.sheet.note", defaultValue: "Items in your Delete List stay in your library until you confirm the iOS deletion prompt.", table: "LocalizableReview"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: { isShowingClearConfirmation = true }) {
                            Text(String(localized: "review.queue.clear", defaultValue: "Clear Delete List", table: "LocalizableReview"))
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 8)

                        Button(action: onDeleteAll) {
                            HStack {
                                Image(systemName: "trash.fill")

                                Text(String(localized: "review.queue.deleteInPhotos", defaultValue: "Delete These Items", table: "LocalizableReview"))
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
            .navigationTitle(String(localized: "review.queue.title", defaultValue: "Delete List", table: "LocalizableReview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "LocalizableShared")) {
                        onDismiss()
                    }
                }
            }
            .alert(String(localized: "review.queue.clear.confirmation.title", defaultValue: "Clear Delete List?", table: "LocalizableReview"), isPresented: $isShowingClearConfirmation) {
                Button(String(localized: "common.cancel", defaultValue: "Cancel", table: "LocalizableShared"), role: .cancel) {}
                Button(String(localized: "common.clear", defaultValue: "Clear", table: "LocalizableShared"), role: .destructive) {
                    onClearQueue()
                    onDismiss()
                }
            } message: {
                Text(String(localized: "review.queue.clear.confirmation.message", defaultValue: "All items will be removed from your Delete List and kept in your library.", table: "LocalizableReview"))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text(String(localized: "review.queue.empty.title", defaultValue: "No items in Delete List", table: "LocalizableReview"))
                .font(.title3)
                .fontWeight(.semibold)

            Text(String(localized: "reviewqueue.empty.description", defaultValue: "Swipe left on items to add them to your Delete List.", table: "LocalizableReview"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

struct DeleteQueueItemRow: View {
    let item: PendingDeletionItem
    @ObservedObject var photoLibraryService: PhotoLibraryService
    let onRemove: () -> Void

    @State private var image: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(item.photo.formattedDate)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 6) {
                    if item.photo.isVideo {
                        Label(videoDurationText, systemImage: "video.fill")
                    }

                    Text(fileSizeText)
                }
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

    private var thumbnail: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .frame(width: 60, height: 60)
                    .overlay {
                        ProgressView()
                    }
            }

            if item.photo.isVideo {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.black.opacity(0.45))
                    .clipShape(Circle())
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadImage() async {
        let size = CGSize(width: 120, height: 120)
        if let result = await photoLibraryService.fetchThumbnail(for: item.photo, targetSize: size) {
            image = result
        }
    }

    private var fileSizeText: String {
        Photo.formattedFileSizeText(item.fileSize)
            ?? item.photo.fileSizeDisplayText
            ?? Int64(0).formattedBytes
    }

    private var videoDurationText: String {
        item.photo.formattedDuration ?? String(localized: "review.preview.video", defaultValue: "Video", table: "LocalizableReview")
    }
}

#Preview {
    DeleteQueueSheet(
        items: [],
        photoLibraryService: PhotoLibraryService(),
        onRemoveFromQueue: { _ in },
        onClearQueue: {},
        onDeleteAll: {},
        onDismiss: {}
    )
}
