import SwiftUI
import UIKit

struct PhotoPreviewSheet: View {
    private enum DismissGesture {
        static let distanceThreshold: CGFloat = 140
        static let velocityThreshold: CGFloat = 1_200
        static let progressRange: CGFloat = 240
    }

    @AppStorage(UserDefaultsKeys.hasSeenPhotoZoomHint) private var hasSeenPhotoZoomHint = false

    let photo: Photo
    @ObservedObject var photoLibraryService: PhotoLibraryService

    @Environment(\.dismiss) private var dismiss

    @State private var isContentVisible = false
    @State private var isDismissing = false
    @State private var previewImage: UIImage?
    @State private var zoomScale: CGFloat = 1
    @State private var showZoomHint = false
    @State private var dismissDragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Color.black
                    .opacity(backdropOpacity)
                    .ignoresSafeArea()

                if let previewImage {
                    ZoomablePhotoView(
                        image: previewImage,
                        zoomScale: $zoomScale,
                        onDismissDragChanged: handleDismissDragChanged,
                        onDismissDragEnded: { translation, velocity in
                            handleDismissDragEnded(
                                translation: translation,
                                velocity: velocity,
                                containerHeight: geometry.size.height
                            )
                        }
                    )
                    .scaleEffect(contentScale)
                    .opacity(contentOpacity)
                    .offset(y: dismissDragOffset)
                    .ignoresSafeArea()
                } else {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(isContentVisible ? max(1.2 - (dismissDragProgress * 0.08), 1.08) : 1.08)
                        .opacity(contentOpacity)
                        .offset(y: dismissDragOffset)
                }

                if showZoomHint {
                    zoomHintChip
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 28)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Button {
                    dismissPreview()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
                        .padding(12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "common.done", table: "LocalizableShared"))
                .scaleEffect(buttonScale)
                .opacity(contentOpacity)
                .offset(y: dismissDragOffset * 0.35)
                .padding(.top, geometry.safeAreaInsets.top + 4)
                .padding(.trailing, 8)
                .allowsHitTesting(!isDismissing)
            }
            .animation(.easeOut(duration: 0.22), value: isContentVisible)
            .animation(.easeInOut(duration: 0.2), value: showZoomHint)
        }
        .task(id: photo.id) {
            await loadPreviewImage()
        }
        .task {
            await presentHintsAndTransition()
        }
        .onChange(of: zoomScale) { _, newValue in
            guard newValue > 1.02 else { return }

            withAnimation(.easeInOut(duration: 0.2)) {
                showZoomHint = false
            }
        }
    }

    private func loadPreviewImage() async {
        previewImage = photo.image

        if let highResolutionImage = await photoLibraryService.fetchHighResolutionPreviewImage(for: photo.asset) {
            previewImage = highResolutionImage
        }
    }

    private var zoomHintChip: some View {
        Label(
            String(localized: "review.preview.zoomHint", defaultValue: "Pinch or double-tap to zoom", table: "LocalizableReview"),
            systemImage: "arrow.up.left.and.arrow.down.right"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.black.opacity(0.55))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private var dismissDragProgress: CGFloat {
        min(max(dismissDragOffset / DismissGesture.progressRange, 0), 1)
    }

    private var backdropOpacity: CGFloat {
        guard isContentVisible else { return 0 }
        return max(0, 1 - (dismissDragProgress * 0.45))
    }

    private var contentOpacity: CGFloat {
        guard isContentVisible else { return 0 }
        return max(0, 1 - (dismissDragProgress * 0.2))
    }

    private var contentScale: CGFloat {
        let dragScale = 1 - (dismissDragProgress * 0.08)
        return isContentVisible ? dragScale : dragScale * 0.985
    }

    private var buttonScale: CGFloat {
        let dragScale = 1 - (dismissDragProgress * 0.08)
        return isContentVisible ? dragScale : dragScale * 0.92
    }

    private func presentHintsAndTransition() async {
        await MainActor.run {
            withAnimation(.easeOut(duration: 0.22)) {
                isContentVisible = true
            }
        }

        guard !hasSeenPhotoZoomHint else { return }

        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled, !isDismissing else { return }

        await MainActor.run {
            withAnimation(.easeOut(duration: 0.2)) {
                showZoomHint = true
            }
        }

        hasSeenPhotoZoomHint = true

        try? await Task.sleep(nanoseconds: 2_200_000_000)
        guard !Task.isCancelled, !isDismissing else { return }

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.2)) {
                showZoomHint = false
            }
        }
    }

    private func handleDismissDragChanged(_ translation: CGFloat) {
        guard !isDismissing else { return }

        dismissDragOffset = translation

        guard showZoomHint else { return }

        withAnimation(.easeInOut(duration: 0.15)) {
            showZoomHint = false
        }
    }

    private func handleDismissDragEnded(translation: CGFloat, velocity: CGFloat, containerHeight: CGFloat) {
        guard !isDismissing else { return }

        let shouldDismiss = translation >= DismissGesture.distanceThreshold || velocity >= DismissGesture.velocityThreshold
        guard shouldDismiss else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                dismissDragOffset = 0
            }
            return
        }

        let projectedOffset = max(translation, min(containerHeight * 0.45, translation + (velocity * 0.12)))
        dismissPreview(finalOffset: projectedOffset)
    }

    private func dismissPreview(finalOffset: CGFloat? = nil) {
        guard !isDismissing else { return }

        isDismissing = true
        withAnimation(.easeInOut(duration: 0.18)) {
            isContentVisible = false
            showZoomHint = false
            dismissDragOffset = finalOffset ?? dismissDragOffset
        }

        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            await MainActor.run {
                dismiss()
            }
        }
    }
}
