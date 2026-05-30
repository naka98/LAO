import * as fs from 'fs';
import * as path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';

const execPromise = promisify(exec);

export interface ValidationResult {
  isValid: boolean;
  errors: string[];
}

export interface DiagnosticsResult {
  provider: string;
  status: 'ok' | 'missing' | 'expired';
  reason?: string;
}

export class PlanningHarness {
  /**
   * 뼈대(Skeleton) 무결성을 검증합니다.
   */
  public static validateSkeleton(parsed: any): ValidationResult {
    const errors: string[] = [];

    if (!parsed) {
      return { isValid: false, errors: ['기획안 데이터가 비어 있거나 JSON 파싱에 실패했습니다.'] };
    }

    if (!parsed.coreSpec) {
      errors.push('[Core Spec 오류] coreSpec 데이터가 누락되었습니다.');
    }

    if (parsed.features && Array.isArray(parsed.features)) {
      if (parsed.features.length === 0) {
        errors.push('[Features 오류] 하나 이상의 Feature Spec 섹션이 필요합니다.');
      }
      parsed.features.forEach((feat: any, idx: number) => {
        const featTitle = feat.title || feat.name || `Feature #${idx + 1}`;
        if (!feat.id) {
          errors.push(`[Feature: ${featTitle} 오류] id 필드가 누락되었습니다.`);
        }
        if (!feat.title && !feat.name) {
          errors.push(`[Feature #${idx + 1} 오류] title 또는 name 필드가 누락되었습니다.`);
        }
        if (!feat.description && !feat.content) {
          errors.push(`[Feature: ${featTitle} 오류] description 또는 content 필드가 누락되었습니다.`);
        }
      });
    } else {
      errors.push('[Features 오류] features 배열 필드가 누락되었습니다.');
    }

    return {
      isValid: errors.length === 0,
      errors
    };
  }

  /**
   * 개별 기능 기획 본문의 세부 마크다운 형식을 정밀 검증합니다.
   */
  public static validateFeatureContent(content: string): ValidationResult {
    return this.validateFeatureSpecContent(content);
  }

  /**
   * 전체 발아(Sprout) 스펙 결과물을 일관되게 검증합니다. (Core + Features)
   */
  public static validateSprout(parsed: any): ValidationResult {
    const errors: string[] = [];

    if (!parsed) {
      return { isValid: false, errors: ['기획안 데이터가 비어 있거나 JSON 파싱에 실패했습니다.'] };
    }

    // 1. Core Spec 검증
    if (parsed.coreSpec) {
      const coreSpecStr = String(parsed.coreSpec);
      const coreCheck = this.validateCoreSpecContent(coreSpecStr);
      if (!coreCheck.isValid) {
        errors.push(...coreCheck.errors.map(err => `[Core Spec 오류] ${err}`));
      }
    } else {
      errors.push('[Core Spec 오류] coreSpec 데이터가 누락되었습니다.');
    }

    // 2. Features 검증
    if (parsed.features && Array.isArray(parsed.features)) {
      if (parsed.features.length === 0) {
        errors.push('[Features 오류] 하나 이상의 Feature Spec 섹션이 필요합니다.');
      }
      parsed.features.forEach((feat: any, idx: number) => {
        const featTitle = feat.title || feat.name || `Feature #${idx + 1}`;
        const featContent = feat.content || feat.description || '';
        
        const featCheck = this.validateFeatureSpecContent(featContent);
        if (!featCheck.isValid) {
          errors.push(...featCheck.errors.map(err => `[Feature: ${featTitle} 오류] ${err}`));
        }
      });
    } else {
      errors.push('[Features 오류] features 배열 필드가 누락되었습니다.');
    }

    // 3. 기계적 Linter: RULES.md가 존재할 시, 상반되는 기술 스택 키워드 체크
    const rulesCheck = this.lintAgainstRules(parsed);
    if (!rulesCheck.isValid) {
      errors.push(...rulesCheck.errors.map(err => `[골든 룰 위반] ${err}`));
    }

    return {
      isValid: errors.length === 0,
      errors
    };
  }

  /**
   * 단일 수정 섹션(specUpdate)의 포맷을 검증합니다.
   */
  public static validateSection(specUpdate: { sectionId: string; title?: string; content: string }): ValidationResult {
    const errors: string[] = [];

    if (!specUpdate || !specUpdate.sectionId || !specUpdate.content) {
      return { isValid: false, errors: ['업데이트 사양 본문 또는 sectionId가 누락되었습니다.'] };
    }

    const content = specUpdate.content;

    if (specUpdate.sectionId === 'core_spec') {
      const coreCheck = this.validateCoreSpecContent(content);
      errors.push(...coreCheck.errors);
    } else {
      const featCheck = this.validateFeatureSpecContent(content);
      errors.push(...featCheck.errors);
    }

    return {
      isValid: errors.length === 0,
      errors
    };
  }

  /**
   * Core Spec의 필수 마크다운 규격을 정적 검증합니다.
   */
  private static validateCoreSpecContent(content: string): ValidationResult {
    const errors: string[] = [];
    
    // Out of Scope 또는 Non-Goals 문맥 검사
    const hasOutOfScope = /##\s*(Out of Scope|Non-Goals)/i.test(content);
    if (!hasOutOfScope) {
      errors.push("Core Spec의 하단에 '## Out of Scope (Non-Goals)' 섹션이 명시되어 있지 않습니다. MVP 범위 제약을 명시하십시오.");
    }

    return {
      isValid: errors.length === 0,
      errors
    };
  }

  /**
   * Feature Spec의 필수 마크다운 규격을 정적 검증합니다.
   */
  private static validateFeatureSpecContent(content: string): ValidationResult {
    const errors: string[] = [];

    // User Story 섹션 유무
    const hasUserStory = /##\s*User Story/i.test(content);
    if (!hasUserStory) {
      errors.push("'## User Story' 섹션이 없습니다. 'As a... I want to... So that...' 양식을 반드시 명시하십시오.");
    }

    // Acceptance Criteria 섹션 유무 및 Given-When-Then 문법 검증
    const hasAcceptance = /##\s*Acceptance Criteria/i.test(content);
    if (!hasAcceptance) {
      errors.push("'## Acceptance Criteria' 섹션이 없습니다. 기능 검증을 위한 인수 조건을 기술하십시오.");
    } else {
      const hasGiven = /Given/i.test(content);
      const hasWhen = /When/i.test(content);
      const hasThen = /Then/i.test(content);
      if (!hasGiven || !hasWhen || !hasThen) {
        errors.push("Acceptance Criteria 내에 'Given', 'When', 'Then' 기술 구문이 모두 포함되어야 합니다.");
      }
    }

    return {
      isValid: errors.length === 0,
      errors
    };
  }

  /**
   * 프로젝트 루트의 RULES.md 제약 사항과 생성 스펙의 1차 상반 검사(정적 린팅)를 돌립니다.
   */
  private static lintAgainstRules(parsed: any): ValidationResult {
    const errors: string[] = [];
    const rulesPath = path.join(process.cwd(), 'RULES.md');
    if (!fs.existsSync(rulesPath)) {
      return { isValid: true, errors: [] };
    }

    try {
      const rules = fs.readFileSync(rulesPath, 'utf8').toLowerCase();
      const stringifiedSpec = JSON.stringify(parsed).toLowerCase();

      // 예시 규칙 1: React vs Vue
      if (rules.includes('react') && stringifiedSpec.includes('vue')) {
        errors.push("프로젝트 룰(RULES.md)은 React 사용을 지시하고 있으나, 스펙에 Vue 관련 명세가 발견되었습니다.");
      }

      // 예시 규칙 2: Tailwind vs CSS
      if (rules.includes('tailwind') && stringifiedSpec.includes('bootstrap')) {
        errors.push("프로젝트 룰은 Tailwind CSS 사용을 지시하고 있으나, 스펙에 Bootstrap 관련 명세가 발견되었습니다.");
      }

      // 예시 규칙 3: SQLite vs MySQL
      if (rules.includes('sqlite') && stringifiedSpec.includes('mysql') && !stringifiedSpec.includes('sqlite')) {
        errors.push("프로젝트 룰은 SQLite 사용을 지시하고 있으나, MySQL 데이터베이스 명세가 감지되었습니다.");
      }
    } catch (e) {
      console.warn('[LAO Harness] Failed to read RULES.md during static linting:', e);
    }

    return {
      isValid: errors.length === 0,
      errors
    };
  }

  /**
   * 로컬 CLI 환경 진단을 수행합니다. (바이너리 유무 및 로그인 세션 테스트)
   */
  public static async runDiagnostics(): Promise<DiagnosticsResult[]> {
    const providers = ['claude', 'gemini', 'codex', 'cursor', 'agy'];
    const results: DiagnosticsResult[] = [];

    for (const prov of providers) {
      try {
        const customEnvKey = `LAO_PROVIDER_${prov.toUpperCase()}_CLI`;
        const envVal = process.env[customEnvKey];

        // 1. 바이너리 존재 여부 1차 체크 (which)
        const isWindows = process.platform === 'win32';
        const checkCmd = isWindows ? `where ${prov}` : `which ${prov}`;
        
        try {
          await execPromise(checkCmd);
        } catch (err) {
          // 환경 변수 설정에서 직접 경로를 넘겨주었는지 확인 (예: LAO_PROVIDER_CLAUDE_CLI)
          if (!envVal) {
            results.push({
              provider: prov,
              status: 'missing',
              reason: `시스템 PATH에서 '${prov}' 명령어를 찾을 수 없으며, 환경변수 '${customEnvKey}'가 정의되지 않았습니다.`
            });
            continue;
          }
        }

        // 2. 세션 및 버전 체크 (Lightweight ping)
        let pingCmd = '';
        const binName = envVal || prov;
        if (prov === 'claude') {
          // ANTHROPIC_API_KEY 검증 포함
          if (!process.env.ANTHROPIC_API_KEY) {
            results.push({
              provider: prov,
              status: 'expired',
              reason: 'ANTHROPIC_API_KEY 환경변수가 누락되었거나 비어 있습니다.'
            });
            continue;
          }
          pingCmd = `${binName} --version`;
        } else if (prov === 'gemini') {
          if (!process.env.GEMINI_API_KEY) {
            results.push({
              provider: prov,
              status: 'expired',
              reason: 'GEMINI_API_KEY 환경변수가 누락되었거나 비어 있습니다.'
            });
            continue;
          }
          pingCmd = `${binName} --version`;
        } else if (prov === 'codex') {
          pingCmd = `${binName} --version`;
        } else if (prov === 'cursor') {
          pingCmd = `${binName} --version`;
        } else {
          pingCmd = `${binName} --help`;
        }

        try {
          await execPromise(pingCmd, { env: process.env });
          results.push({
            provider: prov,
            status: 'ok'
          });
        } catch (pingErr: any) {
          results.push({
            provider: prov,
            status: 'expired',
            reason: `CLI 실행이 거부되었거나 로그인 세션이 만료되었습니다: ${pingErr.message.trim()}`
          });
        }

      } catch (e: any) {
        results.push({
          provider: prov,
          status: 'missing',
          reason: `진단 실패: ${e.message}`
        });
      }
    }

    return results;
  }
}
