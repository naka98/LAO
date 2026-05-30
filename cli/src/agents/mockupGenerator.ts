import * as fs from 'fs';
import * as path from 'path';
import { GeminiClient } from '../gemini';
import { ProjectConfig, SpecSection } from '../models';

export class MockupGenerator {
  private static geminiClient = new GeminiClient();

  /**
   * Reads specifications and existing mockup to generate/update .lao/mockup.html
   */
  public static async generateOrUpdate(
    projectRoot: string,
    config: ProjectConfig,
    sections: SpecSection[],
    userMessage: string
  ): Promise<string> {
    const mockupPath = path.join(projectRoot, '.lao', 'mockup.html');
    let existingMockup = '';
    
    if (fs.existsSync(mockupPath)) {
      try {
        existingMockup = fs.readFileSync(mockupPath, 'utf8');
      } catch (e) {
        console.warn('[LAO MockupGenerator] Failed to read existing mockup.html:', e);
      }
    }

    const specsBlock = sections
      .filter(s => s.status === 'active')
      .map(s => `### ${s.title}\n${s.content}`)
      .join('\n\n');

    const prompt = `
You are the **Mockup Designer** for the project "${config.projectName}".
Your task is to generate or update a standalone, interactive HTML mockup file (\`mockup.html\`) representing the frontend design and user flow based on the latest project specifications and design constraints.

## Tech Stack Constraints (Golden Rules)
- **Frontend**: ${config.goldenRules.frontend}
- **Backend**: ${config.goldenRules.backend}
- **Database**: ${config.goldenRules.database}
- **Additional Constraints**: ${config.goldenRules.additional}

## Current Specifications
${specsBlock}

## User Request / Feedback
"${userMessage}"

${existingMockup ? `
## Existing Mockup (\`mockup.html\`)
We already have an interactive mockup. You should preserve its core functionality, interactive logic, dummy data arrays, and current layout structure, but modify/update the design, styles, widgets, or features as requested by the specifications and the User Request above (e.g. changing styling theme, adding new input elements, updating layout). Keep it fully interactive inside a single file.
` : `
## Initial Mockup Instructions
Create a premium, fully interactive, single-page web app mockup.
Since this is a mockup preview loaded in a sandboxed iframe, implement all functionalities (such as adding items, updating status, deleting items, filtering tabs, updating chart figures, etc.) using client-side JavaScript inside the script tag.
`}

## Design and Quality Guidelines:
1. **Rich Aesthetics**: The design must look extremely premium, modern, and beautiful (e.g., custom colors/gradients, dark/light mode toggle if applicable, soft card shadows, clean typography, system font stacks, consistent padding, and micro-animations). DO NOT use browser defaults or plain colors (like pure red, green, blue).
2. **Dynamic UI Interaction**: Implement robust interactive features in Vanilla JavaScript (e.g., event listeners to add items, filter categories, delete items, update progress widgets dynamically, open modals).
3. **No placeholders**: Fill with realistic dummy data.
4. **Single File**: Output ONLY one single HTML file containing CSS in <style> and JS in <script> tags.

## Output Format
Respond ONLY with the complete HTML code. Do NOT wrap the HTML code in markdown code fences (\`\`\`html or \`\`\`), and do not include any other explanations, comments outside the HTML, or markdown formatting. Start directly with <!DOCTYPE html> and end with </html>.
`;

    console.log('[LAO MockupGenerator] Querying AI to generate/update mockup...');
    const rawOutput = await this.geminiClient.generateText({
      prompt,
      role: 'mockup' // Using the mockup tag for scheduler eviction
    });

    // Clean potential markdown fencing from the model response
    let cleaned = rawOutput.trim();
    if (cleaned.startsWith('```html')) {
      cleaned = cleaned.substring(7);
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }
    } else if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }
    }
    cleaned = cleaned.trim();

    // Write back to .lao/mockup.html
    const laoDir = path.join(projectRoot, '.lao');
    if (!fs.existsSync(laoDir)) {
      fs.mkdirSync(laoDir, { recursive: true });
    }
    
    fs.writeFileSync(mockupPath, cleaned, 'utf8');
    console.log(`[LAO MockupGenerator] Successfully updated mockup at ${mockupPath} (${cleaned.length} bytes)`);

    return cleaned;
  }
}
