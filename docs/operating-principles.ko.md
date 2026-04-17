[English](operating-principles.md) | 한국어

# LAO Operating Principles v0.3

Date: 2026-03-23

## 1. 목적

LAO(Leeway AI Office)는 **기획서를 AI 실행 친화적인 설계서로 바꿔주는 레이어**다.

Director와 Step 에이전트가 기획 초안을 생성하여 보여주고, 의사결정권자(사용자)가 화면에서 판단·피드백하면, 그 결과를 바탕으로 설계를 구체화하여 Claude Code/Codex에 MCP로 전달한다.

산출물 관점에서의 핵심 파이프라인:

**화면 기획서 → 공통 기준 문서 → 개발 설계서 초안**

역할 분리:
* **LAO** = 설계 전환기 — *무엇을 만들지*와 *어떻게 전달할지*를 정리
* **개발 AI** (Claude Code, Codex) = 구현기 — 정리된 설계를 실제 코드로 구현

이를 달성하기 위한 LAO의 본질은 해석 엔진 + 구조화 엔진 + 품질 유지 엔진이다.

추상적 요청
→ 의도 해석
→ 구조화
→ 역할별 세부화
→ 산출
→ 검증
→ MCP로 개발 AI에 전달

구조화된 정보는 압축되어도 의미가 보존된다. LLM 기반 시스템에서 컨텍스트는 반드시 압축된다 — 토큰 제한, phase 전환, 요약 등. 비구조화된 자연어 대화는 이 과정에서 뉘앙스와 맥락을 잃지만, 명시적 필드와 계층을 가진 구조화된 데이터는 압축 후에도 핵심이 보존된다.

의도가 정확하게 구조화되면, 다음이 자연스럽게 따라온다.

* 단계 간 전달에서 의미 손실이 적어, 컨텍스트가 비대해지지 않아도 맥락이 유지된다.
* 각 담당자가 실행 가능한 수준으로 작업을 이해하여, 결과물의 평균 수준이 올라간다.
* 구조가 반복 가능하므로, 전문가 수준의 작업 프로세스가 성립한다.

---

## 2. 핵심 철학

### 2.1 구조화 원칙

* 비구조화된 의도는 큰 작업에서 실패의 근본 원인이다.
* 구조화는 압축에 대한 내성이다 — 명시적 필드와 계층을 가진 데이터는 압축되어도 핵심이 보존된다.
* 자연어 대화는 압축 시 뉘앙스가 유실되지만, 구조화된 정보는 복원 시 원래 의도에 가깝게 재구성할 수 있다.
* LAO의 모든 변환(아이디어 → 방향 수렴 → 산출물 스켈레톤 → 상세 스펙)은 구조화 과정이다.

### 2.2 컨텍스트 관리

* 구조화된 산출물(Deliverable)은 압축에 강하므로, 긴 대화 맥락 대신 구조화된 스펙 문서를 기준으로 진행한다.
* 각 단계는 필요한 정보만 전달받아 작업하며, 불필요한 과거 컨텍스트는 누적하지 않는다.
* 슬라이딩 윈도우로 최근 대화만 유지하고, 이전 맥락은 구조화된 데이터(Work Graph, Deliverable Spec)로 보존한다.

### 2.3 2단계 운영 — IdeaBoard + Director Workflow

* 아이디어 탐색(IdeaBoard)과 실행 구조화(Director Workflow)를 분리한다.
* IdeaBoard에서 전문가 패널이 다양한 방향을 제안하고, 사용자와 대화를 통해 방향을 수렴한다.
* 수렴 시 Work Graph(entity + relationship)를 추출하여, Director Workflow에 구조화된 데이터로 전달한다.
* Director Workflow에서 Deliverable Section/Item 기반으로 상세 스펙을 생성한다.

### 2.4 디렉터 중심 구조화

* 디렉터는 사용자의 비구조화된 의도를 구조화된 작업 정보로 변환한다.
  * 모호한 요청 → 명시적 목표와 성공 기준
  * 큰 덩어리 → 계층적 분해 (DeliverableSection → DeliverableItem)
  * 자연어 의도 → 담당자별 실행 가능한 지시
* 디렉터는 해석, 분해, 전달, 평가를 책임진다.
* 디렉터는 품질 책임자이지만, 최종 제품 방향의 결정권자는 아니다.
* 최종 방향 결정과 중요한 선택은 사용자 승인에 따른다.

### 2.5 결과물 기준

* 결과물은 단순 초안이 아니라 다음 단계에서 바로 활용 가능한 수준이어야 한다.
* 모든 결과물은 명확성, 일관성, 실행 가능성, 검증 가능성을 가져야 한다.
* 목표는 단발성 생성물이 아니라 평균 수준이 높은 반복 가능한 산출 체계를 만드는 것이다.

---

## 3. 운영 구조

LAO의 기본 구조는 다음 계층을 따른다.

* Project
  * Board (요청 보드)
    * Idea (IdeaBoard — 아이디어 탐색, 메인 허브)
      * Expert Panel → Synthesis → Work Graph 추출
      * IdeaStatus 생애주기: `draft → exploring → explored → designing → designed / designFailed`
    * DesignSession (Director Workflow — 실행 구조화)
      * DirectorWorkflow
        * DeliverableSection
          * DeliverableItem
        * ItemEdge (Work Graph)

### 3.1 Project

하나의 제품, 기능군, 혹은 주요 목표 단위.
프로젝트 안에서 여러 아이디어와 워크플로우 요청이 생성될 수 있다.
프로젝트는 선택적으로 로컬 폴더(rootPath)를 연결하여 파일 탐색 컨텍스트를 제공한다.

### 3.2 Idea (IdeaBoard)

사용자의 자연어 아이디어를 전문가 패널이 탐색하는 단계.

* 사용자가 아이디어를 입력하면 Director AI가 3-5명의 전문가 패널을 구성한다.
* 각 전문가는 서로 다른 제품 방향(B2B vs B2C, MVP vs 풀스케일 등)을 제안한다.
* 사용자는 패널 전체 또는 개별 전문가와 후속 대화를 나눈다.
* 수렴(Synthesis) 시 Director가 최종 방향을 정리하고, Work Graph(entity + relationship)를 추출한다.
* 수렴 결과는 DesignSession으로 변환되어 설계 워크플로우로 전달된다.

### 3.3 DesignSession (설계 세션)

> **용어 변경 완료:** 코드 레벨(`WorkflowRequest` → `DesignSession`, `WorkflowEvent` → `DesignEvent`)과 DB 테이블명(`workflow_requests` → `design_sessions`, `workflow_events` → `design_events`) 모두 리네이밍 완료 (schema v9).

사용자의 하나의 작업 요청 단위. 프로젝트 내에서 생성되며 다음을 포함한다.

* 작업 설명 (taskDescription)
* 디렉터의 초기 분석 요약 (triageSummary)
* 워크플로우 상태 (workflowStateJSON) — DirectorWorkflow 전체를 직렬화
* IdeaBoard에서 전달된 사전 추출 그래프 (roadmapJSON)
* 사용량 추적 (apiCallCount, totalInputChars, totalOutputChars)

### 3.4 DirectorWorkflow

워크플로우의 런타임 컨테이너. 다음 phase를 거친다:

| Phase | 설명 |
|-------|------|
| `input` | 사용자가 작업 지시를 입력하는 초기 상태 |
| `analyzing` | Director가 자동 분석 + Deliverable 스켈레톤 + 접근 방식 생성 |
| `approachSelection` | 2-3개 접근 방식 비교 — 사용자가 하나를 선택 |
| `planning` | Planner 판정 + 오케스트레이션 대화 + Item Elaboration |
| `completed` | 모든 Item 완료 |
| `failed` | 복구 불가능한 실패 |

### 3.5 DeliverableSection

산출물 유형별 그룹. 사용 가능한 Section 유형:

* `screen-spec` — 화면 설계
* `data-model` — 데이터 모델
* `api-spec` — API 설계
* `user-flow` — 사용자 흐름
* 기타 프로젝트 유형에 따라 동적으로 결정

각 Section은 여러 DeliverableItem을 포함한다.

### 3.6 DeliverableItem

실제 스펙이 작성되는 최소 단위.

각 Item은 다음을 포함한다.

* 제목 (title)
* 간략 설명 (briefDescription)
* 상세 스펙 (spec) — 유형별 JSON 딕셔너리
* 상태 (status): pending → inProgress → completed 또는 needsRevision
* 병렬 그룹 (parallelGroup) — 의존성 순서 (1=독립, 2+=이전 그룹에 의존)
* 담당 에이전트 (lastAgentId, lastAgentLabel)
* 버전 추적 (version)
* 토큰 사용량 (inputTokens, outputTokens, elaborationDurationMs)

### 3.7 ItemEdge (Work Graph)

DeliverableItem 간의 관계를 표현하는 방향 그래프.

관계 유형:

* `depends_on` — A는 B가 완료되어야 시작 가능
* `navigates_to` — 화면 A에서 화면 B로 이동
* `uses` — A가 B를 호출/참조
* `refines` — A가 B를 개선/확장
* `replaces` — A가 B를 대체
* `calls` — A가 B를 호출 (최종 DesignDocument 단계의 교차 참조에서 추가로 허용)

Work Graph는 두 경로로 생성된다:
1. **IdeaBoard Synthesis** — 수렴 시 자연어 논의에서 entity/relationship 추출 → `roadmapJSON`으로 Director에 전달
2. **Director Workflow** — 분석 단계에서 Deliverable 구조와 함께 생성, 오케스트레이션 대화 중 `link_items` 액션으로 추가

---

## 4. 역할 정의

## 4.1 사용자

* 목표와 방향을 제시한다.
* IdeaBoard에서 전문가와 대화하며 방향을 탐색한다.
* Director Workflow에서 오케스트레이션 대화를 통해 산출물을 조율한다.
* 최종 방향, 우선순위, 큰 변경 사항을 결정한다.

## 4.2 디렉터

* 사용자 의도를 해석한다.
* IdeaBoard에서 전문가 패널을 구성하고, 수렴 시 방향을 정리한다.
* Director Workflow에서 Deliverable 스켈레톤을 설계한다.
* 오케스트레이션 대화를 통해 사용자와 산출물을 조율한다.
* Step Agent에 Item Elaboration을 지시한다.
* Work Graph를 관리한다 (entity 추가, 관계 연결).

디렉터는 다음을 해서는 안 된다.

* 사용자 승인 없이 제품 방향을 임의로 변경하는 것
* 검증 없이 완료 처리하는 것
* 모호한 요청을 임의 해석만으로 강행하는 것

## 4.3 Step Agent

* 자신에게 할당된 DeliverableItem의 스펙을 작성한다.
* Item 유형에 맞는 구조화된 스펙을 생성한다 (화면 → 컴포넌트/인터랙션/상태, 데이터 → 필드/관계/제약, API → 메서드/경로/요청/응답, 흐름 → 트리거/단계/분기).
* Work Graph의 관계를 참조하여 연관 Item과 일관성을 유지한다.
* 가정, 리스크, 미해결 이슈를 명시한다.

---

## 5. 문서 및 맥락 체계

### 5.1 Request Context (요청 맥락)

사용자의 원래 의도, 목표, 제약, 기대 결과.

워크플로우 내 다음 필드에 분산 저장된다:

* taskDescription — 사용자 원문 요청 (IdeaBoard 변환 시 대화 요약 포함)
* triageSummary — 디렉터의 초기 분석 요약
* roadmapJSON — IdeaBoard에서 추출된 사전 Work Graph

### 5.2 Deliverable Spec (산출물 스펙)

각 DeliverableItem의 `spec` 필드에 유형별 JSON으로 저장된다.

유형별 핵심 필드:
* **screen-spec**: 컴포넌트 목록, 인터랙션, 상태 모델, 레이아웃
* **data-model**: 필드 정의, 관계, 제약 조건, 인덱스
* **api-spec**: HTTP 메서드, 경로, 요청/응답 스키마, 에러 코드
* **user-flow**: 트리거, 단계, 분기점, 성공/실패 경로

### 5.3 Work Graph

DeliverableItem 간의 관계를 `ItemEdge` 배열로 관리한다.
Item Elaboration 프롬프트에 관계 정보가 포함되어, 연관 Item의 스펙을 참조하며 일관성을 유지한다.

### 5.4 오케스트레이션 대화 (Chat History)

Director와 사용자의 대화 기록. `DirectorWorkflow.chatHistory`에 저장된다.
프롬프트에는 최근 20개 메시지만 포함하여 컨텍스트 비대화를 방지한다.

### 5.5 IdeaBoard 대화 컨텍스트

* **패널 전체 후속 질문**: 최근 Director 요약 + 최근 4개 메시지 (슬라이딩 윈도우)
* **개별 전문가 카드 대화**: 최근 8개 메시지 (슬라이딩 윈도우)

---

## 6. 품질 관리 프로세스

### 6.1 아이디어 정제

* 작업은 아이디어에서 시작한다.
* IdeaBoard에서 전문가 패널이 다양한 방향을 제안한다.
* 사용자는 후속 질문과 개별 전문가 대화를 통해 방향을 구체화한다.
* 수렴(Synthesis)으로 최종 방향과 Work Graph를 추출한다.

### 6.2 자동 분석

* Director Workflow 진입 시 Director가 자동으로 Deliverable 스켈레톤과 2-3개 접근 방식을 생성한다.
* IdeaBoard에서 전달된 사전 Work Graph가 있으면 분석의 시작점으로 활용한다.
* 프로젝트 유형, Section 구조, Item 목록, 관계를 한 번의 LLM 호출로 도출한다.

### 6.3 접근 방식 선택

* 분석 단계에서 Director가 2-3개의 접근 방식(ApproachOption)을 생성한다.
* 각 접근 방식은 라벨, 요약, 장단점, 프로젝트 스펙, Deliverable 스켈레톤을 포함한다.
* 사용자가 하나를 선택하면 해당 접근 방식의 Deliverable 구조로 Planning 단계에 진입한다.

### 6.4 오케스트레이션 조율

* 사용자는 Director와 채팅으로 Deliverable을 조율한다.
* Director는 다음 액션을 제안한다:
  * `elaborate_item` — Step Agent에 Item 스펙 작성 지시
  * `update_item` / `add_item` / `remove_item` — Item 관리
  * `add_section` — Section 추가
  * `link_items` — Work Graph 관계 추가
  * `mark_complete` — 워크플로우 완료 신호

### 6.5 Item Elaboration

* Step Agent가 할당된 Item의 상세 스펙을 작성한다.
* 동일 Section의 다른 Item과 다른 Section의 완료된 Item을 컨텍스트로 제공한다.
* Work Graph 관계를 참조하여 연관 Item과 일관성을 유지한다.
* 유형별 가이드라인에 따라 구조화된 JSON 스펙을 생성한다.

### 6.6 에이전트 할당

* Director가 각 Item에 가장 적합한 Step Agent를 자동 할당한다.
* Agent의 전문성(systemPrompt)과 Item 유형을 매칭한다.
* UI Item → 프론트엔드 전문 Agent, 데이터 Item → 백엔드 전문 Agent.

### 6.7 일관성 검증

* `buildConsistencyCheckPrompt`로 전체 Deliverable의 일관성을 검증한다.
* 누락 Item, 깨진 참조, 미완성 Item, 불일치를 점검한다.

---

## 7. 자동화와 승인 경계

### 7.1 자동 실행 (사용자 개입 없음)

* 자동 분석 (Deliverable 스켈레톤 생성)
* Agent 자동 할당
* Item Elaboration (병렬 실행)
* Work Graph 관계 자동 감지
* 사용량 추적

### 7.2 디렉터 자율 결정

오케스트레이션 중 사용자 메시지에 대한 응답으로 Director가 자율적으로 실행하는 액션:

* Item 추가/수정/삭제
* Section 추가
* 관계 연결
* Elaboration 지시

### 7.3 사용자 승인 (명시적 확인 필요)

* 제품 방향 변경
* 워크플로우 완료 (mark_complete)
* 대규모 구조 변경

원칙:

* 자동화는 속도를 위한 것이고,
* 자율 결정은 흐름 유지를 위한 것이며,
* 승인은 방향 정확도를 위한 것이다.

---

## 8. 운영 원칙 요약

* LAO는 기획서를 AI 실행 친화적인 설계서로 바꿔주는 레이어다.
* 핵심 파이프라인: 화면 기획서 → 공통 기준 문서 → 개발 설계서 초안.
* LAO(설계 전환기)와 개발 AI(구현기)는 역할이 분리된다.
* 사용자의 의도를 정확하게 구조화하는 것이 모든 운영의 출발점이다.
* 구조화된 정보는 압축되어도 의미가 보존된다.
* IdeaBoard에서 자연어 탐색 → Work Graph 추출 → Director Workflow에서 상세 스펙 생성.
* 원 대화가 아니라 구조화된 Deliverable Spec과 Work Graph로 맥락을 유지한다.
* 큰 작업은 DeliverableSection → DeliverableItem으로 분해한다.
* 디렉터는 사용자 의도의 구조화자이자 품질 책임자다.
* 결과물은 다음 단계에서 바로 쓸 수 있어야 한다.
* 완성된 설계서는 MCP를 통해 Claude Code/Codex에 전달한다.
* 자동화 가능한 것은 자동화하되, 방향은 승인으로 통제한다.

---

## 9. 다음 버전에서 추가 검토할 항목

* Work Graph 기반 Elaboration 순서 최적화 (위상 정렬)
* 완료 Item의 하위 의존 Item 자동 시작 (Completion Cascade)
* Item 간 일관성 자동 검증 강화
* 에러 전파 — 실패 Item의 downstream Item 자동 중단
* Export/문서 생성에 Work Graph 관계 반영
* provider별 역할 분담 정책

---

이 문서는 LAO의 철학 선언을 실제 운영 가능한 규칙으로 변환한 것이다. 이후 실제 사용 중 발견되는 문제를 반영하여 계속 개선한다.
