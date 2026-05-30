# LAO (Leeway AI Office)

LAO는 플랫폼 독립적이며 개발자 중심의 AI 설계 워크플로우 애플리케이션으로, **Node.js (Express)** 백엔드와 **React (Vite)** 프론트엔드로 구축되어 있습니다. 로컬 환경에 로그인된 다양한 CLI AI 도구들(`gemini`, `claude`, `codex`, `agy`)을 셸 프로세스로 직접 호출해 사용자의 아이디어를 체계적인 소프트웨어 기획서 및 구조로 자동 확장합니다.

---

## 아키텍처 전환 배경 (React Flow -> 문서 기반 가이드 워크스페이스)

LAO는 원래 시각적인 React Flow 마인드맵 캔버스 기반으로 설계되었으나, 다음과 같은 기술적/운영적 한계를 극복하기 위해 v0.9 버전에서 **문서 기반 가이드 기획 워크스페이스**로 완전히 전환되었습니다:
1. **인지 부하(Cognitive Load) 감소**: 복잡한 그래프 노드와 연결 관계를 수동으로 제어하는 피로를 덜어내고, 깔끔한 문서 미리보기와 고수준의 의사결정 카드를 통해 명세에 집중할 수 있도록 하였습니다.
2. **기술 스택 가드레일 (Golden Rules)**: 프로젝트 구성 설정 파일(`lao.config.json`)을 통해 핵심 기술 스택 제약 사항(예: SQLite 사용, Docker 비의존 등)을 에이전트 프롬프트에 자동으로 주입하고 통제합니다.
3. **명세서와 코드 간 드리프트 방지**: 기획 단계와 개발 단계를 명확히 분리하고, 개발 돌입 시 명세서를 읽기 전용 상태로 강제 잠금(Lock)하여 명세서가 동기화되지 않고 어긋나는 현상을 방지합니다.

---

## 핵심 기능 (v0.9.3 기준)

1. **초고속 로컬 CLI AI 엔진 및 E2BIG 우회**: 
   * 시스템 CLI의 `gemini`, `claude`, `codex`, `agy`, `cursor` 명령어를 호출할 때, 무거운 로그인 셸 실행(`-lc`) 대신 **비로그인 셸(`-c`)을 사용하여 기동 지연 오버헤드를 10ms 수준으로 최소화**하고 파일 락을 예방합니다.
   * UNIX 계열 커널의 256KB 인수 크기 제한(`E2BIG` 에러)을 우회하기 위해 프롬프트 텍스트 전체를 **표준 파일 리다이렉션(`<`) 형태로 주입**하여 대규모 기획 사양 생성을 완벽히 지원합니다.
2. **기획 검증 하네스 및 자가 교정 (PlanningHarness)**:
   * 발아되거나 수정되는 사양서 마크다운을 기계적으로 Assert 검증(예: `Out of Scope` 섹션 및 Given-When-Then 문법 규격 검사)합니다.
   * 검증 실패 시 에러 피드백을 프롬프트에 주입하여 최대 3회 자가 교정(Self-Correction)을 돌려 품질의 최저 하한선을 강제합니다.
   * **기술 스택 규칙(RULES.md) 주의사항**: 프로젝트 루트의 `RULES.md` 가이드라인 파일과 연동하여 검증을 수행합니다. 단, `RULES.md`는 **기본으로 자동 생성되지 않으므로**, 기술 스택 제약 사항 검증을 활성화하려면 프로젝트 루트에 `RULES.md` 파일을 사용자가 수동으로 생성해주어야 합니다.
3. **순차 실행 스케줄러 큐 (Spawn Queue)**:
   * 로컬 CPU 자원 점유율 폭주와 CLI SQLite DB 잠금 에러를 차단하기 위해 **동시성(최대 2개)을 통제하는 스케줄러 큐**를 가동합니다.
   * 중복성 제거(Deduplication) 기술로 대기 중인 이전 Mockup 요청을 큐에서 자동으로 추방하고, 90초 타이머 초과 시 좀비 프로세스를 소멸(`SIGKILL`)시킵니다.
   * **자동 예외 복구(Failover Fallback)**: 구동 시 설정된 주 AI 도구 CLI가 에러(바이너리 유실, API Key 인증 오류 등)로 실행 실패하는 경우, 별도 설정 없이 `gemini` ➔ `claude` ➔ `codex` 순서로 차례대로 자동 실행 대안 전환(Failover)을 시도합니다.
4. **수동 중재 및 강제 승인 UI (Human-In-The-Loop)**:
   * 자가 교정 루프 3회 초과 실패 시, UI 대시보드 대화창에 붉은색 검증 실패 카드와 세부 에러 내역을 렌더링합니다.
   * 개발자는 반려된 기획안을 버리지 않고 **[강제 승인 (Force Commit)]** 버튼을 클릭하여 하네스 예외 우회 즉각 반영 처리를 내릴 수 있습니다.
5. **다중 에이전트 협업 체계**: AI 에이전트들의 대화를 분류하는 "디렉터(Director)" 에이전트와 분야별 고유 능력을 갖춘 스텝 에이전트(Step Agent)가 유기적으로 작동하며, 에이전트별 관계 사양서만 슬라이싱하여 컨텍스트 효율을 극대화하는 **Context Budgeting**을 수행합니다.
6. **실시간 SSE 진행 상태 중계**: AI 연산 및 하네스 검증 시, 대화창 하단 로더 영역에 *"🔍 [하네스 검증] 스펙을 검증하고 있습니다..."* 등의 상태 메시지를 실시간 중계하여 사용자 대기 피로도를 대폭 완화합니다.
7. **기획 시안 5초 Debounce 가드**: 챗 업데이트로 인한 UI 시안 미리보기(`MockupGenerator`) 재생성 시, 무제한 실행을 막기 위해 **5초 디바운싱 스로틀**을 도입하여 로컬 맥북의 쿨링 팬 과열을 억제합니다.
8. **DevLoop 가상 콘솔 한계**:
   * 기획 잠금 상태에서 `build`, `launch`, `verify` 명령을 실행할 수 있습니다.
   * *유령 기능(Ghost Feature) 주의*: 백엔드 데이터 모델 및 API 레벨에서는 `uiCheck` 명령 유형(`uiCheckCommand`)이 선언되어 있으나, 현재 React 프론트엔드 UI 화면에는 해당 기능 버튼 및 연동 부가 **구현되어 있지 않습니다**.

---

## 프로젝트 구조

```
LAO/
├── cli/                 # Express 백엔드 서버 및 CLI AI 실행부
│   ├── src/
│   │   ├── agents/      # 오케스트레이터, 프롬프트 빌더, 목업 생성기 및 기획 하네스
│   │   │   ├── harness.ts      # [NEW] PlanningHarness (규격 검증 및 Linter)
│   │   │   ├── orchestrator.ts # 마이크로 에이전트 자가보정 루프 및 코디네이터
│   │   │   └── promptBuilder.ts# 에이전트용 피드백 피처 템플릿 빌더
│   │   ├── compiler.ts  # 명세서 마크다운 컴파일러
│   │   ├── gemini.ts    # spawn 셸 프로세스 연동 및 stdin 파이핑 정규화
│   │   ├── index.ts     # Express 엔드포인트, SSE 스트림 및 Debounce 스로틀
│   │   ├── scheduler.ts # [NEW] SpawnQueueManager (동시성 큐 및 타이머 가드)
│   │   └── storage.ts   # .lao 로컬 저장소 및 설정 관리
│   └── package.json
└── web/                 # React 프론트엔드 (Vanilla CSS 레이아웃)
    ├── src/
    │   ├── App.tsx      # 메인 대시보드, 에이전트 스트리밍 중계 및 수동 중재(HITL) 패널
    │   └── types.ts     # 공유 TS 타입 정의
    └── package.json
```

---

## 시작 가이드 (Quick Start)

### 필수 조건
* **Node.js** v18.0.0 이상
* **npm** v9.0.0 이상
* **Yarn** (선택) - Yarn 패키지 매니저를 사용하는 경우
* 로컬 머신에 로그인 및 설정된 AI CLI 도구:
  * **Gemini CLI**: `gemini` (기본값)
  * **Claude CLI**: `claude` (Claude Engineer)
  * **Codex CLI**: `codex`
  * **Antigravity CLI**: `agy` (선택)
  * **Cursor CLI**: `cursor` (Cursor Agent CLI) (선택)

### 설치 및 구동 방법
```bash
# 전체 프로젝트 의존성 설치 및 자동 빌드 수행
npm install

# 애플리케이션 시작 (로컬 포트 4000 구동)
npm start
```

---

## 환경 변수 설정

`cli` 디렉터리 하위에 `.env` 파일을 생성하여 기본 프로바이더 및 로컬 CLI 경로를 지정할 수 있습니다:

```env
# 기본 프로바이더 및 모델 오버라이드
LAO_PROVIDER=gemini       # 사용할 CLI 지정 (gemini | claude | codex | agy | cursor)
LAO_MODEL=                # (선택) 모델명 수동 지정

# [v0.9.3 추가] 커스텀 로컬 CLI 명령어 경로 바인딩 (PATH 자동 탐색에 실패하거나 수동 지정 필요 시)
LAO_PROVIDER_CLAUDE_CLI=/opt/homebrew/bin/claude
LAO_PROVIDER_GEMINI_CLI=/usr/local/bin/gemini
LAO_PROVIDER_CODEX_CLI=
LAO_PROVIDER_CURSOR_CLI=
LAO_PROVIDER_AGY_CLI=
```

### 아이디어 선정 및 온보딩 시 제약 사항
* `selectedOptionKey` 주의: TS 인터페이스 모델 구조상 기술 가드레일 설정 시 `'custom'` 옵션이 기재되어 있으나, 실제 아이디어 선정용 백엔드 API 엔드포인트 `/api/project/intake/select` 에서는 유효성 검증을 통해 오로지 **`'A' | 'B' | 'C'` 값만 허용**하도록 동작합니다. 커스텀 키를 전달하면 400 Bad Request 에러가 발생합니다.

---

## 라이선스

이 프로젝트는 MIT 라이선스에 따라 라이선스가 부여됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하십시오.
