import SwiftUI

struct SurfaceCard<Content: View>: View {
    @Environment(\.theme) private var theme

    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.l) {
            if let title {
                Text(title)
                    .font(AppTheme.Typography.heading)
            }
            content
        }
        .padding(AppTheme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(theme.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(theme.borderSubtle, lineWidth: 1)
        )
        .shadow(color: theme.shadowColor, radius: 4, y: 2)
    }
}
