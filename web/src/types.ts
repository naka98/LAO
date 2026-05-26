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

export interface ProjectConfig {
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
}

export interface NodeMessage {
  id: string;
  author: 'user' | 'director' | 'specifier' | 'researcher' | 'optionizer' | 'gapDetector';
  content: string;
  createdAt: string;
}
