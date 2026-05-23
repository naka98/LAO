import * as fs from 'fs';
import * as path from 'path';
import { MindmapData, GraphNode, GraphEdge } from './models';
import { randomUUID } from 'crypto';

export interface AgentSetting {
  provider: string;
  model: string;
}

export interface SettingsData {
  provider: string;
  model: string;
  agents?: {
    director: AgentSetting;
    specifier: AgentSetting;
    researcher: AgentSetting;
    optionizer: AgentSetting;
    gapDetector: AgentSetting;
  };
}

const LAO_DIR_NAME = '.lao';
const MINDMAP_FILE_NAME = 'mindmap.json';
const CRITERIA_FILE_NAME = 'criteria.md';

export class StorageManager {
  private laoDirPath: string;
  private mindmapFilePath: string;
  private criteriaFilePath: string;
  private settingsFilePath: string;

  constructor(projectRoot: string) {
    this.laoDirPath = path.join(projectRoot, LAO_DIR_NAME);
    this.mindmapFilePath = path.join(this.laoDirPath, MINDMAP_FILE_NAME);
    this.criteriaFilePath = path.join(this.laoDirPath, CRITERIA_FILE_NAME);
    this.settingsFilePath = path.join(this.laoDirPath, 'settings.json');
  }

  /**
   * Initializes the storage. Creates the .lao directory and default files if they do not exist.
   */
  public initStorage(projectName: string = 'New LAO Project'): MindmapData {
    if (!fs.existsSync(this.laoDirPath)) {
      fs.mkdirSync(this.laoDirPath, { recursive: true });
    }

    if (!fs.existsSync(this.criteriaFilePath)) {
      fs.writeFileSync(
        this.criteriaFilePath,
        `# LAO Decision Criteria Log\n\nThis file tracks the decisions and design criteria accumulated over the course of this project.\n\n`,
        'utf8'
      );
    }

    if (!fs.existsSync(this.settingsFilePath)) {
      const defaultGlobalProvider = (process.env.LAO_PROVIDER || 'gemini').toLowerCase();
      const defaultGlobalModel = process.env.LAO_MODEL || '';
      const defaultSettings: SettingsData = {
        provider: defaultGlobalProvider,
        model: defaultGlobalModel,
        agents: {
          director: { provider: defaultGlobalProvider, model: defaultGlobalModel },
          specifier: { provider: defaultGlobalProvider, model: defaultGlobalModel },
          researcher: { provider: defaultGlobalProvider, model: defaultGlobalModel },
          optionizer: { provider: defaultGlobalProvider, model: defaultGlobalModel },
          gapDetector: { provider: defaultGlobalProvider, model: defaultGlobalModel },
        }
      };
      fs.writeFileSync(this.settingsFilePath, JSON.stringify(defaultSettings, null, 2), 'utf8');
    }

    if (!fs.existsSync(this.mindmapFilePath)) {
      const now = new Date().toISOString();
      const seedNodeId = randomUUID();
      
      const defaultData: MindmapData = {
        nodes: [],
        edges: [],
        messages: [],
        userProfile: {
          name: 'Designer',
          title: 'Product Creator',
          bio: 'LAO를 이용해 멋진 기획을 설계하고 있습니다.',
        },
      };

      this.writeMindmap(defaultData);
      return defaultData;
    }

    return this.readMindmap();
  }

  /**
   * Reads settings.json
   */
  public readSettings(): SettingsData {
    const defaultGlobalProvider = (process.env.LAO_PROVIDER || 'gemini').toLowerCase();
    const defaultGlobalModel = process.env.LAO_MODEL || '';

    const defaultAgents = (prov: string, mod: string) => ({
      director: { provider: prov, model: mod },
      specifier: { provider: prov, model: mod },
      researcher: { provider: prov, model: mod },
      optionizer: { provider: prov, model: mod },
      gapDetector: { provider: prov, model: mod },
    });

    if (!fs.existsSync(this.settingsFilePath)) {
      return {
        provider: defaultGlobalProvider,
        model: defaultGlobalModel,
        agents: defaultAgents(defaultGlobalProvider, defaultGlobalModel),
      };
    }
    try {
      const raw = fs.readFileSync(this.settingsFilePath, 'utf8');
      const data = JSON.parse(raw);
      
      const provider = (data.provider || defaultGlobalProvider).toLowerCase();
      const model = data.model || defaultGlobalModel;
      
      const agents = {
        director: {
          provider: data.agents?.director?.provider || provider,
          model: data.agents?.director?.model !== undefined ? data.agents.director.model : model
        },
        specifier: {
          provider: data.agents?.specifier?.provider || provider,
          model: data.agents?.specifier?.model !== undefined ? data.agents.specifier.model : model
        },
        researcher: {
          provider: data.agents?.researcher?.provider || provider,
          model: data.agents?.researcher?.model !== undefined ? data.agents.researcher.model : model
        },
        optionizer: {
          provider: data.agents?.optionizer?.provider || provider,
          model: data.agents?.optionizer?.model !== undefined ? data.agents.optionizer.model : model
        },
        gapDetector: {
          provider: data.agents?.gapDetector?.provider || provider,
          model: data.agents?.gapDetector?.model !== undefined ? data.agents.gapDetector.model : model
        },
      };

      return { provider, model, agents };
    } catch (e) {
      return {
        provider: defaultGlobalProvider,
        model: defaultGlobalModel,
        agents: defaultAgents(defaultGlobalProvider, defaultGlobalModel),
      };
    }
  }

  /**
   * Writes settings.json
   */
  public writeSettings(settings: SettingsData): void {
    fs.writeFileSync(this.settingsFilePath, JSON.stringify(settings, null, 2), 'utf8');
  }

  /**
   * Reads mindmap.json
   */
  public readMindmap(): MindmapData {
    if (!fs.existsSync(this.mindmapFilePath)) {
      return this.initStorage();
    }
    const raw = fs.readFileSync(this.mindmapFilePath, 'utf8');
    return JSON.parse(raw);
  }

  /**
   * Writes data to mindmap.json
   */
  public writeMindmap(data: MindmapData): void {
    fs.writeFileSync(this.mindmapFilePath, JSON.stringify(data, null, 2), 'utf8');
  }

  /**
   * Appends an entry to criteria.md
   */
  public appendCriterion(decisionTitle: string, reason: string): void {
    const entry = `## [Decision] ${decisionTitle}\n- **Date**: ${new Date().toISOString()}\n- **Reasoning**: ${reason}\n\n`;
    fs.appendFileSync(this.criteriaFilePath, entry, 'utf8');
  }

  /**
   * Reads the full criteria.md file content
   */
  public readCriteria(): string {
    if (!fs.existsSync(this.criteriaFilePath)) {
      return '';
    }
    return fs.readFileSync(this.criteriaFilePath, 'utf8');
  }

  /**
   * Writes the compiled spec document (spec_compiled.md)
   */
  public writeCompiledSpec(markdownContent: string): string {
    const specFilePath = path.join(this.laoDirPath, 'spec_compiled.md');
    fs.writeFileSync(specFilePath, markdownContent, 'utf8');
    return specFilePath;
  }
}
