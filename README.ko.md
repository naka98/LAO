# LAO (Leeway AI Office)

LAO는 플랫폼 독립적이며 개발자 중심의 AI 설계 워크플로우 애플리케이션으로, **Node.js (Express)** 백엔드와 **React (Vite)** 프론트엔드로 구축되어 있습니다. 로컬 환경에 로그인된 다양한 CLI AI 도구들(`gemini`, `claude`, `codex`, `agy`)을 셸 프로세스로 직접 호출해 사용자의 아이디어를 체계적인 소프트웨어 기획서 및 구조로 자동 확장합니다.

---

## 아키텍처 전환 배경 (React Flow -> 문서 기반 가이드 워크스페이스)

LAO는 원래 시각적인 React Flow 마인드맵 캔버스 기반으로 설계되었으나, 다음과 같은 기술적/운영적 한계를 극복하기 위해 v0.9 버전에서 **문서 기반 가이드 기획 워크스페이스**로 완전히 전환되었습니다:
1. **인지 부하(Cognitive Load) 감소**: 복잡한 그래프 노드와 연결 관계를 수동으로 제어하는 피로를 덜어내고, 깔끔한 문서 미리보기와 고수준의 의사결정 카드를 통해 명세에 집중할 수 있도록 하였습니다.
2. **기술 스택 가드레일 (Golden Rules)**: 프로젝트 구성 설정 파일(`lao.config.json`)을 통해 핵심 기술 스택 제약 사항(예: SQLite 사용, Docker 비의존 등)을 에이전트 프롬프트에 자동으로 주입하고 통제합니다.
3. **명세서와 코드 간 드리프트 방지**: 기획 단계와 개발 단계를 명확히 분리하고, 개발 돌입 시 명세서를 읽기 전용 상태로 강제 잠금(Lock)하여 명세서가 동기화되지 않고 어긋나는 현상을 방지합니다.

---

## 핵심 기능

1. **로컬 CLI AI 엔진**: 시스템 CLI 실행 경로의 `gemini`, `claude`, `codex`, `agy` 명령어 프로세스를 `spawn` 구조로 직접 호출하여 AI를 실행합니다. 명령어 길이를 초과하지 않도록 프롬프트를 임시 파일로 자동으로 처리합니다.
2. **다중 에이전트 협업 체계**: AI 에이전트들의 대화를 분류하는 "디렉터(Director)" 에이전트와 분야별 고유 능력을 갖춘 4개 스텝 에이전트(Step Agent)가 유기적으로 작동합니다:
   * **Specifier (구체화)**: 요구사항 구체화 및 소프트웨어 컴포넌트 구조를 모듈 단위로 작성
   * **Researcher (조사)**: 구현을 위한 기술 스택 조사 및 논리적 타당성 검증
   * **Optionizer (대안 제시)**: 선택 가능한 아키텍처 의사결정을 Decision Card 형태로 제안
   * **Gap Detector (공백 감지)**: 명세서 검토를 통해 논리적 모순이나 누락 항목을 탐지
3. **제어 설정 온보딩 위저드**: 프로젝트 이름, 기본 아이디어 구상안, 자동화 레벨, 그리고 Golden Rules(기술 가드레일)을 미려한 Glassmorphic 위저드 화면에서 입력하고 시작할 수 있습니다.
4. **인터랙티브 의사결정 카드 (Decision Cards)**: Optionizer 에이전트가 제안한 의사결정 카드를 해결하면 개발자의 선택과 근거가 기준 기록 파일(`criteria.md`)에 자동으로 아카이빙됩니다.
5. **분할 화면 레이아웃 (Split-Screen)**:
   * **왼쪽 패널**: 온보딩 위저드, 미결정 의사결정 카드 목록 및 공백 탐색 경고 문구를 표시합니다.
   * **오른쪽 패널**: 실시간 통합 명세서 미리보기(Planning 단계에서 더블 클릭 시 인라인 편집 가능), DevLoop 콘솔 로그, 의사결정 누적 타임라인 로그를 탭 단위로 제공합니다.
6. **실시간 SSE 토큰 스트리밍**: 대화 입력 시, AI가 한 글자씩 실시간으로 작성하는 부드러운 타이핑 효과가 노드 대화창에 반영됩니다.
7. **개발자 루프 콘솔 (DevLoop)**: 기획 중인 프로젝트의 검증 명령어(빌드, 단위 테스트, 서버 실행 등)를 Web UI 내부에서 호출하고, 셸 표준 출력을 실시간으로 스트리밍하여 확인합니다.
8. **의사결정 히스토리 타임라인**: 자식 노드 채택 시 기록되는 `.lao/criteria.md`를 파싱하여 의사결정 진행 이력을 시간순으로 축적된 카드 형태로 제공합니다.
9. **통합 명세서 실시간 렌더러**: 개별 스펙 문서들을 수합해 최종 Markdown 명세서(`spec_compiled.md`)로 렌더링하며 즉시 복사하거나 편집할 수 있습니다.

---

## 프로젝트 구조

```
LAO/
├── cli/                 # Express 백엔드 서버 및 CLI AI 실행부
│   ├── src/
│   │   ├── agents/      # 오케스트레이터 및 프롬프트 빌더
│   │   ├── compiler.ts  # 명세서 마크다운 컴파일러
│   │   ├── gemini.ts    # spawn 셸 프로세스 실행기
│   │   ├── index.ts     # Express 엔드포인트 및 SSE 스트림
│   │   └── storage.ts   # .lao 로컬 저장소 및 설정 관리 (Specs, Decisions 포함)
│   └── package.json
└── web/                 # React 프론트엔드 (Vanilla CSS 레이아웃)
    ├── src/
    │   ├── App.tsx      # 메인 대시보드 및 제어 페이지
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

### 설치 및 구동 방법

프로젝트 루트 디렉터리에서 단 한 번의 명령어로 의존성 설치 및 CLI 백엔드와 Web UI 컴파일을 자동으로 진행할 수 있습니다.

#### 방법 A: npm 사용 시
```bash
# 전체 프로젝트 의존성 설치 및 자동 빌드 수행
npm install

# 애플리케이션 시작
npm start
```

#### 방법 B: Yarn 사용 시
```bash
# 전체 프로젝트 의존성 설치 및 자동 빌드 수행
yarn install

# 애플리케이션 시작
yarn start
```

* 백엔드 서버가 `http://localhost:4000` 포트로 실행됩니다.
* macOS의 경우 자동으로 웹 브라우저 창이 실행되어 화면이 뜹니다.

### 원격 Git 직접 / 전역 설치 (Remote Git Installation)

LAO를 시스템 전역 CLI 도구로 설치하거나, 다른 프로젝트의 원격 의존성 패키지로 직접 추가할 수 있습니다.

#### 1. 전역(Global) 설치
전역으로 설치하면 어느 디렉터리에서나 `lao` 명령어를 실행하여 바로 워크스페이스를 시작할 수 있습니다.

* **npm 사용 시**:
  ```bash
  npm install -g naka98/LAO
  ```
* **Yarn 사용 시**:
  ```bash
  yarn global add https://github.com/naka98/LAO.git
  ```

**실행 방법**:
설계를 생성하거나 관리할 프로젝트 폴더로 이동한 후 `lao` 명령어를 실행하면 됩니다:
```bash
cd /path/to/your/project
lao
```

#### 2. 프로젝트 의존성 패키지로 설치
다른 프로젝트의 `package.json`에 LAO를 의존성으로 추가해 사용할 수 있습니다.

* **npm 사용 시**:
  ```bash
  npm install naka98/LAO
  ```
* **Yarn 사용 시**:
  ```bash
  yarn add https://github.com/naka98/LAO.git
  ```
  *(참고: 의존성 추가 시, 라이프사이클 빌드 파이프라인이 작동하여 node_modules 내부의 CLI 및 Web UI 에셋을 자동으로 설치하고 빌드합니다.)*

**실행 방법**:
로컬 의존성 바이너리를 `npx` 또는 `yarn`을 사용하여 실행합니다:
```bash
# npm 사용 시
npx lao

# Yarn 사용 시
yarn lao
```

---

## 환경 변수 설정

`cli` 디렉터리 하위에 `.env` 파일을 생성하여 기본 프로바이더를 수동 제어할 수 있습니다:
```env
LAO_PROVIDER=gemini       # 사용할 CLI 도구 지정 (gemini | claude | codex | agy)
LAO_MODEL=                # (선택) 특정 모델로 실행 오버라이드
```

---

## 라이선스

이 프로젝트는 MIT 라이선스에 따라 라이선스가 부여됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하십시오.

