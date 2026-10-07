import SwiftUI

struct PhotoCardDisplay: View {
    let photo: Photo
    @ObservedObject var photoLibraryService: PhotoLibraryService
    var offset: CGSize = .zero
    var rotation: Double = 0
    var swipeProgress: CGFloat = 0
    var swipeDirection: SwipeDirection?

    @State private var fetchedFileSize: Int64?

    var body: some View {
        PhotoCard(
            photo: photo,
            offset: offset,
            rotation: rotation,
            swipeProgress: swipeProgress,
            swipeDirection: swipeDirection,
            fileSizeOverride: fetchedFileSize
        )
        .task(id: photo.id) {
            fetchedFileSize = nil

            let size = await photoLibraryService.fetchFileSize(for: photo)
            guard !Task.isCancelled else { return }

            if let size {
                fetchedFileSize = size
            }
        }
    }
}
