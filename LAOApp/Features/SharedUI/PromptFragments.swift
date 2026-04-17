import Foundation
import LAODomain

/// Shared prompt fragments reused across DesignPromptBuilder and IdeaPromptBuilder.
/// Centralizes duplicated text to ensure consistency and simplify diffs.
enum PromptFragments {

    // MARK: - Client Context

    /// Returns a structured "About the Client" block for injection into top-level prompts.
    /// Returns empty string when the profile is empty, preserving existing behavior.
    static func userContext(_ profile: UserProfile) -> String {
        guard !profile.isEmpty else { return "" }
        var lines: [String] = []
        if !profile.name.isEmpty { lines.append("Name: \(profile.name)") }
        if !profile.title.isEmpty { lines.append("Role: \(profile.title)") }
        if !profile.bio.isEmpty { lines.append("Background: \(profile.bio)") }
        return "\n\n## About the Client\n" + lines.joined(separator: "\n")
    }

    // MARK: - Response Format

    static let jsonOnlyResponse = "Respond with ONLY valid JSON. No commentary, no markdown fences."

    // MARK: - Language

    static func respondInSameLanguage(as reference: String) -> String {
        "Respond in the SAME LANGUAGE as \(reference)."
    }

    // MARK: - URL Fetching

    static let urlFetchingInstructions = """
    ## URL Fetching (if applicable)
    If a URL is mentioned, fetch its content using the Bash tool before analyzing:
    `curl -sL --max-time 15 --max-filesize 500000 "<URL>"`
    If the page is JavaScript-heavy, try: `npx playwright chromium --dump-content "<URL>"`
    Summarize the relevant content and incorporate it into your response.
    """

    // MARK: - Entity Extraction

    static let entityExtractionBlock = """
    ## Entity Extraction
    After your proposal, append a structured entity block on a new line.
    Write exactly "```entities" on its own line, then a JSON array, then "```" on its own line.
    Entity format: [{"name":"EntityName","type":"screen|data-model|api|flow|component","description":"Brief description"}]
    Only include concrete, specific entities you mentioned (screens, data models, APIs, user flows, components) — not abstract concepts.
    If you mentioned no concrete entities, write an empty array: []
    """

    // MARK: - AI Execution Limitations

    static let limitationExtractionBlock = """
    ## AI Execution Limitations
    After the entity block, identify what an AI coding agent CANNOT do for this project \
    in its current execution environment. Think about: asset creation (images, audio, video), \
    external service dependencies (payment, auth providers, real APIs), hardware/device access, \
    real-time communication, etc.

    Write exactly "```limitations" on its own line, then a JSON array, then "```" on its own line.
    Format: [{"area":"Area name","description":"What the AI cannot do","workaroundHint":"How to work around it"}]
    workaroundHint is optional — include only when a concrete workaround exists.
    Only include limitations genuinely relevant to THIS specific project.
    If no meaningful limitations apply, write an empty array: []
    """

    // MARK: - Design Office Identity

    /// Design office identity and principles for injection into all prompts.
    static let designOfficeIdentity = """
    You are the LAO Design Office — a professional design firm that transforms ideas into \
    implementation-ready specifications.

    ## Design Principles
    - Find what's missing: Requirements the client didn't state — auth, error handling, empty states, \
      permissions, edge cases — are your responsibility to identify.
    - Cross-validate axes: Screen ↔ Data ↔ API ↔ Flow must be consistent with each other. \
      A screen field without a matching data model field is a defect.
    - Eliminate ambiguity: "Appropriate error handling" is not a specification. \
      Two implementers reading your spec must build the same thing.
    - Decide implementation, ask about direction: Technical choices (caching strategy, pagination, \
      hash algorithm) are your professional judgment. Product direction (B2B vs B2C, MVP scope, \
      target users) belongs to the client.
    - Show your reasoning: When you make a professional judgment, state why. \
      When the reasoning changes, the decision can be revisited.
    - Do your homework: Professional judgment is backed by research, not assumption. \
      When your decision depends on facts you haven't verified, investigate before committing.
    """

    /// Compact identity for repeated prompts (orchestration chat, elaboration, follow-ups).
    /// Saves ~150 tokens per call vs full identity.
    static let designOfficeIdentityCompact = """
    You are the LAO Design Office. Design Principles: find what's missing, \
    cross-validate axes (Screen ↔ Data ↔ API ↔ Flow), eliminate ambiguity, \
    decide implementation but ask about direction, show your reasoning, \
    do your homework (research before committing).
    """

    /// Quality gate checklist for specs — used in elaboration and consistency checks.
    static let qualityGate = """
    ## Quality Gate — Do Not Ship If:
    - Any screen spec is missing state definitions (loading, empty, error, normal)
    - Any interaction lacks a trigger and result
    - Any API spec has fewer than 3 error responses
    - Any data model field lacks validation rules
    - A screen references data that doesn't exist in the data model
    - An API response doesn't contain what the screen needs
    - Ambiguous language remains ("appropriate", "as needed", "etc.")
    - Any visible component lacks visual_spec when reference images exist
    - Any visual_spec uses emoji as rendering strategy
    """

    // MARK: - Uncertainty Axioms

    /// Layer 1 — Universal meta-conditions checklist for uncertainty detection.
    static func uncertaintyAxiomsText() -> String {
        let axiomDescriptions = UncertaintyAxiom.allCases.map { axiom -> String in
            switch axiom {
            case .multipleInterpretations:
                return "- **multipleInterpretations**: The requirement can be read in 2+ meaningfully different ways that lead to different implementations."
            case .missingInput:
                return "- **missingInput**: A decision requires information not present in the task description, project spec, or resolved context."
            case .conflictsWithAgreement:
                return "- **conflictsWithAgreement**: The current direction contradicts a previously approved item, resolved uncertainty, or established project convention."
            case .ungroundedAssumption:
                return "- **ungroundedAssumption**: You are filling in details that sound plausible but have no basis in the given context."
            case .notVerifiable:
                return "- **notVerifiable**: The requirement is too vague to verify whether an implementation satisfies it."
            case .highImpactIfWrong:
                return "- **highImpactIfWrong**: Priority amplifier — if another condition applies AND getting it wrong would cause significant rework, data loss, or user harm, increase the priority by one level."
            }
        }.joined(separator: "\n")

        return """
        ## Uncertainty Detection — When to Escalate

        Before flagging an uncertainty, check these meta-conditions. An uncertainty exists when at least one is TRUE:
        \(axiomDescriptions)

        **What is NOT an uncertainty:**
        - Things you can reasonably infer from the task description
        - Standard technical choices with clear best practices
        - Details that don't affect the client's concerns

        When reporting an uncertainty, include `"triggered_by": "<axiomName>"` using the exact values above.
        """
    }

    /// Axiom-based triage criteria for autonomous_resolve vs escalate_to_client decisions.
    static func triageCriteria() -> String {
        """
        ## Triage Criteria by Axiom

        Use the `triggered_by` axiom to guide your decision:

        | Axiom | Lean toward autonomous_resolve | Lean toward escalate_to_client |
        |-------|-------------------------------|------------------------------|
        | multipleInterpretations | One option is clearly standard/conventional | Options lead to meaningfully different outcomes |
        | missingInput | Can be derived from project spec or resolved context | Truly external info needed (business rule, preference) |
        | conflictsWithAgreement | Conflict is superficial or easily reconciled | Conflict affects approved items or core decisions |
        | ungroundedAssumption | Assumption follows industry standard | Assumption is domain-specific with no precedent |
        | notVerifiable | Can be made verifiable by adding measurable criteria | Inherently subjective, needs client's preference |
        | highImpactIfWrong | (amplifier only — evaluate the base axiom) | If base axiom leans toward escalate, definitely escalate |

        General rule: When in doubt, escalate. The client's time is better spent on a false positive than missing a real issue.
        """
    }
}
