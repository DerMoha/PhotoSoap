import SwiftUI
import UIKit

struct PhotoPreviewSheet: View {
    let photo: Photo
    @ObservedObject var photoLibraryService: PhotoLibraryService

    @Environment(\.dismiss) private var dismiss

    @State private var previewImage: UIImage?
    @State private var zoomScale: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Color.black
                    .ignoresSafeArea()

                if let previewImage {
                    ZoomablePhotoView(
                        image: previewImage,
                        zoomScale: $zoomScale
                    )
                    .ignoresSafeArea()
                } else {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
                        .padding(12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "common.done", table: "LocalizableShared"))
                .padding(.top, geometry.safeAreaInsets.top + 4)
                .padding(.trailing, 8)
            }
        }
        .task(id: photo.id) {
            await loadPreviewImage()
        }
    }

    private func loadPreviewImage() async {
        previewImage = photo.image

        if let highResolutionImage = await photoLibraryService.fetchHighResolutionPreviewImage(for: photo.asset) {
            previewImage = highResolutionImage
        }
    }
}
