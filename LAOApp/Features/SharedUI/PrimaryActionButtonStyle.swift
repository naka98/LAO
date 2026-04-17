import SwiftUI

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }
}

private struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(AppTheme.Typography.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(configuration.isPressed ? theme.accentPrimaryPressed : theme.accentPrimary)
            )
            .opacity(isEnabled ? 1.0 : 0.4)
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration)
    }
}

private struct SecondaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.theme) private var theme

    var body: some View {
        configuration.label
            .font(AppTheme.Typography.body.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(configuration.isPressed ? theme.selectionFill : theme.surfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .stroke(
                        configuration.isPressed ? theme.accentPrimary.opacity(0.34) : theme.borderSubtle,
                        lineWidth: 1
                    )
            )
    }
}

struct WarningActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WarningButtonBody(configuration: configuration)
    }
}

private struct WarningButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.theme) private var theme

    var body: some View {
        configuration.label
            .font(AppTheme.Typography.body.weight(.semibold))
            .foregroundStyle(theme.warningAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(configuration.isPressed ? theme.warningSoftFill : theme.surfacePrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .stroke(theme.warningAccent.opacity(configuration.isPressed ? 0.7 : 0.5), lineWidth: 1)
            )
    }
}
