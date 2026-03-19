import SwiftUI

struct DailyGoalSettingSheet: View {
    @EnvironmentObject private var hapticsService: HapticsService
    @Binding var isPresented: Bool
    let currentTarget: Int
    let onSelect: (Int) -> Void

    private let goalOptions = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text(String(localized: "dailyGoal.title", table: "LocalizableReview"))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(goalOptions, id: \.self) { goal in
                            GoalOptionButton(
                                goal: goal,
                                isSelected: goal == currentTarget,
                                action: {
                                    hapticsService.selection()
                                    onSelect(goal)
                                    isPresented = false
                                }
                            )
                        }
                    }
                    .padding(.horizontal)

                    VStack(spacing: 8) {
                        Text(String(localized: "dailyGoal.current", defaultValue: "Current goal: \(currentTarget) photos", table: "LocalizableReview").replacingOccurrences(of: "%d", with: "\(currentTarget)"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(String(localized: "dailyGoal.changeApply", table: "LocalizableReview"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 8)
                }
                .padding(.vertical)
            }
            .navigationTitle(String(localized: "dailyGoal.title", table: "LocalizableReview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel", table: "LocalizableShared")) {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct GoalOptionButton: View {
    let goal: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground))
                    .frame(height: 60)

                VStack(spacing: 2) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }

                    Text("\(goal)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(isSelected ? .white : .primary)

                    Text(String(localized: "common.photos", table: "LocalizableShared"))
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DailyGoalSettingSheet(
        isPresented: .constant(true),
        currentTarget: 30,
        onSelect: { _ in }
    )
    .environmentObject(HapticsService())
}
