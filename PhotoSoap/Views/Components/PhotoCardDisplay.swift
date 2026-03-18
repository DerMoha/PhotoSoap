import SwiftUI
import Photos

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
            guard photo.fileSize <= 0 else {
                fetchedFileSize = photo.fileSize > 0 ? photo.fileSize : nil
                return
            }

            let size = await photoLibraryService.fetchFileSize(for: photo.asset, allowNetworkAccess: true)
            if size > 0 {
                fetchedFileSize = size
            }
        }
    }
}
