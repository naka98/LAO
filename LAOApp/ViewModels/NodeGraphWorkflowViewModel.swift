import Foundation
import LAODomain
import LAOServices

// `GraphNode` and `GraphEdge` are explicitly module-qualified throughout this file
// because LAOApp/Features/Design/WorkGraphView.swift defines internal types of the
// same name for the v0.7 work graph visualization. Until v0.7 is retired we keep the
// two namespaces isolated by qualifying our v0.8 references.

/// v0.8 node graph workflow ViewModel.
///
/// Owns the workflow / nodes / edges / per-node messages for a single graph-mode idea.
/// On first entry, bootstraps a workflow with one seed node (the idea title) and 6 weak
/// starter roots (사용자/핵심 기능/사용 흐름/결정/위험/성공 기준). Subsequent entries just load.
///
/// Step 3 adds the in-node conversation surface: user messages flow to the specifier step
/// (director routing is hardcoded in this step — real intent classification lands in Step 4),
/// and the response is appended to the node's message thread.
@Observable @MainActor
final class NodeGraphWorkflowViewModel {
    let container: AppContainer
    let project: Project
    let ideaId: UUID
    let ideaTitle: String

    var workflow: NodeGraphWorkflow?
    var nodes: [LAODomain.GraphNode] = []
    var edges: [LAODomain.GraphEdge] = []
    var messagesByNode: [UUID: [NodeMessage]] = [:]
    var respondingNodeIds: Set<UUID> = []
    /// Director routing decision for nodes currently awaiting a step reply — set after `classifyRoute`
    /// returns, cleared when `sendMessage` exits. The UI watches this to render a transient routing
    /// chip ("리서치 응답 중…") in the expanded node card (Step 4b). Absent for fallback flows so the
    /// fallback stays silent.
    var routingHintByNode: [UUID: DirectorRoute] = [:]
    /// Pending sub-node proposals keyed by the AI message that produced them (Step 5a). Session-only —
    /// approve persists a new `GraphNode` + `parentChild` edge, dismiss just drops the entry. Cleared
    /// automatically when the user navigates away (no persistence). The parent node is the focused
    /// node that owned the conversation, captured at proposal time.
    var pendingProposalsByMessage: [UUID: NodeProposal] = [:]
    /// Pending option-branch sets keyed by AI message id (Step 5b). Each entry is the full list of
    /// alternative branches the optionizer proposed. Approving creates the full set as candidate
    /// children of the focused node, connected to each other with sibling edges.
    var pendingOptionBranchesByMessage: [UUID: [NodeProposal]] = [:]
    /// Maps each pending proposal/branch-set message back to its parent node, since a `NodeMessage`
    /// only stores `nodeId` (which is the conversation host, also the prospective parent). Shared
    /// between Step 5a single proposals and Step 5b option branch sets.
    var proposalParentByMessage: [UUID: UUID] = [:]
    var availableAgents: [Agent] = []
    var userProfile: UserProfile = UserProfile()
    var isLoading = true
    var errorAlert: ErrorAlert?

    /// Round-robin cursor for picking among enabled step agents — mirrors IdeaDetailViewModel.
    private var stepAgentRoundRobinIndex: Int = 0

    init(container: AppContainer, project: Project, ideaId: UUID, ideaTitle: String) {
        self.container = container
        self.project = project
        self.ideaId = ideaId
        self.ideaTitle = ideaTitle
    }

    /// Loads existing workflow + nodes + edges + agents + user profile.
    /// If no workflow exists for this idea, bootstraps it.
    func loadOrBootstrap() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let workflow: NodeGraphWorkflow
            if let existing = await container.nodeGraphService.getWorkflow(ideaId: ideaId) {
                workflow = existing
            } else {
                workflow = try await bootstrap()
            }
            self.workflow = workflow
            self.nodes = await container.nodeGraphService.listNodes(workflowId: workflow.id)
            self.edges = await container.nodeGraphService.listEdges(workflowId: workflow.id)
            self.availableAgents = await container.agentService.listAgents()
            self.userProfile = await container.userProfileService.getProfile()
        } catch {
            let lang = AppLanguage.currentStrings
            errorAlert = ErrorAlert(
                title: lang.ideaBoard.nodeGraphBootstrapFailedFormat(error.localizedDescription),
                detail: ""
            )
        }
    }

    private func bootstrap() async throws -> NodeGraphWorkflow {
        let lang = AppLanguage.currentStrings
        let created = try await container.nodeGraphService.createWorkflow(
            NodeGraphWorkflow(ideaId: ideaId, projectId: project.id)
        )

        let seedTitle = ideaTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? lang.ideaBoard.newIdeaDefaultTitle
            : ideaTitle
        let seed = try await container.nodeGraphService.createNode(
            LAODomain.GraphNode(
                workflowId: created.id,
                kind: .seed,
                status: .exploring,
                title: seedTitle
            )
        )

        let starterLabels: [String] = [
            lang.ideaBoard.nodeGraphStarterUsers,
            lang.ideaBoard.nodeGraphStarterFeatures,
            lang.ideaBoard.nodeGraphStarterFlow,
            lang.ideaBoard.nodeGraphStarterDecisions,
            lang.ideaBoard.nodeGraphStarterRisks,
            lang.ideaBoard.nodeGraphStarterSuccess,
        ]
        for label in starterLabels {
            let starter = try await container.nodeGraphService.createNode(
                LAODomain.GraphNode(
                    workflowId: created.id,
                    kind: .starter,
                    status: .pending,
                    title: label
                )
            )
            _ = try await container.nodeGraphService.createEdge(
                LAODomain.GraphEdge(
                    workflowId: created.id,
                    fromNodeId: seed.id,
                    toNodeId: starter.id,
                    kind: .parentChild
                )
            )
        }
        return created
    }

    var seedNode: LAODomain.GraphNode? { nodes.first { $0.kind == .seed } }

    /// Starters in deterministic display order (creation time).
    var starterNodes: [LAODomain.GraphNode] {
        nodes.filter { $0.kind == .starter }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Direct `parentChild` children of a node in creation order — used by the canvas to lay
    /// out descendants beyond the fixed seed/starter ring (Step 5a).
    func children(of parentId: UUID) -> [LAODomain.GraphNode] {
        let childIds = edges
            .filter { $0.fromNodeId == parentId && $0.kind == .parentChild }
            .map(\.toNodeId)
        let childSet = Set(childIds)
        return nodes
            .filter { childSet.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Messages (Step 3 / 4a)

    func messages(for nodeId: UUID) -> [NodeMessage] { messagesByNode[nodeId] ?? [] }

    func isResponding(nodeId: UUID) -> Bool { respondingNodeIds.contains(nodeId) }

    /// The active director decision for a node, if any. Used by the View to render the transient
    /// "리서치 응답 중…" chip while the chosen step agent is still composing its reply.
    func routingHint(for nodeId: UUID) -> DirectorRoute? { routingHintByNode[nodeId] }

    /// Lazy-load the per-node message thread on first expansion. No-op once cached.
    func loadMessagesIfNeeded(nodeId: UUID) async {
        if messagesByNode[nodeId] != nil { return }
        messagesByNode[nodeId] = await container.nodeGraphService.listMessages(nodeId: nodeId)
    }

    /// Step 4a flow: append user message → director classifies intent → chosen step agent replies.
    /// Any director failure (network / parse / unknown route) falls back to specifier so misroutes
    /// never dead-end the conversation — preserves the "정정 안전망" intent from the v0.8 vision.
    func sendMessage(nodeId: UUID, content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !respondingNodeIds.contains(nodeId),
              let node = nodes.first(where: { $0.id == nodeId }) else {
            return
        }

        let lang = AppLanguage.currentStrings

        // 1) Persist the user's message and reflect it in the local thread immediately
        let userMessage = NodeMessage(nodeId: nodeId, author: .user, content: trimmed)
        let savedUser: NodeMessage
        do {
            savedUser = try await container.nodeGraphService.appendMessage(userMessage)
        } catch {
            errorAlert = ErrorAlert(
                title: lang.ideaBoard.nodeGraphChatSendFailedFormat(error.localizedDescription),
                detail: ""
            )
            return
        }
        appendLocal(message: savedUser)

        // 2) Mark the node as responding while we wait on the LLM(s)
        respondingNodeIds.insert(nodeId)
        defer {
            respondingNodeIds.remove(nodeId)
            routingHintByNode.removeValue(forKey: nodeId)
        }

        // 3) Director routing — never user-visible; failure silently falls back to specifier.
        // Successful classification publishes a routing hint so the UI can render the role chip
        // for the duration of the step LLM call; fallback path stays silent (no hint).
        let historyBeforeUser = (messagesByNode[nodeId] ?? []).dropLast()
        let route = await classifyRoute(
            node: node,
            historyBeforeUser: Array(historyBeforeUser),
            userMessage: trimmed
        )
        routingHintByNode[nodeId] = route

        // 4) Build the chosen step's prompt with the full conversation so far (incl. the new user line)
        let fullHistory = messagesByNode[nodeId] ?? []
        let prompt = buildStepPrompt(
            for: route,
            node: node,
            chatHistory: fullHistory
        )

        // 5) Run the step agent
        let agent = resolveStepAgent()
        let response: String
        do {
            response = try await container.cliAgentRunner.run(
                agent: agent,
                prompt: prompt,
                projectId: project.id,
                rootPath: project.rootPath
            )
        } catch {
            errorAlert = ErrorAlert(
                title: lang.ideaBoard.nodeGraphChatSendFailedFormat(error.localizedDescription),
                detail: ""
            )
            return
        }

        // 6) Split off the optional proposal block (Step 5a/5b). Prose alone is saved as the
        // message; the proposal (single child or N-option branch set) lives in session state
        // until the user approves or dismisses.
        let (prose, parsedProposal) = NodeGraphPromptBuilder.extractAnyProposal(from: response)
        let aiContent = prose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !aiContent.isEmpty else {
            errorAlert = ErrorAlert(
                title: lang.ideaBoard.nodeGraphChatSendFailedFormat(lang.ideaBoard.nodeGraphChatEmptyResponse),
                detail: ""
            )
            return
        }

        // 7) Persist + render the step agent's reply, stamped with the route's author tag
        let aiMessage = NodeMessage(nodeId: nodeId, author: route.messageAuthor, content: aiContent)
        let savedAI: NodeMessage
        do {
            savedAI = try await container.nodeGraphService.appendMessage(aiMessage)
            appendLocal(message: savedAI)
        } catch {
            errorAlert = ErrorAlert(
                title: lang.ideaBoard.nodeGraphChatSendFailedFormat(error.localizedDescription),
                detail: ""
            )
            return
        }

        // 8) Route the proposal to the matching session bucket so the View can render the
        // right approval card under the bubble.
        switch parsedProposal {
        case .none:
            break
        case .child(let proposal):
            pendingProposalsByMessage[savedAI.id] = proposal
            proposalParentByMessage[savedAI.id] = nodeId
        case .branches(let branches):
            pendingOptionBranchesByMessage[savedAI.id] = branches
            proposalParentByMessage[savedAI.id] = nodeId
        }

        // 9) Promote the node from `.pending` to `.exploring` on first interaction — best-effort
        if node.status == .pending {
            var updated = node
            updated.status = .exploring
            updated.updatedAt = Date()
            do {
                try await container.nodeGraphService.updateNode(updated)
                if let idx = nodes.firstIndex(where: { $0.id == nodeId }) {
                    nodes[idx] = updated
                }
            } catch {
                // Status update failure is non-fatal — the conversation is already saved.
            }
        }
    }

    // MARK: - Routing (Step 4a)

    /// Run the director routing call and decode the JSON response. Any failure (network / decode /
    /// unknown route) returns `.specifier` so the conversation always lands somewhere useful.
    private func classifyRoute(
        node: LAODomain.GraphNode,
        historyBeforeUser: [NodeMessage],
        userMessage: String
    ) async -> DirectorRoute {
        let prompt = NodeGraphPromptBuilder.buildDirectorRoutingPrompt(
            project: project,
            ideaTitle: ideaTitle,
            focusedNode: node,
            branchContext: branchContext(for: node),
            chatHistory: historyBeforeUser,
            userMessage: userMessage
        )
        let agent = resolveStepAgent()

        let raw: String
        do {
            raw = try await container.cliAgentRunner.run(
                agent: agent,
                prompt: prompt,
                projectId: project.id,
                rootPath: project.rootPath,
                jsonSchema: NodeGraphJSONSchemas.directorRouting
            )
        } catch {
            return .specifier
        }

        guard let jsonString = Self.extractJSON(from: raw),
              let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DirectorRoutingResponse.self, from: data) else {
            return .specifier
        }
        return decoded.route
    }

    /// Pick the right step builder for a route. Kept as a single switch so adding more steps
    /// later is a one-line touch.
    private func buildStepPrompt(
        for route: DirectorRoute,
        node: LAODomain.GraphNode,
        chatHistory: [NodeMessage]
    ) -> String {
        switch route {
        case .specifier:
            return NodeGraphPromptBuilder.buildSpecifierPrompt(
                project: project,
                ideaTitle: ideaTitle,
                focusedNode: node,
                branchContext: branchContext(for: node),
                chatHistory: chatHistory,
                userProfile: userProfile
            )
        case .researcher:
            return NodeGraphPromptBuilder.buildResearcherPrompt(
                project: project,
                ideaTitle: ideaTitle,
                focusedNode: node,
                branchContext: branchContext(for: node),
                chatHistory: chatHistory,
                userProfile: userProfile
            )
        case .optionizer:
            return NodeGraphPromptBuilder.buildOptionizerPrompt(
                project: project,
                ideaTitle: ideaTitle,
                focusedNode: node,
                branchContext: branchContext(for: node),
                chatHistory: chatHistory,
                userProfile: userProfile
            )
        case .gapDetector:
            return NodeGraphPromptBuilder.buildGapDetectorPrompt(
                project: project,
                ideaTitle: ideaTitle,
                focusedNode: node,
                branchContext: branchContext(for: node),
                chatHistory: chatHistory,
                userProfile: userProfile
            )
        }
    }

    /// Pull a JSON object out of a raw LLM response. Tries ```json fences first, then bare ```
    /// fences, then a `{...}` substring — mirrors the parser in IdeaDetailViewModel so behavior
    /// stays consistent across the app.
    private static func extractJSON(from text: String) -> String? {
        if let fenceStart = text.range(of: "```json"),
           let fenceEnd = text.range(of: "```", range: fenceStart.upperBound..<text.endIndex) {
            return String(text[fenceStart.upperBound..<fenceEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let fenceStart = text.range(of: "```"),
           let fenceEnd = text.range(of: "```", range: fenceStart.upperBound..<text.endIndex) {
            return String(text[fenceStart.upperBound..<fenceEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let braceStart = text.firstIndex(of: "{"),
           let braceEnd = text.lastIndex(of: "}") {
            return String(text[braceStart...braceEnd])
        }
        return nil
    }

    private func appendLocal(message: NodeMessage) {
        var current = messagesByNode[message.nodeId] ?? []
        current.append(message)
        messagesByNode[message.nodeId] = current
    }

    // MARK: - Proposal Actions (Step 5a)

    /// The proposal pending for an AI message, if any. View renders an approval card when present.
    func proposal(for messageId: UUID) -> NodeProposal? { pendingProposalsByMessage[messageId] }

    /// Persist the proposed sub-node as a `.free` child of the message's owning node and drop the
    /// pending entry. Failure leaves the proposal in place so the user can retry. The new node is
    /// inserted into the local arrays immediately so the canvas reflects it without a reload.
    func approveProposal(messageId: UUID) async {
        guard let proposal = pendingProposalsByMessage[messageId],
              let parentId = proposalParentByMessage[messageId],
              let workflow else { return }
        let lang = AppLanguage.currentStrings

        let child = LAODomain.GraphNode(
            workflowId: workflow.id,
            kind: .free,
            status: .pending,
            title: proposal.title,
            body: proposal.body
        )
        do {
            let savedChild = try await container.nodeGraphService.createNode(child)
            let edge = LAODomain.GraphEdge(
                workflowId: workflow.id,
                fromNodeId: parentId,
                toNodeId: savedChild.id,
                kind: .parentChild
            )
            let savedEdge = try await container.nodeGraphService.createEdge(edge)
            nodes.append(savedChild)
            edges.append(savedEdge)
            pendingProposalsByMessage.removeValue(forKey: messageId)
            proposalParentByMessage.removeValue(forKey: messageId)
        } catch {
            errorAlert = ErrorAlert(
                title: lang.ideaBoard.nodeGraphProposalApproveFailedFormat(error.localizedDescription),
                detail: ""
            )
        }
    }

    /// Drop the proposal without creating anything. The AI's prose message stays in the thread.
    func dismissProposal(messageId: UUID) {
        pendingProposalsByMessage.removeValue(forKey: messageId)
        proposalParentByMessage.removeValue(forKey: messageId)
    }

    // MARK: - Option Branches (Step 5b)

    /// The option-branch set pending for an AI message, if any. View renders the branch
    /// approval card when present.
    func optionBranches(for messageId: UUID) -> [NodeProposal]? { pendingOptionBranchesByMessage[messageId] }

    /// Persist all proposed option branches as `.option`-kind candidate children of the
    /// message's owning node, then chain them with `sibling` edges to record the alternative
    /// relationship. Partial failure stops at the first error and leaves whatever has already
    /// been saved in place; the proposal is retained so the user can retry.
    func approveOptionBranches(messageId: UUID) async {
        guard let branches = pendingOptionBranchesByMessage[messageId],
              let parentId = proposalParentByMessage[messageId],
              let workflow else { return }
        let lang = AppLanguage.currentStrings

        var createdNodeIds: [UUID] = []
        do {
            for branch in branches {
                let candidate = LAODomain.GraphNode(
                    workflowId: workflow.id,
                    kind: .option,
                    status: .pending,
                    branchRole: .candidate,
                    title: branch.title,
                    body: branch.body
                )
                let savedCandidate = try await container.nodeGraphService.createNode(candidate)
                nodes.append(savedCandidate)

                let parentChild = LAODomain.GraphEdge(
                    workflowId: workflow.id,
                    fromNodeId: parentId,
                    toNodeId: savedCandidate.id,
                    kind: .parentChild
                )
                let savedParentEdge = try await container.nodeGraphService.createEdge(parentChild)
                edges.append(savedParentEdge)

                // Chain a sibling edge to the previous candidate so the architecture records
                // "these are alternatives of each other" without exploding edge count.
                if let previousId = createdNodeIds.last {
                    let siblingEdge = LAODomain.GraphEdge(
                        workflowId: workflow.id,
                        fromNodeId: previousId,
                        toNodeId: savedCandidate.id,
                        kind: .sibling
                    )
                    let savedSiblingEdge = try await container.nodeGraphService.createEdge(siblingEdge)
                    edges.append(savedSiblingEdge)
                }
                createdNodeIds.append(savedCandidate.id)
            }
            pendingOptionBranchesByMessage.removeValue(forKey: messageId)
            proposalParentByMessage.removeValue(forKey: messageId)
        } catch {
            errorAlert = ErrorAlert(
                title: lang.ideaBoard.nodeGraphProposalApproveFailedFormat(error.localizedDescription),
                detail: ""
            )
        }
    }

    /// Drop the entire pending branch set. The AI's prose message stays in the thread.
    func dismissOptionBranches(messageId: UUID) {
        pendingOptionBranchesByMessage.removeValue(forKey: messageId)
        proposalParentByMessage.removeValue(forKey: messageId)
    }

    // MARK: - Branch Cleanup (Step 5c-1)

    /// Promote a candidate branch to the mainline:
    /// - The adopted node flips `branchRole` to `.mainline` (and stays `kind = .option`).
    /// - Its sibling candidates (other `parentChild` children of the same parent that are
    ///   still `branchRole = .candidate`) get their status set to `.folded` so they fade out
    ///   of the canvas while the data — and edges — remain for export.
    /// - The director appends a short adoption-reasoning message to the parent node's
    ///   conversation thread. This LLM call is best-effort: the status updates land first,
    ///   so adoption is durable even if the reasoning narration fails.
    ///
    /// No-op if the target isn't actually a `.candidate` or its parent can't be located.
    func adoptCandidate(nodeId: UUID) async {
        guard let adopted = nodes.first(where: { $0.id == nodeId }),
              adopted.branchRole == .candidate,
              let parentId = parentOf(nodeId),
              let parent = nodes.first(where: { $0.id == parentId }) else { return }

        let lang = AppLanguage.currentStrings

        // Identify sibling candidates BEFORE we mutate state so the prompt sees the original set.
        let siblings = candidateSiblings(of: adopted, parentId: parentId)

        // 1) Promote the adopted node
        var updatedAdopted = adopted
        updatedAdopted.branchRole = .mainline
        updatedAdopted.updatedAt = Date()
        do {
            try await container.nodeGraphService.updateNode(updatedAdopted)
            if let idx = nodes.firstIndex(where: { $0.id == adopted.id }) {
                nodes[idx] = updatedAdopted
            }
        } catch {
            errorAlert = ErrorAlert(
                title: lang.ideaBoard.nodeGraphCleanupFailedFormat(error.localizedDescription),
                detail: ""
            )
            return
        }

        // 2) Fold sibling candidates (status → .folded). Failures here are non-fatal so we
        //    don't roll back the adoption — partial folds still communicate the decision.
        for sibling in siblings {
            var updated = sibling
            updated.status = .folded
            updated.updatedAt = Date()
            do {
                try await container.nodeGraphService.updateNode(updated)
                if let idx = nodes.firstIndex(where: { $0.id == sibling.id }) {
                    nodes[idx] = updated
                }
            } catch {
                // Continue; the adoption itself already succeeded.
            }
        }

        // 3) Ask the director to narrate the choice on the parent's conversation thread.
        //    Best-effort: empty / failing response leaves the conversation as-is.
        await appendAdoptionReasoning(parent: parent, adopted: updatedAdopted, siblings: siblings)
    }

    /// Fold a candidate branch without promoting anything else. The node stays `branchRole =
    /// .candidate` but `status = .folded` so the canvas dims it. Useful when the user wants
    /// to defer the decision without picking a winner.
    func foldCandidate(nodeId: UUID) async {
        guard let node = nodes.first(where: { $0.id == nodeId }),
              node.branchRole == .candidate else { return }
        let lang = AppLanguage.currentStrings

        var updated = node
        updated.status = .folded
        updated.updatedAt = Date()
        do {
            try await container.nodeGraphService.updateNode(updated)
            if let idx = nodes.firstIndex(where: { $0.id == nodeId }) {
                nodes[idx] = updated
            }
        } catch {
            errorAlert = ErrorAlert(
                title: lang.ideaBoard.nodeGraphCleanupFailedFormat(error.localizedDescription),
                detail: ""
            )
        }
    }

    /// Run the adoption-reasoning LLM call and append the director's note to the parent
    /// node's conversation. Marks the parent as responding while the call is in flight so
    /// the UI shows the spinner in the right place.
    private func appendAdoptionReasoning(
        parent: LAODomain.GraphNode,
        adopted: LAODomain.GraphNode,
        siblings: [LAODomain.GraphNode]
    ) async {
        respondingNodeIds.insert(parent.id)
        defer { respondingNodeIds.remove(parent.id) }

        await loadMessagesIfNeeded(nodeId: parent.id)
        let history = messagesByNode[parent.id] ?? []

        let prompt = NodeGraphPromptBuilder.buildAdoptionReasoningPrompt(
            project: project,
            ideaTitle: ideaTitle,
            parentNode: parent,
            adopted: adopted,
            siblings: siblings,
            chatHistory: history
        )

        let agent = resolveStepAgent()
        let response: String
        do {
            response = try await container.cliAgentRunner.run(
                agent: agent,
                prompt: prompt,
                projectId: project.id,
                rootPath: project.rootPath
            )
        } catch {
            return // Best-effort — adoption already succeeded
        }
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let directorMessage = NodeMessage(nodeId: parent.id, author: .director, content: trimmed)
        do {
            let saved = try await container.nodeGraphService.appendMessage(directorMessage)
            appendLocal(message: saved)
        } catch {
            // Non-fatal; nothing else to do.
        }
    }

    /// Look up the parentChild edge for a node and return the from-side node id.
    private func parentOf(_ nodeId: UUID) -> UUID? {
        edges.first { $0.toNodeId == nodeId && $0.kind == .parentChild }?.fromNodeId
    }

    /// All candidate siblings of `node` under a given parent — i.e. other parentChild children
    /// of the same parent whose branchRole is still `.candidate`. The node itself is excluded.
    private func candidateSiblings(of node: LAODomain.GraphNode, parentId: UUID) -> [LAODomain.GraphNode] {
        let childIds = edges
            .filter { $0.fromNodeId == parentId && $0.kind == .parentChild && $0.toNodeId != node.id }
            .map(\.toNodeId)
        let set = Set(childIds)
        return nodes.filter { set.contains($0.id) && $0.branchRole == .candidate }
    }

    // MARK: - Branch Cleanup (Step 5c-2)

    /// Count of candidate siblings (including the seed node) that would participate in a
    /// merge triggered from `nodeId`. Used by the View to label the menu item ("병합 (N)")
    /// and to hide the option when there's nothing to merge with.
    func mergeableSiblingCount(of nodeId: UUID) -> Int {
        guard let node = nodes.first(where: { $0.id == nodeId }),
              node.branchRole == .candidate,
              node.status != .folded,
              let parentId = parentOf(nodeId) else { return 0 }
        let activeSiblings = candidateSiblings(of: node, parentId: parentId)
            .filter { $0.status != .folded }
        // node itself + its active candidate siblings
        return activeSiblings.count + 1
    }

    /// Synthesize `nodeId` and its active candidate siblings into a single new mainline node.
    /// Steps:
    ///   1. Call the merge LLM with all sources + parent context.
    ///   2. Create the synthesized node (`.option` kind, `.mainline` branch role) under the parent.
    ///   3. Add `supersedes` edges from the new node to each source so lineage is preserved.
    ///   4. Mark each source as `branchRole = .archived, status = .folded`.
    ///   5. Append the director's reasoning sentence to the parent node's conversation.
    /// LLM/decode failure aborts without mutating state. Per-edge / per-update failures after
    /// the new node is saved are best-effort so the merge is durable even if a side write fails.
    func mergeCandidateWithSiblings(nodeId: UUID) async {
        guard let node = nodes.first(where: { $0.id == nodeId }),
              node.branchRole == .candidate,
              node.status != .folded,
              let parentId = parentOf(nodeId),
              let parent = nodes.first(where: { $0.id == parentId }),
              let workflow else { return }
        let lang = AppLanguage.currentStrings

        var sources = candidateSiblings(of: node, parentId: parentId)
            .filter { $0.status != .folded }
        sources.insert(node, at: 0)
        guard sources.count >= 2 else { return } // Nothing to merge

        respondingNodeIds.insert(parent.id)
        defer { respondingNodeIds.remove(parent.id) }

        await loadMessagesIfNeeded(nodeId: parent.id)
        let history = messagesByNode[parent.id] ?? []

        // 1) Run the merge LLM with strict JSON schema
        let prompt = NodeGraphPromptBuilder.buildMergePrompt(
            project: project,
            ideaTitle: ideaTitle,
            parentNode: parent,
            candidates: sources,
            chatHistory: history
        )
        let agent = resolveStepAgent()
        let raw: String
        do {
            raw = try await container.cliAgentRunner.run(
                agent: agent,
                prompt: prompt,
                projectId: project.id,
                rootPath: project.rootPath,
                jsonSchema: NodeGraphJSONSchemas.merge
            )
        } catch {
            errorAlert = ErrorAlert(
                title: lang.ideaBoard.nodeGraphCleanupFailedFormat(error.localizedDescription),
                detail: ""
            )
            return
        }
        guard let jsonString = Self.extractJSON(from: raw),
              let data = jsonString.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(MergeResponse.self, from: data),
              !decoded.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorAlert = ErrorAlert(
                title: lang.ideaBoard.nodeGraphCleanupFailedFormat(lang.ideaBoard.nodeGraphChatEmptyResponse),
                detail: ""
            )
            return
        }

        // 2) Create the merged node + parentChild edge
        let merged = LAODomain.GraphNode(
            workflowId: workflow.id,
            kind: .option,
            status: .exploring,
            branchRole: .mainline,
            title: decoded.title,
            body: decoded.body
        )
        let savedMerged: LAODomain.GraphNode
        do {
            savedMerged = try await container.nodeGraphService.createNode(merged)
            nodes.append(savedMerged)
            let parentChild = LAODomain.GraphEdge(
                workflowId: workflow.id,
                fromNodeId: parentId,
                toNodeId: savedMerged.id,
                kind: .parentChild
            )
            let savedEdge = try await container.nodeGraphService.createEdge(parentChild)
            edges.append(savedEdge)
        } catch {
            errorAlert = ErrorAlert(
                title: lang.ideaBoard.nodeGraphCleanupFailedFormat(error.localizedDescription),
                detail: ""
            )
            return
        }

        // 3) supersedes edges + 4) archive sources — best-effort each
        for source in sources {
            let supersedes = LAODomain.GraphEdge(
                workflowId: workflow.id,
                fromNodeId: savedMerged.id,
                toNodeId: source.id,
                kind: .supersedes
            )
            if let saved = try? await container.nodeGraphService.createEdge(supersedes) {
                edges.append(saved)
            }

            var archived = source
            archived.branchRole = .archived
            archived.status = .folded
            archived.updatedAt = Date()
            do {
                try await container.nodeGraphService.updateNode(archived)
                if let idx = nodes.firstIndex(where: { $0.id == source.id }) {
                    nodes[idx] = archived
                }
            } catch {
                // Continue archiving the rest; merge already succeeded.
            }
        }

        // 5) Director reasoning into the parent thread
        let reasoning = decoded.reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reasoning.isEmpty {
            let directorMessage = NodeMessage(nodeId: parent.id, author: .director, content: reasoning)
            if let saved = try? await container.nodeGraphService.appendMessage(directorMessage) {
                appendLocal(message: saved)
            }
        }
    }

    // MARK: - Export (Step 5d-1)

    /// Tracks whether an export is in flight. Drives the UI to disable the button and show a
    /// progress indicator while the snapshot is being written.
    var isExporting: Bool = false

    /// Where the v0.8 graph exports live for this idea. Mirrors the v0.7
    /// `{rootPath}/.lao/{ideaId}/{requestId}/` pattern but uses a `graph/` segment instead
    /// of a per-request UUID since v0.8 workflows are 1:1 with the idea.
    private func exportDirectoryURL() -> URL {
        URL(fileURLWithPath: project.rootPath)
            .appendingPathComponent(".lao", isDirectory: true)
            .appendingPathComponent(ideaId.uuidString, isDirectory: true)
            .appendingPathComponent("graph", isDirectory: true)
    }

    /// Serialize the workflow + every node, edge, and message into a raw JSON snapshot and
    /// write it to disk. Returns the file URL on success so the View can offer "reveal in
    /// Finder". All work is done off the main actor where possible; only the in-memory state
    /// reads happen up front.
    @discardableResult
    func exportGraph() async throws -> URL {
        guard let workflow else {
            throw NSError(
                domain: "NodeGraphExport",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Workflow not loaded"]
            )
        }
        isExporting = true
        defer { isExporting = false }

        // Pull the full conversation per node. Most are already cached from prior expansions;
        // we top up the rest so the export captures the complete reasoning trail.
        var allMessages: [NodeMessage] = []
        for node in nodes {
            await loadMessagesIfNeeded(nodeId: node.id)
            if let nodeMessages = messagesByNode[node.id] {
                allMessages.append(contentsOf: nodeMessages)
            }
        }

        let payload = NodeGraphExport(
            schemaVersion: 1,
            exportedAt: Date(),
            ideaId: ideaId,
            ideaTitle: ideaTitle,
            workflow: workflow,
            nodes: nodes,
            edges: edges,
            messages: allMessages
        )

        let encoder = NodeGraphExportEncoder.make()
        let data = try encoder.encode(payload)

        let dir = exportDirectoryURL()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("export.json")
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    /// Permanently delete a candidate (and its edges via FK CASCADE). Used for the "버리기"
    /// action when the user wants the option gone entirely rather than archived. Note: this
    /// breaks the reasoning trail by design — fold is the preserve-history path; discard is
    /// the "remove this from consideration entirely" path.
    func discardCandidate(nodeId: UUID) async {
        guard let node = nodes.first(where: { $0.id == nodeId }),
              node.branchRole == .candidate else { return }
        let lang = AppLanguage.currentStrings

        do {
            try await container.nodeGraphService.deleteNode(id: nodeId)
            // Mirror the cascade locally — drop the node, any edges that touched it, the
            // conversation cache for it, and any session-only proposals that targeted it.
            nodes.removeAll { $0.id == nodeId }
            edges.removeAll { $0.fromNodeId == nodeId || $0.toNodeId == nodeId }
            messagesByNode.removeValue(forKey: nodeId)
        } catch {
            errorAlert = ErrorAlert(
                title: lang.ideaBoard.nodeGraphCleanupFailedFormat(error.localizedDescription),
                detail: ""
            )
        }
    }

    /// Walks parent→child edges upward until it lands on a starter, returning its title.
    /// Gives the specifier a domain hint (e.g., "사용자"). Returns nil for the seed.
    private func branchContext(for node: LAODomain.GraphNode) -> String? {
        if node.kind == .seed { return nil }
        if node.kind == .starter { return node.title }
        guard let parentId = edges.first(where: { $0.toNodeId == node.id && $0.kind == .parentChild })?.fromNodeId,
              let parent = nodes.first(where: { $0.id == parentId }) else { return nil }
        return branchContext(for: parent)
    }

    /// Pick an enabled step agent via round-robin. Falls back to a built-in "sonnet" agent so
    /// the conversation still works even when no agents are configured yet.
    private func resolveStepAgent() -> Agent {
        let stepAgents = availableAgents.filter { $0.tier == .step && $0.isEnabled }
        if !stepAgents.isEmpty {
            let agent = stepAgents[stepAgentRoundRobinIndex % stepAgents.count]
            stepAgentRoundRobinIndex += 1
            return agent
        }
        return Agent(name: "Specifier", tier: .step, provider: .claude, model: "sonnet")
    }
}
