import SwiftUI

struct PhotoCard: View {
    let photo: Photo
    var offset: CGSize = .zero
    var rotation: Double = 0
    var showKeepOverlay: Bool = false
    var showDeleteOverlay: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                cardContent(size: geometry.size)
                overlays
            }
        }
        .offset(offset)
        .rotationEffect(.degrees(rotation))
    }

    private func cardContent(size: CGSize) -> some View {
        VStack(spacing: 0) {
            photoImage(size: size)
            compactMetadata
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private func photoImage(size: CGSize) -> some View {
        let imageHeight = size.height - 44 // Reserve space for compact metadata
        if let image = photo.image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: imageHeight)
                .clipped()
        } else {
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(width: size.width, height: imageHeight)
                .overlay {
                    ProgressView()
                }
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

            // File size
            Text(photo.fileSizeFormatted)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Dimensions
            Text(photo.compactDimensions)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var overlays: some View {
        ZStack {
            if showKeepOverlay {
                keepOverlay
                    .transition(.opacity)
            }

            if showDeleteOverlay {
                deleteOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showKeepOverlay)
        .animation(.easeInOut(duration: 0.2), value: showDeleteOverlay)
    }

    private var keepOverlay: some View {
        VStack {
            HStack {
                Label("KEEP", systemImage: "checkmark")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .rotationEffect(.degrees(-15))

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

                Label("DELETE", systemImage: "trash")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.red)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .rotationEffect(.degrees(15))
            }
            .padding()

            Spacer()
        }
    }
}

// Preview requires a real PHAsset, so we skip it
// Use the app's simulator to test PhotoCard
