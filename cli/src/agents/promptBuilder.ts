import { ProjectConfig, SpecSection, DecisionCard, NodeMessage, GoldenRules } from '../models';

export class PromptBuilder {

  /**
   * Builds prompt for the Director to route user message to appropriate agent
   */
  public static buildDirectorRoutingPrompt(params: {
    config: ProjectConfig;
    chatHistory: NodeMessage[];
    userMessage: string;
  }): string {
    const historyBlock = this.chatHistorySection(params.chatHistory);
    return `
You are the **Director** — you do NOT answer the client directly. Your only job is to read the client's latest message in the context of the current project specification and decide which of the four step agents should respond.

## The Four Step Agents
- **specifier**: sharpens vague specifications, refines feature wording, details APIs. Pick when the client asks to write/extend/refine specs, detail requirements, or make designs concrete.
- **researcher**: surfaces similar examples, industry standards, library conventions. Pick when the client asks "how is this normally done", "any libraries for this", or asks for code patterns.
- **optionizer**: presents distinct options or alternative angles. Pick when the client is undecided, asks for alternatives, or wants to make architectural choices.
- **gapDetector**: surfaces implicit assumptions, missing aspects, blind spots. Pick when the client asks "what am I missing", "any bugs/holes in the spec", or when verifying consistency.

Respond with ONLY valid JSON matching this shape:
{"route": "specifier|researcher|optionizer|gapDetector", "reasoning": "<one short sentence>"}
No commentary, no markdown fences.

## Project Context
Project: ${params.config.projectName}
Description: ${params.config.projectDesc}
Golden Rules:
- Frontend: ${params.config.goldenRules.frontend}
- Backend: ${params.config.goldenRules.backend}
- Database: ${params.config.goldenRules.database}
- Additional Constraints: ${params.config.goldenRules.additional}

${historyBlock}

## Client's Latest Message
${params.userMessage}
`;
  }

  /**
   * Prompts the Specifier to translate a rough idea into draft specs (core spec + features)
   */
  public static buildIntakeSproutPrompt(params: {
    projectName: string;
    projectDesc: string;
    goldenRules: GoldenRules;
  }): string {
    return `
You are the **Specifier**. Your job is to translate the following rough idea into a structured draft specification (both the Core Spec and 2 to 4 primary feature sections) under the strict constraints of the Golden Rules.

## Project Title
\${params.projectName}

## Rough Idea
\${params.projectDesc}

## Golden Rules (Constraints)
- Frontend: \${params.goldenRules.frontend}
- Backend: \${params.goldenRules.backend}
- Database: \${params.goldenRules.database}
- Additional: \${params.goldenRules.additional}

## Required Sections & Formatting Rules:
1. **Core Spec (\`coreSpec\`)\**:
   - MUST contain a \`## Out of Scope (Non-Goals)\` section at the end of the markdown content outlining what features, integrations, or capabilities the MVP will NOT build.
2. **Feature Content (\`content\` of features)**:
   - For every feature, the content markdown MUST be structured with:
     - A \`## User Story\` section formatted as:
       \`As a [role], I want to [action], so that [benefit].\`
     - A \`## Acceptance Criteria\` section outlining the scenarios using the Given/When/Then layout, formatted as:
       \`Scenario: [Scenario description]\`
       \`Given [context/preconditions]\`
       \`When [action/trigger]\`
       \`Then [expected outcome/behavior]\`

## Output Format
You must output a single, valid JSON block inside a fenced code block of type \`\`\`json.
The JSON must match the following TypeScript shape:
{
  "coreSpec": "# Core Architecture Specification\\n\\nOutline the system base, tech stack, and structure conforming to the Golden Rules.\\n\\n## Out of Scope (Non-Goals)\\n- [Exclusion item 1]\\n- [Exclusion item 2]",
  "features": [
    {
      "id": "feature_slug_1",
      "title": "Feature Title 1",
      "content": "# Feature Requirement Details\\n\\n## User Story\\nAs a [user], I want to [action], so that [benefit].\\n\\n## Acceptance Criteria\\nScenario: [Scenario Title]\\nGiven [precondition]\\nWhen [action]\\nThen [result]"
    }
  ]
}

No other prose or text outside the json block. Keep markdown content well-structured and detailed.
`;
  }

  /**
   * Prompts the Optionizer to read specifications and generate Decision Cards
   */
  public static buildOptionizerForkPrompt(params: {
    config: ProjectConfig;
    sections: SpecSection[];
  }): string {
    const specsBlock = params.sections.map(s => `### ${s.title}\n${s.content}`).join('\n\n');
    return `
You are the **Optionizer**. Your task is to analyze the draft specification below and propose 1 to 3 critical architectural or design decisions (Decision Cards) that the developer needs to make.
Each decision must conform to the Golden Rules and present 2 to 3 distinct options.

## Project Golden Rules
- Frontend: ${params.config.goldenRules.frontend}
- Backend: ${params.config.goldenRules.backend}
- Database: ${params.config.goldenRules.database}
- Constraints: ${params.config.goldenRules.additional}

## Active Specifications
${specsBlock}

## Output Format
You must output a single, valid JSON block inside a fenced code block of type \`\`\`json.
The JSON must match the following shape:
[
  {
    "id": "dec_unique_slug_1",
    "section": "Category name (e.g. Database / Auth)",
    "title": "Clear question title (e.g. Select Query Cache Strategy)",
    "options": [
      {
        "name": "Option Name A",
        "desc": "Consequences and detail of option A",
        "approved": false
      },
      {
        "name": "Option Name B",
        "desc": "Consequences and detail of option B",
        "approved": false
      }
    ]
  }
]
`;
  }

  /**
   * Prompts the Gap Detector to review the specification
   */
  public static buildGapDetectorReviewPrompt(params: {
    config: ProjectConfig;
    sections: SpecSection[];
  }): string {
    const specsBlock = params.sections.map(s => `### ${s.title}\n${s.content}`).join('\n\n');
    return `
You are the **Gap Detector**. Review the active specification below. 
Find any logical contradictions, empty requirements, edge cases, or violations of the Golden Rules.

## Project Golden Rules
- Frontend: ${params.config.goldenRules.frontend}
- Backend: ${params.config.goldenRules.backend}
- Database: ${params.config.goldenRules.database}
- Constraints: ${params.config.goldenRules.additional}

## Active Specifications
${specsBlock}

## Output Format
Provide a clean Markdown list of findings. Highlight each gap with:
- **Location**: Which section (Core or feature name)
- **Problem**: What is missing or conflicting
- **Recommendation**: How the user can resolve it

Keep it highly actionable. If there are no gaps, respond with "No gaps found."
`;
  }

  /**
   * Prompts a specific agent for general chat response
   */
  public static buildAgentChatPrompt(params: {
    agentType: 'specifier' | 'researcher' | 'optionizer' | 'gapDetector';
    config: ProjectConfig;
    sections: SpecSection[];
    chatHistory: NodeMessage[];
  }): string {
    let roleDescription = '';
    if (params.agentType === 'specifier') {
      roleDescription = 'You are the **Specifier**. Detail requirements, refine phrasing, and ensure APIs and schemas are clear.';
    } else if (params.agentType === 'researcher') {
      roleDescription = 'You are the **Researcher**. Supply design patterns, prior art, library recommendations, and standard solutions.';
    } else if (params.agentType === 'optionizer') {
      roleDescription = 'You are the **Optionizer**. Lay out architectural choices, pros/cons, and help make technology comparisons.';
    } else {
      roleDescription = 'You are the **Gap Detector**. Find contradictions, unhandled errors, missing edge cases, and design holes.';
    }

    const historyBlock = this.chatHistorySection(params.chatHistory);
    const specsBlock = params.sections.map(s => `### ${s.title}\n${s.content}`).join('\n\n');

    return `
\${roleDescription}

Analyze the project specs and user messages. Conform to the Golden Rules.
Respond with:
- 1 to 2 paragraphs of clear explanation or research.
- If you have updates to the specifications, append them inside a \`\`\`specUpdate fenced code block matching this shape:
\`\`\`specUpdate
{
  "sectionId": "feature_slug_or_core_spec",
  "title": "Optional Title Update",
  "content": "Full revised specification content for this section"
}
\`\`\`

## Formatting Rules for Specification Updates:
- **Core Spec (core_spec)**: MUST contain a \`## Out of Scope (Non-Goals)\` section at the end of the markdown content.
- **Feature content**: MUST contain \`## User Story\` (using the \`As a... I want to... So that...\` template) and \`## Acceptance Criteria\` (using the Given/When/Then layout) sections.

## Golden Rules
- Frontend: \${params.config.goldenRules.frontend}
- Backend: \${params.config.goldenRules.backend}
- Database: \${params.config.goldenRules.database}
- Constraints: \${params.config.goldenRules.additional}

## Current Specifications
\${specsBlock}

\${historyBlock}
`;
  }

  /**
   * Prompts the Specifier to draft a step-by-step checklist based on the compiled specs.
   */
  public static buildTaskSproutPrompt(params: {
    projectName: string;
    projectDesc: string;
    specsBlock: string;
  }): string {
    return `
You are the **Specifier**. Your job is to take the compiled software specification below and break it down into a highly actionable, step-by-step implementation checklist (task list).
This task list will guide the AI developer engine and the human developer to implement the project.

## Project Title
${params.projectName}

## Project Overview
${params.projectDesc}

## Compiled Specifications
${params.specsBlock}

## Requirements for Task List:
1. Break down the project into logical steps, including:
   - Base workspace preparation / configurations
   - Database schemas / migrations / storage logic
   - Backend APIs / controllers / endpoints
   - Frontend views / components / styling
   - Verification / testing setup
2. Each task MUST be formatted as a markdown checkbox:
   - Use \`- [ ]\` for pending tasks.
   - Do NOT use \`- [x]\` or others.
3. Be specific. Name files, API paths, and component names (e.g. \`- [ ] Create user authentication API endpoint in /api/auth/login\` instead of just \`- [ ] Make login\`).
4. Output ONLY the markdown checklist. Do not include introductory text, conversational greetings, explanations, or code blocks. Just output the checklist lines directly.
`;
  }

  private static chatHistorySection(messages: NodeMessage[]): string {
    if (messages.length === 0) return '';
    const lines = messages.map(
      (m) => `**${this.getAuthorLabel(m.author)}**: ${m.content}`
    );
    return `## Conversation History\n${lines.join('\n')}`;
  }

  private static getAuthorLabel(author: string): string {
    switch (author) {
      case 'user': return 'Client';
      case 'director': return 'Director';
      case 'specifier': return 'Specifier';
      case 'researcher': return 'Researcher';
      case 'optionizer': return 'Optionizer';
      case 'gapDetector': return 'Gap Detector';
      default: return author;
    }
  }
}
