import * as fs from 'fs';
import * as path from 'path';
import { ProjectConfig, SpecSection, DecisionCard, NodeMessage, GoldenRules } from './models';
import { randomUUID } from 'crypto';

const LAO_DIR_NAME = '.lao';

export class StorageManager {
  private laoDirPath: string;
  private specsDirPath: string;
  private featuresDirPath: string;
  private decisionsDirPath: string;
  private configFilePath: string;
  private criteriaFilePath: string;
  private compiledSpecFilePath: string;
  private messagesFilePath: string;
  private taskFilePath: string;

  constructor(projectRoot: string) {
    this.laoDirPath = path.join(projectRoot, LAO_DIR_NAME);
    this.specsDirPath = path.join(this.laoDirPath, 'specs');
    this.featuresDirPath = path.join(this.specsDirPath, 'features');
    this.decisionsDirPath = path.join(this.laoDirPath, 'decisions');
    this.configFilePath = path.join(this.laoDirPath, 'lao.config.json');
    this.criteriaFilePath = path.join(this.laoDirPath, 'criteria.md');
    this.compiledSpecFilePath = path.join(this.laoDirPath, 'spec_compiled.md');
    this.messagesFilePath = path.join(this.laoDirPath, 'messages.json');
    this.taskFilePath = path.join(this.laoDirPath, 'task.md');
  }

  /**
   * Initializes the storage folder structure and default files if they do not exist.
   */
  public initStorage(projectName: string = 'New LAO Project', projectDesc: string = 'A new local AI office project.'): ProjectConfig {
    // Create folders
    if (!fs.existsSync(this.laoDirPath)) fs.mkdirSync(this.laoDirPath, { recursive: true });
    if (!fs.existsSync(this.specsDirPath)) fs.mkdirSync(this.specsDirPath, { recursive: true });
    if (!fs.existsSync(this.featuresDirPath)) fs.mkdirSync(this.featuresDirPath, { recursive: true });
    if (!fs.existsSync(this.decisionsDirPath)) fs.mkdirSync(this.decisionsDirPath, { recursive: true });

    // Criteria log
    if (!fs.existsSync(this.criteriaFilePath)) {
      fs.writeFileSync(
        this.criteriaFilePath,
        `# LAO Decision Criteria Log\n\nThis file tracks the decisions and design criteria accumulated over the course of this project.\n\n`,
        'utf8'
      );
    }

    // Config file
    if (!fs.existsSync(this.configFilePath)) {
      const defaultGlobalProvider = (process.env.LAO_PROVIDER || 'gemini').toLowerCase();
      const defaultGlobalModel = process.env.LAO_MODEL || 'gemini-2.5-flash';
      
      const defaultConfig: ProjectConfig = {
        sprouted: false,
        projectName,
        projectDesc,
        automationLevel: 'supervised',
        phase: 'planning',
        goldenRules: {
          frontend: 'React, Vite, Vanilla CSS',
          backend: 'Node.js Express, TypeScript',
          database: 'SQLite',
          additional: 'RESTful API structure'
        },
        settings: {
          provider: defaultGlobalProvider,
          model: defaultGlobalModel,
          agents: {
            director: { provider: defaultGlobalProvider, model: defaultGlobalModel },
            specifier: { provider: defaultGlobalProvider, model: defaultGlobalModel },
            researcher: { provider: defaultGlobalProvider, model: defaultGlobalModel },
            optionizer: { provider: defaultGlobalProvider, model: defaultGlobalModel },
            gapDetector: { provider: defaultGlobalProvider, model: defaultGlobalModel },
          }
        },
        developerLoop: {
          buildCommand: 'npm run build',
          launchCommand: 'npx -y http-server web/dist -p 3000',
          verifyCommand: 'npm test',
          uiCheckCommand: '',
        }
      };
      this.writeConfig(defaultConfig);
    }

    // Messages log
    if (!fs.existsSync(this.messagesFilePath)) {
      fs.writeFileSync(this.messagesFilePath, JSON.stringify([], null, 2), 'utf8');
    }

    // Seed core_spec.md if it doesn't exist
    const coreSpecPath = path.join(this.specsDirPath, 'core_spec.md');
    if (!fs.existsSync(coreSpecPath)) {
      const now = new Date().toISOString();
      const initialCoreSpec: SpecSection = {
        id: 'core_spec',
        title: 'Core Architecture Spec',
        content: `# Core Architecture Specification\n\nThis is the base architecture specification for ${projectName}.\n\n## Technology Stack\n- **Frontend**: React, Vite, Vanilla CSS\n- **Backend**: Node.js Express, TypeScript\n- **Database**: SQLite\n\n## Project Context\n${projectDesc}`,
        status: 'active',
        createdAt: now,
        updatedAt: now
      };
      this.writeSpecSection(initialCoreSpec);
    }

    return this.readConfig();
  }

  /**
   * Reads lao.config.json
   */
  public readConfig(): ProjectConfig {
    if (!fs.existsSync(this.configFilePath)) {
      return this.initStorage();
    }
    const raw = fs.readFileSync(this.configFilePath, 'utf8');
    return JSON.parse(raw);
  }

  /**
   * Writes config to lao.config.json
   */
  public writeConfig(config: ProjectConfig): void {
    fs.writeFileSync(this.configFilePath, JSON.stringify(config, null, 2), 'utf8');
  }

  /**
   * Parse Frontmatter from markdown string
   */
  private parseFrontmatter(content: string): { metadata: Record<string, string>; body: string } {
    const result = { metadata: {} as Record<string, string>, body: content };
    if (content.startsWith('---')) {
      const endIdx = content.indexOf('---', 3);
      if (endIdx !== -1) {
        const fm = content.substring(3, endIdx);
        const lines = fm.split('\n');
        for (const line of lines) {
          const parts = line.split(':');
          if (parts.length >= 2) {
            const k = parts[0].trim();
            const v = parts.slice(1).join(':').trim();
            result.metadata[k] = v;
          }
        }
        result.body = content.substring(endIdx + 3).trim();
      }
    }
    return result;
  }

  /**
   * Stringify Frontmatter and markdown body
   */
  private stringifyFrontmatter(metadata: Record<string, string>, body: string): string {
    let fm = '---\n';
    for (const [k, v] of Object.entries(metadata)) {
      fm += `${k}: ${v}\n`;
    }
    fm += '---\n';
    return fm + body;
  }

  /**
   * Reads all spec files (core_spec + features)
   */
  public readSpecs(): SpecSection[] {
    const sections: SpecSection[] = [];

    // 1. Read core_spec.md
    const coreSpecPath = path.join(this.specsDirPath, 'core_spec.md');
    if (fs.existsSync(coreSpecPath)) {
      const raw = fs.readFileSync(coreSpecPath, 'utf8');
      const { metadata, body } = this.parseFrontmatter(raw);
      sections.push({
        id: metadata.id || 'core_spec',
        title: metadata.title || 'Core Architecture Spec',
        content: body,
        status: (metadata.status as any) || 'active',
        createdAt: metadata.createdAt || new Date().toISOString(),
        updatedAt: metadata.updatedAt || new Date().toISOString(),
      });
    }

    // 2. Read feature markdown files
    if (fs.existsSync(this.featuresDirPath)) {
      const files = fs.readdirSync(this.featuresDirPath);
      for (const file of files) {
        if (file.endsWith('.md')) {
          const filePath = path.join(this.featuresDirPath, file);
          const raw = fs.readFileSync(filePath, 'utf8');
          const { metadata, body } = this.parseFrontmatter(raw);
          sections.push({
            id: metadata.id || path.basename(file, '.md'),
            title: metadata.title || path.basename(file, '.md'),
            content: body,
            status: (metadata.status as any) || 'active',
            createdAt: metadata.createdAt || new Date().toISOString(),
            updatedAt: metadata.updatedAt || new Date().toISOString(),
          });
        }
      }
    }

    return sections;
  }

  /**
   * Writes a spec section to disk
   */
  public writeSpecSection(section: SpecSection): void {
    const metadata = {
      id: section.id,
      title: section.title,
      status: section.status,
      createdAt: section.createdAt,
      updatedAt: new Date().toISOString(),
    };
    const content = this.stringifyFrontmatter(metadata, section.content);
    
    if (section.id === 'core_spec') {
      fs.writeFileSync(path.join(this.specsDirPath, 'core_spec.md'), content, 'utf8');
    } else {
      fs.writeFileSync(path.join(this.featuresDirPath, `${section.id}.md`), content, 'utf8');
    }
  }

  /**
   * Delete or archive a feature specification file
   */
  public deleteSpecSection(id: string): void {
    if (id === 'core_spec') return; // Cannot delete core spec
    const filePath = path.join(this.featuresDirPath, `${id}.md`);
    if (fs.existsSync(filePath)) {
      // We perform a soft delete: mark it deprecated in frontmatter
      const raw = fs.readFileSync(filePath, 'utf8');
      const { metadata, body } = this.parseFrontmatter(raw);
      metadata.status = 'deprecated';
      metadata.updatedAt = new Date().toISOString();
      const updated = this.stringifyFrontmatter(metadata, body);
      fs.writeFileSync(filePath, updated, 'utf8');
    }
  }

  /**
   * Reads all decision cards
   */
  public readDecisions(): DecisionCard[] {
    const cards: DecisionCard[] = [];
    if (fs.existsSync(this.decisionsDirPath)) {
      const files = fs.readdirSync(this.decisionsDirPath);
      for (const file of files) {
        if (file.endsWith('.json')) {
          const raw = fs.readFileSync(path.join(this.decisionsDirPath, file), 'utf8');
          cards.push(JSON.parse(raw));
        }
      }
    }
    return cards;
  }

  /**
   * Writes a decision card
   */
  public writeDecision(card: DecisionCard): void {
    const filePath = path.join(this.decisionsDirPath, `${card.id}.json`);
    fs.writeFileSync(filePath, JSON.stringify(card, null, 2), 'utf8');
  }

  /**
   * Appends a log to criteria.md
   */
  public appendCriterion(decisionTitle: string, reason: string): void {
    const entry = `## [Decision] ${decisionTitle}\n- **Date**: ${new Date().toISOString()}\n- **Reasoning**: ${reason}\n\n`;
    fs.appendFileSync(this.criteriaFilePath, entry, 'utf8');
  }

  /**
   * Reads criteria.md
   */
  public readCriteria(): string {
    if (!fs.existsSync(this.criteriaFilePath)) {
      return '';
    }
    return fs.readFileSync(this.criteriaFilePath, 'utf8');
  }

  /**
   * Reads node messages
   */
  public readMessages(): NodeMessage[] {
    if (!fs.existsSync(this.messagesFilePath)) {
      return [];
    }
    const raw = fs.readFileSync(this.messagesFilePath, 'utf8');
    return JSON.parse(raw);
  }

  /**
   * Writes node messages
   */
  public writeMessages(messages: NodeMessage[]): void {
    fs.writeFileSync(this.messagesFilePath, JSON.stringify(messages, null, 2), 'utf8');
  }

  /**
   * Writes the final compiled specification file (spec_compiled.md)
   */
  public writeCompiledSpec(markdownContent: string): string {
    fs.writeFileSync(this.compiledSpecFilePath, markdownContent, 'utf8');
    return this.compiledSpecFilePath;
  }

  /**
   * Reads task.md raw content
   */
  public readTasksRaw(): string {
    if (!fs.existsSync(this.taskFilePath)) {
      return '';
    }
    return fs.readFileSync(this.taskFilePath, 'utf8');
  }

  /**
   * Writes task.md raw content
   */
  public writeTasksRaw(markdown: string): void {
    fs.writeFileSync(this.taskFilePath, markdown, 'utf8');
  }

  /**
   * Reads task.md and parses tasks list
   */
  public readTasksParsed(): { index: number; text: string; status: 'todo' | 'in_progress' | 'done' }[] {
    const raw = this.readTasksRaw();
    if (!raw) return [];

    const lines = raw.split('\n');
    const tasks: { index: number; text: string; status: 'todo' | 'in_progress' | 'done' }[] = [];

    lines.forEach((line, index) => {
      const trimmed = line.trim();
      if (trimmed.startsWith('- [ ]')) {
        tasks.push({
          index,
          text: trimmed.substring(5).trim(),
          status: 'todo'
        });
      } else if (trimmed.startsWith('- [/]')) {
        tasks.push({
          index,
          text: trimmed.substring(5).trim(),
          status: 'in_progress'
        });
      } else if (trimmed.startsWith('- [x]') || trimmed.startsWith('- [X]')) {
        tasks.push({
          index,
          text: trimmed.substring(5).trim(),
          status: 'done'
        });
      }
    });

    return tasks;
  }

  /**
   * Updates status of a task by changing the markdown line checkbox
   */
  public updateTaskStatus(index: number, status: 'todo' | 'in_progress' | 'done'): void {
    const raw = this.readTasksRaw();
    if (!raw) return;

    const lines = raw.split('\n');
    if (index < 0 || index >= lines.length) return;

    const line = lines[index];
    const trimmed = line.trim();
    let prefix = '- [ ]';
    if (status === 'in_progress') prefix = '- [/]';
    else if (status === 'done') prefix = '- [x]';

    // Preserve leading whitespace
    const leadingWhitespace = line.substring(0, line.indexOf('-'));
    
    // Extract actual content of task
    let content = '';
    if (trimmed.startsWith('- [ ]') || trimmed.startsWith('- [/]') || trimmed.startsWith('- [x]') || trimmed.startsWith('- [X]')) {
      content = trimmed.substring(5).trim();
    } else {
      return; // Not a valid task checkbox line
    }

    lines[index] = `${leadingWhitespace}${prefix} ${content}`;
    this.writeTasksRaw(lines.join('\n'));
  }
}
