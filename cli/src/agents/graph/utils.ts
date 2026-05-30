/**
 * Helper to clean markdown JSON fences and repair invalid JSON structures before parsing
 */
export function cleanJsonResponse(raw: string): string {
  let cleaned = raw.trim();

  // 1. Regex to extract code block content (preferring ```json)
  const jsonBlockRegex = /```json\s*([\s\S]*?)\s*```/;
  const genericBlockRegex = /```\s*([\s\S]*?)\s*```/;
  
  const blockMatch = cleaned.match(jsonBlockRegex) || cleaned.match(genericBlockRegex);
  if (blockMatch) {
    cleaned = blockMatch[1].trim();
  }

  // 2. Extract JSON structure by tracking balanced braces/brackets (filters out conversational text)
  const startIdx = cleaned.search(/[\{\[]/);
  if (startIdx !== -1) {
    const isObject = cleaned[startIdx] === '{';
    const openChar = cleaned[startIdx];
    const closeChar = isObject ? '}' : ']';
    
    let balance = 0;
    let endIdx = -1;
    let inString = false;
    let escape = false;
    
    for (let i = startIdx; i < cleaned.length; i++) {
      const char = cleaned[i];
      if (char === '\\' && inString) {
        escape = !escape;
        continue;
      }
      if (char === '"' && !escape) {
        inString = !inString;
      }
      escape = false;
      
      if (!inString) {
        if (char === openChar) {
          balance++;
        } else if (char === closeChar) {
          balance--;
          if (balance === 0) {
            endIdx = i;
            break;
          }
        }
      }
    }
    
    if (endIdx !== -1) {
      cleaned = cleaned.substring(startIdx, endIdx + 1);
    } else {
      const lastCloseIdx = cleaned.lastIndexOf(closeChar);
      if (lastCloseIdx > startIdx) {
        cleaned = cleaned.substring(startIdx, lastCloseIdx + 1);
      }
    }
  }

  // 3. Robust recovery transformations
  // A. Strip single-line & multi-line comments that LLMs write in JSON
  cleaned = cleaned.replace(/\/\*[\s\S]*?\*\/|([^\\:]|^)\/\/.*$/gm, '$1');

  // B. Fix trailing commas before closing braces/brackets
  cleaned = cleaned.replace(/,\s*([\}\]])/g, '$1');

  // C. Fix unescaped newlines in JSON strings
  let repaired = '';
  let inString = false;
  let escape = false;
  for (let i = 0; i < cleaned.length; i++) {
    const char = cleaned[i];
    if (char === '"' && !escape) {
      inString = !inString;
      repaired += char;
    } else if (char === '\\' && inString && !escape) {
      escape = true;
      repaired += char;
    } else if (inString && (char === '\n' || char === '\r')) {
      repaired += '\\n';
      escape = false;
    } else {
      repaired += char;
      escape = false;
    }
  }
  cleaned = repaired;

  // D. Truncation repair: auto-close open brackets/braces
  let braceCount = 0;
  let bracketCount = 0;
  let inStr = false;
  let esc = false;
  for (let i = 0; i < cleaned.length; i++) {
    const char = cleaned[i];
    if (char === '\\' && inStr) {
      esc = !esc;
      continue;
    }
    if (char === '"' && !esc) {
      inStr = !inStr;
    }
    esc = false;
    if (!inStr) {
      if (char === '{') braceCount++;
      else if (char === '}') braceCount--;
      else if (char === '[') bracketCount++;
      else if (char === ']') bracketCount--;
    }
  }
  
  while (braceCount > 0) {
    cleaned += '}';
    braceCount--;
  }
  while (bracketCount > 0) {
    cleaned += ']';
    bracketCount--;
  }

  return cleaned;
}

/**
 * Helper to extract optional spec update blocks from prose responses
 */
export function extractSpecUpdate(response: string): { prose: string; specUpdate?: { sectionId: string; title?: string; content: string } } {
  const marker = '```specUpdate';
  const index = response.indexOf(marker);
  if (index === -1) {
    return { prose: response.trim() };
  }
  const prose = response.substring(0, index).trim();
  const rest = response.substring(index + marker.length);
  const closeIndex = rest.indexOf('```');
  if (closeIndex === -1) {
    return { prose };
  }
  const body = rest.substring(0, closeIndex).trim();

  // Match divider line consisting of two or more '=' characters on a single line
  const dividerRegex = /^\s*==+\s*$/m;
  const match = body.match(dividerRegex);
  if (!match || match.index === undefined) {
    console.warn('[LAO Core] Found ```specUpdate block but could not find divider line (===)');
    return { prose };
  }

  const headerPart = body.substring(0, match.index).trim();
  const contentPart = body.substring(match.index + match[0].length).trim();

  const lines = headerPart.split('\n');
  let sectionId = '';
  let title: string | undefined = undefined;

  for (const line of lines) {
    const colonIdx = line.indexOf(':');
    if (colonIdx !== -1) {
      const key = line.substring(0, colonIdx).trim().toLowerCase();
      let val = line.substring(colonIdx + 1).trim();
      // Strip surrounding quotes
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.substring(1, val.length - 1);
      }
      if (key === 'sectionid' || key === 'section_id') {
        sectionId = val;
      } else if (key === 'title') {
        title = val;
      }
    }
  }

  if (sectionId && contentPart) {
    return {
      prose,
      specUpdate: {
        sectionId,
        title,
        content: contentPart
      }
    };
  }

  return { prose };
}
