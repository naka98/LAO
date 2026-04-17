import LAODomain
import SwiftUI

struct BadgeView: View {
    @Environment(\.theme) private var theme

    let title: String
    let tone: StatusTone

    var body: some View {
        Text(title)
            .font(AppTheme.Typography.bodySecondary.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch tone {
        case .neutral: theme.neutralBadgeFill
        case .blue: theme.accentSoft
        case .green: theme.infoSoftFill
        case .amber: theme.warningSoftFill
        case .red: theme.criticalSoftFill
        case .purple: Color.purple.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        switch tone {
        case .neutral: theme.foregroundSecondary
        case .blue: theme.accentPrimary
        case .green: theme.positiveAccent
        case .amber: theme.warningAccent
        case .red: theme.criticalAccent
        case .purple: Color.purple
        }
    }
}
