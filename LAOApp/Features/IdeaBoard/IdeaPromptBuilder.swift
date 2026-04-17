import Foundation
import LAODomain

/// Builds prompts for the Design AI to analyze ideas with expert panels.
enum IdeaPromptBuilder {

    /// Prompt for the Design to assign expert panelists who will each propose a distinct product direction.
    /// - Called by: `IdeaBoardViewModel.analyzeIdea()`
    /// - Output: JSON with `content` (intro) + `experts` array (name, role, focus, agentId)
    static func buildInitialAnalysisPrompt(ideaBody: String, agents: [Agent], userProfile: UserProfile = UserProfile()) -> String {
        """
        \(PromptFragments.designOfficeIdentity)\(PromptFragments.userContext(userProfile))

        Your job is to assemble a panel of 3-5 experts who will each \
        propose a DIFFERENT product direction for the client's idea.

        Do NOT write the direction proposals yourself — only assign who should propose and what angle to take.
        Each expert must champion a meaningfully different approach (e.g. MVP vs full-scale, \
        B2B vs B2C, API-first vs UX-first, etc.).

        ## Panel Quality Standards
        - Each expert must champion a fundamentally different approach — not variations of the same idea.
        - Experts should surface what the client hasn't considered: hidden risks, market assumptions, technical constraints.
        - Each direction must be concrete enough for the client to compare: what gets built, who uses it, what's different.

        ## Idea
        \(ideaBody)

        ## Available Step Agents
        \(Agent.promptDescription(for: agents))

        You MUST assign an agentId to every expert from the Available Step Agents above.
        Match agent expertise to each expert's focus area.

        ## Important
        - \(PromptFragments.respondInSameLanguage(as: "the idea above"))
        - Respond with ONLY valid JSON, no markdown fences, no extra text.
        - Use the exact format below:

        {
          "content": "Brief intro: the idea in one line, and a note that each expert will propose a different direction",
          "experts": [
            {
              "name": "Expert Display Name",
              "role": "Their specialty/role",
              "focus": "The specific product direction angle this expert should champion — be concrete",
              "agentId": "agent-uuid-string (REQUIRED, from Available Step Agents)"
            }
          ]
        }
        """
    }

    /// Prompt for a single expert to propose a concrete product direction (run as Step Agent).
    /// - Output: Plain text proposal (2-4 paragraphs) + optional ```entities``` JSON block
    static func buildExpertInitialAnalysisPrompt(
        expertName: String,
        expertRole: String,
        focus: String,
        ideaBody: String,
        projectRootPath: String = "",
        discussionContext: String = "",
        userProfile: UserProfile = UserProfile()
    ) -> String {
        let discussionSection = discussionContext.isEmpty ? "" : """

        ## Previous Discussion (from earlier expert panel)
        \(discussionContext)

        Build on this discussion — do NOT repeat what was already said. Offer fresh insights from your angle.

        """
        return """
        You are \(expertName), a \(expertRole). You are part of an expert panel where each member \
        proposes a distinct product direction for the client's idea.\(PromptFragments.userContext(userProfile))

        ## Idea
        \(ideaBody)
        \(discussionSection)
        ## Your Direction Angle
        \(focus)

        ## Task
        Propose a specific, concrete product direction from your angle. Be decisive — recommend \
        HOW to build this product. Cover: the core approach, key screens or flows, and why this \
        direction makes sense. Write 2-4 paragraphs.

        Start with a clear recommendation: "I recommend building this as [X] because..."

        ## Your Standards as a Design Office Expert
        - Don't just list pros and cons — recommend a specific direction and defend it.
        - Surface risks and assumptions the client may not have considered.
        - Be concrete: name the screens, the data, the core flow — not abstract concepts.

        \(projectFilesSection(rootPath: projectRootPath))
        \(PromptFragments.urlFetchingInstructions)

        \(PromptFragments.entityExtractionBlock)

        \(PromptFragments.limitationExtractionBlock)

        ## Important
        - \(PromptFragments.respondInSameLanguage(as: "the idea above"))
        - Write your proposal as plain text (2-4 paragraphs), then append the entity block, then the limitations block at the very end.
        - Be opinionated and concrete — not just pros/cons, but a real direction proposal.
        """
    }

    // MARK: - Follow-up: Individual Expert Prompt (for parallel Step Agent calls)

    /// Build a prompt for a single expert to answer the client's follow-up question.
    /// Each expert runs as a separate Step Agent call in parallel.
    /// - Output: Plain text answer (1-3 paragraphs)
    static func buildExpertFollowUpPrompt(
        expertName: String,
        expertRole: String,
        initialOpinion: String,
        ideaBody: String,
        recentContext: String,
        question: String,
        projectRootPath: String = ""
    ) -> String {
        """
        You are \(expertName), a \(expertRole) at the LAO Design Office. \
        You are part of an expert panel analyzing an idea.

        ## Original Idea
        \(ideaBody)

        ## Your Previous Analysis
        \(initialOpinion)

        \(recentContext.isEmpty ? "" : "## Recent Discussion\n\(recentContext)\n")
        ## Client's New Question
        \(question)

        ## Task
        Answer the client's message from your perspective as \(expertRole). Be concise but insightful (1-3 paragraphs). Focus on actionable advice.

        \(projectFilesSection(rootPath: projectRootPath))
        \(PromptFragments.urlFetchingInstructions)

        ## Important
        - \(PromptFragments.respondInSameLanguage(as: "the client's message"))
        - Respond with ONLY plain text. No JSON, no markdown fences.
        - Just write your expert opinion directly.
        """
    }

    // MARK: - Reference Request Prompt

    /// Build a prompt asking a specific expert to provide reference anchors for their proposal.
    /// Triggered by user clicking "레퍼런스 요청" button under an expert card.
    /// - Output: Plain text explanation + ```references JSON block + downloaded images
    static func buildReferenceRequestPrompt(
        expertName: String,
        expertRole: String,
        initialOpinion: String,
        ideaBody: String
    ) -> String {
        """
        You are \(expertName), a \(expertRole). You previously proposed the following direction:

        ## Your Previous Proposal
        \(initialOpinion)

        ## Task
        The client wants to see reference anchors for your proposal.
        Name existing products, apps, or visual styles whose design should guide this project.

        For each reference:
        1. Describe the SPECIFIC visual or experiential characteristics to adopt.
        2. Provide a Google Images search URL so the client can see representative screenshots.

        After your explanation, include a structured block at the end:

        ```references
        [
          {
            "category": "visual",
            "productName": "Existing Product Name",
            "aspect": "Concrete visual characteristics: colors, shapes, layout, rendering style, proportions",
            "searchQuery": "Product Name screenshot keyword",
            "searchURL": "https://www.google.com/search?tbm=isch&q=Product+Name+screenshot+keyword"
          }
        ]
        ```

        ## Rules
        - Include 2-4 references across visual, experience, and implementation categories.
        - category: "visual" (look & feel), "experience" (UX patterns, interactions), "implementation" (technical approach)
        - The aspect field must describe concrete, observable characteristics — not abstract adjectives.
        - The searchURL must be a valid Google Images search URL with relevant keywords URL-encoded.
        - First briefly explain (1-2 sentences) why you chose each reference, then the structured block.
        - \(PromptFragments.respondInSameLanguage(as: "the proposal above"))
        """
    }

    // MARK: - Unified Reference Prompt (Reference Phase)

    /// Build a prompt to generate unified reference anchors from ALL expert opinions.
    /// Aggregates every expert direction into one coherent set of design anchors.
    /// - Parameters:
    ///   - feedback: Optional user feedback from a previous iteration
    ///   - previousReferences: Optional JSON string of previously generated references for iteration
    static func buildUnifiedReferencePrompt(
        ideaBody: String,
        expertSummary: String,
        feedback: String? = nil,
        previousReferences: String? = nil,
        userProfile: UserProfile = UserProfile()
    ) -> String {
        let iterationSection: String
        if let feedback, let previousReferences {
            iterationSection = """

            ## Previous References
            \(previousReferences)

            ## Client Feedback
            The client reviewed the references above and gave this feedback:
            "\(feedback)"

            Adjust the reference set based on this feedback. You may add, remove, or replace references.
            Keep references that were NOT mentioned in the feedback unchanged.

            """
        } else {
            iterationSection = ""
        }

        return """
        \(PromptFragments.designOfficeIdentity)\(PromptFragments.userContext(userProfile))

        You are producing **Reference Anchors** — concrete examples from existing products \
        that establish a shared visual and experiential baseline between the design team and the client.

        References are NOT mere illustrations. They are **alignment anchors**: they ensure everyone \
        pictures the same thing when discussing a direction. Without them, "minimal design" can mean \
        Apple Notes to one person and Notion to another.

        ## Original Idea
        \(ideaBody)

        ## Expert Panel Summary
        \(expertSummary)
        \(iterationSection)
        ## Task
        Synthesize the expert directions above and produce 5-8 unified reference anchors. \
        Each reference should name a specific, well-known product or design and describe \
        the concrete aspect to adopt.

        Distribute references across three categories:
        - **visual** (2-3): look & feel, color palette, typography, layout, shape language
        - **experience** (2-3): UX patterns, interaction models, user flows, navigation
        - **implementation** (1-2): technical architecture, API patterns, data modeling approaches

        After a brief explanation (2-3 sentences per category), include this structured block:

        ```references
        [
          {
            "category": "visual",
            "productName": "Existing Product Name",
            "aspect": "Concrete observable characteristics to adopt — not abstract adjectives",
            "searchQuery": "Product Name UI screenshot keyword",
            "searchURL": "https://www.google.com/search?tbm=isch&q=Product+Name+UI+screenshot+keyword"
          }
        ]
        ```

        ## Rules
        - References must bridge multiple expert directions, not just serve one.
        - The aspect field must describe concrete, observable characteristics — not "clean" or "modern".
        - Each searchURL must be a valid Google Images URL with relevant keywords URL-encoded.
        - \(PromptFragments.respondInSameLanguage(as: "the idea above"))
        """
    }

    /// Build a compact recent context string for expert follow-ups.
    /// Uses a sliding window: last Design summary + last 4 messages.
    static func buildRecentContext(from messages: [IdeaMessage]) -> String {
        var lines: [String] = []

        let lastSummary = messages.last(where: { $0.role == .design && $0.summary != nil })?.summary
        let recentMessages = Array(messages.suffix(4))

        if let summary = lastSummary, !recentMessages.isEmpty {
            let recentIds = Set(recentMessages.map(\.id))
            let summaryFromOlder = messages.first(where: { $0.summary == summary && !recentIds.contains($0.id) }) != nil
            if summaryFromOlder {
                lines.append("[Previous analysis summary]: \(summary)")
                lines.append("")
            }
        }

        for message in recentMessages {
            appendMessageLines(message, to: &lines)
        }

        return lines.joined(separator: "\n")
    }

    private static func appendMessageLines(_ message: IdeaMessage, to lines: inout [String]) {
        switch message.role {
        case .user:
            lines.append("[Client]: \(message.content)")
        case .design:
            if let experts = message.experts, !experts.isEmpty {
                for expert in experts {
                    lines.append("  [\(expert.name)]: \(expert.opinion.prefix(150))...")
                }
            } else if !message.content.isEmpty {
                lines.append("[Design]: \(message.content.prefix(200))...")
            }
        }
    }

    // MARK: - Single Expert Conversation (카드별 개별 대화)

    /// Prompt for a 1:1 follow-up conversation with a specific expert inside their card.
    /// Includes the full per-expert conversation history (sliding window of last 8 messages).
    /// - Output: Plain text answer
    static func buildSingleExpertConversationPrompt(
        expertName: String,
        expertRole: String,
        focus: String,
        initialOpinion: String,
        ideaBody: String,
        followUpHistory: [IdeaExpertFollowUp],
        currentQuestion: String,
        projectRootPath: String = ""
    ) -> String {
        var parts: [String] = []

        parts.append("You are \(expertName), a \(expertRole) at the LAO Design Office, specializing in \(focus). You proposed a product direction for the client's idea.")
        parts.append("## Original Idea\n\(ideaBody)")
        parts.append("## Your Recommended Direction\n\(initialOpinion)")

        if !followUpHistory.isEmpty {
            // Sliding window: keep only the most recent exchanges to bound prompt size
            let recentHistory = followUpHistory.suffix(8)
            let lines = recentHistory.map { msg -> String in
                switch msg.role {
                case .user: return "[Client]: \(msg.content)"
                case .expert: return "[\(expertName)]: \(msg.content)"
                }
            }
            let prefix = followUpHistory.count > 8 ? "(earlier \(followUpHistory.count - 8) messages omitted)\n" : ""
            parts.append("## Your Conversation with the Client So Far\n\(prefix)\(lines.joined(separator: "\n"))")
        }

        parts.append("## Client's New Question\n\(currentQuestion)")

        var taskSection = """
            ## Task
            Answer the client's message directly as \(expertName). Stay consistent with your recommended \
            direction. Be concise and actionable (1-3 paragraphs).

            \(projectFilesSection(rootPath: projectRootPath))
            \(PromptFragments.urlFetchingInstructions)

            ## Important
            - \(PromptFragments.respondInSameLanguage(as: "the client's message"))
            - Respond with ONLY plain text. No JSON, no markdown fences.
            - Do not repeat your entire previous analysis — just answer the question.
            """
        parts.append(taskSection)

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Project Files Context

    /// Returns a prompt section instructing the agent to explore project files via Bash.
    /// Returns empty string when rootPath is empty (no project folder set).
    private static func projectFilesSection(rootPath: String) -> String {
        guard !rootPath.isEmpty else { return "" }
        return """
            ## Project Files
            Project root: \(rootPath)
            You have Bash tool access and can explore project files to enrich your analysis.
            - Use `ls`, `find`, `cat`, `grep` to locate and read relevant files
            - Start with: README.md, package.json, requirements.txt, or main entry points
            - Explore ONLY files relevant to the idea — do not recursively scan everything
            - If you find relevant code, reference it specifically in your response

            """
    }

    // MARK: - Panel Rearrangement (패널 재구성)

    /// Prompt for the Design to assign a NEW expert panel, given the existing panel was unsatisfying.
    /// - Output: JSON with `content` (summary + rationale) + `experts` array
    static func buildPanelRearrangementPrompt(
        ideaBody: String,
        existingExperts: [String],   // ["이름 (역할)"]
        reason: String,
        agents: [Agent],
        discussionContext: String = ""
    ) -> String {
        let existingList = existingExperts.isEmpty
            ? "None"
            : existingExperts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let discussionSection = discussionContext.isEmpty ? "" : """

        ## Previous Discussion (what was discussed so far)
        \(discussionContext)

        Take the previous discussion into account when assigning new expert angles.
        """
        return """
        \(PromptFragments.designOfficeIdentity)

        The client wants a DIFFERENT expert panel for their idea.

        ## Idea
        \(ideaBody)

        ## Previous Expert Panel (do NOT repeat these exact roles)
        \(existingList)
        \(discussionSection)

        ## Reason for Rearrangement
        \(reason.isEmpty ? "The client wants different perspectives." : reason)

        ## Available Step Agents
        \(Agent.promptDescription(for: agents))

        Assign a NEW panel of 3-5 experts with meaningfully different angles from the previous panel.

        ## Important
        - \(PromptFragments.respondInSameLanguage(as: "the idea above"))
        - Respond with ONLY valid JSON, no markdown fences, no extra text.
        - The "content" field MUST include a concise summary of the previous discussion's key insights \
        and conclusions, then explain why this new panel offers fresh perspectives. \
        This summary will be passed to the new experts as their briefing.
        - Use the exact same format as before:

        {
          "content": "Summary of previous discussion insights + why this new panel brings fresh perspectives",
          "experts": [
            {
              "name": "Expert Display Name",
              "role": "Their specialty/role",
              "focus": "The specific product direction angle — different from the previous panel",
              "agentId": "agent-uuid-string (optional)"
            }
          ]
        }
        """
    }

    // MARK: - Design Synthesis (수렴)

    /// Build a summary of entities extracted by each expert for inclusion in synthesis prompt.
    /// Returns empty string if no expert has extracted entities.
    private static func buildExpertEntitiesSummary(from messages: [IdeaMessage]) -> String {
        var sections: [String] = []
        for message in messages where message.role == .design {
            guard let experts = message.experts else { continue }
            for expert in experts {
                guard let json = expert.entitiesJSON,
                      let data = json.data(using: .utf8),
                      let entities = try? JSONDecoder().decode([SynthesisEntity].self, from: data),
                      !entities.isEmpty else { continue }
                let lines = entities.map { "- \($0.name) (\($0.type)): \($0.description)" }
                sections.append("[\(expert.name) — \(expert.role)]:\n\(lines.joined(separator: "\n"))")
            }
        }
        guard !sections.isEmpty else { return "" }
        return """

        ## Pre-extracted Entities by Expert
        Each expert identified the following entities in their proposals. \
        Use these as structured input — adopt, merge, or discard as appropriate. \
        When possible, indicate which entities you kept and from which expert.

        \(sections.joined(separator: "\n\n"))
        """
    }

    /// JSON structure for parsing expert reference anchors.
    private struct ParsedReference: Codable {
        let category: String
        let productName: String
        let aspect: String
        let searchQuery: String?
    }

    /// Build a summary of reference anchors extracted by each expert for inclusion in synthesis prompt.
    private static func buildExpertReferencesSummary(from messages: [IdeaMessage]) -> String {
        var lines: [String] = []
        for message in messages where message.role == .design {
            guard let experts = message.experts else { continue }
            for expert in experts {
                guard let json = expert.referencesJSON,
                      let data = json.data(using: .utf8),
                      let refs = try? JSONDecoder().decode([ParsedReference].self, from: data),
                      !refs.isEmpty else { continue }
                for ref in refs {
                    lines.append("- \(ref.productName) (\(ref.category)): \(ref.aspect)")
                }
            }
        }
        guard !lines.isEmpty else { return "" }
        return """

        ## Reference Anchors from Experts
        \(lines.joined(separator: "\n"))

        Consolidate these into the referenceAnchors field. Keep only confirmed/relevant ones.
        """
    }

    /// Build a compact thread summary for the synthesis prompt.
    /// Includes expert opinions (up to 800 chars) and any 1:1 follow-up conversations.
    static func buildThreadSummary(from messages: [IdeaMessage]) -> String {
        var lines: [String] = []
        for message in messages {
            switch message.role {
            case .user:
                lines.append("[Client]: \(message.content)")
            case .design:
                if let experts = message.experts, !experts.isEmpty {
                    for expert in experts where !expert.opinion.isEmpty && expert.errorMessage == nil {
                        var expertBlock = "[\(expert.name) — \(expert.role)]: \(expert.opinion.prefix(800))"
                        // Include 1:1 follow-up conversations so synthesis captures refined insights
                        if let followUps = expert.followUpMessages, !followUps.isEmpty {
                            let followUpLines = followUps.map { msg in
                                let role = msg.role == .user ? "Client" : expert.name
                                return "  [\(role)]: \(msg.content.prefix(400))"
                            }
                            expertBlock += "\n  --- Follow-up ---\n" + followUpLines.joined(separator: "\n")
                        }
                        lines.append(expertBlock)
                    }
                } else if !message.content.isEmpty {
                    lines.append("[Design]: \(message.content.prefix(300))")
                }
            }
        }
        return lines.joined(separator: "\n\n")
    }

    // MARK: - Design Brief (structured exploration output)

    /// Produces a Design Brief — the "what and why" contract before design begins.
    /// Includes the full BRD plus synthesis direction, key decisions, and exploration summary.
    static func buildDesignBriefPrompt(
        ideaBody: String,
        messages: [IdeaMessage],
        synthesisDirection: String,
        expertCount: Int,
        discussionRounds: Int,
        keyEntities: [String],
        referenceAnchorsCount: Int,
        userProfile: UserProfile = UserProfile()
    ) -> String {
        let thread = buildThreadSummary(from: messages)
        let entitiesList = keyEntities.isEmpty ? "None extracted" : keyEntities.joined(separator: ", ")
        return """
        \(PromptFragments.designOfficeIdentity)\(PromptFragments.userContext(userProfile))

        You are producing a **Design Brief** — the formal contract between exploration and design.
        This document captures what was explored, what was decided, and what will be designed.

        ## Original Idea
        \(ideaBody)

        ## Discussion Summary
        \(thread)

        ## Chosen Direction
        \(synthesisDirection)

        ## Exploration Stats
        - Expert panelists: \(expertCount)
        - Discussion rounds: \(discussionRounds)
        - Key entities identified: \(entitiesList)
        - Reference anchors: \(referenceAnchorsCount)

        ## Your Task
        1. **BRD**: Formalize the problem, target users, objectives, scope, constraints, \
        and non-functional requirements.
        2. **Key Decisions**: Extract every significant decision made during exploration — \
        what was chosen, what alternatives were considered, and why.
        3. **Synthesis**: Capture the chosen direction and its rationale.
        4. **Execution Context**: Aggregate AI execution limitations identified by the expert panel. \
        These are current conditions of the AI execution environment, not permanent impossibilities. \
        Consolidate duplicates and include only project-relevant items. \
        If no limitations were identified, return an empty array.

        \(PromptFragments.respondInSameLanguage(as: "the idea above"))
        Respond with ONLY valid JSON, no markdown fences, no extra text:

        {
          "brief": {
            "synthesisDirection": "One-sentence description of the chosen direction",
            "synthesisRationale": "Why this direction was chosen over alternatives",
            "keyDecisions": [
              {
                "topic": "Decision topic (e.g. Target platform, Auth strategy)",
                "chosen": "What was decided",
                "alternatives": ["Alternative 1", "Alternative 2"],
                "rationale": "Why this choice was made"
              }
            ],
            "brd": {
              "problemStatement": "Clear statement of the problem to solve",
              "targetUsers": [{ "name": "Persona name", "description": "Who they are", "needs": ["Need 1"] }],
              "businessObjectives": ["Objective 1"],
              "successMetrics": [{ "metric": "Metric name", "target": "Target value", "measurement": "How to measure" }],
              "scope": { "inScope": ["Feature 1"], "outOfScope": ["Feature X"], "mvpBoundary": "What defines MVP" },
              "constraints": ["Constraint 1"],
              "assumptions": ["Assumption 1"],
              "nonFunctionalRequirements": { "performance": [], "security": [], "accessibility": [], "scalability": [] }
            },
            "executionContext": {
              "currentLimitations": [
                {
                  "area": "Area name (e.g. Asset Creation, External APIs, Payment Processing)",
                  "description": "What the AI cannot do — framed as a current condition, not an impossibility",
                  "workaroundHint": "Optional: how the design could work around this"
                }
              ]
            }
          }
        }
        """
    }

    // MARK: - BRD/CPS Document Synthesis (legacy — used in proceedWithExport fallback)

    /// Separate prompt for generating BRD and CPS documents from the discussion.
    /// Called after the main synthesis is complete, during design conversion.
    static func buildBRDCPSSynthesisPrompt(
        ideaBody: String,
        messages: [IdeaMessage],
        synthesisDirection: String
    ) -> String {
        let thread = buildThreadSummary(from: messages)
        return """
        \(PromptFragments.designOfficeIdentity)

        Based on a completed product exploration discussion, produce two structured \
        analysis documents.

        ## Original Idea
        \(ideaBody)

        ## Discussion Summary
        \(thread)

        ## Chosen Direction
        \(synthesisDirection)

        ## Your Task
        Produce two documents:
        1. **BRD** (Business Requirements Document): Formalize the problem, target users, business objectives, \
        scope, constraints, and non-functional requirements that emerged from the discussion.
        2. **CPS** (Context-Problem-Solution): Structure the market/user/technical context, the core problem, \
        the recommended solution, and alternatives considered.

        \(PromptFragments.respondInSameLanguage(as: "the idea above"))
        Respond with ONLY valid JSON, no markdown fences, no extra text:

        {
          "brd": {
            "problemStatement": "Clear statement of the problem to solve",
            "targetUsers": [{ "name": "Persona name", "description": "Who they are", "needs": ["Need 1"] }],
            "businessObjectives": ["Objective 1", "Objective 2"],
            "successMetrics": [{ "metric": "Metric name", "target": "Target value", "measurement": "How to measure" }],
            "scope": { "inScope": ["Feature 1"], "outOfScope": ["Feature X"], "mvpBoundary": "What defines MVP" },
            "constraints": ["Constraint 1"],
            "assumptions": ["Assumption 1"],
            "nonFunctionalRequirements": { "performance": [], "security": [], "accessibility": [], "scalability": [] }
          },
          "cps": {
            "context": { "background": "...", "marketContext": "...", "userContext": "...", "technicalContext": "..." },
            "problem": { "coreProblem": "...", "subProblems": ["..."], "impactIfUnsolved": "..." },
            "solution": { "direction": "...", "keyComponents": ["..."], "differentiation": "..." },
            "alternativesConsidered": [{ "name": "Expert direction name", "summary": "...", "pros": ["..."], "cons": ["..."], "whyNotChosen": "..." }],
            "openQuestions": ["Unresolved question 1"]
          }
        }
        """
    }

}

// MARK: - JSON Schemas for Idea Workflow

/// JSON Schema definitions for structured LLM output in the Idea workflow.
/// Mirrors the pattern used by `DesignJSONSchemas` in the Design workflow.
enum IdeaJSONSchemas {
    /// Schema for Design Brief output — matches `buildDesignBriefPrompt()` template.
    /// Enforced via CLI `--json-schema` (Claude) or `--output-schema` (Codex).
    static let designBrief = """
    {"type":"object","properties":{"brief":{"type":"object","properties":{"synthesisDirection":{"type":"string"},"synthesisRationale":{"type":"string"},"keyDecisions":{"type":"array","items":{"type":"object","properties":{"topic":{"type":"string"},"chosen":{"type":"string"},"alternatives":{"type":"array","items":{"type":"string"}},"rationale":{"type":"string"}},"required":["topic","chosen","alternatives","rationale"],"additionalProperties":false}},"brd":{"type":"object","properties":{"problemStatement":{"type":"string"},"targetUsers":{"type":"array","items":{"type":"object","properties":{"name":{"type":"string"},"description":{"type":"string"},"needs":{"type":"array","items":{"type":"string"}}},"required":["name","description","needs"],"additionalProperties":false}},"businessObjectives":{"type":"array","items":{"type":"string"}},"successMetrics":{"type":"array","items":{"type":"object","properties":{"metric":{"type":"string"},"target":{"type":"string"},"measurement":{"type":"string"}},"required":["metric","target","measurement"],"additionalProperties":false}},"scope":{"type":"object","properties":{"inScope":{"type":"array","items":{"type":"string"}},"outOfScope":{"type":"array","items":{"type":"string"}},"mvpBoundary":{"type":"string"}},"required":["inScope","outOfScope","mvpBoundary"],"additionalProperties":false},"constraints":{"type":"array","items":{"type":"string"}},"assumptions":{"type":"array","items":{"type":"string"}},"nonFunctionalRequirements":{"type":"object","properties":{"performance":{"type":"array","items":{"type":"string"}},"security":{"type":"array","items":{"type":"string"}},"accessibility":{"type":"array","items":{"type":"string"}},"scalability":{"type":"array","items":{"type":"string"}}},"required":["performance","security","accessibility","scalability"],"additionalProperties":false}},"required":["problemStatement","targetUsers","businessObjectives","successMetrics","scope","constraints","assumptions","nonFunctionalRequirements"],"additionalProperties":false},"executionContext":{"type":"object","properties":{"currentLimitations":{"type":"array","items":{"type":"object","properties":{"area":{"type":"string"},"description":{"type":"string"},"workaroundHint":{"type":"string"}},"required":["area","description","workaroundHint"],"additionalProperties":false}}},"required":["currentLimitations"],"additionalProperties":false}},"required":["synthesisDirection","synthesisRationale","keyDecisions","brd","executionContext"],"additionalProperties":false}},"required":["brief"],"additionalProperties":false}
    """
}
