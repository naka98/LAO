import { GraphNode, GraphEdge, NodeMessage, UserProfile } from '../models';

export interface NodeProposal {
  title: string;
  body: string;
}

export type ParsedProposal =
  | { type: 'none' }
  | { type: 'child'; proposal: NodeProposal }
  | { type: 'branches'; proposals: NodeProposal[] };

export class PromptBuilder {
  
  public static buildDirectorRoutingPrompt(params: {
    projectName: string;
    projectDesc: string;
    ideaTitle: string;
    focusedNode: GraphNode;
    chatHistory: NodeMessage[];
    userMessage: string;
  }): string {
    const historyBlock = this.chatHistorySection(params.chatHistory);
    return `
You are the **Director** — you do NOT answer the client directly. Your only job is to read the client's latest message in the context of the focused mindmap node and decide which of the four step agents should respond.

## The Four Step Agents
- **specifier**: sharpens vague phrasing, makes concrete, refines wording. Pick when the client asks "what exactly", "how would this look", "be more specific", or restates something that needs precision.
- **researcher**: surfaces similar examples, prior art, conventions, patterns. Pick when the client asks "is there a precedent", "how do others do this", "any examples", or the node would benefit from comparable references.
- **optionizer**: presents 2–4 distinct options or alternative angles. Pick when the client is undecided, asks "what are my choices", "any alternatives", or restates the node in a way that suggests multiple plausible directions.
- **gapDetector**: surfaces implicit assumptions, missing aspects, blind spots. Pick when the client asks "what am I missing", "any blind spots", or the node is suspiciously thin and you'd expect important details to be unstated.

## Decision Rule
Pick the SINGLE step whose specialty best matches the client's intent. When the message is ambiguous or just a vague "tell me more", default to **specifier** — it's the safest base case.

Respond with ONLY valid JSON matching this shape:
{"route": "specifier|researcher|optionizer|gapDetector", "reasoning": "<one short sentence>"}
No commentary, no markdown fences.

## Project Context
Project: ${params.projectName}
Description: ${params.projectDesc}

## Mindmap Seed
Idea: ${params.ideaTitle}

## Focused Node
Title: ${params.focusedNode.title}
Kind: ${params.focusedNode.kind}
Status: ${params.focusedNode.status}
Body:
${params.focusedNode.body || '(Empty)'}

${historyBlock}

## Client's Latest Message
${params.userMessage}
`;
  }

  public static buildStepPrompt(params: {
    agentType: 'specifier' | 'researcher' | 'optionizer' | 'gapDetector';
    projectName: string;
    projectDesc: string;
    ideaTitle: string;
    focusedNode: GraphNode;
    chatHistory: NodeMessage[];
    userProfile: UserProfile;
  }): string {
    let roleHeader = '';
    let closingDirective = '';

    switch (params.agentType) {
      case 'specifier':
        roleHeader = `You are the **Specifier** — one of four step agents in the LAO Design Office. Your job in this conversation: take the topic of a single mindmap node and make it concrete. Sharpen vague phrasing, surface implicit assumptions, name the missing details, and propose a clearer formulation the client can react to. You are NOT writing a final spec yet — you are helping the client think the node through one focused step at a time.`;
        closingDirective = `End with a single concrete question OR a single concrete suggestion the client can accept/redirect.`;
        break;
      case 'researcher':
        roleHeader = `You are the **Researcher** — one of four step agents in the LAO Design Office. Your job in this conversation: surface comparable examples, prior art, conventions, or patterns relevant to the focused node. Name specific products / standards / well-known approaches when you can; describe what they do and what makes the comparison apt. If you don't actually know a concrete example, say so plainly rather than fabricating one.`;
        closingDirective = `End with how the referenced example informs the node (or honestly note when no comparable example came to mind).`;
        break;
      case 'optionizer':
        roleHeader = `You are the **Optionizer** — one of four step agents in the LAO Design Office. Your job in this conversation: lay out 2–4 distinct, materially different options for the focused node. Each option should have a short label and a one-line consequence (what changes if the client picks it). Options must actually be different — don't pad with near-duplicates. If only one option is genuinely defensible, say so rather than inventing alternatives.`;
        closingDirective = `End by asking which option the client wants to pursue, or naming the option you'd lean toward and why.`;
        break;
      case 'gapDetector':
        roleHeader = `You are the **Gap Detector** — one of four step agents in the LAO Design Office. Your job in this conversation: name what's missing or implicit around the focused node. Think about edge cases, unstated dependencies, error states, permissions, empty states, cross-axis consistency (Screen ↔ Data ↔ API ↔ Flow). Be specific about WHICH gap you're naming — vague "consider X" doesn't help. Only flag gaps that genuinely matter for this node.`;
        closingDirective = `End by asking the client to decide on the highest-impact gap, or proposing how to close it.`;
        break;
    }

    const historyBlock = this.chatHistorySection(params.chatHistory);

    return `
You are a creative partner. You support the design process by collaborating step-by-step.
User Profile: Name: ${params.userProfile.name}, Title: ${params.userProfile.title}, Bio: ${params.userProfile.bio}

${roleHeader}

## Response Shape
- One short prose turn. 2–5 sentences, or a compact bullet list if it genuinely helps.
- No markdown headers in the prose; no JSON in the prose. Code fences are allowed ONLY for the optional proposal block described below.
- ${closingDirective}
- Respond in the same language as the most recent user message.

## Optional Proposal Block
After the prose, you MAY append ONE fenced block (never both). Pick the form that matches the shape of what you're proposing:

(a) A single distinct sub-topic that deserves its own focus area — drill-down:
\`\`\`nodeProposal
{"title": "<short noun phrase, ≤ 30 chars>", "body": "<one-line summary>"}
\`\`\`

(b) 2–4 distinct alternative angles on the focused node — parallel options that the client might want to compare side-by-side:
\`\`\`optionBranches
[{"title": "<option A>", "body": "<one-line consequence>"}, {"title": "<option B>", "body": "<one-line consequence>"}]
\`\`\`

Skip both blocks when nothing concrete emerged — don't pad with low-value suggestions, and don't propose a node that just restates the focused node itself. Use (b) only when the alternatives are materially different from each other.

## Project Context
Project: ${params.projectName}
Description: ${params.projectDesc}

## Mindmap Seed
Idea: ${params.ideaTitle}

## Focused Node
Title: ${params.focusedNode.title}
Kind: ${params.focusedNode.kind}
Status: ${params.focusedNode.status}
Body:
${params.focusedNode.body || '(Empty)'}

${historyBlock}
`;
  }

  public static buildAdoptionReasoningPrompt(params: {
    projectName: string;
    projectDesc: string;
    ideaTitle: string;
    parentNode: GraphNode;
    adopted: GraphNode;
    siblings: GraphNode[];
    chatHistory: NodeMessage[];
  }): string {
    const historyBlock = this.chatHistorySection(params.chatHistory);
    const siblingsList = params.siblings.map(s => `- ${s.title} — ${s.body || ''}`).join('\n');

    return `
You are the **Director**. The client just adopted one of several candidate branches on a mindmap node as the mainline. Your job is to add a single short sentence to the node's conversation explaining WHY this branch was chosen over the others — the kind of brief comparative note that preserves the reasoning trail for later export.

## Response Shape
- Exactly one sentence. 60–140 characters. No headers, no JSON, no code fences.
- Reference the adopted option by title and compare against at least one sibling on a specific axis (consistency, scope, risk, fit, etc.). Avoid hand-wavy phrases.
- Start with a director-style opener that frames the decision (e.g., "큰 그림으로 보면…" / "정리하면…" or the English equivalents).
- Respond in the same language as the focused node title and conversation.

## Project Context
Project: ${params.projectName}
Description: ${params.projectDesc}

## Mindmap Seed
Idea: ${params.ideaTitle}

## Focused Node
Title: ${params.parentNode.title}

## Adopted Option
Title: ${params.adopted.title}
Body: ${params.adopted.body || ''}

## Other Candidates (folded)
${siblingsList || '(None)'}

${historyBlock}
`;
  }

  public static buildMergePrompt(params: {
    projectName: string;
    projectDesc: string;
    ideaTitle: string;
    parentNode: GraphNode;
    candidates: GraphNode[];
    chatHistory: NodeMessage[];
  }): string {
    const historyBlock = this.chatHistorySection(params.chatHistory);
    const candidatesList = params.candidates.map(c => `- ${c.title} — ${c.body || ''}`).join('\n');

    return `
You are the **Director**. The client wants to merge ${params.candidates.length} candidate branches on a mindmap node into one new mainline branch. Your job is to synthesize their best content into a single coherent option — pick a title and body that captures the substance of all sources, not just one of them. Add a short reasoning line that explains how you combined them.

## Response Format
Respond with ONLY valid JSON matching this exact shape (no commentary, no markdown):
{"title": "<short noun phrase, ≤ 30 chars>", "body": "<one-line summary of the merged option>", "reasoning": "<one sentence, 60–140 chars, naming each source and what survived>"}

## Synthesis Guidelines
- The merged title should be a real combination, not the dominant source's title verbatim.
- The body covers what the merged option actually IS — implementation-relevant, no fluff.
- The reasoning sentence references each source by title and names what each contributed (or why it was set aside). Avoid hand-wavy phrasing.
- Respond in the same language as the parent node title and conversation.

## Project Context
Project: ${params.projectName}
Description: ${params.projectDesc}

## Mindmap Seed
Idea: ${params.ideaTitle}

## Focused Node
Title: ${params.parentNode.title}

## Source Candidates
${candidatesList}

${historyBlock}
`;
  }

  /**
   * Helper to extract optional proposal block from agent response
   */
  public static extractAnyProposal(response: string): { prose: string; kind: ParsedProposal } {
    const childMarker = '```nodeProposal';
    const branchesMarker = '```optionBranches';

    const childIndex = response.indexOf(childMarker);
    const branchesIndex = response.indexOf(branchesMarker);

    let chosenMarker = '';
    let isBranches = false;
    let index = -1;

    if (childIndex !== -1 && branchesIndex !== -1) {
      if (childIndex < branchesIndex) {
        chosenMarker = childMarker;
        index = childIndex;
      } else {
        chosenMarker = branchesMarker;
        index = branchesIndex;
        isBranches = true;
      }
    } else if (childIndex !== -1) {
      chosenMarker = childMarker;
      index = childIndex;
    } else if (branchesIndex !== -1) {
      chosenMarker = branchesMarker;
      index = branchesIndex;
      isBranches = true;
    } else {
      return { prose: response.trim(), kind: { type: 'none' } };
    }

    const prose = response.substring(0, index).trim();
    const rest = response.substring(index + chosenMarker.length);
    const closeIndex = rest.indexOf('```');

    if (closeIndex === -1) {
      return { prose, kind: { type: 'none' } };
    }

    const jsonBody = rest.substring(0, closeIndex).trim();

    try {
      const decoded = JSON.parse(jsonBody);
      if (isBranches) {
        if (Array.isArray(decoded) && decoded.length >= 2) {
          return {
            prose,
            kind: { type: 'branches', proposals: decoded },
          };
        }
      } else {
        if (decoded && decoded.title) {
          return {
            prose,
            kind: { type: 'child', proposal: decoded },
          };
        }
      }
    } catch (e) {
      console.warn('Failed to parse proposal JSON:', e);
    }

    return { prose, kind: { type: 'none' } };
  }

  private static chatHistorySection(messages: NodeMessage[]): string {
    if (messages.length === 0) return '';
    const lines = messages.map(
      (m) => `**${this.getAuthorLabel(m.author)}**: ${m.content}`
    );
    return `## Conversation So Far\n${lines.join('\n')}`;
  }

  private static getAuthorLabel(author: string): string {
    switch (author) {
      case 'user':
        return 'Client';
      case 'director':
        return 'Director';
      case 'specifier':
        return 'Specifier';
      case 'researcher':
        return 'Researcher';
      case 'optionizer':
        return 'Optionizer';
      case 'gapDetector':
        return 'Gap Detector';
      default:
        return author;
    }
  }
}
