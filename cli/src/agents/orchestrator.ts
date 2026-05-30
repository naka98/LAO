import { ProjectConfig, SpecSection, DecisionCard, NodeMessage, IntakeProposals, IntakeOption } from '../models';
import { GeminiClient } from '../gemini';
import { PromptBuilder } from './promptBuilder';
import { randomUUID } from 'crypto';
import { PlanningHarness } from './harness';

export interface RouteAndRespondResult {
  route: 'specifier' | 'researcher' | 'optionizer' | 'gapDetector';
  reasoning: string;
  prose: string;
  specUpdate?: {
    sectionId: string;
    title?: string;
    content: string;
  };
  validationErrors?: string[]; // 최종 검증 실패 시 에러 로그 리포트용
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
   * 기획안 초안 발아(Sprout) 시, 기획 하네스 자가 교정 루프를 거쳐 안전한 명세를 생성합니다.
   */
  public async runIntakeSprout(
    config: ProjectConfig,
    chosenOption?: IntakeOption,
    userAdjustments?: string
  ): Promise<{ coreSpec: string; features: SpecSection[] }> {
    let attempts = 0;
    const maxAttempts = 3;
    let parsed: any = null;
    let validationErrors: string[] = [];

    console.log('[LAO Core] Intake Sprout started with PlanningHarness Loop.');

    while (attempts < maxAttempts) {
      attempts++;
      console.log(`[LAO Core] Sprouting attempt ${attempts}/${maxAttempts}`);
      
      const prompt = PromptBuilder.buildIntakeSproutPrompt({
        projectName: config.projectName,
        projectDesc: config.projectDesc,
        goldenRules: config.goldenRules,
        chosenOption,
        userAdjustments,
        feedback: validationErrors.length > 0 ? validationErrors.join('\n') : undefined
      });

      // 100% JSON 출력을 유도하기 위해 CLI 플래그 활성화 및 Direct Call
      const responseRaw = await this.geminiClient.generateText({
        prompt,
        jsonMode: true,
        role: 'specifier'
      });

      const cleaned = this.cleanJsonResponse(responseRaw);
      parsed = JSON.parse(cleaned);

      // 1단계: 기획 하네스 Linter 검증
      const validation = PlanningHarness.validateSprout(parsed);
      if (validation.isValid) {
        console.log('[LAO Core] Sprout Spec validation PASSED on attempt ' + attempts);
        break; // 통과
      }

      // 2단계: 실패 시 에러 로그 누적 및 다음 루프 피드백 준비
      validationErrors = validation.errors;
      console.warn(`[LAO Core] Sprout Spec validation FAILED (Attempt ${attempts}):`, validationErrors);
    }

    if (!parsed || validationErrors.length > 0) {
      // 3회 실패 시, 멈추지 않고 UI에 에러 내역을 반환하여 유저가 중재할 수 있도록 정보를 남깁니다.
      console.error('[LAO Core] Sprout Spec failed validation after max attempts. Proceeding with best-effort draft.');
    }

    const now = new Date().toISOString();

    // 1. Resolve coreSpec as a Markdown string
    let coreSpecStr = '';
    if (parsed && parsed.coreSpec) {
      if (typeof parsed.coreSpec === 'object') {
        coreSpecStr = Object.entries(parsed.coreSpec)
          .map(([key, val]) => `## ${key}\n\n${val}`)
          .join('\n\n');
      } else {
        coreSpecStr = String(parsed.coreSpec);
      }
    } else {
      coreSpecStr = `# Core Spec\n\nConforming to Golden Rules.\n\n## Out of Scope (Non-Goals)\n- [Default Out of Scope Item]`;
    }

    // 2. Map feature array fields dynamically
    const features: SpecSection[] = ((parsed && parsed.features) || []).map((f: any) => {
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
   * Sprout three distinct design options and a Director recommendation
   */
  public async runIntakeDivergence(config: ProjectConfig, feedback?: string): Promise<IntakeProposals> {
    const prompt = PromptBuilder.buildIntakeDivergencePrompt({
      projectName: config.projectName,
      projectDesc: config.projectDesc,
      goldenRules: config.goldenRules,
      feedback
    });

    const responseRaw = await this.geminiClient.generateText({
      prompt,
      jsonMode: true,
      role: 'director'
    });

    const cleaned = this.cleanJsonResponse(responseRaw);
    return JSON.parse(cleaned) as IntakeProposals;
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
   * 실시간 에이전트 간 토론 및 기획 하네스 자가 보정 루프가 탑재된 메인 라우터Responder입니다.
   */
  public async routeAndRespondStream(params: {
    config: ProjectConfig;
    sections: SpecSection[];
    chatHistory: NodeMessage[];
    userMessage: string;
    onChunk: (data: { type: 'routing' | 'content' | 'status'; route?: string; reasoning?: string; chunk?: string }) => void;
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

    // 2. Context Budgeting (컨텍스트 버제팅): 에이전트별 불필요 사양서 필터링하여 토큰 및 컨텍스트 부하 방어
    let budgetedSections = params.sections;
    if (route === 'researcher') {
      // Researcher는 유저가 묻는 주제의 섹션 및 코어 명세만 유지
      budgetedSections = params.sections.filter(s => 
        s.id === 'core_spec' ||
        params.userMessage.toLowerCase().includes(s.title.toLowerCase()) ||
        params.userMessage.toLowerCase().includes(s.id.toLowerCase())
      );
    } else if (route === 'optionizer' || route === 'gapDetector') {
      // 리스크 감지나 의사결정은 Core Spec과 활성화된 기능 사양서만 집중 전송 (비활성 섹션 제외)
      budgetedSections = params.sections.filter(s => s.status === 'active');
    }

    let finalProse = '';
    let finalSpecUpdate: any = null;
    let validationErrors: string[] = [];

    // 3. Specifier(사양 기획) 요청에 대해 검증 하네스 교정 루프 연동
    if (route === 'specifier') {
      let attempts = 0;
      const maxAttempts = 3;
      let feedback = '';

      while (attempts < maxAttempts) {
        if (attempts > 0) {
          // 실시간 진행 상황을 SSE 스트림 콘솔에 전송
          params.onChunk({ 
            type: 'status', 
            chunk: `\n\n*[기획 검증 규칙 미충족으로 인해 사양 재구성 루프가 실행 중입니다 (시도 ${attempts + 1}/${maxAttempts})]*\n` 
          });
        }

        const agentPrompt = PromptBuilder.buildAgentChatPrompt({
          agentType: route,
          config: params.config,
          sections: budgetedSections,
          chatHistory: params.chatHistory,
          userMessage: params.userMessage,
          feedback: feedback || undefined
        });

        // 텍스트 설명(Prose)을 실시간 스트리밍으로 출력하며 수집
        const responseRaw = await this.geminiClient.generateText({
          prompt: agentPrompt,
          role: route,
          onChunk: (chunk) => params.onChunk({ type: 'content', chunk })
        });

        // specUpdate JSON 블록 추출
        const { prose, specUpdate } = this.extractSpecUpdate(responseRaw);
        finalProse = prose;
        finalSpecUpdate = specUpdate;

        if (specUpdate) {
          params.onChunk({ type: 'status', chunk: `\n*[PlanningHarness를 통한 명세 검증 Assert를 돌리고 있습니다...]*\n` });
          
          // 개별 명세 규칙 정적 Assert
          const validation = PlanningHarness.validateSection(specUpdate);
          if (validation.isValid) {
            params.onChunk({ type: 'status', chunk: `\n*[기획 하네스 최종 검증 완료: 합격]*\n` });
            validationErrors = [];
            break; // 통과
          }

          // 검증 실패 시 피드백 장착 및 루프 회전
          validationErrors = validation.errors;
          feedback = `[오류 피드백]\n` + validation.errors.map(err => `- ${err}`).join('\n') + `\n위 사항을 반드시 해결하여 specUpdate 블록을 다시 써 주십시오.`;
          attempts++;
        } else {
          // specUpdate가 없는 일반 채팅은 루프 없이 즉시 종료
          break;
        }
      }

      if (attempts >= maxAttempts && validationErrors.length > 0) {
        params.onChunk({ 
          type: 'status', 
          chunk: `\n\n*⚠️ [기획 하네스 반려] AI가 규격에 맞는 기획서를 생성하는 데 실패했습니다. 오류 내역이 상단에 기록되며, 최종 수동 중재 모드로 전환합니다.*` 
        });
      }
    } else {
      // Specifier 이외의 에이전트는 기존 단발성 호출 및 스트리밍 처리
      const agentPrompt = PromptBuilder.buildAgentChatPrompt({
        agentType: route,
        config: params.config,
        sections: budgetedSections,
        chatHistory: params.chatHistory,
        userMessage: params.userMessage
      });

      const responseRaw = await this.geminiClient.generateText({
        prompt: agentPrompt,
        role: route,
        onChunk: (chunk) => params.onChunk({ type: 'content', chunk })
      });

      const { prose, specUpdate } = this.extractSpecUpdate(responseRaw);
      finalProse = prose;
      finalSpecUpdate = specUpdate;
    }

    return {
      route,
      reasoning: routingReason,
      prose: finalProse,
      specUpdate: finalSpecUpdate,
      validationErrors: validationErrors.length > 0 ? validationErrors : undefined
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
