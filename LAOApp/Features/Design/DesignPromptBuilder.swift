import Foundation
import LAODomain

/// Decoded shape for IdeaBoard synthesis graph data carried via roadmapJSON.
private struct PreExtractedGraph: Codable {
    struct Entity: Codable { let name: String; let type: String; let description: String }
    struct Relationship: Codable { let sourceName: String; let targetName: String; let relationType: String }
    struct ReferenceAnchor: Codable { let category: String; let productName: String; let aspect: String; let searchURL: String? }
    let entities: [Entity]
    let relationships: [Relationship]
    let referenceAnchors: [ReferenceAnchor]?
}

/// Centralizes all prompt-building logic for the Design workflow.
/// Each method returns a fully-formed prompt string ready for LLM consumption.
struct DesignPromptBuilder {
    let workflow: DesignWorkflow?
    let taskInput: String
    let availableAgents: [Agent]
    let project: Project
    let requestId: UUID?
    let ideaId: UUID?
    /// Design Brief JSON from idea exploration — primary structured input for analysis
    let designBriefJSON: String?
    /// User profile for client context injection into top-level prompts
    let userProfile: UserProfile

    // MARK: - Helpers

    private var enabledStepAgents: [Agent] {
        availableAgents.filter { $0.tier == .step && $0.isEnabled }
    }

    /// Returns a project context block for injection into all prompts.
    /// Includes project identity, description, and tech stack when available.
    /// Prefers workflow-level techStack (from analysis); falls back to project-level techStack (from settings).
    private func projectContextBlock() -> String {
        var lines: [String] = ["## Project Context"]
        lines.append("Project: \(project.name)")
        if !project.description.isEmpty {
            lines.append("Description: \(project.description)")
        }
        if !project.rootPath.isEmpty {
            lines.append("Root Path: \(project.rootPath)")
        }
        if let wf = workflow, let spec = wf.projectSpec {
            lines.append("Type: \(spec.type)")
        }

        // Tech stack: prefer workflow-inferred stack, fall back to project-level settings
        let techStack: [String: String] = {
            if let wfStack = workflow?.projectSpec?.techStack, !wfStack.isEmpty {
                return wfStack
            }
            let projectStack = project.techStack
            return projectStack.isEmpty ? [:] : projectStack
        }()
        if !techStack.isEmpty {
            lines.append("Tech Stack: \(techStack.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    private func referenceContextBlock() -> String {
        guard let refs = workflow?.referenceAnchors, !refs.isEmpty else { return "" }
        var lines: [String] = []
        lines.append("")
        lines.append("## Reference Anchors")
        lines.append("These existing products define the target visual and experiential direction:")
        lines.append("")
        for ref in refs {
            lines.append("- **\(ref.productName)**: \(ref.aspect)")
        }
        lines.append("")
        lines.append("Ground visual decisions in these references. Translate into visual_spec:")
        lines.append("1. Color palette — dominant colors as hex")
        lines.append("2. Shape language — rounded? angular? geometric?")
        lines.append("3. Rendering style — proportions, detail level, technique")
        lines.append("4. UI layout — spacing, typography, component arrangement")
        lines.append("5. Visual feedback — interaction communication patterns")
        lines.append("")
        lines.append("Do NOT use emoji as visual elements.")
        lines.append("Specify rendering as: CSS art, SVG, Canvas, or framework components.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Agent Assignment Prompt

    /// Builds a prompt asking the Design to assign the best step agent to each item.
    /// - Called by: `DesignWorkflowViewModel.assignAgents()`
    /// - Output: JSON array of `{itemId, agentId}` assignments
    func buildAgentAssignmentPrompt(
        items: [(sectionType: String, itemId: UUID, itemName: String, briefDescription: String?)],
        stepAgents: [Agent]
    ) -> String {
        let agentLines = Agent.promptDescription(for: stepAgents, snippetLength: 200)

        let itemLines = items.map { item in
            let desc = item.briefDescription.map { " — \($0)" } ?? ""
            return "- id: \"\(item.itemId.uuidString)\", section: \(item.sectionType), name: \"\(item.itemName)\"\(desc)"
        }.joined(separator: "\n")

        return """
        Your task is to assign the most suitable step agent \
        to each deliverable item based on the item's nature and the agent's expertise.

        ## Available Step Agents
        \(agentLines)

        ## Items to Elaborate
        \(itemLines)

        ## Assignment Guidelines
        - Match agent expertise to item type:
          - screen-spec / user-flow items → prefer agents with UI/UX, frontend, or design expertise
          - data-model / api-spec items → prefer agents with backend, data, or API expertise
        - Consider the agent's instruction/system prompt to judge expertise.
        - If agents have similar capabilities, distribute items evenly across agents for balanced load.
        - Every item MUST be assigned exactly one agent.

        ## Response Schema (TypeScript — your JSON must conform exactly to this)
        ```typescript
        type AgentAssignment = { itemId: string; agentId: string }[];
        ```

        ## Response Format
        Return ONLY a JSON array, no other text:
        ```json
        [
          {"itemId": "uuid-of-item", "agentId": "uuid-of-agent"}
        ]
        ```
        """
    }

    // MARK: - Analysis Prompt (auto-analysis + skeleton generation)

    /// Builds a prompt for auto-analysis of the work instruction.
    /// - Called by: `DesignWorkflowViewModel.runAutoAnalysis()`
    /// - Output: Text message + `[ANALYSIS_RESULT]` JSON block with approaches, deliverables, uncertainties
    func buildAnalysisPrompt(
        preExtractedGraph: String? = nil,
        reanalyzeFeedback: String? = nil,
        previousAnalysisSummary: String? = nil
    ) -> String {
        let brief = briefContextBlock()
        let hasBrief = !brief.isEmpty

        return """
        \(PromptFragments.designOfficeIdentity)\(PromptFragments.userContext(userProfile))

        Analyze the \(hasBrief ? "Design Brief" : "work instruction") below using a structured reasoning process.

        \(projectContextBlock())

        \(hasBrief ? brief : "")\(hasBrief ? "\n\n## Original Discussion (Reference)\nThe full exploration thread is provided for additional context. The Brief above is the primary input.\n\(taskInput)" : "## Work Instruction\n\(taskInput)")\(analysisGraphHint(preExtractedGraph))\(reanalysisContext(feedback: reanalyzeFeedback, previousSummary: previousAnalysisSummary))

        ## Reasoning Protocol
        Follow these 7 steps in order. Your thinking should be reflected in the output structure.

        **Step 1 — Decompose**: Break the work instruction into independent sub-problems.
        **Step 2 — Infer Hidden Requirements**: Identify requirements NOT explicitly stated but likely needed \
        (e.g., authentication, error handling, edge cases, data migration, accessibility, performance, security).
        **Step 3 — List Approaches**: Generate 2-3 distinct approaches to structure this project. \
        Each approach should differ meaningfully in architecture, scope, or implementation strategy.
        **Step 4 — Evaluate**: For each approach, list concrete pros, cons, and risks.
        **Step 5 — Recommend**: Select the best approach for the current context. Mark it as "recommended": true. Explain why.
        **Step 6 — Pre-validate**: Check for internal conflicts, missing pieces, or feasibility issues in each approach.
        **Step 7 — Output**: Generate the structured result with all approaches and their deliverable skeletons.

        ## Your Task
        - Classify the project type (e.g., ios-app, web-app, api-server, dashboard, landing-page, etc.)
        - Detect or infer the tech stack from the work instruction and project context. \
          Include language, framework, platform, and database in the projectSpec.techStack field. \
          If the work instruction mentions specific technologies, use those. \
          If not explicitly stated, infer the most appropriate tech stack for the project type.
        - Determine which deliverable sections are needed. Common types:
          - "screen-spec" (화면 설계): individual screen specifications
          - "data-model" (데이터 모델): data entities and relationships
          - "api-spec" (API 명세): API endpoints and contracts
          - "user-flow" (사용자 플로우): user journey and navigation flows
          - Choose what fits the project. Not all types are needed for every project.
        - For each approach, produce a complete skeleton of deliverables with items.
        - Infer hidden requirements that the client may not have stated.

        ## Rules
        - Write all text in the same language as the work instruction.
        - Generate 2-3 approaches with meaningfully different architectures or strategies.
        - If the project is straightforward with only one reasonable approach, \
          you may output a single approach — but still include hiddenRequirements.
        - For each approach, specify which deliverable section types are needed in "sectionTypes".
        - Do NOT generate detailed deliverable items, relationships, or uncertainties in this step. \
          Those will be generated in a follow-up step for the selected approach.

        ## Response Schema (TypeScript — your JSON must conform exactly to this)
        ```typescript
        interface AnalysisResult {
          projectSpec: {
            name: string;           // project name
            type: string;           // e.g. "ios-app", "web-app", "api-server"
            techStack: Record<string, string>;  // keys: language, framework, platform, database, other
          };
          hiddenRequirements: string[];   // inferred requirements not in the work instruction
          approaches: Approach[];         // 1-3 approaches
          message: string;                // brief analysis message (2-4 sentences)
        }
        interface Approach {
          label: string;                  // e.g. "접근 방식 A: 화면 중심 설계"
          summary: string;                // 1-2 sentence description
          pros: string[];
          cons: string[];
          risks: string[];
          estimatedComplexity: "low" | "medium" | "high";
          recommended: boolean;           // exactly one approach should be true
          reasoning: string;              // why this approach is (or isn't) recommended
          sectionTypes: string[];         // e.g. ["screen-spec", "data-model", "api-spec"]
        }
        ```

        ## CRITICAL — Output Format Rules
        - Your JSON must match the TypeScript interfaces above EXACTLY.
        - "approaches" must be an ARRAY of objects, never a dictionary.
        - Do NOT add extra top-level keys (no "decomposition", "subProblems", etc.).
        - Do NOT nest "deliverables" inside approaches at this stage.

        ## Response Format
        First write a brief analysis message for the client (2-4 sentences explaining what you found).
        Then add the structured result:

        [ANALYSIS_RESULT]
        ```json
        {
          "projectSpec": {
            "name": "Project name",
            "type": "project-type",
            "techStack": {
              "language": "e.g. Swift, TypeScript, Python",
              "framework": "e.g. SwiftUI, React, FastAPI",
              "platform": "e.g. macOS, iOS, Web, Linux",
              "database": "e.g. PostgreSQL, SQLite, MongoDB (if applicable)",
              "other": "e.g. Docker, Redis (if applicable)"
            }
          },
          "hiddenRequirements": ["..."],
          "approaches": [
            {
              "label": "접근 방식 A: 화면 중심 설계",
              "summary": "...",
              "pros": ["..."],
              "cons": ["..."],
              "risks": ["..."],
              "estimatedComplexity": "medium",
              "recommended": true,
              "reasoning": "...",
              "sectionTypes": ["screen-spec", "data-model", "api-spec"]
            }
          ],
          "message": "The analysis message (same as what you wrote above)"
        }
        ```
        """
    }

    // MARK: - Skeleton Structure Prompt (Stage 2a)

    /// Builds a prompt to generate the deliverable structure (items only, no relationships/uncertainties).
    /// Called after the user selects an approach in the approachSelection phase.
    func buildSkeletonStructurePrompt(
        approach: ApproachOption,
        hiddenRequirements: [String],
        preExtractedGraph: String? = nil
    ) -> String {
        let brief = briefContextBlock()
        let hasBrief = !brief.isEmpty

        return """
        \(PromptFragments.designOfficeIdentity)\(PromptFragments.userContext(userProfile))

        Generate a detailed deliverable skeleton for the selected design approach.

        \(projectContextBlock())

        \(hasBrief ? brief : "")\(hasBrief ? "\n\n## Original Discussion (Reference)\n\(taskInput)" : "## Work Instruction\n\(taskInput)")\(analysisGraphHint(preExtractedGraph))

        ## Selected Approach
        **\(approach.label)**
        \(approach.summary)
        \(approach.reasoning.isEmpty ? "" : "\nReasoning: \(approach.reasoning)")

        ## Hidden Requirements
        \(hiddenRequirements.isEmpty ? "None identified." : hiddenRequirements.map { "- \($0)" }.joined(separator: "\n"))

        ## Your Task
        Generate all deliverable sections and items for this approach.
        Focus on defining items with their metadata. Relationships and uncertainties will be handled separately.

        Available section types:
        - "screen-spec" (화면 설계): individual screen specifications
        - "data-model" (데이터 모델): data entities and relationships
        - "api-spec" (API 명세): API endpoints and contracts
        - "user-flow" (사용자 플로우): user journey and navigation flows
        Choose what fits the project. Not all types are needed for every project.

        ## Rules
        - Be thorough but not excessive. Include all items that are clearly needed, skip speculative ones.
        - Write all text in the same language as the work instruction.
        - Item names should be concise and descriptive.
        - For "screen-spec" items, include a "purpose" string and a "components" array with basic UI component hints.
          Each component: {"type": "ComponentType", "name": "Display Name"}
          Common types: NavigationBar, TextField, Button, List, Image, Label, TabBar, Form, Card, SearchBar
          Keep it to 3-8 main components per screen. These are rough sketches, not final specs.
        - Assign a parallelGroup number (integer, starting from 1) to each item.
          Items in the same group can be elaborated in parallel (no dependency between them).
          Items in a higher group depend on results from lower groups.
          If unsure about dependencies, put items in the same group (prefer parallelism).
        - For each item, include a "plannerQuestion" — a short question highlighting an ambiguity or design choice.
        - Optionally assign a "scenarioGroup" label to related items that form a cross-section functional scenario.
          Items sharing the same scenarioGroup will be visually grouped. Use short, descriptive names (e.g., "인증 플로우", "결제 프로세스").

        ## Response Schema (TypeScript — your JSON must conform exactly to this)
        ```typescript
        interface SkeletonResult {
          deliverables: DeliverableSection[];   // MUST be an array, never a dictionary
        }
        interface DeliverableSection {
          type: string;                // e.g. "screen-spec", "data-model", "api-spec", "user-flow"
          label: string;               // human-readable, e.g. "화면 설계"
          items: ItemSkeleton[];       // MUST be an array
        }
        interface ItemSkeleton {
          name: string;
          briefDescription: string;
          parallelGroup: number;       // integer starting from 1
          plannerQuestion: string;
          scenarioGroup?: string;      // optional group label
          purpose?: string;            // for screen-spec items
          components?: {type: string, name: string}[];  // for screen-spec items, 3-8 components
        }
        ```

        ## CRITICAL — Output Format Rules
        - "deliverables" must be an ARRAY of objects, never a dictionary.
        - Each deliverable must have "type", "label", and "items" fields.
        - "items" must be an ARRAY of objects, never a dictionary.

        ## Response Format

        [SKELETON_RESULT]
        ```json
        {
          "deliverables": [
            {
              "type": "screen-spec",
              "label": "화면 설계",
              "items": [
                { "name": "로그인", "briefDescription": "사용자 인증 화면", "purpose": "이메일/비밀번호로 로그인", "components": [{"type": "NavigationBar", "name": "로그인"}, {"type": "TextField", "name": "이메일"}, {"type": "TextField", "name": "비밀번호"}, {"type": "Button", "name": "로그인"}], "parallelGroup": 1, "plannerQuestion": "소셜 로그인 지원이 필요한가?", "scenarioGroup": "인증 플로우" }
              ]
            }
          ]
        }
        ```
        """
    }

    // MARK: - Skeleton Graph Prompt (Stage 2b)

    /// Builds a prompt to generate relationships and uncertainties for existing skeleton items.
    /// Called after skeleton structure is generated, with the full item list as context.
    func buildSkeletonGraphPrompt(
        approach: ApproachOption,
        hiddenRequirements: [String],
        itemList: [(section: String, name: String, briefDescription: String, components: [String])]
    ) -> String {
        let itemLines = itemList.map { item in
            var line = "- [\(item.section)] \(item.name): \(item.briefDescription)"
            if !item.components.isEmpty {
                line += " | UI: \(item.components.joined(separator: ", "))"
            }
            return line
        }.joined(separator: "\n")

        return """
        \(PromptFragments.designOfficeIdentity)

        Analyze the relationships and uncertainties for the following design skeleton items.

        \(projectContextBlock())

        ## Work Instruction
        \(taskInput)

        ## Selected Approach
        **\(approach.label)**
        \(approach.summary)

        ## Hidden Requirements
        \(hiddenRequirements.isEmpty ? "None identified." : hiddenRequirements.map { "- \($0)" }.joined(separator: "\n"))

        ## Skeleton Items
        \(itemLines)

        ## Your Task
        1. Identify relationships between the items listed above.
        2. Surface the most significant uncertainties or ambiguities.

        ## Relationship Rules
        - Use one of these relationType values: depends_on, navigates_to, uses, refines, replaces.
        - sourceName and targetName must exactly match item names from the list above.
        - For screen-spec items: examine UI components (buttons, navigation actions, links) to derive navigates_to relationships. If a screen has a "설정" button, it must navigates_to the settings screen. If a screen has "결과 보기", it must navigates_to the results screen.
        - Every screen-spec item must have at least one navigates_to relationship (as source or target). If a screen appears isolated, re-examine its components and purpose to find the connection.
        - Overlay/modal screens must have a navigates_to from the screen that opens them AND a navigates_to back to the parent or next screen.
        - Include all meaningful relationships. Do not skip navigation edges.

        \(PromptFragments.uncertaintyAxiomsText())

        \(analysisUncertaintyExamples())

        ### Uncertainty Rules
        - Each uncertainty has: type ("question", "suggestion", "discussion", "information_gap"), priority ("blocking", "important", "advisory"), title, body, triggered_by.
        - For "suggestion" type, include an "options" array with concrete choices.
        - Include "relatedItemName" if the uncertainty relates to a specific item (must match an item name above).
        - Write all text in the same language as the item names.
        - Keep uncertainties focused and actionable. Limit to 3-5 most significant ones.

        ## Response Schema (TypeScript — your JSON must conform exactly to this)
        ```typescript
        interface SkeletonGraphResult {
          relationships: Relationship[];
          uncertainties: Uncertainty[];
        }
        interface Relationship {
          sourceName: string;   // must exactly match an item name above
          targetName: string;   // must exactly match an item name above
          relationType: "depends_on" | "navigates_to" | "uses" | "refines" | "replaces";
        }
        interface Uncertainty {
          type: "question" | "suggestion" | "discussion" | "information_gap";
          priority: "blocking" | "important" | "advisory";
          title: string;
          body: string;
          options?: string[];         // for "suggestion" type — MUST be string[], not object[]
          relatedItemName?: string;   // must match an item name above
          triggeredBy?: string;       // UncertaintyAxiom rawValue
        }
        ```

        ## CRITICAL — Output Format Rules
        - "options" in uncertainties must be a string array (e.g. ["Option A", "Option B"]), never an array of objects.
        - "relationships" and "uncertainties" must be arrays, never dictionaries.

        ## Response Format

        [SKELETON_GRAPH]
        ```json
        {
          "relationships": [
            { "sourceName": "로그인", "targetName": "메인 대시보드", "relationType": "navigates_to" }
          ],
          "uncertainties": [
            { "type": "question", "priority": "important", "title": "인증 방식", "body": "소셜 로그인 포함 여부가 불명확합니다.", "relatedItemName": "로그인", "triggeredBy": "missingInput" }
          ]
        }
        ```
        """
    }

    // MARK: - Skeleton Relationships Prompt (split from graph)

    /// Builds a focused prompt for skeleton relationships only.
    /// Lighter than the combined graph prompt — no uncertainty axioms or examples.
    func buildSkeletonRelationshipsPrompt(
        approachLabel: String,
        approachSummary: String,
        itemList: [(section: String, name: String, briefDescription: String, components: [String])]
    ) -> String {
        let itemLines = itemList.map { item in
            var line = "- [\(item.section)] \(item.name): \(item.briefDescription)"
            if !item.components.isEmpty {
                line += " | UI: \(item.components.joined(separator: ", "))"
            }
            return line
        }.joined(separator: "\n")

        return """
        \(PromptFragments.designOfficeIdentityCompact)

        Analyze the relationships between the following design skeleton items.

        \(projectContextBlock())

        ## Selected Approach
        **\(approachLabel)**
        \(approachSummary)

        ## Skeleton Items
        \(itemLines)

        ## Your Task
        Identify relationships between the items listed above.

        ## Relationship Rules
        - Use one of these relationType values: depends_on, navigates_to, uses, refines, replaces.
        - sourceName and targetName must exactly match item names from the list above.
        - For screen-spec items: examine UI components (buttons, navigation actions, links) to derive navigates_to relationships. If a screen has a "설정" button, it must navigates_to the settings screen. If a screen has "결과 보기", it must navigates_to the results screen.
        - Every screen-spec item must have at least one navigates_to relationship (as source or target). If a screen appears isolated, re-examine its components and purpose to find the connection.
        - Overlay/modal screens must have a navigates_to from the screen that opens them AND a navigates_to back to the parent or next screen.
        - Include all meaningful relationships. Do not skip navigation edges.

        ## Response Format

        [SKELETON_RELATIONSHIPS]
        ```json
        {
          "relationships": [
            { "sourceName": "로그인", "targetName": "메인 대시보드", "relationType": "navigates_to" }
          ]
        }
        ```
        """
    }

    // MARK: - Skeleton Uncertainties Prompt (split from graph)

    /// Builds a focused prompt for skeleton uncertainties only.
    /// Lighter than the combined graph prompt — no relationship rules or component data.
    func buildSkeletonUncertaintiesPrompt(
        approachLabel: String,
        approachSummary: String,
        hiddenRequirements: [String],
        itemList: [(section: String, name: String, briefDescription: String)]
    ) -> String {
        let itemLines = itemList.map { "- [\($0.section)] \($0.name): \($0.briefDescription)" }
            .joined(separator: "\n")

        return """
        \(PromptFragments.designOfficeIdentityCompact)

        Surface the most significant uncertainties or ambiguities for the following design skeleton.

        \(projectContextBlock())

        ## Selected Approach
        **\(approachLabel)**
        \(approachSummary)

        ## Hidden Requirements
        \(hiddenRequirements.isEmpty ? "None identified." : hiddenRequirements.map { "- \($0)" }.joined(separator: "\n"))

        ## Skeleton Items
        \(itemLines)

        ## Your Task
        Identify the most significant uncertainties or ambiguities in this design skeleton.

        \(PromptFragments.uncertaintyAxiomsText())

        \(analysisUncertaintyExamples())

        ### Uncertainty Rules
        - Each uncertainty has: type ("question", "suggestion", "discussion", "information_gap"), priority ("blocking", "important", "advisory"), title, body, triggered_by.
        - For "suggestion" type, include an "options" array with concrete choices.
        - Include "relatedItemName" if the uncertainty relates to a specific item (must match an item name above).
        - Write all text in the same language as the item names.
        - Keep uncertainties focused and actionable. Limit to 3-5 most significant ones.

        ## CRITICAL — Output Format Rules
        - "options" in uncertainties must be a string array (e.g. ["Option A", "Option B"]), never an array of objects.
        - "uncertainties" must be an array, never a dictionary.

        ## Response Format

        [SKELETON_UNCERTAINTIES]
        ```json
        {
          "uncertainties": [
            { "type": "question", "priority": "important", "title": "인증 방식", "body": "소셜 로그인 포함 여부가 불명확합니다.", "relatedItemName": "로그인", "triggeredBy": "missingInput" }
          ]
        }
        ```
        """
    }

    // MARK: - Orchestration Chat Prompt

    /// Builds a prompt for Design chat with orchestration capability.
    // MARK: - Uncertainty Discussion Prompt

    /// Build a prompt for discussing a specific uncertainty with the client.
    /// Provides uncertainty context and guides toward resolution.
    func buildUncertaintyDiscussPrompt(
        uncertaintyId: UUID,
        uncertainty: DesignDecision,
        chatHistory: [DesignChatMessage],
        userMessage: String,
        deliverables: [DeliverableSection]
    ) -> String {
        var parts: [String] = []

        parts.append(orchestrationRoleSection())
        parts.append(orchestrationProjectContext())

        if let section = orchestrationDeliverablesSection(deliverables) {
            parts.append(section)
        }
        if let section = orchestrationFocusedItemSection(focusedItemId: uncertainty.relatedItemId, deliverables: deliverables) {
            parts.append(section)
        }
        if let section = orchestrationChatHistorySection(chatHistory) {
            parts.append(section)
        }

        let typeLabel = uncertainty.escalationType?.rawValue ?? "question"
        let priorityLabel = uncertainty.priority.rawValue
        let optionsText = uncertainty.options.isEmpty ? "None" : uncertainty.options.joined(separator: ", ")
        let relatedItemName: String = {
            if let itemId = uncertainty.relatedItemId {
                for section in deliverables {
                    if let item = section.items.first(where: { $0.id == itemId }) {
                        return item.name
                    }
                }
            }
            return "None"
        }()

        parts.append("""
        ## Uncertainty Discussion Context
        You are discussing a specific uncertainty with the client.

        **Type**: \(typeLabel)
        **Priority**: \(priorityLabel)
        **Title**: \(uncertainty.title)
        **Description**: \(uncertainty.body)
        **Options**: \(optionsText)
        **Related Item**: \(relatedItemName)

        Your goal:
        1. Help the client understand this uncertainty and its implications.
        2. Discuss possible resolutions based on the project context.
        3. When a resolution becomes clear, propose it clearly in your message.
        4. If the resolution requires deliverable changes, include appropriate actions.
        5. For suggestion-type uncertainties, recommend one of the given options with rationale.
        6. For question/discussion/informationGap types, synthesize the discussion into a clear resolution statement.
        7. Write in the same language as the client's message.

        ## User Message
        \(userMessage)
        """)

        if let section = orchestrationRelationshipsSection() {
            parts.append(section)
        }

        parts.append(orchestrationResponseFormat())

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Revision Review Prompt

    /// Build a prompt for the revision review overlay.
    /// Focuses on a specific item, analyzes impact, and proposes structured actions.
    func buildRevisionReviewPrompt(
        itemId: UUID,
        chatHistory: [DesignChatMessage],
        userMessage: String,
        deliverables: [DeliverableSection]
    ) -> String {
        var parts: [String] = []

        parts.append(orchestrationRoleSection())
        parts.append(orchestrationProjectContext())

        if let section = orchestrationDeliverablesSection(deliverables) {
            parts.append(section)
        }
        if let section = orchestrationFocusedItemSection(focusedItemId: itemId, deliverables: deliverables) {
            parts.append(section)
        }
        if let section = orchestrationChatHistorySection(chatHistory) {
            parts.append(section)
        }

        parts.append("""
        ## Revision Review Context
        The client is reviewing a specific item and requesting changes.
        Analyze the requested change carefully:
        1. What exactly needs to change in this item's spec?
        2. Does this change affect other items? (navigation, dependencies, shared components)
        3. Propose concrete actions using the standard action format.

        Always include actions in your response so the changes can be applied automatically.
        Common actions for revisions: update_item (modify an existing item), remove_item, add_item, link_items, unlink_items.

        ### update_item field conventions
        The action schema does not expose a free-form `changes` object, so encode
        the update values into these flat fields:
        - `itemId`: UUID of the item being updated (required).
        - `sectionType`: section containing the item (required).
        - `itemName`: the item's new name. If the name should stay the same, repeat the current name.
        - `body`: the item's new brief description / spec summary after the revision.
        Leave unrelated fields as empty strings. At minimum one of `itemName` or `body` must carry a meaningful value, otherwise the update will be discarded.

        ## User Message
        \(userMessage)
        """)

        if let section = orchestrationRelationshipsSection() {
            parts.append(section)
        }

        parts.append(orchestrationResponseFormat())

        return parts.joined(separator: "\n\n")
    }

    /// - Called by: `DesignWorkflowViewModel.sendChatMessage()`
    /// - Output: Text response + optional `[DIRECTOR_RESPONSE]` JSON block
    /// - JSON actions: elaborate_item, update_item, add_item, remove_item, add_section, link_items, unlink_items, mark_complete, raise_uncertainty
    func buildOrchestrationChatPrompt(
        chatHistory: [DesignChatMessage],
        userMessage: String,
        deliverables: [DeliverableSection],
        focusedItemId: UUID? = nil
    ) -> String {
        var parts: [String] = []

        parts.append(orchestrationRoleSection())
        parts.append(orchestrationProjectContext())

        if let section = orchestrationDeliverablesSection(deliverables) {
            parts.append(section)
        }
        if let section = orchestrationFocusedItemSection(focusedItemId: focusedItemId, deliverables: deliverables) {
            parts.append(section)
        }
        if let section = orchestrationChatHistorySection(chatHistory) {
            parts.append(section)
        }
        if let section = orchestrationAgentsSection() {
            parts.append(section)
        }

        parts.append("## User Message\n\(userMessage)")

        if let section = orchestrationRelationshipsSection() {
            parts.append(section)
        }

        parts.append(orchestrationResponseFormat())

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Orchestration Chat Sections (private)

    private func orchestrationRoleSection() -> String {
        """
        \(PromptFragments.designOfficeIdentityCompact)\(PromptFragments.userContext(userProfile))

        You are assisting a client who reviews and judges each deliverable item.
        Your role is to:
        1. Discuss the project with the client — answer questions, explain decisions, suggest improvements
        2. Translate client feedback into concrete deliverable changes (add/remove/modify items)
        3. When the client requests elaboration for an item, trigger detailed spec generation by a step agent
        4. Track progress and suggest next steps based on current verdict states

        ## Judgment Boundaries
        - Direction belongs to the client: product scope, target users, feature priority, business rules.
        - Implementation belongs to you: technical patterns, UI conventions, data structures, error strategies.
        - Don't burden the client with technical decisions you can make professionally.
        - When you make a judgment call, state your reasoning briefly so the client can override if needed.

        ## Reasoning Protocol
        When processing the client's message, follow this internal reasoning before responding:
        1. Decompose: What specific items or aspects is this feedback about?
        2. Infer intent: What is the client's underlying goal, beyond what they explicitly said?
        3. Consider options: What are the possible actions to address this feedback?
        4. Evaluate: Which option best serves the project with minimal disruption?
        5. Pre-validate: Does the chosen action conflict with any confirmed items?
        Then respond with the best action. Do NOT output the reasoning steps — just the result.

        The client controls the workflow by setting a verdict on each item:
        - unreviewed: not yet reviewed
        - approved: client accepts the current state (OK)
        - rejected: client removes this item

        When the client wants changes to an item, they use chat to describe the changes,
        which triggers elaboration for that specific item.

        You respond with a message for the client AND optional actions to modify the deliverables.
        """
    }

    private func orchestrationProjectContext() -> String {
        if let wf = workflow {
            var lines: [String] = []
            lines.append(projectContextBlock())
            lines.append("Task: \(wf.taskDescription.isEmpty ? taskInput : wf.taskDescription)")
            lines.append("Phase: \(wf.phase.rawValue)")

            if !wf.designSummary.isEmpty {
                lines.append("Summary: \(wf.designSummary)")
            }
            return lines.joined(separator: "\n")
        } else if !taskInput.isEmpty {
            return "\(projectContextBlock())\n\n## Task\n\(taskInput)"
        }
        return projectContextBlock()
    }

    private func orchestrationDeliverablesSection(_ deliverables: [DeliverableSection]) -> String? {
        guard !deliverables.isEmpty else { return nil }
        var parts: [String] = ["## Current Deliverables"]
        for section in deliverables {
            parts.append("### \(section.label) (\(section.type))")
            for item in section.items {
                let statusIcon: String
                switch item.status {
                case .completed: statusIcon = "[DONE]"
                case .inProgress: statusIcon = "[WORKING]"
                case .pending: statusIcon = "[PENDING]"
                case .needsRevision: statusIcon = "[NEEDS_REVISION]"
                }
                let specPreview = item.spec.isEmpty ? "" : " — has spec"
                let verdictTag = item.designVerdict == .pending ? "" : " [verdict: \(item.designVerdict.rawValue)]"
                parts.append("  - \(statusIcon) \(item.name) (id: \(item.id.uuidString))\(specPreview)\(verdictTag)")
                if let desc = item.briefDescription {
                    parts.append("    \(desc)")
                }
                if let notes = item.plannerNotes, !notes.isEmpty {
                    parts.append("    Planner notes: \(notes)")
                }
            }
        }
        return parts.joined(separator: "\n\n")
    }

    private func orchestrationFocusedItemSection(
        focusedItemId: UUID?,
        deliverables: [DeliverableSection]
    ) -> String? {
        guard let focusedId = focusedItemId,
              let wf = workflow,
              let (si, _, item) = wf.findItem(byId: focusedId),
              si < deliverables.count else { return nil }
        let section = deliverables[si]
        var lines: [String] = []
        lines.append("## Currently Focused Item")
        lines.append("The client is currently viewing this item. Prioritize context about it in your response.")
        lines.append("- Name: \(item.name)")
        lines.append("- Section: \(section.label) (\(section.type))")
        lines.append("- Status: \(item.status.rawValue)")
        lines.append("- Verdict: \(item.designVerdict.rawValue)")
        if let desc = item.briefDescription {
            lines.append("- Description: \(desc)")
        }
        if let notes = item.plannerNotes, !notes.isEmpty {
            lines.append("- Planner notes: \(notes)")
        }
        if !item.spec.isEmpty {
            lines.append("- Has detailed spec")
        }
        let relatedEdges = wf.edges(for: focusedId)
        if !relatedEdges.isEmpty {
            lines.append("Related items:")
            for edge in relatedEdges {
                let otherId = edge.sourceId == focusedId ? edge.targetId : edge.sourceId
                if let (_, _, other) = wf.findItem(byId: otherId) {
                    let dir = edge.sourceId == focusedId ? "→" : "←"
                    lines.append("  - \(dir) \(other.name) (\(edge.relationType))")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private func orchestrationChatHistorySection(_ chatHistory: [DesignChatMessage]) -> String? {
        guard !chatHistory.isEmpty else { return nil }
        var parts: [String] = ["## Conversation History"]
        let recentHistory = chatHistory.suffix(20)
        for msg in recentHistory {
            let label: String
            switch msg.role {
            case .user: label = "Client"
            case .design: label = "Design"
            case .system: label = "System"
            }
            parts.append("\(label): \(msg.content)")
        }
        return parts.joined(separator: "\n\n")
    }

    private func orchestrationAgentsSection() -> String? {
        let agentsDesc = Agent.promptDescription(for: availableAgents)
        guard agentsDesc != "No step agents available." else { return nil }
        return """
        ## Available Step Agents
        \(agentsDesc)

        When issuing "elaborate_item" actions, you MUST include an "agentId" field
        to assign the most suitable step agent. Choose based on section type and agent expertise:
        - screen-spec / user-flow: prefer agents with UI/UX or frontend expertise
        - data-model / api-spec: prefer agents with backend or data expertise
        """
    }

    private func orchestrationRelationshipsSection() -> String? {
        guard let wf = workflow, !wf.edges.isEmpty else { return nil }
        return """
        ## Current Item Relationships
        These are known dependencies and relationships between deliverable items. Use them to inform your decisions.
        \(wf.edges.map { edge -> String in
            let srcName = wf.findItem(byId: edge.sourceId)?.item.name ?? edge.sourceId.uuidString
            let tgtName = wf.findItem(byId: edge.targetId)?.item.name ?? edge.targetId.uuidString
            return "- \(srcName) → \(tgtName) (\(edge.relationType))"
        }.joined(separator: "\n"))
        """
    }

    private func orchestrationResponseFormat() -> String {
        """
        ## Response Instructions
        1. Write a helpful response to the planner (be concise and direct).
        2. If the planner's message implies changes to deliverables, include actions.
        3. If items need detailed specs created, use "elaborate_item" action.
        4. If the planner says something like "상세 설계 해줘" or "이 항목 자세히", elaborate the relevant items.
        5. Write in the same language as the planner's message.
        6. Use existing item relationships (shown in "Current Item Relationships") to inform decisions: respect dependency order when elaborating, and reference linked items in your explanations.
           Actively mine the planner's latest message for relationship language and emit "link_items" actions when you detect:
           - Navigation: "A에서 B로 이동", "A navigates to B", "from A go to B"
           - Dependency: "A는 B에 의존", "A depends on B", "A needs B first"
           - Usage: "A는 B를 호출/사용", "A uses B", "A calls B"
           - Refinement: "A는 B를 개선/확장", "A refines B"
           - Removal: "A와 B의 관계를 제거", "remove link between A and B", "A no longer depends on B"
           Emit link_items for NEW relationships and unlink_items for removed relationships. Emit silently alongside your main response — do not ask permission.

        ## Response Schema (TypeScript — your JSON must conform exactly to this)
        ```typescript
        interface DirectorResponse {
          message: string;          // your message to the client
          actions?: Action[];       // omit if no deliverable changes needed
        }
        type Action =
          | { type: "elaborate_item"; sectionType: string; itemId: string; agentId?: string }
          | { type: "update_item"; sectionType: string; itemId: string; changes: Record<string, any> }
          | { type: "add_item"; sectionType: string; itemName: string; briefDescription?: string }
          | { type: "remove_item"; sectionType: string; itemId: string }
          | { type: "add_section"; sectionType: string; sectionLabel: string; items: {name: string; briefDescription: string}[] }
          | { type: "link_items"; sourceItemId: string; targetItemId: string; relationType: string }
          | { type: "unlink_items"; sourceItemId: string; targetItemId: string; relationType?: string }
          | { type: "mark_complete" }
          | { type: "raise_uncertainty"; uncertaintyType: string; priority: string; title: string; body: string; itemId?: string; options?: string[]; triggeredBy?: string };
        ```

        ## CRITICAL — Output Format Rules
        - "actions" must be an ARRAY, never a dictionary.
        - "options" in raise_uncertainty must be string[], not object[].
        - If no actions needed, omit the [DIRECTOR_RESPONSE] block entirely.

        ## Response Format
        First write your message to the client.
        Then, if there are deliverable changes, add:

        [DIRECTOR_RESPONSE]
        ```json
        {
          "message": "Your message to the client (same as above)",
          "actions": [
            {
              "type": "elaborate_item",
              "sectionType": "screen-spec",
              "itemId": "uuid-string",
              "agentId": "agent-uuid-string"
            },
            {
              "type": "update_item",
              "sectionType": "screen-spec",
              "itemId": "uuid-string",
              "changes": { "key": "new value" }
            },
            {
              "type": "add_item",
              "sectionType": "screen-spec",
              "itemName": "새 화면 이름"
            },
            {
              "type": "remove_item",
              "sectionType": "screen-spec",
              "itemId": "uuid-string"
            },
            {
              "type": "add_section",
              "sectionType": "new-type",
              "sectionLabel": "새 유형 이름",
              "items": [{ "name": "항목명", "briefDescription": "설명" }]
            },
            {
              "type": "link_items",
              "sourceItemId": "uuid-of-source-item",
              "targetItemId": "uuid-of-target-item",
              "relationType": "depends_on"
            },
            {
              "type": "unlink_items",
              "sourceItemId": "uuid-of-source-item",
              "targetItemId": "uuid-of-target-item",
              "relationType": "depends_on"
            },
            {
              "type": "mark_complete"
            },
            {
              "type": "raise_uncertainty",
              "uncertaintyType": "question",
              "priority": "important",
              "itemId": "uuid-of-related-item",
              "title": "질문 제목",
              "body": "구체적인 질문 내용",
              "options": ["선택지1", "선택지2"]
            }
          ]
        }
        ```

        Action types:
        - "elaborate_item": Request step agent to create detailed spec for an item
        - "update_item": Directly modify an item's spec fields
        - "add_item": Add a new item to a section
        - "remove_item": Remove an item from a section
        - "add_section": Add a new deliverable section with items
        - "link_items": Record a relationship between two items. Use one of these relationType values: depends_on, refines, replaces, navigates_to, uses
        - "unlink_items": Remove a relationship between two items. Specify sourceItemId, targetItemId, and optionally relationType (if omitted, removes all edges between the pair)
        - "mark_complete": Mark the entire workflow as complete
        - "raise_uncertainty": Surface a question, suggestion, or discussion topic to the client.
          - uncertaintyType: "question" (needs an answer), "suggestion" (propose with options), "discussion" (complex topic), "information_gap" (missing context)
          - priority: "blocking" (cannot proceed without answer), "important" (should resolve before finalizing), "advisory" (nice to know)
          - itemId: UUID of the related item (optional)
          - title: Short title for the uncertainty
          - body: Detailed description
          - options: Array of choices (for suggestion type)

        \(PromptFragments.uncertaintyAxiomsText())

        \(chatUncertaintyExamples())

        When a meta-condition is TRUE, use "raise_uncertainty" instead of guessing. Include "triggeredBy" with the axiom name.
        If no actions are needed (just a conversation response), omit the [DIRECTOR_RESPONSE] block entirely.
        """
    }

    // MARK: - Item Elaboration Prompt (for step agents)

    /// Builds a prompt for a step agent to elaborate a specific deliverable item.
    /// - Called by: `DesignWorkflowViewModel.elaborateItem()`
    /// - Output: JSON code block with `spec` + `summary`, optional `[UNCERTAINTIES]` block
    func buildItemElaborationPrompt(
        section: DeliverableSection,
        item: DeliverableItem,
        projectSpec: ProjectSpec?,
        relatedItems: [DeliverableItem],
        crossSectionItems: [(sectionLabel: String, item: DeliverableItem)] = [],
        itemEdgeLines: [String] = []
    ) -> String {
        let docDir: String
        if let iId = ideaId, let rId = requestId {
            docDir = ".lao/\(iId.uuidString)/\(rId.uuidString)"
        } else {
            docDir = ".lao/docs"
        }

        var prompt = """
        \(PromptFragments.designOfficeIdentityCompact)

        You are creating a detailed specification for a deliverable item. \
        Your spec must be implementation-ready — a developer reading it should have zero questions.

        \(projectContextBlock())
        \(referenceContextBlock())

        ## Item to Elaborate
        Name: \(item.name)
        Type: \(section.type) (in section: \(section.label))
        \(item.briefDescription.map { "Description: \($0)" } ?? "")

        \(elaborationSectionTypeGuidance(section.type))
        """

        if let note = item.revisionNote, !note.isEmpty {
            // Include existing spec so the AI can preserve unchanged parts
            if !item.spec.isEmpty,
               let json = try? JSONEncoder().encode(item.spec),
               let specStr = String(data: json, encoding: .utf8) {
                prompt += """

                ## Current Spec (to be revised)
                Below is the existing spec JSON. Preserve all fields and values that are NOT affected by the revision request.
                Only modify what the revision explicitly asks to change.
                ```json
                \(specStr)
                ```
                """
            }

            prompt += """

            ## Revision Request
            The client reviewed the previous spec and requested changes:
            \(note)
            IMPORTANT: Output the COMPLETE revised spec. Keep every field from the current spec intact unless the revision request specifically asks to change it. Do NOT omit components, states, or other existing details.
            """
        }

        if let ctx = elaborationRelatedItemsContext(relatedItems) {
            prompt += ctx
        }

        if let ctx = elaborationCrossSectionContext(crossSectionItems) {
            prompt += ctx
        }

        if !itemEdgeLines.isEmpty {
            prompt += """

            ## This Item's Relationships
            \(itemEdgeLines.map { "- \($0)" }.joined(separator: "\n"))
            Use these relationships when writing the spec (e.g., reference linked items in navigation fields, mention dependencies in descriptions).
            """
        }

        if let wf = workflow, !wf.taskDescription.isEmpty {
            prompt += """

            ## Overall Task Context
            \(wf.taskDescription)
            """
        }

        prompt += elaborationOutputFormat(docDir: docDir, sectionType: section.type)

        return prompt
    }

    // MARK: - Item Elaboration Sections (private)

    private func elaborationSectionTypeGuidance(_ sectionType: String) -> String {
        switch sectionType {
        case "screen-spec":
            return """
            ## Screen Spec Elaboration
            Create a detailed screen specification with:
            - purpose: What the user accomplishes on this screen
            - entry_condition: How the user arrives at this screen
            - exit_to: Screen IDs this screen navigates to
            - components: Every UI element with name, type, and role. Use "children" array for nested hierarchy (e.g., a Form containing TextFields). Include "data_source" to specify what data each component displays or binds to (e.g., "model: User.displayName", "api: GET /users/:id → response.name")
            - interactions: What happens on tap/input/scroll for each element
            - states: normal, loading, empty, error — describe each state's appearance
            - edge_cases: boundary conditions, validation messages, permission states
            - api_calls: Array of APIs this screen invokes, each with { endpoint, trigger, on_success, on_error }
            - state_management: What local/shared state this screen holds, how it changes, and what triggers re-renders

            Example output:
            ```json
            {
              "spec": {
                "purpose": "사용자 인증을 처리하는 로그인 화면",
                "entry_condition": "앱 시작 시 또는 로그아웃 후",
                "exit_to": ["main-dashboard", "signup"],
                "components": [
                  { "name": "header", "type": "NavigationBar", "role": "상단 네비게이션",
                    "children": [
                      { "name": "back_button", "type": "Button", "role": "뒤로가기" },
                      { "name": "title_label", "type": "Text", "role": "화면 제목" }
                    ]
                  },
                  { "name": "login_form", "type": "VStack", "role": "로그인 입력 영역",
                    "children": [
                      { "name": "email_field", "type": "TextField", "role": "이메일 입력", "data_source": "local state: email" },
                      { "name": "password_field", "type": "SecureField", "role": "비밀번호 입력", "data_source": "local state: password" },
                      { "name": "login_button", "type": "Button", "role": "로그인 실행" }
                    ]
                  },
                  { "name": "error_banner", "type": "Text", "role": "에러 메시지 표시", "data_source": "local state: errorMessage" }
                ],
                "interactions": [
                  { "trigger": "로그인 버튼 탭", "action": "POST /api/auth/login 호출 → 성공 시 토큰 저장 후 메인 대시보드 이동" }
                ],
                "states": {
                  "normal": "이메일/비밀번호 필드 + 로그인 버튼",
                  "loading": "버튼 비활성화 + 스피너",
                  "error": "에러 메시지 배너 표시"
                },
                "api_calls": [
                  {
                    "endpoint": "POST /api/auth/login",
                    "trigger": "로그인 버튼 탭",
                    "on_success": "토큰 저장 → main-dashboard 이동",
                    "on_error": "errorMessage 상태 업데이트 → error 상태 전환"
                  }
                ],
                "state_management": {
                  "local_state": ["email: String", "password: String", "isLoading: Bool", "errorMessage: String?"],
                  "shared_state": ["authToken: 로그인 성공 시 앱 전역 저장소에 저장"],
                  "triggers": "로그인 버튼 탭 → isLoading=true → API 호출 → 결과에 따라 상태 전환"
                }
              },
              "summary": "이메일/비밀번호 기반 로그인 화면으로 인증 API 호출 후 메인 대시보드로 이동"
            }
            ```

            When reference images exist, each visible component MUST include "visual_spec":
            ```json
            {
              "name": "player_character",
              "type": "CSSArt",
              "role": "Main character",
              "visual_spec": {
                "reference": "Referenced product name (see reference image)",
                "rendering": "CSS border-radius + box-shadow / SVG / Canvas",
                "shape": "Description of shape, size, border-radius",
                "colors": {"primary": "#hex", "secondary": "#hex"},
                "animation": {"idle": "description of idle animation"},
                "layout": "Position and z-index information"
              }
            }
            ```
            Do NOT use emoji as rendering strategy. Specify concrete CSS/SVG/Canvas rendering.
            """

        case "data-model":
            return """
            ## Data Model Elaboration
            Create a detailed data model specification with:
            - description: What this entity represents
            - fields: Each field with name, type, required flag, description, default (if any), validation (constraints/format)
            - relationships: Related entities with relationship type (one-to-one, one-to-many, many-to-many) and cascade behavior
            - indexes: Fields that should be indexed, with uniqueness constraints
            - business_rules: Domain-specific rules and constraints
            - access_patterns: Common query patterns describing how this entity is typically read/written (e.g., "lookup by email", "list by created_at DESC with pagination")
            - migration_notes: Considerations for schema creation or migration (nullable transitions, data backfill, etc.)

            Example output:
            ```json
            {
              "spec": {
                "description": "사용자 계정 정보를 저장하는 엔티티",
                "fields": [
                  { "name": "id", "type": "UUID", "required": true, "description": "고유 식별자", "default": "auto-generated" },
                  { "name": "email", "type": "String", "required": true, "description": "로그인용 이메일", "validation": "RFC 5322 이메일 형식" },
                  { "name": "displayName", "type": "String", "required": false, "description": "표시 이름", "default": null, "validation": "2-50자" },
                  { "name": "status", "type": "Enum(active, suspended, deleted)", "required": true, "description": "계정 상태", "default": "active" },
                  { "name": "createdAt", "type": "DateTime", "required": true, "description": "생성 시각", "default": "now()" }
                ],
                "relationships": [
                  { "entity": "Post", "type": "one-to-many", "description": "사용자가 작성한 게시물", "cascade": "soft-delete" }
                ],
                "indexes": [
                  { "fields": ["email"], "unique": true },
                  { "fields": ["status", "createdAt"], "unique": false }
                ],
                "business_rules": [
                  "이메일은 유효한 형식이어야 함",
                  "displayName은 2-50자 사이",
                  "삭제 시 soft-delete (status → deleted)"
                ],
                "access_patterns": [
                  "이메일로 단건 조회 (로그인, 중복 확인)",
                  "status별 목록 조회 (관리자 페이지, createdAt DESC 정렬)",
                  "ID로 단건 조회 (프로필, 관계 로딩)"
                ],
                "migration_notes": "email에 UNIQUE 인덱스 필수. status 컬럼 추가 시 기존 행은 'active'로 backfill."
              },
              "summary": "사용자 계정 정보 엔티티로 이메일 기반 인증 지원, soft-delete 적용"
            }
            ```
            """

        case "api-spec":
            return """
            ## API Spec Elaboration
            Create a detailed API endpoint specification with:
            - method: HTTP method (GET, POST, PUT, DELETE, etc.)
            - path: URL path with parameters (e.g., /api/v1/users/:id)
            - description: What this endpoint does
            - parameters: Path, query, and header parameters with name, in (path/query/header), type, required flag, and description
            - request_body: Expected request payload with field types
            - request_body_schema: Typed schema — each field with { type, required, description, example } for implementation
            - response: Expected response structure
            - response_schema: Typed schema — each field with { type, nullable, description, example } for implementation
            - error_responses: Error codes, messages, and when each occurs
            - auth: Authentication requirements (method, token type, scopes if applicable)
            - pagination: (for list endpoints) { strategy: "cursor"|"offset"|"page", parameters, default_page_size }
            - example_request: A concrete example request (headers + body)
            - example_response: A concrete example successful response body
            - implementation_hints: Caching strategy, rate limiting, idempotency, side effects, retry behavior

            Example output:
            ```json
            {
              "spec": {
                "method": "GET",
                "path": "/api/v1/users/:user_id/posts",
                "description": "특정 사용자의 게시물 목록 조회",
                "parameters": [
                  { "name": "user_id", "in": "path", "type": "UUID", "required": true, "description": "대상 사용자 ID" },
                  { "name": "page", "in": "query", "type": "Int", "required": false, "description": "페이지 번호 (기본값: 1)" },
                  { "name": "limit", "in": "query", "type": "Int", "required": false, "description": "페이지당 항목 수 (기본값: 20, 최대: 100)" }
                ],
                "request_body_schema": null,
                "response_schema": {
                  "items": { "type": "[PostSummary]", "description": "게시물 요약 배열" },
                  "total": { "type": "Int", "description": "전체 게시물 수" },
                  "page": { "type": "Int", "description": "현재 페이지" },
                  "hasNext": { "type": "Bool", "description": "다음 페이지 존재 여부" }
                },
                "response": {
                  "items": [{ "id": "UUID", "title": "String", "createdAt": "Date", "excerpt": "String" }],
                  "total": 42,
                  "page": 1,
                  "hasNext": true
                },
                "error_responses": [
                  { "code": 404, "message": "User not found", "when": "user_id가 존재하지 않을 때" },
                  { "code": 401, "message": "Unauthorized", "when": "인증 토큰이 없거나 만료됨" }
                ],
                "auth": "Bearer token",
                "pagination": {
                  "strategy": "offset",
                  "parameters": ["page", "limit"],
                  "default_page_size": 20
                },
                "example_request": {
                  "url": "GET /api/v1/users/550e8400-e29b-41d4-a716-446655440000/posts?page=1&limit=20",
                  "headers": { "Authorization": "Bearer <token>" }
                },
                "example_response": {
                  "items": [{ "id": "...", "title": "첫 번째 게시물", "createdAt": "2025-01-15T09:00:00Z", "excerpt": "..." }],
                  "total": 42,
                  "page": 1,
                  "hasNext": true
                },
                "implementation_hints": {
                  "caching": "목록은 60초 TTL 캐시 적용 가능",
                  "side_effects": "없음 (읽기 전용)",
                  "notes": "deleted_at이 NULL인 게시물만 반환"
                }
              },
              "summary": "사용자별 게시물 목록 페이지네이션 조회 API (오프셋 기반)"
            }
            ```
            """

        case "user-flow":
            return """
            ## User Flow Elaboration
            Create a detailed user flow specification with:
            - trigger: What initiates this flow
            - steps: Ordered list of user actions and system responses
            - decision_points: Where the flow branches based on conditions
            - success_outcome: What happens when the flow completes successfully
            - error_paths: How errors are handled at each step
            - related_screens: Which screens are involved in this flow

            Example output:
            ```json
            {
              "spec": {
                "trigger": "사용자가 앱을 처음 실행할 때",
                "steps": [
                  { "order": 1, "actor": "system", "action": "스플래시 화면 표시 (2초)" },
                  { "order": 2, "actor": "system", "action": "로그인 상태 확인" },
                  { "order": 3, "actor": "user", "action": "이메일/비밀번호 입력 후 로그인 탭" }
                ],
                "decision_points": [
                  { "condition": "로그인 상태 확인", "yes": "메인 대시보드로 이동", "no": "로그인 화면 표시" }
                ],
                "success_outcome": "메인 대시보드에 도착하여 콘텐츠 확인 가능",
                "error_paths": [
                  { "at_step": 3, "error": "잘못된 비밀번호", "handling": "에러 메시지 표시 후 재입력 유도" }
                ],
                "related_screens": ["splash", "login", "main-dashboard"]
              },
              "summary": "앱 최초 실행부터 메인 대시보드 진입까지의 온보딩 플로우"
            }
            ```
            """

        default:
            return """
            ## Item Elaboration
            Create a detailed specification for this item. Include all relevant fields
            that would be needed for implementation.
            """
        }
    }

    private func elaborationRelatedItemsContext(_ relatedItems: [DeliverableItem]) -> String? {
        guard !relatedItems.isEmpty else { return nil }
        let relatedContext = relatedItems.map { relItem in
            var desc = "- \(relItem.name)"
            if let brief = relItem.briefDescription { desc += ": \(brief)" }
            if !relItem.spec.isEmpty, let json = try? JSONEncoder().encode(relItem.spec),
               let str = String(data: json, encoding: .utf8) {
                let preview = String(str.prefix(500))
                desc += "\n  Spec: \(preview)"
            }
            return desc
        }.joined(separator: "\n")
        return """

        ## Related Items in Same Section (for cross-reference)
        \(relatedContext)
        """
    }

    private func elaborationCrossSectionContext(
        _ crossSectionItems: [(sectionLabel: String, item: DeliverableItem)]
    ) -> String? {
        guard !crossSectionItems.isEmpty else { return nil }
        let crossContext = crossSectionItems.prefix(20).map { entry in
            var desc = "- [\(entry.sectionLabel)] \(entry.item.name)"
            if let brief = entry.item.briefDescription { desc += ": \(brief)" }
            if !entry.item.spec.isEmpty {
                let keyFields = entry.item.spec.keys.sorted().prefix(5).joined(separator: ", ")
                desc += " (spec keys: \(keyFields))"
            }
            return desc
        }.joined(separator: "\n")
        return """

        ## Completed Items from Other Sections (for consistency)
        \(crossContext)
        """
    }

    /// Section-type-specific required fields schema for elaboration output.
    /// Ensures AI includes all required fields rather than relying on examples alone.
    private func elaborationRequiredFieldsSchema(_ sectionType: String) -> String {
        switch sectionType {
        case "screen-spec":
            return """
            ## Response Schema — screen-spec (ALL fields are REQUIRED)
            ```typescript
            interface ElaborationResult {
              spec: {
                purpose: string;                      // what user accomplishes on this screen
                entry_condition: string;               // how user arrives at this screen
                exit_to: string[];                     // screen names this navigates to
                components: Array<{                    // REQUIRED — every UI element
                  name: string;
                  type: string;
                  role: string;
                  data_source?: string;
                  children?: Array<{name: string; type: string; role: string}>;
                }>;
                interactions: Array<{                  // REQUIRED — user interactions
                  trigger: string;
                  action: string;
                }>;
                states: Record<string, string>;        // REQUIRED — normal, loading, empty, error
                edge_cases: string[];
                api_calls?: Array<{endpoint: string; trigger: string; on_success: string; on_error: string}>;
                state_management?: {local_state: string[]; shared_state: string[]; triggers: string};
                implementation_notes: string;
              };
              summary: string;
            }
            ```
            IMPORTANT: "components", "interactions", and "states" are REQUIRED and must NOT be omitted.
            """
        case "data-model":
            return """
            ## Response Schema — data-model (ALL fields are REQUIRED)
            ```typescript
            interface ElaborationResult {
              spec: {
                description: string;
                fields: Array<{name: string; type: string; required: boolean; description: string; default?: any; validation?: string}>;
                relationships: Array<{entity: string; type: string; description: string; cascade?: string}>;
                indexes: Array<{fields: string[]; unique: boolean}>;
                business_rules: string[];
                access_patterns: string[];
                migration_notes: string;
                implementation_notes: string;
              };
              summary: string;
            }
            ```
            IMPORTANT: "fields", "relationships", and "business_rules" are REQUIRED and must NOT be omitted.
            """
        case "api-spec":
            return """
            ## Response Schema — api-spec (ALL fields are REQUIRED)
            ```typescript
            interface ElaborationResult {
              spec: {
                description: string;
                method: string;
                path: string;
                request_body?: Record<string, any>;
                response: Record<string, any>;
                error_responses: Array<{status: number; description: string}>;
                auth_required: boolean;
                business_rules: string[];
                implementation_notes: string;
              };
              summary: string;
            }
            ```
            IMPORTANT: "method", "path", "response", and "error_responses" are REQUIRED and must NOT be omitted.
            """
        case "user-flow":
            return """
            ## Response Schema — user-flow (ALL fields are REQUIRED)
            ```typescript
            interface ElaborationResult {
              spec: {
                description: string;
                trigger: string;
                steps: Array<{order: number; action: string; screen?: string; outcome: string}>;
                success_condition: string;
                failure_paths: Array<{condition: string; handling: string}>;
                implementation_notes: string;
              };
              summary: string;
            }
            ```
            IMPORTANT: "steps", "success_condition", and "failure_paths" are REQUIRED and must NOT be omitted.
            """
        default:
            return """
            ## Response Schema (TypeScript — your JSON must conform exactly to this)
            ```typescript
            interface ElaborationResult {
              spec: Record<string, any> & {
                implementation_notes: string;
              };
              summary: string;
            }
            ```
            """
        }
    }

    private func elaborationOutputFormat(docDir: String, sectionType: String) -> String {
        """

        ## Pre-flight Check
        Before elaborating, verify internally:
        1. Are all referenced dependencies (items this one depends on) available and clear?
        2. Is the item's scope unambiguous enough to produce a concrete spec?
        3. Does this item conflict with any already-completed items referenced above?
        If any issue is found, raise an uncertainty instead of elaborating with assumptions.

        ## Rules
        - Be thorough and specific. This spec will be used for implementation.
        - Write in the same language as the project task description.
        - Use concrete values (exact colors, sizes, behaviors) rather than vague descriptions.
        - Reference related items by name when describing navigation or relationships.
        - All document outputs should be saved to `\(docDir)/`.
        - Always include an "implementation_notes" field in your spec with practical guidance for the developer:
          - Architectural patterns or constraints to follow
          - Performance considerations (caching, lazy loading, indexing, etc.)
          - Security considerations (input validation, authorization checks, data sanitization)
          - Known dependencies on other items or external services
          - Any non-obvious implementation decisions or trade-offs

        \(PromptFragments.qualityGate)

        \(elaborationRequiredFieldsSchema(sectionType))

        ## Response Format
        You MUST respond with ONLY a single JSON code block. No text before or after the JSON.

        ```json
        {
          "spec": {
            ... all REQUIRED fields for this item type (see schema above) ...,
            "implementation_notes": "practical dev guidance"
          },
          "summary": "1-2 sentence summary of what was specified"
        }
        ```

        CRITICAL RULES:
        - Output ONLY the JSON code block. Do NOT write any text outside it.
        - Do NOT add comments (// or /* */) inside the JSON.
        - The "spec" object MUST contain ALL required fields listed in the schema above. Missing required fields will cause validation failure.
        - Use proper JSON syntax (double quotes, no trailing commas).

        \(PromptFragments.uncertaintyAxiomsText())

        \(elaborationUncertaintyExamples(sectionType: sectionType))

        ## Uncertainty Reporting (optional)
        If a meta-condition above is TRUE, add an [UNCERTAINTIES] block AFTER the JSON code block:

        [UNCERTAINTIES]
        [{"type":"question","priority":"important","title":"인증 방식","body":"소셜 로그인 필요 여부가 불명확합니다.","triggered_by":"missingInput"}]
        [/UNCERTAINTIES]

        - type: "question", "suggestion", "discussion", "information_gap"
        - priority: "blocking" (cannot proceed), "important" (should resolve), "advisory" (nice to know)
        - triggered_by: the axiom name that triggered this uncertainty
        - For "suggestion" type, include "options": ["choice1", "choice2"]
        - Limit to 1-3 per item. The spec JSON block must come first.
        """
    }

    // MARK: - Step Evaluation Prompts

    /// Evaluates whether a step agent completed its task successfully.
    /// - Called by: `DesignWorkflowViewModel.evaluateStepCompletion()`
    /// - Output: JSON with checklist, evidence, confidence, success verdict
    func buildStepCompletionEvaluationPrompt(step: DesignWorkflowStep, truncatedOutput: String) -> String {
        let reviewKeywords = ["review", "QA", "verification", "testing", "check", "inspect"]
        let isReviewStep = reviewKeywords.contains(where: { keyword in
            step.title.localizedCaseInsensitiveContains(keyword) ||
            step.goal.localizedCaseInsensitiveContains(keyword)
        })

        let reviewChecklistItem = isReviewStep ? """

            ### Review/QA Step — Additional Check
            6. `reviewFoundCriticalIssues` (bool): Did the review/QA findings contain critical or major issues?
               - true = the review found critical bugs, failures, or "FAIL" verdicts (even if the review itself ran correctly)
               - false = the review passed with no critical/major issues, or only minor suggestions
        """ : ""

        let reviewVerdictRule = isReviewStep ? """

        - **Review step rule**: If `reviewFoundCriticalIssues` is true, `success` MUST be false — the issues need to be addressed.
        """ : ""

        return """
        You are evaluating whether a step agent completed its task successfully.

        ## Step
        Title: \(step.title)
        Goal: \(step.goal)

        ## Agent Output (first 1000 + last 3000 chars)
        \(truncatedOutput)

        ## Instructions

        Evaluate the output by completing the checklist below FIRST, then determine the verdict.

        ### Checklist (answer each item honestly)
        1. `hasExplicitErrors` (bool): Are there explicit error messages, exceptions, or stack traces?
        2. `hasToolOrInstallFailure` (bool): Did any tool, package, or dependency installation fail?
        3. `hasTestFailure` (bool): Did any test, assertion, or verification fail?
        4. `agentSkippedCriticalPart` (bool): Did the agent admit it skipped or could not complete a critical part of the task?
        5. `criticalDeliverablesPresent` (bool): Are all critical deliverables mentioned in the goal present in the output?
        \(reviewChecklistItem)

        ### Verdict Rules
        - If ANY of items 1-4 is true, or item 5 is false -> `success` should be false
        - EXCEPTION: Minor warnings that don't affect the deliverable are NOT errors (item 1 = false)
        - EXCEPTION: Alternative valid approaches that achieve the goal are acceptable (item 5 = true)
        - EXCEPTION: Output being shorter than expected but achieving the goal is acceptable
        \(reviewVerdictRule)

        ### Evidence
        Quote 1-2 lines from the agent output that most strongly support your verdict.

        ## Response Schema (TypeScript — your JSON must conform exactly to this)
        ```typescript
        interface StepEvaluation {
          checklist: {
            hasExplicitErrors: boolean;
            hasToolOrInstallFailure: boolean;
            hasTestFailure: boolean;
            agentSkippedCriticalPart: boolean;
            criticalDeliverablesPresent: boolean;
          };
          evidence: string;
          confidence: "high" | "medium" | "low";
          success: boolean;
          failureCategory?: "error_message" | "tool_failure" | "test_failure" | "incomplete" | "wrong_approach";
          failureReason?: string;
          suggestedFix?: string;
        }
        ```

        ## Response Format
        Respond with ONLY valid JSON:
        ```json
        {
          "checklist": {
            "hasExplicitErrors": false,
            "hasToolOrInstallFailure": false,
            "hasTestFailure": false,
            "agentSkippedCriticalPart": false,
            "criticalDeliverablesPresent": true
          },
          "evidence": "Quoted text from output supporting the verdict",
          "confidence": "high",
          "success": true
        }
        ```

        If the step failed, also include `failureCategory`, `failureReason`, `suggestedFix`.
        """
    }

    /// Evaluates whether the Design can resolve a decision autonomously or must escalate.
    /// - Output: JSON with `canResolve`, `chosenOption`, `reasoning`
    func buildDecisionEvaluationPrompt(decision: DesignDecision, step: DesignWorkflowStep) -> String {
        let optionsList = decision.options.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        return """
        \(PromptFragments.designOfficeIdentityCompact)

        A step agent has raised a decision during their work.
        Evaluate whether you can resolve this yourself or if it requires the client's judgment.

        ## Task Context
        \(workflow?.taskDescription ?? "")

        ## Step That Raised the Decision
        Title: \(step.title)
        Description: \(step.description)
        Output so far:
        \(String(step.output.suffix(2000)))

        ## Decision
        Title: \(decision.title)
        Body: \(decision.body)

        ## Options
        \(optionsList)

        ## Rules
        - If this is something you can resolve based on project context, resolve it yourself.
        - If this truly requires the client's judgment, escalate it.
        - Write your response in the same language as the task description.

        ## Response Schema (TypeScript — your JSON must conform exactly to this)
        ```typescript
        type DecisionEvaluation =
          | { canResolve: true; chosenOption: string; reasoning: string }
          | { canResolve: false; reasoning: string };
        ```

        ## Response Format
        Respond with ONLY valid JSON:
        ```json
        {
          "canResolve": true,
          "chosenOption": "The exact option text you chose",
          "reasoning": "Brief explanation of why you chose this"
        }
        ```
        Or if the client must decide:
        ```json
        {
          "canResolve": false,
          "reasoning": "Why this needs the client's judgment"
        }
        ```
        """
    }

    /// Generates an alternative step approach after a step has failed.
    /// - Output: JSON with `title`, `description`, `goal`, `promptTemplate`
    func buildReplacementStepPrompt(failedStep: DesignWorkflowStep, workflowContext: DesignWorkflow?) -> String {
        let completedStepsContext: String = {
            guard let wf = workflowContext else { return "" }
            return wf.steps
                .filter { $0.status == .completed }
                .map { "- Step \($0.sequence): \($0.title) — \($0.structuredOutput?.summary ?? String($0.output.prefix(200)))" }
                .joined(separator: "\n")
        }()

        let taskDesc = workflowContext?.taskDescription ?? ""
        let hasNonLatin = taskDesc.unicodeScalars.contains(where: { !$0.isASCII && CharacterSet.letters.contains($0) })
        let lang = hasNonLatin ? "same language as the original task description" : "English"

        return """
        \(PromptFragments.designOfficeIdentityCompact)

        A workflow step has failed and the client wants to REPLACE it with an alternative approach.

        ## Failed Step
        Title: \(failedStep.title)
        Description: \(failedStep.description)
        Goal: \(failedStep.goal)

        ## Failure Information
        Failure reason: \(failedStep.lastFailureReason ?? "Unknown")
        Last output (last 1500 chars): \(String(failedStep.output.suffix(1500)))

        ## Workflow Context
        Overall task: \(workflowContext?.designSummary ?? workflowContext?.taskDescription ?? "")
        \(!completedStepsContext.isEmpty ? "Completed steps:\n\(completedStepsContext)" : "")

        ## Instructions
        Design a REPLACEMENT step that achieves a similar goal but uses a fundamentally different approach.
        - Avoid the approach that failed.
        - Keep the replacement focused and achievable in a single step.
        - Write all text in \(lang).

        ## Response Schema (TypeScript — your JSON must conform exactly to this)
        ```typescript
        interface ReplacementStep {
          title: string;
          description: string;
          goal: string;
          promptTemplate: string;
        }
        ```

        ## Response Format
        Respond with ONLY valid JSON (no markdown fences):
        {
          "title": "New step title (concise)",
          "description": "What this replacement step does differently",
          "goal": "What this step should achieve",
          "promptTemplate": "Complete detailed instructions for the executing agent"
        }
        """
    }

    // MARK: - Consistency Verification Prompt

    /// Builds a prompt for Design to verify deliverable consistency before completion.
    /// - Output: Text-based consistency report (under 300 words)
    // MARK: - CPS Document (after Approach Selection)

    // MARK: - Consistency Check

    func buildConsistencyCheckPrompt(deliverables: [DeliverableSection]) -> String {
        var parts: [String] = []

        parts.append("""
        \(PromptFragments.designOfficeIdentity)\(PromptFragments.userContext(userProfile))

        You are performing a final consistency check before the design is handed off to developers.
        This is the last gate — nothing leaves the office without passing this review.
        """)

        if let wf = workflow {
            parts.append("## Task\n\(wf.taskDescription)")
        }

        parts.append("## Deliverables to Check")
        for section in deliverables {
            parts.append("### \(section.label) (\(section.completedCount)/\(section.totalCount) completed)")
            for item in section.items {
                if !item.spec.isEmpty, let data = try? JSONEncoder().encode(item.spec),
                   let str = String(data: data, encoding: .utf8) {
                    parts.append("#### \(item.name) [\(item.status.rawValue)]\n\(String(str.prefix(2000)))")
                } else {
                    parts.append("#### \(item.name) [\(item.status.rawValue)] — no spec yet")
                }
            }
        }

        parts.append("""
        ## Check For
        1. Missing items: Are there screens/models/endpoints that should exist but don't?
        2. Broken references: Do items reference other items that don't exist?
        3. Incomplete items: Are any items still pending that should be completed?
        4. Inconsistencies: Do any items contradict each other?

        \(PromptFragments.qualityGate)

        ## Response Format
        Respond with a JSON object:
        - "issues": array of issues found (empty array if none)
          - "id": stable identifier like "issue-1", "issue-2"
          - "severity": "critical" | "warning" | "info"
          - "category": "missing_item" | "broken_reference" | "incomplete_item" | "inconsistency"
          - "description": what the issue is
          - "affectedItems": list of item names involved
          - "suggestedFix": what should be done to fix it
        - "summary": one-sentence overall assessment

        Write descriptions and summary in the same language as the task description.
        If everything is consistent, return an empty issues array with a positive summary.
        """)

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Consistency Discussion Prompt

    /// Builds a prompt for discussing consistency issues and proposing concrete fix actions.
    func buildConsistencyDiscussPrompt(
        issues: [ConsistencyIssue],
        chatHistory: [DesignChatMessage],
        userMessage: String,
        deliverables: [DeliverableSection]
    ) -> String {
        var parts: [String] = []

        parts.append(orchestrationRoleSection())
        parts.append(orchestrationProjectContext())

        // Consistency issues context
        let issueLines = issues.enumerated().map { i, issue in
            """
            \(i + 1). [\(issue.severity.uppercased())] \(issue.description)
               Category: \(issue.category)
               Affected: \(issue.affectedItems.joined(separator: ", "))
               Suggested fix: \(issue.suggestedFix)
            """
        }.joined(separator: "\n")

        parts.append("""
        ## Consistency Issues to Fix
        The following issues were found during the final consistency review:

        \(issueLines)
        """)

        if let delSection = orchestrationDeliverablesSection(deliverables) {
            parts.append(delSection)
        }
        if let relSection = orchestrationRelationshipsSection() {
            parts.append(relSection)
        }
        if let chatSection = orchestrationChatHistorySection(chatHistory) {
            parts.append(chatSection)
        }

        parts.append("""
        ## Current User Message
        \(userMessage)

        ## Your Task
        Review the consistency issues and propose concrete fix actions.
        For each issue, explain what you'll do and propose actions to fix it.
        Use the standard action types: elaborate_item, update_item, add_item, remove_item, link_items, unlink_items.

        \(orchestrationResponseFormat())
        """)

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Uncertainty Triage Prompt

    /// Builds a prompt for Design to triage uncertainties surfaced by a Step agent.
    /// Design decides whether to resolve autonomously or escalate to the client.
    /// - Output: JSON array of `{index, action, reasoning}` triage decisions
    func buildUncertaintyTriagePrompt(
        uncertainties: [DesignAnalysisResponse.UncertaintySpec],
        item: DeliverableItem,
        sectionType: String
    ) -> String {
        let uncertaintyJSON = uncertainties.enumerated().map { (i, u) in
            """
            \(i + 1). [\(u.type)] \(u.title)
               \(u.body)\(u.options.map { "\n   Options: \($0.joined(separator: ", "))" } ?? "")
            """
        }.joined(separator: "\n")

        let resolvedContext: String = {
            guard let wf = workflow else { return "" }
            let resolved = wf.uncertainties.filter { $0.status != .pending }
            guard !resolved.isEmpty else { return "" }
            let lines = resolved.prefix(10).map { d in
                "- \(d.title): \(d.userResponse ?? d.selectedOption ?? d.autonomousReasoning ?? "resolved")"
            }.joined(separator: "\n")
            return "\n## Previously Resolved Uncertainties\n\(lines)"
        }()

        return """
        \(PromptFragments.designOfficeIdentityCompact)

        You are reviewing uncertainties raised by a step agent during elaboration of "\(item.name)" (\(sectionType)).

        ## Step Agent Uncertainties
        \(uncertaintyJSON)

        ## Project Context
        Task: \(workflow?.taskDescription ?? taskInput)
        \(workflow?.projectSpec.map { "Project: \($0.name) (\($0.type))" } ?? "")\(resolvedContext)

        \(PromptFragments.triageCriteria())

        ## Professional Judgment Boundary
        These are YOUR professional decisions (resolve autonomously):
        - Technical implementation choices (caching, pagination, indexing, hash algorithms)
        - UI pattern selection when industry standards exist (modal vs page, tab vs accordion)
        - Error handling strategies (retry policy, fallback behavior)
        - Data validation rules (format, length, range — not business rules)
        - Security basics (input validation, token handling)

        These MUST be escalated to the client:
        - Product direction (B2B vs B2C, MVP scope, target users)
        - Business rules (pricing, permissions, content policies)
        - Feature priority (what first, what later, what never)
        - Core UX decisions (onboarding approach, key flow branch points)

        ## Your Task
        For each uncertainty, decide:
        1. **autonomous_resolve** — You have enough context to answer this yourself. Provide your reasoning.
        2. **escalate_to_client** — This requires the client's input. Keep the original type and priority.

        ## Response Schema (TypeScript — your JSON must conform exactly to this)
        ```typescript
        type TriageResult = TriageDecision[];
        type TriageDecision =
          | { index: number; action: "autonomous_resolve"; reasoning: string }
          | { index: number; action: "escalate_to_client" };
        ```

        ## Response Format
        Respond with ONLY a JSON array:
        ```json
        [
          {
            "index": 1,
            "action": "autonomous_resolve",
            "reasoning": "프로젝트 스펙에 iOS 앱으로 명시되어 있어 Apple 로그인은 필수입니다."
          },
          {
            "index": 2,
            "action": "escalate_to_client"
          }
        ]
        ```
        """
    }

    // MARK: - Analysis Helpers (private)

    /// Decoded shape for Design Brief JSON from idea exploration.
    private struct DecodedBrief: Codable {
        struct KeyDecision: Codable {
            let topic: String
            let chosen: String
            let alternatives: [String]?
            let rationale: String
        }
        struct BRD: Codable {
            let problemStatement: String?
            let targetUsers: [TargetUser]?
            let businessObjectives: [String]?
            let scope: Scope?
            let constraints: [String]?
        }
        struct TargetUser: Codable {
            let name: String
            let description: String?
            let needs: [String]?
        }
        struct Scope: Codable {
            let inScope: [String]?
            let outOfScope: [String]?
            let mvpBoundary: String?
        }
        struct DecodedExecutionLimitation: Codable {
            let area: String
            let description: String
            let workaroundHint: String?
        }
        struct DecodedExecutionContext: Codable {
            let currentLimitations: [DecodedExecutionLimitation]?
        }
        let synthesisDirection: String?
        let synthesisRationale: String?
        let keyDecisions: [KeyDecision]?
        let brd: BRD?
        let executionContext: DecodedExecutionContext?
    }

    /// Wraps the Brief JSON in `{"brief": ...}` envelope for decoding.
    private struct BriefEnvelope: Codable {
        let brief: DecodedBrief
    }

    /// Build a structured context block from Design Brief JSON.
    /// Returns empty string if Brief is unavailable or unparseable.
    private func briefContextBlock() -> String {
        guard let json = designBriefJSON,
              let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(BriefEnvelope.self, from: data) else { return "" }
        let brief = envelope.brief

        var lines: [String] = ["## Design Brief (from Exploration)"]
        lines.append("This Brief is the primary input — it captures what was explored, decided, and scoped.")
        lines.append("")

        if let dir = brief.synthesisDirection {
            lines.append("**Direction**: \(dir)")
        }
        if let rationale = brief.synthesisRationale {
            lines.append("**Rationale**: \(rationale)")
        }

        if let decisions = brief.keyDecisions, !decisions.isEmpty {
            lines.append("")
            lines.append("### Key Decisions")
            for d in decisions {
                lines.append("- **\(d.topic)**: \(d.chosen) — \(d.rationale)")
            }
        }

        if let brd = brief.brd {
            lines.append("")
            lines.append("### Requirements")
            if let problem = brd.problemStatement {
                lines.append("**Problem**: \(problem)")
            }
            if let users = brd.targetUsers, !users.isEmpty {
                lines.append("**Target Users**: " + users.map { $0.name }.joined(separator: ", "))
            }
            if let objectives = brd.businessObjectives, !objectives.isEmpty {
                lines.append("**Objectives**: " + objectives.joined(separator: "; "))
            }
            if let scope = brd.scope {
                if let inScope = scope.inScope, !inScope.isEmpty {
                    lines.append("**In Scope**: " + inScope.joined(separator: ", "))
                }
                if let outScope = scope.outOfScope, !outScope.isEmpty {
                    lines.append("**Out of Scope**: " + outScope.joined(separator: ", "))
                }
                if let mvp = scope.mvpBoundary {
                    lines.append("**MVP Boundary**: \(mvp)")
                }
            }
            if let constraints = brd.constraints, !constraints.isEmpty {
                lines.append("**Constraints**: " + constraints.joined(separator: "; "))
            }
        }

        if let ctx = brief.executionContext,
           let limitations = ctx.currentLimitations, !limitations.isEmpty {
            lines.append("")
            lines.append("### Execution Context — Current Limitations")
            lines.append("These are current conditions of the AI execution environment. " +
                         "For each limitation, the design MUST include a concrete workaround, " +
                         "graceful degradation path, or manual-step placeholder.")
            for lim in limitations {
                var line = "- **\(lim.area)**: \(lim.description)"
                if let hint = lim.workaroundHint {
                    line += " (Suggested workaround: \(hint))"
                }
                lines.append(line)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func analysisGraphHint(_ preExtractedGraph: String?) -> String {
        guard let json = preExtractedGraph,
              let data = json.data(using: .utf8),
              let graph = try? JSONDecoder().decode(PreExtractedGraph.self, from: data),
              !graph.entities.isEmpty else { return "" }
        let entityLines = graph.entities.map { "- \($0.name) (\($0.type)): \($0.description)" }.joined(separator: "\n")
        let relLines = graph.relationships.map { "- \($0.sourceName) → \($0.targetName) (\($0.relationType))" }.joined(separator: "\n")

        var refSection = ""
        if let refs = graph.referenceAnchors, !refs.isEmpty {
            let refLines = refs.map { "- **\($0.productName)** (\($0.category)): \($0.aspect)" }
            refSection = """

            ## Reference Anchors (from Exploration)
            These define the project's visual and experiential direction.
            Ground each approach in these references.

            \(refLines.joined(separator: "\n"))
            """
        }

        return """

        ## Pre-extracted Entities and Relationships (from IdeaBoard)
        These were identified during idea exploration. Use as a starting point — include them in your deliverables \
        and relationships if relevant. You may add, modify, or omit based on your analysis.

        Entities:
        \(entityLines)
        \(relLines.isEmpty ? "" : "\nRelationships:\n\(relLines)")\(refSection)
        """
    }

    /// Build re-analysis context section for the analysis prompt.
    private func reanalysisContext(feedback: String?, previousSummary: String?) -> String {
        guard feedback != nil || previousSummary != nil else { return "" }
        var block = "\n\n## Re-analysis Context\n"
        block += "This is a RE-ANALYSIS. The client reviewed the previous result and wants changes.\n"
        if let summary = previousSummary {
            block += "\n### Previous Analysis\n\(summary)\n"
        }
        if let fb = feedback {
            block += "\n### Client Feedback\n\(fb)\n"
            block += "\nAddress this feedback directly. Adjust approaches, scope, or deliverables accordingly.\n"
        }
        return block
    }

    // MARK: - Uncertainty Example Helpers

    /// Layer 2 — Analysis phase uncertainty examples.
    private func analysisUncertaintyExamples() -> String {
        """
        ### Uncertainty Examples (Analysis Phase)
        - multipleInterpretations: "로그인" could mean email/password only, or include social login and biometric — different screen structures result.
        - missingInput: Task says "결제 기능" but no payment provider is specified — cannot determine API integration scope.
        - conflictsWithAgreement: Task mentions "실시간 채팅" but an approved item already uses polling for notifications.
        - ungroundedAssumption: You're designing an "admin dashboard" with role-based access, but no role hierarchy was described.
        - notVerifiable: "사용하기 쉬운 UI" — no measurable criteria to verify.
        """
    }

    /// Layer 2 — Section-type-specific uncertainty examples for elaboration.
    private func elaborationUncertaintyExamples(sectionType: String) -> String {
        switch sectionType {
        case "screen-spec":
            return """
            ### Uncertainty Examples (Screen Spec)
            - multipleInterpretations: "목록 화면" — card layout vs table layout lead to different component trees.
            - missingInput: No error state design is described — cannot specify error UI components.
            - referenceGap: Existing reference images don't cover this screen's visual direction — additional reference needed. Include suggestedSearchQuery in the uncertainty body.
            """
        case "data-model":
            return """
            ### Uncertainty Examples (Data Model)
            - missingInput: Relationship cardinality between User and Organization is not specified.
            - conflictsWithAgreement: A "soft delete" field conflicts with the approved API spec that uses hard deletes.
            """
        case "api-spec":
            return """
            ### Uncertainty Examples (API Spec)
            - multipleInterpretations: "인증" could mean session-based or token-based — different request/response structures.
            - ungroundedAssumption: Assuming pagination defaults (page=1, limit=20) without specification.
            """
        case "user-flow":
            return """
            ### Uncertainty Examples (User Flow)
            - notVerifiable: "빠르게 완료" — no measurable criterion for step count or time.
            - missingInput: Error recovery path not described — cannot specify what happens on payment failure.
            """
        default:
            return """
            ### Uncertainty Examples
            - missingInput: Required context is not available for this item type.
            - multipleInterpretations: The requirement could lead to meaningfully different implementations.
            """
        }
    }

    /// Layer 2 — Chat phase uncertainty examples.
    private func chatUncertaintyExamples() -> String {
        """
        ### Uncertainty Examples (Chat)
        - multipleInterpretations: User says "이거 바꿔주세요" — could mean rename, redesign, or remove.
        - conflictsWithAgreement: User requests a change that conflicts with a previously approved item.
        - highImpactIfWrong: A scope change that would affect multiple approved items — raise with elevated priority.
        """
    }

}

// MARK: - JSON Schemas for CLI Output Enforcement (--output-schema / --output-format json)

// MARK: - JSON Schemas for OpenAI Structured Output
//
// OpenAI Structured Output rules:
// 1. All objects must have "additionalProperties": false
// 2. All keys in "properties" must appear in "required"
// 3. Dynamic objects (additionalProperties as type) are not supported
//
// Fields removed due to rule 3:
//   - analysis: projectSpec.techStack (dynamic key-value object)
//   - skeleton: item.components (dynamic key-value object)
//   - chat: action.changes (untyped bare object)
// These fields are optional in decoders and still returned by non-Codex providers.

enum DesignJSONSchemas {

    /// Schema for DesignAnalysisResponse
    /// Omits: projectSpec.techStack (dynamic object incompatible with strict mode)
    static let analysis = """
    {"type":"object","properties":{"projectSpec":{"type":"object","properties":{"name":{"type":"string"},"type":{"type":"string"}},"required":["name","type"],"additionalProperties":false},"hiddenRequirements":{"type":"array","items":{"type":"string"}},"approaches":{"type":"array","items":{"type":"object","properties":{"label":{"type":"string"},"summary":{"type":"string"},"pros":{"type":"array","items":{"type":"string"}},"cons":{"type":"array","items":{"type":"string"}},"risks":{"type":"array","items":{"type":"string"}},"estimatedComplexity":{"type":"string","enum":["low","medium","high"]},"recommended":{"type":"boolean"},"reasoning":{"type":"string"},"sectionTypes":{"type":"array","items":{"type":"string"}}},"required":["label","summary","pros","cons","risks","estimatedComplexity","recommended","reasoning","sectionTypes"],"additionalProperties":false}},"message":{"type":"string"}},"required":["projectSpec","hiddenRequirements","approaches","message"],"additionalProperties":false}
    """

    /// Schema for DesignSkeletonResponse
    /// Components use fixed keys {"type","name"} per prompt spec.
    static let skeleton = """
    {"type":"object","properties":{"deliverables":{"type":"array","items":{"type":"object","properties":{"type":{"type":"string"},"label":{"type":"string"},"items":{"type":"array","items":{"type":"object","properties":{"name":{"type":"string"},"briefDescription":{"type":"string"},"parallelGroup":{"type":"integer"},"plannerQuestion":{"type":"string"},"scenarioGroup":{"type":"string"},"components":{"type":"array","items":{"type":"object","properties":{"type":{"type":"string"},"name":{"type":"string"}},"required":["type","name"],"additionalProperties":false}},"purpose":{"type":"string"}},"required":["name","briefDescription","parallelGroup","plannerQuestion","scenarioGroup","components","purpose"],"additionalProperties":false}}},"required":["type","label","items"],"additionalProperties":false}}},"required":["deliverables"],"additionalProperties":false}
    """

    /// Schema for DesignSkeletonGraphResponse
    static let skeletonGraph = """
    {"type":"object","properties":{"relationships":{"type":"array","items":{"type":"object","properties":{"sourceName":{"type":"string"},"targetName":{"type":"string"},"relationType":{"type":"string"}},"required":["sourceName","targetName","relationType"],"additionalProperties":false}},"uncertainties":{"type":"array","items":{"type":"object","properties":{"type":{"type":"string"},"priority":{"type":"string"},"title":{"type":"string"},"body":{"type":"string"},"options":{"type":"array","items":{"type":"string"}},"relatedItemName":{"type":"string"},"triggeredBy":{"type":"string"}},"required":["type","priority","title","body","options","relatedItemName","triggeredBy"],"additionalProperties":false}}},"required":["relationships","uncertainties"],"additionalProperties":false}
    """

    /// Schema for skeleton relationships only (split from skeletonGraph)
    static let skeletonRelationships = """
    {"type":"object","properties":{"relationships":{"type":"array","items":{"type":"object","properties":{"sourceName":{"type":"string"},"targetName":{"type":"string"},"relationType":{"type":"string"}},"required":["sourceName","targetName","relationType"],"additionalProperties":false}}},"required":["relationships"],"additionalProperties":false}
    """

    /// Schema for skeleton uncertainties only (split from skeletonGraph)
    static let skeletonUncertainties = """
    {"type":"object","properties":{"uncertainties":{"type":"array","items":{"type":"object","properties":{"type":{"type":"string"},"priority":{"type":"string"},"title":{"type":"string"},"body":{"type":"string"},"options":{"type":"array","items":{"type":"string"}},"relatedItemName":{"type":"string"},"triggeredBy":{"type":"string"}},"required":["type","priority","title","body","options","relatedItemName","triggeredBy"],"additionalProperties":false}}},"required":["uncertainties"],"additionalProperties":false}
    """

    /// Schema for ConsistencyCheckResponse
    static let consistencyCheck = """
    {"type":"object","properties":{"issues":{"type":"array","items":{"type":"object","properties":{"id":{"type":"string"},"severity":{"type":"string"},"category":{"type":"string"},"description":{"type":"string"},"affectedItems":{"type":"array","items":{"type":"string"}},"suggestedFix":{"type":"string"}},"required":["id","severity","category","description","affectedItems","suggestedFix"],"additionalProperties":false}},"summary":{"type":"string"}},"required":["issues","summary"],"additionalProperties":false}
    """

    /// Schema for DesignChatResponse
    /// Omits: action.changes (untyped object incompatible with strict mode)
    static let chat = """
    {"type":"object","properties":{"message":{"type":"string"},"actions":{"type":"array","items":{"type":"object","properties":{"type":{"type":"string"},"sectionType":{"type":"string"},"itemId":{"type":"string"},"itemName":{"type":"string"},"sectionLabel":{"type":"string"},"items":{"type":"array","items":{"type":"object","properties":{"name":{"type":"string"},"briefDescription":{"type":"string"}},"required":["name","briefDescription"],"additionalProperties":false}},"agentId":{"type":"string"},"sourceItemId":{"type":"string"},"targetItemId":{"type":"string"},"relationType":{"type":"string"},"uncertaintyType":{"type":"string"},"priority":{"type":"string"},"title":{"type":"string"},"body":{"type":"string"},"options":{"type":"array","items":{"type":"string"}},"triggeredBy":{"type":"string"}},"required":["type","sectionType","itemId","itemName","sectionLabel","items","agentId","sourceItemId","targetItemId","relationType","uncertaintyType","priority","title","body","options","triggeredBy"],"additionalProperties":false}}},"required":["message","actions"],"additionalProperties":false}
    """

    /// Schema for triage results
    static let triage = """
    {"type":"object","properties":{"results":{"type":"array","items":{"type":"object","properties":{"index":{"type":"integer"},"action":{"type":"string"},"reasoning":{"type":"string"}},"required":["index","action","reasoning"],"additionalProperties":false}}},"required":["results"],"additionalProperties":false}
    """

    /// Schema for agent assignment
    static let agentAssignment = """
    {"type":"object","properties":{"assignments":{"type":"array","items":{"type":"object","properties":{"itemId":{"type":"string"},"agentId":{"type":"string"}},"required":["itemId","agentId"],"additionalProperties":false}}},"required":["assignments"],"additionalProperties":false}
    """

    /// Schema for step completion evaluation
    static let stepCompletionEval = """
    {"type":"object","properties":{"complete":{"type":"boolean"},"confidence":{"type":"number"},"reasoning":{"type":"string"},"missingElements":{"type":"array","items":{"type":"string"}},"suggestions":{"type":"array","items":{"type":"string"}}},"required":["complete","confidence","reasoning","missingElements","suggestions"],"additionalProperties":false}
    """

    /// Schema for decision evaluation
    static let decisionEval = """
    {"type":"object","properties":{"decision":{"type":"string"},"confidence":{"type":"number"},"reasoning":{"type":"string"}},"required":["decision","confidence","reasoning"],"additionalProperties":false}
    """
}
