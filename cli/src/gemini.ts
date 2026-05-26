import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { execFile, spawn } from 'child_process';
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

export const activeProcesses = new Map<string, any>();

export function getShellInfo(): { shell: string; args: string[] } {
  const isWindows = process.platform === 'win32';
  if (process.platform === 'darwin') {
    return { shell: '/bin/zsh', args: ['-lc'] };
  }
  const shell = isWindows ? (process.env.ComSpec || 'cmd.exe') : '/bin/sh';
  const args = isWindows ? ['/d', '/s', '/c'] : ['-c'];
  return { shell, args };
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
    nodeId?: string;
    onChunk?: (chunk: string) => void;
  }): Promise<string> {
    let provider = this.defaultProvider;
    let model = params.model || this.defaultModel;
    const jsonMode = !!params.jsonMode;

    // Load settings dynamically from lao.config.json if it exists
    const configPath = path.join(process.cwd(), '.lao', 'lao.config.json');
    if (fs.existsSync(configPath)) {
      try {
        const raw = fs.readFileSync(configPath, 'utf8');
        const config = JSON.parse(raw);
        const settings = config.settings || {};
        
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
        console.warn('[LAO Core] Failed to parse lao.config.json, falling back to process.env defaults', e);
      }
    }

    let promptFile: string | null = null;
    let schemaFile: string | null = null;

    try {
      // 1. Create temporary file for prompt
      promptFile = path.join(os.tmpdir(), `lao_prompt_${randomUUID()}.txt`);
      fs.writeFileSync(promptFile, params.prompt, 'utf8');

      // 2. Create temporary file for JSON schema if jsonMode is active
      if (jsonMode && (provider === 'claude' || provider === 'codex')) {
        schemaFile = path.join(os.tmpdir(), `lao_schema_${randomUUID()}.json`);
        const schema = getJsonSchemaForPrompt(params.prompt);
        fs.writeFileSync(schemaFile, JSON.stringify(schema, null, 2), 'utf8');
      }

      // 3. Build command template
      let command = '';
      if (provider === 'claude') {
        let baseCmd = process.env.LAO_PROVIDER_CLAUDE_CLI || 'claude';
        if (!baseCmd.includes('--dangerously-skip-permissions')) {
          baseCmd = baseCmd.replace(/\bclaude\b/, 'claude --dangerously-skip-permissions --allowedTools Bash');
        }
        if (model && !baseCmd.includes('--model')) {
          baseCmd += ` --model "${model}"`;
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
          baseCmd = baseCmd.replace(/\bcodex\b/, 'codex exec');
        }
        if (model && !baseCmd.includes('--model')) {
          baseCmd += ` --model "${model}"`;
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

      } else if (provider === 'agy') {
        let baseCmd = process.env.LAO_PROVIDER_AGY_CLI || 'agy';
        if (!baseCmd.includes('--dangerously-skip-permissions')) {
          baseCmd = baseCmd.replace(/\bagy\b/, 'agy --dangerously-skip-permissions');
        }
        if (model && !baseCmd.includes('--model')) {
          baseCmd += ` --model "${model}"`;
        }
        if (jsonMode && !baseCmd.includes('--output-format')) {
          baseCmd += ' --output-format json';
        }
        if (baseCmd.includes('"$LAO_PROMPT"') || baseCmd.includes('$LAO_PROMPT')) {
          baseCmd = baseCmd.replace(/"?\$LAO_PROMPT"?/g, '"$(cat "$LAO_PROMPT_FILE")"');
        } else if (!baseCmd.includes('$LAO_PROMPT_FILE')) {
          baseCmd += ' -p "$(cat "$LAO_PROMPT_FILE")"';
        }
        command = baseCmd;

      } else {
        // default: gemini
        let baseCmd = process.env.LAO_PROVIDER_GEMINI_CLI || 'gemini';
        if (!baseCmd.includes('--yolo') && !baseCmd.includes('--approval-mode') && baseCmd.includes('gemini')) {
          baseCmd = baseCmd.replace(/\bgemini\b/, 'gemini --yolo --sandbox false');
        }
        if (model && !baseCmd.includes('--model')) {
          baseCmd += ` --model "${model}"`;
        }
        if (jsonMode && !baseCmd.includes('--output-format')) {
          baseCmd += ' --output-format json';
        }
        const hasPromptArg = baseCmd.includes('--prompt') || baseCmd.includes(' -p ') || baseCmd.includes('$LAO_PROMPT_FILE');
        if (!hasPromptArg && baseCmd.includes('gemini')) {
          baseCmd += ' -p "$(cat "$LAO_PROMPT_FILE")"';
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

      // Get cross-platform shell
      const { shell, args: shellArgs } = getShellInfo();

      // 5. Execute command using dynamic shell via spawn to support stdout streaming
      const child = spawn(shell, [...shellArgs, command], {
        cwd: process.cwd(),
        env,
      });

      if (params.nodeId) {
        activeProcesses.set(params.nodeId, child);
      }

      let stdout = '';
      let stderr = '';

      if (child.stdout) {
        child.stdout.on('data', (data) => {
          const chunk = data.toString();
          stdout += chunk;
          if (params.onChunk) {
            params.onChunk(chunk);
          }
        });
      }

      if (child.stderr) {
        child.stderr.on('data', (data) => {
          stderr += data.toString();
        });
      }

      const exitCode = await new Promise<number>((resolve) => {
        child.on('close', (code) => {
          resolve(code ?? 0);
        });
        child.on('error', (err) => {
          console.error('[LAO Core] Spawn error:', err);
          resolve(-1);
        });
      });

      if (exitCode !== 0) {
        const error = new Error(`Command failed with exit code ${exitCode}`) as any;
        error.code = exitCode;
        error.stderr = stderr;
        error.stdout = stdout;
        throw error;
      }

      let output = stdout.trim();

      // 6. Handle schema response extraction for Claude/Gemini CLIs
      if (jsonMode) {
        if (provider === 'claude') {
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
        } else if (provider === 'gemini' || provider === 'agy') {
          try {
            const firstBrace = output.indexOf('{');
            if (firstBrace !== -1) {
              const jsonBody = output.substring(firstBrace);
              const parsed = JSON.parse(jsonBody);
              if (parsed.response) {
                if (typeof parsed.response === 'string') {
                  try {
                    const innerJson = JSON.parse(parsed.response);
                    output = JSON.stringify(innerJson);
                  } catch (e) {
                    output = parsed.response;
                  }
                } else {
                  output = JSON.stringify(parsed.response);
                }
              }
            }
          } catch (e) {
            console.warn('[LAO Core] Failed to parse gemini CLI JSON response:', e);
          }
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
      if (params.nodeId) {
        activeProcesses.delete(params.nodeId);
      }
      // 7. Cleanup temp files
      try {
        if (promptFile && fs.existsSync(promptFile)) {
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
