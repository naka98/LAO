import { ProjectConfig, SpecSection, DecisionCard, NodeMessage, IntakeOption, IntakeProposals } from '../models';
import { GeminiClient } from '../gemini';
import { PromptBuilder } from './promptBuilder';
import { randomUUID } from 'crypto';
import { PlanningHarness } from './harness';
import { createInitialState } from './graph/state';
import { directorNode } from './graph/nodes/director';
import { specifierNode } from './graph/nodes/specifier';
import { researcherNode } from './graph/nodes/researcher';
import { optionizerNode } from './graph/nodes/optionizer';
import { gapDetectorNode } from './graph/nodes/gapDetector';
import { validatorNode } from './graph/nodes/validator';
import { cleanJsonResponse, extractSpecUpdate } from './graph/utils';

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
    let previousAttempt: string | undefined = undefined;

    console.log('[LAO Core] Intake Sprout (Skeleton) started with PlanningHarness Loop.');

    // 1단계: 뼈대 생성 루프
    while (attempts < maxAttempts) {
      attempts++;
      console.log(`[LAO Core] Sprouting skeleton attempt ${attempts}/${maxAttempts}`);
      
      const prompt = PromptBuilder.buildIntakeSproutPrompt({
        projectName: config.projectName,
        projectDesc: config.projectDesc,
        goldenRules: config.goldenRules,
        chosenOption,
        userAdjustments,
        feedback: validationErrors.length > 0 ? validationErrors.join('\n') : undefined,
        previousAttempt
      });

      const responseRaw = await this.geminiClient.generateText({
        prompt,
        jsonMode: true,
        role: 'specifier'
      });

      previousAttempt = responseRaw;

      let cleaned = '';
      try {
        cleaned = cleanJsonResponse(responseRaw);
        parsed = JSON.parse(cleaned);
      } catch (e: any) {
        console.warn(`[LAO Core] JSON parse failed on skeleton sprout attempt ${attempts}:`, e);
        validationErrors = [`JSON parsing error: ${e.message}. Ensure your output matches a single valid JSON block.`];
        continue;
      }

      // 기획 하네스 뼈대 검증
      const validation = PlanningHarness.validateSkeleton(parsed);
      if (validation.isValid) {
        console.log('[LAO Core] Sprout Skeleton validation PASSED on attempt ' + attempts);
        validationErrors = [];
        break; // 통과
      }

      validationErrors = validation.errors;
      console.warn(`[LAO Core] Sprout Skeleton validation FAILED (Attempt ${attempts}):`, validationErrors);
    }

    if (!parsed || validationErrors.length > 0) {
      console.error('[LAO Core] Sprout Skeleton failed validation after max attempts. Proceeding with best-effort draft.');
    }

    const now = new Date().toISOString();

    // Core Spec 마크다운 문자열 추출
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

    // 2단계: 각 Feature 순차 상세화(Elaboration) 루프
    const rawFeatures = (parsed && parsed.features) || [];
    const features: SpecSection[] = [];

    for (const rawFeat of rawFeatures) {
      const featId = rawFeat.id || randomUUID().substring(0, 8);
      const featTitle = rawFeat.title || rawFeat.name || 'Untitled Feature';
      const featDesc = rawFeat.description || '';
      const dependencies = rawFeat.dependencies || [];

      console.log(`[LAO Core] Elaborating feature details for: ${featTitle} (${featId})`);

      let featAttempts = 0;
      let featContent = '';
      let featErrors: string[] = [];
      let featPrevAttempt: string | undefined = undefined;

      while (featAttempts < maxAttempts) {
        featAttempts++;
        console.log(`  -> Feature elaboration attempt ${featAttempts}/${maxAttempts}`);

        const elaborationPrompt = PromptBuilder.buildFeatureElaborationPrompt({
          projectName: config.projectName,
          coreSpec: coreSpecStr,
          feature: {
            id: featId,
            title: featTitle,
            description: featDesc,
            dependencies
          },
          goldenRules: config.goldenRules,
          feedback: featErrors.length > 0 ? featErrors.join('\n') : undefined,
          previousAttempt: featPrevAttempt
        });

        const featResponseRaw = await this.geminiClient.generateText({
          prompt: elaborationPrompt,
          jsonMode: true,
          role: 'specifier'
        });

        featPrevAttempt = featResponseRaw;

        try {
          const cleanedFeat = cleanJsonResponse(featResponseRaw);
          const parsedFeat = JSON.parse(cleanedFeat);
          featContent = parsedFeat.content || '';
        } catch (e: any) {
          console.warn(`  -> JSON parse failed on feature ${featId} attempt ${featAttempts}:`, e);
          featErrors = [`JSON parsing error: ${e.message}. Ensure your output matches a single valid JSON block.`];
          continue;
        }

        // 개별 기능 마크다운 상세 검증 (GWT, User Story 필수 등)
        const valFeat = PlanningHarness.validateFeatureContent(featContent);
        if (valFeat.isValid) {
          console.log(`  -> Feature ${featId} validation PASSED on attempt ${featAttempts}`);
          featErrors = [];
          break;
        }

        featErrors = valFeat.errors;
        console.warn(`  -> Feature ${featId} validation FAILED (Attempt ${featAttempts}):`, featErrors);
      }

      if (featErrors.length > 0) {
        console.error(`  -> Feature ${featId} failed validation after max attempts. Proceeding with best-effort content.`);
      }

      // 만약 생성이 완전히 비어있거나 실패한 경우 기본값
      if (!featContent) {
        featContent = `# ${featTitle}\n\n## User Story\nAs a user, I want to experience ${featTitle}, so that I get value.\n\n## Acceptance Criteria\nScenario: Accessing ${featTitle}\nGiven the application runs\nWhen I view ${featTitle}\nThen I should see the interface.`;
      }

      features.push({
        id: featId,
        title: featTitle,
        content: featContent,
        status: 'active',
        createdAt: now,
        updatedAt: now
      });
    }

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

    const cleaned = cleanJsonResponse(responseRaw);
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

    const cleaned = cleanJsonResponse(responseRaw);
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
   * State-Graph Agent Architecture 루프로 전면 교체되었습니다.
   */
  public async routeAndRespondStream(params: {
    config: ProjectConfig;
    sections: SpecSection[];
    chatHistory: NodeMessage[];
    userMessage: string;
    onChunk: (data: { type: 'routing' | 'content' | 'status'; route?: string; reasoning?: string; chunk?: string }) => void;
    abortSignal?: AbortSignal;
    requestUuid?: string;
  }): Promise<RouteAndRespondResult> {
    
    // 1. 초기 전역 상태 생성
    let state = createInitialState({
      config: params.config,
      sections: params.sections,
      decisions: [],
      messages: params.chatHistory,
      userMessage: params.userMessage,
      requestUuid: params.requestUuid,
      abortSignal: params.abortSignal
    });

    // 2. 그래프 상태 전이 실행 루프
    while (!state.isDone) {
      if (params.abortSignal?.aborted) {
        state.isDone = true;
        state.currentRoute = 'end';
        break;
      }

      switch (state.currentRoute) {
        case 'director':
          state = await directorNode(state, this.geminiClient, params.onChunk);
          break;
        case 'specifier':
          state = await specifierNode(state, this.geminiClient, params.onChunk);
          break;
        case 'researcher':
          state = await researcherNode(state, this.geminiClient, params.onChunk);
          break;
        case 'optionizer':
          state = await optionizerNode(state, this.geminiClient, params.onChunk);
          break;
        case 'gapDetector':
          state = await gapDetectorNode(state, this.geminiClient, params.onChunk);
          break;
        case 'validator':
          state = await validatorNode(state, params.onChunk);
          break;
        case 'end':
        default:
          state.isDone = true;
          break;
      }
    }

    // 3. 최종 라우트 정보 정규화 (author 스키마 컴파일 충돌 방지용)
    const finalRoute = state.selectedAgent || 'specifier';

    return {
      route: finalRoute,
      reasoning: state.routingReason,
      prose: state.tempProse,
      specUpdate: state.tempSpecUpdate,
      validationErrors: state.validationErrors
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
