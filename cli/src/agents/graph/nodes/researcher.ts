import { GeminiClient } from '../../../gemini';
import { AgentGraphState } from '../state';
import { PromptBuilder } from '../../promptBuilder';
import { extractSpecUpdate } from '../utils';

export async function researcherNode(
  state: AgentGraphState,
  geminiClient: GeminiClient,
  onChunk: (data: any) => void
): Promise<AgentGraphState> {
  const nextState = structuredClone(state);

  // Researcher는 유저가 묻는 주제의 섹션 및 코어 명세만 유지
  const budgetedSections = nextState.sections.filter(s => 
    s.id === 'core_spec' ||
    nextState.userMessage.toLowerCase().includes(s.title.toLowerCase()) ||
    nextState.userMessage.toLowerCase().includes(s.id.toLowerCase())
  );

  const agentPrompt = PromptBuilder.buildAgentChatPrompt({
    agentType: 'researcher',
    config: nextState.config,
    sections: budgetedSections,
    chatHistory: nextState.messages,
    userMessage: nextState.userMessage
  });

  let responseRaw = '';
  try {
    responseRaw = await geminiClient.generateText({
      prompt: agentPrompt,
      role: 'researcher',
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
