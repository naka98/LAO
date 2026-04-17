import SwiftUI

// MARK: - Decision Audit View

/// A timeline of decision-maker actions taken during the workflow.
struct DecisionAuditView: View {
    typealias Entry = DesignWorkflowViewModel.DecisionHistoryEntry

    let entries: [Entry]
    let isLoading: Bool
    let onSelectItem: (UUID) -> Void
    let theme: ThemePalette
    let lang: AppStrings

    var body: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 40)
        } else if entries.isEmpty {
            Text(lang.design.decisionCountFormat(0))
                .font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, AppTheme.Spacing.s)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    entryRow(entry)
                    if entry.id != entries.last?.id {
                        Divider().padding(.leading, 28)
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: Entry) -> some View {
        let (icon, color) = categoryStyle(entry.category)
        return HStack(alignment: .top, spacing: AppTheme.Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.summary)
                    .font(AppTheme.Typography.caption)
                    .lineLimit(2)
                Text(relativeTime(entry.timestamp))
                    .font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundTertiary)
            }

            Spacer(minLength: 0)

            if let itemId = entry.relatedItemId {
                Button {
                    onSelectItem(itemId)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10)).foregroundStyle(theme.foregroundMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .padding(.horizontal, AppTheme.Spacing.s)
    }

    private func categoryStyle(_ category: Entry.DecisionCategory) -> (String, Color) {
        switch category {
        case .approachSelected:      ("arrow.triangle.branch", theme.accentPrimary)
        case .itemConfirmed:         ("checkmark.circle.fill", theme.positiveAccent)
        case .itemRevisionRequested: ("pencil.circle.fill", theme.warningAccent)
        case .uncertaintyResolved:   ("questionmark.circle.fill", theme.accentPrimary)
        case .uncertaintyDismissed:  ("xmark.circle", Color.secondary)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
