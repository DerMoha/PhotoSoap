import SwiftUI

struct DeleteQueueTray: View {
    let queueCount: Int
    let onUndo: () -> Void
    let onReviewQueue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label {
                Text(summaryText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "trash.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)

            trayButton(
                title: String(localized: "review.queue.undo", defaultValue: "Undo", table: "LocalizableReview"),
                systemImage: "arrow.uturn.backward"
            ) {
                onUndo()
            }

            trayButton(
                title: String(localized: "review.queue.shortTitle", defaultValue: "List", table: "LocalizableReview"),
                systemImage: "list.bullet"
            ) {
                onReviewQueue()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .modifier(DeleteQueueTraySurface())
    }

    private var summaryText: String {
        String.localizedStringWithFormat(
            String(localized: "review.queue.count", defaultValue: "%lld in Delete List", table: "LocalizableReview"),
            queueCount
        )
    }

    private func trayButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .contentShape(Capsule())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

private struct DeleteQueueTraySurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
    }
}

#Preview {
    VStack {
        Spacer()
        DeleteQueueTray(
            queueCount: 12,
            onUndo: {},
            onReviewQueue: {}
        )
    }
}
