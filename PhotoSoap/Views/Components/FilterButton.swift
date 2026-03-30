import SwiftUI

struct FilterButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .foregroundStyle(.primary)

                if isActive {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                        .offset(x: 2, y: -2)
                }
            }
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(String(localized: "filter.accessibility", defaultValue: "Filter photos", table: "LocalizableFilter"))
    }
}

#Preview {
    HStack(spacing: 20) {
        FilterButton(isActive: false, action: {})
        FilterButton(isActive: true, action: {})
    }
    .padding()
}
