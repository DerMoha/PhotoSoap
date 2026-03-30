import SwiftUI
import UIKit

struct StreakBanner: View {
    let currentStreak: Int
    let bestStreak: Int

    @State private var isAnimating = false
    @State private var previousStreak = 0

    var body: some View {
        HStack(spacing: 16) {
            currentStreakSection
            Divider()
                .frame(height: 40)
            bestStreakSection
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onChange(of: currentStreak) { oldValue, newValue in
            if newValue > oldValue {
                triggerAnimation()
            }
            previousStreak = oldValue
        }
    }

    private var currentStreakSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(streakColor)
                .scaleEffect(isAnimating ? 1.3 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isAnimating)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "streak.current", table: "LocalizableReview"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(currentStreak)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .contentTransition(.numericText())
                    .animation(.spring(), value: currentStreak)
            }
        }
    }

    private var bestStreakSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.title3)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "streak.best", table: "LocalizableReview"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(bestStreak)")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
        }
    }

    private var streakColor: Color {
        switch currentStreak {
        case 0..<5:
            return .orange
        case 5..<10:
            return .orange
        case 10..<25:
            return .red
        case 25..<50:
            return .purple
        default:
            return .blue
        }
    }

    private func triggerAnimation() {
        isAnimating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.isAnimating = false
        }
    }
}

struct CompactHeader: View {
    let todayReviewCount: Int
    let progress: Double
    let current: Int
    let target: Int
    let challengeTitle: String
    let challengeCompactTitle: String
    let isFilterActive: Bool
    let onFilterTap: () -> Void
    let onGoalTap: () -> Void
    let onDailyGoalComplete: () -> Void

    @State private var isAnimating = false
    @State private var wasCompleted = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isAnimating)

                Text("\(todayReviewCount)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .contentTransition(.numericText())
                    .animation(.spring(), value: todayReviewCount)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(Capsule())

            FilterButton(isActive: isFilterActive, action: onFilterTap)

            Spacer()

            Button(action: onGoalTap) {
                ViewThatFits(in: .horizontal) {
                    goalLabel(title: challengeTitle)
                    goalLabel(title: challengeCompactTitle)
                    goalLabel(title: nil)
                }
            }
            .buttonStyle(.plain)
        }
        .onChange(of: todayReviewCount) { oldValue, newValue in
            if newValue > oldValue {
                isAnimating = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.isAnimating = false
                }
            }
        }
        .onChange(of: progress) { oldValue, newValue in
            if oldValue < 1.0 && newValue >= 1.0 && !wasCompleted {
                wasCompleted = true
                isAnimating = true
                onDailyGoalComplete()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isAnimating = false
                }
            }
        }
    }

    private var progressColor: Color {
        if progress >= 1.0 {
            return .green
        } else if progress >= 0.75 {
            return .blue
        } else {
            return .orange
        }
    }

    private var progressIndicator: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 3)
                .frame(width: 24, height: 24)

            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(progressColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 24, height: 24)
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.5), value: progress)

            if progress >= 1.0 {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.green)
                    .scaleEffect(isAnimating ? 1.3 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isAnimating)
            }
        }
        .frame(width: 24, height: 24)
    }

    private func goalLabel(title: String?) -> some View {
        HStack(spacing: 8) {
            progressIndicator

            if progress < 1.0 {
                if let title {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text("\(current)/\(target)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(current)/\(target)")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(Capsule())
    }
}

struct StreakBannerCompact: View {
    let todayReviewCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
            Text("\(todayReviewCount)")
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray5))
        .clipShape(Capsule())
    }
}

struct StreakMilestoneView: View {
    let milestone: Int
    @Binding var isShowing: Bool

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                ForEach(0..<8) { index in
                    Circle()
                        .fill(.orange.opacity(0.3))
                        .frame(width: 20, height: 20)
                        .offset(y: -60)
                        .rotationEffect(.degrees(Double(index) * 45))
                        .scaleEffect(isShowing ? 1.5 : 0)
                        .opacity(isShowing ? 0 : 1)
                        .animation(
                            .easeOut(duration: 0.8).delay(Double(index) * 0.05),
                            value: isShowing
                        )
                }

                Image(systemName: "flame.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange, .red],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(isShowing ? 1.2 : 0.5)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: isShowing)
            }

            Text(String(localized: "streak.milestone", defaultValue: "\(milestone) Streak!", table: "LocalizableReview"))
                .font(.title)
                .fontWeight(.bold)
                .scaleEffect(isShowing ? 1 : 0.5)
                .opacity(isShowing ? 1 : 0)
                .animation(.spring().delay(0.2), value: isShowing)

            Text(String(localized: "streak.fire", table: "LocalizableReview"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .opacity(isShowing ? 1 : 0)
                .animation(.easeIn.delay(0.4), value: isShowing)
        }
        .padding(40)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

#Preview {
    VStack(spacing: 20) {
        StreakBanner(currentStreak: 15, bestStreak: 42)
        StreakBannerCompact(todayReviewCount: 15)
        StreakMilestoneView(milestone: 25, isShowing: .constant(true))
    }
    .padding()
}
