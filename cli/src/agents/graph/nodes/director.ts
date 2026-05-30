import { GeminiClient } from '../../../gemini';
import { AgentGraphState } from '../state';
import { PromptBuilder } from '../../promptBuilder';
import { cleanJsonResponse } from '../utils';

export async function directorNode(
  state: AgentGraphState,
  geminiClient: GeminiClient,
  onChunk: (data: any) => void
): Promise<AgentGraphState> {
  const nextState = structuredClone(state);
  const lowerMessage = nextState.userMessage.toLowerCase();
  let route: 'specifier' | 'researcher' | 'optionizer' | 'gapDetector' = 'specifier';
  let routingReason = 'Vague intent fallback';
  let matchedOverride = false;

  if (lowerMessage.includes('@specifier')) {
    route = 'specifier';
    routingReason = 'Static override via @specifier mention';
    matchedOverride = true;
  } else if (lowerMessage.includes('@researcher')) {
    route = 'researcher';
    routingReason = 'Static override via @researcher mention';
    matchedOverride = true;
  } else if (lowerMessage.includes('@optionizer')) {
    route = 'optionizer';
    routingReason = 'Static override via @optionizer mention';
    matchedOverride = true;
  } else if (lowerMessage.includes('@gapdetector') || lowerMessage.includes('@gap_detector')) {
    route = 'gapDetector';
    routingReason = 'Static override via @gapDetector mention';
    matchedOverride = true;
  }

  if (!matchedOverride) {
    const directorPrompt = PromptBuilder.buildDirectorRoutingPrompt({
      config: nextState.config,
      chatHistory: nextState.messages,
      userMessage: nextState.userMessage
    });

    try {
      const directorResponseRaw = await geminiClient.generateText({
        prompt: directorPrompt,
        jsonMode: true,
        role: 'director',
        abortSignal: nextState.abortSignal
      });

      const cleanedDirector = cleanJsonResponse(directorResponseRaw);
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
  }

  // Notify client of selected agent route
  onChunk({ type: 'routing', route, reasoning: routingReason });

  nextState.currentRoute = route;
  nextState.routingReason = routingReason;
  nextState.selectedAgent = route;

  return nextState;
}
