[English](handoff.md) | 한국어

# LAO 핸드오프 메커니즘

Date: 2026-04-28

이 문서는 완료된 LAO 설계가 개발 AI(Claude Code, Codex)에 어떻게 전달되는지를 설명한다. 전달의 *원칙*은 [Design Principles §3.4](design-principles.ko.md) 참고. 이 문서는 *구현*을 다룬다.

---

## 1. 개요

디자인 워크플로우가 `completed` phase에 도달하면 LAO는 다음 세 가지 동작을 순서대로 수행한다.

1. **내보내기(Export)** — 정해진 산출물 세트를 `.lao/{ideaId}/{requestId}/`에 쓴다(임시 디렉토리에서 atomic move).
2. **MCP 서버 등록** — 프로젝트 루트에 `.mcp.json`을 작성하여 MCP 인식 AI 도구가 LAO MCP 서버를 자동 발견하게 한다.
3. **도구로 열기(사용자 트리거)** — 사용자가 "Open in Claude Code" / "Open in Codex" 버튼을 누르면 LAO가 `.command` 스크립트를 임시 디렉토리에 생성하고 Finder로 연다. macOS가 기본 동작으로 Terminal.app에서 해당 CLI를 실행하고, 초기 프롬프트가 `DESIGN_SPEC.md`를 가리킨다.

1번과 2번은 finish 동작의 일부로 자동 실행된다. 3번은 도구별로 사용자가 명시적으로 누른다.

---

## 2. 내보내기 산출물

위치: `{project_root}/.lao/{ideaId}/{requestId}/`

디렉토리는 atomic하게 교체된다 — 모든 파일을 먼저 `.tmp-{uuid}/`에 쓴 뒤 `moveItem`으로 자리를 바꾼다. 어떤 파일이라도 쓰기에 실패하면 최종 디렉토리는 이전 export 상태를 유지한다.

| 파일 | 형식 | 역할 |
|---|---|---|
| `spec.json` | JSON | 승인된 deliverable item만 (canonical filter) |
| `spec.md` | Markdown | section 타입별로 구조화된 승인 스펙 (screen / data-model / api-spec / user-flow) |
| `context.md` | Markdown | Planner의 판단 컨텍스트 — 무엇을 왜 승인/기각했는지 |
| `design.json` | JSON | 구조화된 `DesignDocument` — 기계가 읽는 정본 설계서 |
| `DESIGN_SPEC.md` | Markdown | AI 소비에 최적화된 통합 설계 스펙 (Open in… 버튼이 AI에게 가장 먼저 읽으라고 지시하는 파일) |
| `brd.json` | JSON | Business Requirements Document. **조건부** — BRD 소스가 없으면 스킵 (§2.1 참고) |
| `BRD.md` | Markdown | 사람이 읽는 BRD. `brd.json`과 같은 조건 |
| `plan.json` | JSON | `design.json`에서 도출한 구현 계획 |
| `PLAN.md` | Markdown | phase와 표준이 포함된 사람이 읽는 구현 계획 |
| `test.json` | JSON | `design.json`에서 도출한 테스트 시나리오 |
| `TEST.md` | Markdown | 우선순위별로 묶인 사람이 읽는 테스트 시나리오 |

`design.json`은 `DesignDocumentValidator`로 검증된다. 검증 에러는 Completed phase UI에 노출되지만 **export를 막지 않는다** — 파일은 그대로 쓰이고, 사용자에게 인라인 disclosure로 이슈 목록이 표시된다.

### 2.1 BRD 조건부 스킵

`brd.json`과 `BRD.md`는 다음 조건이 모두 성립할 때 스킵된다.

- 캐시된 BRD JSON이 비어 있고, **그리고**
- 캐시된 design Brief JSON이 비어 있거나 `BriefBrdEnvelope`로 디코드되지 않을 때.

즉 BRD는 워크플로우가 실제로 BRD를 만들었거나(Brief에서 추출 가능할 때만) 작성된다. 다른 산출물은 항상 작성된다.

---

## 3. `.mcp.json` 등록

위치: `{project_root}/.mcp.json` (`.lao/` 아래가 아니라 프로젝트 루트).

LAO는 기존 `.mcp.json`에 **병합**한다. 파일이 이미 있으면 `mcpServers` 맵을 보존하고 `lao-design` 키만 갱신한다.

### 3.1 두 가지 서버 엔트리 형태

빌드된 `LAOMCPServer` 바이너리를 찾았는지에 따라 형태가 달라진다.

**(a) 바이너리 발견 — 권장:**

```json
{
  "mcpServers": {
    "lao-design": {
      "type": "stdio",
      "command": "/path/to/LAOMCPServer",
      "args": ["--project-root", "/path/to/project"]
    }
  }
}
```

**(b) 바이너리 미발견 — `swift run` 폴백:**

```json
{
  "mcpServers": {
    "lao-design": {
      "type": "stdio",
      "command": "swift",
      "args": ["run", "--package-path", "/path/to/lao/package", "LAOMCPServer", "--project-root", "/path/to/project"]
    }
  }
}
```

폴백은 호스트에 LAO 소스 트리가 있고 `Package.swift`가 해석 가능할 때만 동작한다. 소스가 없는 최종 사용자 머신에서는 바이너리를 앱 번들 옆에 두어 (a) 형태가 선택되도록 한다.

### 3.2 바이너리 탐색 순서

`findMCPServerBinary()`는 다음 순서로 경로를 해석한다.

1. **앱 번들 디렉토리** — `Bundle.main.executableURL`과 같은 디렉토리, 파일명 `LAOMCPServer`. 배포·Xcode 빌드 경로.
2. **SPM 빌드 디렉토리** — `{packageRoot}/.build/{*-apple-macosx*}/{debug|release}/LAOMCPServer`. 패키지 트리 안에서 앱이 실행될 때의 로컬 개발 경로.
3. 둘 다 실패하면 `.mcp.json`에 (b) 형태가 작성된다.

---

## 4. `Open in …` 흐름

트리거: Completed phase에서 `hasExportedDeliverables && hasSubstantiveExport`가 참일 때 버튼이 노출된다. 지원 도구는 두 가지.

| 버튼 | CLI 명령 | 초기 프롬프트 |
|---|---|---|
| Open in Claude Code | `claude` | `Read .lao/{ideaId}/{requestId}/DESIGN_SPEC.md and implement the project according to the design specification.` |
| Open in Codex | `codex` | (동일) |

동작 메커니즘:

1. 시스템 임시 디렉토리에 `lao-handoff-{claude\|codex}.command`를 쓴다.
2. 스크립트는 프로젝트 루트로 `cd`한 뒤 초기 프롬프트와 함께 CLI를 실행한다.
3. LAO가 `NSWorkspace`로 스크립트를 열면 macOS 기본 동작에 따라 Terminal.app으로 위임된다.
4. CLI가 프롬프트를 입력한 상태로 시작 → AI가 `DESIGN_SPEC.md`를 읽고, 필요 시 `.mcp.json`에 등록된 `lao-design` 서버를 통해 MCP tools/resources를 호출한다.

CLI가 `PATH`에 없으면 Terminal 세션이 `command not found`를 표시한다. LAO는 `handoffLaunchFailed` 메시지로 일반적인 실행 실패를 노출한다.

---

## 5. MCP 서버 표면

등록된 `lao-design` 서버(`Packages/LAOMCPServer`로 빌드)는 표준 MCP `resources`와 `tools`로 설계 산출물을 노출한다. 서버는 `.lao/` 아래의 가장 최근 `design.json`을 해석하고, 같은 디렉토리에 BRD / plan / test JSON이 있으면 함께 로드한다.

### 5.1 Resources

정적:

| URI | 설명 |
|---|---|
| `lao://schema` | `design.json`의 JSON Schema (Draft 2020-12) |
| `lao://design` | `design.json` 전체 |
| `lao://design/markdown` | `DESIGN_SPEC.md` 렌더링 |
| `lao://tech-stack` | 설계의 프로젝트 tech stack 섹션 |
| `lao://brd` | `brd.json` |
| `lao://brd/markdown` | `BRD.md` 렌더링 |
| `lao://plan` | `plan.json` |
| `lao://plan/markdown` | 사람이 읽는 구현 계획 |
| `lao://test` | `test.json` |
| `lao://test/markdown` | 사람이 읽는 테스트 시나리오 |
| `lao://documents` | 전체 문서 묶음 (BRD + design + plan + test)을 한 번에 |

동적 — 로드된 설계의 항목별로 1개씩:

| URI 패턴 | 설명 |
|---|---|
| `lao://screens/{id}` | 화면별 스펙 |
| `lao://models/{id}` | 데이터 모델별 스펙 |
| `lao://apis/{id}` | API별 스펙 |
| `lao://flows/{id}` | 사용자 플로우별 스펙 |

export 시점에 `brd.json`이 스킵되었다면 BRD 관련 리소스는 `documents` 응답에서 빈 페이로드를 반환한다 — URI 자체는 그대로 노출된다.

### 5.2 Tools

| Tool | 필수 입력 | 용도 |
|---|---|---|
| `get_implementation_plan` | — | 권장 빌드 순서: 병렬 가능한 spec ID 그룹 |
| `get_related_specs` | `spec_id` | 화면 / 모델 / API / 플로우 전반의 상호참조 spec |
| `search_specs` | `query` | 모든 spec에 대한 키워드 검색 |
| `get_implementation_context` | `spec_id` | 한 항목의 spec + 관련 spec + tech stack + 구현 노트 |
| `get_project_context` | — | BRD 문제 정의, tech stack, MVP 범위 |
| `get_test_scenarios` | `spec_id` (선택) | 테스트 케이스, spec ID로 필터 가능 |
| `get_milestone_plan` | — | 마일스톤, phase, MVP 범위, 프로젝트 표준, 인프라 노트 |
| `reload_documents` | — | 새 export 후 디스크에서 모든 설계 문서를 다시 읽기 |
| `reload_design` | — | `reload_documents`의 alias |

`reload_design`은 구버전 클라이언트 호환을 위해 alias로 유지된다. 신규 통합은 `reload_documents`를 호출한다.

---

## 6. 전제 조건

`Open in …` 흐름:

- `PATH`에 `claude` CLI — [Claude Code](https://docs.claude.com/en/docs/claude-code)
- `PATH`에 `codex` CLI — [OpenAI Codex CLI](https://github.com/openai/codex)

`lao-design` MCP 서버 자동 시작:

- 앱 번들 옆에 빌드된 `LAOMCPServer` (권장), **또는**
- `swift`가 `PATH`에 있고 LAO 소스 트리가 있는 경우 (폴백).

최종 사용자 배포에는 `LAOMCPServer`를 함께 번들링하여 폴백이 절대 사용되지 않게 한다.

---

## 7. 트러블슈팅

| 증상 | 추정 원인 |
|---|---|
| `brd.json` / `BRD.md`가 없음 | 워크플로우가 BRD를 생성하지 않은 경우 — §2.1 참고. 다른 산출물은 그대로 존재해야 함. |
| `Open in …`이 Terminal을 열지만 CLI가 즉시 `command not found` | 사용자의 로그인 셸 `PATH`에 해당 CLI가 없음. |
| 개발 AI가 `lao-design` MCP 서버를 못 봄 | 프로젝트 루트의 `.mcp.json`이 갱신되지 않았거나, AI 도구가 다른 작업 디렉토리에서 실행됨. finish를 다시 돌리거나 `{project_root}/.mcp.json`에 `lao-design` 엔트리가 있는지 확인. |
| 재-export 후 MCP 서버 리소스가 stale | `reload_documents` tool 호출 (또는 AI 세션 재시작). |
| 최종 사용자 머신에서 `.mcp.json`이 `swift run`으로 폴백됨 | `LAOMCPServer` 바이너리가 앱 실행 파일 옆에 없음. 앱과 함께 번들링하여 바이너리 형태로 전환. |
