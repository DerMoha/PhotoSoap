import SwiftUI

struct ActionButtons: View {
    let onKeep: () -> Void
    let onDelete: () -> Void

    @State private var keepPressed = false
    @State private var deletePressed = false

    private let buttonSize: CGFloat = 65

    var body: some View {
        HStack(spacing: 50) {
            deleteButton
            keepButton
        }
        .padding(.horizontal, 32)
    }

    private var deleteButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                deletePressed = true
            }

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                deletePressed = false
                onDelete()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: buttonSize, height: buttonSize)

                Circle()
                    .stroke(Color.red, lineWidth: 2.5)
                    .frame(width: buttonSize, height: buttonSize)

                Image(systemName: "trash.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
            }
            .scaleEffect(deletePressed ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete photo")
    }

    private var keepButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                keepPressed = true
            }

            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                keepPressed = false
                onKeep()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: buttonSize, height: buttonSize)

                Circle()
                    .stroke(Color.green, lineWidth: 2.5)
                    .frame(width: buttonSize, height: buttonSize)

                Image(systemName: "checkmark")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)
            }
            .scaleEffect(keepPressed ? 0.9 : 1.0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Keep photo")
    }
}

struct ActionButtonsCompact: View {
    let onKeep: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 40) {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                onDelete()
            } label: {
                Image(systemName: "xmark")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                    .frame(width: 60, height: 60)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Circle())
            }

            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                onKeep()
            } label: {
                Image(systemName: "checkmark")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                    .frame(width: 60, height: 60)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Circle())
            }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        ActionButtons(onKeep: {}, onDelete: {})
        ActionButtonsCompact(onKeep: {}, onDelete: {})
    }
}
