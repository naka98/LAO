import { GeminiClient } from '../../../../gemini';
import { ProjectConfig, SpecSection, NodeMessage } from '../../../../models';
import { PromptBuilder } from '../../../promptBuilder';

export async function runTestScenarioAgent(params: {
  geminiClient: GeminiClient;
  config: ProjectConfig;
  section: SpecSection;
  userMessage: string;
  chatHistory: NodeMessage[];
}): Promise<string> {
  const prompt = PromptBuilder.buildTestScenarioAgentPrompt({
    config: params.config,
    section: params.section,
    userMessage: params.userMessage,
    chatHistory: params.chatHistory
  });

  const response = await params.geminiClient.generateText({
    prompt,
    role: 'specifier'
  });

  return response.trim();
}
