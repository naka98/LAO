import { GeminiClient } from '../../../gemini';
import { AgentGraphState } from '../state';
import { PromptBuilder } from '../../promptBuilder';
import { extractSpecUpdate } from '../utils';

export async function optionizerNode(
  state: AgentGraphState,
  geminiClient: GeminiClient,
  onChunk: (data: any) => void
): Promise<AgentGraphState> {
  const nextState = structuredClone(state);

  // 리스크 감지나 의사결정은 Core Spec과 활성화된 기능 사양서만 집중 전송 (비활성 섹션 제외)
  const budgetedSections = nextState.sections.filter(s => s.status === 'active');

  const agentPrompt = PromptBuilder.buildAgentChatPrompt({
    agentType: 'optionizer',
    config: nextState.config,
    sections: budgetedSections,
    chatHistory: nextState.messages,
    userMessage: nextState.userMessage
  });

  let responseRaw = '';
  try {
    responseRaw = await geminiClient.generateText({
      prompt: agentPrompt,
      role: 'optionizer',
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

  const { prose, specUpdate } = extractSpecUpdate(responseRaw);
  nextState.tempProse = prose;
  nextState.tempSpecUpdate = specUpdate;

  if (specUpdate) {
    nextState.currentRoute = 'validator';
  } else {
    nextState.currentRoute = 'end';
    nextState.isDone = true;
  }

  return nextState;
}
