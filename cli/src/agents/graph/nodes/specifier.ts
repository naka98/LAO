import { GeminiClient } from '../../../gemini';
import { AgentGraphState } from '../state';
import { PromptBuilder } from '../../promptBuilder';
import { extractSpecUpdate } from '../utils';

export async function specifierNode(
  state: AgentGraphState,
  geminiClient: GeminiClient,
  onChunk: (data: any) => void
): Promise<AgentGraphState> {
  const nextState = structuredClone(state);

  // 1. Context Budgeting (컨텍스트 버제팅)
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
          content: `<!-- Content stubbed out for context budgeting. Feature is Active. -->`
        };
      }
    });
  }

  // 루프백 시 찌꺼기 초기화 (Audit 지적사항 5.3)
  nextState.tempProse = '';
  nextState.tempSpecUpdate = undefined;

  if (nextState.attempts > 0) {
    onChunk({ 
      type: 'status', 
      chunk: `\n\n*[기획 검증 규칙 미충족으로 인해 사양 재구성 루프가 실행 중입니다 (시도 ${nextState.attempts + 1}/${nextState.maxAttempts})]*\n` 
    });
  }

  // 2. 피드백 수집 및 프롬프트 빌드
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

  // 3. LLM 호출 및 스트리밍 수집
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

  // 4. specUpdate 추출 및 저장
  // 직전 원본 결과물 기록 (자가 교정용)
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

  // 세이프가드: Stub된 스펙 덮어쓰기 감지 (Audit 지적사항 5.4)
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
