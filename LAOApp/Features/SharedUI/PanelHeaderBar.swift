import SwiftUI

/// Unified navigation-style header bar for main content panels.
/// Provides consistent height, padding, and typography across all panels.
struct PanelHeaderBar<Trailing: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang

    let title: String
    var subtitle: String?
    var backAction: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        backAction: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.backAction = backAction
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
            // Center: title + subtitle
            VStack(spacing: 2) {
                Text(title)
                    .font(AppTheme.Typography.heading)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTheme.Typography.label)
                        .foregroundStyle(theme.foregroundSecondary)
                }
            }

            // Leading / trailing
            HStack {
                if let backAction {
                    Button(action: backAction) {
                        Label(lang.common.back, systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
                trailing()
            }
        }
        // Fixed height keeps the header consistent whether trailing
        // buttons are visible (list mode) or hidden (detail/back mode).
        .frame(height: 28)
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.vertical, AppTheme.Spacing.m)
    }
}

extension PanelHeaderBar where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, backAction: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.backAction = backAction
        self.trailing = { EmptyView() }
    }
}
