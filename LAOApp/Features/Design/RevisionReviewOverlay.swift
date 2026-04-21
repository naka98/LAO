import SwiftUI

// MARK: - Revision Review Overlay

/// [Purpose] 특정 항목의 수정 요청을 director와 대화하면서 수정안을 받고 승인하는 오버레이.
/// [Trigger] `showRevisionOverlay == true` && `revisionTargetItemId != nil` (항목별 수정 트리거).
/// [Flow] 사용자가 항목 수정 요청 → Revision Review(이 오버레이) → director가 수정안 제시 → 사용자 승인 → action dispatch.
struct RevisionReviewOverlay: View {
    let itemId: UUID
    let itemName: String
    @Bindable var vm: DesignWorkflowViewModel
    let onDismiss: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang
    @State private var inputText: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { /* block tap-through */ }

            // Panel
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
        .onAppear { inputFocused = true }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.design.revisionReviewTitle)
                    .font(.headline)
                Text(itemName)
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
                    ForEach(vm.revisionChatMessages) { msg in
                        revisionBubble(msg).id(msg.id)
                    }

                    // Streaming response
                    if vm.isRevisionChatting, !vm.revisionStreamOutput.isEmpty {
                        streamingBubble.id("rev-streaming")
                    }

                    // Thinking indicator
                    if vm.isRevisionChatting, vm.revisionStreamOutput.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(lang.design.thinking)
                                .font(.caption)
                                .foregroundStyle(theme.foregroundTertiary)
                        }
                        .padding(8)
                        .id("rev-thinking")
                    }

                    // Pending actions card
                    if !vm.isRevisionChatting, let actions = vm.pendingRevisionActions, !actions.isEmpty {
                        pendingActionsCard(actions).id("rev-actions")
                    }

                    // Post-approval progress
                    if vm.isRevisionApplying {
                        revisionProgressCard(
                            icon: "arrow.triangle.2.circlepath",
                            label: lang.design.revisionApplyingChanges,
                            showSpinner: true
                        ).id("rev-applying")
                    }

                    if vm.isRevisionElaborating {
                        revisionProgressCard(
                            icon: "pencil.and.outline",
                            label: lang.design.revisionReElaborating,
                            showSpinner: true
                        ).id("rev-elaborating")
                    }

                    if vm.revisionCompleted {
                        revisionProgressCard(
                            icon: "checkmark.circle.fill",
                            label: lang.design.revisionComplete,
                            showSpinner: false,
                            tint: theme.positiveAccent
                        ).id("rev-complete")
                    }
                }
                .padding(16)
            }
            .onChange(of: vm.revisionChatMessages.count) { _, _ in
                if let id = vm.revisionChatMessages.last?.id {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .onChange(of: vm.isRevisionApplying) { _, applying in
                if applying { withAnimation { proxy.scrollTo("rev-applying", anchor: .bottom) } }
            }
            .onChange(of: vm.isRevisionElaborating) { _, elaborating in
                if elaborating { withAnimation { proxy.scrollTo("rev-elaborating", anchor: .bottom) } }
            }
            .onChange(of: vm.revisionCompleted) { _, completed in
                if completed { withAnimation { proxy.scrollTo("rev-complete", anchor: .bottom) } }
            }
        }
    }

    // MARK: - Input Bar

    /// True when revision is being applied (post-approval phase).
    private var isPostApproval: Bool {
        vm.isRevisionApplying || vm.isRevisionElaborating || vm.revisionCompleted
    }

    private var inputBar: some View {
        VStack(spacing: 12) {
            if vm.revisionCompleted {
                // Revision done — close button only
                Button { onDismiss() } label: {
                    Label(lang.common.done, systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.positiveAccent)
                .controlSize(.regular)
            } else if isPostApproval {
                // Applying/elaborating — show progress, no input
                EmptyView()
            } else {
                // Normal conversation phase
                HStack(spacing: 8) {
                    TextField(lang.design.revisionNotePlaceholder, text: $inputText, axis: .vertical)
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

                    if vm.pendingRevisionActions != nil && !vm.isRevisionChatting {
                        // After director responded with actions: send more feedback or approve
                        Button { sendMessage() } label: {
                            Text(lang.design.revisionAddComment).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            vm.approveRevisionActions(for: itemId)
                        } label: {
                            Text(lang.design.revisionApprove).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    } else {
                        // Initial or follow-up: send revision request
                        Button { sendMessage() } label: {
                            Text(lang.design.revisionSubmitReview).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isRevisionChatting)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        vm.sendRevisionMessage(text, for: itemId)
    }

    @ViewBuilder
    private func revisionBubble(_ msg: DesignChatMessage) -> some View {
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
            Text(vm.revisionStreamOutput)
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

    private func revisionProgressCard(
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
                Image(systemName: "list.clipboard")
                    .font(.caption)
                    .foregroundStyle(theme.warningAccent)
                Text(lang.design.revisionProposedChanges)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.warningAccent)
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
        .background(theme.warningAccent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }
}
