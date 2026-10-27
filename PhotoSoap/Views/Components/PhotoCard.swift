import SwiftUI

struct PhotoCard: View {
    let photo: Photo
    var offset: CGSize = .zero
    var rotation: Double = 0
    var swipeProgress: CGFloat = 0
    var swipeDirection: SwipeDirection?
    var fileSizeOverride: Int64?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                cardContent(size: geometry.size)
                overlays
            }
        }
        .rotationEffect(.degrees(rotation))
        .offset(x: offset.width, y: 0)
    }

    private func cardContent(size: CGSize) -> some View {
        return VStack(spacing: 0) {
            GeometryReader { imageGeometry in
                photoImage(size: imageGeometry.size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            compactMetadata
        }
        .frame(width: size.width, height: size.height)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private func photoImage(size: CGSize) -> some View {
        ZStack {
            if let image = photo.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                mediaPlaceholder(size: size)
            }

            if photo.isVideo {
                videoPlayBadge

                VStack {
                    HStack {
                        videoDurationBadge
                        Spacer()
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func mediaPlaceholder(size: CGSize) -> some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .frame(width: size.width, height: size.height)
            .overlay {
                Image(systemName: photo.isVideo ? "video.fill" : "photo.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
    }

    private var videoPlayBadge: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(.black.opacity(0.42))
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 6)
    }

    private var videoDurationBadge: some View {
        Label(photo.formattedDuration ?? String(localized: "review.preview.video", defaultValue: "Video", table: "LocalizableReview"), systemImage: "video.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.5))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
    }

    // Compact single-line metadata
    private var compactMetadata: some View {
        HStack(spacing: 12) {
            // Date
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(photo.shortFormattedDate)
                    .font(.caption)
            }

            Spacer()

            if let fileSizeText {
                Text(fileSizeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(photo.isVideo ? videoMetadataText : photo.compactDimensions)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var videoMetadataText: String {
        if let formattedDuration = photo.formattedDuration {
            return formattedDuration
        }

        return photo.compactDimensions
    }

    private var fileSizeText: String? {
        Photo.formattedFileSizeText(fileSizeOverride ?? photo.fileSize)
    }

    private var overlays: some View {
        ZStack {
            if showKeepOverlay {
                keepOverlay
                    .opacity(overlayOpacity)
                    .transition(.opacity)
            }

            if showDeleteOverlay {
                deleteOverlay
                    .opacity(overlayOpacity)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showKeepOverlay)
        .animation(.easeInOut(duration: 0.2), value: showDeleteOverlay)
    }

    private var showKeepOverlay: Bool {
        swipeDirection == .keep
    }

    private var showDeleteOverlay: Bool {
        swipeDirection == .delete
    }

    private var overlayOpacity: Double {
        Double(min(max(swipeProgress, 0), 1))
    }

    private var keepOverlay: some View {
        VStack {
            HStack {
                Label(String(localized: "review.swipe.keep", table: "LocalizableReview"), systemImage: "checkmark")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.green.opacity(0.2), lineWidth: 1)
                    }

                Spacer()
            }
            .padding()

            Spacer()
        }
    }

    private var deleteOverlay: some View {
        VStack {
            HStack {
                Spacer()

                Label(String(localized: "review.swipe.delete", table: "LocalizableReview"), systemImage: "trash")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.red.opacity(0.2), lineWidth: 1)
                    }
            }
            .padding()

            Spacer()
        }
    }
}

// Preview requires a real PHAsset, so we skip it
// Use the app's simulator to test PhotoCard
