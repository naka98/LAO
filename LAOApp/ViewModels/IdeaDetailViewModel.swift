import Foundation
import LAODomain
import LAOServices

/// ViewModel for the idea detail (chat) view. Handles message thread, AI analysis, and request conversion.
@Observable @MainActor
final class IdeaDetailViewModel {
    let container: AppContainer
    let project: Project

    var idea: Idea
    var messages: [IdeaMessage] = []
    var isAnalyzing = false
    var streamingOutput: String = ""
    var analysisStatus: String = ""
    var errorMessage: String?
    var designFailed = false
    var isConverting = false
    /// Whether loadFullIdea() has completed at least once.
    /// Prevents deleteIfEmpty() from acting on stale list-loaded data.
    private(set) var fullDataLoaded = false
    var lang: AppStrings = .en
    var replyingExperts: Set<UUID> = []
    /// Experts that failed follow-up due to no configured step agent — stores the unsent text for retry
    var expertFollowUpErrors: [UUID: String] = [:]

    // Reference images collected from expert analysis or unified reference phase
    var referenceImages: [ReferenceImage] = []
    var requestingReferencesExperts: Set<UUID> = []

    // Unified reference phase state
    var isGeneratingUnifiedReferences = false
    var unifiedReferenceFeedback: String = ""
    var showReferencePhaseOverlay = false

    // BRD generation state (triggered after synthesis)
    var brdJSON: String = ""
    var isBrdGenerating = false
    var isBrdReady = false
    var brdError: String?

    // Design Brief state (structured exploration output — wraps BRD + synthesis decisions)
    var designBriefJSON: String = ""
    var isBriefReady = false

    private var availableAgents: [Agent] = []
    private var stepAgentRoundRobinIndex: Int = 0
    /// Cached user profile for client context injection into prompts.
    private var userProfile = UserProfile()

    /// Always reload agents from DB so settings changes take effect immediately.
    private func refreshAgents() async {
        availableAgents = await container.agentService.listAgents()
    }
    private var currentTask: Task<Void, Never>?
    private var expertFollowUpTasks: [UUID: Task<Void, Never>] = [:]

    init(container: AppContainer, project: Project, idea: Idea) {
        self.container = container
        self.project = project
        self.idea = idea
        loadMessages()
        // Restore references: prefer unified phase refs, fall back to per-expert
        if messages.contains(where: { $0.unifiedReferencesJSON != nil }) {
            collectUnifiedReferenceImages()
        } else {
            collectReferenceImagesFromExperts()
        }
    }

    // MARK: - Message Serialization

    private func loadMessages() {
        guard !idea.messagesJSON.isEmpty, idea.messagesJSON != "[]" else {
            messages = []
            return
        }
        guard let data = idea.messagesJSON.data(using: .utf8) else { return }
        var decoded = (try? JSONDecoder().decode([IdeaMessage].self, from: data)) ?? []
        // isLoading과 partialOpinion은 런타임 전용 UI 상태 — 세션 간 유지 불가
        for i in decoded.indices {
            guard var experts = decoded[i].experts else { continue }
            for j in experts.indices {
                experts[j].isLoading = false
                experts[j].partialOpinion = nil
            }
            decoded[i].experts = experts
        }
        messages = decoded
    }

    private func serializeMessages() -> String {
        guard let data = try? JSONEncoder().encode(messages) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func saveIdea() async {
        idea.messagesJSON = serializeMessages()
        idea.updatedAt = Date()
        do {
            try await container.ideaService.updateIdea(idea)
        } catch {
            errorMessage = lang.common.failedToSaveIdeaFormat(error.localizedDescription)
        }
    }

    /// Record an API call's prompt and response sizes for usage tracking.
    private func trackUsage(promptLength: Int, responseLength: Int) {
        idea.apiCallCount += 1
        idea.totalInputChars += promptLength
        idea.totalOutputChars += responseLength
    }

    // MARK: - Load Full Data

    func loadFullIdea() async {
        guard let full = await container.ideaService.getIdea(id: idea.id) else {
            fullDataLoaded = true
            return
        }
        // Don't overwrite in-memory state if analysis started while the DB fetch was in flight
        guard !isAnalyzing else {
            fullDataLoaded = true
            return
        }
        idea = full
        loadMessages()
        fullDataLoaded = true
        collectReferenceImagesFromExperts()

        // Recover stuck .analyzing status — if no task is running, reset to previous state.
        // The previous VM's background task may still be running and saving results,
        // so show loading spinners first and wait briefly before marking as interrupted.
        if idea.status == .analyzing, !isAnalyzing {
            let hasDesignResponse = messages.contains { $0.role == .design }
            if hasDesignResponse {
                // Show loading spinners for incomplete experts while waiting
                var hasIncomplete = false
                for msgIdx in messages.indices {
                    guard messages[msgIdx].experts != nil else { continue }
                    for expIdx in messages[msgIdx].experts!.indices {
                        let expert = messages[msgIdx].experts![expIdx]
                        if expert.opinion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && expert.errorMessage == nil {
                            messages[msgIdx].experts![expIdx].isLoading = true
                            hasIncomplete = true
                        }
                    }
                }

                // Wait for background task to finish saving results
                if hasIncomplete {
                    for _ in 0..<3 {
                        try? await Task.sleep(for: .seconds(2))
                        guard !isAnalyzing else { return } // user started new analysis
                        if let refreshed = await container.ideaService.getIdea(id: idea.id),
                           refreshed.status != .analyzing {
                            idea = refreshed
                            loadMessages()
                            collectReferenceImagesFromExperts()
                            return // background task completed successfully
                        }
                    }
                    // Re-fetch latest state before marking interrupted
                    if let refreshed = await container.ideaService.getIdea(id: idea.id) {
                        idea = refreshed
                        loadMessages()
                        collectReferenceImagesFromExperts()
                    }
                }

                // Mark any still-incomplete experts as interrupted
                for msgIdx in messages.indices {
                    guard messages[msgIdx].experts != nil else { continue }
                    for expIdx in messages[msgIdx].experts!.indices {
                        let expert = messages[msgIdx].experts![expIdx]
                        if expert.opinion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && expert.errorMessage == nil {
                            messages[msgIdx].experts![expIdx].errorMessage = lang.ideaBoard.interruptedByRestart
                        }
                    }
                }
                idea.status = .analyzed
            } else {
                idea.status = .draft
            }
            await saveIdea()
        }
    }

    /// Cancel all in-progress tasks (director + expert follow-ups).
    func cancelIfNeeded() {
        currentTask?.cancel()
        currentTask = nil
        for (id, task) in expertFollowUpTasks {
            task.cancel()
            expertFollowUpTasks[id] = nil
        }
    }

    /// Stop the current analysis, cancel all tasks, and clean up UI state.
    func stopAnalysis() async {
        cancelIfNeeded()
        isAnalyzing = false
        streamingOutput = ""
        analysisStatus = ""
        replyingExperts.removeAll()

        // Mark still-loading experts as interrupted
        for msgIdx in messages.indices {
            guard messages[msgIdx].experts != nil else { continue }
            for expIdx in messages[msgIdx].experts!.indices {
                let expert = messages[msgIdx].experts![expIdx]
                if expert.isLoading
                    || (expert.opinion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && expert.errorMessage == nil) {
                    messages[msgIdx].experts![expIdx].isLoading = false
                    messages[msgIdx].experts![expIdx].errorMessage = lang.ideaBoard.interruptedByRestart
                }
            }
        }

        // Revert idea status: draft if no completed expert round, analyzed otherwise
        let hasCompletedRound = messages.contains { msg in
            msg.role == .design && msg.experts?.contains(where: {
                !$0.opinion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) == true
        }
        idea.status = hasCompletedRound ? .analyzed : .draft
        await saveIdea()
    }

    /// Delete the idea from the DB if no messages have been added yet.
    /// Guarded by fullDataLoaded to prevent race with async loadFullIdea(),
    /// and by status to avoid deleting ideas that have progressed beyond draft.
    func deleteIfEmpty() async {
        guard fullDataLoaded else { return }
        guard idea.status == .draft else { return }
        guard messages.isEmpty else { return }
        cancelIfNeeded()
        try? await container.ideaService.deleteIdea(id: idea.id)
    }

    // MARK: - Initial Analysis (Design)

    func analyze() {
        guard !isAnalyzing else { return }
        designFailed = false
        errorMessage = nil
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            await self?.performAnalysis()
        }
    }

    private func performAnalysis() async {
        isAnalyzing = true
        designFailed = false
        streamingOutput = ""
        analysisStatus = lang.ideaBoard.designPlanningStatus
        errorMessage = nil

        // Update status
        idea.status = .analyzing
        await saveIdea()

        // Load agents and user profile
        await refreshAgents()
        userProfile = await container.userProfileService.getProfile()

        // Build the initial idea body from the first user message
        let ideaBody = messages.first(where: { $0.role == .user })?.content ?? idea.title

        let prompt = IdeaPromptBuilder.buildInitialAnalysisPrompt(ideaBody: ideaBody, agents: availableAgents, userProfile: userProfile)

        do {
            try Task.checkCancellation()

            // Phase 1: Design assigns expert roles (planning only)
            let (response, designAgent, designFallback) = try await runWithFallback(prompt: prompt) { [weak self] text in
                Task { @MainActor in
                    self?.streamingOutput = text
                }
            }

            try Task.checkCancellation()

            // Parse planning response
            let planning = parsePlanningResponse(response)

            guard !planning.experts.isEmpty else {
                // Fallback: if no experts parsed, treat as plain text director message
                let fallbackMessage = IdeaMessage(
                    role: .design,
                    content: response,
                    modelName: designAgent.model,
                    fallbackInfo: designFallback
                )
                messages.append(fallbackMessage)
                idea.status = .analyzed
                streamingOutput = ""
                await saveIdea()
                isAnalyzing = false
                return
            }

            // Phase 2: Run each expert in parallel via Step Agents
            streamingOutput = ""
            analysisStatus = lang.ideaBoard.expertsAnalyzingStatus

            // Pre-populate loading placeholders so users see how many experts will run
            let placeholders = planning.experts.map { a in
                IdeaExpert(name: a.name, role: a.role, opinion: "", isLoading: true, focus: a.focus)
            }

            // Create message immediately with placeholders visible
            let designMessage = IdeaMessage(
                role: .design,
                content: planning.content,
                experts: placeholders,
                modelName: designAgent.model,
                fallbackInfo: designFallback
            )
            messages.append(designMessage)
            let messageIndex = messages.count - 1
            await saveIdea()

            await runInitialExpertsInParallel(
                assignments: planning.experts,
                ideaBody: ideaBody,
                messageIndex: messageIndex
            )

            collectReferenceImagesFromExperts()

            try Task.checkCancellation()

            idea.status = .analyzed
            streamingOutput = ""
            await saveIdea()
        } catch is CancellationError {
            idea.status = .draft
            streamingOutput = ""
            await saveIdea()
        } catch {
            idea.status = .draft
            designFailed = true
            errorMessage = lang.ideaBoard.analysisFailedFormat(error.localizedDescription)
            await saveIdea()
        }

        isAnalyzing = false
    }

    // MARK: - Send Follow-up Message (Parallel Step Agents)

    /// Sends first user message and immediately starts analysis (no separate Analyze button needed).
    func sendAndAnalyze(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAnalyzing else { return }
        messages.append(IdeaMessage(role: .user, content: trimmed))
        // Update idea title from the first message content so the list shows something meaningful
        let firstLine = trimmed.components(separatedBy: "\n").first ?? trimmed
        idea.title = firstLine.count > 60 ? String(firstLine.prefix(60)) + "..." : firstLine
        designFailed = false
        errorMessage = nil
        // Set analyzing state immediately so UI shows feedback before async work
        isAnalyzing = true
        analysisStatus = lang.ideaBoard.designPlanningStatus
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            await self?.saveIdea()
            await self?.performAnalysis()
        }
    }

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAnalyzing else { return }

        // Add user message synchronously
        let userMessage = IdeaMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        // Set analyzing state immediately so UI shows feedback before async work
        isAnalyzing = true
        analysisStatus = lang.ideaBoard.expertsAnalyzingStatus

        currentTask?.cancel()
        currentTask = Task { [weak self] in
            await self?.performSendMessage(trimmed)
        }
    }

    private func performSendMessage(_ trimmed: String) async {
        idea.status = .analyzing
        await saveIdea()

        streamingOutput = ""
        errorMessage = nil

        // Reload agents so settings changes take effect
        await refreshAgents()

        let ideaBody = messages.first(where: { $0.role == .user })?.content ?? idea.title

        // Find expert definitions from the most recent director message with experts
        let expertDefs = messages.last(where: {
            $0.role == .design && $0.experts != nil && !($0.experts?.isEmpty ?? true)
        })?.experts ?? []

        if expertDefs.isEmpty {
            idea.status = .analyzed
            await saveIdea()
            errorMessage = lang.ideaBoard.noExpertPanel
            designFailed = true
            isAnalyzing = false
            return
        }

        analysisStatus = lang.ideaBoard.expertsAnalyzingStatus

        // Build compact recent context (sliding window)
        let previousMessages = Array(messages.dropLast()) // exclude the just-added user message
        let recentContext = IdeaPromptBuilder.buildRecentContext(from: previousMessages)

        do {
            try Task.checkCancellation()

            // Pre-populate with loading placeholders
            let placeholders = expertDefs.map { e in
                IdeaExpert(name: e.name, role: e.role, opinion: "",
                           agentId: e.agentId, isLoading: true, focus: e.focus)
            }
            let designMessage = IdeaMessage(
                role: .design,
                content: "",
                experts: placeholders,
                summary: nil
            )
            messages.append(designMessage)
            let messageIndex = messages.count - 1
            await saveIdea()

            await runExpertsInParallel(
                experts: expertDefs,
                ideaBody: ideaBody,
                recentContext: recentContext,
                question: trimmed,
                messageIndex: messageIndex
            )

            try Task.checkCancellation()

            streamingOutput = ""
            idea.status = .analyzed
            await saveIdea()
        } catch is CancellationError {
            streamingOutput = ""
            idea.status = .analyzed
            await saveIdea()
        } catch {
            idea.status = .analyzed
            errorMessage = "\(lang.ideaBoard.responseFailed): \(error.localizedDescription)"
            await saveIdea()
        }

        isAnalyzing = false
    }

    /// Explicitly trigger Design synthesis (방향 결정 버튼).
    /// Opens the synthesis overlay immediately and runs LLM in the background.
    /// No chat message is added until the founder approves.
    /// - Parameter guide: Optional convergence guide from the founder (e.g. preferred direction, elements to combine/exclude).
    func requestSynthesis(guide: String? = nil) {
        guard !isBrdGenerating else { return }

        // Set status to analyzed and start Brief generation directly (no intermediate synthesis LLM)
        idea.status = .analyzed
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            guard let self else { return }
            await saveIdea()
            startBRDGeneration()
        }
    }

    // MARK: - Panel Rearrangement (패널 재구성)

    func rearrangePanel(reason: String = "") {
        guard !isAnalyzing else { return }
        let existingExperts = messages
            .last(where: { $0.role == .design && ($0.experts?.isEmpty == false) })?
            .experts?
            .map { "\($0.name) (\($0.role))" } ?? []
        designFailed = false
        errorMessage = nil
        isAnalyzing = true
        analysisStatus = lang.ideaBoard.arrangingNewExperts
        currentTask?.cancel()
        currentTask = Task { [weak self] in
            await self?.performPanelRearrangement(reason: reason, existingExperts: existingExperts)
        }
    }

    private func performPanelRearrangement(reason: String, existingExperts: [String]) async {
        isAnalyzing = true
        idea.status = .analyzing
        streamingOutput = ""
        analysisStatus = lang.ideaBoard.arrangingNewExperts
        await saveIdea()

        await refreshAgents()
        let ideaBody = messages.first(where: { $0.role == .user })?.content ?? idea.title
        let recentContext = IdeaPromptBuilder.buildRecentContext(from: messages)
        let prompt = IdeaPromptBuilder.buildPanelRearrangementPrompt(
            ideaBody: ideaBody,
            existingExperts: existingExperts,
            reason: reason,
            agents: availableAgents,
            discussionContext: recentContext
        )

        do {
            try Task.checkCancellation()
            let (response, designAgent, designFallback) = try await runWithFallback(prompt: prompt) { [weak self] text in
                Task { @MainActor in self?.streamingOutput = text }
            }
            try Task.checkCancellation()

            let planning = parsePlanningResponse(response)
            guard !planning.experts.isEmpty else {
                let fallbackMsg = IdeaMessage(role: .design, content: response,
                                              modelName: designAgent.model, fallbackInfo: designFallback)
                messages.append(fallbackMsg)
                idea.status = .analyzed
                streamingOutput = ""
                await saveIdea()
                isAnalyzing = false
                return
            }

            streamingOutput = ""
            analysisStatus = lang.ideaBoard.newExpertsAnalyzing

            let placeholders = planning.experts.map { a in
                IdeaExpert(name: a.name, role: a.role, opinion: "", isLoading: true, focus: a.focus)
            }
            let designMessage = IdeaMessage(
                role: .design, content: planning.content,
                experts: placeholders, modelName: designAgent.model, fallbackInfo: designFallback
            )
            messages.append(designMessage)
            let messageIndex = messages.count - 1
            await saveIdea()

            await runInitialExpertsInParallel(
                assignments: planning.experts, ideaBody: ideaBody, messageIndex: messageIndex,
                discussionContext: planning.content
            )
            collectReferenceImagesFromExperts()
            try Task.checkCancellation()
            streamingOutput = ""
            idea.status = .analyzed
            await saveIdea()
        } catch is CancellationError {
            streamingOutput = ""
            idea.status = .analyzed
            await saveIdea()
        } catch {
            idea.status = .analyzed
            designFailed = true
            errorMessage = lang.ideaBoard.panelRearrangeFailedFormat(error.localizedDescription)
            await saveIdea()
        }
        isAnalyzing = false
    }

    // MARK: - Conversion Preview (변환 미리보기)


    // MARK: - Parallel Expert Execution

    /// Run initial expert analysis in parallel via Step Agents. Updates placeholders at messageIndex progressively.
    /// Non-throwing: individual expert failures are stored in expert.errorMessage instead of propagating.
    private func runInitialExpertsInParallel(
        assignments: [(name: String, role: String, focus: String, agentId: String?)],
        ideaBody: String,
        messageIndex: Int,
        discussionContext: String = ""
    ) async {
        let totalCount = assignments.count
        var completed = 0
        let capturedProfile = userProfile
        await withTaskGroup(of: (Int, Result<IdeaExpert, Error>, Int, Int).self) { group in
            for (i, assignment) in assignments.enumerated() {
                let (agent, fallbackInfo) = resolveAgentForExpert(agentId: assignment.agentId)
                group.addTask { [container, project, weak self] in
                    do {
                        let localI = i
                        let accumulator = StreamAccumulator()
                        let prompt = IdeaPromptBuilder.buildExpertInitialAnalysisPrompt(
                            expertName: assignment.name,
                            expertRole: assignment.role,
                            focus: assignment.focus,
                            ideaBody: ideaBody,
                            projectRootPath: project.rootPath,
                            discussionContext: discussionContext,
                            userProfile: capturedProfile
                        )
                        let response = try await container.cliAgentRunner.runStreaming(
                            agent: agent,
                            prompt: prompt,
                            projectId: project.id,
                            rootPath: project.rootPath
                        ) { chunk in
                            let text = accumulator.append(chunk)
                            Task { @MainActor in
                                self?.messages[messageIndex].experts?[localI].partialOpinion = text
                            }
                        }
                        let (afterEntities, entitiesJSON) = IdeaDetailViewModel.separateEntitiesBlock(from: response)
                        let (afterRefs, referencesJSON) = IdeaDetailViewModel.separateReferencesBlock(from: afterEntities)
                        let (opinion, limitationsJSON) = IdeaDetailViewModel.separateLimitationsBlock(from: afterRefs)
                        let expert = IdeaExpert(
                            name: assignment.name,
                            role: assignment.role,
                            opinion: opinion.trimmingCharacters(in: .whitespacesAndNewlines),
                            modelName: agent.model,
                            agentId: agent.id.uuidString,
                            fallbackInfo: fallbackInfo,
                            focus: assignment.focus,
                            entitiesJSON: entitiesJSON,
                            referencesJSON: referencesJSON,
                            limitationsJSON: limitationsJSON
                        )
                        return (localI, .success(expert), prompt.count, response.count)
                    } catch {
                        return (i, .failure(error), 0, 0)
                    }
                }
            }

            for await (i, result, promptLen, responseLen) in group {
                completed += 1
                if promptLen > 0 { trackUsage(promptLength: promptLen, responseLength: responseLen) }
                switch result {
                case .success(let expert):
                    messages[messageIndex].experts?[i] = expert
                case .failure(let error):
                    messages[messageIndex].experts?[i].isLoading = false
                    messages[messageIndex].experts?[i].errorMessage = error.localizedDescription
                }
                analysisStatus = lang.ideaBoard.expertsAnalyzingProgressFormat(completed, totalCount)
                await saveIdea()
            }
        }
    }

    /// Send a follow-up message to a single expert (per-card conversation).
    /// Appends user message immediately, then runs the expert's agent and appends the reply.
    func sendMessageToExpert(text: String, expertIndex: Int, messageIndex: Int) {
        guard messageIndex < messages.count,
              let experts = messages[messageIndex].experts,
              expertIndex < experts.count else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Prevent out-of-order messages: block new question while a reply is in flight
        guard !replyingExperts.contains(experts[expertIndex].id) else { return }

        // Capture history BEFORE the new user message so it's not duplicated in the prompt
        let historyBeforeCurrent = messages[messageIndex].experts?[expertIndex].followUpMessages ?? []

        // Append user message immediately for instant feedback (will be rolled back if no agent)
        let userMsg = IdeaExpertFollowUp(role: .user, content: trimmed)
        if messages[messageIndex].experts?[expertIndex].followUpMessages == nil {
            messages[messageIndex].experts?[expertIndex].followUpMessages = []
        }
        messages[messageIndex].experts?[expertIndex].followUpMessages?.append(userMsg)

        let expert = messages[messageIndex].experts![expertIndex]
        let expertId = expert.id
        let expertAgentId = expert.agentId
        let expertModelName = expert.modelName   // stored at initial analysis time
        let ideaBody = messages.first(where: { $0.role == .user })?.content ?? idea.title

        // Clear any previous no-agent error for this expert
        expertFollowUpErrors.removeValue(forKey: expertId)
        replyingExperts.insert(expertId)

        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                replyingExperts.remove(expertId)
                expertFollowUpTasks.removeValue(forKey: expertId)
            }

            // Reload agents so settings changes take effect
            await refreshAgents()

            // Abort immediately if user cancelled while agents were loading
            guard !Task.isCancelled else { return }

            // Check if any agent path is available: configured step agent, or expert's stored model
            let hasStepAgent = availableAgents.contains { $0.tier == .step && $0.isEnabled }
            guard hasStepAgent || expertModelName != nil else {
                // No agent available — roll back the optimistic append and show error with retry
                messages[messageIndex].experts?[expertIndex].followUpMessages?.removeLast()
                expertFollowUpErrors[expertId] = trimmed
                return
            }

            let (agent, _) = resolveAgentForExpert(agentId: expertAgentId,
                                                    preferredModel: expertModelName)
            do {
                let prompt = IdeaPromptBuilder.buildSingleExpertConversationPrompt(
                    expertName: expert.name,
                    expertRole: expert.role,
                    focus: expert.focus ?? expert.role,
                    initialOpinion: expert.opinion,
                    ideaBody: ideaBody,
                    followUpHistory: historyBeforeCurrent,
                    currentQuestion: trimmed,
                    projectRootPath: project.rootPath
                )
                let response = try await container.cliAgentRunner.run(
                    agent: agent,
                    prompt: prompt,
                    projectId: project.id,
                    rootPath: project.rootPath
                )
                guard !Task.isCancelled else { return }
                trackUsage(promptLength: prompt.count, responseLength: response.count)
                let replyMsg = IdeaExpertFollowUp(
                    role: .expert,
                    content: response.trimmingCharacters(in: .whitespacesAndNewlines),
                    modelName: agent.model
                )
                messages[messageIndex].experts?[expertIndex].followUpMessages?.append(replyMsg)
                await saveIdea()
            } catch is CancellationError {
                // User cancelled — do nothing (optimistic message already rolled back by cancelExpertFollowUp)
            } catch {
                let errMsg = IdeaExpertFollowUp(role: .expert, content: "⚠️ \(error.localizedDescription)")
                messages[messageIndex].experts?[expertIndex].followUpMessages?.append(errMsg)
                await saveIdea()
            }
        }
        expertFollowUpTasks[expertId] = task
    }

    /// Request reference anchors from a specific expert.
    /// Similar to sendMessageToExpert but uses a dedicated reference request prompt
    /// and parses ```references block from the response.
    func requestReferencesFromExpert(expertIndex: Int, messageIndex: Int) {
        guard messageIndex < messages.count,
              let experts = messages[messageIndex].experts,
              expertIndex < experts.count else { return }

        let expert = experts[expertIndex]
        let expertId = expert.id

        // Prevent duplicate requests
        guard !replyingExperts.contains(expertId) else { return }
        guard !requestingReferencesExperts.contains(expertId) else { return }

        let ideaBody = messages.first(where: { $0.role == .user })?.content ?? idea.title

        // Append a system-like user message so the conversation shows the request
        let userMsg = IdeaExpertFollowUp(role: .user, content: lang.ideaBoard.referenceRequestMessage)
        if messages[messageIndex].experts?[expertIndex].followUpMessages == nil {
            messages[messageIndex].experts?[expertIndex].followUpMessages = []
        }
        messages[messageIndex].experts?[expertIndex].followUpMessages?.append(userMsg)

        requestingReferencesExperts.insert(expertId)
        replyingExperts.insert(expertId)

        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                replyingExperts.remove(expertId)
                requestingReferencesExperts.remove(expertId)
                expertFollowUpTasks.removeValue(forKey: expertId)
            }

            await refreshAgents()
            guard !Task.isCancelled else { return }

            let (agent, _) = resolveAgentForExpert(agentId: expert.agentId,
                                                    preferredModel: expert.modelName)
            do {
                let prompt = IdeaPromptBuilder.buildReferenceRequestPrompt(
                    expertName: expert.name,
                    expertRole: expert.role,
                    initialOpinion: expert.opinion,
                    ideaBody: ideaBody
                )
                let response = try await container.cliAgentRunner.run(
                    agent: agent,
                    prompt: prompt,
                    projectId: project.id,
                    rootPath: project.rootPath
                )
                guard !Task.isCancelled else { return }
                trackUsage(promptLength: prompt.count, responseLength: response.count)

                // Parse references from response
                let (opinionText, refsJSON) = IdeaDetailViewModel.separateReferencesBlock(from: response)

                // Store references JSON on the expert
                if let refsJSON {
                    messages[messageIndex].experts?[expertIndex].referencesJSON = refsJSON
                    collectReferenceImagesFromExperts()
                }

                let replyMsg = IdeaExpertFollowUp(
                    role: .expert,
                    content: opinionText.trimmingCharacters(in: .whitespacesAndNewlines),
                    modelName: agent.model
                )
                messages[messageIndex].experts?[expertIndex].followUpMessages?.append(replyMsg)
                await saveIdea()
            } catch is CancellationError {
                // cancelled
            } catch {
                let errMsg = IdeaExpertFollowUp(role: .expert, content: "⚠️ \(error.localizedDescription)")
                messages[messageIndex].experts?[expertIndex].followUpMessages?.append(errMsg)
                await saveIdea()
            }
        }
        expertFollowUpTasks[expertId] = task
    }

    /// Cancel an in-flight expert follow-up and roll back the optimistic user message.
    /// Returns the question text so the caller can restore it to the input field.
    @discardableResult
    func cancelExpertFollowUp(expertIndex: Int, messageIndex: Int) -> String? {
        guard messageIndex < messages.count,
              let experts = messages[messageIndex].experts,
              expertIndex < experts.count else { return nil }

        let expertId = experts[expertIndex].id
        expertFollowUpTasks[expertId]?.cancel()
        // defer in the task will handle replyingExperts.remove and task cleanup

        // Roll back the optimistically appended user message and return its text
        guard messages[messageIndex].experts?[expertIndex].followUpMessages?.last?.role == .user else {
            return nil
        }
        let text = messages[messageIndex].experts?[expertIndex].followUpMessages?.last?.content
        messages[messageIndex].experts?[expertIndex].followUpMessages?.removeLast()
        if messages[messageIndex].experts?[expertIndex].followUpMessages?.isEmpty == true {
            messages[messageIndex].experts?[expertIndex].followUpMessages = nil
        }
        return text
    }

    /// Retry a follow-up that failed due to no configured step agent.
    func retryExpertFollowUp(expertIndex: Int, messageIndex: Int) {
        guard messageIndex < messages.count,
              let experts = messages[messageIndex].experts,
              expertIndex < experts.count else { return }
        let expertId = experts[expertIndex].id
        guard let text = expertFollowUpErrors[expertId] else { return }
        expertFollowUpErrors.removeValue(forKey: expertId)
        sendMessageToExpert(text: text, expertIndex: expertIndex, messageIndex: messageIndex)
    }

    /// Retry a single failed expert. Re-runs CLI and updates the expert at expertIndex in messageIndex.
    func retryExpert(expertIndex: Int, messageIndex: Int) {
        guard messageIndex < messages.count,
              let experts = messages[messageIndex].experts,
              expertIndex < experts.count else { return }
        let expert = experts[expertIndex]
        messages[messageIndex].experts?[expertIndex].isLoading = true
        messages[messageIndex].experts?[expertIndex].errorMessage = nil

        let ideaBody = messages.first(where: { $0.role == .user })?.content ?? idea.title
        let focus = expert.focus ?? expert.role

        Task { [weak self] in
            guard let self else { return }
            await refreshAgents()
            let (agent, fallbackInfo) = resolveAgentForExpert(agentId: expert.agentId,
                                                               preferredModel: expert.modelName)
            do {
                // Detect follow-up round: the user message immediately before this director message
                // is a different message from the first user message (which is the original idea).
                let prevUserIdx = (0..<messageIndex).reversed()
                    .first { messages[$0].role == .user }
                let firstUserMsgId = messages.first(where: { $0.role == .user })?.id
                let isFollowUpRound = prevUserIdx.map { messages[$0].id != firstUserMsgId } ?? false

                let prompt: String
                if isFollowUpRound, let prevIdx = prevUserIdx {
                    let question = messages[prevIdx].content
                    let recentContext = IdeaPromptBuilder.buildRecentContext(from: Array(messages[0..<messageIndex]))
                    let previousOpinion = findPreviousOpinion(
                        expertName: expert.name,
                        beforeMessageIndex: messageIndex
                    )
                    prompt = IdeaPromptBuilder.buildExpertFollowUpPrompt(
                        expertName: expert.name,
                        expertRole: expert.role,
                        initialOpinion: String(previousOpinion.prefix(500)),
                        ideaBody: ideaBody,
                        recentContext: recentContext,
                        question: question,
                        projectRootPath: project.rootPath
                    )
                } else {
                    prompt = IdeaPromptBuilder.buildExpertInitialAnalysisPrompt(
                        expertName: expert.name,
                        expertRole: expert.role,
                        focus: focus,
                        ideaBody: ideaBody,
                        projectRootPath: project.rootPath,
                        userProfile: userProfile
                    )
                }
                let response = try await container.cliAgentRunner.run(
                    agent: agent,
                    prompt: prompt,
                    projectId: project.id,
                    rootPath: project.rootPath
                )
                trackUsage(promptLength: prompt.count, responseLength: response.count)
                // Extract entities and limitations from initial analysis responses; preserve existing for follow-ups
                let (afterEntities, entitiesJSON) = isFollowUpRound
                    ? (response, expert.entitiesJSON)
                    : IdeaDetailViewModel.separateEntitiesBlock(from: response)
                let (opinion, limitationsJSON) = isFollowUpRound
                    ? (afterEntities, expert.limitationsJSON)
                    : IdeaDetailViewModel.separateLimitationsBlock(from: afterEntities)
                let updated = IdeaExpert(
                    id: expert.id,
                    name: expert.name,
                    role: expert.role,
                    opinion: opinion.trimmingCharacters(in: .whitespacesAndNewlines),
                    modelName: agent.model,
                    agentId: agent.id.uuidString,
                    fallbackInfo: fallbackInfo,
                    isLoading: false,
                    focus: expert.focus,
                    entitiesJSON: entitiesJSON,
                    limitationsJSON: limitationsJSON
                )
                messages[messageIndex].experts?[expertIndex] = updated
            } catch {
                messages[messageIndex].experts?[expertIndex].isLoading = false
                messages[messageIndex].experts?[expertIndex].errorMessage = error.localizedDescription
            }
            await saveIdea()
        }
    }

    /// Find the most recent completed opinion for a given expert name
    /// from a director message before the specified index (for follow-up retry context).
    private func findPreviousOpinion(expertName: String, beforeMessageIndex: Int) -> String {
        for idx in stride(from: beforeMessageIndex - 1, through: 0, by: -1) {
            guard let experts = messages[idx].experts else { continue }
            if let match = experts.first(where: {
                $0.name == expertName
                && !$0.opinion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                return match.opinion
            }
        }
        return ""
    }

    /// Run all experts in parallel for follow-up. Updates placeholders at messageIndex progressively.
    /// Non-throwing: individual expert failures are stored in expert.errorMessage instead of propagating.
    private func runExpertsInParallel(
        experts: [IdeaExpert],
        ideaBody: String,
        recentContext: String,
        question: String,
        messageIndex: Int
    ) async {
        let totalCount = experts.count
        var completed = 0
        await withTaskGroup(of: (Int, Result<IdeaExpert, Error>, Int, Int).self) { group in
            for (i, expert) in experts.enumerated() {
                let (agent, fallbackInfo) = resolveAgentForExpert(agentId: expert.agentId)
                group.addTask { [container, project, weak self] in
                    do {
                        let localI = i
                        let accumulator = StreamAccumulator()
                        let prompt = IdeaPromptBuilder.buildExpertFollowUpPrompt(
                            expertName: expert.name,
                            expertRole: expert.role,
                            initialOpinion: String(expert.opinion.prefix(500)),
                            ideaBody: ideaBody,
                            recentContext: recentContext,
                            question: question,
                            projectRootPath: project.rootPath
                        )
                        let response = try await container.cliAgentRunner.runStreaming(
                            agent: agent,
                            prompt: prompt,
                            projectId: project.id,
                            rootPath: project.rootPath
                        ) { chunk in
                            let text = accumulator.append(chunk)
                            Task { @MainActor in
                                self?.messages[messageIndex].experts?[localI].partialOpinion = text
                            }
                        }
                        let result = IdeaExpert(
                            name: expert.name,
                            role: expert.role,
                            opinion: response.trimmingCharacters(in: .whitespacesAndNewlines),
                            modelName: agent.model,
                            agentId: agent.id.uuidString,
                            fallbackInfo: fallbackInfo,
                            focus: expert.focus,
                            entitiesJSON: expert.entitiesJSON  // preserve entities from initial analysis
                        )
                        return (localI, .success(result), prompt.count, response.count)
                    } catch {
                        return (i, .failure(error), 0, 0)
                    }
                }
            }

            for await (i, result, promptLen, responseLen) in group {
                completed += 1
                if promptLen > 0 { trackUsage(promptLength: promptLen, responseLength: responseLen) }
                switch result {
                case .success(let expert):
                    messages[messageIndex].experts?[i] = expert
                case .failure(let error):
                    messages[messageIndex].experts?[i].isLoading = false
                    messages[messageIndex].experts?[i].errorMessage = error.localizedDescription
                }
                analysisStatus = lang.ideaBoard.expertsAnalyzingProgressFormat(completed, totalCount)
                await saveIdea()
            }
        }
    }

    // MARK: - Convert to Request

    func convertToRequest() async -> UUID? {
        guard !isConverting else { return nil }
        isConverting = true
        defer { isConverting = false }

        // Build task description from the full conversation thread
        var taskParts: [String] = []

        for message in messages {
            switch message.role {
            case .user:
                taskParts.append("[User]\n\(message.content)")
            case .design:
                var section = "[Design Analysis]"
                if !message.content.isEmpty {
                    section += "\n\(message.content)"
                }
                if let experts = message.experts, !experts.isEmpty {
                    for expert in experts {
                        section += "\n\n- \(expert.name) (\(expert.role)): \(expert.opinion)"
                        // Include 1:1 follow-up conversations so Design receives refined insights
                        if let followUps = expert.followUpMessages, !followUps.isEmpty {
                            for followUp in followUps {
                                let role = followUp.role == .user ? "User" : expert.name
                                section += "\n  [\(role)]: \(followUp.content)"
                            }
                        }
                    }
                }
                if let summary = message.summary, !summary.isEmpty {
                    section += "\n\nSummary: \(summary)"
                }
                taskParts.append(section)
            }
        }

        let taskDescription = taskParts.joined(separator: "\n\n---\n\n")
        let title = String(idea.title.prefix(60))

        // Carry enriched Work Graph data (synthesis + expert entities) to Design via roadmapJSON
        let roadmapJSON = buildEnrichedRoadmapJSON()

        let request = DesignSession(
            projectId: project.id,
            boardId: project.id,  // default board has same UUID as project
            title: title,
            taskDescription: taskDescription,
            roadmapJSON: roadmapJSON,
            brdJSON: brdJSON,   // BRD generated after synthesis
            designBriefJSON: designBriefJSON,  // Design Brief (BRD + synthesis decisions)
            cpsJSON: ""         // CPS generated after approach selection in Design
        )

        do {
            let created = try await container.designSessionService.createRequest(request)
            idea.status = .designing
            idea.designSessionId = created.id
            await saveIdea()
            NotificationCenter.default.post(name: .laoDesignStatsChanged, object: nil)
            NotificationCenter.default.post(name: .laoNavigateToRequest, object: created.id)

            return created.id
        } catch {
            errorMessage = lang.ideaBoard.failedToCreateRequestFormat(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Design Brief Generation (explicit trigger from View)

    /// Start Design Brief generation — called when user agrees to the recommended direction.
    /// Generates a full Brief (BRD + synthesis decisions + exploration summary).
    /// Also populates brdJSON for backward compatibility.
    func startBRDGeneration() {
        guard !isBrdGenerating else { return }
        let ideaBody = messages.first(where: { $0.role == .user })?.content ?? idea.title
        let direction = messages.last(where: { $0.role == .design })?.summary
            ?? lang.ideaBoard.recommendedDirectionDefault
        let capturedMessages = messages

        // Gather exploration stats for the Brief
        let expertCount = capturedMessages.compactMap(\.experts).flatMap({ $0 }).count
        let discussionRounds = capturedMessages.filter({ $0.role == .user }).count
        let keyEntities = extractKeyEntities(from: capturedMessages)
        let refCount = referenceImages.count

        Task { [weak self] in
            await self?.generateDesignBrief(
                ideaBody: ideaBody,
                messages: capturedMessages,
                direction: direction,
                expertCount: expertCount,
                discussionRounds: discussionRounds,
                keyEntities: keyEntities,
                referenceAnchorsCount: refCount
            )
        }
    }

    /// Retry Brief generation after failure.
    func retryBRDGeneration() {
        brdJSON = ""
        designBriefJSON = ""
        isBrdReady = false
        isBriefReady = false
        brdError = nil
        startBRDGeneration()
    }

    /// Extract entity names from synthesis graphJSON or expert entitiesJSON.
    private func extractKeyEntities(from messages: [IdeaMessage]) -> [String] {
        // Prefer synthesis entities
        if let synthMessage = messages.last(where: { $0.graphJSON != nil }),
           let graphJSON = synthMessage.graphJSON,
           let data = graphJSON.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let entities = root["entities"] as? [[String: Any]] {
            return entities.compactMap { $0["name"] as? String }
        }
        // Fallback: aggregate expert entities
        var names: [String] = []
        for message in messages {
            guard let experts = message.experts else { continue }
            for expert in experts {
                guard let json = expert.entitiesJSON,
                      let data = json.data(using: .utf8),
                      let arr = try? JSONDecoder().decode([SynthesisEntity].self, from: data) else { continue }
                names.append(contentsOf: arr.map(\.name))
            }
        }
        return Array(Set(names)).sorted()
    }

    // MARK: - BRD Display Model

    struct BRDDisplayModel {
        let problemStatement: String
        let targetUsers: [(name: String, description: String, needs: [String])]
        let businessObjectives: [String]
        let scopeInScope: [String]
        let scopeOutOfScope: [String]
        let mvpBoundary: String
        let constraints: [String]
        let assumptions: [String]
    }

    var parsedBRD: BRDDisplayModel? {
        guard !brdJSON.isEmpty,
              let data = brdJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let problemStatement = root["problemStatement"] as? String ?? ""
        let businessObjectives = root["businessObjectives"] as? [String] ?? []
        let constraints = root["constraints"] as? [String] ?? []
        let assumptions = root["assumptions"] as? [String] ?? []

        var targetUsers: [(name: String, description: String, needs: [String])] = []
        if let users = root["targetUsers"] as? [[String: Any]] {
            for user in users {
                let name = user["name"] as? String ?? ""
                let desc = user["description"] as? String ?? ""
                let needs = user["needs"] as? [String] ?? []
                targetUsers.append((name: name, description: desc, needs: needs))
            }
        }

        var scopeInScope: [String] = []
        var scopeOutOfScope: [String] = []
        var mvpBoundary = ""
        if let scope = root["scope"] as? [String: Any] {
            scopeInScope = scope["inScope"] as? [String] ?? []
            scopeOutOfScope = scope["outOfScope"] as? [String] ?? []
            mvpBoundary = scope["mvpBoundary"] as? String ?? ""
        }

        return BRDDisplayModel(
            problemStatement: problemStatement,
            targetUsers: targetUsers,
            businessObjectives: businessObjectives,
            scopeInScope: scopeInScope,
            scopeOutOfScope: scopeOutOfScope,
            mvpBoundary: mvpBoundary,
            constraints: constraints,
            assumptions: assumptions
        )
    }

    // MARK: - Design Brief Summary

    struct DesignBriefSummary {
        let title: String
        let direction: String
        let expertCount: Int
        let messageCount: Int
        let entityCount: Int
        let hasBRD: Bool
        let hasBrief: Bool
    }

    var designBriefSummary: DesignBriefSummary {
        let direction = messages.last(where: { $0.role == .design && $0.summary != nil })?.summary ?? ""
        let expertCount = Set(messages.compactMap(\.experts).flatMap { $0 }.map(\.name)).count
        let entityCount: Int = {
            guard let graphMsg = messages.last(where: { $0.graphJSON != nil }),
                  let json = graphMsg.graphJSON,
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entities = obj["entities"] as? [Any] else { return 0 }
            return entities.count
        }()

        return DesignBriefSummary(
            title: String(idea.title.prefix(60)),
            direction: direction,
            expertCount: expertCount,
            messageCount: messages.count,
            entityCount: entityCount,
            hasBRD: !brdJSON.isEmpty,
            hasBrief: !designBriefJSON.isEmpty
        )
    }

    // MARK: - Design Brief Display Model

    struct BriefDisplayModel {
        let synthesisDirection: String
        let synthesisRationale: String
        let keyDecisions: [(topic: String, chosen: String, alternatives: [String], rationale: String)]
        let brd: BRDDisplayModel?
        let executionLimitations: [(area: String, description: String, workaroundHint: String?)]
    }

    var parsedDesignBrief: BriefDisplayModel? {
        guard !designBriefJSON.isEmpty,
              let data = designBriefJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let direction = root["synthesisDirection"] as? String ?? ""
        let rationale = root["synthesisRationale"] as? String ?? ""

        var decisions: [(topic: String, chosen: String, alternatives: [String], rationale: String)] = []
        if let rawDecisions = root["keyDecisions"] as? [[String: Any]] {
            for d in rawDecisions {
                decisions.append((
                    topic: d["topic"] as? String ?? "",
                    chosen: d["chosen"] as? String ?? "",
                    alternatives: d["alternatives"] as? [String] ?? [],
                    rationale: d["rationale"] as? String ?? ""
                ))
            }
        }

        var executionLimitations: [(area: String, description: String, workaroundHint: String?)] = []
        if let ctx = root["executionContext"] as? [String: Any],
           let rawLimitations = ctx["currentLimitations"] as? [[String: Any]] {
            for lim in rawLimitations {
                executionLimitations.append((
                    area: lim["area"] as? String ?? "",
                    description: lim["description"] as? String ?? "",
                    workaroundHint: lim["workaroundHint"] as? String
                ))
            }
        }

        return BriefDisplayModel(
            synthesisDirection: direction,
            synthesisRationale: rationale,
            keyDecisions: decisions,
            brd: parsedBRD,
            executionLimitations: executionLimitations
        )
    }

    /// Generate a Design Brief (BRD + synthesis direction + key decisions + exploration summary).
    /// Falls back to legacy BRD generation if the Brief-specific parsing fails.
    private func generateDesignBrief(
        ideaBody: String,
        messages: [IdeaMessage],
        direction: String,
        expertCount: Int,
        discussionRounds: Int,
        keyEntities: [String],
        referenceAnchorsCount: Int
    ) async {
        isBrdGenerating = true
        brdError = nil

        let prompt = IdeaPromptBuilder.buildDesignBriefPrompt(
            ideaBody: ideaBody,
            messages: messages,
            synthesisDirection: direction,
            expertCount: expertCount,
            discussionRounds: discussionRounds,
            keyEntities: keyEntities,
            referenceAnchorsCount: referenceAnchorsCount,
            userProfile: userProfile
        )

        do {
            let (response, _, _) = try await runWithFallback(
                prompt: prompt,
                jsonSchema: IdeaJSONSchemas.designBrief
            ) { _ in }

            // Extract JSON using robust parser (handles markdown fences, balanced braces)
            guard let jsonStr = DesignStepResultParser.extractJSON(from: response) else {
                brdError = lang.ideaBoard.jsonNotFoundError
                isBrdGenerating = false
                return
            }

            // Parse — try direct first, then sanitized fallback
            let root: [String: Any]
            if let data = jsonStr.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                root = parsed
            } else if let sanitized = DesignStepResultParser.sanitizeJSON(jsonStr),
                      let data = sanitized.data(using: .utf8),
                      let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                root = parsed
            } else {
                brdError = lang.ideaBoard.jsonParseFailedFormat(String(jsonStr.prefix(200)))
                isBrdGenerating = false
                return
            }

            if let brief = root["brief"] as? [String: Any] {
                // Store full Brief JSON
                if let briefData = try? JSONSerialization.data(withJSONObject: brief) {
                    designBriefJSON = String(data: briefData, encoding: .utf8) ?? ""
                }
                // Extract BRD portion for backward compatibility
                if let brd = brief["brd"],
                   let brdData = try? JSONSerialization.data(withJSONObject: brd) {
                    brdJSON = String(data: brdData, encoding: .utf8) ?? ""
                }
            } else if let brd = root["brd"] {
                // Fallback: response used legacy BRD format
                if let brdData = try? JSONSerialization.data(withJSONObject: brd) {
                    brdJSON = String(data: brdData, encoding: .utf8) ?? ""
                }
            }

            isBrdGenerating = false
            isBrdReady = !brdJSON.isEmpty
            isBriefReady = !designBriefJSON.isEmpty
            if brdJSON.isEmpty {
                brdError = "Empty Brief result"
            }
        } catch {
            brdError = error.localizedDescription
            isBrdGenerating = false
        }
    }

    // MARK: - LLM Call (Design Pattern)

    private func runWithFallback(
        prompt: String,
        jsonSchema: String? = nil,
        streamHandler: @Sendable @escaping (String) -> Void
    ) async throws -> (response: String, agent: Agent, fallbackInfo: String?) {
        // Always refresh from DB so settings changes take effect immediately
        await refreshAgents()
        let agents = resolveDesignAgents()
        guard !agents.isEmpty else {
            throw IdeaError.noAgent
        }

        do {
            let result = try await runWithAgentFallback(
                agents: agents,
                runner: container.cliAgentRunner,
                prompt: prompt,
                jsonSchema: jsonSchema,
                projectId: project.id,
                rootPath: project.rootPath,
                streamHandler: streamHandler
            )

            // Track failed attempts cost
            for attempt in result.failedAttempts {
                trackUsage(promptLength: attempt.promptLength, responseLength: 0)
            }
            // Track successful call
            trackUsage(promptLength: prompt.count, responseLength: result.response.count)

            let fallbackInfo: String? = result.attemptIndex > 0
                ? "\(agents[0].model) → \(result.agent.model) (primary failed)"
                : nil
            return (result.response, result.agent, fallbackInfo)
        } catch is FallbackRunError {
            throw IdeaError.noAgent
        }
    }

    // MARK: - Agent Resolution

    private func resolveDesignAgents() -> [Agent] {
        var agents: [Agent] = []
        agents.append(contentsOf: availableAgents.filter { $0.tier == .director && $0.isEnabled })
        agents.append(contentsOf: availableAgents.filter { $0.tier == .directorFallback && $0.isEnabled })
        if agents.isEmpty {
            agents.append(Agent(
                name: "Director",
                tier: .director,
                provider: .claude,
                model: "claude-sonnet-4-5-20250514"
            ))
        }
        return agents
    }

    /// Resolve a step agent for expert calls via round-robin.
    /// Priority: enabled step agents (round-robin) → preferredModel (expert's stored model) → "sonnet"
    private func resolveStepAgent(preferredModel: String? = nil) -> Agent {
        let stepAgents = availableAgents.filter { $0.tier == .step && $0.isEnabled }
        if !stepAgents.isEmpty {
            let agent = stepAgents[stepAgentRoundRobinIndex % stepAgents.count]
            stepAgentRoundRobinIndex += 1
            return agent
        }
        // No configured step agent: use the expert's original model or a safe short-form default
        return Agent(
            name: "Expert",
            tier: .step,
            provider: .claude,
            model: preferredModel ?? "sonnet"
        )
    }

    /// Resolve the agent for a specific expert. Design-chosen agentId → first step agent → preferredModel → "sonnet".
    /// Returns (agent, fallbackInfo) — fallbackInfo is nil when the requested agent was used as-is.
    private func resolveAgentForExpert(agentId: String?, preferredModel: String? = nil) -> (Agent, String?) {
        guard let agentIdString = agentId else {
            return (resolveStepAgent(preferredModel: preferredModel), nil) // Design did not specify — normal
        }
        guard let uuid = UUID(uuidString: agentIdString) else {
            let fallback = resolveStepAgent(preferredModel: preferredModel)
            return (fallback, "Invalid agent ID → \(fallback.model)")
        }
        if let matched = availableAgents.first(where: { $0.id == uuid && $0.tier == .step && $0.isEnabled }) {
            return (matched, nil)
        }
        let fallback = resolveStepAgent(preferredModel: preferredModel)
        if let disabled = availableAgents.first(where: { $0.id == uuid }) {
            return (fallback, "\(disabled.model) → \(fallback.model) (disabled)")
        }
        return (fallback, "Requested agent not found → \(fallback.model)")
    }

    // MARK: - Response Parsing

    private func parsePlanningResponse(_ response: String) -> (content: String, experts: [(name: String, role: String, focus: String, agentId: String?)]) {
        if let jsonString = extractJSON(from: response),
           let data = jsonString.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(IdeaPlanningResponse.self, from: data) {
            return (parsed.content, parsed.experts.map { ($0.name, $0.role, $0.focus, $0.agentId) })
        }
        return (response, [])
    }

    private func extractJSON(from text: String) -> String? {
        // Try ```json ... ``` fence
        if let fenceStart = text.range(of: "```json"),
           let fenceEnd = text.range(of: "```", range: fenceStart.upperBound..<text.endIndex) {
            return String(text[fenceStart.upperBound..<fenceEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Try ``` ... ``` fence
        if let fenceStart = text.range(of: "```"),
           let fenceEnd = text.range(of: "```", range: fenceStart.upperBound..<text.endIndex) {
            return String(text[fenceStart.upperBound..<fenceEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Try raw braces
        if let braceStart = text.firstIndex(of: "{"),
           let braceEnd = text.lastIndex(of: "}") {
            return String(text[braceStart...braceEnd])
        }
        return nil
    }

    // MARK: - Entity Extraction from Expert Responses

    /// Separate a ```entities JSON block from the expert's opinion text.
    /// Returns (opinion text without the block, parsed entitiesJSON string or nil).
    nonisolated static func separateEntitiesBlock(from response: String) -> (opinion: String, entitiesJSON: String?) {
        // Look for ```entities ... ``` block
        guard let blockStart = response.range(of: "```entities", options: .caseInsensitive) else {
            return (response, nil)
        }
        let afterMarker = blockStart.upperBound
        guard let blockEnd = response.range(of: "```", range: afterMarker..<response.endIndex) else {
            return (response, nil)
        }
        let jsonCandidate = String(response[afterMarker..<blockEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate it's a JSON array of SynthesisEntity
        guard let data = jsonCandidate.data(using: .utf8),
              let _ = try? JSONDecoder().decode([SynthesisEntity].self, from: data) else {
            return (response, nil)
        }

        // Remove the block (including any trailing newline) from the opinion text
        var opinion = response
        var removeEnd = blockEnd.upperBound
        if removeEnd < opinion.endIndex, opinion[removeEnd] == "\n" {
            removeEnd = opinion.index(after: removeEnd)
        }
        opinion.removeSubrange(blockStart.lowerBound..<removeEnd)
        return (opinion, jsonCandidate)
    }

    /// Separate a ```references JSON block from the expert's opinion text.
    /// Returns (opinion text without the block, parsed referencesJSON string or nil).
    nonisolated static func separateReferencesBlock(from response: String) -> (opinion: String, referencesJSON: String?) {
        guard let blockStart = response.range(of: "```references", options: .caseInsensitive) else {
            return (response, nil)
        }
        let afterMarker = blockStart.upperBound
        guard let blockEnd = response.range(of: "```", range: afterMarker..<response.endIndex) else {
            return (response, nil)
        }
        let jsonCandidate = String(response[afterMarker..<blockEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate it's a JSON array
        guard let data = jsonCandidate.data(using: .utf8),
              let _ = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return (response, nil)
        }

        var opinion = response
        var removeEnd = blockEnd.upperBound
        if removeEnd < opinion.endIndex, opinion[removeEnd] == "\n" {
            removeEnd = opinion.index(after: removeEnd)
        }
        opinion.removeSubrange(blockStart.lowerBound..<removeEnd)
        return (opinion, jsonCandidate)
    }

    nonisolated static func separateLimitationsBlock(from response: String) -> (text: String, limitationsJSON: String?) {
        guard let blockStart = response.range(of: "```limitations", options: .caseInsensitive) else {
            return (response, nil)
        }
        let afterMarker = blockStart.upperBound
        guard let blockEnd = response.range(of: "```", range: afterMarker..<response.endIndex) else {
            return (response, nil)
        }
        let jsonCandidate = String(response[afterMarker..<blockEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonCandidate.data(using: .utf8),
              let _ = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return (response, nil)
        }

        var text = response
        var removeEnd = blockEnd.upperBound
        if removeEnd < text.endIndex, text[removeEnd] == "\n" {
            removeEnd = text.index(after: removeEnd)
        }
        text.removeSubrange(blockStart.lowerBound..<removeEnd)
        return (text, jsonCandidate)
    }

    // MARK: - Reference Image Collection

    /// JSON structure for parsing expert reference anchors.
    private struct ParsedReference: Codable {
        let category: String
        let productName: String
        let aspect: String
        let searchQuery: String?
        let searchURL: String?
        // Legacy field — ignored in new code but kept for backward compatibility
        let fileName: String?
    }

    /// Collect reference images from all expert panels and populate `referenceImages`.
    func collectReferenceImagesFromExperts() {
        var allRefs: [ReferenceImage] = []
        var seenProducts = Set<String>()
        for message in messages where message.role == .design {
            guard let experts = message.experts else { continue }
            for expert in experts {
                guard let json = expert.referencesJSON,
                      let data = json.data(using: .utf8),
                      let parsed = try? JSONDecoder().decode([ParsedReference].self, from: data) else { continue }
                for ref in parsed {
                    let key = ref.productName.lowercased()
                    guard !seenProducts.contains(key) else { continue }
                    seenProducts.insert(key)
                    let image = ReferenceImage(
                        category: ReferenceCategory(rawValue: ref.category) ?? .visual,
                        productName: ref.productName,
                        aspect: ref.aspect,
                        searchURL: ref.searchURL,
                        searchQuery: ref.searchQuery
                    )
                    allRefs.append(image)
                }
            }
        }
        referenceImages = allRefs
    }

    /// Return reference images for a specific expert by parsing their referencesJSON.
    func referencesForExpert(_ expert: IdeaExpert) -> [ReferenceImage] {
        guard let json = expert.referencesJSON,
              let data = json.data(using: .utf8),
              let parsed = try? JSONDecoder().decode([ParsedReference].self, from: data) else { return [] }
        return parsed.map { ref in
            ReferenceImage(
                category: ReferenceCategory(rawValue: ref.category) ?? .visual,
                productName: ref.productName,
                aspect: ref.aspect,
                searchURL: ref.searchURL,
                searchQuery: ref.searchQuery
            )
        }
    }

    /// Toggle a reference's inclusion in the design handoff.
    func toggleReference(_ id: UUID) {
        guard let idx = referenceImages.firstIndex(where: { $0.id == id }) else { return }
        referenceImages[idx].isConfirmed.toggle()
    }

    // MARK: - Unified Reference Phase

    /// Generate unified reference anchors from all expert opinions.
    /// Optionally accepts user feedback to iterate on previous results.
    func requestUnifiedReferences(feedback: String? = nil) {
        guard !isGeneratingUnifiedReferences else { return }

        idea.status = .referencing
        isGeneratingUnifiedReferences = true

        let ideaBody = messages.first(where: { $0.role == .user })?.content ?? idea.title
        let expertSummary = IdeaPromptBuilder.buildThreadSummary(from: messages)
        let previousRefs = messages.last(where: { $0.unifiedReferencesJSON != nil })?.unifiedReferencesJSON

        currentTask?.cancel()
        currentTask = Task { [weak self] in
            guard let self else { return }
            await refreshAgents()
            guard !Task.isCancelled else { return }

            let agent = resolveStepAgent()

            let prompt = IdeaPromptBuilder.buildUnifiedReferencePrompt(
                ideaBody: ideaBody,
                expertSummary: expertSummary,
                feedback: feedback,
                previousReferences: previousRefs,
                userProfile: userProfile
            )

            do {
                let response = try await container.cliAgentRunner.run(
                    agent: agent,
                    prompt: prompt,
                    projectId: project.id,
                    rootPath: project.rootPath
                )
                guard !Task.isCancelled else { return }
                trackUsage(promptLength: prompt.count, responseLength: response.count)

                let (explanation, refsJSON) = IdeaDetailViewModel.separateReferencesBlock(from: response)

                var refMessage = IdeaMessage(
                    role: .design,
                    content: explanation.trimmingCharacters(in: .whitespacesAndNewlines),
                    unifiedReferencesJSON: refsJSON,
                    referenceFeedback: feedback
                )
                refMessage.modelName = agent.model
                messages.append(refMessage)

                collectUnifiedReferenceImages()
                isGeneratingUnifiedReferences = false
                await saveIdea()
            } catch is CancellationError {
                isGeneratingUnifiedReferences = false
            } catch {
                isGeneratingUnifiedReferences = false
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Populate referenceImages from the latest unified references message.
    func collectUnifiedReferenceImages() {
        guard let refMessage = messages.last(where: { $0.unifiedReferencesJSON != nil }),
              let json = refMessage.unifiedReferencesJSON,
              let data = json.data(using: .utf8),
              let parsed = try? JSONDecoder().decode([ParsedReference].self, from: data) else {
            return
        }
        referenceImages = parsed.map { ref in
            ReferenceImage(
                category: ReferenceCategory(rawValue: ref.category) ?? .visual,
                productName: ref.productName,
                aspect: ref.aspect,
                searchURL: ref.searchURL,
                searchQuery: ref.searchQuery
            )
        }
    }

    /// Skip the reference phase and return to analyzed state.
    func skipReferencePhase() {
        idea.status = .analyzed
        showReferencePhaseOverlay = false
        Task { await saveIdea() }
    }

    /// Confirm references and proceed to Brief generation.
    func confirmReferencesAndProceed() {
        idea.status = .analyzed
        showReferencePhaseOverlay = false
        // referenceImages already populated with confirmed/unconfirmed state
        // Brief generation will pick them up via buildEnrichedRoadmapJSON()
    }

    // MARK: - Enriched Roadmap for Design Handoff

    /// Build enriched roadmapJSON by merging Synthesis graphJSON with expert-level entities.
    /// Falls back to aggregating all expert entities when no synthesis exists.
    private func buildEnrichedRoadmapJSON() -> String {
        struct ConfirmedReferenceData: Codable {
            let category: String
            let productName: String
            let aspect: String
            let searchURL: String?
        }

        struct GraphData: Codable {
            var entities: [SynthesisEntity]
            var relationships: [SynthesisRelationship]
            var referenceAnchors: [ConfirmedReferenceData]?
        }

        // Collect synthesis graph if available
        let synthesisJSON = messages.last(where: { $0.graphJSON != nil })?.graphJSON

        // Collect all expert entities across all messages
        var expertEntities: [SynthesisEntity] = []
        for message in messages where message.role == .design {
            guard let experts = message.experts else { continue }
            for expert in experts {
                guard let json = expert.entitiesJSON,
                      let data = json.data(using: .utf8),
                      let entities = try? JSONDecoder().decode([SynthesisEntity].self, from: data) else { continue }
                expertEntities.append(contentsOf: entities)
            }
        }

        // Collect confirmed reference anchors from referenceImages
        let confirmedRefs: [ConfirmedReferenceData] = referenceImages
            .filter { $0.isConfirmed }
            .map { ConfirmedReferenceData(
                category: $0.category.rawValue,
                productName: $0.productName,
                aspect: $0.aspect,
                searchURL: $0.searchURL
            )}
        let refsToInclude: [ConfirmedReferenceData]? = confirmedRefs.isEmpty ? nil : confirmedRefs

        // If synthesis exists, merge expert entities as supplementary
        if let synthesisJSON, let synthesisData = synthesisJSON.data(using: .utf8) {
            guard var graph = try? JSONDecoder().decode(GraphData.self, from: synthesisData) else {
                return synthesisJSON
            }
            // Add expert entities not already in synthesis (by name, case-insensitive)
            let existingNames = Set(graph.entities.map { $0.name.lowercased() })
            let supplementary = expertEntities.filter { !existingNames.contains($0.name.lowercased()) }
            graph.entities.append(contentsOf: supplementary)
            // Inject confirmed reference anchors
            if let refs = refsToInclude {
                graph.referenceAnchors = refs
            }
            if let data = try? JSONEncoder().encode(graph) {
                return String(data: data, encoding: .utf8) ?? synthesisJSON
            }
            return synthesisJSON
        }

        // No synthesis — aggregate expert entities (deduplicate by name)
        guard !expertEntities.isEmpty || refsToInclude != nil else { return "[]" }
        var seen = Set<String>()
        var unique: [SynthesisEntity] = []
        for entity in expertEntities {
            let key = entity.name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(entity)
        }
        let graph = GraphData(entities: unique, relationships: [], referenceAnchors: refsToInclude)
        if let data = try? JSONEncoder().encode(graph) {
            return String(data: data, encoding: .utf8) ?? "[]"
        }
        return "[]"
    }

    private enum IdeaError: LocalizedError {
        case noAgent
        var errorDescription: String? {
            "No AI agent is configured. Go to Settings > Agents to set up a provider."
        }
    }
}


