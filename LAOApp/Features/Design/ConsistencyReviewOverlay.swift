import SwiftUI

// MARK: - Consistency Review Overlay

/// Full-screen overlay for reviewing and fixing consistency issues before export.
/// Pattern: consistency check finds issues → director proposes fixes → user approves → actions dispatched → export.
struct ConsistencyReviewOverlay: View {
    @Bindable var vm: DesignWorkflowViewModel
    let onDismiss: () -> Void
    let onExport: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang
    @State private var inputText: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { /* block tap-through */ }

            VStack(spacing: 0) {
                headerBar
                Divider()
                conversationArea
                Divider()
                inputBar
            }
            .frame(width: 520)
            .frame(minHeight: 360, maxHeight: 600)
            .background(theme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 8)
        }
        .onExitCommand { onDismiss() }
        .transition(.opacity)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.design.consistencyReviewTitle)
                    .font(.headline)
                Text(lang.design.consistencyReviewSubtitle(vm.consistencyIssues.count))
                    .font(.subheadline)
                    .foregroundStyle(theme.foregroundSecondary)
            }
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(theme.foregroundTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Conversation Area

    private var conversationArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Issues summary card (always visible at top)
                    issuesSummaryCard.id("issues-card")

                    // Chat messages
                    ForEach(vm.consistencyChatMessages) { msg in
                        chatBubble(msg).id(msg.id)
                    }

                    // Streaming response
                    if vm.isConsistencyChatting, !vm.consistencyStreamOutput.isEmpty {
                        streamingBubble.id("con-streaming")
                    }

                    // Thinking indicator
                    if vm.isConsistencyChatting, vm.consistencyStreamOutput.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(lang.design.thinking)
                                .font(.caption)
                                .foregroundStyle(theme.foregroundTertiary)
                        }
                        .padding(8)
                        .id("con-thinking")
                    }

                    // Pending actions card
                    if !vm.isConsistencyChatting, let actions = vm.pendingConsistencyActions, !actions.isEmpty {
                        pendingActionsCard(actions).id("con-actions")
                    }

                    // Post-approval progress
                    if vm.isConsistencyApplying {
                        progressCard(
                            icon: "arrow.triangle.2.circlepath",
                            label: lang.design.consistencyApplyingFixes,
                            showSpinner: true
                        ).id("con-applying")
                    }

                    if vm.isConsistencyElaborating {
                        progressCard(
                            icon: "pencil.and.outline",
                            label: lang.design.consistencyReElaborating,
                            showSpinner: true
                        ).id("con-elaborating")
                    }

                    if vm.consistencyReviewCompleted {
                        progressCard(
                            icon: "checkmark.circle.fill",
                            label: lang.design.consistencyFixesComplete,
                            showSpinner: false,
                            tint: theme.positiveAccent
                        ).id("con-complete")
                    }
                }
                .padding(16)
            }
            .onChange(of: vm.consistencyChatMessages.count) { _, _ in
                if let id = vm.consistencyChatMessages.last?.id {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .onChange(of: vm.isConsistencyApplying) { _, applying in
                if applying { withAnimation { proxy.scrollTo("con-applying", anchor: .bottom) } }
            }
            .onChange(of: vm.isConsistencyElaborating) { _, elaborating in
                if elaborating { withAnimation { proxy.scrollTo("con-elaborating", anchor: .bottom) } }
            }
            .onChange(of: vm.consistencyReviewCompleted) { _, completed in
                if completed { withAnimation { proxy.scrollTo("con-complete", anchor: .bottom) } }
            }
        }
    }

    // MARK: - Input Bar

    private var isPostApproval: Bool {
        vm.isConsistencyApplying || vm.isConsistencyElaborating || vm.consistencyReviewCompleted
    }

    private var inputBar: some View {
        VStack(spacing: 12) {
            if vm.consistencyReviewCompleted {
                // Fixes applied — export button
                Button { onExport() } label: {
                    Label(lang.design.consistencyProceedExport, systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.positiveAccent)
                .controlSize(.regular)
            } else if isPostApproval {
                EmptyView()
            } else {
                // Conversation phase
                HStack(spacing: 8) {
                    TextField(lang.design.consistencyDiscussPlaceholder, text: $inputText, axis: .vertical)
                        .focused($inputFocused)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .padding(10)
                        .font(.body)
                        .background(theme.surfaceSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                }

                HStack(spacing: 10) {
                    Button { onDismiss() } label: {
                        Text(lang.common.cancel).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    if vm.pendingConsistencyActions != nil && !vm.isConsistencyChatting {
                        Button { sendMessage() } label: {
                            Text(lang.design.consistencyAddComment).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            vm.approveConsistencyFixes()
                        } label: {
                            Text(lang.design.consistencyApproveFixes).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    } else if !vm.isConsistencyChatting {
                        // Follow-up message (auto-send already happened)
                        Button { sendMessage() } label: {
                            Text(lang.common.send).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Issues Summary Card

    private var issuesSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(theme.warningAccent)
                Text(lang.design.consistencyReviewTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.warningAccent)
            }

            if !vm.consistencySummary.isEmpty {
                Text(vm.consistencySummary)
                    .font(.callout)
                    .foregroundStyle(theme.foregroundSecondary)
            }

            ForEach(vm.consistencyIssues) { issue in
                issueRow(issue)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.warningAccent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }

    private func issueRow(_ issue: ConsistencyIssue) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: severityIcon(issue.severity))
                .font(.system(size: 12))
                .foregroundStyle(severityColor(issue.severity))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(severityLabel(issue.severity))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(severityColor(issue.severity))
                    Text("·")
                        .foregroundStyle(theme.foregroundTertiary)
                    Text(issue.affectedItems.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(theme.foregroundTertiary)
                        .lineLimit(1)
                }
                Text(issue.description)
                    .font(.caption)
                    .foregroundStyle(theme.foregroundPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        vm.sendConsistencyMessage(text)
    }

    @ViewBuilder
    private func chatBubble(_ msg: DesignChatMessage) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(msg.content)
                    .font(.body)
                    .padding(12)
                    .background(theme.accentPrimary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                    .textSelection(.enabled)
            }
        case .design:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(theme.accentPrimary)
                    Text(lang.common.design)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.accentPrimary)
                    Spacer()
                }
                Text(msg.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(theme.accentPrimary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        case .system:
            HStack {
                Spacer()
                Text(msg.content)
                    .font(.caption)
                    .foregroundStyle(theme.foregroundTertiary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    private var streamingBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(lang.common.design)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accentPrimary)
            }
            Text(vm.consistencyStreamOutput)
                .font(.body)
                .foregroundStyle(theme.foregroundSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(10)
        }
        .padding(12)
        .background(theme.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }

    private func progressCard(
        icon: String,
        label: String,
        showSpinner: Bool,
        tint: Color? = nil
    ) -> some View {
        HStack(spacing: 10) {
            if showSpinner {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(tint ?? theme.accentPrimary)
            }
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(tint ?? theme.foregroundPrimary)
            Spacer()
        }
        .padding(12)
        .background((tint ?? theme.accentPrimary).opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }

    private func pendingActionsCard(_ actions: [DesignAction]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.caption)
                    .foregroundStyle(theme.accentPrimary)
                Text(lang.design.consistencyApproveFixes)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accentPrimary)
            }
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                HStack(alignment: .top, spacing: 6) {
                    Text("•").foregroundStyle(theme.foregroundSecondary)
                    Text(action.displayDescription)
                        .font(.callout)
                        .foregroundStyle(theme.foregroundPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accentPrimary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }

    // MARK: - Severity Helpers

    private func severityIcon(_ severity: String) -> String {
        switch severity {
        case "critical": return "exclamationmark.triangle.fill"
        case "warning": return "exclamationmark.circle.fill"
        case "info": return "info.circle.fill"
        default: return "questionmark.circle"
        }
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity {
        case "critical": return theme.criticalAccent
        case "warning": return theme.warningAccent
        case "info": return theme.foregroundTertiary
        default: return theme.foregroundSecondary
        }
    }

    private func severityLabel(_ severity: String) -> String {
        switch severity {
        case "critical": return lang.design.consistencyIssueCritical
        case "warning": return lang.design.consistencyIssueWarning
        case "info": return lang.design.consistencyIssueInfo
        default: return severity
        }
    }
}
