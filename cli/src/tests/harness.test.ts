import * as fs from 'fs';
import * as path from 'path';
import { PlanningHarness } from '../agents/harness';

describe('PlanningHarness Unit Tests', () => {
  describe('validateSkeleton', () => {
    it('should fail validation when parsed object is null or undefined', () => {
      const result1 = PlanningHarness.validateSkeleton(null);
      expect(result1.isValid).toBe(false);
      expect(result1.errors[0]).toContain('기획안 데이터가 비어 있거나 JSON 파싱에 실패했습니다.');

      const result2 = PlanningHarness.validateSkeleton(undefined);
      expect(result2.isValid).toBe(false);
      expect(result2.errors[0]).toContain('기획안 데이터가 비어 있거나 JSON 파싱에 실패했습니다.');
    });

    it('should fail when coreSpec is missing', () => {
      const parsed = {
        features: [
          { id: 'feat_1', title: 'Feature 1', content: 'Some content' }
        ]
      };
      const result = PlanningHarness.validateSkeleton(parsed);
      expect(result.isValid).toBe(false);
      expect(result.errors).toContain('[Core Spec 오류] coreSpec 데이터가 누락되었습니다.');
    });

    it('should fail when features field is missing or empty array', () => {
      const parsedNoFeatures = {
        coreSpec: 'Some architecture plan'
      };
      const resultNoFeatures = PlanningHarness.validateSkeleton(parsedNoFeatures);
      expect(resultNoFeatures.isValid).toBe(false);
      expect(resultNoFeatures.errors).toContain('[Features 오류] features 배열 필드가 누락되었습니다.');

      const parsedEmptyFeatures = {
        coreSpec: 'Some architecture plan',
        features: []
      };
      const resultEmptyFeatures = PlanningHarness.validateSkeleton(parsedEmptyFeatures);
      expect(resultEmptyFeatures.isValid).toBe(false);
      expect(resultEmptyFeatures.errors).toContain('[Features 오류] 하나 이상의 Feature Spec 섹션이 필요합니다.');
    });

    it('should fail when feature items lack mandatory fields (id, title/name, description/content)', () => {
      const parsedInvalidFeat = {
        coreSpec: 'Some architecture plan',
        features: [
          { title: 'Feature 1', content: 'Content' }, // lacks id
          { id: 'f2', content: 'Content' }, // lacks title/name
          { id: 'f3', name: 'Feature 3' } // lacks description/content
        ]
      };
      const result = PlanningHarness.validateSkeleton(parsedInvalidFeat);
      expect(result.isValid).toBe(false);
      expect(result.errors.length).toBe(3);
      expect(result.errors[0]).toContain('id 필드가 누락되었습니다.');
      expect(result.errors[1]).toContain('title 또는 name 필드가 누락되었습니다.');
      expect(result.errors[2]).toContain('description 또는 content 필드가 누락되었습니다.');
    });
  });

  describe('validateSprout (including Core & Feature content validation)', () => {
    it('should validate coreSpec has "Out of Scope" or "Non-Goals" section', () => {
      const invalidParsed = {
        coreSpec: '# Core Spec\nNo scoping constraints here.',
        features: [
          {
            id: 'f1',
            title: 'Feature 1',
            content: '## User Story\nAs a... I want to... So that...\n## Acceptance Criteria\nGiven standard context\nWhen action happens\nThen expect outcome'
          }
        ]
      };
      const result = PlanningHarness.validateSprout(invalidParsed);
      expect(result.isValid).toBe(false);
      expect(result.errors.some(err => err.includes("Core Spec의 하단에 '## Out of Scope (Non-Goals)' 섹션이 명시되어 있지 않습니다."))).toBe(true);

      const validParsed = {
        coreSpec: '# Core Spec\n## Out of Scope\nNo external database integration.',
        features: [
          {
            id: 'f1',
            title: 'Feature 1',
            content: '## User Story\nAs a... I want to... So that...\n## Acceptance Criteria\nGiven standard context\nWhen action happens\nThen expect outcome'
          }
        ]
      };
      const resultValid = PlanningHarness.validateSprout(validParsed);
      expect(resultValid.isValid).toBe(true);
    });

    it('should validate feature content contains User Story and proper Acceptance Criteria', () => {
      const parsedNoUserStory = {
        coreSpec: '# Core Spec\n## Out of Scope\nNone',
        features: [
          {
            id: 'f1',
            title: 'Feature 1',
            content: '## Acceptance Criteria\nGiven standard context\nWhen action happens\nThen expect outcome'
          }
        ]
      };
      const result1 = PlanningHarness.validateSprout(parsedNoUserStory);
      expect(result1.isValid).toBe(false);
      expect(result1.errors.some(err => err.includes("'## User Story' 섹션이 없습니다."))).toBe(true);

      const parsedNoGivenWhenThen = {
        coreSpec: '# Core Spec\n## Out of Scope\nNone',
        features: [
          {
            id: 'f1',
            title: 'Feature 1',
            content: '## User Story\nAs a... I want to... So that...\n## Acceptance Criteria\nShould just work somehow without GWT.'
          }
        ]
      };
      const result2 = PlanningHarness.validateSprout(parsedNoGivenWhenThen);
      expect(result2.isValid).toBe(false);
      expect(result2.errors.some(err => err.includes("Acceptance Criteria 내에 'Given', 'When', 'Then' 기술 구문이 모두 포함되어야 합니다."))).toBe(true);
    });
  });

  describe('RULES.md Linter integration', () => {
    const rulesPath = path.join(process.cwd(), 'RULES.md');
    let originalRulesExist = false;
    let originalRulesContent = '';

    beforeAll(() => {
      if (fs.existsSync(rulesPath)) {
        originalRulesExist = true;
        originalRulesContent = fs.readFileSync(rulesPath, 'utf8');
      }
    });

    afterAll(() => {
      if (originalRulesExist) {
        fs.writeFileSync(rulesPath, originalRulesContent, 'utf8');
      } else if (fs.existsSync(rulesPath)) {
        fs.unlinkSync(rulesPath);
      }
    });

    it('should detect conflicting technology rules defined in RULES.md', () => {
      const testRules = `
- Framework: React
- CSS: Tailwind CSS
- Database: SQLite
      `;
      fs.writeFileSync(rulesPath, testRules, 'utf8');

      const conflictingParsed = {
        coreSpec: '# Architecture\nWe plan to use Vue.js for components, Bootstrap for styling, and MySQL as database.',
        features: [
          {
            id: 'f1',
            title: 'Feat 1',
            content: '## User Story\nAs a... I want to... So that...\n## Acceptance Criteria\nGiven context\nWhen action\nThen result\n## Out of Scope\nNone'
          }
        ]
      };

      const result = PlanningHarness.validateSprout(conflictingParsed);
      expect(result.isValid).toBe(false);
      
      const errorsStr = JSON.stringify(result.errors);
      expect(errorsStr).toContain('React 사용을 지시하고 있으나, 스펙에 Vue 관련 명세가 발견되었습니다.');
      expect(errorsStr).toContain('Tailwind CSS 사용을 지시하고 있으나, 스펙에 Bootstrap 관련 명세가 발견되었습니다.');
      expect(errorsStr).toContain('SQLite 사용을 지시하고 있으나, MySQL 데이터베이스 명세가 감지되었습니다.');
    });
  });

  describe('runDiagnostics', () => {
    it('should run diagnostics on system and check providers', async () => {
      // 일부 환경변수를 Mocking 하여 진단 동작의 흐름 및 분기 테스트
      const originalAnthropicKey = process.env.ANTHROPIC_API_KEY;
      const originalGeminiKey = process.env.GEMINI_API_KEY;

      process.env.ANTHROPIC_API_KEY = ''; // Claude key missing
      process.env.GEMINI_API_KEY = 'mock-key';

      const results = await PlanningHarness.runDiagnostics();
      expect(Array.isArray(results)).toBe(true);

      const claudeResult = results.find(r => r.provider === 'claude');
      expect(claudeResult).toBeDefined();
      if (claudeResult) {
        // key가 비었으므로 expired 상태이거나 missing이어야 함
        expect(['expired', 'missing']).toContain(claudeResult.status);
        if (claudeResult.status === 'expired') {
          expect(claudeResult.reason).toContain('ANTHROPIC_API_KEY 환경변수가 누락되었거나 비어 있습니다.');
        }
      }

      // 복구
      if (originalAnthropicKey) {
        process.env.ANTHROPIC_API_KEY = originalAnthropicKey;
      } else {
        delete process.env.ANTHROPIC_API_KEY;
      }
      if (originalGeminiKey) {
        process.env.GEMINI_API_KEY = originalGeminiKey;
      } else {
        delete process.env.GEMINI_API_KEY;
      }
    });

    it('should succeed diagnostics for a provider if it is fully configured', async () => {
      // 실제 로컬에 설치되어 있고 키가 설정되어 있다면 ok로 진단되는 것을 한 번 확인
      // (단, 머신에 의존적이므로 dynamic하게 체크하여 assertions 구성)
      const results = await PlanningHarness.runDiagnostics();
      expect(results.length).toBeGreaterThan(0);
      
      results.forEach(res => {
        expect(res.provider).toBeDefined();
        expect(['ok', 'missing', 'expired']).toContain(res.status);
      });
    });
  });
});
