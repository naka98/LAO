export interface SpecSection {
  id: string;
  title: string;
  content: string;
  status: 'active' | 'deprecated';
  createdAt: string;
  updatedAt: string;
}

export interface DecisionOption {
  name: string;
  desc: string;
  approved: boolean;
}

export interface DecisionCard {
  id: string;
  section: string;
  title: string;
  options: DecisionOption[];
  status: 'pending' | 'decided';
  reason?: string;
  createdAt: string;
  updatedAt: string;
}

export interface GoldenRules {
  frontend: string;
  backend: string;
  database: string;
  additional: string;
}

export interface AgentSetting {
  provider: string;
  model: string;
}

export interface IntakeOption {
  key: 'A' | 'B' | 'C';
  title: string;
  objective: string;
  coreUser: string;
  scope: string[];
  pros: string[];
  cons: string[];
  recommendedScenario: string;
}

export interface DirectorRecommendation {
  recommendedOption: 'A' | 'B' | 'C';
  reason: string;
  discardedOptions: string;
  combinedElements?: string;
  userDecisionsRequired: string[];
}

export interface IntakeProposals {
  options: {
    A: IntakeOption;
    B: IntakeOption;
    C: IntakeOption;
  };
  recommendation: DirectorRecommendation;
}

export interface ProjectConfig {
  sprouted?: boolean;
  projectName: string;
  projectDesc: string;
  automationLevel: 'supervised' | 'interactive' | 'autopilot';
  phase: 'planning' | 'development';
  goldenRules: GoldenRules;
  settings: {
    provider: string;
    model: string;
    agents: {
      director: AgentSetting;
      specifier: AgentSetting;
      researcher: AgentSetting;
      optionizer: AgentSetting;
      gapDetector: AgentSetting;
    };
  };
  developerLoop: {
    buildCommand: string;
    launchCommand: string;
    verifyCommand: string;
    uiCheckCommand: string;
  };
  proposals?: IntakeProposals;
  selectedOptionKey?: 'A' | 'B' | 'C' | 'custom';
  onboardingStep?: number;
}

export interface NodeMessage {
  id: string;
  author: 'user' | 'director' | 'specifier' | 'researcher' | 'optionizer' | 'gapDetector';
  content: string;
  createdAt: string;
}

export interface TaskItem {
  index: number;
  text: string;
  status: 'todo' | 'in_progress' | 'done';
}

