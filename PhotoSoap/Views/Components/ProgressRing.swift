import SwiftUI

struct ProgressRing: View {
    let progress: Double
    let current: Int
    let target: Int
    let title: String

    @State private var animatedProgress: Double = 0

    var body: some View {
        HStack(spacing: 16) {
            ringView

            VStack(alignment: .leading, spacing: 4) {
                Text("challenge.daily")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(current)/\(target)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if progress >= 1.0 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.spring()) {
                animatedProgress = newValue
            }
        }
    }

    private var ringView: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 6)
                .frame(width: 50, height: 50)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 50, height: 50)
                .rotationEffect(.degrees(-90))

            Text("\(Int(animatedProgress * 100))%")
                .font(.caption2)
                .fontWeight(.semibold)
        }
    }

    private var progressColor: Color {
        if progress >= 1.0 {
            return .green
        } else if progress >= 0.75 {
            return .blue
        } else if progress >= 0.5 {
            return .orange
        } else {
            return .blue
        }
    }
}

struct ProgressRingLarge: View {
    let progress: Double
    let current: Int
    let target: Int
    let title: String
    let subtitle: String

    @State private var animatedProgress: Double = 0

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 12)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.8), value: animatedProgress)

                VStack(spacing: 2) {
                    Text("\(current)")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("of \(target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.spring()) {
                animatedProgress = newValue
            }
        }
    }

    private var gradientColors: [Color] {
        if progress >= 1.0 {
            return [.green, .mint]
        } else {
            return [.blue, .purple]
        }
    }
}

struct ProgressBar: View {
    let progress: Double
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color(.systemGray4))

                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * min(progress, 1.0))
                    .animation(.spring(), value: progress)
            }
        }
        .frame(height: height)
    }
}

#Preview {
    VStack(spacing: 30) {
        ProgressRing(
            progress: 0.65,
            current: 13,
            target: 20,
            title: "Review 20 photos"
        )

        ProgressRingLarge(
            progress: 0.75,
            current: 15,
            target: 20,
            title: "Daily Challenge",
            subtitle: "Review 20 photos today"
        )

        ProgressBar(progress: 0.7, height: 8)
            .padding(.horizontal)
    }
    .padding()
}
