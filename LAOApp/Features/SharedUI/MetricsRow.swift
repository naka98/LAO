import SwiftUI

/// Compact inline display of API call count and token usage.
struct MetricsRow: View {
    @Environment(\.theme) private var theme

    let apiCalls: Int
    let tokens: Int

    var body: some View {
        if apiCalls > 0 || tokens > 0 {
            HStack(spacing: 8) {
                if apiCalls > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(AppTheme.Typography.iconSmall)
                        Text("\(apiCalls)")
                            .font(AppTheme.Typography.caption)
                    }
                    .foregroundStyle(theme.foregroundTertiary)
                }

                if tokens > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "textformat.size")
                            .font(AppTheme.Typography.iconSmall)
                        Text(TokenFormatter.abbreviated(tokens))
                            .font(AppTheme.Typography.caption)
                    }
                    .foregroundStyle(theme.foregroundTertiary)
                }
            }
        }
    }
}
