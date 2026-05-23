import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { execFile } from 'child_process';
import { promisify } from 'util';
import { randomUUID } from 'crypto';
import * as dotenv from 'dotenv';

// Load environmental variables
dotenv.config();

const execFilePromise = promisify(execFile);

/**
 * Returns the appropriate JSON schema for a prompt if jsonMode is enabled.
 */
function getJsonSchemaForPrompt(prompt: string): any {
  const lowerPrompt = prompt.toLowerCase();
  if (lowerPrompt.includes('director') || lowerPrompt.includes('route')) {
    return {
      type: "object",
      properties: {
        route: {
          type: "string",
          enum: ["specifier", "researcher", "optionizer", "gapDetector"]
        },
        reasoning: {
          type: "string"
        }
      },
      required: ["route", "reasoning"]
    };
  }
  if (lowerPrompt.includes('merge') || lowerPrompt.includes('synthesis') || lowerPrompt.includes('synthesize')) {
    return {
      type: "object",
      properties: {
        title: {
          type: "string"
        },
        body: {
          type: "string"
        },
        reasoning: {
          type: "string"
        }
      },
      required: ["title", "body", "reasoning"]
    };
  }
  // Generic fallback schema
  return {
    type: "object"
  };
}

function getStatusFromCLIError(exitCode: number, stderr: string, stdout: string): string {
  const normalized = (stderr + '\n' + stdout).toLowerCase();
  if (normalized.includes('command not found') || normalized.includes('no such file or directory') || normalized.includes('not found')) {
    return 'cli_not_found';
  }
  if (normalized.includes('rate limit') || normalized.includes('too many requests') || normalized.includes('resource_exhausted')) {
    return 'rate_limited';
  }
  if (
    normalized.includes('authentication failed') ||
    normalized.includes('not logged in') ||
    normalized.includes('login required') ||
    normalized.includes('unauthorized') ||
    normalized.includes('forbidden') ||
    normalized.includes('invalid api key') ||
    normalized.includes('check your api key')
  ) {
    return 'auth_failed';
  }
  if (normalized.includes('permission denied') || normalized.includes('operation not permitted') || normalized.includes('read-only')) {
    return 'permission_denied';
  }
  return `cli_exit_${exitCode}`;
}

export class GeminiClient {
  private defaultProvider = (process.env.LAO_PROVIDER || 'gemini').toLowerCase();
  private defaultModel = process.env.LAO_MODEL || '';

  constructor() {
    console.log(`[LAO Core] Initialized with local CLI provider: "${this.defaultProvider}"`);
  }

  /**
   * Calls the local CLI (gemini, claude, codex) with the given prompt.
   * Emulates the SwiftUI ProviderBackedCLIAgentRunner.
   */
  public async generateText(params: {
    prompt: string;
    systemInstruction?: string;
    jsonMode?: boolean;
    model?: string;
    role?: 'director' | 'specifier' | 'researcher' | 'optionizer' | 'gapDetector';
  }): Promise<string> {
    let provider = this.defaultProvider;
    let model = params.model || this.defaultModel;
    const jsonMode = !!params.jsonMode;

    // Load settings dynamically from settings.json if it exists
    const settingsPath = path.join(process.cwd(), '.lao', 'settings.json');
    if (fs.existsSync(settingsPath)) {
      try {
        const raw = fs.readFileSync(settingsPath, 'utf8');
        const settings = JSON.parse(raw);
        
        let targetProvider = settings.provider;
        let targetModel = settings.model;
        
        if (params.role && settings.agents && settings.agents[params.role]) {
          const agentConfig = settings.agents[params.role];
          targetProvider = agentConfig.provider || targetProvider;
          targetModel = agentConfig.model !== undefined ? agentConfig.model : targetModel;
        }

        if (targetProvider) {
          provider = targetProvider.toLowerCase();
        }
        if (targetModel !== undefined) {
          model = params.model || targetModel;
        }
      } catch (e) {
        console.warn('[LAO Core] Failed to parse settings.json, falling back to process.env defaults', e);
      }
    }

    // 1. Create temporary file for prompt
    const promptFile = path.join(os.tmpdir(), `lao_prompt_${randomUUID()}.txt`);
    fs.writeFileSync(promptFile, params.prompt, 'utf8');

    // 2. Create temporary file for JSON schema if jsonMode is active
    let schemaFile: string | null = null;
    if (jsonMode && (provider === 'claude' || provider === 'codex')) {
      schemaFile = path.join(os.tmpdir(), `lao_schema_${randomUUID()}.json`);
      const schema = getJsonSchemaForPrompt(params.prompt);
      fs.writeFileSync(schemaFile, JSON.stringify(schema, null, 2), 'utf8');
    }

    try {
      // 3. Build command template
      let command = '';
      if (provider === 'claude') {
        let baseCmd = process.env.LAO_PROVIDER_CLAUDE_CLI || 'claude';
        if (!baseCmd.includes('--dangerously-skip-permissions')) {
          baseCmd = baseCmd.replace('claude', 'claude --dangerously-skip-permissions --allowedTools Bash');
        }
        if (schemaFile) {
          if (!baseCmd.includes('--json-schema')) {
            baseCmd += ` --json-schema "$(cat '${schemaFile}')"`;
          }
          if (!baseCmd.includes('--output-format')) {
            baseCmd += ' --output-format json';
          }
        }
        if (!baseCmd.includes('-p ') && !baseCmd.includes('--prompt ') && !baseCmd.includes('$LAO_PROMPT_FILE')) {
          baseCmd += ' -p "$(cat "$LAO_PROMPT_FILE")"';
        } else {
          baseCmd = baseCmd.replace(/"?\$LAO_PROMPT"?/g, '"$(cat "$LAO_PROMPT_FILE")"');
        }
        command = baseCmd;

      } else if (provider === 'codex') {
        let baseCmd = process.env.LAO_PROVIDER_CODEX_CLI || 'codex';
        if (!baseCmd.includes('codex exec')) {
          baseCmd = baseCmd.replace('codex', 'codex exec');
        }
        if (!baseCmd.includes('model_reasoning_effort') && !baseCmd.includes('reasoning.effort')) {
          baseCmd = baseCmd.replace('codex exec', "codex exec -c model_reasoning_effort='high'");
        }
        if (!baseCmd.includes('--skip-git-repo-check')) {
          baseCmd = baseCmd.replace('codex exec', 'codex exec --skip-git-repo-check');
        }
        if (!baseCmd.includes('-s ') && !baseCmd.includes('--sandbox')) {
          baseCmd = baseCmd.replace('codex exec', 'codex exec -s workspace-write');
        }
        if (schemaFile) {
          if (!baseCmd.includes('--output-schema')) {
            baseCmd = baseCmd.replace('codex exec', `codex exec --output-schema '${schemaFile}'`);
          }
        }
        if (baseCmd.includes('"$LAO_PROMPT"') || baseCmd.includes('$LAO_PROMPT')) {
          baseCmd = baseCmd.replace(/"?\$LAO_PROMPT"?/g, '"$(cat "$LAO_PROMPT_FILE")"');
        } else if (!baseCmd.includes('$LAO_PROMPT_FILE')) {
          baseCmd += ' "$(cat "$LAO_PROMPT_FILE")"';
        }
        command = baseCmd;

      } else {
        // default: gemini
        let baseCmd = process.env.LAO_PROVIDER_GEMINI_CLI || 'gemini';
        if (!baseCmd.includes('--yolo') && !baseCmd.includes('--approval-mode') && baseCmd.includes('gemini')) {
          baseCmd = baseCmd.replace('gemini', 'gemini --yolo --sandbox false');
        }
        const hasPromptArg = baseCmd.includes('--prompt') || baseCmd.includes(' -p ') || baseCmd.includes('$LAO_PROMPT_FILE');
        if (!hasPromptArg && baseCmd.includes('gemini')) {
          baseCmd = 'cat "$LAO_PROMPT_FILE" | ' + baseCmd;
        } else {
          baseCmd = baseCmd.replace(/"?\$LAO_PROMPT"?/g, '"$(cat "$LAO_PROMPT_FILE")"');
        }
        command = baseCmd;
      }

      // 4. Setup environment variables
      const env: Record<string, string> = {
        ...process.env,
        LAO_PROVIDER: provider,
        LAO_MODEL: model,
        LAO_PROMPT_FILE: promptFile,
      } as any;

      // Ensure opt/homebrew/bin etc. are in the PATH to find local CLIs
      const currentPath = process.env.PATH || '';
      const paths = currentPath.split(':');
      const defaults = [
        '/opt/homebrew/bin',
        '/opt/homebrew/sbin',
        '/usr/local/bin',
        '/usr/local/sbin',
        '/usr/bin',
        '/bin',
        '/usr/sbin',
        '/sbin'
      ];
      for (const p of defaults) {
        if (!paths.includes(p)) {
          paths.push(p);
        }
      }
      env.PATH = paths.join(':');

      console.log(`[LAO Core] Executing local CLI command: ${command}`);

      // 5. Execute command using zsh interactive/login shell
      const { stdout, stderr } = await execFilePromise('/bin/zsh', ['-lc', command], {
        cwd: process.cwd(),
        env,
      });

      let output = stdout.trim();

      // 6. Handle schema response extraction for Claude CLI
      if (jsonMode && provider === 'claude') {
        try {
          const parsed = JSON.parse(output);
          if (parsed.structured_output) {
            if (typeof parsed.structured_output === 'string') {
              output = parsed.structured_output;
            } else {
              output = JSON.stringify(parsed.structured_output);
            }
          } else if (parsed.result) {
            output = parsed.result;
          }
        } catch (e) {
          // stdout was not valid JSON or structured output format wasn't JSON. Return output as is.
        }
      }

      return output;

    } catch (error: any) {
      const exitCode = error.code || -1;
      const stderr = error.stderr || '';
      const stdout = error.stdout || '';
      const status = getStatusFromCLIError(exitCode, stderr, stdout);
      const diagnosticMsg = stderr.trim() || stdout.trim() || error.message;
      console.error(`[LAO Core] CLI Execution failed. Status: ${status}. Detail: ${diagnosticMsg}`);
      throw new Error(`CLI Request Failed (${status}): ${diagnosticMsg}`);
    } finally {
      // 7. Cleanup temp files
      try {
        if (fs.existsSync(promptFile)) {
          fs.unlinkSync(promptFile);
        }
      } catch (err) {
        console.warn(`[LAO Core] Failed to clean up prompt temp file: ${promptFile}`, err);
      }
      if (schemaFile) {
        try {
          if (fs.existsSync(schemaFile)) {
            fs.unlinkSync(schemaFile);
          }
        } catch (err) {
          console.warn(`[LAO Core] Failed to clean up schema temp file: ${schemaFile}`, err);
        }
      }
    }
  }
}
