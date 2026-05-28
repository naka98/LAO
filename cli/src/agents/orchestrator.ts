import { ProjectConfig, SpecSection, DecisionCard, NodeMessage } from '../models';
import { GeminiClient } from '../gemini';
import { PromptBuilder } from './promptBuilder';
import { randomUUID } from 'crypto';

export interface RouteAndRespondResult {
  route: 'specifier' | 'researcher' | 'optionizer' | 'gapDetector';
  reasoning: string;
  prose: string;
  specUpdate?: {
    sectionId: string;
    title?: string;
    content: string;
  };
}

export class AgentOrchestrator {
  private geminiClient: GeminiClient;

  constructor() {
    this.geminiClient = new GeminiClient();
  }

  /**
   * Helper to clean markdown JSON fences before parsing
   */
  private cleanJsonResponse(raw: string): string {
    let cleaned = raw.trim();
    
    // 1. Strip outermost ```json and matching trailing ```
    const jsonMarker = '```json';
    const jsonIndex = cleaned.indexOf(jsonMarker);
    if (jsonIndex !== -1) {
      cleaned = cleaned.substring(jsonIndex + jsonMarker.length).trim();
      const lastFence = cleaned.lastIndexOf('```');
      if (lastFence !== -1) {
        cleaned = cleaned.substring(0, lastFence).trim();
      }
    } else {
      // 2. Strip generic ``` blocks
      const genericMarker = '```';
      const genericIndex = cleaned.indexOf(genericMarker);
      if (genericIndex !== -1) {
        cleaned = cleaned.substring(genericIndex + genericMarker.length).trim();
        const lastFence = cleaned.lastIndexOf('```');
        if (lastFence !== -1) {
          cleaned = cleaned.substring(0, lastFence).trim();
        }
      }
    }
    
    // 3. Fallback to extracting everything within the first and last brace/bracket
    const firstBrace = cleaned.indexOf('{');
    const firstBracket = cleaned.indexOf('[');
    if (firstBrace !== -1 || firstBracket !== -1) {
      const start = firstBrace !== -1 && (firstBracket === -1 || firstBrace < firstBracket) ? firstBrace : firstBracket;
      const lastBrace = cleaned.lastIndexOf('}');
      const lastBracket = cleaned.lastIndexOf(']');
      const end = lastBrace > lastBracket ? lastBrace + 1 : lastBracket + 1;
      if (end > start) {
        return cleaned.substring(start, end).trim();
      }
    }

    return cleaned;
  }

  /**
   * Helper to extract optional spec update blocks from prose responses
   */
  private extractSpecUpdate(response: string): { prose: string; specUpdate?: { sectionId: string; title?: string; content: string } } {
    const marker = '```specUpdate';
    const index = response.indexOf(marker);
    if (index === -1) {
      return { prose: response.trim() };
    }
    const prose = response.substring(0, index).trim();
    const rest = response.substring(index + marker.length);
    const closeIndex = rest.indexOf('```');
    if (closeIndex === -1) {
      return { prose };
    }
    const jsonBody = rest.substring(0, closeIndex).trim();
    
    // Preprocess jsonBody to escape raw newlines inside JSON string values
    let fixedJson = '';
    let inString = false;
    let escape = false;
    for (let i = 0; i < jsonBody.length; i++) {
      const char = jsonBody[i];
      if (char === '"' && !escape) {
        inString = !inString;
        fixedJson += char;
      } else if (char === '\\' && inString && !escape) {
        escape = true;
        fixedJson += char;
      } else if (inString && (char === '\n' || char === '\r')) {
        fixedJson += '\\n';
        escape = false;
      } else {
        fixedJson += char;
        escape = false;
      }
    }

    // Clean trailing commas before closing braces/brackets
    fixedJson = fixedJson.replace(/,\s*([}\]])/g, '$1');

    try {
      const specUpdate = JSON.parse(fixedJson);
      if (specUpdate && specUpdate.sectionId && specUpdate.content) {
        return { prose, specUpdate };
      }
    } catch (e: any) {
      console.warn('Failed to parse specUpdate JSON even after raw newline escaping:', e);
    }
    return { prose };
  }

  /**
   * Sprout draft specifications based on project config and golden rules
   */
  public async runIntakeSprout(config: ProjectConfig): Promise<{ coreSpec: string; features: SpecSection[] }> {
    const prompt = PromptBuilder.buildIntakeSproutPrompt({
      projectName: config.projectName,
      projectDesc: config.projectDesc,
      goldenRules: config.goldenRules
    });

    const responseRaw = await this.geminiClient.generateText({
      prompt,
      jsonMode: true,
      role: 'specifier'
    });

    const cleaned = this.cleanJsonResponse(responseRaw);
    const parsed = JSON.parse(cleaned);

    const now = new Date().toISOString();

    // 1. Resolve coreSpec as a Markdown string
    let coreSpecStr = '';
    if (parsed.coreSpec) {
      if (typeof parsed.coreSpec === 'object') {
        coreSpecStr = Object.entries(parsed.coreSpec)
          .map(([key, val]) => `## ${key}\n\n${val}`)
          .join('\n\n');
      } else {
        coreSpecStr = String(parsed.coreSpec);
      }
    } else {
      coreSpecStr = `# Core Spec\n\nConforming to Golden Rules.`;
    }

    // 2. Map feature array fields dynamically
    const features: SpecSection[] = (parsed.features || []).map((f: any) => {
      const title = f.title || f.name || 'Untitled Feature';
      const content = f.content || f.description || f.requirements || '';
      return {
        id: f.id || randomUUID().substring(0, 8),
        title,
        content: typeof content === 'object' ? JSON.stringify(content, null, 2) : String(content),
        status: 'active',
        createdAt: now,
        updatedAt: now
      };
    });

    return {
      coreSpec: coreSpecStr,
      features
    };
  }

  /**
   * Analyze spec sections to propose Decision Cards (architectural choices)
   */
  public async runOptionizerFork(config: ProjectConfig, sections: SpecSection[]): Promise<DecisionCard[]> {
    const prompt = PromptBuilder.buildOptionizerForkPrompt({ config, sections });
    const responseRaw = await this.geminiClient.generateText({
      prompt,
      jsonMode: true,
      role: 'optionizer'
    });

    const cleaned = this.cleanJsonResponse(responseRaw);
    const parsed = JSON.parse(cleaned);

    const now = new Date().toISOString();
    const cards: DecisionCard[] = (parsed || []).map((c: any) => ({
      id: c.id || randomUUID().substring(0, 8),
      section: c.section || 'General',
      title: c.title || 'Untitled Choice',
      options: (c.options || []).map((opt: any) => ({
        name: opt.name || 'Option',
        desc: opt.desc || '',
        approved: !!opt.approved
      })),
      status: 'pending',
      createdAt: now,
      updatedAt: now
    }));

    return cards;
  }

  /**
   * Analyze spec sections for flaws, omissions, or contradictions
   */
  public async runGapDetectorReview(config: ProjectConfig, sections: SpecSection[]): Promise<string> {
    const prompt = PromptBuilder.buildGapDetectorReviewPrompt({ config, sections });
    return this.geminiClient.generateText({
      prompt,
      role: 'gapDetector'
    });
  }

  /**
   * Main routing and streaming chat responder for the workspace
   */
  public async routeAndRespondStream(params: {
    config: ProjectConfig;
    sections: SpecSection[];
    chatHistory: NodeMessage[];
    userMessage: string;
    onChunk: (data: { type: 'routing' | 'content'; route?: string; reasoning?: string; chunk?: string }) => void;
  }): Promise<RouteAndRespondResult> {
    
    // 1. Route message using Director
    const directorPrompt = PromptBuilder.buildDirectorRoutingPrompt({
      config: params.config,
      chatHistory: params.chatHistory,
      userMessage: params.userMessage
    });

    let route: 'specifier' | 'researcher' | 'optionizer' | 'gapDetector' = 'specifier';
    let routingReason = 'Vague intent fallback';

    try {
      const directorResponseRaw = await this.geminiClient.generateText({
        prompt: directorPrompt,
        jsonMode: true,
        role: 'director'
      });

      const cleanedDirector = this.cleanJsonResponse(directorResponseRaw);
      const parsedRouting = JSON.parse(cleanedDirector);
      if (
        parsedRouting.route &&
        ['specifier', 'researcher', 'optionizer', 'gapDetector'].includes(parsedRouting.route)
      ) {
        route = parsedRouting.route;
        routingReason = parsedRouting.reasoning || '';
      }
    } catch (e) {
      console.warn('[LAO Director] Routing failed, defaulting to specifier', e);
    }

    // Notify client of selected agent route
    params.onChunk({ type: 'routing', route, reasoning: routingReason });

    // 2. Generate agent response stream
    const agentPrompt = PromptBuilder.buildAgentChatPrompt({
      agentType: route,
      config: params.config,
      sections: params.sections,
      chatHistory: params.chatHistory,
      userMessage: params.userMessage
    });

    const responseRaw = await this.geminiClient.generateText({
      prompt: agentPrompt,
      role: route,
      onChunk: (chunk) => params.onChunk({ type: 'content', chunk })
    });

    // 3. Extract spec updates from response
    const { prose, specUpdate } = this.extractSpecUpdate(responseRaw);

    return {
      route,
      reasoning: routingReason,
      prose,
      specUpdate
    };
  }

  /**
   * Sprout checklist tasks (task.md) from specs
   */
  public async runTaskSprout(config: ProjectConfig, sections: SpecSection[]): Promise<string> {
    const specsBlock = sections.map(s => `### ${s.title}\n${s.content}`).join('\n\n');
    const prompt = PromptBuilder.buildTaskSproutPrompt({
      projectName: config.projectName,
      projectDesc: config.projectDesc,
      specsBlock
    });

    const responseRaw = await this.geminiClient.generateText({
      prompt,
      role: 'specifier'
    });

    return responseRaw.trim();
  }
}
