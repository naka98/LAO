import SwiftUI

/// Reusable capsule-shaped filter chip for status/category filtering.
struct FilterChipButton: View {
    @Environment(\.theme) private var theme

    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.Typography.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? theme.accentSoft : theme.surfaceSubtle)
                .foregroundStyle(isSelected ? theme.accentPrimary : theme.foregroundPrimary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
