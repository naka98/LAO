import SwiftUI

// MARK: - Reanalyze Confirmation Sheet

/// Small sheet replacing confirmationDialog — adds optional feedback text input.
/// The client tells the design office what to change before re-analysis.
struct ReanalyzeConfirmationSheet: View {
    let onConfirm: (String?) -> Void
    let onCancel: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang
    @State private var feedbackText: String = ""
    @FocusState private var feedbackFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            Text(lang.design.reanalyzeConfirmTitle)
                .font(.headline)

            // Warning
            Text(lang.design.reanalyzeConfirmMessage)
                .font(.callout)
                .foregroundStyle(theme.foregroundSecondary)

            // Feedback input
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if feedbackText.isEmpty {
                        Text(lang.design.reanalyzeFeedbackPlaceholder)
                            .font(.body)
                            .foregroundStyle(theme.foregroundTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $feedbackText)
                        .font(.body)
                        .focused($feedbackFocused)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 60, maxHeight: 100)
                }
                .padding(6)
                .background(theme.surfaceSubtle)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))

                Text(lang.design.reanalyzeFeedbackHint)
                    .font(.caption)
                    .foregroundStyle(theme.foregroundTertiary)
            }

            // Buttons
            HStack(spacing: 10) {
                Button { onCancel() } label: {
                    Text(lang.common.cancel).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    let trimmed = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
                    onConfirm(trimmed.isEmpty ? nil : trimmed)
                } label: {
                    Text(lang.design.reanalyzeConfirmAction).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.criticalAccent)
                .controlSize(.regular)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { feedbackFocused = true }
    }
}
