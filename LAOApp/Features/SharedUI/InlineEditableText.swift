import SwiftUI

/// A text label that reveals an inline edit field on tap.
///
/// - Single-line (`isMultiline = false`): renders as `TextField`; Return commits.
/// - Multi-line (`isMultiline = true`): renders as `TextEditor` with 2-6 line limit.
/// - Hover shows a pencil icon. ESC / ✕ button cancels (discards draft).
struct InlineEditableText: View {
    @Environment(\.theme) private var theme

    @Binding var draft: String
    let displayText: String
    let placeholder: String
    let isMultiline: Bool
    let isEditing: Bool
    let isSaving: Bool
    let onTap: () -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        if isEditing {
            editingContent
        } else {
            displayContent
        }
    }

    // MARK: - Display

    private var displayContent: some View {
        HStack(spacing: 6) {
            Group {
                if displayText.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(theme.foregroundMuted)
                } else {
                    Text(displayText)
                        .foregroundStyle(isMultiline ? theme.foregroundSecondary : theme.foregroundPrimary)
                }
            }
            .font(isMultiline ? AppTheme.Typography.body : AppTheme.Typography.sectionTitle.weight(.bold))

            if isHovering && !isSaving {
                Image(systemName: "pencil.circle")
                    .font(.system(size: isMultiline ? 13 : 15))
                    .foregroundStyle(theme.foregroundTertiary)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
        .onTapGesture { onTap() }
    }

    // MARK: - Editing

    private var editingContent: some View {
        HStack(alignment: isMultiline ? .top : .center, spacing: 6) {
            if isMultiline {
                TextEditor(text: $draft)
                    .font(AppTheme.Typography.body)
                    .frame(minHeight: 40, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
            } else {
                TextField(placeholder, text: $draft)
                    .font(AppTheme.Typography.sectionTitle.weight(.bold))
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit { onCommit() }
            }

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.foregroundSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .stroke(theme.accentPrimary.opacity(0.4), lineWidth: 1)
        )
        .onAppear { isFocused = true }
        .onExitCommand { onCancel() }
    }
}
