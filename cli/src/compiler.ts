import { ProjectConfig, SpecSection } from './models';

export class SpecCompiler {
  /**
   * Compiles the core and active feature spec sections into a single cohesive markdown document.
   */
  public static compile(config: ProjectConfig, sections: SpecSection[]): string {
    const markdownLines: string[] = [];

    // Header
    markdownLines.push(`# Specification: ${config.projectName}`);
    markdownLines.push(`*Generated at: ${new Date().toISOString()}*`);
    markdownLines.push('');
    markdownLines.push(`> **Project Context**: ${config.projectDesc}`);
    markdownLines.push(`> **Automation Level**: \`${config.automationLevel}\``);
    markdownLines.push(`> **Phase**: \`${config.phase.toUpperCase()}\``);
    markdownLines.push('');

    // Golden Rules Box
    markdownLines.push('> [!IMPORTANT]');
    markdownLines.push('> **Golden Rules (Tech Stack Constraints)**');
    markdownLines.push(`> - **Frontend**: ${config.goldenRules.frontend}`);
    markdownLines.push(`> - **Backend**: ${config.goldenRules.backend}`);
    markdownLines.push(`> - **Database**: ${config.goldenRules.database}`);
    markdownLines.push(`> - **Constraints**: ${config.goldenRules.additional}`);
    markdownLines.push('');
    markdownLines.push('---');
    markdownLines.push('');

    // Find and compile core spec
    const coreSpec = sections.find(s => s.id === 'core_spec');
    if (coreSpec) {
      markdownLines.push(coreSpec.content.trim());
      markdownLines.push('');
      markdownLines.push('---');
      markdownLines.push('');
    }

    // Compile active feature specs
    const activeFeatures = sections.filter(s => s.id !== 'core_spec' && s.status === 'active');
    if (activeFeatures.length > 0) {
      markdownLines.push('## Feature Specifications');
      markdownLines.push('');
      
      for (const feature of activeFeatures) {
        markdownLines.push(`### ${feature.title}`);
        markdownLines.push('');
        markdownLines.push(feature.content.trim());
        markdownLines.push('');
        markdownLines.push('---');
        markdownLines.push('');
      }
    } else {
      markdownLines.push('*(No active feature specifications defined yet)*');
      markdownLines.push('');
    }

    return markdownLines.join('\n');
  }
}
