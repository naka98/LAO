# LAO (Leeway AI Office)

LAO는 코딩 에이전트가 구현을 시작하기 전에 모호한 제품 아이디어를 구조화되고 잠금 상태인 AI-ready 명세서로 변환합니다.

---

## Why LAO?

코딩 에이전트는 강력하지만, 모호한 채팅 대화는 종종 방향을 잃은 구현으로 이어집니다.  
LAO는 아이디어와 코드 사이에 강력한 **기획 및 명세 검증 레이어**를 추가합니다.

```
Idea ➔ Spec Sprout ➔ Decision Cards ➔ Spec Lock ➔ DevLoop
```

---

## Who is it for?

- Claude Code, Codex, Gemini CLI, Cursor 등의 로컬 AI 에이전트를 사용하는 **개발자** (설정 및 커스텀 가능)
- 구현에 들어가기 전에 구조화된 설계를 원하는 **1인 빌더(Solo Builder)**
- 파편화된 AI 채팅 로그 대신 재사용 가능한 명세서를 구축하려는 **개발 팀**

---

## 핵심 개념 (Core Concepts)

- **Local CLI AI Engine**: 로컬 CLI 환경을 직접 연동하여 오케스트레이션 오버헤드를 최소화하고 초고속 연산을 수행합니다.
- **Director + Specialized Agents**: 디렉터 에이전트의 안내에 따라 단계별 전문 에이전트가 협업합니다.
- **Golden Rules**: 명세서에 강제되는 프로그래밍 방식의 기술 스택 및 포맷 제약 조건입니다.
- **Decision Cards**: 명세서 잠금 전 합의하는 기획 단계의 마이크로 의사결정 카드입니다.
- **Compiled Spec**: 프로젝트의 단일 진실 공급원(Single Source of Truth) 역할을 하는 명세서입니다.
- **Handover Gate**: 명세서와 코드 간의 불일치(Drift)를 줄여주는 명세 잠금 장치입니다.
- **DevLoop Console**: 개발 단계에서 로컬 빌드, 구동 및 검증을 돕는 통합 콘솔입니다.

---

## 시작 가이드 (Quick Start for Existing CLI Users)

### 필수 조건 (Prerequisites)
- Node.js v18.0.0 이상
- 설정 가능한 로컬 AI CLI 도구 (`gemini`, `claude`, `codex`, `cursor` 등) 로그인 및 인증 완료

### 1. 글로벌 설치
GitHub에서 직접 LAO를 글로벌 패키지로 설치합니다.

```bash
# yarn을 사용하는 경우
yarn global add git+https://github.com/naka98/LAO.git

# 또는 npm을 사용하는 경우
npm install -g git+https://github.com/naka98/LAO.git
```

### 2. 실행하기
기획을 진행할 프로젝트의 루트 폴더로 이동하여 아래 명령어를 실행합니다.

```bash
lao
```
LAO 로컬 서버가 `4000`번 포트에서 시작되며, 기본 브라우저에 가이드 기획 워크스페이스 대시보드가 자동으로 열립니다 (`http://localhost:4000`).

---

## 상세 문서 읽기

- 📄 [왜 LAO가 필요한가?](./docs/why-lao.ko.md)
- 📐 [아키텍처 전환 배경](./docs/v0.9_architecture.ko.md)
- ⚙️ [운영 원칙](./docs/operating-principles.ko.md)

<details>
<summary>🛠️ 로컬 개발 환경 구성 (기여용)</summary>

소스를 클론하여 로컬에서 수정하며 구동하려는 경우:

```bash
# 저장소 복제 및 이동
git clone https://github.com/naka98/LAO.git
cd LAO

# 의존성 설치 및 실행
npm install # 또는 yarn install
npm start   # 또는 yarn start
```
</details>

<details>
<summary>⚙️ 기술적 특징 및 아키텍처 상세 (v0.9.3)</summary>

### 1. 초고속 로컬 CLI AI 엔진 및 E2BIG 우회
- 무거운 로그인 셸 실행 대신 비로그인 셸(`-c`)을 사용하여 CLI 구동 지연 오버헤드를 10ms 수준으로 단축했습니다.
- UNIX 계열의 인수 크기 제한(`E2BIG` 에러)을 우회하기 위해 프롬프트 전체를 표준 파일 리다이렉션(`<`) 형태로 주입합니다.

### 2. 동시성 통제 스케줄러 큐 (Spawn Queue)
- CPU 자원 폭주와 SQLite DB 잠금 에러(`SQLITE_BUSY`)를 예방하기 위해 동시 실행 태스크를 최대 2개로 제한합니다.
- 중복되는 대기 요청을 큐에서 자동으로 Evict하고, 90초 초과 시 orphan 프로세스를 강제 종료합니다.

### 3. 기획 검증 하네스 및 자가 교정
- Given-When-Then 문법 규격 및 필수 섹션 포함 여부를 Linter로 기계적 검증합니다.
- 실패 시 에러 피드백을 프롬프트 버퍼에 주입하여 최대 3회 자가 교정을 실행합니다.
- 프로젝트 루트의 `RULES.md` 파일과 연동하여 커스텀 기술 가드레일을 강제할 수 있습니다.

### 4. 수동 중재 및 강제 승인 UI (Human-In-The-Loop)
- 자가 교정 루프 3회 실패 시, 대화창에 붉은색 검증 오류 경고 카드가 렌더링됩니다.
- 개발자는 기획안을 버리지 않고 **[강제 승인 (Force Commit)]** 버튼으로 우회 저장할 수 있습니다.

### 5. 다중 에이전트 협업 및 컨텍스트 경량화
- 디렉터가 각 분야별 스텝 에이전트에게 작업을 중계합니다.
- 에이전트별 필요한 명세서 조각만 잘라서 전달하는 **Context Budgeting** 기법을 적용합니다.

### 6. DevLoop 콘솔 및 실시간 SSE 스트리밍
- 기획 잠금 상태에서 `build`, `launch`, `verify` 명령을 실행할 수 있습니다.
- 백엔드 연산 상황을 Server-Sent Events (SSE) 진단 스트림 메시지를 브라우저 UI 화면에 직접 중계하여 대기 피로도를 줄여줍니다.

</details>
