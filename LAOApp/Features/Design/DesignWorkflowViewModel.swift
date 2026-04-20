import AppKit
import Foundation
import LAODomain
import LAORuntime
import LAOServices
import os

private let logger = Logger(subsystem: "com.leewaystudio.lao", category: "design")

@MainActor
@Observable
final class DesignWorkflowViewModel {
    let container: AppContainer
    let project: Project
    let requestId: UUID?
    private(set) var ideaId: UUID?

    var taskInput: String = ""
    var workflow: DesignWorkflow?
    var hasExportedDeliverables: Bool { !diskDocumentFiles.isEmpty }
    private(set) var exportValidationIssues: [DesignDocumentValidator.Issue] = []
    /// Set to true by the Design when all items are confirmed and the workflow is ready to complete.
    var shouldPromptCompletion = false

    // Idea-phase metrics (loaded from linked Idea for aggregated display)
    private(set) var ideaApiCallCount: Int = 0
    private(set) var ideaEstimatedTokens: Int = 0
    var totalApiCallCount: Int { (workflow?.apiCallCount ?? 0) + ideaApiCallCount }
    var totalEstimatedTokens: Int { (workflow?.estimatedTokens ?? 0) + ideaEstimatedTokens }

    /// True when exported deliverables contain substantive content (not just empty skeletons).
    var hasSubstantiveExport: Bool {
        guard let wf = workflow else { return false }
        return !wf.deliverables.flatMap(\.exportableItems).isEmpty
    }

    // Analysis state
    var isAnalyzing: Bool = false
    var analysisStreamOutput: String = ""

    // Design Freeze confirmation (approach selection → planning gate)

    // Structure Approval confirmation (REFINE → SPECIFY gate)
    var showStructureApproval: Bool = false
    var structureGateResult: PhaseGateResult?

    // Finish Approval confirmation (elaboration complete → consistency check + export gate)
    var showFinishApproval: Bool = false

    // Skeleton generation state (stage 2, after approach selection)
    var isGeneratingSkeleton: Bool = false
    var skeletonStreamOutput: String = ""

    // Skeleton graph generation state (stage 2b, relationships + uncertainties — now split into two parallel calls)
    var isGeneratingGraph: Bool = false
    var graphStreamOutput: String = ""
    var skeletonPreviewSections: [DeliverableSection] = []

    /// Per-call status for the split skeleton graph phase.
    enum SubtaskStatus: Equatable {
        case idle
        case loading
        case done(Int)    // associated value = item count
        case failed
    }
    var relationshipsStatus: SubtaskStatus = .idle
    var uncertaintiesStatus: SubtaskStatus = .idle

    /// Cached user profile for client context injection into prompts.
    private var userProfile = UserProfile()

    // Revision review overlay state
    var revisionChatMessages: [DesignChatMessage] = []
    var revisionStreamOutput: String = ""
    var isRevisionChatting: Bool = false
    var pendingRevisionActions: [DesignAction]?
    var isRevisionApplying: Bool = false
    var isRevisionElaborating: Bool = false
    var revisionCompleted: Bool = false
    private var revisionExecutionTask: Task<Void, Never>?

    // Uncertainty discussion overlay state
    var uncertaintyChatMessages: [DesignChatMessage] = []
    var uncertaintyStreamOutput: String = ""
    var isUncertaintyChatting: Bool = false
    var pendingUncertaintyResolution: UncertaintyResolution?
    var uncertaintyDiscussionCompleted: Bool = false
    private var uncertaintyDiscussionTask: Task<Void, Never>?

    struct UncertaintyResolution {
        var selectedOption: String?
        var responseText: String?
        var summary: String
        var relatedActions: [DesignAction]?
    }

    // Active item work (step agents working on items — supports parallel elaboration)
    /// Active item elaborations keyed by itemId. Supports parallel work.
    var activeItemWorks: [UUID: ActiveItemWork] = [:]

    /// Backward-compatible accessor.
    var activeItemWork: ActiveItemWork? { activeItemWorks.values.first }

    /// True when any item elaboration is in progress.
    var isElaborating: Bool { !activeItemWorks.isEmpty }

    /// True during the preparation phase before first item starts (agent assignment, context building).
    var isPreparingElaboration: Bool = false

    /// True when current elaboration is a retry (not initial run). Prevents auto-finish chaining.
    var isRetryElaboration: Bool = false

    struct ActiveItemWork {
        var sectionType: String
        var itemId: UUID
        var itemName: String
        var agentLabel: String
        var streamOutput: String
    }

    // Deliverable viewer state
    var selectedItemId: UUID?
    var planningViewMode: PlanningViewMode = .canvas
    var inspectorVisible: Bool = true

    /// True when planning phase has no elaborated items yet (canvas serves as skeleton preview).
    var isPreElaboration: Bool {
        guard let wf = workflow, wf.phase == .planning else { return false }
        return !wf.deliverables.contains { section in
            section.items.contains { $0.status == .completed || $0.status == .inProgress }
        }
    }

    /// True when there are non-excluded items still awaiting elaboration (pending or needsRevision).
    var hasIncompleteElaborationItems: Bool {
        guard let wf = workflow, wf.isStructureApproved else { return false }
        return wf.deliverables.contains { section in
            section.items.contains {
                ($0.status == .pending || $0.status == .needsRevision)
                && $0.designVerdict != .excluded
            }
        }
    }

    /// True only when all active items finished elaboration and no in-flight elaboration remains.
    /// Used as the canonical guard before entering finishWorkflow / requestFinishApproval to
    /// prevent the between-parallel-groups idle gap from triggering premature completion.
    var isElaborationFullyDone: Bool {
        guard !isElaborating, !isPreparingElaboration else { return false }
        guard let wf = workflow else { return false }
        let hasInFlight = wf.deliverables.flatMap(\.items).contains {
            $0.designVerdict != .excluded
            && ($0.status == .pending || $0.status == .inProgress)
        }
        return !hasInFlight
    }

    /// REFINE sub-phase: planning phase, structure not yet approved.
    var isRefinePhase: Bool {
        guard let wf = workflow, wf.phase == .planning else { return false }
        return !wf.isStructureApproved
    }

    /// SPECIFY sub-phase: planning phase, structure approved, elaboration can proceed.
    var isSpecifyPhase: Bool {
        guard let wf = workflow, wf.phase == .planning else { return false }
        return wf.isStructureApproved
    }

    enum PlanningViewMode: String, CaseIterable {
        case canvas, list
    }

    // Decision audit trail
    var decisionHistory: [DecisionHistoryEntry] = []
    var isLoadingHistory: Bool = false

    struct DecisionHistoryEntry: Identifiable {
        let id: UUID
        let timestamp: Date
        let category: DecisionCategory
        let summary: String
        let relatedItemId: UUID?

        enum DecisionCategory: String {
            case approachSelected
            case itemConfirmed
            case itemRevisionRequested
            case uncertaintyResolved
            case uncertaintyDismissed
        }
    }

    // Finishing state (transient — not persisted)
    enum FinishingStep: String { case consistencyCheck, applyingFixes, exporting }
    var finishingStep: FinishingStep?
    var isFinishing: Bool { finishingStep != nil }

    /// VM-owned task that bridges elaboration completion to finishWorkflow.
    /// Owned by the ViewModel (not the overlay view) so it survives view re-creation
    /// and parent re-renders. Replaces the previous view-owned Task pattern that
    /// silently broke the auto-chain when the overlay view was rebuilt.
    private var autoFinishTask: Task<Void, Never>?

    /// Tracks the active finishWorkflow Task so cancellation (Cancel button or Back navigation)
    /// can actually reach the in-flight LLM call started by confirmFinishApproval.
    private var finishingTask: Task<Void, Never>?

    // Consistency review overlay state
    var consistencyIssues: [ConsistencyIssue] = []
    var consistencySummary: String = ""
    var consistencyChatMessages: [DesignChatMessage] = []
    var consistencyStreamOutput: String = ""
    var isConsistencyChatting: Bool = false
    var pendingConsistencyActions: [DesignAction]?
    var isConsistencyApplying: Bool = false
    var isConsistencyElaborating: Bool = false
    var consistencyReviewCompleted: Bool = false
    var showConsistencyReview: Bool = false
    private var consistencyReviewTask: Task<Void, Never>?

    // Re-analysis feedback (transient — consumed once by runAnalysis)
    private var pendingReanalyzeFeedback: String?
    private var previousAnalysisSummary: String?

    // General state
    var currentAgentLabel: String = ""
    var errorMessage: String?
    var isLoadingRequest: Bool = false
    var isRestoredRequest: Bool = false
    var restoredRequest: DesignSession?

    /// Localization strings injected from the View layer.
    var lang: AppStrings = .en

    // Coordinator
    var coordinatorRequestId: UUID?

    // Private
    private var availableAgents: [Agent] = []
    private var executionTask: Task<Void, Never>?
    // Adaptive concurrency: adjusts based on rate limit responses
    private var currentMaxConcurrency: Int = 5
    private let concurrencyFloor: Int = 1
    private var concurrencyCeiling: Int = 5
    private var consecutiveSuccesses: Int = 0
    private let successesBeforeScaleUp: Int = 3
    private var stepAgentRoundRobinIndex: Int = 0
    private(set) var diskDocumentFiles: [(name: String, path: String)] = []

    /// Pre-extracted graph data from IdeaBoard synthesis (carried via roadmapJSON).
    private var preExtractedGraphJSON: String?
    /// Cached BRD/CPS JSON from DesignSession, loaded during loadState(), consumed by exportDeliverables()
    private var cachedBrdJSON: String = ""
    /// Cached Design Brief JSON from DesignSession — primary input for Design analysis
    private var cachedDesignBriefJSON: String = ""
    /// Reference anchors loaded from roadmapJSON, applied to workflow during initialization.
    private var pendingReferenceAnchors: [ReferenceImageData]?

    /// Minimal decode shape for extracting referenceAnchors from roadmapJSON.
    private struct RoadmapGraphForRefs: Codable {
        struct RefAnchor: Codable { let category: String; let productName: String; let aspect: String; let searchURL: String? }
        let referenceAnchors: [RefAnchor]?
    }

    /// Tracks last checkpoint time per item for streaming checkpoint (5-second interval).
    private var lastCheckpointTime: [UUID: Date] = [:]
    private var lastAnalysisCheckpointTime: Date?

    /// Debounce task for coalescing rapid syncToRequest calls.
    private var syncDebounceTask: Task<Void, Never>?
    private static let syncDebounceInterval: Duration = .seconds(2)

    init(container: AppContainer, project: Project, requestId: UUID? = nil, ideaId: UUID? = nil) {
        self.container = container
        self.project = project
        self.requestId = requestId
        self.ideaId = ideaId
        // Pre-set loading flag so the very first render shows a loading state
        // instead of flashing the input phase.
        if requestId != nil {
            self.isLoadingRequest = true
        }
    }

    /// Backfill ideaId when it wasn't available at init time.
    func backfillIdeaId(_ id: UUID) {
        guard ideaId == nil else { return }
        ideaId = id
    }

    // MARK: - Event Logging

    private func logEvent(_ type: String, payload: [String: Any]? = nil) {
        guard let reqId = requestId else { return }
        let json: String? = payload.flatMap {
            guard let data = try? JSONSerialization.data(withJSONObject: $0) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        let event = DesignEvent(sessionId: reqId, eventType: type, payloadJSON: json)
        Task {
            do {
                try await container.designEventService.appendEvent(event)
            } catch {
                logger.warning("Failed to log event \(type, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func handleAnalysisStreamUpdate(_ text: String, at now: Date) {
        analysisStreamOutput = text

        // Checkpoint analysis output every 10 seconds for crash resilience.
        if let lastCheckpoint = lastAnalysisCheckpointTime,
           now.timeIntervalSince(lastCheckpoint) >= 10.0 {
            workflow?.partialAnalysisOutput = text
            syncToRequest()
            lastAnalysisCheckpointTime = now
        }
    }

    // MARK: - Computed

    var progress: (completed: Int, total: Int) {
        guard let wf = workflow else { return (0, 0) }
        return (wf.completedItemCount, wf.totalItemCount)
    }

    private var promptBuilder: DesignPromptBuilder {
        DesignPromptBuilder(
            workflow: workflow,
            taskInput: taskInput,
            availableAgents: availableAgents,
            project: project,
            requestId: requestId,
            ideaId: ideaId,
            designBriefJSON: cachedDesignBriefJSON.isEmpty ? nil : cachedDesignBriefJSON,
            userProfile: userProfile
        )
    }

    /// Whether this workflow is waiting in the per-project queue.
    var isQueuedForExecution: Bool {
        guard let reqId = requestId else { return false }
        return container.activeWorkflowCoordinator.isQueued(reqId)
    }

    // MARK: - Actions

    func loadAgents() async {
        availableAgents = await container.agentService.listAgents()
        let settings = await container.appSettingsService.getSettings()
        concurrencyCeiling = max(1, min(10, settings.elaborationConcurrency))
        currentMaxConcurrency = concurrencyCeiling
    }

    /// Load task description from an existing DesignSession (DB).
    /// - Fresh request (just created, status=planning, no deliverables) -> auto-start analysis
    /// - Existing request with designStateJSON -> full restore (resume)
    /// - Legacy request without designStateJSON -> fallback summary view
    func loadFromRequest() async {
        guard let requestId else { return }
        // Skip reload if already analyzing (prevents duplicate tasks on view re-appear)
        guard !isAnalyzing && executionTask == nil else { return }
        isLoadingRequest = true
        defer { isLoadingRequest = false }

        guard let request = await container.designSessionService.getRequest(id: requestId) else { return }
        taskInput = request.taskDescription

        // Load idea-phase metrics for aggregated display and resolve ideaId if needed
        let ideas = await container.ideaService.listIdeas(projectId: project.id)
        if let idea = ideas.first(where: { $0.designSessionId == requestId }) {
            ideaApiCallCount = idea.apiCallCount
            ideaEstimatedTokens = idea.estimatedTokens
            if ideaId == nil { ideaId = idea.id }
        }

        // Carry pre-extracted graph from IdeaBoard synthesis (if present)
        if request.roadmapJSON != "[]" && !request.roadmapJSON.isEmpty {
            preExtractedGraphJSON = request.roadmapJSON

            // Load reference anchors into workflow if present in graph
            if let data = request.roadmapJSON.data(using: .utf8),
               let graph = try? JSONDecoder().decode(RoadmapGraphForRefs.self, from: data),
               let anchors = graph.referenceAnchors, !anchors.isEmpty {
                let refs = anchors.map {
                    ReferenceImageData(
                        category: $0.category, productName: $0.productName,
                        aspect: $0.aspect, searchURL: $0.searchURL,
                        addedDuring: "exploration"
                    )
                }
                // Will be applied to workflow when it's initialized
                pendingReferenceAnchors = refs
            }
        }
        // Cache BRD JSON for later export (avoids async call in sync exportDeliverables)
        cachedBrdJSON = request.brdJSON
        cachedDesignBriefJSON = request.designBriefJSON

        // Restore or start: designStateJSON is the single source of truth.
        if workflow == nil {
            if !request.designStateJSON.isEmpty {
                // Saved workflow exists — restore from it
                if restoreFullWorkflow(from: request) {
                    refreshDiskDocumentFiles()
                    return
                }
                // Decode failed — data corruption
                workflow = DesignWorkflow(phase: .failed, taskDescription: request.title)
                errorMessage = lang.design.workflowRestoreFailed
                return
            }
            // No saved workflow — fresh request or legacy
            if request.status == .planning || request.phaseName.isEmpty {
                startAnalysis()
                return
            }
            // Legacy fallback (pre-designStateJSON records)
            isRestoredRequest = true
            restoredRequest = request
        }
    }

    /// Restore full DesignWorkflow state from the persisted JSON.
    /// Returns `true` if restoration succeeded.
    private func restoreFullWorkflow(from request: DesignSession) -> Bool {
        guard !request.designStateJSON.isEmpty,
              let data = request.designStateJSON.data(using: .utf8) else { return false }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let restoredResult: DesignWorkflow
        do {
            restoredResult = try decoder.decode(DesignWorkflow.self, from: data)
        } catch {
            logger.error("[Restore] Failed to decode workflow: \(error.localizedDescription, privacy: .public)")
            return false
        }
        var restoredWorkflow = restoredResult

        // Edge case: revert inProgress items to pending (streaming was interrupted).
        // Partial output is preserved as plannerNotes so the user can recover context.
        for si in restoredWorkflow.deliverables.indices {
            for ii in restoredWorkflow.deliverables[si].items.indices {
                if restoredWorkflow.deliverables[si].items[ii].status == .inProgress {
                    restoredWorkflow.deliverables[si].items[ii].status = .pending
                    if let partial = restoredWorkflow.deliverables[si].items[ii].partialOutput, !partial.isEmpty {
                        let existing = restoredWorkflow.deliverables[si].items[ii].plannerNotes ?? ""
                        restoredWorkflow.deliverables[si].items[ii].plannerNotes =
                            (existing.isEmpty ? "" : existing + "\n\n") +
                            "[Recovered partial output from interrupted elaboration]\n" +
                            String(partial.prefix(2000))
                    }
                    restoredWorkflow.deliverables[si].items[ii].partialOutput = nil
                    restoredWorkflow.deliverables[si].items[ii].lastCheckpoint = nil
                }
            }
        }

        // Edge case: revert inProgress steps to pending
        for i in restoredWorkflow.steps.indices {
            if restoredWorkflow.steps[i].status == .inProgress {
                restoredWorkflow.steps[i].status = .pending
                restoredWorkflow.steps[i].startedAt = nil
                restoredWorkflow.steps[i].output = ""
            }
        }

        // Edge case: failed workflow with no deliverables -> re-analyze
        if restoredWorkflow.phase == .failed && restoredWorkflow.deliverables.isEmpty {
            taskInput = restoredWorkflow.taskDescription
            startAnalysis()
            return true
        }

        // Edge case: analyzing phase was interrupted -> try to recover from checkpoint
        if restoredWorkflow.phase == .analyzing {
            taskInput = restoredWorkflow.taskDescription
            // Attempt to parse partial analysis output from checkpoint
            if let partial = restoredWorkflow.partialAnalysisOutput,
               !partial.isEmpty,
               let analysisResponse = DesignStepResultParser.parseAnalysisResponse(from: partial),
               !(analysisResponse.deliverables ?? []).isEmpty || analysisResponse.hasApproaches {
                // Partial analysis is parseable — skip re-analysis and apply results directly
                restoredWorkflow.partialAnalysisOutput = nil
                restoredWorkflow.phase = .input  // will transition to planning via normal flow
                workflow = restoredWorkflow
                // Feed the recovered response into the normal analysis completion path
                analysisStreamOutput = partial
                return true
            }
            // Partial not usable — full re-analysis
            startAnalysis()
            return true
        }

        // Edge case: generatingGraph interrupted with deliverables already built → advance to planning
        if restoredWorkflow.phase == .generatingGraph && !restoredWorkflow.deliverables.isEmpty {
            restoredWorkflow.transitionTo(.planning)
        }
        // generatingSkeleton interrupted → stay on that phase (user sees retry button)

        // Re-resolve agents for team members (agent data may have changed)
        for i in restoredWorkflow.teamMembers.indices {
            if let savedAgent = restoredWorkflow.teamMembers[i].resolvedAgent {
                let freshAgent = availableAgents.first { $0.id == savedAgent.id }
                restoredWorkflow.teamMembers[i].resolvedAgent = freshAgent ?? savedAgent
            }
        }

        workflow = restoredWorkflow
        taskInput = restoredWorkflow.taskDescription

        // Restore chat messages from workflow history
        // Planning phase: start with overview (no item selected)
        // so the inspector shows the "Pending Decisions" summary first.
        selectedItemId = nil

        if restoredWorkflow.allItemsConfirmed { shouldPromptCompletion = true }

        return true
    }

    // MARK: - Analysis (Entry Point)

    /// Start the analysis phase: analyze the task and generate a deliverable skeleton.
    /// This replaces the old startPlanning() flow.
    func startAnalysis() {
        guard !taskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Prevent duplicate analysis if already running
        guard !isAnalyzing && executionTask == nil else { return }

        // Per-project queue: check if another workflow is already executing for this project
        if let reqId = requestId {
            let canStart = container.activeWorkflowCoordinator.enqueue(
                requestId: reqId, projectId: project.id
            )
            if !canStart {
                // Queued -- ViewModel stays alive, will be started automatically
                workflow = DesignWorkflow(phase: .input, taskDescription: taskInput)
                syncToRequest()
                return
            }
        }

        errorMessage = nil
        isAnalyzing = true
        analysisStreamOutput = ""
        workflow = DesignWorkflow(phase: .analyzing, taskDescription: taskInput)
        // Apply reference anchors from IdeaBoard exploration (if available)
        if let refs = pendingReferenceAnchors {
            workflow?.referenceAnchors = refs
            pendingReferenceAnchors = nil
        }
        logEvent(DesignEventType.analysisStarted)

        executionTask?.cancel()
        executionTask = Task {
            await runAnalysis()
        }
    }

    /// Core analysis implementation: call LLM, parse response, create deliverable skeleton.
    private func runAnalysis() async {
        userProfile = await container.userProfileService.getProfile()

        guard !resolveDesignAgents().isEmpty else {
            errorMessage = lang.common.noAgentConfigured
            isAnalyzing = false
            workflow?.transitionTo(.failed)
            notifyBlockingState(message: lang.common.noAgentConfiguredShort)
            return
        }

        let prompt = promptBuilder.buildAnalysisPrompt(
            preExtractedGraph: preExtractedGraphJSON,
            reanalyzeFeedback: pendingReanalyzeFeedback,
            previousAnalysisSummary: previousAnalysisSummary
        )
        pendingReanalyzeFeedback = nil
        previousAnalysisSummary = nil
        analysisStreamOutput = ""

        do {
            lastAnalysisCheckpointTime = Date()
            defer { lastAnalysisCheckpointTime = nil }
            let (response, _) = try await runWithFallback(prompt: prompt, jsonSchema: DesignJSONSchemas.analysis) { [weak self] text in
                let now = Date()
                Task { @MainActor in
                    self?.handleAnalysisStreamUpdate(text, at: now)
                }
            }

            guard !Task.isCancelled else { return }

            // Clear analysis checkpoint now that response is complete
            workflow?.partialAnalysisOutput = nil

            // Parse the analysis response
            if let analysisResponse = DesignStepResultParser.parseAnalysisResponse(from: response) {
                // Build ProjectSpec
                let projectSpec = ProjectSpec(
                    name: analysisResponse.projectSpec.name ?? "",
                    type: analysisResponse.projectSpec.type,
                    techStack: analysisResponse.projectSpec.techStack
                )

                // Add Design chat message with analysis summary
                let analysisMessage = (analysisResponse.message ?? "").isEmpty
                    ? DesignStepResultParser.extractAnalysisMessage(from: response)
                    : (analysisResponse.message ?? "")
                let designMsg = DesignChatMessage(role: .design, content: analysisMessage)

                // Route based on response format: approaches (new) vs deliverables (legacy)
                if analysisResponse.hasApproaches, let approachSpecs = analysisResponse.approaches, !approachSpecs.isEmpty {
                    // Approaches from stage 1 — deliverables are populated later by skeleton call
                    let options = approachSpecs.map { spec in
                        let deliverables = Self.buildSections(from: spec.deliverables ?? [])
                        let relationships = spec.relationships.map { rels in
                            Self.buildEdges(from: rels, sections: deliverables)
                        }
                        return ApproachOption(
                            label: spec.label,
                            summary: spec.summary,
                            pros: spec.pros ?? [],
                            cons: spec.cons ?? [],
                            risks: spec.risks ?? [],
                            estimatedComplexity: spec.estimatedComplexity ?? "medium",
                            isRecommended: spec.recommended ?? false,
                            reasoning: spec.reasoning ?? "",
                            deliverables: deliverables,
                            relationships: relationships,
                            hiddenRequirements: analysisResponse.hiddenRequirements ?? []
                        )
                    }

                    if var wf = workflow {
                        wf.projectSpec = projectSpec
                        wf.designSummary = analysisMessage
                        wf.appendChatMessage(designMsg)
                        wf.approachOptions = options
                        wf.hiddenRequirements = analysisResponse.hiddenRequirements ?? []
                        wf.transitionTo(.approachSelection)
                        workflow = wf
                    }

                    // Process uncertainties
                    processAnalysisUncertainties(analysisResponse.uncertainties, nameToId: [:])
                } else {
                    // Single/legacy approach — wrap as ApproachOption for user review
                    let sectionSpecs: [DesignAnalysisResponse.DeliverableSectionSpec]
                    let relationshipSpecs: [DesignAnalysisResponse.RelationshipSpec]?

                    if let approach = analysisResponse.recommendedApproach {
                        sectionSpecs = approach.deliverables ?? []
                        relationshipSpecs = approach.relationships
                    } else {
                        sectionSpecs = analysisResponse.deliverables ?? []
                        relationshipSpecs = analysisResponse.relationships
                    }

                    let sections = Self.buildSections(from: sectionSpecs)
                    let edges: [ItemEdge]? = relationshipSpecs.map { rels in
                        Self.buildEdges(from: rels, sections: sections)
                    }

                    let recommended = analysisResponse.recommendedApproach
                    let singleOption = ApproachOption(
                        label: recommended?.label ?? lang.design.recommendedApproach,
                        summary: recommended?.summary ?? analysisMessage,
                        pros: recommended?.pros ?? [],
                        cons: recommended?.cons ?? [],
                        risks: recommended?.risks ?? [],
                        estimatedComplexity: recommended?.estimatedComplexity ?? "medium",
                        isRecommended: true,
                        reasoning: recommended?.reasoning ?? "",
                        deliverables: sections,
                        relationships: edges,
                        hiddenRequirements: analysisResponse.hiddenRequirements ?? []
                    )

                    if var wf = workflow {
                        wf.projectSpec = projectSpec
                        wf.designSummary = analysisMessage
                        wf.appendChatMessage(designMsg)
                        wf.approachOptions = [singleOption]
                        wf.hiddenRequirements = analysisResponse.hiddenRequirements ?? []
                        wf.transitionTo(.approachSelection)
                        workflow = wf
                    }

                    processAnalysisUncertainties(analysisResponse.uncertainties, nameToId: [:])
                }

                refreshDiskDocumentFiles()

                // Start with overview — no item auto-selected
                selectedItemId = nil
            } else {
                // Parsing failed — show raw response and mark as failed so user can retry
                let fallbackMessage = DesignStepResultParser.extractAnalysisMessage(from: response)
                let designMsg = DesignChatMessage(role: .design, content: fallbackMessage)
                let agentInfo = self.currentAgentLabel ?? "unknown"
                errorMessage = lang.design.analysisFailedFormat("\(lang.design.responseParseFailed) [\(agentInfo)]")

                if var wf = workflow {
                    wf.designSummary = fallbackMessage
                    wf.appendChatMessage(designMsg)
                    wf.transitionTo(.failed)
                    workflow = wf
                }
                let responsePreview = String(response.prefix(500))
                logger.error("Analysis parsing failed — agent=\(self.currentAgentLabel ?? "unknown", privacy: .public) len=\(response.count, privacy: .public) preview=\(responsePreview, privacy: .public)")
                logEvent(DesignEventType.analysisFailed, payload: ["error": "parsing_failed"])
                notifyBlockingState(message: "Analysis parsing failed")
            }

            isAnalyzing = false
            analysisStreamOutput = ""
            syncToRequestImmediate()
            let phaseStr = self.workflow?.phase.rawValue ?? "nil"
            let sectionCount = self.workflow?.deliverables.count ?? 0
            let itemCount = self.workflow?.totalItemCount ?? 0
            logger.info("Analysis done: phase=\(phaseStr, privacy: .public), sections=\(sectionCount)")
            logEvent(DesignEventType.analysisCompleted, payload: [
                "sections": sectionCount,
                "items": itemCount,
            ])

            // Planning or approach-selection phase — user reviews the structure before elaboration.
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = lang.design.analysisFailedFormat(error.localizedDescription)
            isAnalyzing = false
            analysisStreamOutput = ""
            workflow?.transitionTo(.failed)
            logger.error("Analysis failed: \(error.localizedDescription, privacy: .public)")
            logEvent(DesignEventType.analysisFailed, payload: ["error": error.localizedDescription])
            notifyBlockingState(message: "Analysis failed")
        }
    }

    // MARK: - Approach Selection

    /// User selects one of the approach options — freezes the design direction and starts skeleton generation.
    func selectApproach(_ approachId: UUID) {
        guard var wf = workflow,
              wf.phase == .approachSelection,
              let approach = wf.approachOptions?.first(where: { $0.id == approachId }) else { return }

        // Block if there are unresolved blocking uncertainties
        let blockingUncertainties = wf.uncertainties.filter {
            $0.isUncertainty && $0.priority == .blocking && $0.status == .pending
        }
        guard blockingUncertainties.isEmpty else { return }

        wf.selectedApproachId = approach.id
        wf.hiddenRequirements = approach.hiddenRequirements
        wf.designFreezeAt = Date()
        wf.transitionTo(.generatingSkeleton)

        let systemMsg = DesignChatMessage(role: .system, content: "Approach confirmed (Design Freeze): \(approach.label)")
        wf.appendChatMessage(systemMsg)

        workflow = wf
        syncToRequest()
        logEvent("approach_confirmed", payload: [
            "approachId": approach.id.uuidString,
            "label": approach.label,
        ])

        Task { [weak self] in
            await self?.runSkeletonGeneration(approach: approach)
        }
    }

    // MARK: - Skeleton Generation Retry

    /// Retry skeleton generation for the already-selected approach.
    func retrySkeletonGeneration() {
        guard let wf = workflow,
              wf.phase == .generatingSkeleton,
              let approachId = wf.selectedApproachId,
              let approach = wf.approachOptions?.first(where: { $0.id == approachId }) else { return }
        errorMessage = nil
        Task { [weak self] in
            await self?.runSkeletonGeneration(approach: approach)
        }
    }

    // MARK: - Structure Approval (REFINE → SPECIFY gate)

    /// User requests structure approval — shows confirmation overlay with gate check.
    func requestStructureApproval() {
        guard let wf = workflow, wf.phase == .planning, !wf.isStructureApproved else { return }
        structureGateResult = PhaseGateChecker.gateForStructureApproval(wf)
        showStructureApproval = true
    }

    /// User confirms structure approval — locks the skeleton and enables elaboration.
    func confirmStructureApproval() {
        guard var wf = workflow else { return }

        let gate = PhaseGateChecker.gateForStructureApproval(wf)
        guard gate.canProceed else {
            structureGateResult = gate
            return
        }

        wf.structureApprovedAt = Date()

        let systemMsg = DesignChatMessage(role: .system, content: "Structure approved — entering SPECIFY phase")
        wf.appendChatMessage(systemMsg)

        workflow = wf
        syncToRequest()
        logEvent("structure_approved", payload: [:])

        showStructureApproval = false
        structureGateResult = nil
    }

    /// User cancels structure approval from the confirmation overlay.
    func cancelStructureApproval() {
        showStructureApproval = false
        structureGateResult = nil
    }

    // MARK: - Finish Approval (elaboration complete → consistency check + export gate)

    /// User requests finish approval — shows confirmation overlay if elaboration is fully done.
    func requestFinishApproval() {
        guard isElaborationFullyDone else {
            logger.notice("requestFinishApproval blocked — elaboration not fully done")
            return
        }
        guard let wf = workflow,
              wf.allItemsConfirmed,
              !wf.deliverables.flatMap(\.exportableItems).isEmpty else {
            logger.notice("requestFinishApproval blocked — workflow not ready for completion")
            return
        }
        guard !isFinishing else { return }
        showFinishApproval = true
    }

    /// User confirms finish approval — closes overlay and starts consistency check + export.
    func confirmFinishApproval() {
        showFinishApproval = false
        finishingTask?.cancel()
        finishingTask = Task { await finishWorkflow() }
    }

    /// User cancels finish approval from the confirmation overlay.
    func cancelFinishApproval() {
        showFinishApproval = false
    }

    // MARK: - Finishing Cancellation (consistencyCheck step only)

    /// Cancel an in-flight finishWorkflow that is still in the consistencyCheck step.
    /// Safe only for consistencyCheck — applyingFixes/exporting cannot be safely cancelled
    /// (partial action dispatch / file write risk).
    func cancelFinishingConsistencyCheck() {
        guard finishingStep == .consistencyCheck else {
            logger.notice("cancelFinishingConsistencyCheck blocked — current step is \(self.finishingStep?.rawValue ?? "nil", privacy: .public)")
            return
        }
        autoFinishTask?.cancel()
        consistencyReviewTask?.cancel()
        finishingTask?.cancel()
        finishingStep = nil
        logger.info("finishWorkflow consistency check cancelled by user")
    }

    // MARK: - Skeleton Generation (Stage 2: Structure → Graph → Canvas)

    /// Generate deliverable skeleton in two phases, then transition to planning.
    /// Phase A: structure (items + metadata) → preview.
    /// Phase B: graph (relationships + uncertainties) → canvas.
    private func runSkeletonGeneration(approach: ApproachOption) async {
        isGeneratingSkeleton = true
        skeletonStreamOutput = ""
        skeletonPreviewSections = []

        let promptBuilder = DesignPromptBuilder(
            workflow: workflow,
            taskInput: workflow?.taskDescription ?? taskInput,
            availableAgents: availableAgents,
            project: project,
            requestId: requestId,
            ideaId: ideaId,
            designBriefJSON: cachedDesignBriefJSON.isEmpty ? nil : cachedDesignBriefJSON,
            userProfile: userProfile
        )

        // --- Phase A: Structure ---
        let structurePrompt = promptBuilder.buildSkeletonStructurePrompt(
            approach: approach,
            hiddenRequirements: workflow?.hiddenRequirements ?? [],
            preExtractedGraph: preExtractedGraphJSON
        )

        let sections: [DeliverableSection]
        do {
            let (response, _) = try await runWithFallback(prompt: structurePrompt, jsonSchema: DesignJSONSchemas.skeleton) { [weak self] text in
                guard !Task.isCancelled else { return }
                Task { @MainActor in
                    self?.skeletonStreamOutput = text
                }
            }

            if let skeletonResponse = DesignStepResultParser.parseSkeletonResponse(from: response) {
                sections = Self.buildSections(from: skeletonResponse.deliverables)
                skeletonPreviewSections = sections
            } else {
                let agentInfo = self.currentAgentLabel ?? "unknown"
                errorMessage = lang.design.analysisFailedFormat("\(lang.design.skeletonFailed) [\(agentInfo)]")
                let preview = String(response.prefix(500))
                logger.error("Skeleton structure parsing failed — agent=\(agentInfo, privacy: .public) len=\(response.count, privacy: .public) preview=\(preview, privacy: .public)")
                logEvent(DesignEventType.analysisFailed, payload: ["error": "skeleton_structure_parsing_failed"])
                isGeneratingSkeleton = false
                skeletonStreamOutput = ""
                syncToRequest()
                return
            }
        } catch {
            errorMessage = lang.design.analysisFailedFormat(error.localizedDescription)
            logEvent(DesignEventType.analysisFailed, payload: ["error": error.localizedDescription])
            isGeneratingSkeleton = false
            skeletonStreamOutput = ""
            syncToRequest()
            return
        }

        // Transition to graph phase — show preview with items
        isGeneratingSkeleton = false
        skeletonStreamOutput = ""
        isGeneratingGraph = true
        graphStreamOutput = ""

        if var wf = workflow {
            wf.transitionTo(.generatingGraph)
            workflow = wf
            syncToRequest()
        }

        // --- Phase B: Graph (relationships + uncertainties — two parallel calls) ---
        let nameToId = Self.buildNameToIdLookup(sections: sections)
        let itemListWithComponents: [(section: String, name: String, briefDescription: String, components: [String])] = sections.flatMap { section in
            section.items.map { item in
                let componentNames = (item.spec["components"]?.arrayValue as? [[String: Any]])?
                    .compactMap { $0["name"] as? String } ?? []
                return (section: section.type, name: item.name, briefDescription: item.briefDescription ?? "", components: componentNames)
            }
        }
        let itemListSimple = itemListWithComponents.map { (section: $0.section, name: $0.name, briefDescription: $0.briefDescription) }

        relationshipsStatus = .loading
        uncertaintiesStatus = .loading

        let hiddenReqs = workflow?.hiddenRequirements ?? []
        let approachLabel = approach.label
        let approachSummary = approach.summary

        let graphRelationships = await fetchSkeletonRelationships(
            approachLabel: approachLabel,
            approachSummary: approachSummary,
            itemList: itemListWithComponents
        )
        let graphUncertainties = await fetchSkeletonUncertainties(
            approachLabel: approachLabel,
            approachSummary: approachSummary,
            hiddenRequirements: hiddenReqs,
            itemList: itemListSimple
        )

        // --- Canvas transition: assemble full skeleton and enter planning ---
        if var wf = workflow {
            wf.deliverables = sections
            wf.rebuildIndexes()

            if let rels = graphRelationships, !rels.isEmpty {
                for rel in rels {
                    guard let srcId = nameToId[rel.sourceName],
                          let tgtId = nameToId[rel.targetName] else { continue }
                    wf.addEdgeIfNew(ItemEdge(sourceId: srcId, targetId: tgtId, relationType: rel.relationType))
                }
            }

            wf.transitionTo(.planning)
            workflow = wf
            processAnalysisUncertainties(graphUncertainties, nameToId: nameToId)
        }

        selectedItemId = nil
        syncToRequestImmediate()

        isGeneratingGraph = false
        graphStreamOutput = ""
        skeletonPreviewSections = []
        relationshipsStatus = .idle
        uncertaintiesStatus = .idle
    }



    // MARK: - Analysis Helpers

    /// Build DeliverableSections from section specs.
    private static func buildSections(from specs: [DesignAnalysisResponse.DeliverableSectionSpec]) -> [DeliverableSection] {
        specs.map { sectionSpec in
            let items = (sectionSpec.items ?? []).map { skeleton in
                // Pre-populate spec with component hints from skeleton (enables wireframe preview)
                var initialSpec: [String: AnyCodable] = [:]
                if let components = skeleton.components, !components.isEmpty {
                    initialSpec["components"] = AnyCodable(components)
                }
                if let purpose = skeleton.purpose, !purpose.isEmpty {
                    initialSpec["purpose"] = AnyCodable(purpose)
                }
                return DeliverableItem(
                    name: skeleton.name,
                    spec: initialSpec,
                    briefDescription: skeleton.briefDescription,
                    parallelGroup: skeleton.parallelGroup,
                    scenarioGroup: skeleton.scenarioGroup
                )
            }
            return DeliverableSection(
                type: sectionSpec.type ?? sectionSpec.label ?? "unknown",
                label: sectionSpec.label ?? sectionSpec.type ?? "unknown",
                items: items
            )
        }
    }

    /// Build a name→UUID lookup from sections.
    private static func buildNameToIdLookup(sections: [DeliverableSection]) -> [String: UUID] {
        Dictionary(
            sections.flatMap { $0.items }.map { ($0.name, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Build ItemEdges from relationship specs, resolving names to IDs within the given sections.
    private static func buildEdges(
        from rels: [DesignAnalysisResponse.RelationshipSpec],
        sections: [DeliverableSection]
    ) -> [ItemEdge] {
        let nameToId = buildNameToIdLookup(sections: sections)
        return rels.compactMap { rel in
            guard let srcId = nameToId[rel.sourceName],
                  let tgtId = nameToId[rel.targetName] else { return nil }
            return ItemEdge(sourceId: srcId, targetId: tgtId, relationType: rel.relationType)
        }
    }

    /// Process uncertainty specs from analysis, adding them to the workflow.
    private func processAnalysisUncertainties(
        _ specs: [DesignAnalysisResponse.UncertaintySpec]?,
        nameToId: [String: UUID]
    ) {
        guard let specs, !specs.isEmpty else { return }
        for spec in specs {
            let uType = UncertaintyType(rawValue: spec.type) ?? .question
            let uPriority = spec.priority.flatMap { UncertaintyPriority(rawValue: $0) } ?? .important
            let relatedId = spec.relatedItemName.flatMap { nameToId[$0] }
            let axiom = spec.triggeredBy.flatMap { UncertaintyAxiom(rawValue: $0) }
            addUncertainty(
                type: uType, priority: uPriority, relatedItemId: relatedId,
                title: spec.title, body: spec.body, options: spec.options ?? [],
                triggeredAxiom: axiom
            )
        }
    }

    // MARK: - Action Dispatch

    /// Process an array of DesignActions from the chat response.
    /// Elaboration actions are collected and executed in parallel with bounded concurrency.
    private func dispatchActions(_ actions: [DesignAction]) async {
        var elaborationTargets: [(sectionType: String, itemId: UUID, agentId: UUID?)] = []

        for action in actions {
            guard !Task.isCancelled else { return }

            switch action {
            case .elaborateItem(let sectionType, let itemId, let agentId):
                elaborationTargets.append((sectionType, itemId, agentId))

            case .updateItem(let sectionType, let itemId, let changes):
                applyItemUpdate(sectionType: sectionType, itemId: itemId, changes: changes)

            case .addItem(let sectionType, let name, let briefDescription):
                applyAddItem(sectionType: sectionType, name: name, briefDescription: briefDescription)

            case .removeItem(let sectionType, let itemId):
                applyRemoveItem(sectionType: sectionType, itemId: itemId)

            case .addSection(let type, let label, let items):
                applyAddSection(type: type, label: label, skeletons: items)

            case .linkItems(let sourceId, let targetId, let relationType):
                applyLinkItems(sourceId: sourceId, targetId: targetId, relationType: relationType)

            case .unlinkItems(let sourceId, let targetId, let relationType):
                applyUnlinkItems(sourceId: sourceId, targetId: targetId, relationType: relationType)

            case .markComplete:
                // Do not auto-complete — notify the user so they can confirm manually
                let msg = DesignChatMessage(role: .system, content: lang.design.aiRequestedCompletion)
                workflow?.appendChatMessage(msg)

            case .raiseUncertainty(let type, let priority, let relatedItemId, let title, let body, let options, let triggeredAxiom):
                addUncertainty(type: type, priority: priority, relatedItemId: relatedItemId, title: title, body: body, options: options, triggeredAxiom: triggeredAxiom)
            }
        }

        if !elaborationTargets.isEmpty {
            await withTaskGroup(of: Void.self) { group in
                var running = 0
                var index = 0
                while index < elaborationTargets.count {
                    guard !Task.isCancelled else { return }
                    while running < currentMaxConcurrency && index < elaborationTargets.count {
                        let target = elaborationTargets[index]; index += 1; running += 1
                        group.addTask {
                            await self.runSingleItemElaboration(
                                sectionType: target.sectionType,
                                itemId: target.itemId,
                                preferredAgentId: target.agentId
                            )
                        }
                    }
                    await group.next()
                    running -= 1
                }
                await group.waitForAll()
            }
        }

        syncToRequest()
    }

    /// Directly update an item's spec fields and mark as needing revision or completed.
    private func applyItemUpdate(sectionType: String, itemId: UUID, changes: [String: AnyCodable]) {
        guard var wf = workflow else { return }
        wf.updateItem(itemId) { item in
            for (key, value) in changes {
                item.spec[key] = value
            }
            item.updatedAt = Date()
            // If the item was completed and is being updated, mark as needs revision
            if item.status == .completed {
                item.status = .needsRevision
            }
            // Recompute spec readiness after spec changes
            let issues = SpecReadinessValidator.validate(item: item, sectionType: sectionType)
            item.specReadiness = issues.contains(where: { $0.severity == .error }) ? .incomplete : .ready
        }
        workflow = wf
    }

    /// Add a new deliverable item to an existing section.
    private func applyAddItem(sectionType: String, name: String, briefDescription: String?) {
        guard var wf = workflow,
              let sectionIdx = wf.deliverables.firstIndex(where: { $0.type == sectionType }) else { return }
        let newItem = DeliverableItem(name: name, briefDescription: briefDescription)
        wf.deliverables[sectionIdx].items.append(newItem)
        wf.rebuildIndexes()
        workflow = wf
    }

    /// Remove a deliverable item from a section and clean up orphan edges.
    private func applyRemoveItem(sectionType: String, itemId: UUID) {
        setDesignVerdict(itemId, .excluded)
    }

    /// Add a new deliverable section with skeleton items.
    private func applyAddSection(type: String, label: String, skeletons: [DesignAnalysisResponse.ItemSkeleton]) {
        guard var wf = workflow else { return }
        let items = skeletons.map { skeleton in
            DeliverableItem(name: skeleton.name, briefDescription: skeleton.briefDescription, scenarioGroup: skeleton.scenarioGroup)
        }
        let section = DeliverableSection(type: type, label: label, items: items)
        wf.deliverables.append(section)
        wf.rebuildIndexes()
        workflow = wf
    }

    /// Record a relationship (edge) between two items in the work graph.
    private func applyLinkItems(sourceId: UUID, targetId: UUID, relationType: String) {
        guard var wf = workflow else { return }
        guard wf.findItem(byId: sourceId) != nil,
              wf.findItem(byId: targetId) != nil else { return }
        // Validate relationType — fall back to "uses" for unknown types
        let validatedType = EdgeRelationType.all.contains(relationType) ? relationType : EdgeRelationType.uses
        let edge = ItemEdge(sourceId: sourceId, targetId: targetId, relationType: validatedType)
        let added = wf.addEdgeIfNew(edge)
        if !added && validatedType == EdgeRelationType.dependsOn {
            // Cycle detected — notify via system message
            let srcName = wf.findItem(byId: sourceId)?.item.name ?? "?"
            let tgtName = wf.findItem(byId: targetId)?.item.name ?? "?"
            let sysMsg = DesignChatMessage(
                role: .system,
                content: "⚠️ Circular dependency detected: \(srcName) → \(tgtName). Edge not added."
            )
            wf.appendChatMessage(sysMsg)
        }
        workflow = wf
        syncParallelGroupsFromEdges()
    }

    /// Remove a relationship (edge) between two items.
    private func applyUnlinkItems(sourceId: UUID, targetId: UUID, relationType: String?) {
        guard var wf = workflow else { return }
        wf.edges.removeAll { edge in
            edge.sourceId == sourceId &&
            edge.targetId == targetId &&
            (relationType == nil || edge.relationType == relationType)
        }
        wf.rebuildIndexes()
        workflow = wf
        syncParallelGroupsFromEdges()
    }

    /// Remove an edge by ID (called from UI delete button).
    func removeEdge(id: UUID) {
        guard var wf = workflow else { return }
        wf.removeEdge(id: id)
        workflow = wf
        syncParallelGroupsFromEdges()
        syncToRequest()
    }

    /// Recompute and store parallelGroup for all items based on current edge graph.
    private func syncParallelGroupsFromEdges() {
        guard var wf = workflow else { return }
        let hasDependencyEdges = wf.edges.contains { $0.relationType == EdgeRelationType.dependsOn }
        guard hasDependencyEdges else { return }
        let groups = wf.computeParallelGroups()
        for si in wf.deliverables.indices {
            for ii in wf.deliverables[si].items.indices {
                let itemId = wf.deliverables[si].items[ii].id
                if let group = groups[itemId] {
                    wf.deliverables[si].items[ii].parallelGroup = group
                }
            }
        }
        workflow = wf
    }

    // MARK: - Item Elaboration (Step Agent Work)

    /// Public entry point: elaborate a single item, then sync.
    func runItemElaboration(sectionType: String, itemId: UUID, preferredAgentId: UUID? = nil) async {
        await runSingleItemElaboration(sectionType: sectionType, itemId: itemId, preferredAgentId: preferredAgentId)
        syncToRequest()
    }

    /// Core item elaboration logic. Safe for parallel invocation from TaskGroup.
    /// Uses direct `workflow?` mutation instead of copy-and-writeback to avoid race conditions.
    // MARK: - Shared Elaboration Context

    /// Pre-computed context snapshot to avoid redundant per-item traversals during bulk elaboration.
    /// Marked @unchecked Sendable because it is a read-only snapshot created before TaskGroup entry.
    private struct SharedElaborationContext: @unchecked Sendable {
        let itemsBySection: [UUID: [DeliverableItem]]  // sectionId → items with non-empty spec
        let crossSectionCompleted: [UUID: [(sectionLabel: String, item: DeliverableItem)]]  // sectionId → completed items from OTHER sections
        let edgeIndex: [UUID: [ItemEdge]]
        let allItemsById: [UUID: DeliverableItem]
        let allItemNames: [UUID: String]

        init(workflow wf: DesignWorkflow) {
            var bySection: [UUID: [DeliverableItem]] = [:]
            var allById: [UUID: DeliverableItem] = [:]
            var names: [UUID: String] = [:]
            for section in wf.deliverables {
                bySection[section.id] = section.items.filter { !$0.spec.isEmpty }
                for item in section.items {
                    allById[item.id] = item
                    names[item.id] = item.name
                }
            }
            self.itemsBySection = bySection
            self.allItemsById = allById
            self.allItemNames = names

            // Pre-compute cross-section completed items for each section
            var crossSection: [UUID: [(sectionLabel: String, item: DeliverableItem)]] = [:]
            let allCompleted: [(sectionId: UUID, sectionLabel: String, item: DeliverableItem)] =
                wf.deliverables.flatMap { sec in
                    sec.items.filter { $0.status == .completed && !$0.spec.isEmpty }
                        .map { (sectionId: sec.id, sectionLabel: sec.label, item: $0) }
                }
            for section in wf.deliverables {
                crossSection[section.id] = allCompleted
                    .filter { $0.sectionId != section.id }
                    .map { (sectionLabel: $0.sectionLabel, item: $0.item) }
            }
            self.crossSectionCompleted = crossSection

            // Snapshot edge index
            var eIdx: [UUID: [ItemEdge]] = [:]
            for edge in wf.edges {
                eIdx[edge.sourceId, default: []].append(edge)
                eIdx[edge.targetId, default: []].append(edge)
            }
            self.edgeIndex = eIdx
        }

        func edges(for itemId: UUID) -> [ItemEdge] {
            edgeIndex[itemId] ?? []
        }
    }

    /// Build edge context lines for a specific item using pre-computed context.
    private func buildEdgeLines(
        itemId: UUID,
        context: SharedElaborationContext
    ) -> [String] {
        let directEdges = context.edges(for: itemId)
        var lines: [String] = directEdges.compactMap { edge -> String? in
            let isSource = edge.sourceId == itemId
            let otherId = isSource ? edge.targetId : edge.sourceId
            guard let otherName = context.allItemNames[otherId] else { return nil }
            return isSource
                ? "\(edge.relationType) → \(otherName)"
                : "← \(otherName) (\(edge.relationType))"
        }

        // 2-hop: items connected to directly-connected items
        let directIds = Set(directEdges.flatMap { [$0.sourceId, $0.targetId] }).subtracting([itemId])
        for directId in directIds {
            let secondHopEdges = context.edges(for: directId).filter { $0.sourceId != itemId && $0.targetId != itemId }
            for edge in secondHopEdges.prefix(3) {
                let isSource = edge.sourceId == directId
                let otherId = isSource ? edge.targetId : edge.sourceId
                let directName = context.allItemNames[directId] ?? "?"
                guard let otherName = context.allItemNames[otherId] else { continue }
                lines.append("(indirect via \(directName)) \(edge.relationType) → \(otherName)")
            }
        }

        // Completed spec summaries for direct dependency targets
        let dependencySpecs = directEdges
            .filter { $0.sourceId == itemId && $0.relationType == EdgeRelationType.dependsOn }
            .compactMap { context.allItemsById[$0.targetId] }
            .filter { $0.status == .completed && !$0.spec.isEmpty }
        for dep in dependencySpecs.prefix(5) {
            let specKeys = dep.spec.keys.sorted().prefix(5).joined(separator: ", ")
            lines.append("(dependency spec) \(dep.name): keys=[\(specKeys)]")
        }

        return lines
    }

    private func runSingleItemElaboration(sectionType: String, itemId: UUID, preferredAgentId: UUID? = nil, sharedContext: SharedElaborationContext? = nil) async {
        guard let wf = workflow,
              let found = wf.findItem(byId: itemId) else { return }

        let section = wf.deliverables[found.sectionIndex]
        let item = found.item

        // Set item status to in-progress (direct mutation)
        workflow?.updateItem(itemId) { $0.status = .inProgress }

        // Resolve step agent — prefer assigned agent, then round-robin, then Claude fallback
        let agent: Agent? = nextStepAgent(preferredId: preferredAgentId)
        let agentLabel = agent.map { "\($0.provider.rawValue) / \($0.model)" } ?? "step agent"
        logEvent(DesignEventType.elaborationStarted, payload: [
            "itemId": itemId.uuidString,
            "itemName": item.name,
            "agent": agentLabel,
        ])

        // Set active item work for UI
        activeItemWorks[itemId] = ActiveItemWork(
            sectionType: sectionType,
            itemId: itemId,
            itemName: item.name,
            agentLabel: agentLabel,
            streamOutput: ""
        )

        // Add system message to chat
        let systemMsg = DesignChatMessage(role: .system, content: "Elaborating \(item.name)...")
        workflow?.appendChatMessage(systemMsg)

        // Gather context — use pre-computed shared context if available, otherwise compute per-item
        let relatedItems: [DeliverableItem]
        let crossSectionItems: [(sectionLabel: String, item: DeliverableItem)]
        let itemEdgeLines: [String]

        if let ctx = sharedContext {
            relatedItems = (ctx.itemsBySection[section.id] ?? []).filter { $0.id != itemId }
            crossSectionItems = ctx.crossSectionCompleted[section.id] ?? []
            itemEdgeLines = buildEdgeLines(itemId: itemId, context: ctx)
        } else {
            // Fallback: per-item context gathering (used for single-item elaboration)
            relatedItems = section.items.filter { $0.id != itemId && !$0.spec.isEmpty }
            crossSectionItems = wf.deliverables
                .filter { $0.id != section.id }
                .flatMap { sec in
                    sec.items.filter { $0.status == .completed && !$0.spec.isEmpty }
                        .map { (sectionLabel: sec.label, item: $0) }
                }

            let directEdges = wf.edges(for: itemId)
            var edgeLines: [String] = directEdges.compactMap { edge -> String? in
                let isSource = edge.sourceId == itemId
                let otherId = isSource ? edge.targetId : edge.sourceId
                guard let other = wf.findItem(byId: otherId) else { return nil }
                if isSource {
                    return "\(edge.relationType) → \(other.item.name)"
                } else {
                    return "← \(other.item.name) (\(edge.relationType))"
                }
            }

            let directIds = Set(directEdges.flatMap { [$0.sourceId, $0.targetId] }).subtracting([itemId])
            for directId in directIds {
                let secondHopEdges = wf.edges(for: directId).filter { $0.sourceId != itemId && $0.targetId != itemId }
                for edge in secondHopEdges.prefix(3) {
                    let isSource = edge.sourceId == directId
                    let otherId = isSource ? edge.targetId : edge.sourceId
                    let directName = wf.findItem(byId: directId)?.item.name ?? "?"
                    guard let other = wf.findItem(byId: otherId) else { continue }
                    edgeLines.append("(indirect via \(directName)) \(edge.relationType) → \(other.item.name)")
                }
            }

            let dependencySpecs = directEdges
                .filter { $0.sourceId == itemId && $0.relationType == EdgeRelationType.dependsOn }
                .compactMap { wf.findItem(byId: $0.targetId) }
                .filter { $0.item.status == .completed && !$0.item.spec.isEmpty }
            for dep in dependencySpecs.prefix(5) {
                let specKeys = dep.item.spec.keys.sorted().prefix(5).joined(separator: ", ")
                edgeLines.append("(dependency spec) \(dep.item.name): keys=[\(specKeys)]")
            }
            itemEdgeLines = edgeLines
        }

        // Build elaboration prompt
        let prompt = promptBuilder.buildItemElaborationPrompt(
            section: section,
            item: item,
            projectSpec: wf.projectSpec,
            relatedItems: relatedItems,
            crossSectionItems: crossSectionItems,
            itemEdgeLines: itemEdgeLines
        )

        // Record start time for duration tracking
        let elaborationStart = Date()
        let maxRetries = 3
        var lastError: Error?

        for attempt in 0..<maxRetries {
            guard !Task.isCancelled else { return }

            // Exponential backoff for retries (longer for rate limits)
            if attempt > 0 {
                let retryMsg = DesignChatMessage(
                    role: .system,
                    content: lang.design.retryingFormat(attempt + 1, maxRetries)
                )
                workflow?.appendChatMessage(retryMsg)

                let isRateLimit = (lastError as? ProviderRequestError)?.status == "rate_limited"
                let backoffTable: [UInt64] = isRateLimit ? [2, 8, 20] : [0, 2, 4]
                let backoff = backoffTable[min(attempt, backoffTable.count - 1)]
                try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                guard !Task.isCancelled else { return }
            }

            do {
                guard let runAgent = agent else {
                    throw DesignError.noAgent(lang.common.noAgentConfigured)
                }

                let accumulator = StreamAccumulator()
                let throttle = ThrottledMainActorUpdater(interval: 0.15)
                self.lastCheckpointTime[itemId] = Date()
                let response = try await container.cliAgentRunner.runStreaming(
                    agent: runAgent,
                    prompt: prompt,
                    projectId: project.id,
                    rootPath: project.rootPath
                ) { [weak self] chunk in
                    guard !Task.isCancelled else { return }
                    let text = accumulator.append(chunk)
                    let now = Date()
                    throttle.update(text) { [weak self] text in
                        self?.activeItemWorks[itemId]?.streamOutput = text
                        // Checkpoint partial output every 5 seconds for crash resilience
                        if let lastCP = self?.lastCheckpointTime[itemId],
                           now.timeIntervalSince(lastCP) >= 5.0 {
                            self?.workflow?.updateItem(itemId) { item in
                                item.partialOutput = text
                                item.lastCheckpoint = now
                            }
                            self?.lastCheckpointTime[itemId] = now
                        }
                    }
                }
                // Flush any pending throttled update to ensure final text is displayed
                throttle.flush { [weak self] text in
                    self?.activeItemWorks[itemId]?.streamOutput = text
                }

                trackUsage(promptLength: prompt.count, responseLength: response.count)
                guard !Task.isCancelled else { return }

                // Parse item spec and uncertainties from output
                let parseResult = DesignStepResultParser.parseItemSpecWithUncertainties(from: response)
                let parsedSpec = parseResult.spec
                let stepUncertainties = parseResult.uncertainties

                if parsedSpec == nil {
                    logger.warning("parseItemSpec failed for \(item.name, privacy: .public)")
                    logger.debug("Response length: \(response.count) chars")
                    logger.debug("Response preview: \(String(response.prefix(500)), privacy: .public)")
                }

                // Process step agent uncertainties through Design triage
                if !stepUncertainties.isEmpty {
                    await triageStepUncertainties(stepUncertainties, item: item, sectionType: sectionType)
                }

                // Calculate duration
                let durationMs = Int(Date().timeIntervalSince(elaborationStart) * 1000)

                // Update item with spec — direct mutation to avoid race conditions
                workflow?.updateItem(itemId) { item in
                    if let spec = parsedSpec {
                        item.spec = spec
                        item.status = .completed
                    } else {
                        item.spec = ["_rawResponse": AnyCodable(String(response.prefix(5000)))]
                        item.status = .needsRevision
                    }
                    item.version += 1
                    item.updatedAt = Date()
                    // Judgment gate: reset verdict so planner must re-review
                    item.plannerVerdict = .unreviewed
                    // Preserve confirmed verdict — user's explicit approval stays valid after elaboration
                    if item.designVerdict != .confirmed {
                        item.designVerdict = .pending
                    }
                    // Auto-compute spec readiness (agent-internal layer)
                    if parsedSpec != nil {
                        let issues = SpecReadinessValidator.validate(item: item, sectionType: sectionType)
                        item.specReadiness = issues.contains(where: { $0.severity == .error }) ? .incomplete : .ready
                    } else {
                        item.specReadiness = .notValidated
                    }
                    // Record per-item tracking data
                    item.inputTokens = prompt.count / 4
                    item.outputTokens = response.count / 4
                    item.elaborationDurationMs = durationMs
                    item.lastAgentId = runAgent.id
                    item.lastAgentLabel = agentLabel
                    // Clear checkpoint and error data on completion
                    item.partialOutput = nil
                    item.lastCheckpoint = nil
                    item.lastElaborationError = nil
                }

                // Add completion system message
                let completionMsg = DesignChatMessage(
                    role: .system,
                    content: "\(item.name) elaboration completed."
                )
                workflow?.appendChatMessage(completionMsg)

                // Success — break out of retry loop
                logEvent(DesignEventType.elaborationCompleted, payload: [
                    "itemId": itemId.uuidString,
                    "itemName": item.name,
                    "durationMs": durationMs,
                    "parsed": parsedSpec != nil,
                ])
                recordElaborationSuccess()
                lastError = nil
                break

            } catch {
                guard !Task.isCancelled else { return }
                lastError = error

                // Adaptive concurrency: reduce on rate limit
                if let providerError = error as? ProviderRequestError,
                   providerError.status == "rate_limited" {
                    reduceConcurrency()
                }

                // If this was the last attempt, mark as needsRevision
                if attempt == maxRetries - 1 {
                    workflow?.updateItem(itemId) { item in
                        item.status = .needsRevision
                        item.lastElaborationError = error.localizedDescription
                    }
                    logEvent(DesignEventType.elaborationFailed, payload: [
                        "itemId": itemId.uuidString,
                        "itemName": item.name,
                        "error": error.localizedDescription,
                    ])

                    let errorMsg = DesignChatMessage(
                        role: .system,
                        content: "Failed to elaborate \(item.name): \(error.localizedDescription)"
                    )
                    workflow?.appendChatMessage(errorMsg)
                }
            }
        }

        // Clear active item work and checkpoint tracking for this item
        activeItemWorks.removeValue(forKey: itemId)
        lastCheckpointTime.removeValue(forKey: itemId)
        // Fire-and-forget sync for crash resilience
        syncToRequest()
    }

    // MARK: - Uncertainty Triage (Step → Design → User)

    /// Triage uncertainties surfaced by a Step agent: Design decides autonomous resolve vs escalate.
    private func triageStepUncertainties(
        _ uncertainties: [DesignAnalysisResponse.UncertaintySpec],
        item: DeliverableItem,
        sectionType: String
    ) async {
        guard let wf = workflow else { return }

        // Helper: escalate all uncertainties to user (used as fallback)
        func escalateAllToUser() {
            for spec in uncertainties {
                let uType = UncertaintyType(rawValue: spec.type) ?? .question
                let uPriority = spec.priority.flatMap { UncertaintyPriority(rawValue: $0) } ?? .important
                let axiom = spec.triggeredBy.flatMap { UncertaintyAxiom(rawValue: $0) }
                addUncertainty(
                    type: uType, priority: uPriority, relatedItemId: item.id,
                    title: spec.title, body: spec.body, options: spec.options ?? [],
                    triggeredAxiom: axiom
                )
            }
        }

        let promptBuilder = DesignPromptBuilder(
            workflow: wf, taskInput: taskInput,
            availableAgents: availableAgents, project: project,
            requestId: requestId, ideaId: ideaId,
            designBriefJSON: cachedDesignBriefJSON.isEmpty ? nil : cachedDesignBriefJSON,
            userProfile: userProfile
        )
        let triagePrompt = promptBuilder.buildUncertaintyTriagePrompt(
            uncertainties: uncertainties, item: item, sectionType: sectionType
        )

        // Run triage through Design agent
        guard let designAgent = resolveDesignAgent() else {
            escalateAllToUser()
            return
        }

        do {
            let response = try await container.cliAgentRunner.run(
                agent: designAgent, prompt: triagePrompt,
                projectId: project.id, rootPath: project.rootPath,
                jsonSchema: DesignJSONSchemas.triage
            )
            trackUsage(promptLength: triagePrompt.count, responseLength: response.count)

            // Parse triage decisions
            struct TriageResult: Codable {
                let index: Int
                let action: String
                let reasoning: String?
            }

            let jsonString = DesignStepResultParser.extractJSON(from: response) ?? response
            guard let data = jsonString.data(using: .utf8) else {
                escalateAllToUser()
                return
            }
            let results: [TriageResult]
            do {
                results = try JSONDecoder().decode([TriageResult].self, from: data)
            } catch {
                logger.warning("[Triage] Failed to decode triage response: \(error.localizedDescription, privacy: .public)")
                escalateAllToUser()
                return
            }

            for result in results {
                let idx = result.index - 1  // 1-indexed → 0-indexed
                guard idx >= 0 && idx < uncertainties.count else { continue }
                let spec = uncertainties[idx]
                let uType = UncertaintyType(rawValue: spec.type) ?? .question
                let uPriority = spec.priority.flatMap { UncertaintyPriority(rawValue: $0) } ?? .important
                let axiom = spec.triggeredBy.flatMap { UncertaintyAxiom(rawValue: $0) }

                if result.action == "autonomous_resolve" {
                    addUncertainty(
                        type: uType, priority: uPriority, relatedItemId: item.id,
                        title: spec.title, body: spec.body, options: spec.options ?? [],
                        isAutonomous: true, autonomousReasoning: result.reasoning,
                        triggeredAxiom: axiom
                    )
                } else {
                    addUncertainty(
                        type: uType, priority: uPriority, relatedItemId: item.id,
                        title: spec.title, body: spec.body, options: spec.options ?? [],
                        triggeredAxiom: axiom
                    )
                }
            }
        } catch {
            logger.warning("Uncertainty triage failed: \(error.localizedDescription, privacy: .public)")
            escalateAllToUser()
        }
    }

    // MARK: - Elaborate All Pending

    /// Re-run analysis from scratch, optionally with client feedback on what to change.
    func reanalyzeWithFeedback(_ feedback: String? = nil) {
        let summary = buildPreviousAnalysisSummary()
        pendingReanalyzeFeedback = feedback
        previousAnalysisSummary = (feedback != nil) ? summary : nil
        restartWorkflow()
    }

    /// Build a concise summary of the current analysis for re-analysis context.
    private func buildPreviousAnalysisSummary() -> String? {
        guard let wf = workflow else { return nil }
        var lines: [String] = []
        if let approaches = wf.approachOptions, !approaches.isEmpty {
            lines.append("Previous approaches:")
            for a in approaches {
                let marker = (a.id == wf.selectedApproachId) ? " [SELECTED]" : ""
                lines.append("- \(a.label)\(marker): \(a.summary)")
            }
        }
        if !wf.deliverables.isEmpty {
            lines.append("Previous deliverables:")
            for s in wf.deliverables {
                let names = s.items.map(\.name).joined(separator: ", ")
                lines.append("- \(s.label): \(names)")
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Retry elaboration for a failed item (shown in inspector as retry button).
    func retryElaboration(_ itemId: UUID) {
        guard let wf = workflow,
              let (sectionIdx, _, item) = wf.findItem(byId: itemId),
              item.status == .needsRevision else { return }
        let sectionType = wf.deliverables[sectionIdx].type
        workflow?.updateItem(itemId) { $0.status = .pending; $0.lastElaborationError = nil }
        syncToRequest()
        executionTask?.cancel()
        executionTask = Task { await elaborateItems([(itemId, sectionType)]) }
    }

    /// Re-elaborate an item after the user requested revision via designVerdict.
    func revisionElaboration(_ itemId: UUID) {
        guard let wf = workflow,
              let (sectionIdx, _, item) = wf.findItem(byId: itemId),
              item.designVerdict == .needsRevision,
              (item.status == .completed || item.status == .pending) else { return }
        let sectionType = wf.deliverables[sectionIdx].type
        workflow?.updateItem(itemId) { $0.status = .pending; $0.lastElaborationError = nil }
        syncToRequest()
        executionTask?.cancel()
        executionTask = Task { await elaborateItems([(itemId, sectionType)]) }
    }

    // MARK: - Revision Review Overlay

    /// Reset revision overlay state for a new review session.
    func beginRevisionReview(for itemId: UUID) {
        revisionChatMessages = []
        revisionStreamOutput = ""
        isRevisionChatting = false
        pendingRevisionActions = nil
        isRevisionApplying = false
        isRevisionElaborating = false
        revisionCompleted = false
    }

    /// Send a message in the revision review overlay. Director reviews and proposes actions.
    func sendRevisionMessage(_ text: String, for itemId: UUID) {
        guard !text.isEmpty, !isRevisionChatting else { return }

        let userMsg = DesignChatMessage(role: .user, content: text)
        revisionChatMessages.append(userMsg)

        revisionExecutionTask?.cancel()
        revisionExecutionTask = Task {
            await runRevisionChat(userMessage: text, itemId: itemId)
        }
    }

    /// Approve pending revision actions and trigger re-elaboration.
    /// Overlay stays open — caller should NOT dismiss.
    func approveRevisionActions(for itemId: UUID) {
        guard let actions = pendingRevisionActions, !actions.isEmpty else { return }

        // Set revision verdict and note from conversation
        let conversationSummary = revisionChatMessages
            .filter { $0.role == .user }
            .map(\.content)
            .joined(separator: "\n")
        setDesignVerdict(itemId, .needsRevision)
        setRevisionNote(itemId, note: conversationSummary)

        // Check if director already included elaborate_item for the target
        let directorIncludesElaboration = actions.contains { action in
            if case .elaborateItem(_, let id, _) = action { return id == itemId }
            return false
        }
        // Check if director excluded the target item
        let directorExcludesTarget = actions.contains { action in
            if case .removeItem(_, let id) = action { return id == itemId }
            return false
        }

        // Dispatch director-proposed actions, then re-elaborate if needed
        let actionsToDispatch = actions
        pendingRevisionActions = nil
        isRevisionApplying = true

        revisionExecutionTask?.cancel()
        revisionExecutionTask = Task {
            await dispatchActions(actionsToDispatch)
            isRevisionApplying = false

            // Skip re-elaboration if director already handled it or excluded the item
            let needsReElaboration = !directorIncludesElaboration && !directorExcludesTarget
            if needsReElaboration {
                isRevisionElaborating = true
                await revisionElaborationAndWait(itemId)
                isRevisionElaborating = false
            }

            revisionCompleted = true
        }
    }

    /// Re-elaborate and wait for completion (used by revision overlay to track progress).
    private func revisionElaborationAndWait(_ itemId: UUID) async {
        guard let wf = workflow,
              let (sectionIdx, _, item) = wf.findItem(byId: itemId),
              item.designVerdict == .needsRevision,
              (item.status == .completed || item.status == .pending) else { return }
        let sectionType = wf.deliverables[sectionIdx].type
        workflow?.updateItem(itemId) { $0.status = .pending; $0.lastElaborationError = nil }
        syncToRequest()
        await elaborateItems([(itemId, sectionType)])
    }

    private func runRevisionChat(userMessage: String, itemId: UUID) async {
        isRevisionChatting = true
        revisionStreamOutput = ""
        defer {
            isRevisionChatting = false
            revisionStreamOutput = ""
        }

        let prompt = promptBuilder.buildRevisionReviewPrompt(
            itemId: itemId,
            chatHistory: revisionChatMessages,
            userMessage: userMessage,
            deliverables: workflow?.deliverables ?? []
        )

        do {
            let (response, _) = try await runWithFallback(prompt: prompt, jsonSchema: DesignJSONSchemas.chat) { [weak self] text in
                guard !Task.isCancelled else { return }
                Task { @MainActor in
                    self?.revisionStreamOutput = text
                }
            }

            guard !Task.isCancelled else { return }

            // [REVISION-DEBUG] TEMP — remove after verification
            print("[REVISION-DEBUG] ===== runRevisionChat response =====")
            print("[REVISION-DEBUG] raw length=\(response.count)")
            print("[REVISION-DEBUG] raw response:\n\(response)")
            print("[REVISION-DEBUG] ===================================")

            if let chatResponse = DesignStepResultParser.parseChatResponse(from: response) {
                // [REVISION-DEBUG]
                print("[REVISION-DEBUG] parsed message head: \(chatResponse.message.prefix(160))")
                print("[REVISION-DEBUG] parsed actions count: \(chatResponse.actions?.count ?? -1)")
                if let acts = chatResponse.actions {
                    for (i, a) in acts.enumerated() {
                        let changesDesc: String
                        if let ch = a.changes {
                            changesDesc = "present(keys=\(ch.keys.sorted()))"
                        } else {
                            changesDesc = "nil"
                        }
                        print("[REVISION-DEBUG]   action[\(i)] type=\(a.type) sectionType=\(a.sectionType ?? "nil") itemId=\(a.itemId ?? "nil") itemName=\(a.itemName ?? "nil") changes=\(changesDesc)")
                    }
                }

                let designMsg = DesignChatMessage(role: .design, content: chatResponse.message)
                revisionChatMessages.append(designMsg)

                // Store proposed actions for user approval (NOT auto-dispatched)
                if let actionJSONs = chatResponse.actions, let wf = workflow {
                    let actions = actionJSONs.compactMap { DesignAction.from(json: $0, workflow: wf) }
                    // [REVISION-DEBUG]
                    print("[REVISION-DEBUG] after compactMap: \(actions.count) / \(actionJSONs.count) survived")
                    if !actions.isEmpty {
                        pendingRevisionActions = actions
                        print("[REVISION-DEBUG] pendingRevisionActions SET (count=\(actions.count))")
                    } else {
                        print("[REVISION-DEBUG] pendingRevisionActions NOT set — empty after compactMap")
                    }
                } else {
                    print("[REVISION-DEBUG] chatResponse.actions is nil or workflow missing")
                }
            } else {
                // [REVISION-DEBUG]
                print("[REVISION-DEBUG] parseChatResponse returned nil — falling back to plain message")
                let message = DesignStepResultParser.extractChatMessage(from: response)
                let designMsg = DesignChatMessage(role: .design, content: message)
                revisionChatMessages.append(designMsg)
            }
        } catch {
            // [REVISION-DEBUG]
            print("[REVISION-DEBUG] runRevisionChat threw: \(error)")
            let errorMsg = DesignChatMessage(role: .system, content: error.localizedDescription)
            revisionChatMessages.append(errorMsg)
        }
    }

    // MARK: - Planner Verdict

    /// Set the planner verdict for a single item (internal/agent use).
    /// Does NOT auto-sync directorVerdict — director verdict is the human decision-maker's
    /// independent judgment and must only be changed via setDesignVerdict().
    func setVerdict(_ itemId: UUID, _ verdict: PlannerVerdict) {
        workflow?.updateItem(itemId) { item in
            item.plannerVerdict = verdict
            item.updatedAt = Date()
        }
        syncToRequest()
    }

    /// Set the planner verdict for multiple items at once (internal/agent use).
    /// Does NOT auto-sync directorVerdict — see setVerdict() comment.
    func setVerdictBatch(_ itemIds: [UUID], _ verdict: PlannerVerdict) {
        guard var wf = workflow else { return }
        for itemId in itemIds {
            wf.updateItem(itemId) { item in
                item.plannerVerdict = verdict
                item.updatedAt = Date()
            }
        }
        workflow = wf
        syncToRequest()
    }

    // MARK: - Design Verdict (decision-maker facing)

    /// Set the decision-maker's directional verdict for a single item.
    func setDesignVerdict(_ itemId: UUID, _ verdict: DesignVerdict) {
        let previousVerdict = workflow?.findItem(byId: itemId)?.item.designVerdict
        workflow?.updateItem(itemId) { item in
            item.designVerdict = verdict
            item.updatedAt = Date()
            // Track oscillation: confirmed↔needsRevision transitions
            if (previousVerdict == .confirmed && verdict == .needsRevision)
                || (previousVerdict == .needsRevision && verdict == .confirmed) {
                item.verdictFlipCount += 1
            }
            // Clear revision note when leaving needsRevision
            if verdict != .needsRevision {
                item.revisionNote = nil
            }
            // Sync legacy field for backward compatibility
            switch verdict {
            case .confirmed:     item.plannerVerdict = .approved
            case .pending:       item.plannerVerdict = .unreviewed
            case .needsRevision: item.plannerVerdict = .unreviewed
            case .excluded:      item.plannerVerdict = .rejected
            }
        }
        logEvent(DesignEventType.verdictChanged, payload: [
            "itemId": itemId.uuidString,
            "from": previousVerdict?.rawValue ?? "nil",
            "to": verdict.rawValue,
        ])
        // Log oscillation event when flip threshold reached
        if let item = workflow?.findItem(byId: itemId)?.item,
           item.verdictFlipCount >= 2,
           (previousVerdict == .confirmed && verdict == .needsRevision) {
            logEvent(DesignEventType.convergenceOscillation, payload: [
                "itemId": itemId.uuidString,
                "itemName": item.name,
                "flipCount": item.verdictFlipCount,
            ])
        }
        // Auto-deselect excluded items so the inspector returns to overview
        if verdict == .excluded && selectedItemId == itemId {
            selectedItemId = nil
        }
        syncToRequest()
        if workflow?.allItemsConfirmed == true { shouldPromptCompletion = true }
    }

    /// Set the decision-maker's verdict for multiple items at once.
    func setDesignVerdictBatch(_ itemIds: [UUID], _ verdict: DesignVerdict) {
        guard var wf = workflow else { return }
        for itemId in itemIds {
            let previousVerdict = wf.findItem(byId: itemId)?.item.designVerdict
            wf.updateItem(itemId) { item in
                item.designVerdict = verdict
                item.updatedAt = Date()
                if (previousVerdict == .confirmed && verdict == .needsRevision)
                    || (previousVerdict == .needsRevision && verdict == .confirmed) {
                    item.verdictFlipCount += 1
                }
                switch verdict {
                case .confirmed:     item.plannerVerdict = .approved
                case .pending:       item.plannerVerdict = .unreviewed
                case .needsRevision: item.plannerVerdict = .unreviewed
                case .excluded:      item.plannerVerdict = .rejected
                }
            }
        }
        workflow = wf
        syncToRequest()
        if workflow?.allItemsConfirmed == true { shouldPromptCompletion = true }
    }

    // MARK: - Decision Audit Trail

    func loadDecisionHistory() async {
        guard let reqId = requestId else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }

        let events = await container.designEventService.listEvents(sessionId: reqId, limit: 200, offset: 0)
        let decisionTypes: Set<String> = [
            DesignEventType.verdictChanged,
            "approach_selected",
            DesignEventType.uncertaintyResolved,
            DesignEventType.uncertaintyDismissed,
        ]

        decisionHistory = events
            .filter { decisionTypes.contains($0.eventType) }
            .compactMap { event -> DecisionHistoryEntry? in
                let payload = parsePayload(event.payloadJSON)
                switch event.eventType {
                case DesignEventType.verdictChanged:
                    guard let to = payload?["to"] as? String else { return nil }
                    let itemId = (payload?["itemId"] as? String).flatMap(UUID.init)
                    let itemName = itemId.flatMap { id in workflow?.findItem(byId: id)?.item.name } ?? ""
                    let cat: DecisionHistoryEntry.DecisionCategory = to == "confirmed" ? .itemConfirmed : .itemRevisionRequested
                    let summary = to == "confirmed"
                        ? "\(lang.design.verdictConfirmed): \(itemName)"
                        : "\(lang.design.verdictNeedsRevision): \(itemName)"
                    return DecisionHistoryEntry(id: event.id, timestamp: event.createdAt, category: cat, summary: summary, relatedItemId: itemId)
                case "approach_selected":
                    let label = payload?["label"] as? String ?? ""
                    return DecisionHistoryEntry(id: event.id, timestamp: event.createdAt, category: .approachSelected, summary: label, relatedItemId: nil)
                case DesignEventType.uncertaintyResolved:
                    let desc = payload?["description"] as? String ?? ""
                    return DecisionHistoryEntry(id: event.id, timestamp: event.createdAt, category: .uncertaintyResolved, summary: desc, relatedItemId: nil)
                case DesignEventType.uncertaintyDismissed:
                    let desc = payload?["description"] as? String ?? ""
                    return DecisionHistoryEntry(id: event.id, timestamp: event.createdAt, category: .uncertaintyDismissed, summary: desc, relatedItemId: nil)
                default:
                    return nil
                }
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func parsePayload(_ json: String?) -> [String: Any]? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Remove an item (sets internal rejected state, resets director verdict).
    func removeItem(_ itemId: UUID) {
        workflow?.updateItem(itemId) { item in
            item.plannerVerdict = .rejected
            item.designVerdict = .pending
            item.updatedAt = Date()
        }
        syncToRequest()
    }

    // MARK: - Uncertainty Escalation

    /// Computed: pending uncertainties across the entire workflow.
    var pendingUncertainties: [DesignDecision] {
        workflow?.pendingUncertainties ?? []
    }

    /// Computed: uncertainties for the currently selected item.
    var uncertaintiesForSelectedItem: [DesignDecision] {
        guard let id = selectedItemId else { return [] }
        return workflow?.uncertainties(for: id) ?? []
    }

    /// True when any blocking uncertainty exists.
    var hasBlockingUncertainties: Bool {
        workflow?.blockingUncertainties.isEmpty == false
    }

    /// Add a new uncertainty escalation to the workflow.
    func addUncertainty(
        type: UncertaintyType,
        priority: UncertaintyPriority,
        relatedItemId: UUID?,
        title: String,
        body: String,
        options: [String],
        isAutonomous: Bool = false,
        autonomousReasoning: String? = nil,
        triggeredAxiom: UncertaintyAxiom? = nil
    ) {
        // De-duplicate: skip if same title + relatedItemId already pending
        if let existing = workflow?.uncertainties.first(where: {
            $0.title == title && $0.relatedItemId == relatedItemId && $0.status == .pending
        }) {
            logger.debug("Skipping duplicate uncertainty: \(existing.title, privacy: .public)")
            return
        }

        let decision = DesignDecision(
            title: title,
            body: body,
            options: options,
            status: isAutonomous ? .approved : .pending,
            isAutonomous: isAutonomous,
            escalationType: type,
            priority: priority,
            relatedItemId: relatedItemId,
            resolvedAt: isAutonomous ? Date() : nil,
            autonomousReasoning: autonomousReasoning,
            triggeredAxiom: triggeredAxiom
        )
        workflow?.uncertainties.append(decision)

        let eventType = isAutonomous
            ? DesignEventType.uncertaintyAutoResolved
            : DesignEventType.uncertaintyRaised
        logEvent(eventType, payload: [
            "uncertaintyId": decision.id.uuidString,
            "type": type.rawValue,
            "priority": priority.rawValue,
            "title": title,
            "relatedItemId": relatedItemId?.uuidString ?? "nil",
            "isAutonomous": isAutonomous,
            "axiom": triggeredAxiom?.rawValue ?? "nil",
        ])

        syncToRequest()
    }

    /// Resolve an uncertainty with a selected option (for suggestion type).
    func resolveUncertainty(_ id: UUID, selectedOption: String) {
        workflow?.resolveUncertainty(id) { decision in
            decision.status = .approved
            decision.selectedOption = selectedOption
            decision.resolvedAt = Date()
        }

        // Inject resolution into chat context
        let designMsg = DesignChatMessage(
            role: .design,
            content: "Uncertainty resolved — \(selectedOption)"
        )
        workflow?.appendChatMessage(designMsg)

        logEvent(DesignEventType.uncertaintyResolved, payload: [
            "uncertaintyId": id.uuidString,
            "selectedOption": selectedOption,
        ])
        syncToRequest()
        if workflow?.allItemsConfirmed == true { shouldPromptCompletion = true }
    }

    /// Resolve an uncertainty with a free-text response (for question/informationGap type).
    func resolveUncertaintyWithText(_ id: UUID, response: String) {
        var title = ""
        workflow?.resolveUncertainty(id) { decision in
            decision.status = .approved
            decision.userResponse = response
            decision.resolvedAt = Date()
            title = decision.title
        }

        let designMsg = DesignChatMessage(
            role: .design,
            content: "Uncertainty resolved (\(title)): \(response)"
        )
        workflow?.appendChatMessage(designMsg)

        logEvent(DesignEventType.uncertaintyResolved, payload: [
            "uncertaintyId": id.uuidString,
            "response": String(response.prefix(200)),
        ])
        syncToRequest()
        if workflow?.allItemsConfirmed == true { shouldPromptCompletion = true }
    }

    /// Dismiss an advisory uncertainty.
    func dismissUncertainty(_ id: UUID) {
        workflow?.resolveUncertainty(id) { decision in
            decision.status = .rejected
            decision.resolvedAt = Date()
        }
        logEvent(DesignEventType.uncertaintyDismissed, payload: [
            "uncertaintyId": id.uuidString,
        ])
        syncToRequest()
        if workflow?.allItemsConfirmed == true { shouldPromptCompletion = true }
    }

    /// Reopen an autonomously-resolved uncertainty (user disagrees with Design's judgment).
    func reopenUncertainty(_ id: UUID) {
        workflow?.resolveUncertainty(id) { decision in
            decision.status = .pending
            decision.isAutonomous = false
            decision.resolvedAt = nil
            decision.autonomousReasoning = nil
        }
        logEvent(DesignEventType.uncertaintyRaised, payload: [
            "uncertaintyId": id.uuidString,
            "reopened": true,
        ])
        syncToRequest()
    }

    // MARK: - Uncertainty Discussion

    /// Initialize uncertainty discussion overlay state.
    func beginUncertaintyDiscussion(_ uncertaintyId: UUID) {
        uncertaintyChatMessages = []
        uncertaintyStreamOutput = ""
        isUncertaintyChatting = false
        pendingUncertaintyResolution = nil
        uncertaintyDiscussionCompleted = false
        uncertaintyDiscussionTask?.cancel()
        uncertaintyDiscussionTask = nil

        // Focus related item in inspector
        if let uncertainty = workflow?.uncertainties.first(where: { $0.id == uncertaintyId }),
           let itemId = uncertainty.relatedItemId {
            selectedItemId = itemId
        }
    }

    /// Send a user message in the uncertainty discussion overlay.
    func sendUncertaintyMessage(_ text: String, for uncertaintyId: UUID) {
        guard !text.isEmpty, !isUncertaintyChatting else { return }

        let userMsg = DesignChatMessage(role: .user, content: text)
        uncertaintyChatMessages.append(userMsg)

        uncertaintyDiscussionTask?.cancel()
        uncertaintyDiscussionTask = Task {
            await runUncertaintyChat(userMessage: text, uncertaintyId: uncertaintyId)
        }
    }

    private func runUncertaintyChat(userMessage: String, uncertaintyId: UUID) async {
        isUncertaintyChatting = true
        uncertaintyStreamOutput = ""
        defer {
            isUncertaintyChatting = false
            uncertaintyStreamOutput = ""
        }

        guard let uncertainty = workflow?.uncertainties.first(where: { $0.id == uncertaintyId }) else { return }
        guard !resolveDesignAgents().isEmpty else {
            errorMessage = lang.common.noAgentConfiguredShort
            return
        }

        let prompt = promptBuilder.buildUncertaintyDiscussPrompt(
            uncertaintyId: uncertaintyId,
            uncertainty: uncertainty,
            chatHistory: uncertaintyChatMessages,
            userMessage: userMessage,
            deliverables: workflow?.deliverables ?? []
        )

        do {
            let (response, _) = try await runWithFallback(prompt: prompt, jsonSchema: DesignJSONSchemas.chat) { [weak self] text in
                guard !Task.isCancelled else { return }
                Task { @MainActor in
                    self?.uncertaintyStreamOutput = text
                }
            }

            guard !Task.isCancelled else { return }

            if let chatResponse = DesignStepResultParser.parseChatResponse(from: response) {
                let designMsg = DesignChatMessage(role: .design, content: chatResponse.message)
                uncertaintyChatMessages.append(designMsg)

                // If actions present, treat as resolution proposal
                if let actionJSONs = chatResponse.actions, let wf = workflow {
                    let actions = actionJSONs.compactMap { DesignAction.from(json: $0, workflow: wf) }
                    let resolution = UncertaintyResolution(
                        selectedOption: matchSuggestionOption(from: chatResponse.message, options: uncertainty.options),
                        responseText: chatResponse.message,
                        summary: chatResponse.message,
                        relatedActions: actions.isEmpty ? nil : actions
                    )
                    pendingUncertaintyResolution = resolution
                }
            } else {
                let message = DesignStepResultParser.extractChatMessage(from: response)
                let designMsg = DesignChatMessage(role: .design, content: message)
                uncertaintyChatMessages.append(designMsg)
            }
        } catch {
            let errorMsg = DesignChatMessage(role: .system, content: error.localizedDescription)
            uncertaintyChatMessages.append(errorMsg)
        }
    }

    /// Match director's recommendation against suggestion options.
    private func matchSuggestionOption(from message: String, options: [String]) -> String? {
        let lowered = message.lowercased()
        for option in options where lowered.contains(option.lowercased()) {
            return option
        }
        return nil
    }

    /// Approve the proposed resolution and resolve the uncertainty.
    func approveUncertaintyResolution(for uncertaintyId: UUID) {
        guard let resolution = pendingUncertaintyResolution else { return }

        if let selectedOption = resolution.selectedOption {
            resolveUncertainty(uncertaintyId, selectedOption: selectedOption)
        } else if let responseText = resolution.responseText {
            resolveUncertaintyWithText(uncertaintyId, response: responseText)
        }

        // Dispatch related actions if any
        if let actions = resolution.relatedActions, !actions.isEmpty {
            Task { await dispatchActions(actions) }
        }

        uncertaintyDiscussionCompleted = true
        pendingUncertaintyResolution = nil
    }

    // MARK: - Auto-fix Consistency Issues

    /// Automatically request fixes from the director and apply them without user intervention.
    /// The design office handles consistency issues internally.
    private func autoFixConsistencyIssues(issues: [ConsistencyIssue]) async {
        guard !resolveDesignAgents().isEmpty, let wf = workflow else { return }

        // Ask the director for fix actions
        let prompt = promptBuilder.buildConsistencyDiscussPrompt(
            issues: issues,
            chatHistory: [],
            userMessage: lang.design.consistencyAutoRequest,
            deliverables: wf.deliverables
        )

        do {
            let (response, _) = try await runWithFallback(
                prompt: prompt,
                jsonSchema: DesignJSONSchemas.chat
            ) { _ in }

            guard !Task.isCancelled else { return }

            if let chatResponse = DesignStepResultParser.parseChatResponse(from: response),
               let actionJSONs = chatResponse.actions {
                let actions = actionJSONs.compactMap { DesignAction.from(json: $0, workflow: wf) }
                if !actions.isEmpty {
                    // Apply fix actions
                    let elaborationItemIds: Set<UUID> = Set(actions.compactMap { action in
                        if case .elaborateItem(_, let id, _) = action { return id }
                        return nil
                    })
                    await dispatchActions(actions)

                    // Re-elaborate updated items that weren't already elaborated by dispatch
                    let itemsToReElaborate: [(UUID, String)] = actions.compactMap { action in
                        if case .updateItem(let sectionType, let itemId, _) = action,
                           !elaborationItemIds.contains(itemId) {
                            return (itemId, sectionType)
                        }
                        return nil
                    }
                    if !itemsToReElaborate.isEmpty {
                        for (itemId, _) in itemsToReElaborate {
                            workflow?.updateItem(itemId) { $0.status = .pending; $0.lastElaborationError = nil }
                        }
                        syncToRequest()
                        await elaborateItems(itemsToReElaborate)
                    }
                }
            }
        } catch {
            logger.warning("Auto-fix consistency issues failed: \(error.localizedDescription, privacy: .public)")
            // Non-fatal — proceed to export even if auto-fix fails
        }
    }

    // MARK: - Consistency Review

    /// Initialize the consistency review overlay with structured issues.
    func beginConsistencyReview(issues: [ConsistencyIssue], summary: String) {
        consistencyIssues = issues
        consistencySummary = summary
        consistencyChatMessages = []
        consistencyStreamOutput = ""
        isConsistencyChatting = false
        pendingConsistencyActions = nil
        isConsistencyApplying = false
        isConsistencyElaborating = false
        consistencyReviewCompleted = false
        consistencyReviewTask?.cancel()
        consistencyReviewTask = nil
        showConsistencyReview = true

        // Auto-send initial request to the director
        let autoMessage = lang.design.consistencyAutoRequest
        let userMsg = DesignChatMessage(role: .user, content: autoMessage)
        consistencyChatMessages.append(userMsg)
        consistencyReviewTask = Task {
            await runConsistencyChat(userMessage: autoMessage)
        }
    }

    /// Send a user message in the consistency review discussion.
    func sendConsistencyMessage(_ text: String) {
        guard !text.isEmpty, !isConsistencyChatting else { return }

        let userMsg = DesignChatMessage(role: .user, content: text)
        consistencyChatMessages.append(userMsg)

        consistencyReviewTask?.cancel()
        consistencyReviewTask = Task {
            await runConsistencyChat(userMessage: text)
        }
    }

    /// Run a consistency discussion LLM call with streaming.
    private func runConsistencyChat(userMessage: String) async {
        isConsistencyChatting = true
        consistencyStreamOutput = ""
        defer {
            isConsistencyChatting = false
            consistencyStreamOutput = ""
        }

        guard !resolveDesignAgents().isEmpty else {
            errorMessage = lang.common.noAgentConfiguredShort
            return
        }

        let prompt = promptBuilder.buildConsistencyDiscussPrompt(
            issues: consistencyIssues,
            chatHistory: consistencyChatMessages,
            userMessage: userMessage,
            deliverables: workflow?.deliverables ?? []
        )

        do {
            let (response, _) = try await runWithFallback(
                prompt: prompt,
                jsonSchema: DesignJSONSchemas.chat
            ) { [weak self] text in
                guard !Task.isCancelled else { return }
                Task { @MainActor in
                    self?.consistencyStreamOutput = text
                }
            }

            guard !Task.isCancelled else { return }

            if let chatResponse = DesignStepResultParser.parseChatResponse(from: response) {
                let designMsg = DesignChatMessage(role: .design, content: chatResponse.message)
                consistencyChatMessages.append(designMsg)

                if let actionJSONs = chatResponse.actions, let wf = workflow {
                    let actions = actionJSONs.compactMap { DesignAction.from(json: $0, workflow: wf) }
                    if !actions.isEmpty {
                        pendingConsistencyActions = actions
                    }
                }
            } else {
                let message = DesignStepResultParser.extractChatMessage(from: response)
                let designMsg = DesignChatMessage(role: .design, content: message)
                consistencyChatMessages.append(designMsg)
            }
        } catch {
            let errorMsg = DesignChatMessage(role: .system, content: error.localizedDescription)
            consistencyChatMessages.append(errorMsg)
        }
    }

    /// Approve and dispatch the proposed consistency fix actions.
    func approveConsistencyFixes() {
        guard let actions = pendingConsistencyActions, !actions.isEmpty else { return }

        let actionsToDispatch = actions
        pendingConsistencyActions = nil
        isConsistencyApplying = true

        // Collect item IDs that need re-elaboration from elaborate_item actions
        let elaborationItemIds: Set<UUID> = Set(actionsToDispatch.compactMap { action in
            if case .elaborateItem(_, let id, _) = action { return id }
            return nil
        })

        consistencyReviewTask?.cancel()
        consistencyReviewTask = Task {
            await dispatchActions(actionsToDispatch)
            isConsistencyApplying = false

            // Re-elaborate items that were updated (but not already elaborated by dispatch)
            let itemsToReElaborate: [(UUID, String)] = actionsToDispatch.compactMap { action in
                switch action {
                case .updateItem(let sectionType, let itemId, _):
                    if !elaborationItemIds.contains(itemId) {
                        return (itemId, sectionType)
                    }
                default: break
                }
                return nil
            }

            if !itemsToReElaborate.isEmpty {
                isConsistencyElaborating = true
                for (itemId, _) in itemsToReElaborate {
                    workflow?.updateItem(itemId) { $0.status = .pending; $0.lastElaborationError = nil }
                }
                syncToRequest()
                await elaborateItems(itemsToReElaborate)
                isConsistencyElaborating = false
            }

            consistencyReviewCompleted = true
        }
    }

    /// Add an edge between two items (user-initiated from graph canvas).
    func addUserEdge(sourceId: UUID, targetId: UUID, relationType: String) {
        let edge = ItemEdge(sourceId: sourceId, targetId: targetId, relationType: relationType)
        if workflow?.addEdgeIfNew(edge) == true {
            logEvent(DesignEventType.edgeAdded, payload: [
                "sourceId": sourceId.uuidString,
                "targetId": targetId.uuidString,
                "relationType": relationType,
            ])
            syncToRequest()
        }
    }

    /// Elaborate all unreviewed items that are still pending or need revision.
    func elaborateRemainingItems() {
        guard let wf = workflow else { return }
        let targets = wf.deliverables.flatMap { section in
            section.items
                .filter { ($0.status == .pending || $0.status == .needsRevision) && $0.designVerdict != .excluded }
                .map { ($0.id, section.type) }
        }
        guard !targets.isEmpty else { return }
        isRetryElaboration = true
        executionTask?.cancel()
        executionTask = Task {
            await elaborateItems(targets)
            isRetryElaboration = false
        }
    }

    /// Elaborate specific items by ID (used by chat-triggered "수정 요청").
    func elaborateItems(_ targets: [(UUID, String)]) async {
        await elaborateItemsInternal(targets)
    }

    private func elaborateItemsInternal(_ targets: [(UUID, String)]) async {
        isPreparingElaboration = true
        let agentAssignments = await assignAgentsToItems(targets: targets.map { ($0.1, $0.0) })
        // Pre-compute shared context once for all items in this batch
        let sharedCtx = workflow.map { SharedElaborationContext(workflow: $0) }
        isPreparingElaboration = false
        await withTaskGroup(of: Void.self) { group in
            var running = 0
            var index = 0
            while index < targets.count {
                guard !Task.isCancelled else { return }
                while running < currentMaxConcurrency && index < targets.count {
                    let t = targets[index]; index += 1; running += 1
                    group.addTask {
                        await self.runSingleItemElaboration(
                            sectionType: t.1,
                            itemId: t.0,
                            preferredAgentId: agentAssignments[t.0],
                            sharedContext: sharedCtx
                        )
                    }
                }
                await group.next()
                running -= 1
            }
            await group.waitForAll()
        }
        syncToRequest()
    }

    /// Update a single spec field for an item (inline editing).
    func updateItemSpec(_ itemId: UUID, key: String, value: AnyCodable) {
        workflow?.updateItem(itemId) { item in
            item.spec[key] = value
            item.updatedAt = Date()
        }
        syncToRequest()
    }

    /// Set planner notes for an item.
    func setPlannerNotes(_ itemId: UUID, notes: String?) {
        workflow?.updateItem(itemId) { item in
            item.plannerNotes = notes
            item.updatedAt = Date()
        }
        syncToRequest()
    }

    /// Set revision note for an item.
    func setRevisionNote(_ itemId: UUID, note: String?) {
        workflow?.updateItem(itemId) { item in
            item.revisionNote = note
            item.updatedAt = Date()
        }
        syncToRequest()
    }

    // MARK: - Spec Readiness

    /// All spec readiness issues for the current workflow.
    var specReadinessIssues: [SpecReadinessIssue] {
        workflow?.specReadinessIssues ?? []
    }

    /// Issues for a specific item.
    func specIssues(for itemId: UUID) -> [SpecReadinessIssue] {
        specReadinessIssues.filter { $0.itemId == itemId }
    }

    /// Whether a specific item has blocking (error-level) spec issues.
    func hasBlockingIssues(for itemId: UUID) -> Bool {
        specReadinessIssues.contains { $0.itemId == itemId && $0.severity == .error }
    }

    /// Elaborate all pending / needsRevision items with parallel execution within dependency groups.
    func elaborateAllPending() async {
        guard let wf = workflow, wf.isStructureApproved else { return }
        // Prevent a concurrent second TaskGroup from spinning up if the caller
        // re-triggers (e.g. header "Start Design" pressed while a prior run is
        // still live because the Back path didn't cancel it in time).
        guard !isElaborating, !isPreparingElaboration else {
            logger.notice("elaborateAllPending blocked — already running (isElaborating=\(self.isElaborating), isPreparing=\(self.isPreparingElaboration))")
            return
        }

        // Compute parallel groups from edge graph (falls back to stored parallelGroup)
        let computedGroups = wf.computeParallelGroups()

        var targets: [(sectionType: String, itemId: UUID, group: Int)] = []
        for section in wf.deliverables {
            for item in section.items where (item.status == .pending || item.status == .needsRevision)
                && item.designVerdict != .excluded {
                let group = computedGroups[item.id] ?? (item.parallelGroup ?? 0)
                targets.append((section.type, item.id, group))
            }
        }
        guard !targets.isEmpty else { return }

        // Preparation phase: assign agents + build shared context
        isPreparingElaboration = true

        // Ask Design to assign best step agent per item
        let agentAssignments = await assignAgentsToItems(
            targets: targets.map { ($0.sectionType, $0.itemId) }
        )

        // Pre-compute shared context once for all items in this batch
        let sharedCtx = SharedElaborationContext(workflow: wf)

        isPreparingElaboration = false

        let grouped = Dictionary(grouping: targets, by: \.group).sorted { $0.key < $1.key }

        for (_, groupTargets) in grouped {
            guard !Task.isCancelled else { return }

            await withTaskGroup(of: Void.self) { group in
                var running = 0
                var index = 0

                while index < groupTargets.count {
                    guard !Task.isCancelled else { return }

                    while running < currentMaxConcurrency && index < groupTargets.count {
                        let t = groupTargets[index]; index += 1; running += 1
                        group.addTask {
                            await self.runSingleItemElaboration(
                                sectionType: t.sectionType,
                                itemId: t.itemId,
                                preferredAgentId: agentAssignments[t.itemId],
                                sharedContext: sharedCtx
                            )
                        }
                    }

                    await group.next()
                    running -= 1
                }

                await group.waitForAll()
            }

            syncToRequest()
        }

        syncToRequest()
    }

    // MARK: - Selective Item Elaboration (removed — now uses elaborateRemainingItems)

    // MARK: - Workflow Completion

    /// Schedule finishWorkflow to run after a brief delay, owned by the ViewModel
    /// rather than a view, so the chain survives view re-creation and overlay
    /// re-renders. Replaces the previous view-owned Task pattern in
    /// `ElaborationProgressOverlay`.
    func scheduleAutoFinish(delay: Duration = .seconds(0.8)) {
        // Cancel any prior pending auto-finish to avoid double-fire
        autoFinishTask?.cancel()
        logger.info("scheduleAutoFinish: queued")
        autoFinishTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            // Re-verify after sleep: between parallel groups, isElaborating can briefly
            // flip to false while items in the next group are still .pending. The earlier
            // !isElaborating check at queue time is not enough on its own.
            guard self.isElaborationFullyDone else {
                logger.notice("scheduleAutoFinish: aborted — elaboration not fully done after wakeup")
                return
            }
            await self.finishWorkflow()
        }
    }

    /// Finish the workflow: run consistency check, then either pause for user review or proceed to export.
    func finishWorkflow() async {
        logger.info("finishWorkflow: enter")
        guard isElaborationFullyDone else {
            logger.notice("finishWorkflow blocked — elaboration not fully done")
            return
        }
        guard let wf = workflow, wf.allItemsConfirmed else {
            logger.notice("finishWorkflow blocked — not all items confirmed")
            return
        }

        guard wf.phase != .completed else {
            logger.notice("finishWorkflow blocked — already completed")
            return
        }

        guard wf.isStructureApproved else {
            logger.notice("finishWorkflow blocked — structure not approved")
            return
        }

        // Defense-in-depth: verify exportable items exist (elaborated + confirmed)
        let exportable = wf.deliverables.flatMap(\.exportableItems)
        guard !exportable.isEmpty else {
            errorMessage = lang.design.noExportableItems
            logger.notice("finishWorkflow blocked — no exportable items")
            return
        }

        guard !isFinishing else {
            logger.notice("finishWorkflow blocked — already finishing (step=\(self.finishingStep?.rawValue ?? "nil", privacy: .public))")
            return
        }

        // Run consistency check (trackUsage is called inside runWithFallback)
        finishingStep = .consistencyCheck
        logger.info("finishWorkflow: consistency check started")
        var parsedResponse: ConsistencyCheckResponse?
        if !wf.deliverables.isEmpty {
            let consistencyPrompt = promptBuilder.buildConsistencyCheckPrompt(deliverables: wf.deliverables)

            do {
                let (response, _) = try await runWithFallback(
                    prompt: consistencyPrompt,
                    jsonSchema: DesignJSONSchemas.consistencyCheck
                ) { _ in }
                guard !Task.isCancelled else {
                    logger.warning("finishWorkflow: cancelled after consistency check — aborting auto-chain (recoverable via P5 banner)")
                    finishingStep = nil
                    return
                }

                let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
                let consistencyMsg = DesignChatMessage(role: .design, content: trimmed)
                workflow?.appendChatMessage(consistencyMsg)

                parsedResponse = DesignStepResultParser.parseConsistencyCheckResponse(from: trimmed)
            } catch {
                logger.warning("Consistency check failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // If consistency check found issues, present for user review instead of auto-fixing
        if let result = parsedResponse, !result.issues.isEmpty {
            logger.info("Consistency check found \(result.issues.count) issues — presenting for review")
            finishingStep = nil
            beginConsistencyReview(issues: result.issues, summary: result.summary)
            return // User reviews and approves fixes via ConsistencyReviewOverlay → onExport
        }

        // No issues — proceed to export
        logger.info("finishWorkflow: proceeding to export")
        finishingStep = .exporting
        await proceedWithExport()
    }

    /// Complete the export after consistency check review. Called by the user from the consistency result overlay.
    func proceedWithExport() async {
        finishingStep = .exporting
        defer { finishingStep = nil }

        // Refresh BRD/Brief cache from DB (may have been generated asynchronously after session creation)
        if let reqId = requestId,
           let freshSession = try? await container.designSessionService.getRequest(id: reqId) {
            cachedBrdJSON = freshSession.brdJSON
            cachedDesignBriefJSON = freshSession.designBriefJSON
        }

        // Export deliverables to disk
        exportDeliverables()

        // Mark workflow as completed (transitionTo increments mutationCounter for DB sync)
        workflow?.transitionTo(.completed)

        syncToRequestImmediate()
        notifyBlockingState(message: "Workflow completed")
        logger.info("Workflow completed")
        logEvent(DesignEventType.workflowCompleted)
    }

    // MARK: - Export

    /// Export deliverables to disk as two-tier documents:
    /// 1. `spec.json` + `spec.md` — approved items only, structured for AI dev tools
    /// 2. `context.md` — planner judgment context (why approved, what rejected)
    func exportDeliverables() {
        guard let wf = workflow, let reqId = requestId else { return }
        guard let iId = ideaId else {
            logger.warning("Cannot export: ideaId not set")
            return
        }

        let rootPath = project.rootPath
        let ideaBase = (rootPath as NSString).appendingPathComponent(".lao/\(iId.uuidString)")
        let finalDir = (ideaBase as NSString).appendingPathComponent(reqId.uuidString)
        let tmpDir = (ideaBase as NSString).appendingPathComponent(".tmp-\(UUID().uuidString)")
        let fm = FileManager.default

        // Ensure access
        SecurityScopedBookmarkStore.shared.startAccessing(path: rootPath)

        do {
            // Write all files to a temporary directory first (atomic export)
            try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

            // 1. spec.json — approved items only (canonical filter)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .secondsSince1970
            let approvedSections = wf.deliverables.compactMap { section -> DeliverableSection? in
                let exportable = section.exportableItems
                guard !exportable.isEmpty else { return nil }
                var filtered = section
                filtered.items = exportable
                return filtered
            }
            let jsonData = try encoder.encode(approvedSections)
            try jsonData.write(to: URL(fileURLWithPath: (tmpDir as NSString).appendingPathComponent("spec.json")))

            // 2. spec.md — AI dev tool document (structured per section type)
            let specMd = renderApprovedSpec(wf)
            try specMd.write(toFile: (tmpDir as NSString).appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)

            // 3. context.md — planner judgment context
            let contextMd = renderPlannerContext(wf)
            try contextMd.write(toFile: (tmpDir as NSString).appendingPathComponent("context.md"), atomically: true, encoding: .utf8)

            // 4. design.json — structured DesignDocument for AI dev tools
            let designDoc = DesignDocumentConverter.convert(wf, requestId: reqId)
            let validationIssues = DesignDocumentValidator.validate(designDoc)
            exportValidationIssues = validationIssues
            let validationErrors = validationIssues.filter { $0.severity == .error }
            if !validationErrors.isEmpty {
                logger.warning("Design document validation: \(validationErrors.count) error(s)")
                for issue in validationErrors {
                    logger.warning("  \(issue.description, privacy: .public)")
                }
            }
            let designEncoder = JSONEncoder()
            designEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            designEncoder.dateEncodingStrategy = .iso8601
            let designData = try designEncoder.encode(designDoc)
            try designData.write(to: URL(fileURLWithPath: (tmpDir as NSString).appendingPathComponent("design.json")))

            // 5. DESIGN_SPEC.md — unified design spec optimized for AI consumption
            let designMd = DesignDocumentConverter.renderMarkdown(designDoc)
            try designMd.write(toFile: (tmpDir as NSString).appendingPathComponent("DESIGN_SPEC.md"), atomically: true, encoding: .utf8)

            // 6-7. BRD/CPS — business requirements & context-problem-solution
            // Uses cached JSON from loadState(). Falls back to extracting BRD from Brief.

            // Resolve BRD source: direct BRD JSON → extract from Brief JSON
            let resolvedBrdJSON: String = {
                if !cachedBrdJSON.isEmpty { return cachedBrdJSON }
                guard !cachedDesignBriefJSON.isEmpty,
                      let data = cachedDesignBriefJSON.data(using: .utf8),
                      let envelope = try? JSONDecoder().decode(BriefBrdEnvelope.self, from: data),
                      let brdData = try? JSONEncoder().encode(envelope.brief.brd) else { return "" }
                return String(data: brdData, encoding: .utf8) ?? ""
            }()

            // 6. brd.json + BRD.md
            if !resolvedBrdJSON.isEmpty,
               let rawBrd = resolvedBrdJSON.data(using: .utf8),
               let brdFields = try? JSONDecoder().decode(BRDFields.self, from: rawBrd) {
                let brdMeta = DocumentMeta(
                    documentType: "brd",
                    projectName: designDoc.meta.projectName,
                    sourceRequestId: reqId.uuidString
                )
                let brd = BusinessRequirementsDocument(
                    meta: brdMeta,
                    problemStatement: brdFields.problemStatement,
                    targetUsers: brdFields.targetUsers ?? [],
                    businessObjectives: brdFields.businessObjectives ?? [],
                    successMetrics: brdFields.successMetrics ?? [],
                    scope: brdFields.scope ?? ProjectScope(),
                    constraints: brdFields.constraints ?? [],
                    assumptions: brdFields.assumptions ?? [],
                    nonFunctionalRequirements: brdFields.nonFunctionalRequirements ?? NonFunctionalRequirements()
                )
                let brdData = try designEncoder.encode(brd)
                try brdData.write(to: URL(fileURLWithPath: (tmpDir as NSString).appendingPathComponent("brd.json")))
                let brdMd = renderBRDMarkdown(brd)
                try brdMd.write(toFile: (tmpDir as NSString).appendingPathComponent("BRD.md"), atomically: true, encoding: .utf8)
            }

            // 7. plan.json + PLAN.md — implementation plan (derived from DesignDocument)
            let planDoc = PlanDocumentConverter.convert(designDoc)
            let planData = try designEncoder.encode(planDoc)
            try planData.write(to: URL(fileURLWithPath: (tmpDir as NSString).appendingPathComponent("plan.json")))
            let planMd = PlanDocumentConverter.renderMarkdown(planDoc)
            try planMd.write(toFile: (tmpDir as NSString).appendingPathComponent("PLAN.md"), atomically: true, encoding: .utf8)

            // 9. test.json + TEST.md — test scenarios (derived from DesignDocument)
            let testDoc = TestDocumentConverter.convert(designDoc)
            let testData = try designEncoder.encode(testDoc)
            try testData.write(to: URL(fileURLWithPath: (tmpDir as NSString).appendingPathComponent("test.json")))
            let testMd = TestDocumentConverter.renderMarkdown(testDoc)
            try testMd.write(toFile: (tmpDir as NSString).appendingPathComponent("TEST.md"), atomically: true, encoding: .utf8)

            // All files written successfully — atomic move to final path
            if fm.fileExists(atPath: finalDir) {
                try fm.removeItem(atPath: finalDir)
            }
            try fm.moveItem(atPath: tmpDir, toPath: finalDir)

            // 6. .mcp.json — only after design.json is confirmed on disk
            writeMCPConfig()

            logger.info("Deliverables exported to \(finalDir, privacy: .public)")
            logEvent(DesignEventType.deliverablesExported, payload: ["path": finalDir])
        } catch {
            logger.error("Failed to export deliverables: \(error.localizedDescription, privacy: .public)")
            // Clean up incomplete temp directory
            do { try fm.removeItem(atPath: tmpDir) }
            catch { logger.warning("[Export] Failed to clean up temp dir: \(error.localizedDescription, privacy: .public)") }
        }

        refreshDiskDocumentFiles()
    }

    // MARK: - BRD/CPS Intermediate Types (synthesis JSON lacks meta)

    /// Fields produced by synthesis prompt — no DocumentMeta, all optional for resilience.
    /// Decode shape for extracting BRD from Design Brief JSON ({"brief": {"brd": {...}}}).
    private struct BriefBrdEnvelope: Codable {
        struct Brief: Codable { let brd: BRDFields }
        let brief: Brief
    }

    private struct BRDFields: Codable {
        let problemStatement: String
        let targetUsers: [TargetUser]?
        let businessObjectives: [String]?
        let successMetrics: [SuccessMetric]?
        let scope: ProjectScope?
        let constraints: [String]?
        let assumptions: [String]?
        let nonFunctionalRequirements: NonFunctionalRequirements?
    }

    // MARK: - BRD Markdown Rendering

    private func renderBRDMarkdown(_ brd: BusinessRequirementsDocument) -> String {
        var md = "# \(brd.meta.projectName) — Business Requirements Document\n\n"
        md += "**Generated**: \(ISO8601DateFormatter().string(from: brd.meta.generatedAt))\n\n"
        md += "## Problem Statement\n\n\(brd.problemStatement)\n\n"
        if !brd.targetUsers.isEmpty {
            md += "## Target Users\n\n"
            for user in brd.targetUsers {
                md += "### \(user.name)\n\n\(user.description)\n\n"
                if !user.needs.isEmpty { md += "**Needs**: \(user.needs.joined(separator: ", "))\n\n" }
            }
        }
        if !brd.businessObjectives.isEmpty {
            md += "## Business Objectives\n\n" + brd.businessObjectives.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if !brd.successMetrics.isEmpty {
            md += "## Success Metrics\n\n"
            md += "| Metric | Target | Measurement |\n|--------|--------|-------------|\n"
            for m in brd.successMetrics { md += "| \(m.metric) | \(m.target) | \(m.measurement) |\n" }
            md += "\n"
        }
        md += "## Scope\n\n"
        if !brd.scope.inScope.isEmpty { md += "**In Scope**: \(brd.scope.inScope.joined(separator: ", "))\n\n" }
        if !brd.scope.outOfScope.isEmpty { md += "**Out of Scope**: \(brd.scope.outOfScope.joined(separator: ", "))\n\n" }
        if !brd.scope.mvpBoundary.isEmpty { md += "**MVP Boundary**: \(brd.scope.mvpBoundary)\n\n" }
        if !brd.constraints.isEmpty { md += "## Constraints\n\n" + brd.constraints.map { "- \($0)" }.joined(separator: "\n") + "\n\n" }
        if !brd.assumptions.isEmpty { md += "## Assumptions\n\n" + brd.assumptions.map { "- \($0)" }.joined(separator: "\n") + "\n\n" }
        let nfr = brd.nonFunctionalRequirements
        if !nfr.performance.isEmpty || !nfr.security.isEmpty || !nfr.accessibility.isEmpty || !nfr.scalability.isEmpty {
            md += "## Non-Functional Requirements\n\n"
            if !nfr.performance.isEmpty { md += "**Performance**: \(nfr.performance.joined(separator: "; "))\n\n" }
            if !nfr.security.isEmpty { md += "**Security**: \(nfr.security.joined(separator: "; "))\n\n" }
            if !nfr.accessibility.isEmpty { md += "**Accessibility**: \(nfr.accessibility.joined(separator: "; "))\n\n" }
            if !nfr.scalability.isEmpty { md += "**Scalability**: \(nfr.scalability.joined(separator: "; "))\n\n" }
        }
        return md
    }

    // MARK: - Tier 1: AI Dev Tool Document (approved items, structured spec)

    /// Render approved deliverables as a structured Markdown spec consumable by AI coding tools.
    private func renderApprovedSpec(_ wf: DesignWorkflow) -> String {
        var md = "# \(wf.projectSpec?.name ?? "Project") — Implementation Spec\n\n"

        if let spec = wf.projectSpec {
            md += "**Type**: \(spec.type)\n\n"
        }

        if !wf.designSummary.isEmpty {
            md += "## Overview\n\n\(wf.designSummary)\n\n"
        }

        for section in wf.deliverables {
            let approved = section.exportableItems
            guard !approved.isEmpty else { continue }

            md += "## \(section.label)\n\n"

            for item in approved {
                md += "### \(item.name)\n\n"

                if let desc = item.briefDescription {
                    md += "> \(desc)\n\n"
                }

                if let notes = item.plannerNotes, !notes.isEmpty {
                    md += "**Planner note**: \(notes)\n\n"
                }

                if !item.spec.isEmpty {
                    md += renderStructuredSpec(item.spec, sectionType: section.type)
                }
            }
        }

        // Append edges between approved items
        let approvedIds = Set(wf.deliverables.flatMap(\.exportableItems).map(\.id))
        let activeEdges = wf.edges.filter { approvedIds.contains($0.sourceId) && approvedIds.contains($0.targetId) }
        if !activeEdges.isEmpty {
            let itemName: (UUID) -> String = { id in
                for s in wf.deliverables { if let i = s.items.first(where: { $0.id == id }) { return i.name } }
                return id.uuidString.prefix(8).description
            }
            md += "## Relationships\n\n"
            for edge in activeEdges {
                let rel = edge.relationType.replacingOccurrences(of: "_", with: " ")
                md += "- **\(itemName(edge.sourceId))** → *\(rel)* → **\(itemName(edge.targetId))**\n"
            }
            md += "\n"
        }

        return md
    }

    /// Render a spec dictionary with structure appropriate to the section type.
    private func renderStructuredSpec(_ spec: [String: AnyCodable], sectionType: String) -> String {
        var md = ""

        switch sectionType {
        case "screen-spec":
            if let purpose = spec["purpose"]?.stringValue { md += "**Purpose**: \(purpose)\n\n" }
            if let entry = spec["entry_condition"]?.stringValue { md += "**Entry**: \(entry)\n\n" }
            if let exits = spec["exit_to"]?.arrayValue {
                let targets = exits.compactMap { readableExitTarget($0) }
                if !targets.isEmpty {
                    md += "**Navigates to**: \(targets.joined(separator: ", "))\n\n"
                }
            }
            if let components = spec["components"]?.arrayValue, !components.isEmpty {
                md += "**Components**:\n\n"
                md += renderComponentTree(components, indent: 0)
            }
            if let interactions = spec["interactions"]?.arrayValue, !interactions.isEmpty {
                md += "**Interactions**:\n\n"
                for interaction in interactions {
                    if let dict = (interaction as? AnyCodable)?.dictValue ?? (interaction as? [String: Any]) {
                        let trigger = (dict["trigger"] as? String) ?? ""
                        let action = (dict["action"] as? String) ?? ""
                        if !trigger.isEmpty { md += "- \(trigger) → \(action)\n" }
                    }
                }
                md += "\n"
            }
            if let states = spec["states"]?.dictValue {
                md += "**States**:\n\n"
                for (state, desc) in states.sorted(by: { $0.key < $1.key }) {
                    md += "- **\(state)**: \(desc)\n"
                }
                md += "\n"
            }
            renderSpecAnnotation(spec, key: "edge_cases", heading: "Edge cases", emoji: "⚠️",
                primaryKeys: ["case", "scenario"], secondaryKeys: ["handling", "response"], to: &md)
            renderSpecAnnotation(spec, key: "suggested_refinements", heading: "Suggested refinements", emoji: "💡",
                primaryKeys: ["area", "field"], secondaryKeys: ["suggestion", "description"], to: &md)
            appendRawSpecFallback(spec: spec, excluding: ["purpose", "entry_condition", "exit_to", "components", "interactions", "states", "edge_cases", "suggested_refinements", "summary"], to: &md)

        case "data-model":
            if let desc = spec["description"]?.stringValue { md += "**Description**: \(desc)\n\n" }
            if let fields = spec["fields"]?.arrayValue, !fields.isEmpty {
                md += "**Fields**:\n\n"
                md += "| Name | Type | Required | Description |\n|------|------|----------|-------------|\n"
                for field in fields {
                    if let dict = (field as? AnyCodable)?.dictValue ?? (field as? [String: Any]) {
                        let name = (dict["name"] as? String) ?? ""
                        let type = (dict["type"] as? String) ?? ""
                        let req = (dict["required"] as? Bool) == true ? "Yes" : "No"
                        let fdesc = (dict["description"] as? String) ?? ""
                        md += "| \(name) | \(type) | \(req) | \(fdesc) |\n"
                    }
                }
                md += "\n"
            }
            if let rels = spec["relationships"]?.arrayValue, !rels.isEmpty {
                md += "**Relationships**:\n\n"
                for rel in rels {
                    if let dict = (rel as? AnyCodable)?.dictValue ?? (rel as? [String: Any]) {
                        let entity = (dict["entity"] as? String) ?? ""
                        let type = (dict["type"] as? String) ?? ""
                        let rdesc = (dict["description"] as? String) ?? ""
                        md += "- \(entity) (\(type)): \(rdesc)\n"
                    }
                }
                md += "\n"
            }
            if let rules = spec["business_rules"]?.arrayValue, !rules.isEmpty {
                md += "**Business rules**:\n\n"
                for rule in rules {
                    let text = (rule as? AnyCodable)?.stringValue ?? (rule as? String) ?? "\(rule)"
                    md += "- \(text)\n"
                }
                md += "\n"
            }
            renderSpecAnnotation(spec, key: "edge_cases", heading: "Edge cases", emoji: "⚠️",
                primaryKeys: ["case", "scenario"], secondaryKeys: ["handling", "response"], to: &md)
            renderSpecAnnotation(spec, key: "suggested_refinements", heading: "Suggested refinements", emoji: "💡",
                primaryKeys: ["area", "field"], secondaryKeys: ["suggestion", "description"], to: &md)
            appendRawSpecFallback(spec: spec, excluding: ["description", "fields", "relationships", "indexes", "business_rules", "edge_cases", "suggested_refinements", "summary"], to: &md)

        case "api-spec":
            if let method = spec["method"]?.stringValue, let path = spec["path"]?.stringValue {
                md += "**Endpoint**: `\(method) \(path)`\n\n"
            }
            if let desc = spec["description"]?.stringValue { md += "\(desc)\n\n" }
            if let params = spec["parameters"]?.arrayValue, !params.isEmpty {
                md += "**Parameters**:\n\n"
                md += "| Name | In | Type | Required | Description |\n|------|-----|------|----------|-------------|\n"
                for param in params {
                    if let dict = (param as? AnyCodable)?.dictValue ?? (param as? [String: Any]) {
                        let name = (dict["name"] as? String) ?? ""
                        let loc = (dict["in"] as? String) ?? ""
                        let type = (dict["type"] as? String) ?? ""
                        let req = (dict["required"] as? Bool) == true ? "Yes" : "No"
                        let pdesc = (dict["description"] as? String) ?? ""
                        md += "| \(name) | \(loc) | \(type) | \(req) | \(pdesc) |\n"
                    }
                }
                md += "\n"
            }
            if let body = spec["request_body"]?.dictValue {
                md += "**Request body**:\n\n```json\n\(prettyJSON(body))\n```\n\n"
            }
            if let resp = spec["response"]?.dictValue {
                md += "**Response**:\n\n```json\n\(prettyJSON(resp))\n```\n\n"
            }
            if let errs = spec["error_responses"]?.arrayValue, !errs.isEmpty {
                md += "**Error responses**:\n\n"
                for err in errs {
                    if let dict = (err as? AnyCodable)?.dictValue ?? (err as? [String: Any]) {
                        let code = dict["code"] ?? ""
                        let msg = (dict["message"] as? String) ?? ""
                        md += "- `\(code)`: \(msg)\n"
                    }
                }
                md += "\n"
            }
            if let auth = spec["auth"]?.stringValue { md += "**Auth**: \(auth)\n\n" }
            renderSpecAnnotation(spec, key: "edge_cases", heading: "Edge cases", emoji: "⚠️",
                primaryKeys: ["case", "scenario"], secondaryKeys: ["handling", "response"], to: &md)
            renderSpecAnnotation(spec, key: "suggested_refinements", heading: "Suggested refinements", emoji: "💡",
                primaryKeys: ["area", "field"], secondaryKeys: ["suggestion", "description"], to: &md)
            appendRawSpecFallback(spec: spec, excluding: ["method", "path", "description", "parameters", "request_body", "response", "error_responses", "auth", "edge_cases", "suggested_refinements", "summary"], to: &md)

        case "user-flow":
            if let trigger = spec["trigger"]?.stringValue { md += "**Trigger**: \(trigger)\n\n" }
            if let steps = spec["steps"]?.arrayValue, !steps.isEmpty {
                md += "**Steps**:\n\n"
                for step in steps {
                    if let dict = (step as? AnyCodable)?.dictValue ?? (step as? [String: Any]) {
                        let order = dict["order"] ?? ""
                        let actor = (dict["actor"] as? String) ?? ""
                        let action = (dict["action"] as? String) ?? ""
                        md += "\(order). [\(actor)] \(action)\n"
                    }
                }
                md += "\n"
            }
            if let decisions = spec["decision_points"]?.arrayValue, !decisions.isEmpty {
                md += "**Decision points**:\n\n"
                for dp in decisions {
                    if let dict = (dp as? AnyCodable)?.dictValue ?? (dp as? [String: Any]) {
                        let cond = (dict["condition"] as? String) ?? ""
                        let yes = (dict["yes"] as? String) ?? ""
                        let no = (dict["no"] as? String) ?? ""
                        md += "- If \(cond): Yes → \(yes) / No → \(no)\n"
                    }
                }
                md += "\n"
            }
            if let outcome = spec["success_outcome"]?.stringValue { md += "**Success**: \(outcome)\n\n" }
            if let screens = spec["related_screens"]?.arrayValue, !screens.isEmpty {
                let names = screens.compactMap { readableExitTarget($0) }
                if !names.isEmpty {
                    md += "**Related screens**: \(names.joined(separator: ", "))\n\n"
                }
            }
            renderSpecAnnotation(spec, key: "error_paths", heading: "Error paths", emoji: "⚠️",
                separator: " → ", primaryKeys: ["condition", "error"], secondaryKeys: ["handling", "action"], to: &md)
            renderSpecAnnotation(spec, key: "edge_cases", heading: "Edge cases", emoji: "⚠️",
                primaryKeys: ["case", "scenario"], secondaryKeys: ["handling", "response"], to: &md)
            renderSpecAnnotation(spec, key: "suggested_refinements", heading: "Suggested refinements", emoji: "💡",
                primaryKeys: ["area", "field"], secondaryKeys: ["suggestion", "description"], to: &md)
            appendRawSpecFallback(spec: spec, excluding: ["trigger", "steps", "decision_points", "success_outcome", "error_paths", "related_screens", "edge_cases", "suggested_refinements", "summary"], to: &md)

        default:
            // Fallback: pretty-print entire spec as JSON
            if let data = try? JSONEncoder().encode(spec),
               let jsonObj = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObj, options: .prettyPrinted),
               let prettyStr = String(data: prettyData, encoding: .utf8) {
                md += "```json\n\(prettyStr)\n```\n\n"
            }
        }

        return md
    }

    /// Render a component tree as indented markdown.
    private func renderComponentTree(_ components: [Any], indent: Int) -> String {
        var md = ""
        let prefix = String(repeating: "  ", count: indent)
        for comp in components {
            guard let dict = (comp as? AnyCodable)?.dictValue ?? (comp as? [String: Any]) else { continue }
            let name = (dict["name"] as? String) ?? "?"
            let type = (dict["type"] as? String) ?? ""
            let role = (dict["role"] as? String) ?? ""
            md += "\(prefix)- **\(name)** (`\(type)`)"
            if !role.isEmpty { md += " — \(role)" }
            md += "\n"
            if let children = (dict["children"] as? [Any]) ?? ((dict["children"] as? AnyCodable)?.arrayValue) {
                md += renderComponentTree(children, indent: indent + 1)
            }
        }
        return md
    }

    /// Generic renderer for spec annotation arrays (edge_cases, suggested_refinements, error_paths).
    /// Extracts primary/secondary text from each item using the provided key lists.
    private func renderSpecAnnotation(
        _ spec: [String: AnyCodable],
        key: String,
        heading: String,
        emoji: String,
        separator: String = ": ",
        primaryKeys: [String],
        secondaryKeys: [String],
        to md: inout String
    ) {
        guard let items = spec[key]?.arrayValue, !items.isEmpty else { return }
        md += "**\(heading)**:\n\n"
        for item in items {
            if let dict = (item as? AnyCodable)?.dictValue ?? (item as? [String: Any]) {
                let primary = primaryKeys.lazy.compactMap { dict[$0] as? String }.first ?? ""
                let secondary = secondaryKeys.lazy.compactMap { dict[$0] as? String }.first ?? ""
                if !primary.isEmpty {
                    md += "- \(emoji) **\(primary)**"
                    if !secondary.isEmpty { md += "\(separator)\(secondary)" }
                    md += "\n"
                }
            } else if let text = (item as? AnyCodable)?.stringValue ?? (item as? String) {
                md += "- \(emoji) \(text)\n"
            }
        }
        md += "\n"
    }

    /// Extract readable text from a spec value (may be String, AnyCodable, or Dict with name/description).
    private func readableExitTarget(_ value: Any) -> String? {
        if let s = value as? String { return s }
        if let ac = value as? AnyCodable, let s = ac.stringValue { return s }
        if let dict = (value as? [String: Any]) ?? (value as? AnyCodable)?.dictValue {
            if let name = dict["name"] as? String {
                if let desc = dict["description"] as? String { return "\(name) — \(desc)" }
                return name
            }
        }
        return nil
    }

    /// Append remaining spec keys not already rendered, as JSON fallback.
    private func appendRawSpecFallback(spec: [String: AnyCodable], excluding keys: [String], to md: inout String) {
        let remaining = spec.filter { !keys.contains($0.key) }
        guard !remaining.isEmpty else { return }
        if let data = try? JSONEncoder().encode(remaining),
           let jsonObj = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObj, options: .prettyPrinted),
           let prettyStr = String(data: prettyData, encoding: .utf8) {
            md += "<details><summary>Additional spec details</summary>\n\n```json\n\(prettyStr)\n```\n\n</details>\n\n"
        }
    }

    /// Pretty-print a dictionary as JSON string.
    private func prettyJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    // MARK: - Tier 2: Planner Context Document

    /// Render the planner's judgment context — original request, approval rationale, rejections.
    private func renderPlannerContext(_ wf: DesignWorkflow) -> String {
        var md = "# \(wf.projectSpec?.name ?? "Project") — Planner Context\n\n"
        md += "> This document records the planner's judgment decisions. "
        md += "AI dev tools should read `spec.md` for implementation specs and reference this file for intent context.\n\n"

        // Original request
        if !wf.taskDescription.isEmpty {
            md += "## Original Request\n\n\(wf.taskDescription)\n\n"
        }

        if !wf.designSummary.isEmpty {
            md += "## Design Summary\n\n\(wf.designSummary)\n\n"
        }

        // Approved items with rationale (uses canonical export filter)
        let approvedItems = wf.deliverables.flatMap { section in
            section.exportableItems.map { (section.type, section.label, $0) }
        }
        if !approvedItems.isEmpty {
            md += "## Approved Items (\(approvedItems.count))\n\n"
            var currentSection = ""
            for (_, label, item) in approvedItems {
                if label != currentSection {
                    currentSection = label
                    md += "### \(label)\n\n"
                }
                md += "- **\(item.name)**"
                if let notes = item.plannerNotes, !notes.isEmpty {
                    md += " — \(notes)"
                }
                md += "\n"
            }
            md += "\n"
        }

        // Rejected items with reasons
        let rejectedItems = wf.deliverables.flatMap { section in
            section.items.filter { $0.plannerVerdict == .rejected }.map { (section.type, section.label, $0) }
        }
        if !rejectedItems.isEmpty {
            md += "## Rejected Items (\(rejectedItems.count))\n\n"
            var currentSection = ""
            for (_, label, item) in rejectedItems {
                if label != currentSection {
                    currentSection = label
                    md += "### \(label)\n\n"
                }
                md += "- ~~\(item.name)~~"
                if let notes = item.plannerNotes, !notes.isEmpty {
                    md += " — \(notes)"
                }
                md += "\n"
            }
            md += "\n"
        }

        // Pending review items (still awaiting decision-maker review)
        let pendingItems = wf.deliverables.flatMap { section in
            section.items.filter { $0.designVerdict == .pending && $0.plannerVerdict != .rejected }.map { (section.label, $0) }
        }
        if !pendingItems.isEmpty {
            md += "## Pending Review (\(pendingItems.count))\n\n"
            for (label, item) in pendingItems {
                md += "- \(item.name) (\(label))\n"
            }
            md += "\n"
        }

        return md
    }

    // MARK: - Document Management

    /// Gather all available document items (disk files from export).
    func gatherDocumentItems() async -> [DesignDocumentItem] {
        refreshDiskDocumentFiles()
        let files = diskDocumentFiles
        let items = await Task.detached(priority: .userInitiated) {
            var result: [DesignDocumentItem] = []
            for file in files {
                let title = file.name.replacingOccurrences(of: ".md", with: "")
                    .replacingOccurrences(of: ".json", with: "")
                guard let content = try? String(contentsOfFile: file.path, encoding: .utf8),
                      !content.isEmpty else { continue }
                // Skip semantically empty files (e.g. "[]", "{}", or headers-only markdown)
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != "[]", trimmed != "{}" else { continue }
                result.append(DesignDocumentItem(
                    id: UUID(),
                    title: title,
                    icon: file.name.hasSuffix(".json") ? "doc.text.magnifyingglass" : "doc.text",
                    summary: "",
                    content: content,
                    completedAt: nil
                ))
            }
            return result
        }.value
        return items
    }

    func refreshDiskDocumentFiles() {
        guard let reqId = requestId, let iId = ideaId else { diskDocumentFiles = []; return }
        let docsDir = (project.rootPath as NSString).appendingPathComponent(".lao/\(iId.uuidString)/\(reqId.uuidString)")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: docsDir) else { diskDocumentFiles = []; return }
        diskDocumentFiles = files
            .filter { $0.hasSuffix(".md") || $0.hasSuffix(".json") }
            .sorted()
            .map { (name: $0, path: (docsDir as NSString).appendingPathComponent($0)) }
    }

    // MARK: - AI Tool Handoff

    enum AITool: String, CaseIterable {
        case claudeCode = "Claude Code"
        case codex = "Codex"

        var icon: String {
            switch self {
            case .claudeCode: return "terminal"
            case .codex: return "terminal.fill"
            }
        }
    }

    /// Open the project in an AI coding tool. Assumes .mcp.json is already written by export.
    func openInAITool(_ tool: AITool) {
        let path = project.rootPath

        // Claude Code / Codex — create a .command file that macOS opens in Terminal.app
        let command = tool == .claudeCode ? "claude" : "codex"
        let specPath: String
        if let iId = ideaId, let reqId = requestId {
            specPath = ".lao/\(iId.uuidString)/\(reqId.uuidString)/DESIGN_SPEC.md"
        } else {
            specPath = ""
        }
        let initialPrompt = specPath.isEmpty ? "" : " \(shellEscaped("Read \(specPath) and implement the project according to the design specification."))"
        let script = "#!/bin/zsh\ncd \(shellEscaped(path))\n\(command)\(initialPrompt)\n"
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lao-handoff-\(command).command")
        do {
            try script.write(to: tmpURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: tmpURL.path)
            NSWorkspace.shared.open(tmpURL)
        } catch {
            logger.error("[Handoff] Failed to launch \(command, privacy: .public): \(error.localizedDescription, privacy: .public)")
            errorMessage = AppLanguage.currentStrings.design.handoffLaunchFailed(command)
        }
    }

    /// Write .mcp.json to project root so AI tools auto-discover the MCP server.
    private func writeMCPConfig() {
        let configPath = (project.rootPath as NSString).appendingPathComponent(".mcp.json")
        let fm = FileManager.default

        let binPath = findMCPServerBinary()
        let serverEntry: [String: Any] = binPath != nil
            ? ["type": "stdio", "command": binPath!, "args": ["--project-root", project.rootPath]]
            : ["type": "stdio", "command": "swift", "args": ["run", "--package-path", findPackageRoot() ?? ".", "LAOMCPServer", "--project-root", project.rootPath]]

        var root: [String: Any] = [:]
        if let existingData = fm.contents(atPath: configPath),
           let existing = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
            root = existing
        }
        var servers = (root["mcpServers"] as? [String: Any]) ?? [:]
        servers["lao-design"] = serverEntry
        root["mcpServers"] = servers

        do {
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: configPath))
            logger.info("[MCP] .mcp.json written to \(configPath, privacy: .public)")
        } catch {
            logger.error("[MCP] Failed to write .mcp.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func findMCPServerBinary() -> String? {
        let fm = FileManager.default

        // 1. App bundle (distribution / Xcode build)
        if let bundlePath = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("LAOMCPServer").path,
           fm.isExecutableFile(atPath: bundlePath) {
            return bundlePath
        }

        // 2. SPM build directory — search across architectures and configurations
        if let pkgRoot = findPackageRoot() {
            let buildDir = (pkgRoot as NSString).appendingPathComponent(".build")
            if let triples = try? fm.contentsOfDirectory(atPath: buildDir) {
                for triple in triples where triple.contains("apple-macosx") {
                    for config in ["debug", "release"] {
                        let candidate = "\(buildDir)/\(triple)/\(config)/LAOMCPServer"
                        if fm.isExecutableFile(atPath: candidate) {
                            return candidate
                        }
                    }
                }
            }
        }

        return nil
    }

    private func findPackageRoot() -> String? {
        let packageRoot = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
        let packageSwift = (packageRoot as NSString).appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: packageSwift) {
            return packageRoot
        }
        return nil
    }

    private func shellEscaped(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Persistence

    /// Debounced sync — coalesces rapid calls within 2 seconds.
    @discardableResult
    private func syncToRequest() -> Task<Void, Never>? {
        syncDebounceTask?.cancel()
        syncDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.syncDebounceInterval)
            guard !Task.isCancelled else { return }
            _ = self?.syncToRequestImmediate()
        }
        return syncDebounceTask
    }

    /// Tracks the mutation counter value at the time of the last successful sync.
    private var lastSyncedMutationCounter: Int = 0

    /// Sync current workflow state to the DB DesignSession (immediate, no debounce).
    /// Skips serialization if nothing has mutated since the last sync.
    @discardableResult
    private func syncToRequestImmediate() -> Task<Void, Never>? {
        guard let requestId else { return nil }
        guard let wf = workflow else { return nil }

        // Skip if no mutations since last sync
        if wf.mutationCounter == lastSyncedMutationCounter { return nil }
        lastSyncedMutationCounter = wf.mutationCounter

        let p = progress

        let status: DesignSessionStatus = {
            switch wf.phase {
            case .input: return .planning
            case .analyzing: return .planning
            case .approachSelection: return .planning
            case .generatingSkeleton: return .planning
            case .generatingGraph: return .planning
            case .planning: return .reviewing
            case .completed: return .completed
            case .failed: return .failed
            }
        }()

        let workflowJSON: String = {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            do {
                let data = try encoder.encode(wf)
                return String(data: data, encoding: .utf8) ?? ""
            } catch {
                logger.error("[Sync] Failed to encode workflow: \(error.localizedDescription, privacy: .public)")
                return ""
            }
        }()

        var request = DesignSession(
            id: requestId,
            projectId: project.id,
            boardId: project.id, // default board has same UUID as project
            title: String(wf.taskDescription.prefix(60)),
            taskDescription: wf.taskDescription,
            status: status,
            phaseName: wf.phase.rawValue,
            totalSteps: p.total,
            completedSteps: p.completed,
            triageSummary: wf.designSummary,
            roadmapJSON: preExtractedGraphJSON ?? "[]",
            brdJSON: cachedBrdJSON,
            designBriefJSON: cachedDesignBriefJSON,
            cpsJSON: "",
            designStateJSON: workflowJSON,
            apiCallCount: wf.apiCallCount,
            estimatedTokens: wf.estimatedTokens
        )

        // Auto-register with coordinator on first sync
        registerWithCoordinator()

        let syncTask = Task {
            // Read existing record to preserve createdAt
            if let existing = await container.designSessionService.getRequest(id: requestId) {
                request.createdAt = existing.createdAt
            }
            do {
                try await container.designSessionService.updateRequest(request)
            } catch {
                logger.error("[Sync] DB write failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self.errorMessage = AppLanguage.currentStrings.design.syncFailed
                }
            }
            NotificationCenter.default.post(name: .laoDesignStatsChanged, object: nil)
        }
        return syncTask
    }

    /// Ensure the latest workflow state is flushed to DB before navigating away.
    func flushSync() async {
        syncDebounceTask?.cancel()
        await syncToRequestImmediate()?.value
    }

    // MARK: - Coordinator

    /// Register this ViewModel with ActiveWorkflowCoordinator for background lifecycle management.
    func registerWithCoordinator() {
        guard let reqId = requestId, coordinatorRequestId == nil else { return }
        coordinatorRequestId = reqId
        container.activeWorkflowCoordinator.viewModels[reqId] = self
    }

    /// Notify the coordinator that this workflow has reached a blocking state
    /// requiring user intervention (completion, failure, etc.).
    /// For terminal states (completed/failed), also dequeue the next request for this project.
    private func notifyBlockingState(message: String? = nil) {
        guard let reqId = coordinatorRequestId ?? requestId else { return }
        container.activeWorkflowCoordinator.markNeedsAttention(requestId: reqId, message: message)

        // Release the project execution slot for terminal states
        if workflow?.phase == .completed || workflow?.phase == .failed {
            container.activeWorkflowCoordinator.dequeueNext(projectId: project.id)
        }
    }

    // MARK: - Lifecycle

    /// Cancel any running tasks, persist current state, and ensure the sync completes.
    /// Called when the user navigates away from the workflow detail view.
    func gracefulStop() async {
        // 1. Cancel the running execution task
        executionTask?.cancel()
        executionTask = nil

        // 2. Mark inProgress items as pending (streaming was interrupted)
        if var wf = workflow {
            var changed = false
            for si in wf.deliverables.indices {
                for ii in wf.deliverables[si].items.indices where wf.deliverables[si].items[ii].status == .inProgress {
                    wf.deliverables[si].items[ii].status = .pending
                    changed = true
                }
            }
            for i in wf.steps.indices where wf.steps[i].status == .inProgress {
                wf.steps[i].status = .pending
                wf.steps[i].startedAt = nil
                wf.steps[i].output = ""
                changed = true
            }
            if changed { workflow = wf }
        }

        // 3. Reset transient UI state
        isAnalyzing = false
        activeItemWorks.removeAll()

        // 4. Flush to DB and wait for completion
        await flushSync()
    }

    /// Stop the current director task without destroying workflow state.
    /// Preserves the workflow and coordinator registration so the user can retry.
    func stopDesignTask() {
        executionTask?.cancel()
        executionTask = nil
        isAnalyzing = false
        isGeneratingSkeleton = false
        isGeneratingGraph = false
        skeletonStreamOutput = ""
        skeletonPreviewSections = []
        graphStreamOutput = ""
        activeItemWorks.removeAll()
        analysisStreamOutput = ""
        currentAgentLabel = ""
        errorMessage = lang.design.stoppedByUser

        // Clean up workflow.phase to prevent ghost overlay
        if workflow?.phase == .analyzing {
            // Analysis was in progress -- revert to input so user can try again
            if workflow?.deliverables.isEmpty == true {
                workflow?.transitionTo(.input)
            } else {
                workflow?.transitionTo(.planning)
            }
        }
        if workflow?.phase == .generatingSkeleton {
            workflow?.transitionTo(.approachSelection)
        }
        if workflow?.phase == .generatingGraph {
            if workflow?.deliverables.isEmpty == true {
                workflow?.transitionTo(.approachSelection)
            } else {
                workflow?.transitionTo(.planning)
            }
        }

        syncToRequest()
    }

    /// Restart the workflow from scratch (re-runs analysis).
    func restartWorkflow() {
        let savedTask = taskInput
        let feedback = pendingReanalyzeFeedback
        let prevSummary = previousAnalysisSummary
        isRestoredRequest = false
        restoredRequest = nil
        reset()
        taskInput = savedTask
        pendingReanalyzeFeedback = feedback
        previousAnalysisSummary = prevSummary
        startAnalysis()
    }

    func dismissError() {
        errorMessage = nil
        // If workflow is stuck in .analyzing phase but nothing is actually analyzing,
        // restore to a sensible state to avoid showing an empty overlay.
        if workflow?.phase == .analyzing, !isAnalyzing {
            if workflow?.deliverables.isEmpty == true {
                // Analysis never completed -- no progress to preserve
                workflow = nil
            } else {
                workflow?.transitionTo(.planning)
            }
        }
    }

    func reset() {
        executionTask?.cancel()
        executionTask = nil
        taskInput = ""
        workflow = nil
        isAnalyzing = false
        analysisStreamOutput = ""
        activeItemWorks.removeAll()
        selectedItemId = nil
        currentAgentLabel = ""
        errorMessage = nil
        isLoadingRequest = false
        isRestoredRequest = false
        restoredRequest = nil
        diskDocumentFiles = []
        exportValidationIssues = []
        uncertaintyChatMessages = []
        uncertaintyStreamOutput = ""
        isUncertaintyChatting = false
        pendingUncertaintyResolution = nil
        uncertaintyDiscussionCompleted = false
        uncertaintyDiscussionTask?.cancel()
        uncertaintyDiscussionTask = nil
    }

    // MARK: - Private: Agent Resolution

    /// Returns the preferred director agent (first match).
    private func resolveDesignAgent() -> Agent? {
        resolveDesignAgents().first
    }

    /// Returns director + directorFallback agents in priority order for fallback retry.
    private func resolveDesignAgents() -> [Agent] {
        var agents: [Agent] = []
        // Primary director(s)
        agents.append(contentsOf: availableAgents.filter { $0.tier == .director && $0.isEnabled })
        // Fallback director(s)
        agents.append(contentsOf: availableAgents.filter { $0.tier == .directorFallback && $0.isEnabled })
        // Built-in Claude fallback if nothing configured
        if agents.isEmpty, let claude = resolveClaudeAgent() {
            agents.append(claude)
        }
        return agents
    }

    /// Run a streaming call with automatic fallback to the next director agent on failure.
    /// Updates `currentAgentLabel` to reflect which agent is actually being used.
    private func runWithFallback(
        prompt: String,
        jsonSchema: String? = nil,
        streamHandler: @Sendable @escaping (String) -> Void
    ) async throws -> (response: String, agent: Agent) {
        // Always refresh from DB so settings changes take effect immediately
        await loadAgents()
        let agents = resolveDesignAgents()
        guard !agents.isEmpty else {
            throw DesignError.noAgent(lang.common.noAgentConfigured)
        }

        do {
            let result = try await runWithAgentFallback(
                agents: agents,
                runner: container.cliAgentRunner,
                prompt: prompt,
                jsonSchema: jsonSchema,
                projectId: project.id,
                rootPath: project.rootPath,
                onAttemptStart: { [weak self] agent, attemptIndex in
                    guard let self else { return }
                    if attemptIndex > 0 {
                        self.currentAgentLabel = "\(agent.provider.rawValue) / \(agent.model) (fallback)"
                        streamHandler("Switching to fallback agent: \(agent.provider.rawValue) / \(agent.model)...\n")
                    } else {
                        self.currentAgentLabel = "\(agent.provider.rawValue) / \(agent.model)"
                    }
                },
                streamHandler: streamHandler
            )

            // Track failed attempts cost
            for attempt in result.failedAttempts {
                trackUsage(promptLength: attempt.promptLength, responseLength: 0,
                           provider: attempt.agent.provider, succeeded: false)
            }
            // Track successful call
            trackUsage(promptLength: prompt.count, responseLength: result.response.count,
                       provider: result.agent.provider)
            return (result.response, result.agent)
        } catch is FallbackRunError {
            throw DesignError.noAgent(lang.common.noAgentConfigured)
        }
    }

    // MARK: - Split Skeleton Graph Helpers

    /// Fetch skeleton relationships in isolation. Updates `relationshipsStatus` on completion.
    private func fetchSkeletonRelationships(
        approachLabel: String,
        approachSummary: String,
        itemList: [(section: String, name: String, briefDescription: String, components: [String])]
    ) async -> [DesignAnalysisResponse.RelationshipSpec]? {
        let prompt = promptBuilder.buildSkeletonRelationshipsPrompt(
            approachLabel: approachLabel,
            approachSummary: approachSummary,
            itemList: itemList
        )
        do {
            let (response, _) = try await runWithFallback(
                prompt: prompt,
                jsonSchema: DesignJSONSchemas.skeletonRelationships
            ) { [weak self] text in
                guard !Task.isCancelled else { return }
                Task { @MainActor in self?.graphStreamOutput = text }
            }
            if let result = DesignStepResultParser.parseSkeletonRelationshipsResponse(from: response) {
                let count = result.relationships?.count ?? 0
                relationshipsStatus = .done(count)
                return result.relationships
            } else {
                logger.warning("Skeleton relationships parsing failed")
                logEvent(DesignEventType.analysisFailed, payload: ["error": "skeleton_relationships_parsing_failed_nonfatal"])
                relationshipsStatus = .failed
                return nil
            }
        } catch {
            logger.warning("Skeleton relationships generation failed: \(error.localizedDescription, privacy: .public)")
            relationshipsStatus = .failed
            return nil
        }
    }

    /// Fetch skeleton uncertainties in isolation. Updates `uncertaintiesStatus` on completion.
    private func fetchSkeletonUncertainties(
        approachLabel: String,
        approachSummary: String,
        hiddenRequirements: [String],
        itemList: [(section: String, name: String, briefDescription: String)]
    ) async -> [DesignAnalysisResponse.UncertaintySpec]? {
        let prompt = promptBuilder.buildSkeletonUncertaintiesPrompt(
            approachLabel: approachLabel,
            approachSummary: approachSummary,
            hiddenRequirements: hiddenRequirements,
            itemList: itemList
        )
        do {
            let (response, _) = try await runWithFallback(
                prompt: prompt,
                jsonSchema: DesignJSONSchemas.skeletonUncertainties
            ) { _ in }  // no streaming UI for uncertainties
            if let result = DesignStepResultParser.parseSkeletonUncertaintiesResponse(from: response) {
                let count = result.uncertainties?.count ?? 0
                uncertaintiesStatus = .done(count)
                return result.uncertainties
            } else {
                logger.warning("Skeleton uncertainties parsing failed")
                logEvent(DesignEventType.analysisFailed, payload: ["error": "skeleton_uncertainties_parsing_failed_nonfatal"])
                uncertaintiesStatus = .failed
                return nil
            }
        } catch {
            logger.warning("Skeleton uncertainties generation failed: \(error.localizedDescription, privacy: .public)")
            uncertaintiesStatus = .failed
            return nil
        }
    }

    private func resolveClaudeAgent() -> Agent? {
        Agent(
            name: "Director",
            tier: .director,
            provider: .claude,
            model: "claude-sonnet-4-5-20250514"
        )
    }

    /// Resolve step agent: prefer explicit ID, then round-robin across enabled step agents, then Claude fallback.
    private func nextStepAgent(preferredId: UUID? = nil) -> Agent? {
        let stepAgents = availableAgents.filter { $0.tier == .step && $0.isEnabled }
        if let preferred = preferredId,
           let match = stepAgents.first(where: { $0.id == preferred }) {
            return match
        }
        guard !stepAgents.isEmpty else { return resolveClaudeAgent() }
        let agent = stepAgents[stepAgentRoundRobinIndex % stepAgents.count]
        stepAgentRoundRobinIndex += 1
        return agent
    }

    /// Ask the Design LLM to assign the best step agent to each item.
    /// Returns empty dictionary when ≤1 step agents (no assignment needed) or on failure (round-robin fallback).
    private func assignAgentsToItems(
        targets: [(sectionType: String, itemId: UUID)]
    ) async -> [UUID: UUID] {
        let stepAgents = availableAgents.filter { $0.tier == .step && $0.isEnabled }
        guard stepAgents.count > 1, let wf = workflow else { return [:] }

        // Build item descriptors from workflow
        let items: [(sectionType: String, itemId: UUID, itemName: String, briefDescription: String?)] = targets.compactMap { t in
            guard let found = wf.findItem(byId: t.itemId) else { return nil }
            return (t.sectionType, t.itemId, found.item.name, found.item.briefDescription)
        }
        guard !items.isEmpty else { return [:] }

        let prompt = promptBuilder.buildAgentAssignmentPrompt(items: items, stepAgents: stepAgents)

        let systemMsg = DesignChatMessage(role: .system, content: "Assigning agents to items...")
        workflow?.appendChatMessage(systemMsg)

        do {
            let (response, _) = try await runWithFallback(prompt: prompt, jsonSchema: DesignJSONSchemas.agentAssignment) { _ in }
            // trackUsage is already called inside runWithFallback
            return parseAgentAssignments(response, validAgentIds: Set(stepAgents.map(\.id)))
        } catch {
            return [:]
        }
    }

    /// Parse Design's agent assignment JSON response.
    private func parseAgentAssignments(_ response: String, validAgentIds: Set<UUID>) -> [UUID: UUID] {
        // Extract JSON array from response (may be wrapped in ```json ... ```)
        let cleaned: String
        if let jsonStart = response.firstIndex(of: "["),
           let jsonEnd = response.lastIndex(of: "]") {
            cleaned = String(response[jsonStart...jsonEnd])
        } else {
            return [:]
        }

        struct Assignment: Decodable {
            let itemId: String
            let agentId: String
        }

        guard let data = cleaned.data(using: .utf8) else { return [:] }
        let assignments: [Assignment]
        do {
            assignments = try JSONDecoder().decode([Assignment].self, from: data)
        } catch {
            logger.warning("[AgentAssignment] Failed to decode: \(error.localizedDescription, privacy: .public)")
            return [:]
        }

        var result: [UUID: UUID] = [:]
        for a in assignments {
            if let itemUUID = UUID(uuidString: a.itemId),
               let agentUUID = UUID(uuidString: a.agentId),
               validAgentIds.contains(agentUUID) {
                result[itemUUID] = agentUUID
            }
        }
        return result
    }

    // MARK: - Private: Adaptive Concurrency

    /// Reduce concurrency when rate-limited, notifying user via chat.
    private func reduceConcurrency() {
        guard currentMaxConcurrency > concurrencyFloor else { return }
        currentMaxConcurrency -= 1
        consecutiveSuccesses = 0
        let msg = DesignChatMessage(
            role: .system,
            content: lang.design.concurrencyReducedFormat(currentMaxConcurrency)
        )
        workflow?.appendChatMessage(msg)
    }

    /// Record a successful elaboration; scale concurrency back up after enough successes.
    private func recordElaborationSuccess() {
        consecutiveSuccesses += 1
        if consecutiveSuccesses >= successesBeforeScaleUp,
           currentMaxConcurrency < concurrencyCeiling {
            currentMaxConcurrency += 1
            consecutiveSuccesses = 0
        }
    }

    // MARK: - Private: Usage Tracking

    /// Record an API call's prompt and response sizes for usage tracking.
    private func trackUsage(promptLength: Int, responseLength: Int,
                            provider: ProviderKey? = nil, succeeded: Bool = true) {
        workflow?.recordUsage(promptLength: promptLength, responseLength: responseLength,
                              provider: provider, succeeded: succeeded)
    }

    // MARK: - Step Helper

    /// Atomically update a single step inside the workflow.
    private func updateStep(at index: Int, _ mutate: (inout DesignWorkflowStep) -> Void) {
        guard var wf = workflow, index < wf.steps.count else { return }
        mutate(&wf.steps[index])
        workflow = wf
    }

    // MARK: - Error Types

    private enum DesignError: LocalizedError {
        case noAgent(String)
        case invalidJSON(String)
        var errorDescription: String? {
            switch self {
            case .noAgent(let message):
                message
            case .invalidJSON(let detail):
                detail
            }
        }
    }
}

// MARK: - Stream Accumulator
