import { GeminiClient } from '../../../gemini';
import { AgentGraphState } from '../state';
import { PromptBuilder } from '../../promptBuilder';
import { extractSpecUpdate, cleanJsonResponse } from '../utils';
import { runSchemaAgent } from './subagents/schemaAgent';
import { runUISpecAgent } from './subagents/uiSpecAgent';
import { runTestScenarioAgent } from './subagents/testScenarioAgent';

// Helper to keep DB Schema & API Signatures during Context Budgeting
function stubifyContent(content: string): string {
  const lines = content.split('\n');
  const keptSections: string[] = [];
  let currentSectionTitle = '';
  let currentSectionContent: string[] = [];
  let capturing = false;

  for (const line of lines) {
    if (line.startsWith('## ')) {
      if (capturing && currentSectionContent.length > 0) {
        keptSections.push(`## ${currentSectionTitle}\n${currentSectionContent.join('\n')}`);
      }
      
      const title = line.substring(3).trim();
      if (
        /database\s*schema|schema|db\s*schema|api\s*signatures|api|endpoint/i.test(title)
      ) {
        currentSectionTitle = title;
        currentSectionContent = [];
        capturing = true;
      } else {
        capturing = false;
      }
    } else if (capturing) {
      currentSectionContent.push(line);
    }
  }

  if (capturing && currentSectionContent.length > 0) {
    keptSections.push(`## ${currentSectionTitle}\n${currentSectionContent.join('\n')}`);
  }

  const stubbedMessage = `<!-- Content stubbed out for context budgeting. Feature is Active. -->`;
  if (keptSections.length > 0) {
    return `${stubbedMessage}\n\n${keptSections.join('\n\n')}`;
  }
  return stubbedMessage;
}

// Helper to replace sections in original markdown content
function mergeSubagentUpdates(
  originalContent: string, 
  schemaUpdate?: string, 
  uiUpdate?: string, 
  testUpdate?: string
): string {
  let content = originalContent;

  const replaceSection = (contentStr: string, sectionTitleRegex: RegExp, newSectionContent: string): string => {
    const lines = contentStr.split('\n');
    let startIdx = -1;
    let endIdx = -1;

    for (let i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('## ') && sectionTitleRegex.test(lines[i].substring(3).trim())) {
        startIdx = i;
        for (let j = i + 1; j < lines.length; j++) {
          if (lines[j].startsWith('## ')) {
            endIdx = j;
            break;
          }
        }
        break;
      }
    }

    if (startIdx !== -1) {
      const before = lines.slice(0, startIdx);
      const after = endIdx !== -1 ? lines.slice(endIdx) : [];
      return [...before, newSectionContent, ...after].join('\n');
    } else {
      return contentStr + '\n\n' + newSectionContent;
    }
  };

  if (schemaUpdate && schemaUpdate.trim()) {
    content = replaceSection(content, /database\s*schema|schema|db\s*schema/i, schemaUpdate.trim());
  }
  if (uiUpdate && uiUpdate.trim()) {
    content = replaceSection(content, /ui\s*spec|ui\s*design|interaction|layout/i, uiUpdate.trim());
  }
  if (testUpdate && testUpdate.trim()) {
    content = replaceSection(content, /acceptance\s*criteria|test\s*scenario|scenarios/i, testUpdate.trim());
  }

  return content;
}

export async function specifierNode(
  state: AgentGraphState,
  geminiClient: GeminiClient,
  onChunk: (data: any) => void
): Promise<AgentGraphState> {
  const nextState = structuredClone(state);

  // 1. Context Budgeting (컨텍스트 버제팅) with Interface Stubbing
  const totalLen = nextState.sections.reduce((acc, s) => acc + s.content.length, 0);
  let budgetedSections = nextState.sections;

  if (totalLen > 10000) {
    const userMsgLower = nextState.userMessage.toLowerCase();
    const recentHistoryText = nextState.messages.slice(-3).map(m => m.content).join(' ').toLowerCase();

    budgetedSections = nextState.sections.map(s => {
      if (s.id === 'core_spec') return s;
      
      const isMentioned = userMsgLower.includes(s.title.toLowerCase()) ||
                          userMsgLower.includes(s.id.toLowerCase()) ||
                          recentHistoryText.includes(s.title.toLowerCase()) ||
                          recentHistoryText.includes(s.id.toLowerCase());
      if (isMentioned) {
        return s;
      } else {
        return {
          ...s,
          content: stubifyContent(s.content)
        };
      }
    });
  }

  // 루프백 시 찌꺼기 초기화
  nextState.tempProse = '';
  nextState.tempSpecUpdate = undefined;

  if (nextState.attempts > 0) {
    onChunk({ 
      type: 'status', 
      chunk: `\n\n*[기획 검증 규칙 미충족으로 인해 사양 재구성 루프가 실행 중입니다 (시도 ${nextState.attempts + 1}/${nextState.maxAttempts})]*\n` 
    });
  }

  // 2. Spec Coordinator Planning
  let plan: {
    targetSectionId: string;
    runSchema: boolean;
    runUI: boolean;
    runTest: boolean;
    proseExplanation: string;
  } | null = null;

  onChunk({ type: 'status', chunk: `*[Spec Coordinator가 변경 계획을 수립하고 있습니다...]*\n` });

  try {
    const planPrompt = PromptBuilder.buildCoordinatorPlanPrompt({
      config: nextState.config,
      sections: budgetedSections,
      chatHistory: nextState.messages,
      userMessage: nextState.userMessage
    });

    const planRaw = await geminiClient.generateText({
      prompt: planPrompt,
      jsonMode: true,
      role: 'specifier',
      abortSignal: nextState.abortSignal
    });

    const cleanedPlan = cleanJsonResponse(planRaw);
    plan = JSON.parse(cleanedPlan);
  } catch (e) {
    console.warn('[LAO Coordinator] Planning failed, falling back to monolithic spec update', e);
  }

  // 3. Subagent Scatter-Gather or Fallback Monolithic Call
  if (plan && plan.targetSectionId && (plan.runSchema || plan.runUI || plan.runTest)) {
    const targetSection = nextState.sections.find(s => s.id === plan!.targetSectionId);
    if (targetSection && targetSection.id !== 'core_spec') {
      onChunk({ 
        type: 'status', 
        chunk: `*[Coordinator 판단: ${plan.proseExplanation} (대상: ${targetSection.title})]*\n` 
      });

      let schemaUpdate = '';
      let uiUpdate = '';
      let testUpdate = '';

      if (plan.runSchema) {
        onChunk({ type: 'status', chunk: `*[Schema Agent 기동: 데이터 스키마 설계를 보완하고 있습니다...]*\n` });
        schemaUpdate = await runSchemaAgent({
          geminiClient,
          config: nextState.config,
          section: targetSection,
          userMessage: nextState.userMessage,
          chatHistory: nextState.messages
        });
      }

      if (plan.runUI) {
        onChunk({ type: 'status', chunk: `*[UI Spec Agent 기동: 사용자 인터페이스 명세를 수정하고 있습니다...]*\n` });
        uiUpdate = await runUISpecAgent({
          geminiClient,
          config: nextState.config,
          section: targetSection,
          userMessage: nextState.userMessage,
          chatHistory: nextState.messages
        });
      }

      if (plan.runTest) {
        onChunk({ type: 'status', chunk: `*[Test Scenario Agent 기동: 인수조건(Given-When-Then)을 보강하고 있습니다...]*\n` });
        testUpdate = await runTestScenarioAgent({
          geminiClient,
          config: nextState.config,
          section: targetSection,
          userMessage: nextState.userMessage,
          chatHistory: nextState.messages
        });
      }

      const mergedContent = mergeSubagentUpdates(
        targetSection.content,
        schemaUpdate,
        uiUpdate,
        testUpdate
      );

      nextState.tempProse = plan.proseExplanation;
      nextState.tempSpecUpdate = {
        sectionId: targetSection.id,
        title: targetSection.title,
        content: mergedContent
      };

      // UI에 생성 진행 내용 출력
      onChunk({ type: 'content', chunk: plan.proseExplanation + '\n\n*[특화 서브에이전트들이 생성한 업데이트 내용을 합산하여 반영했습니다.]*' });

      nextState.currentRoute = 'validator';
      return nextState;
    }
  }

  // Fallback: 기존 Monolithic Spec update (코어 스펙 수정이나 서브에이전트 분기가 불필요한 경우)
  onChunk({ type: 'status', chunk: `*[일반 Specifier 모드로 사양 업데이트를 일괄 진행합니다...]*\n` });
  const feedback = nextState.validationErrors && nextState.validationErrors.length > 0
    ? `[오류 피드백]\n` + nextState.validationErrors.map(err => `- ${err}`).join('\n')
    : undefined;

  const agentPrompt = PromptBuilder.buildAgentChatPrompt({
    agentType: 'specifier',
    config: nextState.config,
    sections: budgetedSections,
    chatHistory: nextState.messages,
    userMessage: nextState.userMessage,
    feedback: feedback || undefined,
    previousAttempt: nextState.previousAttempt
  });

  let responseRaw = '';
  try {
    responseRaw = await geminiClient.generateText({
      prompt: agentPrompt,
      role: 'specifier',
      onChunk: (chunk) => onChunk({ type: 'content', chunk }),
      abortSignal: nextState.abortSignal
    });
  } catch (err: any) {
    if (err.message === 'Aborted') {
      nextState.isDone = true;
      nextState.currentRoute = 'end';
      return nextState;
    }
    throw err;
  }

  // specUpdate 추출 및 저장
  const marker = '```specUpdate';
  const startIdx = responseRaw.indexOf(marker);
  if (startIdx !== -1) {
    const rest = responseRaw.substring(startIdx + marker.length);
    const endIdx = rest.indexOf('```');
    if (endIdx !== -1) {
      nextState.previousAttempt = rest.substring(0, endIdx).trim();
    }
  }

  const { prose, specUpdate } = extractSpecUpdate(responseRaw);
  nextState.tempProse = prose;
  nextState.tempSpecUpdate = specUpdate;

  // 형식 검증 실패 사전 체크
  const hasSpecUpdateBlock = responseRaw.includes('```specUpdate');
  if (hasSpecUpdateBlock && !specUpdate) {
    nextState.validationErrors = [
      'The ```specUpdate block formatting is incorrect. Ensure you have sectionId, title (optional) followed by a line with ===, then the markdown content.'
    ];
    nextState.currentRoute = 'validator';
    return nextState;
  }

  // 세이프가드: Stub된 스펙 덮어쓰기 감지
  if (specUpdate) {
    const budgetedSection = budgetedSections.find(s => s.id === specUpdate.sectionId);
    if (budgetedSection && budgetedSection.content.includes('Content stubbed out')) {
      nextState.validationErrors = [
        `Cannot update feature "${specUpdate.sectionId}" while its content is stubbed out. Mention the feature explicitly in your prompt.`
      ];
      nextState.currentRoute = 'validator';
      return nextState;
    }
  }

  nextState.currentRoute = 'validator';
  return nextState;
}
