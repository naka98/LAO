import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import { exec, spawn, ChildProcess } from 'child_process';
import { promisify } from 'util';
import { randomUUID } from 'crypto';
import * as dotenv from 'dotenv';
import { SpawnQueueManager } from './scheduler';

// Load environmental variables
dotenv.config();

const execPromise = promisify(exec);

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

/**
 * Zsh 로그인 셸(-l)을 제거하여 기동 성능을 극대화(10ms 수준)하고 세션 잠금을 원천 차단합니다.
 */
export function getShellInfo(): { shell: string; args: string[] } {
  const isWindows = process.platform === 'win32';
  if (process.platform === 'darwin') {
    // -lc (로그인 셸)에서 -c (단순 비로그인 실행)로 변경하여 startup 스크립트 연쇄 로딩 지연을 우회합니다.
    return { shell: '/bin/zsh', args: ['-c'] };
  }
  const shell = isWindows ? (process.env.ComSpec || 'cmd.exe') : '/bin/sh';
  const args = isWindows ? ['/d', '/s', '/c'] : ['-c'];
  return { shell, args };
}

/**
 * 여러 로컬 CLI(Claude, Gemini, Codex 등)의 제각각인 JSON 출력 포맷을 하나의 공통 스펙 스키마 구조로 통합 정규화합니다.
 */
function normalizeJsonResponse(rawOutput: string, provider: string): string {
  const trimmed = rawOutput.trim();
  if (!trimmed) return '{}';

  try {
    const parsed = JSON.parse(trimmed);

    // 1. Claude/Cursor의 출력 정상화
    if (provider === 'claude' || provider === 'cursor') {
      if (parsed.structured_output) {
        return typeof parsed.structured_output === 'string'
          ? parsed.structured_output
          : JSON.stringify(parsed.structured_output);
      }
      if (parsed.result) {
        return typeof parsed.result === 'string' ? parsed.result : JSON.stringify(parsed.result);
      }
    }

    // 2. Gemini/AGY의 출력 정상화 (이중 래핑 풀기)
    if (provider === 'gemini' || provider === 'agy') {
      if (parsed.response) {
        if (typeof parsed.response === 'string') {
          try {
            // 이중 래핑된 JSON String을 다시 파싱하여 일반 JSON으로 변환
            const innerJson = JSON.parse(parsed.response);
            return JSON.stringify(innerJson);
          } catch (e) {
            return parsed.response;
          }
        } else {
          return JSON.stringify(parsed.response);
        }
      }
    }

    return JSON.stringify(parsed);
  } catch (e) {
    // 만약 전체 파싱에 실패한다면, 텍스트 내에서 중괄호 { } 부분을 도려내어 파싱을 2차 시도
    try {
      const firstBrace = trimmed.indexOf('{');
      const lastBrace = trimmed.lastIndexOf('}');
      if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
        const jsonSubstring = trimmed.substring(firstBrace, lastBrace + 1);
        const parsedSub = JSON.parse(jsonSubstring);
        
        if ((provider === 'gemini' || provider === 'agy') && parsedSub.response) {
          return typeof parsedSub.response === 'object' 
            ? JSON.stringify(parsedSub.response)
            : String(parsedSub.response);
        }
        return JSON.stringify(parsedSub);
      }
    } catch (innerErr) {
      console.warn('[LAO GeminiClient] Normalization parsing fail:', innerErr);
    }
  }

  return trimmed;
}

export class GeminiClient {
  private defaultProvider = (process.env.LAO_PROVIDER || 'gemini').toLowerCase();
  private defaultModel = process.env.LAO_MODEL || '';

  constructor() {
    console.log(`[LAO Core] Initialized with local CLI provider: "${this.defaultProvider}"`);
  }

  /**
   * 로컬 CLI를 호출합니다. 지수 백오프 기반 재시도와 SpawnQueueManager가 연동되어 안전하게 작동합니다.
   */
  public async generateText(params: {
    prompt: string;
    systemInstruction?: string;
    jsonMode?: boolean;
    model?: string;
    role?: 'director' | 'specifier' | 'researcher' | 'optionizer' | 'gapDetector' | 'mockup';
    nodeId?: string;
    onChunk?: (chunk: string) => void;
  }): Promise<string> {
    let attempts = 0;
    const maxAttempts = 3;
    let delay = 2000; // 초기 백오프 딜레이 2초
    
    // Fallback CLI용 프로바이더 순서 정의
    const fallbackProviders = ['gemini', 'claude', 'codex'];
    let currentProviderIndex = -1;

    while (attempts < maxAttempts) {
      try {
        return await this.executeCli(params);
      } catch (error: any) {
        attempts++;
        const status = error.message;
        
        // Rate limit인 경우 또는 자원 락이 발생한 경우 백오프 대기 후 재시도
        if ((status.includes('rate_limited') || status.includes('SQLITE_BUSY')) && attempts < maxAttempts) {
          console.warn(`[LAO Core] Rate limited or DB locked. Backing off for ${delay}ms... (Attempt ${attempts}/${maxAttempts})`);
          await new Promise(resolve => setTimeout(resolve, delay));
          delay *= 2; // 지수 백오프 곱연산
        } else {
          // 바이너리 없음, 인증 오류, 혹은 일반 에러인 경우 다른 CLI로의 Fallback 스위칭 시도 (Gap 4 해결)
          console.warn(`[LAO Core] CLI generation failed due to: ${status}. Attempting Fallback Provider...`);
          
          let currentProvider = this.defaultProvider;
          const configPath = path.join(process.cwd(), '.lao', 'lao.config.json');
          if (fs.existsSync(configPath)) {
            try {
              const raw = fs.readFileSync(configPath, 'utf8');
              const config = JSON.parse(raw);
              if (config.settings && config.settings.provider) {
                currentProvider = config.settings.provider.toLowerCase();
              }
            } catch {}
          }
          
          const candidates = fallbackProviders.filter(p => p !== currentProvider);
          if (candidates.length > 0 && currentProviderIndex < candidates.length - 1) {
            currentProviderIndex++;
            const fallbackProvider = candidates[currentProviderIndex];
            console.log(`[LAO Core] Switching provider to Fallback CLI: "${fallbackProvider}"`);
            
            try {
              return await this.executeCli({ ...params, fallbackProvider });
            } catch (fallbackErr: any) {
              console.error(`[LAO Core] Fallback CLI "${fallbackProvider}" also failed:`, fallbackErr.message);
            }
          } else {
            throw error;
          }
        }
      }
    }
    throw new Error('CLI Request Failed after maximum backoff retries and fallback options.');
  }

  /**
   * 실제 자식 프로세스를 기동하고 큐에 넣어 순차 실행을 조율하는 저수준 래퍼입니다.
   */
  private async executeCli(params: {
    prompt: string;
    systemInstruction?: string;
    jsonMode?: boolean;
    model?: string;
    role?: 'director' | 'specifier' | 'researcher' | 'optionizer' | 'gapDetector' | 'mockup';
    nodeId?: string;
    onChunk?: (chunk: string) => void;
    fallbackProvider?: string;
  }): Promise<string> {
    let provider = params.fallbackProvider || this.defaultProvider;
    let model = params.model || this.defaultModel;
    const jsonMode = !!params.jsonMode;

    // Load settings dynamically from lao.config.json if it exists
    const configPath = path.join(process.cwd(), '.lao', 'lao.config.json');
    if (fs.existsSync(configPath) && !params.fallbackProvider) {
      try {
        const raw = fs.readFileSync(configPath, 'utf8');
        const config = JSON.parse(raw);
        const settings = config.settings || {};
        
        let targetProvider = settings.provider;
        let targetModel = settings.model;
        
        if (params.role && settings.agents && settings.agents[params.role as any]) {
          const agentConfig = settings.agents[params.role as any];
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
        console.warn('[LAO Core] Failed to parse lao.config.json', e);
      }
    }

    let promptFile: string | null = null;
    let schemaFile: string | null = null;

    // 큐 관리자 할당
    const queue = SpawnQueueManager.getInstance();
    // 우선순위 판정 (실시간 스트림 챗 등은 high, 나머지는 medium)
    const priority = params.role === 'director' || params.onChunk ? 'high' : 'medium';

    try {
      const finalPrompt = params.prompt;

      // 1. Create temporary file for prompt
      promptFile = path.join(os.tmpdir(), `lao_prompt_${randomUUID()}.txt`);
      fs.writeFileSync(promptFile, finalPrompt, 'utf8');

      // 2. Create temporary file for JSON schema if jsonMode is active
      if (jsonMode && (provider === 'claude' || provider === 'codex')) {
        schemaFile = path.join(os.tmpdir(), `lao_schema_${randomUUID()}.json`);
        const schema = getJsonSchemaForPrompt(params.prompt);
        fs.writeFileSync(schemaFile, JSON.stringify(schema, null, 2), 'utf8');
      }

      // 3. Build command template
      // ARG_MAX 용량 한계(E2BIG)를 완벽히 우회하기 위해, cat 연산 대신 파일 지향 리다이렉션 < "$LAO_PROMPT_FILE" 을 사용합니다.
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
            // macOS 환경을 위해 싱글 쿼테이션 이스케이프
            baseCmd += ` --json-schema "$(cat '${schemaFile}')"`;
          }
          if (!baseCmd.includes('--output-format')) {
            baseCmd += ' --output-format json';
          }
        }
        // E2BIG 회피: 셸 리다이렉션 연산자(<) 사용
        command = `${baseCmd} < "$LAO_PROMPT_FILE"`;

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
        // E2BIG 회피: 셸 리다이렉션 연산자(<) 사용
        command = `${baseCmd} < "$LAO_PROMPT_FILE"`;

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
        // E2BIG 회피: 셸 리다이렉션 연산자(<) 사용
        command = `${baseCmd} < "$LAO_PROMPT_FILE"`;

      } else if (provider === 'cursor') {
        let baseCmd = process.env.LAO_PROVIDER_CURSOR_CLI || 'cursor agent';
        if (!baseCmd.includes('--yolo') && !baseCmd.includes('-f') && baseCmd.includes('cursor')) {
          if (baseCmd.includes('agent')) {
            baseCmd = baseCmd.replace(/\bcursor agent\b/, 'cursor agent --yolo');
          } else {
            baseCmd = baseCmd.replace(/\bcursor\b/, 'cursor agent --yolo');
          }
        }
        if (!baseCmd.includes('--print') && !baseCmd.includes('-p')) {
          baseCmd += ' --print';
        }
        if (model && !baseCmd.includes('--model')) {
          baseCmd += ` --model "${model}"`;
        }
        if (jsonMode && !baseCmd.includes('--output-format')) {
          baseCmd += ' --output-format json';
        }
        // E2BIG 회피: 셸 리다이렉션 연산자(<) 사용
        command = `${baseCmd} < "$LAO_PROMPT_FILE"`;

      } else {
        // default: gemini
        let baseCmd = process.env.LAO_PROVIDER_GEMINI_CLI || 'gemini';
        if (!baseCmd.includes('--yolo') && !baseCmd.includes('--approval-mode') && baseCmd.includes('gemini')) {
          baseCmd = baseCmd.replace(/\bgemini\b/, 'gemini --approval-mode plan --sandbox false');
        }
        if (model && !baseCmd.includes('--model')) {
          baseCmd += ` --model "${model}"`;
        }
        if (jsonMode && !baseCmd.includes('--output-format')) {
          baseCmd += ' --output-format json';
        }
        // E2BIG 회피: 셸 리다이렉션 연산자(<) 사용
        command = `${baseCmd} < "$LAO_PROMPT_FILE"`;
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

      // Get cross-platform shell (non-login -c option)
      const { shell, args: shellArgs } = getShellInfo();

      // 5. 큐에 작업을 실어서 실행 (Concurrency 조절 및 좀비 해제)
      const executePromise = (taskRef: { setProcess: (proc: ChildProcess) => void }) => new Promise<string>((resolve, reject) => {
        const child = spawn(shell, [...shellArgs, command], {
          cwd: process.cwd(),
          env,
        });

        taskRef.setProcess(child);

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

        child.on('close', (code) => {
          if (params.nodeId) {
            activeProcesses.delete(params.nodeId);
          }

          if (code !== 0) {
            const error = new Error(`Command failed with exit code ${code}`) as any;
            error.code = code;
            error.stderr = stderr;
            error.stdout = stdout;
            reject(error);
          } else {
            resolve(stdout.trim());
          }
        });

        child.on('error', (err) => {
          if (params.nodeId) {
            activeProcesses.delete(params.nodeId);
          }
          reject(err);
        });
      });

      // 큐 스케줄러 가동 (90초 타임아웃 강제 탑재)
      const executionResultRaw = await queue.enqueue(
        categoryMapping(params.role),
        priority,
        (taskRef) => {
          return executePromise(taskRef);
        },
        90000 // 90초 타이머
      );

      let output = executionResultRaw;

      // 6. JSON 정규화 작업 수행 (Normalization Layer)
      if (jsonMode) {
        output = normalizeJsonResponse(output, provider);
      }

      return output;

    } catch (error: any) {
      const exitCode = error.code || -1;
      const stderr = error.stderr || '';
      const stdout = error.stdout || '';
      const status = getStatusFromCLIError(exitCode, stderr, stdout);
      const diagnosticMsg = stderr.trim() || stdout.trim() || error.message;
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

/**
 * 에이전트 역할별로 스케줄링 큐의 카테고리를 할당합니다.
 */
function categoryMapping(role?: string): 'inference' | 'mockup' | 'build' {
  if (role === 'mockup') {
    return 'mockup';
  }
  if (role === 'director' || role === 'specifier' || role === 'researcher' || role === 'optionizer' || role === 'gapDetector') {
    return 'inference';
  }
  return 'inference';
}

