import SwiftUI

// MARK: - Uncertainty Discussion Overlay

/// [Purpose] 특정 불확실성(DesignDecision)에 대해 director와 질의응답하며 해결안을 도출하는 오버레이.
/// [Trigger] `showUncertaintyDiscussOverlay == true` && `discussingUncertaintyId != nil`.
/// [Flow] 사용자가 불확실성 질문 → Uncertainty Discuss(이 오버레이) → director가 논의/해결안 제시 → 사용자 승인 → 해결안 반영.
struct UncertaintyDiscussOverlay: View {
    let uncertaintyId: UUID
    let uncertainty: DesignDecision
    @Bindable var vm: DesignWorkflowViewModel
    let onDismiss: () -> Void

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
        .onAppear { inputFocused = true }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.design.uncertaintyDiscussTitle)
                    .font(.headline)
                Text(uncertainty.title)
                    .font(.subheadline)
                    .foregroundStyle(theme.foregroundSecondary)
                    .lineLimit(1)
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
                    // Context card — shows uncertainty details
                    contextCard.id("context")

                    ForEach(vm.uncertaintyChatMessages) { msg in
                        discussionBubble(msg).id(msg.id)
                    }

                    if vm.isUncertaintyChatting, !vm.uncertaintyStreamOutput.isEmpty {
                        streamingBubble.id("unc-streaming")
                    }

                    if vm.isUncertaintyChatting, vm.uncertaintyStreamOutput.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(lang.design.thinking)
                                .font(.caption)
                                .foregroundStyle(theme.foregroundTertiary)
                        }
                        .padding(8)
                        .id("unc-thinking")
                    }

                    if !vm.isUncertaintyChatting, let resolution = vm.pendingUncertaintyResolution {
                        proposedResolutionCard(resolution).id("unc-resolution")
                    }

                    if vm.uncertaintyDiscussionCompleted {
                        completionCard.id("unc-complete")
                    }
                }
                .padding(16)
            }
            .onChange(of: vm.uncertaintyChatMessages.count) { _, _ in
                if let id = vm.uncertaintyChatMessages.last?.id {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .onChange(of: vm.uncertaintyDiscussionCompleted) { _, completed in
                if completed { withAnimation { proxy.scrollTo("unc-complete", anchor: .bottom) } }
            }
        }
    }

    // MARK: - Context Card

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                uncertaintyTypeBadge
                uncertaintyPriorityBadge
                Spacer()
            }
            Text(uncertainty.title)
                .font(.callout.weight(.medium))
                .foregroundStyle(theme.foregroundPrimary)
            Text(uncertainty.body)
                .font(.callout)
                .foregroundStyle(theme.foregroundSecondary)
            if !uncertainty.options.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lang.design.options)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.foregroundTertiary)
                    ForEach(uncertainty.options, id: \.self) { option in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").foregroundStyle(theme.foregroundTertiary)
                            Text(option)
                                .font(.callout)
                                .foregroundStyle(theme.foregroundPrimary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.warningSoftFill)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }

    // MARK: - Badges

    private var uncertaintyTypeBadge: some View {
        let (label, icon): (String, String) = switch uncertainty.escalationType ?? .question {
        case .question:        (lang.design.uncertaintyQuestion, "questionmark.circle")
        case .suggestion:      (lang.design.uncertaintySuggestion, "lightbulb")
        case .discussion:      (lang.design.uncertaintyDiscussion, "bubble.left.and.bubble.right")
        case .informationGap:  (lang.design.uncertaintyInfoGap, "info.circle")
        }
        return Label(label, systemImage: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(theme.warningAccent)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(theme.warningAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var uncertaintyPriorityBadge: some View {
        let (label, color): (String, Color) = switch uncertainty.priority {
        case .blocking:  (lang.design.uncertaintyBlocking, theme.criticalAccent)
        case .important: (lang.design.uncertaintyImportant, theme.warningAccent)
        case .advisory:  (lang.design.uncertaintyAdvisory, .secondary)
        }
        return Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 12) {
            if vm.uncertaintyDiscussionCompleted {
                Button { onDismiss() } label: {
                    Label(lang.common.done, systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.positiveAccent)
                .controlSize(.regular)
            } else {
                HStack(spacing: 8) {
                    TextField(lang.design.uncertaintyDiscussPlaceholder, text: $inputText, axis: .vertical)
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

                    if vm.pendingUncertaintyResolution != nil && !vm.isUncertaintyChatting {
                        Button { sendMessage() } label: {
                            Text(lang.design.uncertaintyAddComment).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            vm.approveUncertaintyResolution(for: uncertaintyId)
                        } label: {
                            Text(lang.design.uncertaintyApproveResolution).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    } else {
                        Button { sendMessage() } label: {
                            Text(lang.common.send).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isUncertaintyChatting)
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
        vm.sendUncertaintyMessage(text, for: uncertaintyId)
    }

    @ViewBuilder
    private func discussionBubble(_ msg: DesignChatMessage) -> some View {
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
            Text(vm.uncertaintyStreamOutput)
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

    private func proposedResolutionCard(_ resolution: DesignWorkflowViewModel.UncertaintyResolution) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(theme.positiveAccent)
                Text(lang.design.uncertaintyProposedResolution)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.positiveAccent)
            }
            if let selected = resolution.selectedOption {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(theme.accentPrimary)
                    Text(selected)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.foregroundPrimary)
                }
            }
            Text(resolution.summary)
                .font(.callout)
                .foregroundStyle(theme.foregroundPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actions = resolution.relatedActions, !actions.isEmpty {
                Divider()
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
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.positiveAccent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }

    private var completionCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.positiveAccent)
            Text(lang.design.uncertaintyResolutionComplete)
                .font(.callout.weight(.medium))
                .foregroundStyle(theme.positiveAccent)
            Spacer()
        }
        .padding(12)
        .background(theme.positiveAccent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }
}
