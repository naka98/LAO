import { ProjectConfig, SpecSection, DecisionCard, NodeMessage } from '../../models';

export interface AgentGraphState {
  // 프로젝트 기본 컨텍스트 및 상태
  config: ProjectConfig;
  sections: SpecSection[];
  decisions: DecisionCard[];
  messages: NodeMessage[];
  
  // 입력 및 라우팅 상태
  userMessage: string;
  currentRoute: 'director' | 'specifier' | 'researcher' | 'optionizer' | 'gapDetector' | 'validator' | 'end';
  routingReason: string;
  selectedAgent?: 'specifier' | 'researcher' | 'optionizer' | 'gapDetector';
  
  // 에이전트 생성 결과 임시 버퍼
  tempProse: string;
  tempSpecUpdate?: {
    sectionId: string;
    title?: string;
    content: string;
  };
  
  // 검증 및 루프 상태
  validationErrors?: string[];
  attempts: number;
  maxAttempts: number;
  previousAttempt?: string;
  
  // 동시성 및 실행 제어 상태
  requestUuid?: string;
  abortSignal?: AbortSignal;
  isDone: boolean;
}

export function createInitialState(params: {
  config: ProjectConfig;
  sections: SpecSection[];
  decisions: DecisionCard[];
  messages: NodeMessage[];
  userMessage: string;
  requestUuid?: string;
  abortSignal?: AbortSignal;
}): AgentGraphState {
  return {
    config: params.config,
    sections: params.sections,
    decisions: params.decisions,
    messages: params.messages,
    userMessage: params.userMessage,
    currentRoute: 'director',
    routingReason: '',
    selectedAgent: undefined,
    tempProse: '',
    attempts: 0,
    maxAttempts: 3,
    validationErrors: undefined,
    previousAttempt: undefined,
    requestUuid: params.requestUuid,
    abortSignal: params.abortSignal,
    isDone: false
  };
}
