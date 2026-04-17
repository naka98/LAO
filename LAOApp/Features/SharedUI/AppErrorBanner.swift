import SwiftUI

// MARK: - Data Model

enum AppErrorSeverity {
    case info
    case warning
    case critical
}

struct AppBannerItem: Identifiable {
    let id = UUID()
    let severity: AppErrorSeverity
    let title: String
    let message: String?
    let actionTitle: String?
    let action: (() -> Void)?
    let autoDismissSeconds: Double?

    static func info(_ title: String, message: String? = nil) -> AppBannerItem {
        AppBannerItem(severity: .info, title: title, message: message,
                      actionTitle: nil, action: nil, autoDismissSeconds: 4)
    }

    static func warning(_ title: String, message: String? = nil) -> AppBannerItem {
        AppBannerItem(severity: .warning, title: title, message: message,
                      actionTitle: nil, action: nil, autoDismissSeconds: 6)
    }

    static func critical(_ title: String, message: String? = nil,
                         actionTitle: String? = nil, action: (() -> Void)? = nil) -> AppBannerItem {
        AppBannerItem(severity: .critical, title: title, message: message,
                      actionTitle: actionTitle, action: action, autoDismissSeconds: nil)
    }
}

// MARK: - App-wide State

@Observable
@MainActor
final class AppBannerState {
    var current: AppBannerItem? = nil

    func show(_ item: AppBannerItem) {
        withAnimation { current = item }
        if let seconds = item.autoDismissSeconds {
            let itemId = item.id
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if current?.id == itemId {
                    dismiss()
                }
            }
        }
    }

    func dismiss() {
        withAnimation { current = nil }
    }
}

// MARK: - Banner View

struct ErrorBannerView: View {
    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang

    let item: AppBannerItem
    var onDismiss: () -> Void

    private var iconName: String {
        switch item.severity {
        case .info:     "info.circle.fill"
        case .warning:  "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch item.severity {
        case .info:     theme.accentPrimary
        case .warning:  theme.warningAccent
        case .critical: theme.criticalAccent
        }
    }

    private var backgroundColor: Color {
        switch item.severity {
        case .info:     theme.infoSoftFill
        case .warning:  theme.warningSoftFill
        case .critical: theme.criticalSoftFill
        }
    }

    private var borderColor: Color {
        switch item.severity {
        case .info:     theme.accentSoft
        case .warning:  theme.warningAccent.opacity(0.5)
        case .critical: theme.criticalAccent.opacity(0.5)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.system(size: 16, weight: .semibold))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(AppTheme.Typography.heading)
                if let message = item.message {
                    Text(message).font(AppTheme.Typography.label).foregroundStyle(theme.foregroundPrimary)
                }
            }

            Spacer()

            if let actionTitle = item.actionTitle {
                Button(actionTitle) { item.action?(); onDismiss() }
                    .font(AppTheme.Typography.label.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .buttonStyle(.plain)
            }

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.foregroundSecondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(lang.common.dismiss)
        }
        .padding(14)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
    }
}

// MARK: - ViewModifier

struct AppErrorBannerModifier: ViewModifier {
    @Bindable var state: AppBannerState

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            if let item = state.current {
                ErrorBannerView(item: item) { state.dismiss() }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity.animation(.easeOut(duration: 0.2))
                    ))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: state.current?.id)
    }
}

extension View {
    func appErrorBanner(_ state: AppBannerState) -> some View {
        modifier(AppErrorBannerModifier(state: state))
    }
}
