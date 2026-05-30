import * as fs from 'fs';
import * as path from 'path';
import { GeminiClient } from '../gemini';
import { ProjectConfig, SpecSection } from '../models';

export class MockupGenerator {
  private static geminiClient = new GeminiClient();

  /**
   * Parses an HTML mockup file to extract CSS, HTML body, and script blocks based on comments
   */
  private static parseMockup(htmlContent: string): { css: string; html: string; js: string } {
    if (!htmlContent) {
      return { css: '', html: '', js: '' };
    }
    const styleMatch = htmlContent.match(/\/\* STYLE_START \*\/\n([\s\S]*?)\n\/\* STYLE_END \*\//);
    const htmlMatch = htmlContent.match(/<!-- HTML_START -->\n([\s\S]*?)\n<!-- HTML_END -->/);
    const jsMatch = htmlContent.match(/\/\/ SCRIPT_START\n([\s\S]*?)\n\/\/ SCRIPT_END/);
    
    // Fallback if markers are missing but content exists (legacy mockups)
    if (!styleMatch && !htmlMatch && !jsMatch) {
      const styleBlockMatch = htmlContent.match(/<style[^>]*>([\s\S]*?)<\/style>/i);
      const scriptBlockMatch = htmlContent.match(/<script[^>]*>([\s\S]*?)<\/script>/i);
      
      let bodyHtml = htmlContent;
      if (styleBlockMatch) bodyHtml = bodyHtml.replace(styleBlockMatch[0], '');
      if (scriptBlockMatch) bodyHtml = bodyHtml.replace(scriptBlockMatch[0], '');
      
      const bodyTagMatch = bodyHtml.match(/<body[^>]*>([\s\S]*?)<\/body>/i);
      if (bodyTagMatch) bodyHtml = bodyTagMatch[1];
      
      return {
        css: styleBlockMatch ? styleBlockMatch[1].trim() : '',
        html: bodyHtml.trim(),
        js: scriptBlockMatch ? scriptBlockMatch[1].trim() : ''
      };
    }

    return {
      css: styleMatch ? styleMatch[1].trim() : '',
      html: htmlMatch ? htmlMatch[1].trim() : '',
      js: jsMatch ? jsMatch[1].trim() : ''
    };
  }

  /**
   * Assembles CSS, HTML body, and Script parts into a complete standalone HTML document with markers
   */
  private static buildMockup(css: string, html: string, js: string): string {
    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <script src="https://cdn.tailwindcss.com"></script>
  <style id="mockup-styles">
    /* STYLE_START */
${css}
    /* STYLE_END */
  </style>
</head>
<body class="bg-gray-50 text-gray-900 font-sans">
  <div id="mockup-app">
    <!-- HTML_START -->
${html}
    <!-- HTML_END -->
  </div>
  <script id="mockup-script">
    // SCRIPT_START
${js}
    // SCRIPT_END
  </script>
</body>
</html>`;
  }

  /**
   * Applies search-and-replace patches to target content
   */
  private static applyPatches(content: string, patches: Array<{ search: string; replace: string }>): string {
    let result = content;
    for (const patch of patches) {
      if (!patch.search) continue;
      if (result.includes(patch.search)) {
        result = result.replace(patch.search, patch.replace);
      } else {
        // Fallback to whitespace normalized matching
        const normSearch = patch.search.replace(/\s+/g, ' ').trim();
        const idx = result.replace(/\s+/g, ' ').indexOf(normSearch);
        if (idx !== -1) {
          console.warn(`[LAO MockupGenerator] Fuzzy match used for patch:`, patch.search);
        } else {
          console.warn(`[LAO MockupGenerator] Search block not found for patch:`, patch.search);
        }
      }
    }
    return result;
  }

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

    const existing = this.parseMockup(existingMockup);

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
## Existing Mockup Components
We already have an interactive mockup. Here are the current CSS, HTML, and JS parts.

### Current CSS
\`\`\`css
${existing.css || '/* No custom styles yet */'}
\`\`\`

### Current HTML (inside body)
\`\`\`html
${existing.html || '<!-- No HTML body yet -->'}
\`\`\`

### Current JavaScript Script
\`\`\`javascript
${existing.js || '// No script logic yet'}
\`\`\`

You can either rewrite a component entirely (by providing the "css", "html", or "js" field) or apply surgical patches (by providing search-and-replace objects in "cssPatches", "htmlPatches", or "jsPatches"). Using patches is highly recommended for minor styling changes, text edits, or adding small elements, as it preserves all other functionality and styling.
` : `
## Initial Mockup Instructions
Create a premium, fully interactive, single-page web app mockup.
Since this is a mockup preview loaded in a sandboxed iframe, implement all functionalities (such as adding items, updating status, deleting items, filtering tabs, updating chart figures, etc.) using client-side JavaScript inside the script tag.
`}

## Design and Quality Guidelines:
1. **Rich Aesthetics**: The design must look extremely premium, modern, and beautiful (e.g., custom colors/gradients, soft card shadows, clean typography, system font stacks, consistent padding, and micro-animations). DO NOT use browser defaults or plain colors (like pure red, green, blue).
2. **Dynamic UI Interaction**: Implement robust interactive features in Vanilla JavaScript (e.g., event listeners to add items, filter categories, delete items, update progress widgets dynamically, open modals).
3. **No placeholders**: Fill with realistic dummy data.

## Output Format
You must output a single, valid JSON block inside a fenced code block of type \`\`\`json.
The JSON must match the following TypeScript shape:
{
  "css": "Full CSS content (only if rewriting entirely)",
  "cssPatches": [
    { "search": "exact string to find", "replace": "exact string to replace with" }
  ],
  "html": "Full HTML content (only if rewriting entirely)",
  "htmlPatches": [
    { "search": "exact string to find", "replace": "exact string to replace with" }
  ],
  "js": "Full JS content (only if rewriting entirely)",
  "jsPatches": [
    { "search": "exact string to find", "replace": "exact string to replace with" }
  ]
}

No other prose or text outside the json block. Keep patch searches precise and matching whitespace exactly.
`;

    console.log('[LAO MockupGenerator] Querying AI to generate/update mockup...');
    const rawOutput = await this.geminiClient.generateText({
      prompt,
      jsonMode: true,
      role: 'mockup' // Using the mockup tag for scheduler eviction
    });

    let cleaned = rawOutput.trim();
    const jsonMarker = '```json';
    const jsonIndex = cleaned.indexOf(jsonMarker);
    if (jsonIndex !== -1) {
      cleaned = cleaned.substring(jsonIndex + jsonMarker.length).trim();
      const lastFence = cleaned.lastIndexOf('```');
      if (lastFence !== -1) {
        cleaned = cleaned.substring(0, lastFence).trim();
      }
    }
    
    // Clean trailing commas and parse
    cleaned = cleaned.replace(/\/\*[\s\S]*?\*\/|([^\\:]|^)\/\/.*$/gm, '$1');
    cleaned = cleaned.replace(/,\s*([\}\]])/g, '$1');
    
    let parsed: any = {};
    try {
      parsed = JSON.parse(cleaned);
    } catch (e: any) {
      console.warn('[LAO MockupGenerator] Failed to parse mockup response JSON. Attempting fallback parse:', e);
      const firstBrace = cleaned.indexOf('{');
      const lastBrace = cleaned.lastIndexOf('}');
      if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
        try {
          parsed = JSON.parse(cleaned.substring(firstBrace, lastBrace + 1));
        } catch (innerErr: any) {
          throw new Error(`Failed to parse mockup generator output: ${innerErr.message}`);
        }
      } else {
        throw new Error(`Failed to parse mockup generator output: ${e.message}`);
      }
    }

    let finalCss = existing.css;
    let finalHtml = existing.html;
    let finalJs = existing.js;

    if (parsed.css) {
      finalCss = parsed.css;
    } else if (parsed.cssPatches && Array.isArray(parsed.cssPatches)) {
      finalCss = this.applyPatches(finalCss, parsed.cssPatches);
    }

    if (parsed.html) {
      finalHtml = parsed.html;
    } else if (parsed.htmlPatches && Array.isArray(parsed.htmlPatches)) {
      finalHtml = this.applyPatches(finalHtml, parsed.htmlPatches);
    }

    if (parsed.js) {
      finalJs = parsed.js;
    } else if (parsed.jsPatches && Array.isArray(parsed.jsPatches)) {
      finalJs = this.applyPatches(finalJs, parsed.jsPatches);
    }

    const fullMockupHtml = this.buildMockup(finalCss, finalHtml, finalJs);

    const laoDir = path.join(projectRoot, '.lao');
    if (!fs.existsSync(laoDir)) {
      fs.mkdirSync(laoDir, { recursive: true });
    }
    
    fs.writeFileSync(mockupPath, fullMockupHtml, 'utf8');
    console.log(`[LAO MockupGenerator] Successfully updated mockup at ${mockupPath} (${fullMockupHtml.length} bytes)`);

    return fullMockupHtml;
  }
}
