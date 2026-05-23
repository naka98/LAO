# LAO (Local AI Office)

LAO는 플랫폼 독립적이며 개발자 중심의 AI 설계 워크플로우 애플리케이션으로, **Node.js (Express)** 백엔드와 **React (Vite + React Flow)** 프론트엔드로 구축되어 있습니다. 로컬 환경에 로그인된 다양한 CLI AI 도구들(`claude`, `gemini`, `codex`)을 셸 프로세스로 직접 호출해 사용자의 아이디어를 체계적이고 세련된 소프트웨어 기획서 및 구조로 자동 확장합니다.

---

## 핵심 기능

1. **로컬 CLI AI 엔진**: 시스템 CLI 실행 경로의 `gemini`, `claude`, `codex` 명령어 프로세스를 `spawn` 구조로 직접 호출하여 AI를 실행합니다. 명령어 한계를 초과하지 않도록 프롬프트를 임시 파일로 자동 파이프라인 처리합니다.
2. **다중 에이전트 협업 체계**: AI 에이전트들의 대화를 분류하는 "디렉터(Director)" 에이전트와 분야별 고유 능력을 갖춘 4개 스텝 에이전트(Step Agent)가 유기적으로 작동합니다:
   * **Specifier (구체화)**: 요구사항 구체화 및 소프트웨어 컴포넌트 구조 정의
   * **Researcher (조사)**: 구현을 위한 기술 스택 조사 및 논리적 타당성 검증
   * **Optionizer (대안 제시)**: 선택 가능한 여러 대안(Branch) 설계 도출
   * **Gap Detector (공백 감지)**: 논리적 허점, 예외 케이스 및 누락 항목 도출
3. **인터랙티브 마인드맵 (React Flow)**: 구상한 개념을 시각적 캔버스로 탐색합니다. 후보군 노드(Candidate)를 캔버스에 붙이거나(Sprout), 메인라인으로 채택(Adopt)하고, 여러 대안을 하나의 노드로 병합(Merge)할 수 있습니다.
4. **온보딩 시드 모달**: 첫 진입 시 프로젝트의 명칭과 기본 아이디어를 입력하고 기본 AI 설정을 마친 뒤 시작하면, 에이전트가 즉시 초기 대안 3가지를 마인드맵 노드에 자동으로 부착해 줍니다.
5. **에이전트별 세부 프로바이더 설정**: 5개 에이전트 역할별로 사용할 프로바이더(Gemini, Claude, Codex)와 모델을 UI 상에서 독립적으로 구성하고 실시간으로 저장 및 오버라이드할 수 있습니다.
6. **실시간 SSE 토큰 스트리밍**: 대화 입력 시, AI가 한 글자씩 실시간으로 작성하는 부드러운 타이핑 효과가 노드 대화창에 반영됩니다.
7. **개발자 루프 콘솔 (DevLoop)**: 기획 중인 프로젝트의 검증 명령어(빌드, 단위 테스트, 서버 실행 등)를 Web UI 내부에서 호출하고, 셸 표준 출력(stdout/stderr)을 검은색 가상 터미널 로그로 실시간 스트리밍하여 확인합니다.
8. **의사결정 히스토리 타임라인**: 자식 노드 채택 시 기록되는 `.lao/criteria.md`를 파싱하여 의사결정 진행 이력을 시간순으로 축적된 카드 형태로 한눈에 볼 수 있습니다.
9. **기획 명세서 실시간 렌더러**: 캔버스의 모든 노드 상태를 수합해 최종 Markdown 명세서(`spec_compiled.md`)를 작성해 주며, UI 상에서 즉시 복사(Copy)하거나 다운로드할 수 있습니다.

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
│   │   └── storage.ts   # .lao 로컬 저장소 및 설정 관리
│   └── package.json
└── web/                 # React Flow 캔버스 UI
    ├── src/
    │   ├── App.tsx      # 메인 캔버스 및 제어 페이지
    │   └── components/  # 온보딩, 디테일 패널, 설정 모달 등
    └── package.json
```

---

## 시작 가이드 (Quick Start)

### 필수 조건
* **Node.js** v18.0.0 이상
* **npm** v9.0.0 이상
* 로컬 머신에 로그인 및 설정된 AI CLI 도구:
  * **Gemini CLI**: `gemini`
  * **Claude CLI**: `claude` (Claude Engineer)
  * **Codex CLI**: `codex`

### 설치 및 구동 방법

1. **패키지 의존성 설치**:
   ```bash
   # CLI 백엔드 의존성 설치
   cd cli
   npm install

   # Web UI 의존성 설치
   cd ../web
   npm install
   ```

2. **프로젝트 빌드**:
   ```bash
   # Web UI 정적 파일 컴파일
   cd ../web
   npm run build

   # CLI 백엔드 컴파일
   cd ../cli
   npm run build
   ```

3. **애플리케이션 실행**:
   ```bash
   cd ../cli
   npm start
   ```
   * 서버가 `http://localhost:4000` 포트로 실행됩니다.
   * macOS의 경우 자동으로 웹 브라우저 창이 실행되어 화면이 뜹니다.

---

## 환경 변수 설정

`cli` 디렉터리 하위에 `.env` 파일을 생성하여 기본 프로바이더를 수동 제어할 수 있습니다:
```env
LAO_PROVIDER=gemini       # 사용할 CLI 도구 지정 (gemini | claude | codex)
LAO_MODEL=                # (선택) 특정 모델로 실행 오버라이드
```

---

## 라이선스

이 프로젝트는 MIT 라이선스에 따라 라이선스가 부여됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하십시오.
