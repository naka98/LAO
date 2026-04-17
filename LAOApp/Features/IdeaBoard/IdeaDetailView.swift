import LAODomain
import LAOServices
import SwiftUI

/// Chat-style detail view for an idea. Shows message thread with tree-structured expert analyses.
struct IdeaDetailView: View {
    @State var viewModel: IdeaDetailViewModel
    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang
    @State private var inputText = ""
    @State private var expandedExpertIds: Set<UUID> = []
    @State private var expertInputTexts: [UUID: String] = [:]
    @State private var showDesignBriefOverlay = false

    var body: some View {
        VStack(spacing: 0) {
            // Chat thread
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { messageIndex, message in
                            treeMessageView(message, messageIndex: messageIndex)
                                .id(message.id)
                        }

                        // Streaming output while analyzing (hidden when brief overlay is active)
                        if viewModel.isAnalyzing, !viewModel.streamingOutput.isEmpty,
                           !showDesignBriefOverlay {
                            streamingBubble
                                .id("streaming")
                        }

                        // Show analyzing indicator when no expert is currently loading
                        // (hidden when brief overlay is active — overlay has its own loading state)
                        if viewModel.isAnalyzing, viewModel.streamingOutput.isEmpty,
                           !showDesignBriefOverlay,
                           !viewModel.messages.contains(where: { $0.experts?.contains(where: { $0.isLoading }) == true }) {
                            analyzingIndicator
                                .id("analyzing")
                        }

                        // Design failure row — inline retry inside the thread
                        if viewModel.designFailed, let err = viewModel.errorMessage {
                            designFailedRow(err)
                                .id("design-failed")
                        }
                    }
                    .padding(24)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
                .onChange(of: viewModel.streamingOutput) { _, _ in
                    withAnimation { proxy.scrollTo("streaming", anchor: .bottom) }
                }
                .onChange(of: viewModel.designFailed) { _, failed in
                    if failed {
                        withAnimation { proxy.scrollTo("design-failed", anchor: .bottom) }
                    }
                }
                .onChange(of: viewModel.isAnalyzing) { _, analyzing in
                    if analyzing {
                        withAnimation {
                            if viewModel.streamingOutput.isEmpty {
                                proxy.scrollTo("analyzing", anchor: .bottom)
                            } else {
                                proxy.scrollTo("streaming", anchor: .bottom)
                            }
                        }
                    }
                }
                .onAppear {
                    guard let lastId = viewModel.messages.last?.id else { return }
                    Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
            }

            // Error banner — only for non-design errors (design failure shown inline above)
            if let error = viewModel.errorMessage, !viewModel.designFailed {
                errorBanner(error)
            }

            Divider()

            // Synthesis CTA banner — shown whenever expert round is done and not analyzing
            if hasCompletedExpertRound && !viewModel.isAnalyzing {
                synthesisCtaBanner
            }

            // Input bar
            inputBar
        }
        .overlay {
            if viewModel.showReferencePhaseOverlay {
                referencePhaseOverlay()
                    .transition(.opacity)
            } else if showDesignBriefOverlay {
                designBriefOverlay()
                    .transition(.opacity)
            }
        }
        .task { await viewModel.loadFullIdea() }
        .onAppear { viewModel.lang = lang }
        .onChange(of: lang.common.save) { _, _ in viewModel.lang = lang }
        .onDisappear { Task { await viewModel.deleteIfEmpty() } }
    }

    // MARK: - Tree Message Router

    @ViewBuilder
    private func treeMessageView(_ message: IdeaMessage, messageIndex: Int) -> some View {
        switch message.role {
        case .user:
            userNode(message)
        case .design:
            if message.summary != nil {
                // Synthesis is a standalone conclusion — no tree rail
                synthesisBubble(message)
            } else if message.contextSummary != nil {
                // Context compression card is also standalone — no tree rail
                contextSummaryCard(message)
            } else if message.unifiedReferencesJSON != nil {
                // Reference data lives in the overlay — skip chat thread rendering
                EmptyView()
            } else {
                designSubtree(message, messageIndex: messageIndex)
            }
        }
    }

    // MARK: - User Node (Root)

    private func userNode(_ message: IdeaMessage) -> some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 4) {
                Text(message.content)
                    .font(AppTheme.Typography.body)
                    .padding(12)
                    .background(theme.accentPrimary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                    .textSelection(.enabled)
                Text(messageTimestamp(message.createdAt))
                    .font(AppTheme.Typography.detail)
                    .foregroundStyle(theme.foregroundMuted)
            }
        }
    }

    // MARK: - Design Subtree (depth 1)
    // Left rail (dot + vertical line) + Design bubble + Expert subtrees

    private func designSubtree(_ message: IdeaMessage, messageIndex: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Left rail: node dot at top, thin line extending down
            VStack(spacing: 0) {
                Circle()
                    .fill(theme.accentPrimary.opacity(0.45))
                    .frame(width: 8, height: 8)
                    .padding(.top, 9)
                Rectangle()
                    .fill(theme.accentPrimary.opacity(0.18))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 14)

            // Design content column
            VStack(alignment: .leading, spacing: 12) {
                // Design bubble (synthesis and contextSummary are routed before reaching here)
                if !message.content.isEmpty {
                    designBubble(message)
                }

                // Expert subtrees
                if let experts = message.experts, !experts.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(experts.enumerated()), id: \.element.id) { expertIndex, expert in
                            expertSubtree(
                                expert,
                                expertIndex: expertIndex,
                                messageIndex: messageIndex
                            )
                        }
                    }

                }
            }
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Panel Rearrangement (moved to inputBar area)

    @State private var showingRearrangeInput = false
    @State private var rearrangeReason = ""

    // MARK: - Expert Subtree (depth 2)
    // Card + inline follow-up conversation thread + input toggle

    private func expertSubtree(_ expert: IdeaExpert, expertIndex: Int, messageIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Expert card
            expertCard(expert, expertIndex: expertIndex, messageIndex: messageIndex)

            // Inline follow-up conversation thread
            if let followUps = expert.followUpMessages, !followUps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(followUps) { msg in
                        expertFollowUpBubble(msg, expert: expert)
                    }
                }
                .padding(.leading, 16)
            }

            // No step agent error banner
            if viewModel.expertFollowUpErrors[expert.id] != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Label(lang.ideaBoard.stepAgentNotConfigured, systemImage: "exclamationmark.triangle.fill")
                        .font(AppTheme.Typography.caption.weight(.medium))
                        .foregroundStyle(theme.warningAccent)
                    Text(lang.ideaBoard.stepAgentSetupInstruction)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundSecondary)
                    Button {
                        viewModel.retryExpertFollowUp(expertIndex: expertIndex, messageIndex: messageIndex)
                    } label: {
                        Label(lang.common.retry, systemImage: "arrow.counterclockwise")
                            .font(AppTheme.Typography.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(theme.warningAccent.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            }

            // Replying indicator + cancel
            if viewModel.replyingExperts.contains(expert.id) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(lang.ideaBoard.answering)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundSecondary)
                    Spacer()
                    Button {
                        if let text = viewModel.cancelExpertFollowUp(
                            expertIndex: expertIndex,
                            messageIndex: messageIndex
                        ) {
                            expertInputTexts[expert.id] = text
                            expandedExpertIds.insert(expert.id)
                        }
                    } label: {
                        Text(lang.common.cancel)
                            .font(AppTheme.Typography.caption.weight(.medium))
                            .foregroundStyle(theme.accentPrimary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 16)
            }

            // Inline input when expanded
            if expandedExpertIds.contains(expert.id) {
                expertInlineInput(expert, expertIndex: expertIndex, messageIndex: messageIndex)
            }

            // Per-expert inline references removed — unified reference phase handles this

            // Action buttons (shown when expert finished loading with no error)
            if !expert.isLoading && expert.errorMessage == nil {
                HStack(spacing: 12) {
                    Button {
                        if expandedExpertIds.contains(expert.id) {
                            expandedExpertIds.remove(expert.id)
                        } else {
                            expandedExpertIds.insert(expert.id)
                        }
                    } label: {
                        Label(
                            expandedExpertIds.contains(expert.id) ? lang.common.close : lang.ideaBoard.askQuestion,
                            systemImage: expandedExpertIds.contains(expert.id)
                                ? "chevron.up.circle" : "bubble.right"
                        )
                        .font(AppTheme.Typography.caption.weight(.medium))
                        .foregroundStyle(theme.accentPrimary)
                    }
                    .buttonStyle(.plain)

                    // Per-expert reference button removed — unified reference phase handles this
                }
            }
        }
    }

    // MARK: - Inline Reference Section

    private func inlineReferenceSection(_ expert: IdeaExpert) -> some View {
        let refs = viewModel.referencesForExpert(expert)
        return VStack(alignment: .leading, spacing: 6) {
            Label(lang.ideaBoard.reference, systemImage: "link")
                .font(AppTheme.Typography.caption.weight(.medium))
                .foregroundStyle(theme.foregroundTertiary)

            ForEach(refs) { ref in
                inlineReferenceRow(ref)
            }
        }
        .padding(10)
        .background(theme.surfaceSecondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
    }

    private func inlineReferenceRow(_ ref: ReferenceImage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Toggle checkbox
            Button {
                viewModel.toggleReference(ref.id)
            } label: {
                Image(systemName: isReferenceConfirmed(ref) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isReferenceConfirmed(ref) ? theme.accentPrimary : theme.foregroundTertiary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(ref.productName)
                    .font(AppTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(theme.foregroundPrimary)
                Text(ref.aspect)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(theme.foregroundSecondary)
                    .lineLimit(2)
            }

            Spacer()

            // Search link button
            if let urlString = ref.searchURL ?? ref.searchQuery.map({
                "https://www.google.com/search?tbm=isch&q=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0)"
            }), let url = URL(string: urlString) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.accentPrimary)
                }
                .buttonStyle(.plain)
                .help(lang.ideaBoard.referenceSearchTooltip)
            }
        }
    }

    /// Check if a reference is confirmed in the global referenceImages array.
    private func isReferenceConfirmed(_ ref: ReferenceImage) -> Bool {
        viewModel.referenceImages.first(where: {
            $0.productName.lowercased() == ref.productName.lowercased()
        })?.isConfirmed ?? true
    }

    // MARK: - Expert Follow-up Bubbles (Inline)

    @ViewBuilder
    private func expertFollowUpBubble(_ msg: IdeaExpertFollowUp, expert: IdeaExpert) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer(minLength: 30)
                Text(msg.content)
                    .font(AppTheme.Typography.label)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(theme.accentPrimary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                    .textSelection(.enabled)
            }
        case .expert:
            VStack(alignment: .leading, spacing: 6) {
                // Header: 이름 · 역할  [모델]
                HStack(spacing: 0) {
                    Text(expert.name)
                        .font(AppTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(theme.foregroundSecondary)
                    Text(" · ")
                        .font(AppTheme.Typography.detail)
                        .foregroundStyle(theme.foregroundMuted)
                    Text(expert.role)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundTertiary)
                        .lineLimit(1)
                    Spacer()
                    // 이 메시지에 기록된 모델 우선, 없으면 카드의 초기 모델 표시
                    let displayModel = msg.modelName ?? expert.modelName
                    if let model = displayModel {
                        Text(model)
                            .font(AppTheme.Typography.detail)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(theme.surfaceSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(theme.foregroundTertiary)
                    }
                }
                Text(msg.content)
                    .font(AppTheme.Typography.label)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(theme.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
        }
    }

    // MARK: - Expert Inline Input

    private func expertInputBinding(for expertId: UUID) -> Binding<String> {
        Binding(
            get: { expertInputTexts[expertId] ?? "" },
            set: { expertInputTexts[expertId] = $0 }
        )
    }

    private func expertInlineInput(_ expert: IdeaExpert, expertIndex: Int, messageIndex: Int) -> some View {
        HStack(spacing: 8) {
            TextField(lang.ideaBoard.askExpertPlaceholder, text: expertInputBinding(for: expert.id), axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(8)
                .background(theme.surfaceSubtle)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                .onKeyPress(keys: [.return]) { press in
                    if press.modifiers.contains(.shift) {
                        NSApp.sendAction(#selector(NSText.insertNewline(_:)), to: nil, from: nil)
                        return .handled
                    }
                    guard canSendToExpert(expert) else { return .handled }
                    handleExpertSend(expert: expert, expertIndex: expertIndex, messageIndex: messageIndex)
                    return .handled
                }

            Button {
                handleExpertSend(expert: expert, expertIndex: expertIndex, messageIndex: messageIndex)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(
                        canSendToExpert(expert) ? theme.accentPrimary : theme.accentPrimary.opacity(0.3)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSendToExpert(expert))
        }
    }

    private func canSendToExpert(_ expert: IdeaExpert) -> Bool {
        let text = expertInputTexts[expert.id] ?? ""
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.replyingExperts.contains(expert.id)
    }

    private func handleExpertSend(expert: IdeaExpert, expertIndex: Int, messageIndex: Int) {
        // onSubmit bypasses the button's disabled state — guard here too
        guard canSendToExpert(expert) else { return }
        let text = (expertInputTexts[expert.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        expertInputTexts[expert.id] = ""
        viewModel.sendMessageToExpert(
            text: text,
            expertIndex: expertIndex,
            messageIndex: messageIndex
        )
    }

    // MARK: - Expert Card

    private func expertCard(_ expert: IdeaExpert, expertIndex: Int, messageIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                if expert.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(
                        systemName: expert.errorMessage != nil
                            ? "exclamationmark.triangle.fill"
                            : "person.circle.fill"
                    )
                    .font(AppTheme.Typography.label)
                    .foregroundStyle(
                        expert.errorMessage != nil
                            ? theme.warningAccent
                            : theme.accentPrimary.opacity(0.7)
                    )
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(expert.name)
                        .font(AppTheme.Typography.label.weight(.semibold))
                        .lineLimit(1)
                    Text(expert.role)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundTertiary)
                        .lineLimit(1)
                }
                Spacer()
                expertStatusBadge(expert: expert, expertIndex: expertIndex, messageIndex: messageIndex)
            }
            .padding(.bottom, 8)

            Divider().padding(.bottom, 10)

            // Content
            if expert.isLoading {
                if let partial = expert.partialOpinion, !partial.isEmpty {
                    // Streaming text coming in
                    Text(partial)
                        .font(AppTheme.Typography.label)
                        .foregroundStyle(theme.foregroundSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ProgressView().controlSize(.small)
                }
            } else if let err = expert.errorMessage {
                Text(err)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(theme.foregroundSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(expert.opinion)
                    .font(AppTheme.Typography.label)
                    .foregroundStyle(theme.foregroundPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // AI limitations identified by this expert
                if let limsJSON = expert.limitationsJSON,
                   let limsData = limsJSON.data(using: .utf8),
                   let lims = try? JSONSerialization.jsonObject(with: limsData) as? [[String: Any]],
                   !lims.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(lang.ideaBoard.expertLimitations, systemImage: "exclamationmark.triangle")
                            .font(AppTheme.Typography.caption.weight(.medium))
                            .foregroundStyle(theme.warningAccent)
                        ForEach(Array(lims.prefix(3).enumerated()), id: \.offset) { _, lim in
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                    .font(AppTheme.Typography.caption)
                                    .foregroundStyle(theme.warningAccent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(lim["area"] as? String ?? "")
                                        .font(AppTheme.Typography.caption.weight(.semibold))
                                    Text(lim["description"] as? String ?? "")
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(theme.foregroundSecondary)
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }

                // Conversation history badge
                if let followUps = expert.followUpMessages, !followUps.isEmpty {
                    let exchangeCount = (followUps.count + 1) / 2
                    Label(lang.ideaBoard.conversationCountFormat(exchangeCount), systemImage: "bubble.left.and.bubble.right")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundTertiary)
                        .padding(.top, 8)
                }
            }
        }
        .padding(14)
        .background(
            expert.errorMessage != nil
                ? theme.warningAccent.opacity(0.05)
                : theme.surfacePrimary
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                .stroke(
                    expert.errorMessage != nil
                        ? theme.warningAccent.opacity(0.3)
                        : theme.borderSubtle,
                    lineWidth: 0.5
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func expertStatusBadge(expert: IdeaExpert, expertIndex: Int, messageIndex: Int) -> some View {
        if expert.isLoading {
            EmptyView()
        } else if expert.errorMessage != nil {
            Button {
                viewModel.retryExpert(expertIndex: expertIndex, messageIndex: messageIndex)
            } label: {
                Label(lang.common.retry, systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        } else if let modelName = expert.modelName {
            if let fallback = expert.fallbackInfo {
                Text(modelName)
                    .font(AppTheme.Typography.detail)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.orange)
                    .help(fallback)
            } else {
                Text(modelName)
                    .font(AppTheme.Typography.detail)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.surfaceSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(theme.foregroundTertiary)
            }
        }
    }

    private func designFailedRow(_ errorMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(theme.warningAccent)
                Text(lang.ideaBoard.designAnalysisFailed)
                    .font(AppTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(theme.warningAccent)
                Spacer()
                Button {
                    viewModel.analyze()
                } label: {
                    Label(lang.ideaBoard.reanalyze, systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text(errorMessage)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(theme.foregroundSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(theme.warningAccent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                .stroke(theme.warningAccent.opacity(0.25), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Design Bubbles

    private func designBubble(_ message: IdeaMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(theme.accentPrimary)
                Text(lang.common.design)
                    .font(AppTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(theme.accentPrimary)
                Text(messageTimestamp(message.createdAt))
                    .font(AppTheme.Typography.detail)
                    .foregroundStyle(theme.foregroundMuted)
                Spacer()
                if let modelName = message.modelName {
                    if let fallback = message.fallbackInfo {
                        Text(modelName)
                            .font(AppTheme.Typography.detail)
                            .foregroundStyle(.orange)
                            .help(fallback)
                    } else {
                        Text(modelName)
                            .font(AppTheme.Typography.detail)
                            .foregroundStyle(theme.foregroundMuted)
                    }
                }
            }
            Text(message.content)
                .font(AppTheme.Typography.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(theme.accentPrimary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Synthesis card — shown when Design has converged on a direction (message.summary != nil).
    private func synthesisBubble(_ message: IdeaMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(theme.positiveAccent)
                Text(lang.ideaBoard.designSynthesis)
                    .font(AppTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(theme.positiveAccent)
                Text(messageTimestamp(message.createdAt))
                    .font(AppTheme.Typography.detail)
                    .foregroundStyle(theme.foregroundMuted)
                Spacer()
                if let modelName = message.modelName {
                    Text(modelName)
                        .font(AppTheme.Typography.detail)
                        .foregroundStyle(theme.foregroundMuted)
                }
            }

            if let direction = message.summary {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lang.ideaBoard.recommendedDirection)
                        .font(AppTheme.Typography.caption.weight(.medium))
                        .foregroundStyle(theme.foregroundSecondary)
                    Text(direction)
                        .font(AppTheme.Typography.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(theme.positiveAccent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            }

            if !message.content.isEmpty {
                Text(message.content)
                    .font(AppTheme.Typography.label)
                    .foregroundStyle(theme.foregroundPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            if viewModel.isBriefReady {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showDesignBriefOverlay = true
                    }
                } label: {
                    Label(lang.ideaBoard.reviewBrief, systemImage: "doc.text.magnifyingglass")
                        .font(AppTheme.Typography.label.weight(.medium))
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(viewModel.isConverting)
            } else if viewModel.isBrdGenerating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(lang.ideaBoard.generatingBrief)
                        .font(AppTheme.Typography.label)
                        .foregroundStyle(theme.foregroundSecondary)
                }
            }
        }
        .padding(16)
        .background(theme.positiveAccent.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                .stroke(theme.positiveAccent.opacity(0.25), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Context Summary Card

    @State private var expandedSummaryIds: Set<UUID> = []

    private func contextSummaryCard(_ message: IdeaMessage) -> some View {
        let isExpanded = expandedSummaryIds.contains(message.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if isExpanded {
                    expandedSummaryIds.remove(message.id)
                } else {
                    expandedSummaryIds.insert(message.id)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundSecondary)
                    Text(lang.ideaBoard.conversationSummary)
                        .font(AppTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(theme.foregroundSecondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(AppTheme.Typography.detail)
                        .foregroundStyle(theme.foregroundTertiary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded, let summary = message.contextSummary {
                Text(summary)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(theme.foregroundPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(theme.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .stroke(theme.borderSubtle, lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Streaming & Loading

    private var streamingBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(viewModel.analysisStatus)
                    .font(AppTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(theme.accentPrimary)
            }
            Text(viewModel.streamingOutput)
                .font(AppTheme.Typography.label)
                .foregroundStyle(theme.foregroundSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(20)
        }
        .padding(16)
        .background(theme.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
    }

    private var analyzingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(viewModel.analysisStatus)
                .font(AppTheme.Typography.label)
                .foregroundStyle(theme.foregroundSecondary)
        }
        .padding(16)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            // URL hint
            if inputContainsURL {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(AppTheme.Typography.detail)
                        .foregroundStyle(theme.accentPrimary)
                    Text(lang.ideaBoard.urlDetectedHint)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundSecondary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 4)
            }

            HStack(spacing: 8) {
                // Panel rearrangement button with popover
                if hasCompletedExpertRound && !viewModel.isAnalyzing {
                    Button {
                        showingRearrangeInput.toggle()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(AppTheme.Typography.body)
                            .foregroundStyle(theme.accentPrimary)
                    }
                    .buttonStyle(.plain)
                    .help(lang.ideaBoard.rearrangePanelHelp)
                    .popover(isPresented: $showingRearrangeInput, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(lang.ideaBoard.rearrangePanelHelp)
                                .font(AppTheme.Typography.label.weight(.semibold))
                            TextField(lang.ideaBoard.rearrangeReasonPlaceholder, text: $rearrangeReason, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(AppTheme.Typography.caption)
                                .lineLimit(1...3)
                                .padding(8)
                                .background(theme.surfaceSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                                .frame(minWidth: 240)
                            HStack {
                                Spacer()
                                Button {
                                    showingRearrangeInput = false
                                    rearrangeReason = ""
                                } label: {
                                    Text(lang.common.cancel)
                                        .font(AppTheme.Typography.caption)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    showingRearrangeInput = false
                                    let reason = rearrangeReason
                                    rearrangeReason = ""
                                    viewModel.rearrangePanel(reason: reason)
                                } label: {
                                    Text(lang.ideaBoard.rearrangeLabel)
                                        .font(AppTheme.Typography.caption.weight(.medium))
                                }
                                .buttonStyle(PrimaryActionButtonStyle())
                            }
                        }
                        .padding(14)
                    }
                }

                // Attachment button
                Button {
                    openAttachmentPanel()
                } label: {
                    Image(systemName: "paperclip")
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(theme.foregroundSecondary)
                }
                .buttonStyle(.plain)
                .help(lang.ideaBoard.attachFileHelp)

                TextField(
                    viewModel.messages.isEmpty ? lang.ideaBoard.describeIdeaPlaceholder : lang.ideaBoard.askExpertsPlaceholder,
                    text: $inputText,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(10)
                .background(theme.surfaceSubtle)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                .onKeyPress(keys: [.return]) { press in
                    if press.modifiers.contains(.shift) {
                        NSApp.sendAction(#selector(NSText.insertNewline(_:)), to: nil, from: nil)
                        return .handled
                    }
                    guard canSend else { return .handled }
                    handleSend()
                    return .handled
                }

                if viewModel.isAnalyzing {
                    Button {
                        Task { await viewModel.stopAnalysis() }
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(AppTheme.Typography.sectionTitle)
                            .foregroundStyle(theme.criticalAccent)
                    }
                    .buttonStyle(.plain)
                    .help(lang.common.stop)
                } else {
                    Button {
                        handleSend()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(AppTheme.Typography.sectionTitle)
                            .foregroundStyle(
                                canSend ? theme.accentPrimary : theme.accentPrimary.opacity(0.3)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private func openAttachmentPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .pdf, .plainText, .json, .sourceCode]
        panel.message = lang.ideaBoard.selectAttachment
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            let tag = "\n" + lang.ideaBoard.attachmentFormat(path)
            inputText += tag
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isAnalyzing
    }

    private var hasCompletedExpertRound: Bool {
        viewModel.messages.contains {
            $0.role == .design && ($0.experts?.contains { !$0.isLoading } ?? false)
        }
    }

    private var inputContainsURL: Bool {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(inputText.startIndex..., in: inputText)
        return detector?.firstMatch(in: inputText, range: range) != nil
    }

    // MARK: - Synthesis CTA Banner

    private var hasBriefGenerated: Bool {
        viewModel.isBriefReady || viewModel.isBrdReady
    }

    private var synthesisCtaBanner: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(hasBriefGenerated ? lang.ideaBoard.reviewOtherDirections : lang.ideaBoard.decideDirection)
                    .font(AppTheme.Typography.label.weight(.semibold))
                Text(hasBriefGenerated
                     ? lang.ideaBoard.briefAfterDiscussion
                     : lang.ideaBoard.referenceGuidance)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(theme.foregroundSecondary)
                    .lineLimit(2)
            }
            Spacer()
            if !hasBriefGenerated {
                // Reference phase entry
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.showReferencePhaseOverlay = true
                    }
                    viewModel.requestUnifiedReferences()
                } label: {
                    Label(lang.ideaBoard.referenceExplore, systemImage: "photo.on.rectangle.angled")
                        .font(AppTheme.Typography.label.weight(.medium))
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
            // Brief generation (skip reference or regenerate)
            if hasBriefGenerated {
                Button {
                    let guide = inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : inputText
                    if guide != nil { inputText = "" }
                    viewModel.requestSynthesis(guide: guide)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showDesignBriefOverlay = true
                    }
                } label: {
                    Label(lang.ideaBoard.regenerateBrief, systemImage: "arrow.triangle.2.circlepath")
                        .font(AppTheme.Typography.label.weight(.medium))
                }
                .buttonStyle(PrimaryActionButtonStyle())
            } else {
                Button {
                    let guide = inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : inputText
                    if guide != nil { inputText = "" }
                    viewModel.requestSynthesis(guide: guide)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showDesignBriefOverlay = true
                    }
                } label: {
                    Label(lang.ideaBoard.generateBriefDirectly, systemImage: "doc.badge.arrow.up")
                        .font(AppTheme.Typography.label.weight(.medium))
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(theme.accentPrimary.opacity(0.06))
    }

    private func handleSend() {
        let text = inputText
        inputText = ""
        let hasExpertPanel = viewModel.messages.contains {
            $0.role == .design && ($0.experts?.isEmpty == false)
        }
        if hasExpertPanel {
            viewModel.sendMessage(text)
        } else {
            viewModel.sendAndAnalyze(text)
        }
    }

    // MARK: - Reference Phase Overlay

    private func referencePhaseOverlay() -> some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {}

            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.accentPrimary)
                    Text(lang.ideaBoard.referenceExplore)
                        .font(AppTheme.Typography.cardTitle.weight(.semibold))
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.skipReferencePhase()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(theme.foregroundTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

                Divider()

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if viewModel.isGeneratingUnifiedReferences {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .controlSize(.regular)
                                Text(lang.ideaBoard.referenceSearching)
                                    .font(AppTheme.Typography.caption)
                                    .foregroundStyle(theme.foregroundSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            // LLM explanation text
                            if let lastRefMsg = viewModel.messages.last(where: { $0.unifiedReferencesJSON != nil }) {
                                Text(lastRefMsg.content)
                                    .font(AppTheme.Typography.body)
                                    .foregroundStyle(theme.foregroundPrimary)
                            }

                            // References grouped by category
                            referenceCategoryGroup(.visual, title: lang.ideaBoard.referenceCategoryVisual)
                            referenceCategoryGroup(.experience, title: lang.ideaBoard.referenceCategoryExperience)
                            referenceCategoryGroup(.implementation, title: lang.ideaBoard.referenceCategoryImplementation)
                        }
                    }
                    .padding(24)
                }

                Divider()

                // Feedback + actions
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        TextField(lang.ideaBoard.referenceFeedbackPlaceholder,
                                  text: $viewModel.unifiedReferenceFeedback)
                            .textFieldStyle(.roundedBorder)
                            .font(AppTheme.Typography.body)

                        Button {
                            let feedback = viewModel.unifiedReferenceFeedback
                            viewModel.unifiedReferenceFeedback = ""
                            viewModel.requestUnifiedReferences(feedback: feedback)
                        } label: {
                            Label(lang.ideaBoard.referenceRetry, systemImage: "arrow.triangle.2.circlepath")
                                .font(AppTheme.Typography.label.weight(.medium))
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .disabled(viewModel.unifiedReferenceFeedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || viewModel.isGeneratingUnifiedReferences)
                    }

                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.skipReferencePhase()
                            }
                        } label: {
                            Text(lang.ideaBoard.referenceSkip)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .controlSize(.large)

                        Button {
                            viewModel.confirmReferencesAndProceed()
                            viewModel.requestSynthesis(guide: nil)
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showDesignBriefOverlay = true
                            }
                        } label: {
                            Label(lang.ideaBoard.referenceProceed, systemImage: "arrow.right.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryActionButtonStyle())
                        .controlSize(.large)
                        .disabled(viewModel.referenceImages.isEmpty || viewModel.isGeneratingUnifiedReferences)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .frame(minWidth: 500, maxWidth: 650, minHeight: 400, maxHeight: 600)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        }
    }

    /// Group references by category for the reference phase overlay.
    private func referenceCategoryGroup(_ category: ReferenceCategory, title: String) -> some View {
        let refs = viewModel.referenceImages.filter { $0.category == category }
        return Group {
            if !refs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(AppTheme.Typography.label.weight(.semibold))
                        .foregroundStyle(theme.foregroundSecondary)
                    ForEach(refs) { ref in
                        inlineReferenceRow(ref)
                    }
                }
                .padding(12)
                .background(theme.surfaceSecondary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            }
        }
    }

    // MARK: - Timestamp Formatting

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd HH:mm"
        return f
    }()

    private func messageTimestamp(_ date: Date) -> String {
        IdeaDetailView.timestampFormatter.string(from: date)
    }

    /// Render parsed BRD content in readable sections.
    @ViewBuilder
    private func brdContentView(_ brd: IdeaDetailViewModel.BRDDisplayModel) -> some View {
        if !brd.problemStatement.isEmpty {
            brdSection(title: lang.ideaBoard.brdProblemStatement) {
                Text(brd.problemStatement)
                    .font(AppTheme.Typography.label)
                    .foregroundStyle(theme.foregroundPrimary)
            }
        }

        if !brd.targetUsers.isEmpty {
            brdSection(title: lang.ideaBoard.brdTargetUsers) {
                ForEach(Array(brd.targetUsers.enumerated()), id: \.offset) { _, user in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name).font(AppTheme.Typography.label.weight(.semibold))
                        Text(user.description).font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundSecondary)
                        if !user.needs.isEmpty {
                            Text(user.needs.map { "• \($0)" }.joined(separator: "\n"))
                                .font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundSecondary)
                        }
                    }
                }
            }
        }

        if !brd.businessObjectives.isEmpty {
            brdSection(title: lang.ideaBoard.brdBusinessObjectives) {
                ForEach(brd.businessObjectives, id: \.self) { obj in
                    Label(obj, systemImage: "target")
                        .font(AppTheme.Typography.caption)
                }
            }
        }

        if !brd.scopeInScope.isEmpty || !brd.scopeOutOfScope.isEmpty {
            brdSection(title: lang.ideaBoard.brdScope) {
                if !brd.scopeInScope.isEmpty {
                    Text(lang.ideaBoard.brdInScope).font(AppTheme.Typography.caption.weight(.medium)).foregroundStyle(theme.positiveAccent)
                    ForEach(brd.scopeInScope, id: \.self) { item in
                        Text("• \(item)").font(AppTheme.Typography.caption)
                    }
                }
                if !brd.scopeOutOfScope.isEmpty {
                    Text(lang.ideaBoard.brdOutOfScope).font(AppTheme.Typography.caption.weight(.medium)).foregroundStyle(theme.warningAccent)
                        .padding(.top, 4)
                    ForEach(brd.scopeOutOfScope, id: \.self) { item in
                        Text("• \(item)").font(AppTheme.Typography.caption)
                    }
                }
                if !brd.mvpBoundary.isEmpty {
                    Text(lang.ideaBoard.brdMvpBoundary).font(AppTheme.Typography.caption.weight(.medium))
                        .padding(.top, 4)
                    Text(brd.mvpBoundary).font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundSecondary)
                }
            }
        }

        if !brd.constraints.isEmpty {
            brdSection(title: lang.ideaBoard.brdConstraints) {
                ForEach(brd.constraints, id: \.self) { c in
                    Text("• \(c)").font(AppTheme.Typography.caption)
                }
            }
        }

        if !brd.assumptions.isEmpty {
            brdSection(title: lang.ideaBoard.brdAssumptions) {
                ForEach(brd.assumptions, id: \.self) { a in
                    Text("• \(a)").font(AppTheme.Typography.caption)
                }
            }
        }
    }

    private func brdSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTheme.Typography.caption.weight(.semibold))
                .foregroundStyle(theme.foregroundSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.surfaceSubtle.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
    }

    // MARK: - Design Brief Overlay (Step 3)

    private func designBriefOverlay() -> some View {
        let brief = viewModel.designBriefSummary
        return ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {}

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.title3)
                        .foregroundStyle(theme.accentPrimary)
                    Text(lang.ideaBoard.designBriefTitle)
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

                Divider()

                // Brief content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if viewModel.isBrdGenerating {
                            // Loading state — Brief LLM is generating
                            VStack(spacing: 12) {
                                ProgressView().controlSize(.large)
                                Text(lang.ideaBoard.generatingBrief)
                                    .font(AppTheme.Typography.label)
                                    .foregroundStyle(theme.foregroundSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else if let error = viewModel.brdError {
                            // Error state
                            VStack(spacing: 12) {
                                Label {
                                    Text(error)
                                        .font(AppTheme.Typography.label)
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(theme.warningAccent)
                                }
                                Button(lang.common.retry) {
                                    viewModel.retryBRDGeneration()
                                }
                                .buttonStyle(SecondaryActionButtonStyle())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                        } else {

                        Text(lang.ideaBoard.designBriefMessage)
                            .font(AppTheme.Typography.label)
                            .foregroundStyle(theme.foregroundSecondary)

                        // Direction
                        if !brief.direction.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lang.ideaBoard.designBriefDirection)
                                    .font(AppTheme.Typography.caption.weight(.medium))
                                    .foregroundStyle(theme.foregroundSecondary)
                                Text(brief.direction)
                                    .font(AppTheme.Typography.body.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(theme.positiveAccent.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                        }

                        // Key Decisions from Design Brief (if available)
                        if let parsedBrief = viewModel.parsedDesignBrief,
                           !parsedBrief.keyDecisions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(lang.ideaBoard.designBriefKeyDecisions)
                                    .font(AppTheme.Typography.caption.weight(.medium))
                                    .foregroundStyle(theme.foregroundSecondary)
                                ForEach(Array(parsedBrief.keyDecisions.prefix(5).enumerated()), id: \.offset) { _, decision in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "checkmark.diamond.fill")
                                            .font(.caption2).foregroundStyle(theme.accentPrimary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(decision.topic)
                                                .font(AppTheme.Typography.caption.weight(.semibold))
                                            Text(decision.chosen)
                                                .font(AppTheme.Typography.caption)
                                                .foregroundStyle(theme.foregroundSecondary)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(theme.surfaceSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                        }

                        // Problem statement + Target users (from BRD)
                        if let brd = viewModel.parsedBRD {
                            if !brd.problemStatement.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(lang.ideaBoard.brdProblemStatement)
                                        .font(AppTheme.Typography.caption.weight(.medium))
                                        .foregroundStyle(theme.foregroundSecondary)
                                    Text(brd.problemStatement)
                                        .font(AppTheme.Typography.label)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(theme.surfaceSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                            }

                            if !brd.targetUsers.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(lang.ideaBoard.brdTargetUsers)
                                        .font(AppTheme.Typography.caption.weight(.medium))
                                        .foregroundStyle(theme.foregroundSecondary)
                                    ForEach(Array(brd.targetUsers.prefix(3).enumerated()), id: \.offset) { _, user in
                                        Text("• \(user.name): \(user.description)")
                                            .font(AppTheme.Typography.caption)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(theme.surfaceSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                            }
                        }

                        // Scope summary (from BRD, if available)
                        if let brd = viewModel.parsedBRD,
                           !brd.scopeInScope.isEmpty || !brd.scopeOutOfScope.isEmpty {
                            HStack(alignment: .top, spacing: 12) {
                                if !brd.scopeInScope.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(lang.ideaBoard.designBriefInScope)
                                            .font(AppTheme.Typography.caption.weight(.medium))
                                            .foregroundStyle(theme.positiveAccent)
                                        ForEach(brd.scopeInScope.prefix(3), id: \.self) { item in
                                            Text("• \(item)").font(.caption)
                                        }
                                    }
                                }
                                if !brd.scopeOutOfScope.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(lang.ideaBoard.designBriefOutOfScope)
                                            .font(AppTheme.Typography.caption.weight(.medium))
                                            .foregroundStyle(theme.foregroundMuted)
                                        ForEach(brd.scopeOutOfScope.prefix(3), id: \.self) { item in
                                            Text("• \(item)").font(.caption)
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Execution Context (AI limitations aggregated in Brief)
                        if let parsedBrief = viewModel.parsedDesignBrief,
                           !parsedBrief.executionLimitations.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(lang.ideaBoard.designBriefExecutionContext)
                                    .font(AppTheme.Typography.caption.weight(.medium))
                                    .foregroundStyle(theme.foregroundSecondary)
                                ForEach(Array(parsedBrief.executionLimitations.prefix(5).enumerated()), id: \.offset) { _, limitation in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.caption2).foregroundStyle(theme.warningAccent)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(limitation.area)
                                                .font(AppTheme.Typography.caption.weight(.semibold))
                                            Text(limitation.description)
                                                .font(AppTheme.Typography.caption)
                                                .foregroundStyle(theme.foregroundSecondary)
                                            if let hint = limitation.workaroundHint {
                                                Text(hint)
                                                    .font(AppTheme.Typography.caption)
                                                    .foregroundStyle(theme.accentPrimary)
                                                    .italic()
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(theme.warningAccent.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                        }

                        // Stats grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            briefStatRow(label: lang.ideaBoard.designBriefExperts, value: "\(brief.expertCount)")
                            briefStatRow(label: lang.ideaBoard.designBriefMessages, value: "\(brief.messageCount)")
                            briefStatRow(label: lang.ideaBoard.designBriefEntities, value: "\(brief.entityCount)")
                            briefStatRow(label: lang.ideaBoard.designBriefBrdIncluded, value: brief.hasBRD ? "✓" : "—")
                        }

                        } // end else (content loaded)
                    }
                    .padding(24)
                }

                Divider()

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDesignBriefOverlay = false
                        }
                    } label: {
                        Text(lang.ideaBoard.designBriefBack)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .controlSize(.large)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDesignBriefOverlay = false
                        }
                        Task { await viewModel.convertToRequest() }
                    } label: {
                        Label(lang.ideaBoard.designBriefStart, systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .controlSize(.large)
                    .disabled(viewModel.isConverting || viewModel.isBrdGenerating || !viewModel.isBriefReady)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .frame(minWidth: 400, maxWidth: 550, minHeight: 300, maxHeight: 450)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 4)
        }
    }

    private func briefStatRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(theme.foregroundSecondary)
            Spacer()
            Text(value)
                .font(AppTheme.Typography.label.weight(.medium).monospacedDigit())
                .foregroundStyle(theme.foregroundPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.surfaceSubtle.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.criticalAccent)
            Text(message)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(theme.foregroundSecondary)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.foregroundMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(theme.criticalAccent.opacity(0.1))
    }


}
