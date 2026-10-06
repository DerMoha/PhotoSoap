import SwiftUI
import UIKit

struct PhotoShareButton: View {
    let photo: Photo
    @ObservedObject var photoLibraryService: PhotoLibraryService

    @State private var isPreparingShare = false
    @State private var shareFile: ShareFile?
    @State private var shareError: String?
    @State private var exportedURL: URL?

    var body: some View {
        Button {
            Task { await prepareShare() }
        } label: {
            Group {
                if isPreparingShare {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3.weight(.semibold))
                }
            }
            .frame(minWidth: 32, minHeight: 32)
        }
        .modifier(NativeGlassButtonStyle())
        .buttonBorderShape(.circle)
        .disabled(isPreparingShare)
        .accessibilityLabel(String(localized: "common.share", defaultValue: "Share", table: "LocalizableShared"))
        .sheet(item: $shareFile, onDismiss: removeShareFile) { file in
            PhotoActivitySheet(url: file.url)
        }
        .alert(String(localized: "error.title", table: "LocalizableShared"), isPresented: Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button(String(localized: "common.ok", table: "LocalizableShared")) { shareError = nil }
        } message: {
            Text(shareError ?? "")
        }
    }

    private func prepareShare() async {
        guard !isPreparingShare else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }

        do {
            let url = try await photoLibraryService.exportShareFile(for: photo)
            exportedURL = url
            shareFile = ShareFile(url: url)
        } catch {
            shareError = error.localizedDescription
        }
    }

    private func removeShareFile() {
        if let exportedURL {
            try? FileManager.default.removeItem(at: exportedURL.deletingLastPathComponent())
        }
        exportedURL = nil
    }
}

private struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PhotoActivitySheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
