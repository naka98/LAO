import AppKit
import LAODomain
import SwiftUI

// `GraphNode` and `GraphEdge` are explicitly module-qualified throughout this file
// because LAOApp/Features/Design/WorkGraphView.swift defines internal types of the
// same name for the v0.7 work graph visualization. Until v0.7 is retired we keep the
// two namespaces isolated by qualifying our v0.8 references.

/// v0.8 mindmap canvas — Phase 2 Step 3.
///
/// Renders the seed (idea title) at center with 6 weak starter roots arranged radially.
/// Nodes fade in sequentially on first appearance and expand in place when tapped.
/// In Step 3 the expanded card hosts a real in-node conversation: user messages flow to
/// the specifier step and the reply is appended to the thread.
struct NodeGraphWorkflowView: View {
    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang
    @State private var viewModel: NodeGraphWorkflowViewModel
    @State private var visibleNodeIds: Set<UUID> = []
    @State private var expandedNodeId: UUID?
    @State private var chatDrafts: [UUID: String] = [:]
    /// Candidate node id currently the target of a pending merge or discard confirmation.
    /// Drives the SwiftUI confirmationDialog presentation — set when the user picks the
    /// "더보기" menu item, cleared when they confirm or dismiss.
    @State private var pendingMergeNodeId: UUID?
    @State private var pendingDiscardNodeId: UUID?
    /// URL of the most recent successful export. Drives the success alert + "Reveal in
    /// Finder" action (Step 5d-1). Cleared when the user dismisses the alert.
    @State private var lastExportURL: URL?

    private static let seedRevealDelay: Duration = .milliseconds(200)
    private static let starterRevealGap: Duration = .milliseconds(280)

    init(container: AppContainer, project: Project, ideaId: UUID, ideaTitle: String) {
        _viewModel = State(wrappedValue: NodeGraphWorkflowViewModel(
            container: container,
            project: project,
            ideaId: ideaId,
            ideaTitle: ideaTitle
        ))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if viewModel.isLoading {
                    ProgressView(lang.ideaBoard.nodeGraphLoadingStatus)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let seed = viewModel.seedNode {
                    canvas(seed: seed, starters: viewModel.starterNodes)
                } else {
                    ContentUnavailableView(
                        lang.ideaBoard.designModeGraphPlaceholderTitle,
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                }
            }

            if viewModel.seedNode != nil {
                exportButton
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }
        }
        .task {
            await viewModel.loadOrBootstrap()
            await runFadeInSequence()
        }
        .task(id: expandedNodeId) {
            if let id = expandedNodeId {
                await viewModel.loadMessagesIfNeeded(nodeId: id)
            }
        }
        .onChange(of: viewModel.nodes.count) {
            // New nodes (e.g., approved proposals during this session) get revealed immediately
            // so the existing chip-opacity transition fades them in without a per-node delay.
            for node in viewModel.nodes where !visibleNodeIds.contains(node.id) {
                visibleNodeIds.insert(node.id)
            }
        }
        .modifier(ExportSuccessModifier(
            lastExportURL: $lastExportURL,
            title: lang.ideaBoard.nodeGraphExportSuccessTitle,
            messageFormat: lang.ideaBoard.nodeGraphExportSuccessPathFormat,
            revealLabel: lang.common.revealInFinder,
            doneLabel: lang.common.done
        ))
        .modifier(ErrorAlertModifier(viewModel: viewModel, confirmLabel: lang.common.confirm))
        .modifier(MergeConfirmationModifier(
            viewModel: viewModel,
            pendingId: $pendingMergeNodeId,
            confirmLabel: lang.ideaBoard.nodeGraphCandidateMergeConfirm,
            cancelLabel: lang.common.cancel,
            message: lang.ideaBoard.nodeGraphCandidateMergeMessage,
            titleFormat: lang.ideaBoard.nodeGraphCandidateMergeConfirmTitleFormat
        ))
        .modifier(DiscardConfirmationModifier(
            viewModel: viewModel,
            pendingId: $pendingDiscardNodeId,
            title: lang.ideaBoard.nodeGraphCandidateDiscardConfirmTitle,
            message: lang.ideaBoard.nodeGraphCandidateDiscardMessage,
            confirmLabel: lang.ideaBoard.nodeGraphCandidateDiscard,
            cancelLabel: lang.common.cancel
        ))
    }

    // MARK: - Export Button (Step 5d-1)

    /// Floating action button anchored to the canvas's top-right corner. Disabled while an
    /// export is already in flight; otherwise kicks off `viewModel.exportGraph()` and
    /// surfaces the resulting file path through the success modifier.
    @ViewBuilder
    private var exportButton: some View {
        Button {
            Task { @MainActor in
                do {
                    let url = try await viewModel.exportGraph()
                    lastExportURL = url
                } catch {
                    viewModel.errorAlert = ErrorAlert(
                        title: lang.ideaBoard.nodeGraphExportFailedFormat(error.localizedDescription),
                        detail: ""
                    )
                }
            }
        } label: {
            HStack(spacing: 4) {
                if viewModel.isExporting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                }
                Text(lang.ideaBoard.nodeGraphExportButton)
                    .font(AppTheme.Typography.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(theme.surfaceSubtle)
                    .overlay(
                        Capsule().stroke(theme.foregroundMuted.opacity(0.35), lineWidth: 1)
                    )
            )
            .foregroundStyle(theme.foregroundSecondary)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isExporting)
    }

    // MARK: - Canvas

    /// Step 5a canvas: seed center, starter ring, and an arbitrary-depth `parentChild` tree
    /// rooted at each starter. Positions are computed once per layout pass and looked up by
    /// node id so adding a child triggers a single SwiftUI redraw with the new position.
    @ViewBuilder
    private func canvas(seed: LAODomain.GraphNode, starters: [LAODomain.GraphNode]) -> some View {
        GeometryReader { geo in
            let positions = computePositions(in: geo.size, seed: seed, starters: starters)

            ZStack {
                // Edges: render every `parentChild` edge generically. Visibility tracks the
                // destination node so newly-revealed children get their line at the same time.
                // Sibling edges aren't drawn in Step 5b — candidate dimming + dashed parentChild
                // already communicates the alternative-branch relationship at this scale.
                ForEach(viewModel.edges) { edge in
                    if edge.kind == .parentChild,
                       let fromPos = positions[edge.fromNodeId],
                       let toPos = positions[edge.toNodeId] {
                        let toNode = viewModel.nodes.first { $0.id == edge.toNodeId }
                        let dashed = toNode.map(isCandidate) ?? false
                        edgeLine(from: fromPos, to: toPos, isCandidate: dashed)
                            .opacity(visibleNodeIds.contains(edge.toNodeId) ? 1 : 0)
                            .animation(.easeInOut(duration: 0.5), value: visibleNodeIds)
                    }
                }

                if expandedNodeId != nil {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { expandedNodeId = nil }
                        .zIndex(5)
                }

                // Chips: render every node from a single list driven off the positions dict.
                ForEach(viewModel.nodes) { node in
                    if let pos = positions[node.id] {
                        nodeChip(node: node)
                            .position(pos)
                            .zIndex(expandedNodeId == node.id ? 10 : 1)
                    }
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: expandedNodeId)
        }
    }

    // MARK: - Layout (Step 5a)

    /// Walk the tree rooted at `seed` and assign every reachable node a canvas position.
    /// - Seed sits at the geometric center.
    /// - Starters sit on a fixed-radius ring, evenly spaced starting at 12 o'clock.
    /// - All other descendants spread outward along their parent's radial direction,
    ///   fanning out on a small arc per generation.
    private func computePositions(
        in size: CGSize,
        seed: LAODomain.GraphNode,
        starters: [LAODomain.GraphNode]
    ) -> [UUID: CGPoint] {
        var positions: [UUID: CGPoint] = [:]
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let starterRadius = min(size.width, size.height) * 0.32
        let descendantStep = starterRadius * 0.55

        positions[seed.id] = center

        let starterPositions = computeStarterPositions(count: starters.count, center: center, radius: starterRadius)
        for (idx, starter) in starters.enumerated() where idx < starterPositions.count {
            positions[starter.id] = starterPositions[idx]
        }

        for starter in starters {
            if let starterPos = positions[starter.id] {
                layoutDescendants(
                    parent: starter,
                    parentPos: starterPos,
                    center: center,
                    step: descendantStep,
                    into: &positions
                )
            }
        }
        return positions
    }

    /// Recurse into `parentChild` children of `parent`, spreading them on a small arc centered
    /// on the parent's radial direction from the seed. Single-child case stays on the radial.
    private func layoutDescendants(
        parent: LAODomain.GraphNode,
        parentPos: CGPoint,
        center: CGPoint,
        step: CGFloat,
        into positions: inout [UUID: CGPoint]
    ) {
        let children = viewModel.children(of: parent.id)
        guard !children.isEmpty else { return }

        let dx = parentPos.x - center.x
        let dy = parentPos.y - center.y
        let parentAngle = atan2(Double(dy), Double(dx))
        let parentRadius = sqrt(Double(dx) * Double(dx) + Double(dy) * Double(dy))
        let childRadius = parentRadius + Double(step)
        let spread: Double = .pi / 5 // 36° fan

        for (i, child) in children.enumerated() {
            let angle: Double
            if children.count == 1 {
                angle = parentAngle
            } else {
                let frac = Double(i) / Double(children.count - 1)
                angle = parentAngle - spread / 2 + spread * frac
            }
            let pos = CGPoint(
                x: center.x + CGFloat(cos(angle) * childRadius),
                y: center.y + CGFloat(sin(angle) * childRadius)
            )
            positions[child.id] = pos
            layoutDescendants(parent: child, parentPos: pos, center: center, step: step, into: &positions)
        }
    }

    /// Distributes `count` points evenly on a circle, starting at the top (12 o'clock)
    /// and proceeding clockwise. Reused by the starter ring.
    private func computeStarterPositions(count: Int, center: CGPoint, radius: Double) -> [CGPoint] {
        guard count > 0 else { return [] }
        let step = 2 * Double.pi / Double(count)
        return (0..<count).map { i in
            let angle = -Double.pi / 2 + step * Double(i)
            return CGPoint(
                x: center.x + CGFloat(cos(angle) * radius),
                y: center.y + CGFloat(sin(angle) * radius)
            )
        }
    }

    /// Solid line for mainline edges, dashed for edges that terminate on a candidate branch
    /// (Step 5b). Caller decides which style by passing `isCandidate=true` when the destination
    /// node's `branchRole == .candidate`.
    @ViewBuilder
    private func edgeLine(from: CGPoint, to: CGPoint, isCandidate: Bool = false) -> some View {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(
            theme.foregroundMuted.opacity(0.45),
            style: StrokeStyle(
                lineWidth: 1,
                dash: isCandidate ? [3, 3] : []
            )
        )
    }

    @ViewBuilder
    private func nodeChip(node: LAODomain.GraphNode) -> some View {
        let isExpanded = expandedNodeId == node.id
        let isSeed = node.kind == .seed

        VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
            HStack(spacing: 8) {
                Text(node.title)
                    .font(isExpanded
                          ? AppTheme.Typography.heading
                          : (isSeed
                             ? AppTheme.Typography.heading
                             : AppTheme.Typography.bodySecondary.weight(.medium)))
                    .lineLimit(isExpanded ? nil : 2)
                    .multilineTextAlignment(isExpanded ? .leading : .center)
                    .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
                if isExpanded {
                    Button {
                        expandedNodeId = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(theme.foregroundMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(lang.ideaBoard.nodeGraphExpandedClose)
                }
            }

            if isExpanded {
                Divider()
                if !node.body.isEmpty {
                    Text(node.body)
                        .font(AppTheme.Typography.bodySecondary)
                        .foregroundStyle(theme.foregroundSecondary)
                }

                if isCandidate(node) && node.status != .folded {
                    candidateActionsRow(node: node)
                }

                conversationPanel(node: node)
            }
        }
        .padding(.horizontal, isExpanded ? 16 : 14)
        .padding(.vertical, isExpanded ? 14 : 10)
        .frame(
            maxWidth: isExpanded ? 360 : 140,
            minHeight: isExpanded ? 320 : nil,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                .fill(chipFill(isSeed: isSeed, isExpanded: isExpanded))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                        .stroke(
                            chipStroke(isSeed: isSeed, isExpanded: isExpanded),
                            lineWidth: (isSeed || isExpanded) ? 1.5 : 1
                        )
                )
                .shadow(
                    color: isExpanded ? Color.black.opacity(0.18) : .clear,
                    radius: isExpanded ? 12 : 0,
                    x: 0,
                    y: isExpanded ? 4 : 0
                )
        )
        .foregroundStyle(isSeed ? theme.accentPrimary : theme.foregroundSecondary)
        .opacity(chipOpacity(node: node, isExpanded: isExpanded))
        .animation(.easeIn(duration: 0.5), value: visibleNodeIds)
        .contentShape(Rectangle())
        .onTapGesture {
            // Folded candidates aren't tappable — adoption/fold collapses them out of the
            // active surface. The user can still see them on the canvas (very dim) as part
            // of the reasoning trail.
            guard node.status != .folded else { return }
            if !isExpanded {
                expandedNodeId = node.id
            }
        }
    }

    private func chipFill(isSeed: Bool, isExpanded: Bool) -> Color {
        if isExpanded { return theme.surfaceSubtle }
        return isSeed ? theme.accentSoft : theme.surfaceSubtle
    }

    private func chipStroke(isSeed: Bool, isExpanded: Bool) -> Color {
        if isExpanded { return theme.accentPrimary.opacity(0.5) }
        return isSeed ? theme.accentPrimary : theme.foregroundMuted.opacity(0.35)
    }

    /// Candidate branch nodes (Step 5b) get a slightly dimmer chip and a dashed connecting
    /// edge so the canvas reads "still under consideration" vs the adopted mainline.
    private func isCandidate(_ node: LAODomain.GraphNode) -> Bool {
        node.branchRole == .candidate
    }

    /// Visible nodes are fully opaque; starters that haven't been revealed yet are 0;
    /// non-seed nodes also receive a small fade-down when another node is expanded
    /// so the expanded card stands out. Candidate branches (Step 5b) sit a notch dimmer
    /// than mainline so they read as "still under consideration"; folded candidates
    /// (Step 5c-1) are dimmer still so they read as "kept for history, not active".
    private func chipOpacity(node: LAODomain.GraphNode, isExpanded: Bool) -> Double {
        guard visibleNodeIds.contains(node.id) else { return 0 }
        if isExpanded { return 1.0 }
        if node.status == .folded { return 0.28 }
        if let activeId = expandedNodeId, activeId != node.id {
            return 0.55
        }
        if isCandidate(node) { return 0.7 }
        return node.kind == .seed ? 1.0 : 0.9
    }

    // MARK: - Conversation Panel (Step 3)

    @ViewBuilder
    private func conversationPanel(node: LAODomain.GraphNode) -> some View {
        let messages = viewModel.messages(for: node.id)
        let isResponding = viewModel.isResponding(nodeId: node.id)
        let draftBinding = Binding<String>(
            get: { chatDrafts[node.id] ?? "" },
            set: { chatDrafts[node.id] = $0 }
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(lang.ideaBoard.nodeGraphExpandedConversationTitle)
                    .font(AppTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(theme.foregroundSecondary)
                Spacer()
                if let route = viewModel.routingHint(for: node.id) {
                    routingChip(for: route)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.routingHint(for: node.id))

            if messages.isEmpty && !isResponding {
                Text(lang.ideaBoard.nodeGraphChatEmptyHint)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(theme.foregroundMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(messages) { message in
                                VStack(alignment: .leading, spacing: 6) {
                                    messageBubble(message: message)
                                    if let proposal = viewModel.proposal(for: message.id) {
                                        proposalApprovalCard(messageId: message.id, proposal: proposal)
                                    }
                                    if let branches = viewModel.optionBranches(for: message.id) {
                                        optionBranchesCard(messageId: message.id, branches: branches)
                                    }
                                }
                                .id(message.id)
                            }
                            if isResponding {
                                respondingBubble()
                                    .id("responding-\(node.id)")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 220)
                    .animation(.easeOut(duration: 0.28), value: messages.count)
                    .animation(.easeOut(duration: 0.28), value: isResponding)
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isResponding) { _, new in
                        if new {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo("responding-\(node.id)", anchor: .bottom)
                            }
                        }
                    }
                }
            }

            chatInputRow(node: node, draft: draftBinding, isResponding: isResponding)
        }
    }

    @ViewBuilder
    private func messageBubble(message: NodeMessage) -> some View {
        let isUser = message.author == .user
        let authorLabel = authorLabel(for: message.author)
        let iconName = authorIcon(for: message.author)
        let roleColor = authorRoleColor(message.author)
        let bubbleFill = authorRoleSoftFill(message.author)

        VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
            HStack(spacing: 4) {
                if !isUser, let iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 10))
                        .foregroundStyle(roleColor)
                }
                Text(authorLabel)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(isUser ? theme.foregroundMuted : roleColor.opacity(0.85))
            }
            Text(message.content)
                .font(AppTheme.Typography.bodySecondary)
                .foregroundStyle(theme.foregroundPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 260, alignment: isUser ? .trailing : .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                        .fill(bubbleFill)
                )
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// Inline cleanup actions for an expanded candidate branch (Step 5c-1 / 5c-2).
    /// Primary actions (채택 / 접기) sit as visible chips; secondary actions (병합 / 버리기)
    /// live under a "더보기" ellipsis menu so the cleanup surface stays uncluttered. Both
    /// secondary actions route through a `confirmationDialog` since one is LLM-expensive
    /// and the other is destructive.
    @ViewBuilder
    private func candidateActionsRow(node: LAODomain.GraphNode) -> some View {
        let candidateColor = authorRoleColor(.optionizer)
        let mergeableCount = viewModel.mergeableSiblingCount(of: node.id)

        HStack(spacing: 8) {
            Button {
                Task { await viewModel.adoptCandidate(nodeId: node.id) }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                    Text(lang.ideaBoard.nodeGraphCandidateAdopt)
                        .font(AppTheme.Typography.caption.weight(.medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(candidateColor))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                Task { await viewModel.foldCandidate(nodeId: node.id) }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 11))
                    Text(lang.ideaBoard.nodeGraphCandidateFold)
                        .font(AppTheme.Typography.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(theme.foregroundSecondary)
                .overlay(
                    Capsule().stroke(theme.foregroundMuted.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Menu {
                Button {
                    pendingMergeNodeId = node.id
                } label: {
                    Label(
                        lang.ideaBoard.nodeGraphCandidateMergeFormat(mergeableCount),
                        systemImage: "arrow.triangle.merge"
                    )
                }
                .disabled(mergeableCount < 2)

                Button(role: .destructive) {
                    pendingDiscardNodeId = node.id
                } label: {
                    Label(
                        lang.ideaBoard.nodeGraphCandidateDiscard,
                        systemImage: "trash"
                    )
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.foregroundSecondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(width: 22, height: 22)
        }
    }


    @ViewBuilder
    private func proposalApprovalCard(messageId: UUID, proposal: NodeProposal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.accentPrimary)
                Text(lang.ideaBoard.nodeGraphProposalHeader)
                    .font(AppTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(theme.accentPrimary)
            }
            Text(proposal.title)
                .font(AppTheme.Typography.bodySecondary.weight(.medium))
                .foregroundStyle(theme.foregroundPrimary)
                .lineLimit(2)
            if !proposal.body.isEmpty {
                Text(proposal.body)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(theme.foregroundSecondary)
                    .lineLimit(3)
            }
            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.approveProposal(messageId: messageId) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11))
                        Text(lang.ideaBoard.nodeGraphProposalApprove)
                            .font(AppTheme.Typography.caption.weight(.medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(theme.accentPrimary))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.dismissProposal(messageId: messageId)
                } label: {
                    Text(lang.ideaBoard.nodeGraphProposalDismiss)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .fill(theme.accentSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                        .stroke(theme.accentPrimary.opacity(0.35), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Approval card for 2–4 alternative option branches (Step 5b). One "Add all" action
    /// commits the full set as candidate sibling nodes; "Dismiss" drops them. Individual
    /// branch adoption / fold / merge / discard arrive in Step 5c.
    @ViewBuilder
    private func optionBranchesCard(messageId: UUID, branches: [NodeProposal]) -> some View {
        let optionizerColor = authorRoleColor(.optionizer)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundStyle(optionizerColor)
                Text(lang.ideaBoard.nodeGraphBranchesHeaderFormat(branches.count))
                    .font(AppTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(optionizerColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(branches.enumerated()), id: \.offset) { _, branch in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundStyle(optionizerColor.opacity(0.7))
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(branch.title)
                                .font(AppTheme.Typography.bodySecondary.weight(.medium))
                                .foregroundStyle(theme.foregroundPrimary)
                                .lineLimit(2)
                            if !branch.body.isEmpty {
                                Text(branch.body)
                                    .font(AppTheme.Typography.caption)
                                    .foregroundStyle(theme.foregroundSecondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.approveOptionBranches(messageId: messageId) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11))
                        Text(lang.ideaBoard.nodeGraphBranchesApproveAll)
                            .font(AppTheme.Typography.caption.weight(.medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(optionizerColor))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.dismissOptionBranches(messageId: messageId)
                } label: {
                    Text(lang.ideaBoard.nodeGraphProposalDismiss)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .fill(authorRoleSoftFill(.optionizer))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                        .stroke(optionizerColor.opacity(0.35), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Transient role chip rendered in the conversation header while the chosen step agent is
    /// still composing. Fades out when responding ends (ViewModel clears the hint). Matches the
    /// "리서치가 답합니다, 잠시 후 사라짐" pattern from the v0.8 vision.
    @ViewBuilder
    private func routingChip(for route: DirectorRoute) -> some View {
        let author = route.messageAuthor
        let label = authorLabel(for: author)
        let iconName = authorIcon(for: author)
        let roleColor = authorRoleColor(author)

        HStack(spacing: 4) {
            if let iconName {
                Image(systemName: iconName)
                    .font(.system(size: 9))
            }
            Text(lang.ideaBoard.nodeGraphChatRoutingChipFormat(label))
                .font(AppTheme.Typography.caption)
        }
        .foregroundStyle(roleColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(authorRoleSoftFill(author))
        )
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity
        ))
    }

    /// Foreground/icon color per role. Derived from existing theme accent tokens where possible;
    /// Researcher/Optionizer use SwiftUI literals because the theme has only 4 accent slots.
    private func authorRoleColor(_ author: NodeMessageAuthor) -> Color {
        switch author {
        case .user: return theme.accentPrimary
        case .director: return theme.accentPrimary
        case .specifier: return theme.positiveAccent
        case .researcher: return Color.purple
        case .optionizer: return Color.indigo
        case .gapDetector: return theme.warningAccent
        }
    }

    /// Soft background fill per role — pairs with `authorRoleColor`. Existing theme soft tokens
    /// are reused when available so dark mode still feels balanced.
    private func authorRoleSoftFill(_ author: NodeMessageAuthor) -> Color {
        switch author {
        case .user: return theme.accentSoft
        case .director: return theme.accentSoft
        case .specifier: return theme.positiveAccent.opacity(0.12)
        case .researcher: return Color.purple.opacity(0.12)
        case .optionizer: return Color.indigo.opacity(0.12)
        case .gapDetector: return theme.warningSoftFill
        }
    }

    /// Human-readable label per author. Step 4a routes the four step roles separately so each
    /// gets its own chip; the full 5-character visual treatment (color, dedicated icon set,
    /// routing animation) lands in Step 4b.
    private func authorLabel(for author: NodeMessageAuthor) -> String {
        switch author {
        case .user: return lang.ideaBoard.nodeGraphChatAuthorUser
        case .director: return lang.ideaBoard.nodeGraphChatAuthorDirector
        case .specifier: return lang.ideaBoard.nodeGraphChatAuthorSpecifier
        case .researcher: return lang.ideaBoard.nodeGraphChatAuthorResearcher
        case .optionizer: return lang.ideaBoard.nodeGraphChatAuthorOptionizer
        case .gapDetector: return lang.ideaBoard.nodeGraphChatAuthorGapDetector
        }
    }

    /// Placeholder icon per non-user author so the four roles are visually distinguishable.
    /// Step 4b will pair these with role-specific colors and a transient routing chip.
    private func authorIcon(for author: NodeMessageAuthor) -> String? {
        switch author {
        case .user: return nil
        case .director: return "person.fill"
        case .specifier: return "pencil.tip.crop.circle"
        case .researcher: return "book.closed.fill"
        case .optionizer: return "arrow.triangle.branch"
        case .gapDetector: return "exclamationmark.shield.fill"
        }
    }

    @ViewBuilder
    private func respondingBubble() -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(lang.ideaBoard.nodeGraphChatRespondingHint)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(theme.foregroundMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .fill(theme.neutralSoftFill)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func chatInputRow(node: LAODomain.GraphNode, draft: Binding<String>, isResponding: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField(
                lang.ideaBoard.nodeGraphChatInputPlaceholder,
                text: draft,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .font(AppTheme.Typography.bodySecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                    .fill(theme.neutralSoftFill)
            )
            .disabled(isResponding)
            .onSubmit { submitDraft(nodeId: node.id, draft: draft) }

            Button {
                submitDraft(nodeId: node.id, draft: draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(canSubmit(draft: draft.wrappedValue, isResponding: isResponding)
                                     ? theme.accentPrimary
                                     : theme.foregroundMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lang.common.send)
            .disabled(!canSubmit(draft: draft.wrappedValue, isResponding: isResponding))
        }
    }

    private func canSubmit(draft: String, isResponding: Bool) -> Bool {
        !isResponding && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitDraft(nodeId: UUID, draft: Binding<String>) {
        let content = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !viewModel.isResponding(nodeId: nodeId) else { return }
        draft.wrappedValue = ""
        Task { await viewModel.sendMessage(nodeId: nodeId, content: content) }
    }

    // MARK: - Fade-in sequence

    /// Reveal seed first after a short beat, then starters at a steady cadence, then any
    /// pre-existing descendants in one batch (so reopening a workflow with prior session's
    /// children shows them all immediately without a redundant per-node delay).
    /// Bails out if the view is dismissed mid-sequence (Task cancellation).
    private func runFadeInSequence() async {
        if let seed = viewModel.seedNode {
            try? await Task.sleep(for: Self.seedRevealDelay)
            guard !Task.isCancelled else { return }
            visibleNodeIds.insert(seed.id)
        }
        for starter in viewModel.starterNodes {
            try? await Task.sleep(for: Self.starterRevealGap)
            guard !Task.isCancelled else { return }
            visibleNodeIds.insert(starter.id)
        }
        for node in viewModel.nodes where !visibleNodeIds.contains(node.id) {
            visibleNodeIds.insert(node.id)
        }
    }
}

// MARK: - View Modifiers
// Hoisted out of the main body so SwiftUI's type checker stays under its complexity limit
// (the inline chain was timing out in SourceKit even though the compiler accepted it).

/// Error alert sourced from the ViewModel's `errorAlert` payload.
private struct ErrorAlertModifier: ViewModifier {
    let viewModel: NodeGraphWorkflowViewModel
    let confirmLabel: String

    func body(content: Content) -> some View {
        content.alert(
            viewModel.errorAlert?.title ?? "",
            isPresented: Binding(
                get: { viewModel.errorAlert != nil },
                set: { if !$0 { viewModel.errorAlert = nil } }
            ),
            presenting: viewModel.errorAlert
        ) { _ in
            Button(confirmLabel) { }
        } message: { item in
            Text(item.detail)
        }
    }
}

/// Confirmation dialog for the "병합" action (Step 5c-2). Wraps the dialog state binding so
/// the main body only owns a single `@State` slot.
private struct MergeConfirmationModifier: ViewModifier {
    let viewModel: NodeGraphWorkflowViewModel
    @Binding var pendingId: UUID?
    let confirmLabel: String
    let cancelLabel: String
    let message: String
    let titleFormat: (Int) -> String

    func body(content: Content) -> some View {
        content.confirmationDialog(
            titleFormat(pendingId.map { viewModel.mergeableSiblingCount(of: $0) } ?? 0),
            isPresented: Binding(
                get: { pendingId != nil },
                set: { if !$0 { pendingId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(confirmLabel) {
                if let id = pendingId {
                    pendingId = nil
                    Task { await viewModel.mergeCandidateWithSiblings(nodeId: id) }
                }
            }
            Button(cancelLabel, role: .cancel) { pendingId = nil }
        } message: {
            Text(message)
        }
    }
}

/// Success alert for the JSON export action (Step 5d-1). Offers "Reveal in Finder" as the
/// primary action because the typical follow-up is to feed the file into an AI executor or
/// inspect it manually.
private struct ExportSuccessModifier: ViewModifier {
    @Binding var lastExportURL: URL?
    let title: String
    let messageFormat: (String) -> String
    let revealLabel: String
    let doneLabel: String

    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: Binding(
                get: { lastExportURL != nil },
                set: { if !$0 { lastExportURL = nil } }
            ),
            presenting: lastExportURL
        ) { url in
            Button(revealLabel) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                lastExportURL = nil
            }
            Button(doneLabel, role: .cancel) { lastExportURL = nil }
        } message: { url in
            Text(messageFormat(url.path))
        }
    }
}

/// Confirmation dialog for the destructive "버리기" action (Step 5c-2). The action is
/// destructive — once confirmed, the node and its edges are removed from the DB.
private struct DiscardConfirmationModifier: ViewModifier {
    let viewModel: NodeGraphWorkflowViewModel
    @Binding var pendingId: UUID?
    let title: String
    let message: String
    let confirmLabel: String
    let cancelLabel: String

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(
                get: { pendingId != nil },
                set: { if !$0 { pendingId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(confirmLabel, role: .destructive) {
                if let id = pendingId {
                    pendingId = nil
                    Task { await viewModel.discardCandidate(nodeId: id) }
                }
            }
            Button(cancelLabel, role: .cancel) { pendingId = nil }
        } message: {
            Text(message)
        }
    }
}
