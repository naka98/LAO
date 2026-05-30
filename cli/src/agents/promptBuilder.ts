import { ProjectConfig, SpecSection, DecisionCard, NodeMessage, GoldenRules } from '../models';
import * as fs from 'fs';
import * as path from 'path';

export class PromptBuilder {

  public static buildConsolidatedRules(configOrGoldenRules: ProjectConfig | GoldenRules): string {
    const golden = 'goldenRules' in configOrGoldenRules ? configOrGoldenRules.goldenRules : configOrGoldenRules;
    let rulesMd = '';
    const rulesPath = path.join(process.cwd(), 'RULES.md');
    if (fs.existsSync(rulesPath)) {
      try {
        rulesMd = fs.readFileSync(rulesPath, 'utf8').trim();
      } catch (e) {
        console.warn('[LAO Core] Failed to read RULES.md inside PromptBuilder:', e);
      }
    }

    return `## Consolidated Project Rules & Constraints
### Tech Stack constraints
- **Frontend**: ${golden.frontend}
- **Backend**: ${golden.backend}
- **Database**: ${golden.database}
- **Additional**: ${golden.additional}
${rulesMd ? `\n### Strict Custom Rules (RULES.md)\n${rulesMd}` : ''}`;
  }

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

${this.buildConsolidatedRules(params.config)}

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
    chosenOption?: any;
    userAdjustments?: string;
    feedback?: string;
    previousAttempt?: string;
  }): string {
    const optionBlock = params.chosenOption ? `
## Chosen Planning Concept
Option ${params.chosenOption.key}: ${params.chosenOption.title}
- Objective: ${params.chosenOption.objective}
- Core User: ${params.chosenOption.coreUser}
- Scope to Build:
${(params.chosenOption.scope || []).map((s: string) => `  * ${s}`).join('\n')}
` : '';

    const adjustmentsBlock = params.userAdjustments ? `
## Additional User Adjustments & Merge Constraints
"${params.userAdjustments}"
` : '';

    const feedbackBlock = params.feedback ? `
## [필독] 이전 생성에서의 검증 검토 피드백
당신이 이전에 생성한 뼈대 구조에 다음과 같은 검증 실패 및 누락 오류가 발생했습니다.
이번 생성 시에는 이 피드백 오류 사항을 반드시 반영하여 완벽하게 규격을 충족시키십시오:
${params.feedback}
` : '';

    const previousAttemptBlock = params.previousAttempt ? `
## [참고] 이전 생성 결과물 (수정 대상)
아래는 당신이 직전에 생성했으나 검증에 실패한 내용입니다. 이 구조를 기반으로 오류를 분석하고 보완하십시오:
\`\`\`json
${params.previousAttempt}
\`\`\`
` : '';

    return `
You are the **Specifier**. Your job is to translate the following rough idea into a structured draft skeleton specification (both the Core Spec Outline and 2 to 4 primary feature outlines) under the strict constraints of the Golden Rules.

${optionBlock}
${adjustmentsBlock}
${feedbackBlock}
${previousAttemptBlock}

## Project Title
${params.projectName}

## Rough Idea
${params.projectDesc}

${this.buildConsolidatedRules(params.goldenRules)}

## Required Sections & Formatting Rules:
1. **Core Spec (\`coreSpec\`)\**:
   - Outlines the base architecture, tech stack, and global requirements conforming to the Golden Rules.
   - MUST contain a \`## Out of Scope (Non-Goals)\` section at the end of the markdown content.
2. **Feature Outline (\`features\` array)**:
   - For every feature, output a simple skeleton object containing \`id\` (unique slug), \`title\` (name), \`description\` (a single sentence summarizing the feature purpose), and \`dependencies\` (an array of feature IDs this feature depends on).
   - DO NOT write the detailed markdown content (User Story, Acceptance Criteria) yet. Keep it as a clean outline.

## Output Format
You must output a single, valid JSON block inside a fenced code block of type \`\`\`json.
The JSON must match the following TypeScript shape:
{
  "coreSpec": "# Core Architecture Specification\\n\\nOutline the system base, tech stack, and structure conforming to the Golden Rules.\\n\\n## Out of Scope (Non-Goals)\\n- [Exclusion item 1]\\n- [Exclusion item 2]",
  "features": [
    {
      "id": "feature_slug_1",
      "title": "Feature Title 1",
      "description": "A single sentence summarizing the feature purpose.",
      "dependencies": []
    }
  ]
}

No other prose or text outside the json block. Keep the skeleton clean and lightweight.
`;
  }

  /**
   * Prompts the Director to generate exactly three planning concepts
   */
  public static buildIntakeDivergencePrompt(params: {
    projectName: string;
    projectDesc: string;
    goldenRules: GoldenRules;
    feedback?: string;
  }): string {
    const feedbackBlock = params.feedback ? `
## Previous Draft Feedback (User Request)
Please modify and regenerate the proposals incorporating this specific feedback:
"${params.feedback}"
` : '';

    return `
You are the **Director** and **Lead Architect**. Your task is to analyze the following project idea and generate exactly three distinct product planning concepts (Option A, Option B, and Option C) along with a Director Recommendation in Korean.

## Project Title
${params.projectName}

## Rough Idea / Description
${params.projectDesc}

${this.buildConsolidatedRules(params.goldenRules)}
${feedbackBlock}

## The Three Concepts to Generate:
1. **Option A — 빠른 MVP형 (Fast MVP Type)**:
   - Objective: Validate core value as fast as possible. Minimal features, ultra-light layout, SQLite/local storage.
   - Core User: Early adopters, testing users.
   - Scope: Only the single most crucial feature.
2. **Option B — 구조 확장형 (Structural Extension Type)**:
   - Objective: Production-ready scalability, database relationships, multiple user/auth patterns, clean architecture.
   - Core User: General production users, security-conscious clients.
   - Scope: Core feature + multi-user authentication, settings, logging, relational schemas.
3. **Option C — 차별화 실험형 (Differentiated Experiment Type)**:
   - Objective: Highlight a unique competitive advantage (e.g. advanced AI widgets, visualization, interactive flows, offline-sync).
   - Core User: Power users, tech enthusiasts.
   - Scope: Core feature + unique premium experiment features.

## Director Recommendation Rules:
- Propose one of the options (A, B, or C) as the recommendation.
- Detail the reasoning, what options were discarded and why, what elements can be merged, and what decisions the user must make.
- Output MUST be strictly in Korean.

## Output Format
You must output a single, valid JSON block inside a fenced code block of type \`\`\`json.
The JSON must match the following TypeScript shape:
{
  "options": {
    "A": {
      "key": "A",
      "title": "빠른 MVP형 - [Sub-title matching option A]",
      "objective": "[Objective of Option A]",
      "coreUser": "[Core User profile]",
      "scope": ["Feature scope item 1", "Feature scope item 2"],
      "pros": ["Pro 1", "Pro 2"],
      "cons": ["Con 1", "Con 2"],
      "recommendedScenario": "[Recommended scenario]"
    },
    "B": {
      "key": "B",
      "title": "구조 확장형 - [Sub-title matching option B]",
      "objective": "[Objective of Option B]",
      "coreUser": "[Core User profile]",
      "scope": ["Feature scope item 1", "Feature scope item 2", "Feature scope item 3"],
      "pros": ["Pro 1", "Pro 2"],
      "cons": ["Con 1", "Con 2"],
      "recommendedScenario": "[Recommended scenario]"
    },
    "C": {
      "key": "C",
      "title": "차별화 실험형 - [Sub-title matching option C]",
      "objective": "[Objective of Option C]",
      "coreUser": "[Core User profile]",
      "scope": ["Feature scope item 1", "Feature scope item 2", "Feature scope item 3"],
      "pros": ["Pro 1", "Pro 2"],
      "cons": ["Con 1", "Con 2"],
      "recommendedScenario": "[Recommended scenario]"
    }
  },
  "recommendation": {
    "recommendedOption": "A",
    "reason": "[Detail why A was selected]",
    "discardedOptions": "[Explain why B and C were not fully chosen]",
    "combinedElements": "[Optional: any elements from B or C to borrow]",
    "userDecisionsRequired": ["Decision 1", "Decision 2"]
  }
}

Do not include any prose outside the json block. All text fields in the options and recommendation MUST be in Korean.
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

${this.buildConsolidatedRules(params.config)}

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

${this.buildConsolidatedRules(params.config)}

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
    userMessage: string;
    feedback?: string;
    previousAttempt?: string;
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

    const feedbackBlock = params.feedback ? `
## [필독] 기획 하네스 검증 실패 수정 요청
직전에 제출한 specUpdate가 기획 가이드라인 검증을 통과하지 못했습니다.
아래 피드백 사유를 바탕으로 오류 사항을 완벽히 수정한 specUpdate 마크다운을 재작성해주십시오:
${params.feedback}
` : '';

    const previousAttemptBlock = params.previousAttempt ? `
## [참고] 이전 작성 결과물 (수정 대상)
아래는 당신이 직전에 작성했으나 검증에 실패한 specUpdate 내용입니다. 이 내용을 바탕으로 수정하십시오:
\`\`\`specUpdate
${params.previousAttempt}
\`\`\`
` : '';

    return `
roleDescription: ${roleDescription}
${feedbackBlock}
${previousAttemptBlock}

Analyze the project specs and user messages. Conform to the Golden Rules.
Respond with:
- 1 to 2 paragraphs of clear explanation or research.
- If you have updates to the specifications, append them inside a \`\`\`specUpdate fenced code block matching this shape:
\`\`\`specUpdate
sectionId: feature_slug_or_core_spec
title: Optional Title Update
===
# Full revised specification content for this section (Markdown)
\`\`\`

## Formatting Rules for Specification Updates:
- **Core Spec (core_spec)**: MUST contain a \`## Out of Scope (Non-Goals)\` section at the end of the markdown content.
- **Feature content**: MUST contain \`## User Story\` (using the \`As a... I want to... So that...\` template) and \`## Acceptance Criteria\` (using the Given/When/Then layout) sections.

${this.buildConsolidatedRules(params.config)}

## Current Specifications
${specsBlock}

${historyBlock}

## Client's Latest Message
${params.userMessage}
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

  /**
   * Prompts the Specifier to elaborate a single feature skeleton into full details (User Story + GWT Acceptance Criteria)
   */
  public static buildFeatureElaborationPrompt(params: {
    projectName: string;
    coreSpec: string;
    feature: { id: string; title: string; description: string; dependencies?: string[] };
    goldenRules: GoldenRules;
    feedback?: string;
    previousAttempt?: string;
  }): string {
    const feedbackBlock = params.feedback ? `
## [필독] 이전 생성에서의 검증 검토 피드백
당신이 이전에 생성한 기능 사양서에 다음과 같은 검증 실패 오류가 발생했습니다.
이번 생성 시에는 이 피드백 오류 사항을 반드시 반영하여 완벽하게 규격을 충족시키십시오:
${params.feedback}
` : '';

    const previousAttemptBlock = params.previousAttempt ? `
## [참고] 이전 생성 결과물 (수정 대상)
아래는 당신이 직전에 생성했으나 검증에 실패한 내용입니다. 이 구조를 기반으로 오류를 분석하고 보완하십시오:
\`\`\`json
${params.previousAttempt}
\`\`\`
` : '';

    return `
You are the **Specifier**. Your job is to elaborate the following feature outline into a detailed, complete software specification under the strict constraints of the Golden Rules.

${feedbackBlock}
${previousAttemptBlock}

## Project Title
${params.projectName}

## Core Specification Context
${params.coreSpec}

${this.buildConsolidatedRules(params.goldenRules)}

## Target Feature Outline to Elaborate:
- **ID**: ${params.feature.id}
- **Title**: ${params.feature.title}
- **Description**: ${params.feature.description}
${params.feature.dependencies ? `- **Dependencies**: ${params.feature.dependencies.join(', ')}` : ''}

## Required Sections & Formatting Rules:
The content of this feature MUST be a Markdown string structured with:
1. \`## User Story\` section formatted as:
   \`As a [role], I want to [action], so that [benefit].\`
2. \`## Acceptance Criteria\` section outlining the scenarios using the Given/When/Then layout, formatted as:
   \`Scenario: [Scenario description]\`
   \`Given [context/preconditions]\`
   \`When [action/trigger]\`
   \`Then [expected outcome/behavior]\`
3. Any additional specifications, such as API requirements or UI layout guidelines, related to this feature.

## Output Format
You must output a single, valid JSON block inside a fenced code block of type \`\`\`json.
The JSON must match the following TypeScript shape:
{
  "content": "# ${params.feature.title}\\n\\n## User Story\\nAs a [role], I want to [action], so that [benefit].\\n\\n## Acceptance Criteria\\nScenario: [Scenario Title]\\nGiven [precondition]\\nWhen [action]\\nThen [result]"
}

No other prose or text outside the json block.
`;
  }

  /**
   * Prompts the Schema Agent to generate/update Database Schema section
   */
  public static buildSchemaAgentPrompt(params: {
    config: ProjectConfig;
    section: SpecSection;
    userMessage: string;
    chatHistory: NodeMessage[];
  }): string {
    const historyBlock = this.chatHistorySection(params.chatHistory);
    return `
You are the **Schema Agent**, a specialist in database modeling and schemas. 
Your task is to analyze the user request and update the Database Schema section of the feature specification.

## Active Feature
### ${params.section.title} (ID: ${params.section.id})
${params.section.content}

${this.buildConsolidatedRules(params.config)}

## User Request
${params.userMessage}

${historyBlock}

## Instructions:
1. Identify database requirements from the user request.
   - For SQLite, specify tables, columns, primary/foreign keys, types, and indexes.
   - Do NOT specify other DB types if Golden Rules restrict it.
2. Output ONLY the updated \`## Database Schema\` section in markdown. Do not include other sections or prose.
`;
  }

  /**
   * Prompts the UI Spec Agent to generate/update UI design and interaction flow section
   */
  public static buildUISpecAgentPrompt(params: {
    config: ProjectConfig;
    section: SpecSection;
    userMessage: string;
    chatHistory: NodeMessage[];
  }): string {
    const historyBlock = this.chatHistorySection(params.chatHistory);
    return `
You are the **UI Spec Agent**, a specialist in user interface and interaction design.
Your task is to analyze the user request and update the UI design or interaction flow section of the feature specification.

## Active Feature
### ${params.section.title} (ID: ${params.section.id})
${params.section.content}

${this.buildConsolidatedRules(params.config)}

## User Request
${params.userMessage}

${historyBlock}

## Instructions:
1. Detail the layout, view components, transitions, states (normal, loading, empty, error) required.
2. Output ONLY the updated UI/Interaction sections in markdown. Do not include other sections or prose.
`;
  }

  /**
   * Prompts the Test Scenario Agent to generate/update Acceptance Criteria section
   */
  public static buildTestScenarioAgentPrompt(params: {
    config: ProjectConfig;
    section: SpecSection;
    userMessage: string;
    chatHistory: NodeMessage[];
  }): string {
    const historyBlock = this.chatHistorySection(params.chatHistory);
    return `
You are the **Test Scenario Agent**, a specialist in software quality assurance and test design.
Your task is to analyze the user request and update the Acceptance Criteria of the feature specification.

## Active Feature
### ${params.section.title} (ID: ${params.section.id})
${params.section.content}

${this.buildConsolidatedRules(params.config)}

## User Request
${params.userMessage}

${historyBlock}

## Instructions:
1. Define clear, testable requirements using the Given-When-Then layout.
2. Ensure you have \`## Acceptance Criteria\` and write scenarios formatted as:
   \`Scenario: [Title]\`
   \`Given [context]\`
   \`When [trigger]\`
   \`Then [outcome]\`
3. Output ONLY the updated \`## Acceptance Criteria\` section (and optionally \`## User Story\` if user story changed) in markdown. Do not include other sections or prose.
`;
  }

  /**
   * Prompts the Spec Coordinator to plan which subagents to invoke
   */
  public static buildCoordinatorPlanPrompt(params: {
    config: ProjectConfig;
    sections: SpecSection[];
    chatHistory: NodeMessage[];
    userMessage: string;
  }): string {
    const specsBlock = params.sections.map(s => `- **ID**: ${s.id}, **Title**: ${s.title}`).join('\n');
    return `
You are the **Spec Coordinator**. Your job is to analyze the user request and determine:
1. Which section of the specification is the user targeting for modification (e.g. core_spec or a specific feature slug).
2. Which aspects need update:
   - \`schema\`: Database schemas, tables, fields, or relations.
   - \`ui\`: User interface layout, views, screens, interaction flows.
   - \`test\`: Acceptance criteria, test scenarios, User Stories (Given-When-Then criteria).

## Active Specification Sections
${specsBlock}

## User Request
${params.userMessage}

Respond with ONLY valid JSON matching this shape:
{
  "targetSectionId": "core_spec|feature_slug",
  "runSchema": true|false,
  "runUI": true|false,
  "runTest": true|false,
  "proseExplanation": "A short sentence explaining what needs to be updated and why."
}
No commentary, no markdown fences.
`;
  }

  private static chatHistorySection(messages: NodeMessage[], maxMessages = 10): string {
    if (messages.length === 0) return '';
    const startIdx = Math.max(0, messages.length - maxMessages);
    const visibleMessages = messages.slice(startIdx);
    const lines = visibleMessages.map(
      (m) => `**${this.getAuthorLabel(m.author)}**: ${m.content}`
    );
    let output = `## Conversation History\n`;
    if (startIdx > 0) {
      output += `*(Older ${startIdx} messages truncated to optimize agent context)*\n`;
    }
    return output + lines.join('\n');
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
