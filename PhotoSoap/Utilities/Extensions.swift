import SwiftUI
import UIKit
import Photos
import Combine

// MARK: - Haptic Feedback Helpers

enum Haptic {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

// MARK: - View Extensions

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Color Extensions

extension Color {
    static let streakOrange = Color.orange
    static let keepGreen = Color.green
    static let deleteRed = Color.red
    static let achievementGold = Color.yellow
}

// MARK: - Date Extensions

extension Date {
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    func daysBetween(_ date: Date) -> Int {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: self.startOfDay, to: date.startOfDay)
        return components.day ?? 0
    }

    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Int64 Extensions

extension Int64 {
    var formattedBytes: String {
        guard self > 0 else { return String(localized: "photo.unknownSize", defaultValue: "Unknown size", table: "LocalizableShared") }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self)
    }
}

// MARK: - Animation Extensions

extension Animation {
    static var bouncy: Animation {
        .spring(response: 0.3, dampingFraction: 0.6)
    }

    static var smooth: Animation {
        .easeInOut(duration: 0.3)
    }
}

// MARK: - PHAsset Extensions

extension PHAsset {
    var isScreenshot: Bool {
        mediaSubtypes.contains(.photoScreenshot)
    }

    var isLivePhoto: Bool {
        mediaSubtypes.contains(.photoLive)
    }

    var isPanorama: Bool {
        mediaSubtypes.contains(.photoPanorama)
    }

    var isHDR: Bool {
        mediaSubtypes.contains(.photoHDR)
    }
}

// MARK: - Collection Extensions

extension Collection {
    var isNotEmpty: Bool {
        !isEmpty
    }
}

// MARK: - Number Formatting

extension Int {
    var abbreviated: String {
        if self >= 1000000 {
            return String(format: "%.1fM", Double(self) / 1000000.0)
        } else if self >= 1000 {
            return String(format: "%.1fK", Double(self) / 1000.0)
        }
        return "\(self)"
    }
}

// MARK: - Confetti Effect

struct ConfettiView: View {
    @State private var confetti: [ConfettiPiece] = []
    let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(confetti) { piece in
                    Circle()
                        .fill(piece.color)
                        .frame(width: piece.size, height: piece.size)
                        .position(piece.position)
                        .opacity(piece.opacity)
                }
            }
            .onAppear {
                createConfetti(in: geometry.size)
            }
        }
    }

    private func createConfetti(in size: CGSize) {
        for _ in 0..<50 {
            let piece = ConfettiPiece(
                id: UUID(),
                color: colors.randomElement() ?? .blue,
                size: CGFloat.random(in: 5...12),
                position: CGPoint(x: size.width / 2, y: size.height / 2),
                opacity: 1.0
            )
            confetti.append(piece)
        }

        for index in confetti.indices {
            let delay = Double.random(in: 0...0.3)
            let endX = CGFloat.random(in: 0...size.width)
            let endY = CGFloat.random(in: 0...size.height)

            withAnimation(.easeOut(duration: 1.5).delay(delay)) {
                confetti[index].position = CGPoint(x: endX, y: endY)
                confetti[index].opacity = 0
            }
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id: UUID
    let color: Color
    let size: CGFloat
    var position: CGPoint
    var opacity: Double
}

// MARK: - Shake Effect

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX:
            amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
            y: 0))
    }
}

extension View {
    func shake(trigger: Bool, amount: CGFloat = 10) -> some View {
        modifier(ShakeModifier(trigger: trigger, amount: amount))
    }
}

struct ShakeModifier: ViewModifier {
    let trigger: Bool
    let amount: CGFloat
    @State private var shakeAmount: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(ShakeEffect(amount: amount, animatableData: shakeAmount))
            .onChange(of: trigger) { _, newValue in
                if newValue {
                    withAnimation(.default) {
                        shakeAmount = 1
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        await MainActor.run {
                            shakeAmount = 0
                        }
                    }
                }
            }
    }
}
