import { useState, useEffect, useRef } from 'react';
import {
  Brain,
  FileText,
  Check,
  Settings,
  AlertCircle,
  X,
  Play,
  Terminal,
  Loader2,
  Lock,
  Unlock,
  AlertTriangle,
  Send,
  Sparkles,
  GitBranch,
  BookOpen,
  ArrowRight,
  Globe,
  ListTodo,
  RotateCw
} from 'lucide-react';
import type { SpecSection, DecisionCard, NodeMessage, ProjectConfig, GoldenRules, TaskItem, IntakeProposals } from './types';
import { marked } from 'marked';
import mermaid from 'mermaid';

marked.use({
  gfm: true,
  breaks: true,
  renderer: {
    code(token) {
      const { text, lang } = token;
      if (lang === 'mermaid') {
        return `<div class="mermaid">${text}</div>`;
      }
      return `<pre class="bg-slate-950 p-4 rounded-xl border border-slate-900 font-mono text-xs overflow-x-auto text-slate-350 my-4"><code class="language-${lang || ''}">${text}</code></pre>`;
    }
  }
});

const translations = {
  en: {
    projectNamePlaceholder: "e.g. Local Database WebUI",
    roughIdeaPlaceholder: "Type your rough idea here... e.g. A lightweight web-based console to view and query local SQLite files with schema diagrams.",
    launchProject: "Launch New Project",
    launchDesc: "Transform a rough seed idea into compiled specs & code",
    projectNameLabel: "Project Name",
    roughIdeaLabel: "Rough Seed Idea",
    goldenRulesTitle: "Golden Rules Presets (Technology Guardrails)",
    frontendLabel: "Frontend",
    backendLabel: "Backend",
    databaseLabel: "Database",
    additionalLabel: "Constraints",
    automationLevelLabel: "Automation Level",
    supervisedLabel: "Supervised (High)",
    supervisedDesc: "Wait for approvals (Default)",
    interactiveLabel: "Interactive (Medium)",
    interactiveDesc: "Proceed and notify",
    autopilotLabel: "Autopilot (Low)",
    autopilotDesc: "Full hands-off build",
    sproutSpecsBtn: "Analyze Concept & Formulate Options",
    loadingSpecs: "Orchestrating AI Agents...",
    loadingSpecsDesc: "Specifier is drafting core specs, Optionizer is spawning decision forks, and Gap Detector is scanning the initial files. Please wait.",
    startDevelopment: "Start Development",
    lockSpecCTA: "Lock Spec",
    unlockPlanning: "Unlock Planning",
    planningPhase: "PLANNING (EDITABLE)",
    developmentPhase: "DEVELOPMENT (LOCKED)",
    decisionCardsDeck: "Decision Cards Deck",
    allResolved: "All option forks resolved! The design aligns with the Golden Rules.",
    officeAgentChat: "Office Agent Chat",
    directorRouting: "Director routing...",
    responding: "responding...",
    chatLocked: "Chat locked in development phase",
    chatPlaceholder: "Ask Specifier / Researcher / Gap Detector...",
    compiledSpecTab: "Compiled Spec",
    devloopConsoleTab: "DevLoop Console",
    decisionTimelineTab: "Decision Timeline",
    gapAuditorTab: "Gap Auditor Logs",
    runGapAudit: "Run Gap Audit",
    doubleClickToEdit: "Double-click content to edit",
    cancelBtn: "Cancel",
    saveSpecBtn: "Save Spec Section",
    noContent: "*(No details specified yet)*",
    runBuildBtn: "Run Build",
    runVerifyBtn: "Run Verify (Tests)",
    launchServerBtn: "Launch Server",
    consoleIdle: "Console idle. Trigger a DevLoop build or verification command...",
    noDecisionLogs: "No decision logs found. Resolve a Decision Card to log criteria.",
    gapReportTitle: "Specification Gap Report",
    gapReportDesc: "Click the \"Run Gap Audit\" button at the top right to verify all specifications against architectural guardrails.",
    projectConfigTitle: "Project Configuration",
    globalPresetsTab: "Global Presets",
    agentConfigTab: "Agent Customization",
    devloopCommandsTab: "DevLoop Commands",
    globalProviderLabel: "Global AI Provider",
    modelOverrideLabel: "Model Override (Optional)",
    agentRoleLabel: "Agent",
    defaultModelPlaceholder: "default model",
    buildCommandLabel: "Build Command",
    verifyCommandLabel: "Verify (Test) Command",
    launchCommandLabel: "Launch Command",
    closeBtn: "Close",
    saveConfigBtn: "Save Config",
    toastErrorLoading: "Error loading project workspace",
    toastSprouted: "Specs sprouted successfully conforming to Golden Rules!",
    toastDecisionResolved: "Decision resolved: ",
    toastSectionUpdated: "Section updated successfully",
    toastLocked: "Specifications LOCKED. Development phase active!",
    toastUnlocked: "Specifications UNLOCKED. Planning phase active.",
    toastGapCompleted: "Gap Audit completed successfully.",
    toastGapFailed: "Gap Audit failed",
    toastSpecLockedWarning: "Specifications are locked during development phase",
    tasksTitle: "Implementation Checklist",
    generateTasksBtn: "Regenerate Checklist",
    noTasks: "No implementation tasks generated yet.",
    toastTasksGenerated: "Checklist generated successfully from specification!",
    toastTaskUpdated: "Task status updated.",
    previewTab: "Preview",
    errorExplanationTitle: "AI Debugging Assistant",
    previewUrlPlaceholder: "Preview URL (e.g. http://localhost:3050)",
    importPrdBtn: "Import PRD File (.md, .txt)",
    toastPrdLoaded: "PRD file loaded successfully.",
    toastPrdLoadFailed: "Failed to read PRD file.",
    toastPrdTypeWarning: "Only text or markdown files (.md, .txt) are supported.",
    stepIndicator: "Step {step} of 3: {title}",
    proposalsTitle: "Concept Divergence (Multi-Option Selection)",
    proposalsDesc: "LAO has generated three distinct product directions based on your seed idea and constraints. Select the best match to sprout specifications.",
    optionATitle: "Option A: Fast MVP",
    optionBTitle: "Option B: Structural Extension",
    optionCTitle: "Option C: Differentiated Experiment",
    recommendedLabel: "Director Recommendation",
    reasonLabel: "Rationale",
    discardedLabel: "Discarded Options Context",
    decisionsRequiredLabel: "Key Decisions Required",
    customAdjustmentsPlaceholder: "Add specific adjustments, combined features, or modifications to the chosen option...",
    regenerateFeedbackPlaceholder: "Provide feedback to regenerate alternative directions (e.g., 'Make Option B more lightweight, focus on mobile')...",
    regenerateBtn: "Regenerate Drafts",
    selectOptionBtn: "Select and Sprout Spec",
    toastProposalsGenerated: "Concept proposals generated successfully!",
    toastSpecSproutingStarted: "Sprouting specifications based on selected concept...",
    loadingProposals: "Diverging Concepts...",
    loadingProposalsDesc: "Intake Agent is defining multiple routes, Director Agent is analyzing trade-offs, and Conflict Detector is auditing feasibility. Please wait.",
    diagnosticsTab: "System Diagnostics",
    runDiagnosticsBtn: "Run Diagnostics",
    diagnosticsTitle: "Local AI CLI Diagnostics",
    diagnosticsDesc: "Verify your local environment to ensure that local CLI AI paths and API configurations are properly functional.",
  },
  ko: {
    projectNamePlaceholder: "예: 로컬 데이터베이스 웹 UI",
    roughIdeaPlaceholder: "머릿속의 대략적인 아이디어를 자유롭게 적어보세요... 예: SQLite 파일을 로컬에서 열어서 쿼리를 수행하고 스키마 다이어그램을 그려주는 가벼운 웹 도구.",
    launchProject: "새 프로젝트 시작하기",
    launchDesc: "러프한 아이디어 시드에서 정제된 기획 문서 및 코드로 변환합니다",
    projectNameLabel: "프로젝트 이름",
    roughIdeaLabel: "대략적인 아이디어",
    goldenRulesTitle: "골든 룰 프리셋 (기술 스택 제약 조건)",
    frontendLabel: "프론트엔드",
    backendLabel: "백엔드",
    databaseLabel: "데이터베이스",
    additionalLabel: "기타 제약사항",
    automationLevelLabel: "자동화 단계",
    supervisedLabel: "승인 대기 (상)",
    supervisedDesc: "결정 사항 승인 대기 (기본값)",
    interactiveLabel: "알림 후 진행 (중)",
    interactiveDesc: "설계 진행 후 변경 알림",
    autopilotLabel: "완전 자동 (하)",
    autopilotDesc: "개입 없는 자율 설계 진행",
    sproutSpecsBtn: "아이디어 분석 및 대안 기획 생성",
    loadingSpecs: "AI 에이전트단 오케스트레이션 중...",
    loadingSpecsDesc: "기획 에이전트가 초안을 작성하고, 대안 분석 에이전트가 선택지를 분기하고, 모순 감지 에이전트가 설계를 검토하고 있습니다. 잠시만 기다려 주세요.",
    startDevelopment: "개발 단계 전환",
    lockSpecCTA: "기획 잠금",
    unlockPlanning: "기획 수정 (잠금 해제)",
    planningPhase: "기획 설계 단계 (수정 가능)",
    developmentPhase: "개발 진행 단계 (기획 잠금)",
    decisionCardsDeck: "의사결정 카드 덱",
    allResolved: "모든 설계 옵션이 결정되었습니다! 골든 룰에 부합합니다.",
    officeAgentChat: "오피스 에이전트 대화방",
    directorRouting: "디렉터 에이전트 라우팅 중...",
    responding: "답변 중...",
    chatLocked: "개발 단계에서는 대화방이 잠깁니다",
    chatPlaceholder: "기획자 / 리서처 / 갭 디텍터에게 질문하기...",
    compiledSpecTab: "통합 사양서",
    devloopConsoleTab: "개발 루프 콘솔",
    decisionTimelineTab: "의사결정 타임라인",
    gapAuditorTab: "기획 누락 감사로그",
    runGapAudit: "기획 모순 감사 실행",
    doubleClickToEdit: "더블클릭하여 명세서 수정하기",
    cancelBtn: "취소",
    saveSpecBtn: "명세 섹션 저장",
    noContent: "*(아직 상세 사양이 정의되지 않았습니다)*",
    runBuildBtn: "빌드 명령어 실행",
    runVerifyBtn: "테스트 검증 실행",
    launchServerBtn: "로컬 서버 기동",
    consoleIdle: "콘솔이 유휴 상태입니다. 빌드 또는 테스트 검증 명령어를 실행하세요...",
    noDecisionLogs: "기록된 의사결정 이력이 없습니다. 의사결정 카드를 해결해 보세요.",
    gapReportTitle: "기획 정밀 감사 리포트",
    gapReportDesc: "우측 상단의 '기획 모순 감사 실행' 버튼을 클릭하여 기획서에 누락이나 골든 룰 위반이 없는지 확인하세요.",
    projectConfigTitle: "프로젝트 환경 설정",
    globalPresetsTab: "글로벌 프리셋",
    agentConfigTab: "에이전트 역할 설정",
    devloopCommandsTab: "개발 명령어",
    globalProviderLabel: "글로벌 AI 프로바이더",
    modelOverrideLabel: "모델명 수동 지정 (선택)",
    agentRoleLabel: "에이전트 역할",
    defaultModelPlaceholder: "기본 모델 사용",
    buildCommandLabel: "빌드 명령어",
    verifyCommandLabel: "테스트 검증 명령어",
    launchCommandLabel: "서버 기동 명령어",
    closeBtn: "닫기",
    saveConfigBtn: "설정 저장",
    toastErrorLoading: "프로젝트 작업 공간을 로드하는 데 실패했습니다.",
    toastSprouted: "골든 룰에 부합하는 사양 초안이 생성되었습니다!",
    toastDecisionResolved: "의사결정이 반영되었습니다: ",
    toastSectionUpdated: "명세 섹션이 성공적으로 저장되었습니다.",
    toastLocked: "기획서가 잠겼습니다. 이제 개발 단계를 시작합니다!",
    toastUnlocked: "기획서 잠금이 해제되었습니다. 기획 설정을 수정할 수 있습니다.",
    toastGapCompleted: "기획 감사가 성공적으로 완료되었습니다.",
    toastGapFailed: "기획 감사 실행에 실패했습니다.",
    toastSpecLockedWarning: "개발 단계 중에는 기획서를 수정할 수 없습니다.",
    tasksTitle: "구현 태스크 체크리스트",
    generateTasksBtn: "체크리스트 재생성",
    noTasks: "생성된 구현 태스크가 없습니다.",
    toastTasksGenerated: "명세서로부터 구현 태스크를 성공적으로 생성했습니다!",
    toastTaskUpdated: "태스크 상태가 업데이트되었습니다.",
    previewTab: "미리보기",
    errorExplanationTitle: "AI 오류 분석 및 대처 가이드",
    previewUrlPlaceholder: "미리보기 URL (예: http://localhost:3000)",
    importPrdBtn: "PRD 파일 불러오기 (.md, .txt)",
    toastPrdLoaded: "PRD 파일을 성공적으로 불러왔습니다.",
    toastPrdLoadFailed: "PRD 파일을 읽는데 실패했습니다.",
    toastPrdTypeWarning: "텍스트 또는 마크다운 파일(.md, .txt)만 불러올 수 있습니다.",
    stepIndicator: "3단계 중 {step}단계: {title}",
    proposalsTitle: "기획 대안 분산 및 선택",
    proposalsDesc: "LAO가 입력하신 아이디어와 골든 룰에 기반하여 서로 다른 세 가지 제품 접근 방향을 생성했습니다. 가장 적합한 접근안을 선택해 명세를 구체화하세요.",
    optionATitle: "대안 A: 빠른 MVP형",
    optionBTitle: "대안 B: 구조 확장형",
    optionCTitle: "대안 C: 차별화 실험형",
    recommendedLabel: "디렉터 추천안",
    reasonLabel: "추천 사유",
    discardedLabel: "보류한 선택지 분석",
    decisionsRequiredLabel: "사용자가 결정해야 할 항목",
    customAdjustmentsPlaceholder: "선택한 대안에 추가하고 싶은 맞춤형 세부 요구사항이나 결합하고 싶은 기능들을 입력해 주세요...",
    regenerateFeedbackPlaceholder: "기획 대안을 다시 생성하고 싶다면 피드백을 적어주세요 (예: '대안 B를 더 가볍게 만들고 모바일에만 집중하도록 해줘')...",
    regenerateBtn: "대안 재구성 및 생성",
    selectOptionBtn: "대안 선택 및 핵심 명세 생성",
    toastProposalsGenerated: "세 가지 대안이 구성되었습니다!",
    toastSpecSproutingStarted: "선택한 대안을 토대로 사양 명세를 구체화하는 중...",
    loadingProposals: "대안 기획안 발산 중...",
    loadingProposalsDesc: "기획 에이전트가 여러 도메인 접근안을 정의하고, 디렉터 에이전트가 각 장단점을 비교하여 최선의 추천 시나리오를 조율하고 있습니다. 잠시만 기다려 주세요.",
    diagnosticsTab: "시스템 자가진단",
    runDiagnosticsBtn: "자가진단 실행",
    diagnosticsTitle: "로컬 AI CLI 자가진단",
    diagnosticsDesc: "로컬 환경의 CLI AI 경로 및 API 설정 상태를 진단하여 정상 작동하는지 검사합니다.",
  }
};

export default function App() {
  // Localization state
  const [lang, setLang] = useState<'ko' | 'en'>(() => {
    const browserLang = navigator.language.substring(0, 2);
    return browserLang === 'ko' ? 'ko' : 'en';
  });
  const t = translations[lang];

  // App Core States
  const [config, setConfig] = useState<ProjectConfig | null>(null);
  const [sections, setSections] = useState<SpecSection[]>([]);
  const [decisions, setDecisions] = useState<DecisionCard[]>([]);
  const [messages, setMessages] = useState<NodeMessage[]>([]);
  const [criteriaMarkdown, setCriteriaMarkdown] = useState<string>('');
  const [gapReview, setGapReview] = useState<string>('');

  // Checklist States
  const [tasks, setTasks] = useState<TaskItem[]>([]);
  const [isGeneratingTasks, setIsGeneratingTasks] = useState(false);

  // UI States
  const [activeTab, setActiveTab] = useState<'spec' | 'devloop' | 'preview' | 'timeline' | 'gaps' | 'diagnostics'>('spec');
  const [previewUrl, setPreviewUrl] = useState('http://localhost:3000');
  const [devLoopExplanation, setDevLoopExplanation] = useState<string | null>(null);


  const [chatMessage, setChatMessage] = useState('');
  const [isSending, setIsSending] = useState(false);
  const [isInitializing, setIsInitializing] = useState(false);
  const [isAuditing, setIsAuditing] = useState(false);
  const [errorToast, setErrorToast] = useState<{ message: string; type: string } | null>(null);
  
  // Intake Wizard States
  const [intakeProjectName, setIntakeProjectName] = useState('');
  const [intakeDesc, setIntakeDesc] = useState('');
  const [intakeLevel, setIntakeLevel] = useState<'supervised' | 'interactive' | 'autopilot'>('supervised');
  const [intakeGoldenRules, setIntakeGoldenRules] = useState<GoldenRules>({
    frontend: 'React, Vite, Vanilla CSS',
    backend: 'Node.js Express, TypeScript',
    database: 'SQLite',
    additional: 'RESTful API structure, zero Docker dependencies'
  });
  const [intakeProvider, setIntakeProvider] = useState('gemini');
  const [intakeModel, setIntakeModel] = useState('');

  // Concept Divergence & Proposal states
  const [proposals, setProposals] = useState<IntakeProposals | null>(null);
  const [selectedOption, setSelectedOption] = useState<'A' | 'B' | 'C' | null>(null);
  const [userAdjustments, setUserAdjustments] = useState('');
  const [regenerationFeedback, setRegenerationFeedback] = useState('');

  // Settings Modal States
  const [showSettings, setShowSettings] = useState(false);
  const [settingsTab, setSettingsTab] = useState<'global' | 'agents' | 'devloop'>('global');
  const [formConfig, setFormConfig] = useState<ProjectConfig | null>(null);

  // DevLoop Console Logs
  const [consoleLogs, setConsoleLogs] = useState<{ type: string; text: string }[]>([]);
  const [activeDevCommand, setActiveDevCommand] = useState<string | null>(null);

  // Editing Section State
  const [editingSectionId, setEditingSectionId] = useState<string | null>(null);
  const [editingContent, setEditingContent] = useState('');

  // Routing and SSE stream states
  const [routingStatus, setRoutingStatus] = useState<{ isRouting: boolean; route?: string; reasoning?: string }>({ isRouting: false });
  const [isMockupUpdating, setIsMockupUpdating] = useState(false);
  const [harnessStatus, setHarnessStatus] = useState<string | null>(null);
  const [validationErrors, setValidationErrors] = useState<string[] | null>(null);
  const [lastRejectedSpec, setLastRejectedSpec] = useState<{ sectionId: string; title?: string; content: string } | null>(null);
  const [iframeKey, setIframeKey] = useState(0);
  const activeEventSourceRef = useRef<EventSource | null>(null);
  const logsEndRef = useRef<HTMLDivElement | null>(null);
  const chatEndRef = useRef<HTMLDivElement | null>(null);

  // Diagnostics Report States
  const [diagnosticsReport, setDiagnosticsReport] = useState<any[] | null>(null);
  const [isDiagnosing, setIsDiagnosing] = useState(false);

  const fetchDiagnostics = async () => {
    try {
      const res = await fetch('/api/diagnostics');
      if (res.ok) {
        setDiagnosticsReport(await res.json());
      }
    } catch (e) {
      console.warn('Failed to pre-fetch diagnostics:', e);
    }
  };

  const handleRunDiagnostics = async () => {
    setIsDiagnosing(true);
    try {
      const res = await fetch('/api/diagnostics');
      if (res.ok) {
        setDiagnosticsReport(await res.json());
        showToast(lang === 'ko' ? '로컬 AI CLI 자가진단이 완료되었습니다.' : 'Local AI CLI Diagnostics completed.', 'success');
      } else {
        showToast(lang === 'ko' ? '자가진단 실행에 실패했습니다.' : 'Failed to run diagnostics.', 'error');
      }
    } catch (e) {
      showToast(lang === 'ko' ? '자가진단 오류 발생' : 'Error executing diagnostics.', 'error');
    } finally {
      setIsDiagnosing(false);
    }
  };


  // Initialize mermaid on mount
  useEffect(() => {
    mermaid.initialize({
      startOnLoad: false,
      theme: 'dark',
      securityLevel: 'loose',
    });
  }, []);

  // Run mermaid rendering after state updates
  useEffect(() => {
    const timer = setTimeout(() => {
      mermaid.run().catch(err => console.warn('Mermaid rendering error:', err));
    }, 150);
    return () => clearTimeout(timer);
  }, [sections, activeTab, criteriaMarkdown, gapReview, editingSectionId]);

  // Markdown rendering helper
  const renderMarkdown = (content: string) => {
    try {
      return { __html: String(marked.parse(content || '')) };
    } catch (e) {
      return { __html: content || '' };
    }
  };

  // 1. Initial Load
  useEffect(() => {
    fetchProjectData();
  }, []);

  // Auto-scroll dev console
  useEffect(() => {
    logsEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [consoleLogs]);

  // Auto-scroll chat
  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const fetchProjectData = async () => {
    try {
      const resConfig = await fetch('/api/project/config');
      if (resConfig.ok) {
        const configData = await resConfig.json();
        setConfig(configData);
        setFormConfig(configData);
        
        // Sync intake wizard settings
        if (configData.settings) {
          if (configData.settings.provider) setIntakeProvider(configData.settings.provider);
          if (configData.settings.model !== undefined) setIntakeModel(configData.settings.model);
        }
        if (configData.goldenRules) {
          setIntakeGoldenRules(configData.goldenRules);
        }
        if (configData.automationLevel) {
          setIntakeLevel(configData.automationLevel);
        }
        if (configData.proposals) {
          setProposals(configData.proposals);
        }
        if (configData.selectedOptionKey) {
          setSelectedOption(configData.selectedOptionKey);
        }
        if (configData.projectName) {
          setIntakeProjectName(configData.projectName);
        }
        if (configData.projectDesc) {
          setIntakeDesc(configData.projectDesc);
        }
        
        if (configData.projectName) {
          // Fetch specs, decisions, criteria, messages, tasks
          const [resSpecs, resDecs, resCriteria, resMessages, resTasks] = await Promise.all([
            fetch('/api/specs'),
            fetch('/api/decisions'),
            fetch('/api/criteria'),
            fetch('/api/messages'),
            fetch('/api/tasks')
          ]);

          if (resSpecs.ok) setSections(await resSpecs.json());
          if (resDecs.ok) setDecisions(await resDecs.json());
          if (resCriteria.ok) {
            const data = await resCriteria.json();
            setCriteriaMarkdown(data.markdown);
          }
          if (resMessages.ok) setMessages(await resMessages.json());
          if (resTasks.ok) {
            const data = await resTasks.json();
            setTasks(data.parsed || []);
          }

          // Trigger compilation
          compileSpecs();
          fetchDiagnostics();
        }
      }
    } catch (e) {
      showToast(t.toastErrorLoading, 'error');
    }
  };

  const showToast = (message: string, type: string = 'info') => {
    setErrorToast({ message, type });
    setTimeout(() => setErrorToast(null), 5000);
  };

  const compileSpecs = async () => {
    try {
      await fetch('/api/specs/compile', { method: 'POST' });
    } catch (e) {
      console.error('Failed to compile specs', e);
    }
  };

  // File Import handler
  const handleFileImport = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const isText = file.name.endsWith('.md') || file.name.endsWith('.txt') || file.type.startsWith('text/');
    if (!isText) {
      showToast(t.toastPrdTypeWarning, 'warning');
      return;
    }

    const reader = new FileReader();
    reader.onload = (event) => {
      const text = event.target?.result;
      if (typeof text === 'string') {
        setIntakeDesc(text);
        showToast(t.toastPrdLoaded, 'success');
      }
    };
    reader.onerror = () => {
      showToast(t.toastPrdLoadFailed, 'error');
    };
    reader.readAsText(file);
  };

  // 2. Intake Propose Options
  const handleIntakeSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!intakeProjectName.trim() || !intakeDesc.trim()) {
      return showToast('Project Name and Rough Idea are required', 'warning');
    }
    setIsInitializing(true);
    try {
      const res = await fetch('/api/project/intake/propose', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          projectName: intakeProjectName,
          projectDesc: intakeDesc,
          automationLevel: intakeLevel,
          goldenRules: intakeGoldenRules,
          provider: intakeProvider,
          model: intakeModel
        })
      });

      if (!res.ok) throw new Error('Failed to generate proposals');
      const data = await res.json();
      setConfig(data.config);
      setFormConfig(data.config);
      setProposals(data.proposals);
      // Reset selected option on new idea submit
      setSelectedOption(null);
      setUserAdjustments('');
      setRegenerationFeedback('');
      showToast(t.toastProposalsGenerated, 'success');
    } catch (e: any) {
      showToast(`Initialization failed: ${e.message}`, 'error');
    } finally {
      setIsInitializing(false);
    }
  };

  // 2.5. Regenerate Proposals with Feedback
  const handleRegenerateProposals = async () => {
    if (!regenerationFeedback.trim()) {
      return showToast('Please enter feedback to regenerate drafts', 'warning');
    }
    setIsInitializing(true);
    try {
      const res = await fetch('/api/project/intake/propose', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          projectName: intakeProjectName,
          projectDesc: intakeDesc,
          automationLevel: intakeLevel,
          goldenRules: intakeGoldenRules,
          provider: intakeProvider,
          model: intakeModel,
          feedback: regenerationFeedback
        })
      });

      if (!res.ok) throw new Error('Regeneration failed');
      const data = await res.json();
      setConfig(data.config);
      setFormConfig(data.config);
      setProposals(data.proposals);
      setSelectedOption(null);
      setRegenerationFeedback('');
      showToast(t.toastProposalsGenerated, 'success');
    } catch (e: any) {
      showToast(`Regeneration failed: ${e.message}`, 'error');
    } finally {
      setIsInitializing(false);
    }
  };

  // 2.8. Confirm Selection and Sprout Specifications
  const handleSelectOptionSubmit = async () => {
    if (!selectedOption) {
      return showToast('Please select one of the three options', 'warning');
    }
    setIsInitializing(true);
    try {
      const res = await fetch('/api/project/intake/select', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          selectedOptionKey: selectedOption,
          userAdjustments
        })
      });

      if (!res.ok) throw new Error('Failed to sprout specifications');
      const data = await res.json();
      setConfig(data.config);
      setFormConfig(data.config);
      setSections(data.sections || []);
      setDecisions(data.decisions || []);
      setMessages([]);
      setCriteriaMarkdown('');
      compileSpecs();
      showToast(t.toastSprouted, 'success');
    } catch (e: any) {
      showToast(`Sprouting failed: ${e.message}`, 'error');
    } finally {
      setIsInitializing(false);
    }
  };

  // 3. Resolve Decision Card
  const handleResolveDecision = async (cardId: string, optionName: string, reason: string = '') => {
    try {
      const res = await fetch('/api/decisions/resolve', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ cardId, approvedOptionName: optionName, reason })
      });
      if (res.ok) {
        showToast(`${t.toastDecisionResolved}${optionName}`, 'success');
        fetchProjectData();
      }
    } catch (e) {
      showToast('Failed to resolve decision', 'error');
    }
  };

  // 4. Edit Spec Section
  const handleStartEditing = (section: SpecSection) => {
    if (config?.phase === 'development') {
      return showToast(t.toastSpecLockedWarning, 'warning');
    }
    setEditingSectionId(section.id);
    setEditingContent(section.content);
  };

  // 4.5. 기획 하네스 예외 수동 강제 승인 (Force Commit / HITL)
  const handleForceCommit = async () => {
    if (!lastRejectedSpec) return;
    try {
      const res = await fetch('/api/specs/edit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          id: lastRejectedSpec.sectionId,
          title: lastRejectedSpec.title || 'Untitled Section',
          content: lastRejectedSpec.content
        })
      });
      if (res.ok) {
        showToast('기획안이 하네스 예외로 강제 반영되었습니다.', 'success');
        setValidationErrors(null);
        setLastRejectedSpec(null);
        fetchProjectData();
      }
    } catch (e) {
      showToast('수동 강제 반영에 실패했습니다.', 'error');
    }
  };

  const handleSaveEdit = async (sectionId: string) => {
    try {
      const section = sections.find(s => s.id === sectionId);
      if (!section) return;

      const res = await fetch('/api/specs/edit', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          id: sectionId,
          title: section.title,
          content: editingContent,
          status: section.status
        })
      });
      if (res.ok) {
        showToast(t.toastSectionUpdated, 'success');
        setEditingSectionId(null);
        fetchProjectData();
      }
    } catch (e) {
      showToast('Failed to update section', 'error');
    }
  };

  // 5. Phase Lock Toggle
  const togglePhaseLock = async () => {
    if (!config) return;
    const nextPhase = config.phase === 'planning' ? 'development' : 'planning';
    try {
      const res = await fetch('/api/project/phase', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ phase: nextPhase })
      });
      if (res.ok) {
        const data = await res.json();
        setConfig(data.config);
        setFormConfig(data.config);
        showToast(
          nextPhase === 'development'
            ? t.toastLocked
            : t.toastUnlocked,
          'success'
        );
        if (data.tasksGenerated) {
          showToast(t.toastTasksGenerated, 'success');
        }
        fetchProjectData();
      }
    } catch (e) {
      showToast('Failed to change phase lock', 'error');
    }
  };

  // Toggle checklist task status
  const handleToggleTask = async (index: number, currentStatus: 'todo' | 'in_progress' | 'done') => {
    let nextStatus = 'todo';
    if (currentStatus === 'todo') nextStatus = 'in_progress';
    else if (currentStatus === 'in_progress') nextStatus = 'done';
    
    try {
      const res = await fetch('/api/tasks/toggle', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ index, status: nextStatus })
      });
      if (res.ok) {
        const data = await res.json();
        setTasks(data.parsed || []);
        showToast(t.toastTaskUpdated, 'success');
      }
    } catch (e) {
      showToast('Failed to update task status', 'error');
    }
  };

  // Generate / Regenerate checklist tasks manually
  const handleGenerateTasks = async () => {
    setIsGeneratingTasks(true);
    try {
      const res = await fetch('/api/tasks/generate', { method: 'POST' });
      if (res.ok) {
        const data = await res.json();
        setTasks(data.parsed || []);
        showToast(t.toastTasksGenerated, 'success');
      }
    } catch (e) {
      showToast('Failed to generate tasks', 'error');
    } finally {
      setIsGeneratingTasks(false);
    }
  };

  // 6. Run Gap Auditor
  const runGapAuditor = async () => {
    setIsAuditing(true);
    setActiveTab('gaps');
    try {
      const res = await fetch('/api/project/gap-check');
      if (res.ok) {
        const data = await res.json();
        setGapReview(data.review);
        showToast(t.toastGapCompleted, 'success');
      }
    } catch (e) {
      showToast(t.toastGapFailed, 'error');
    } finally {
      setIsAuditing(false);
    }
  };

  // 7. Chat Streaming (SSE)
  const handleSendMessage = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!chatMessage.trim() || isSending || config?.phase === 'development') return;

    setIsSending(true);
    setRoutingStatus({ isRouting: true });

    const messageText = chatMessage;
    setChatMessage('');

    // Optimistically update messages locally
    const localUserMsg: NodeMessage = {
      id: crypto.randomUUID(),
      author: 'user',
      content: messageText,
      createdAt: new Date().toISOString()
    };
    setMessages(prev => [...prev, localUserMsg]);

    const url = `/api/chat/stream?message=${encodeURIComponent(messageText)}`;

    if (activeEventSourceRef.current) {
      activeEventSourceRef.current.close();
    }

    const eventSource = new EventSource(url);
    activeEventSourceRef.current = eventSource;

    let incomingProse = '';
    let currentAgent: any = null;

    eventSource.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);

        if (data.type === 'routing') {
          setRoutingStatus({
            isRouting: false,
            route: data.route,
            reasoning: data.reasoning
          });
          currentAgent = data.route;
        } else if (data.type === 'status') {
          setHarnessStatus(data.chunk || null);
        } else if (data.type === 'mockup_updating') {
          setIsMockupUpdating(true);
        } else if (data.type === 'content') {
          setRoutingStatus(prev => ({ ...prev, isRouting: false }));
          incomingProse += data.chunk || '';
          
          setMessages(prev => {
            const filtered = prev.filter(m => m.id !== 'incoming-stream');
            return [
              ...filtered,
              {
                id: 'incoming-stream',
                author: currentAgent || 'director',
                content: incomingProse,
                createdAt: new Date().toISOString()
              }
            ];
          });
        } else if (data.type === 'done') {
          eventSource.close();
          setIsSending(false);
          setRoutingStatus({ isRouting: false });
          setIsMockupUpdating(false);
          setHarnessStatus(null);
          
          if (data.validationErrors && data.specUpdate) {
            setValidationErrors(data.validationErrors);
            setLastRejectedSpec(data.specUpdate);
          } else {
            setValidationErrors(null);
            setLastRejectedSpec(null);
          }
          
          setIframeKey(prev => prev + 1);
          fetchProjectData(); // Reload full states (spec, features, messages)
        } else if (data.type === 'error') {
          eventSource.close();
          setIsSending(false);
          setRoutingStatus({ isRouting: false });
          setIsMockupUpdating(false);
          setHarnessStatus(null);
          showToast(`Agent error: ${data.error}`, 'error');
        }
      } catch (e) {
        console.error('Error parsing stream event', e);
      }
    };

    eventSource.onerror = () => {
      eventSource.close();
      setIsSending(false);
      setRoutingStatus({ isRouting: false });
      setIsMockupUpdating(false);
      showToast('SSE connection closed or lost', 'error');
    };
  };

  // 8. Run DevLoop command
  const runDevCommand = (kind: 'build' | 'launch' | 'verify') => {
    setConsoleLogs([]);
    setDevLoopExplanation(null);
    setActiveDevCommand(kind);
    setActiveTab('devloop');

    const url = `/api/devloop/run?kind=${kind}`;
    const eventSource = new EventSource(url);

    eventSource.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === 'start') {
          setConsoleLogs(prev => [...prev, { type: 'info', text: `$ Running: ${data.command}` }]);
        } else if (data.type === 'stdout') {
          setConsoleLogs(prev => [...prev, { type: 'stdout', text: data.chunk }]);
        } else if (data.type === 'stderr') {
          setConsoleLogs(prev => [...prev, { type: 'stderr', text: data.chunk }]);
        } else if (data.type === 'explanation') {
          setDevLoopExplanation(data.text);
        } else if (data.type === 'exit') {
          setConsoleLogs(prev => [...prev, { type: 'info', text: `\nProcess completed with exit code: ${data.code}` }]);
          eventSource.close();
          setActiveDevCommand(null);
        } else if (data.type === 'error') {
          setConsoleLogs(prev => [...prev, { type: 'error', text: `\nError: ${data.error}` }]);
          eventSource.close();
          setActiveDevCommand(null);
        }
      } catch (e) {
        console.error('Error parsing devloop stream', e);
      }
    };

    eventSource.onerror = () => {
      eventSource.close();
      setActiveDevCommand(null);
    };
  };

  // 9. Save Settings
  const saveSettings = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!formConfig) return;
    try {
      const res = await fetch('/api/project/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formConfig)
      });
      if (res.ok) {
        showToast('Settings saved successfully', 'success');
        setShowSettings(false);
        fetchProjectData();
      }
    } catch (e) {
      showToast('Failed to save settings', 'error');
    }
  };

  // Render Settings Modal Helper
  const renderSettingsModal = () => {
    if (!showSettings || !formConfig) return null;
    return (
      <div className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 flex flex-col items-center justify-start md:justify-center p-4 md:p-8 overflow-y-auto">
        <form onSubmit={saveSettings} className="bg-slate-900 border border-slate-800 rounded-3xl p-6 max-w-xl w-full shadow-2xl relative my-auto text-xs">
          <button
            type="button"
            onClick={() => setShowSettings(false)}
            className="absolute top-4 right-4 p-1.5 bg-slate-950 border border-slate-855 hover:bg-slate-800 rounded-lg text-slate-400 hover:text-slate-200"
          >
            <X className="w-4 h-4" />
          </button>

          {/* Modal Heading */}
          <div className="flex items-center gap-2.5 mb-5">
            <Settings className="w-5 h-5 text-violet-400" />
            <h2 className="text-base font-bold text-slate-100">{t.projectConfigTitle}</h2>
          </div>

          {/* Tab selection */}
          <div className="flex gap-2 border-b border-slate-850 mb-4 text-xs font-semibold">
            {[
              { id: 'global', label: t.globalPresetsTab },
              { id: 'agents', label: t.agentConfigTab },
              { id: 'devloop', label: t.devloopCommandsTab }
            ].map(tabOpt => (
              <button
                key={tabOpt.id}
                type="button"
                onClick={() => setSettingsTab(tabOpt.id as any)}
                className={`pb-2 px-1 border-b-2 transition-all ${
                  settingsTab === tabOpt.id
                    ? 'border-violet-500 text-slate-200'
                    : 'border-transparent text-slate-500 hover:text-slate-350'
                }`}
              >
                {tabOpt.label}
              </button>
            ))}
          </div>

          <div className="space-y-4 max-h-[350px] overflow-y-auto pr-1">
            {/* Tab Content: Global Settings */}
            {settingsTab === 'global' && (
              <div className="space-y-3.5 text-xs">
                <div>
                  <label className="block font-semibold text-slate-400 mb-1">{t.globalProviderLabel}</label>
                  <select
                    value={formConfig.settings.provider}
                    onChange={e => setFormConfig(prev => ({
                      ...prev!,
                      settings: { ...prev!.settings, provider: e.target.value }
                    }))}
                    className="w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-slate-300 focus:outline-none focus:border-violet-500"
                  >
                    <option value="gemini">Gemini CLI</option>
                    <option value="claude">Claude CLI</option>
                    <option value="codex">Codex CLI</option>
                    <option value="agy">Antigravity CLI (agy)</option>
                    <option value="cursor">Cursor Agent CLI (cursor)</option>
                  </select>
                </div>

                <div>
                  <label className="block font-semibold text-slate-400 mb-1">{t.modelOverrideLabel}</label>
                  <input
                    type="text"
                    value={formConfig.settings.model}
                    onChange={e => setFormConfig(prev => ({
                      ...prev!,
                      settings: { ...prev!.settings, model: e.target.value }
                    }))}
                    placeholder="e.g. gemini-1.5-pro"
                    className="w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-slate-300 placeholder-slate-650 focus:outline-none"
                  />
                </div>

                <div className="border-t border-slate-850 pt-3">
                  <label className="block font-semibold text-slate-300 mb-2">{t.goldenRulesTitle}</label>
                  <div className="grid grid-cols-2 gap-3">
                    <div>
                      <label className="block text-[10px] text-slate-500 uppercase font-bold mb-1">{t.frontendLabel}</label>
                      <input
                        type="text"
                        value={formConfig.goldenRules.frontend}
                        onChange={e => setFormConfig(prev => ({
                          ...prev!,
                          goldenRules: { ...prev!.goldenRules, frontend: e.target.value }
                        }))}
                        className="w-full bg-slate-950 border border-slate-855 rounded-lg px-2.5 py-1.5 text-slate-300 text-xs"
                      />
                    </div>
                    <div>
                      <label className="block text-[10px] text-slate-500 uppercase font-bold mb-1">{t.backendLabel}</label>
                      <input
                        type="text"
                        value={formConfig.goldenRules.backend}
                        onChange={e => setFormConfig(prev => ({
                          ...prev!,
                          goldenRules: { ...prev!.goldenRules, backend: e.target.value }
                        }))}
                        className="w-full bg-slate-950 border border-slate-855 rounded-lg px-2.5 py-1.5 text-slate-300 text-xs"
                      />
                    </div>
                    <div>
                      <label className="block text-[10px] text-slate-500 uppercase font-bold mb-1">{t.databaseLabel}</label>
                      <input
                        type="text"
                        value={formConfig.goldenRules.database}
                        onChange={e => setFormConfig(prev => ({
                          ...prev!,
                          goldenRules: { ...prev!.goldenRules, database: e.target.value }
                        }))}
                        className="w-full bg-slate-950 border border-slate-855 rounded-lg px-2.5 py-1.5 text-slate-300 text-xs"
                      />
                    </div>
                    <div>
                      <label className="block text-[10px] text-slate-500 uppercase font-bold mb-1">{t.additionalLabel}</label>
                      <input
                        type="text"
                        value={formConfig.goldenRules.additional}
                        onChange={e => setFormConfig(prev => ({
                          ...prev!,
                          goldenRules: { ...prev!.goldenRules, additional: e.target.value }
                        }))}
                        className="w-full bg-slate-950 border border-slate-855 rounded-lg px-2.5 py-1.5 text-slate-300 text-xs"
                      />
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* Tab Content: Agent Customization */}
            {settingsTab === 'agents' && (
              <div className="space-y-3 text-xs">
                {Object.keys(formConfig.settings.agents).map(roleKey => {
                  const typedKey = roleKey as keyof typeof formConfig.settings.agents;
                  return (
                    <div key={roleKey} className="flex items-center justify-between border-b border-slate-850 pb-2.5">
                      <span className="font-bold text-slate-300 capitalize">{roleKey} {t.agentRoleLabel}</span>
                      <div className="flex gap-2">
                        <select
                          value={formConfig.settings.agents[typedKey].provider}
                          onChange={e => setFormConfig(prev => {
                            const agents = { ...prev!.settings.agents };
                            agents[typedKey] = { ...agents[typedKey], provider: e.target.value };
                            return { ...prev!, settings: { ...prev!.settings, agents } };
                          })}
                          className="bg-slate-950 border border-slate-800 rounded px-2 py-1 text-slate-300"
                        >
                          <option value="gemini">Gemini</option>
                          <option value="claude">Claude</option>
                          <option value="codex">Codex</option>
                          <option value="agy">Antigravity (agy)</option>
                          <option value="cursor">Cursor Agent</option>
                        </select>
                        <input
                          type="text"
                          value={formConfig.settings.agents[typedKey].model}
                          onChange={e => setFormConfig(prev => {
                            const agents = { ...prev!.settings.agents };
                            agents[typedKey] = { ...agents[typedKey], model: e.target.value };
                            return { ...prev!, settings: { ...prev!.settings, agents } };
                          })}
                          placeholder={t.defaultModelPlaceholder}
                          className="bg-slate-950 border border-slate-800 rounded px-2 py-1 text-slate-300 w-32 placeholder-slate-650"
                        />
                      </div>
                    </div>
                  );
                })}
              </div>
            )}

            {/* Tab Content: DevLoop commands */}
            {settingsTab === 'devloop' && (
              <div className="space-y-3 text-xs">
                <div>
                  <label className="block font-semibold text-slate-400 mb-1">{t.buildCommandLabel}</label>
                  <input
                    type="text"
                    value={formConfig.developerLoop.buildCommand}
                    onChange={e => setFormConfig(prev => ({
                      ...prev!,
                      developerLoop: { ...prev!.developerLoop, buildCommand: e.target.value }
                    }))}
                    className="w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-slate-300 text-xs"
                  />
                </div>
                <div>
                  <label className="block font-semibold text-slate-400 mb-1">{t.verifyCommandLabel}</label>
                  <input
                    type="text"
                    value={formConfig.developerLoop.verifyCommand}
                    onChange={e => setFormConfig(prev => ({
                      ...prev!,
                      developerLoop: { ...prev!.developerLoop, verifyCommand: e.target.value }
                    }))}
                    className="w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-slate-300 text-xs"
                  />
                </div>
                <div>
                  <label className="block font-semibold text-slate-400 mb-1">{t.launchCommandLabel}</label>
                  <input
                    type="text"
                    value={formConfig.developerLoop.launchCommand}
                    onChange={e => setFormConfig(prev => ({
                      ...prev!,
                      developerLoop: { ...prev!.developerLoop, launchCommand: e.target.value }
                    }))}
                    className="w-full bg-slate-950 border border-slate-800 rounded-lg px-3 py-2 text-slate-300 text-xs"
                  />
                </div>
              </div>
            )}
          </div>

          {/* Actions */}
          <div className="flex justify-end gap-2 border-t border-slate-850 pt-4 mt-5 text-xs">
            <button
              type="button"
              onClick={() => setShowSettings(false)}
              className="px-4 py-2 bg-slate-950 border border-slate-800 hover:bg-slate-850 rounded-xl font-bold text-slate-450"
            >
              {t.closeBtn}
            </button>
            <button
              type="submit"
              className="px-4 py-2 bg-violet-600 hover:bg-violet-500 rounded-xl text-white font-bold"
            >
              {t.saveConfigBtn}
            </button>
          </div>
        </form>
      </div>
    );
  };

  // Render Loader screen during initialization
  if (isInitializing) {
    const isSproutingSpec = config && config.onboardingStep === 3;
    const title = isSproutingSpec ? t.loadingSpecs : t.loadingProposals;
    const desc = isSproutingSpec ? t.loadingSpecsDesc : t.loadingProposalsDesc;
    return (
      <div className="h-screen w-full bg-slate-950 flex flex-col items-center justify-start md:justify-center p-4 md:p-8 overflow-y-auto">
        <div className="bg-slate-900/60 backdrop-blur-xl border border-slate-800 p-8 rounded-2xl max-w-md w-full text-center shadow-2xl relative overflow-hidden my-auto shrink-0">
          <div className="absolute inset-0 bg-gradient-to-tr from-violet-500/10 via-transparent to-emerald-500/10 animate-pulse pointer-events-none" />
          <Loader2 className="w-12 h-12 text-violet-500 animate-spin mx-auto mb-6" />
          <h2 className="text-xl font-bold text-slate-200 mb-2">{title}</h2>
          <p className="text-sm text-slate-400">{desc}</p>
        </div>
      </div>
    );
  }

  // Render Intake Wizard if no active project config exists
  if (!config || !config.sprouted) {
    return (
      <div className="min-h-screen w-full bg-slate-950 flex flex-col items-center justify-start p-4 md:p-8 overflow-y-auto relative">
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_80%_at_50%_-20%,rgba(120,119,198,0.25),rgba(255,255,255,0))]" />
        
        {/* Language switcher & Settings on top right */}
        <div className="absolute top-4 right-4 z-10 flex gap-2">
          <button
            type="button"
            onClick={() => setShowSettings(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-900/80 border border-slate-800 hover:bg-slate-800 rounded-xl text-xs font-bold text-slate-350 transition-colors"
          >
            <Settings className="w-3.5 h-3.5" />
            {lang === 'ko' ? '환경설정' : 'Settings'}
          </button>
          <button
            type="button"
            onClick={() => setLang(lang === 'ko' ? 'en' : 'ko')}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-900/80 border border-slate-800 hover:bg-slate-800 rounded-xl text-xs font-bold text-slate-350 transition-colors"
          >
            <Globe className="w-3.5 h-3.5" />
            {lang === 'ko' ? 'English' : '한국어'}
          </button>
        </div>

        {/* Step Progress Bar */}
        <div className="w-full max-w-4xl mt-12 mb-8 relative z-10">
          <div className="flex items-center justify-between text-[11px] text-slate-500 font-bold mb-2 uppercase tracking-wider">
            <span>
              {t.stepIndicator
                .replace('{step}', proposals ? '2' : '1')
                .replace('{title}', proposals ? (lang === 'ko' ? '접근안 결정 및 피드백' : 'Concept Selection & Adjustments') : (lang === 'ko' ? '요구사항 입력' : 'Idea & Constraints'))}
            </span>
            <span className="text-violet-400">{proposals ? 'Step 2 of 3' : 'Step 1 of 3'}</span>
          </div>
          <div className="w-full bg-slate-900 h-1.5 rounded-full overflow-hidden border border-slate-850">
            <div 
              className="bg-gradient-to-r from-violet-500 via-violet-650 to-emerald-500 h-full transition-all duration-500" 
              style={{ width: proposals ? '66%' : '33%' }}
            />
          </div>
        </div>

        {!proposals ? (
          /* STEP 1: Intake input form */
          <form onSubmit={handleIntakeSubmit} className="relative bg-slate-900/60 backdrop-blur-xl border border-slate-800 rounded-3xl p-8 max-w-2xl w-full shadow-2xl overflow-hidden my-auto shrink-0">
            <div className="absolute top-0 right-0 w-64 h-64 bg-violet-600/10 rounded-full blur-3xl pointer-events-none" />
            <div className="absolute bottom-0 left-0 w-64 h-64 bg-emerald-600/10 rounded-full blur-3xl pointer-events-none" />

            {/* Heading */}
            <div className="flex items-center gap-3 mb-6">
              <div className="p-3 bg-violet-500/10 border border-violet-500/20 rounded-2xl">
                <Brain className="w-8 h-8 text-violet-400" />
              </div>
              <div>
                <h1 className="text-2xl font-black text-slate-100 tracking-tight">{t.launchProject}</h1>
                <p className="text-sm text-slate-400">{t.launchDesc}</p>
              </div>
            </div>

            <div className="space-y-5">
              {/* Project Name */}
              <div>
                <label className="block text-xs font-semibold uppercase tracking-wider text-slate-400 mb-2">{t.projectNameLabel}</label>
                <input
                  id="project-name-input"
                  type="text"
                  placeholder={t.projectNamePlaceholder}
                  value={intakeProjectName}
                  onChange={e => setIntakeProjectName(e.target.value)}
                  className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-3 text-slate-100 placeholder-slate-600 focus:outline-none focus:border-violet-500 transition-colors"
                  required
                />
              </div>

              {/* Rough Idea */}
              <div>
                <div className="flex items-center justify-between mb-2">
                  <label className="block text-xs font-semibold uppercase tracking-wider text-slate-400">{t.roughIdeaLabel}</label>
                  <div className="flex items-center">
                    <input
                      type="file"
                      id="prd-file-upload"
                      accept=".md,.txt"
                      className="hidden"
                      onChange={handleFileImport}
                    />
                    <label
                      htmlFor="prd-file-upload"
                      className="cursor-pointer flex items-center gap-1 px-2.5 py-1 bg-slate-900 border border-slate-800 hover:bg-slate-800 rounded-lg text-[9px] font-bold text-violet-400 hover:text-violet-300 transition-colors"
                    >
                      <FileText className="w-3 h-3" />
                      {t.importPrdBtn}
                    </label>
                  </div>
                </div>
                <textarea
                  id="project-desc-input"
                  placeholder={t.roughIdeaPlaceholder}
                  value={intakeDesc}
                  onChange={e => setIntakeDesc(e.target.value)}
                  rows={4}
                  className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-3 text-slate-100 placeholder-slate-600 focus:outline-none focus:border-violet-500 transition-colors resize-none"
                  required
                />
              </div>

              {/* Golden Rules Config */}
              <div className="bg-slate-950/50 border border-slate-800/80 rounded-2xl p-4">
                <span className="block text-xs font-semibold uppercase tracking-wider text-slate-300 mb-3 flex items-center gap-1.5">
                  <Sparkles className="w-3.5 h-3.5 text-violet-400" />
                  {t.goldenRulesTitle}
                </span>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-[10px] uppercase font-bold text-slate-500 mb-1">{t.frontendLabel}</label>
                    <input
                      type="text"
                      value={intakeGoldenRules.frontend}
                      onChange={e => setIntakeGoldenRules(prev => ({ ...prev, frontend: e.target.value }))}
                      className="w-full bg-slate-950 border border-slate-850 rounded-lg px-2.5 py-1.5 text-xs text-slate-300 focus:outline-none focus:border-violet-500"
                    />
                  </div>
                  <div>
                    <label className="block text-[10px] uppercase font-bold text-slate-500 mb-1">{t.backendLabel}</label>
                    <input
                      type="text"
                      value={intakeGoldenRules.backend}
                      onChange={e => setIntakeGoldenRules(prev => ({ ...prev, backend: e.target.value }))}
                      className="w-full bg-slate-950 border border-slate-850 rounded-lg px-2.5 py-1.5 text-xs text-slate-300 focus:outline-none focus:border-violet-500"
                    />
                  </div>
                  <div>
                    <label className="block text-[10px] uppercase font-bold text-slate-500 mb-1">{t.databaseLabel}</label>
                    <input
                      type="text"
                      value={intakeGoldenRules.database}
                      onChange={e => setIntakeGoldenRules(prev => ({ ...prev, database: e.target.value }))}
                      className="w-full bg-slate-950 border border-slate-850 rounded-lg px-2.5 py-1.5 text-xs text-slate-300 focus:outline-none focus:border-violet-500"
                    />
                  </div>
                  <div>
                    <label className="block text-[10px] uppercase font-bold text-slate-500 mb-1">{t.additionalLabel}</label>
                    <input
                      type="text"
                      value={intakeGoldenRules.additional}
                      onChange={e => setIntakeGoldenRules(prev => ({ ...prev, additional: e.target.value }))}
                      className="w-full bg-slate-950 border border-slate-850 rounded-lg px-2.5 py-1.5 text-xs text-slate-300 focus:outline-none focus:border-violet-500"
                    />
                  </div>
                </div>
              </div>

              {/* Automation Level Selection */}
              <div>
                <label className="block text-xs font-semibold uppercase tracking-wider text-slate-400 mb-2">{t.automationLevelLabel}</label>
                <div className="grid grid-cols-3 gap-3">
                  {[
                    { value: 'supervised', label: t.supervisedLabel, desc: t.supervisedDesc },
                    { value: 'interactive', label: t.interactiveLabel, desc: t.interactiveDesc },
                    { value: 'autopilot', label: t.autopilotLabel, desc: t.autopilotDesc }
                  ].map(opt => (
                    <button
                      key={opt.value}
                      type="button"
                      onClick={() => setIntakeLevel(opt.value as any)}
                      className={`border p-3.5 rounded-xl text-left transition-all ${
                        intakeLevel === opt.value
                          ? 'border-violet-500 bg-violet-500/5'
                          : 'border-slate-800 bg-slate-950 hover:bg-slate-900/40'
                      }`}
                    >
                      <span className={`block text-xs font-bold ${intakeLevel === opt.value ? 'text-violet-400' : 'text-slate-300'}`}>
                        {opt.label}
                      </span>
                      <span className="block text-[10px] text-slate-500 mt-1">{opt.desc}</span>
                    </button>
                  ))}
                </div>
              </div>
            </div>

            <button
              id="sprout-submit-btn"
              type="submit"
              className="w-full bg-violet-600 hover:bg-violet-500 text-white font-bold py-3.5 px-6 rounded-xl mt-6 transition-colors flex items-center justify-center gap-2 shadow-lg shadow-violet-600/20"
            >
              <Sparkles className="w-4 h-4 animate-pulse" />
              {t.sproutSpecsBtn}
            </button>
          </form>
        ) : (
          /* STEP 2: Proposals display card deck & adjustments */
          <div className="relative bg-slate-900/60 backdrop-blur-xl border border-slate-800 rounded-3xl p-8 max-w-6xl w-full shadow-2xl overflow-hidden my-auto shrink-0">
            <div className="absolute top-0 right-0 w-96 h-96 bg-violet-600/5 rounded-full blur-3xl pointer-events-none" />
            <div className="absolute bottom-0 left-0 w-96 h-96 bg-emerald-600/5 rounded-full blur-3xl pointer-events-none" />

            {/* Heading */}
            <div className="flex items-start justify-between mb-8 border-b border-slate-800/80 pb-6 flex-wrap gap-4">
              <div className="flex items-center gap-3">
                <div className="p-3 bg-violet-500/10 border border-violet-500/20 rounded-2xl">
                  <Brain className="w-8 h-8 text-violet-400" />
                </div>
                <div>
                  <h1 className="text-2xl font-black text-slate-100 tracking-tight">{t.proposalsTitle}</h1>
                  <p className="text-sm text-slate-400 mt-1">{t.proposalsDesc}</p>
                </div>
              </div>
              
              {/* Go Back button */}
              <button
                type="button"
                onClick={() => {
                  setProposals(null);
                  setSelectedOption(null);
                }}
                className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-950 border border-slate-850 hover:bg-slate-800 rounded-xl text-xs font-bold text-slate-400 hover:text-slate-200 transition-colors"
              >
                {lang === 'ko' ? '1단계로 돌아가기' : 'Back to Step 1'}
              </button>
            </div>

            {/* 3 Option Cards */}
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-8">
              {(['A', 'B', 'C'] as const).map(key => {
                const opt = proposals.options[key];
                const isSelected = selectedOption === key;
                return (
                  <div
                    key={key}
                    onClick={() => setSelectedOption(key)}
                    className={`relative cursor-pointer border rounded-2xl p-5 flex flex-col justify-between transition-all duration-300 transform hover:-translate-y-1 hover:shadow-xl ${
                      isSelected
                        ? 'border-violet-500 bg-violet-950/15 shadow-[0_0_25px_rgba(139,92,246,0.1)] ring-1 ring-violet-500/40'
                        : 'border-slate-800/80 bg-slate-950/40 hover:border-slate-700 hover:bg-slate-950/60'
                    }`}
                  >
                    <div>
                      {/* Header */}
                      <div className="flex items-center justify-between mb-3.5">
                        <span className={`text-[10px] uppercase font-extrabold tracking-wider px-2 py-0.5 rounded-full ${
                          key === 'A' ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20' :
                          key === 'B' ? 'bg-blue-500/10 text-blue-400 border border-blue-500/20' :
                          'bg-violet-500/10 text-violet-400 border border-violet-500/20'
                        }`}>
                          {key === 'A' ? t.optionATitle : key === 'B' ? t.optionBTitle : t.optionCTitle}
                        </span>
                        {isSelected && (
                          <div className="p-1 bg-violet-500 rounded-full text-white shadow-lg shadow-violet-500/30">
                            <Check className="w-3.5 h-3.5 stroke-[3]" />
                          </div>
                        )}
                      </div>

                      <h3 className="text-base font-bold text-slate-200 mb-1.5">{opt.title}</h3>
                      <p className="text-xs text-slate-400 mb-4 leading-relaxed">{opt.objective}</p>

                      <div className="space-y-3.5 border-t border-slate-900 pt-3.5 text-xs">
                        <div>
                          <span className="block text-[10px] uppercase font-bold text-slate-500 mb-1">Target User</span>
                          <span className="text-slate-355">{opt.coreUser}</span>
                        </div>
                        <div>
                          <span className="block text-[10px] uppercase font-bold text-slate-500 mb-1">Core Scope</span>
                          <ul className="list-disc pl-4 space-y-0.5 text-slate-355">
                            {opt.scope.map((s, idx) => <li key={idx}>{s}</li>)}
                          </ul>
                        </div>
                        <div>
                          <span className="block text-[10px] uppercase font-bold text-emerald-400/80 mb-1">Pros</span>
                          <ul className="list-disc pl-4 space-y-0.5 text-emerald-355/90">
                            {opt.pros.map((p, idx) => <li key={idx}>{p}</li>)}
                          </ul>
                        </div>
                        <div>
                          <span className="block text-[10px] uppercase font-bold text-rose-400/80 mb-1">Cons</span>
                          <ul className="list-disc pl-4 space-y-0.5 text-rose-355/90">
                            {opt.cons.map((c, idx) => <li key={idx}>{c}</li>)}
                          </ul>
                        </div>
                      </div>
                    </div>

                    <div className="border-t border-slate-900 mt-4 pt-3.5">
                      <span className="block text-[10px] uppercase font-bold text-slate-500 mb-1">Best Scenario</span>
                      <p className="text-[11px] text-slate-400 italic leading-snug">{opt.recommendedScenario}</p>
                    </div>
                  </div>
                );
              })}
            </div>

            {/* Director Recommendation */}
            <div className="relative border border-violet-500/25 bg-gradient-to-r from-violet-950/15 via-slate-900/30 to-slate-950/50 rounded-2xl p-6 mb-8 shadow-lg shadow-violet-900/5">
              <div className="absolute top-0 right-0 w-32 h-32 bg-violet-500/5 rounded-full blur-2xl pointer-events-none" />
              <span className="absolute -top-3 left-6 flex items-center gap-1 px-3 py-1 bg-violet-650 border border-violet-400/30 rounded-full text-[10px] uppercase font-black text-white tracking-widest shadow-md">
                <Sparkles className="w-3 h-3 fill-white" />
                {t.recommendedLabel}
              </span>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6 text-xs mt-2">
                <div>
                  <div className="mb-4">
                    <span className="block text-[10px] uppercase font-bold text-violet-400 mb-1">Recommended Approach</span>
                    <span className="text-sm font-black text-slate-200">
                      Option {proposals.recommendation.recommendedOption} — {proposals.options[proposals.recommendation.recommendedOption].title}
                    </span>
                  </div>
                  <div>
                    <span className="block text-[10px] uppercase font-bold text-slate-500 mb-1">{t.reasonLabel}</span>
                    <p className="text-slate-355 leading-relaxed">{proposals.recommendation.reason}</p>
                  </div>
                </div>

                <div className="space-y-4 border-l border-slate-800/80 pl-6">
                  <div>
                    <span className="block text-[10px] uppercase font-bold text-slate-500 mb-1">{t.discardedLabel}</span>
                    <p className="text-slate-400 leading-normal">{proposals.recommendation.discardedOptions}</p>
                  </div>
                  {proposals.recommendation.combinedElements && (
                    <div>
                      <span className="block text-[10px] uppercase font-bold text-slate-500 mb-1">Combined Elements (Hybrid Potential)</span>
                      <p className="text-slate-400 leading-normal">{proposals.recommendation.combinedElements}</p>
                    </div>
                  )}
                  <div>
                    <span className="block text-[10px] uppercase font-bold text-violet-400/80 mb-1">{t.decisionsRequiredLabel}</span>
                    <ul className="list-disc pl-4 space-y-1 text-slate-350">
                      {proposals.recommendation.userDecisionsRequired.map((d, idx) => (
                        <li key={idx}>{d}</li>
                      ))}
                    </ul>
                  </div>
                </div>
              </div>
            </div>

            {/* Adjustments & Feedback Row */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
              {/* User Custom Adjustments */}
              <div className="bg-slate-900/30 border border-slate-800/80 rounded-2xl p-5 flex flex-col">
                <label className="block text-xs font-semibold uppercase tracking-wider text-slate-400 mb-2">
                  {lang === 'ko' ? '기획 맞춤 조정 (선택)' : 'Custom Adjustments (Optional)'}
                </label>
                <textarea
                  placeholder={t.customAdjustmentsPlaceholder}
                  value={userAdjustments}
                  onChange={(e) => setUserAdjustments(e.target.value)}
                  rows={3}
                  className="w-full h-full bg-slate-950 border border-slate-850 rounded-xl px-3 py-2 text-xs text-slate-300 placeholder-slate-600 focus:outline-none focus:border-violet-500 transition-colors resize-none"
                />
              </div>

              {/* Regeneration Feedback */}
              <div className="bg-slate-900/30 border border-slate-800/80 rounded-2xl p-5 flex flex-col justify-between">
                <div>
                  <label className="block text-xs font-semibold uppercase tracking-wider text-slate-400 mb-2">
                    {lang === 'ko' ? '기획 대안 피드백 및 재생성' : 'Regenerate with Feedback'}
                  </label>
                  <textarea
                    placeholder={t.regenerateFeedbackPlaceholder}
                    value={regenerationFeedback}
                    onChange={(e) => setRegenerationFeedback(e.target.value)}
                    rows={2}
                    className="w-full bg-slate-950 border border-slate-850 rounded-xl px-3 py-2 text-xs text-slate-300 placeholder-slate-600 focus:outline-none focus:border-violet-500 transition-colors resize-none"
                  />
                </div>
                <button
                  type="button"
                  onClick={handleRegenerateProposals}
                  className="mt-3 self-end flex items-center gap-1.5 px-4 py-2 bg-slate-950 border border-slate-850 hover:bg-slate-800 rounded-xl text-xs font-bold text-violet-400 hover:text-violet-300 transition-colors"
                >
                  <RotateCw className="w-3.5 h-3.5" />
                  {t.regenerateBtn}
                </button>
              </div>
            </div>

            {/* Big Action Submit */}
            <div className="flex flex-col items-center">
              <button
                type="button"
                onClick={handleSelectOptionSubmit}
                disabled={!selectedOption}
                className="px-8 py-4 bg-violet-650 hover:bg-violet-600 disabled:opacity-55 disabled:cursor-not-allowed text-white font-bold rounded-2xl transition-all duration-300 flex items-center gap-2.5 shadow-xl hover:shadow-violet-600/10 text-sm"
              >
                <Sparkles className="w-4 h-4" />
                {t.selectOptionBtn}
              </button>
              {!selectedOption && (
                <span className="text-[10px] text-slate-500 mt-2 text-center">
                  {lang === 'ko' ? '방향 선택을 진행하려면 위 대안 카드 중 하나를 클릭해 주세요.' : 'Please select one of the three option cards above to proceed.'}
                </span>
              )}
            </div>
          </div>
        )}

        {/* Floating toast */}
        {errorToast && (
          <div className="fixed bottom-5 right-5 bg-red-600/90 text-white px-4 py-2.5 rounded-xl shadow-lg border border-red-500 flex items-center gap-2 text-sm backdrop-blur-md">
            <AlertCircle className="w-4 h-4" />
            {errorToast.message}
          </div>
        )}
        {/* Settings Modal (Intake Wizard view) */}
        {renderSettingsModal()}
      </div>
    );
  }

  // Active Main Dashboard View
  const pendingDecisions = decisions.filter(d => d.status === 'pending');

  return (
    <div className="h-screen bg-slate-950 text-slate-100 flex flex-col font-sans overflow-hidden">
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_60%_50%_at_50%_-10%,rgba(120,119,198,0.15),rgba(255,255,255,0))] pointer-events-none" />

      {/* Header Bar */}
      <header className="relative z-10 border-b border-slate-900 bg-slate-950/60 backdrop-blur-md px-6 py-4 flex flex-col md:flex-row gap-4 items-center justify-between">
        <div className="flex items-center gap-3 w-full md:w-auto justify-center md:justify-start">
          <div className="p-2.5 bg-violet-500/10 border border-violet-500/20 rounded-xl">
            <Brain className="w-6 h-6 text-violet-400" />
          </div>
          <div>
            <h1 className="text-lg font-black tracking-tight text-slate-200">{config.projectName}</h1>
            <p className="text-xs text-slate-400 max-w-sm truncate">{config.projectDesc}</p>
          </div>
        </div>

        {/* Phase / Lock Gate & Controls */}
        <div className="flex flex-wrap items-center justify-center md:justify-end gap-3 md:gap-4 w-full md:w-auto">
          
          {/* Dynamic Language Switcher */}
          <button
            onClick={() => setLang(l => l === 'ko' ? 'en' : 'ko')}
            className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-900 border border-slate-800 hover:bg-slate-800 rounded-xl text-xs font-bold text-slate-350 transition-colors"
          >
            <Globe className="w-3.5 h-3.5" />
            {lang === 'ko' ? 'EN' : 'KO'}
          </button>

          {/* Phase Badge */}
          <div className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full border text-xs font-semibold ${
            config.phase === 'development'
              ? 'bg-emerald-500/10 border-emerald-500/20 text-emerald-400'
              : 'bg-amber-500/10 border-amber-500/20 text-amber-400'
          }`}>
            {config.phase === 'development' ? <Lock className="w-3.5 h-3.5" /> : <Unlock className="w-3.5 h-3.5" />}
            {config.phase === 'development' ? t.developmentPhase : t.planningPhase}
          </div>

          {/* Start Dev Transition CTA */}
          <button
            id="phase-lock-btn"
            onClick={togglePhaseLock}
            className={`flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-bold transition-all shadow-md ${
              config.phase === 'development'
                ? 'bg-amber-600 hover:bg-amber-500 text-white'
                : 'bg-emerald-600 hover:bg-emerald-500 text-white shadow-emerald-600/10'
            }`}
          >
            {config.phase === 'development' ? t.unlockPlanning : `${t.startDevelopment} (${t.lockSpecCTA})`}
          </button>

          {/* Settings trigger */}
          <button
            onClick={() => setShowSettings(true)}
            className="p-2.5 bg-slate-900 border border-slate-800 hover:bg-slate-800 rounded-xl transition-colors text-slate-400 hover:text-slate-200"
            title="Settings"
          >
            <Settings className="w-4 h-4" />
          </button>
        </div>
      </header>

      {/* Main split-screen panel */}
      <main className="flex-1 flex flex-col md:flex-row overflow-y-auto md:overflow-hidden">
        {/* Left Side: Wizard / Decision Cards deck & Chat */}
        <div className="w-full md:w-2/5 flex-none md:flex-none border-b md:border-b-0 md:border-r border-slate-900 bg-slate-950/20 flex flex-col p-6 space-y-6 overflow-y-visible md:overflow-y-auto min-h-[450px] md:min-h-0">
          {/* 1. Decision Card Section */}
          {config.phase === 'development' ? (
            /* Implementation Checklist Panel */
            <div className="flex-none flex flex-col bg-slate-900/10 border border-slate-900 rounded-2xl p-5 relative overflow-hidden">
              <div className="absolute top-0 right-0 w-64 h-64 bg-emerald-500/5 rounded-full blur-3xl pointer-events-none" />
              <div className="flex items-center justify-between mb-4 border-b border-slate-900 pb-3">
                <span className="text-xs font-bold uppercase tracking-wider text-slate-350 flex items-center gap-1.5">
                  <ListTodo className="w-4 h-4 text-emerald-400 animate-pulse" />
                  {t.tasksTitle}
                </span>
                
                <button
                  type="button"
                  onClick={handleGenerateTasks}
                  disabled={isGeneratingTasks}
                  className="px-2 py-1 bg-slate-950 border border-slate-850 hover:bg-slate-800 rounded-lg text-[9px] text-slate-450 font-bold transition-all disabled:opacity-50"
                >
                  {isGeneratingTasks ? <Loader2 className="w-2.5 h-2.5 animate-spin" /> : t.generateTasksBtn}
                </button>
              </div>

              {tasks.length > 0 ? (
                <div className="space-y-2.5 max-h-[300px] overflow-y-auto pr-1">
                  {tasks.map(task => (
                    <button
                      key={task.index}
                      type="button"
                      onClick={() => handleToggleTask(task.index, task.status)}
                      className={`w-full text-left p-3 rounded-xl border transition-all text-xs flex items-start gap-2.5 ${
                        task.status === 'done'
                          ? 'bg-slate-950/40 border-slate-900/60 text-slate-550 line-through'
                          : task.status === 'in_progress'
                          ? 'bg-slate-900/60 border-violet-900/50 text-slate-200 border-l-2 border-l-violet-500 shadow-md shadow-violet-500/5'
                          : 'bg-slate-950 border-slate-855 hover:bg-slate-900/40 text-slate-300'
                      }`}
                    >
                      <div className="mt-0.5 shrink-0">
                        {task.status === 'done' ? (
                          <div className="w-4 h-4 rounded bg-emerald-500/20 border border-emerald-500/30 flex items-center justify-center">
                            <Check className="w-2.5 h-2.5 text-emerald-400" />
                          </div>
                        ) : task.status === 'in_progress' ? (
                          <div className="w-4 h-4 rounded bg-violet-500/20 border border-violet-500/30 flex items-center justify-center">
                            <Loader2 className="w-2.5 h-2.5 text-violet-400 animate-spin" />
                          </div>
                        ) : (
                          <div className="w-4 h-4 rounded bg-slate-950 border border-slate-800" />
                        )}
                      </div>
                      <span className="leading-normal">{task.text}</span>
                    </button>
                  ))}
                </div>
              ) : (
                <div className="text-center py-6 text-xs text-slate-555 italic">
                  {t.noTasks}
                </div>
              )}
            </div>
          ) : (
            <div className="flex-none">
              <span className="block text-xs font-bold uppercase tracking-wider text-slate-400 mb-3 flex items-center gap-1.5">
                <GitBranch className="w-4 h-4 text-violet-400" />
                {t.decisionCardsDeck} ({pendingDecisions.length})
              </span>

              {pendingDecisions.length > 0 ? (
                <div className="space-y-4">
                  {pendingDecisions.map(card => (
                    <div
                      key={card.id}
                      className="bg-slate-900/50 border border-slate-800/80 rounded-2xl p-5 relative overflow-hidden transition-all hover:border-slate-700"
                    >
                      <div className="absolute top-0 right-0 px-2 py-0.5 bg-violet-600/20 text-violet-400 rounded-bl-lg text-[9px] uppercase font-bold tracking-wider">
                        {card.section}
                      </div>
                      <h3 className="text-sm font-bold text-slate-200 mb-1.5 pr-14">{card.title}</h3>
                      
                      {/* Alternatives list */}
                      <div className="space-y-2 mt-3">
                        {card.options.map(opt => (
                          <button
                            key={opt.name}
                            type="button"
                            onClick={() => handleResolveDecision(card.id, opt.name)}
                            className="w-full bg-slate-950 border border-slate-850 hover:bg-slate-900/60 p-3 rounded-xl text-left transition-colors border-l-2 hover:border-l-violet-500"
                          >
                            <span className="block text-xs font-bold text-slate-300 flex items-center justify-between">
                              {opt.name}
                              <ArrowRight className="w-3 h-3 text-slate-500" />
                            </span>
                            <span className="block text-[10px] text-slate-505 mt-1">{opt.desc}</span>
                          </button>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="bg-slate-900/20 border border-slate-900 rounded-2xl p-6 text-center text-xs text-slate-500">
                  {t.allResolved}
                </div>
              )}
            </div>
          )}

          {/* 기획 하네스 반려 오류 경고 패널 (HITL) */}
          {validationErrors && lastRejectedSpec && (
            <div className="bg-red-950/20 border border-red-900/50 rounded-2xl p-5 text-xs space-y-3.5 relative overflow-hidden animate-fade-in">
              <div className="absolute top-0 right-0 w-32 h-32 bg-red-500/5 rounded-full blur-2xl pointer-events-none" />
              <div className="flex items-center gap-2 text-red-200 font-bold border-b border-red-900/20 pb-2.5">
                <AlertTriangle className="w-4 h-4 text-red-400 animate-pulse animate-duration-1000" />
                <span>기획 하네스 검증 통과 실패 (반려)</span>
              </div>
              <p className="text-slate-400 text-[10px] leading-relaxed">
                AI가 제안한 명세 변경 사항이 기획 가이드라인 규격을 충족하지 못해 저장이 보류되었습니다.
              </p>
              <ul className="list-disc pl-4.5 space-y-1 text-red-350 font-medium text-[11px]">
                {validationErrors.map((err, idx) => <li key={idx}>{err}</li>)}
              </ul>
              <div className="flex gap-2 justify-end pt-2.5 border-t border-red-900/10 text-[11px]">
                <button
                  type="button"
                  onClick={() => {
                    setValidationErrors(null);
                    setLastRejectedSpec(null);
                  }}
                  className="px-3 py-1.5 bg-slate-950 border border-slate-850 hover:bg-slate-800 rounded-xl text-slate-400 font-bold transition-colors"
                >
                  반려창 닫기
                </button>
                <button
                  type="button"
                  onClick={handleForceCommit}
                  className="px-3 py-1.5 bg-red-800 hover:bg-red-700 text-white rounded-xl font-bold flex items-center gap-1 shadow-md shadow-red-900/20 transition-colors"
                >
                  <Check className="w-3.5 h-3.5" />
                  강제 승인 (Force Commit)
                </button>
              </div>
            </div>
          )}

          {/* 2. Interactive Agent Chat Widget */}
          <div className="flex-1 flex flex-col bg-slate-900/30 border border-slate-900 rounded-2xl overflow-visible md:overflow-hidden min-h-[350px]">
            {/* Chat header */}
            <div className="bg-slate-900/40 border-b border-slate-900 px-4 py-3 flex items-center justify-between">
              <span className="text-xs font-bold uppercase tracking-wider text-slate-400 flex items-center gap-1.5">
                <Brain className="w-3.5 h-3.5 text-violet-400" />
                {t.officeAgentChat}
              </span>

              {/* Streaming routing chip */}
              {routingStatus.isRouting && (
                <div className="flex items-center gap-1.5 px-2.5 py-0.5 bg-violet-500/10 border border-violet-500/20 text-violet-400 rounded-full text-[10px] font-semibold animate-pulse">
                  <span className="w-1.5 h-1.5 rounded-full bg-violet-400" />
                  <span>{t.directorRouting}</span>
                </div>
              )}
              {routingStatus.route && (
                <div className="flex items-center gap-1.5 px-2.5 py-0.5 bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 rounded-full text-[10px] font-semibold">
                  <span className="w-1.5 h-1.5 rounded-full bg-emerald-450 animate-ping" />
                  <span className="capitalize">{routingStatus.route}</span>
                  <span className="opacity-75">{t.responding}</span>
                </div>
              )}
            </div>

            {/* Chat Messages */}
            <div className="flex-1 p-4 overflow-y-visible md:overflow-y-auto space-y-4 text-xs">
              {messages.length === 0 ? (
                <div className="text-center text-slate-600 mt-10">
                  Discuss or refine the sprouted spec here. Ask questions, request new features, or technical clarifications.
                </div>
              ) : (
                messages.map((msg, i) => (
                  <div
                    key={msg.id || i}
                    className={`flex flex-col max-w-[85%] ${msg.author === 'user' ? 'ml-auto items-end' : 'mr-auto items-start'}`}
                  >
                    <span className="text-[10px] uppercase font-bold text-slate-500 mb-1 capitalize">
                      {msg.author === 'user' ? 'You' : msg.author}
                    </span>
                    {msg.author === 'user' ? (
                      <div className="p-3 rounded-2xl bg-violet-600 text-white rounded-tr-none whitespace-pre-wrap">
                        {msg.content}
                      </div>
                    ) : (
                      <div 
                        className="p-3 rounded-2xl bg-slate-900 text-slate-300 rounded-tl-none border border-slate-800/80 markdown-content w-full"
                        dangerouslySetInnerHTML={renderMarkdown(msg.content)}
                      />
                    )}
                  </div>
                ))
              )}
              {isSending && messages.length > 0 && messages[messages.length - 1].author === 'user' && (
                <div className="flex flex-col items-start max-w-[85%] mr-auto animate-fade-in">
                  <span className="text-[10px] uppercase font-bold text-slate-500 mb-1 capitalize">
                    {routingStatus.route || 'Agent'}
                  </span>
                  <div className="p-3 rounded-2xl bg-slate-900 text-slate-300 rounded-tl-none border border-slate-800/80 flex items-center gap-1 px-4">
                    {harnessStatus ? (
                      <span className="flex items-center gap-1.5 text-slate-400 font-medium italic animate-pulse">
                        <Loader2 className="w-3.5 h-3.5 text-violet-400 animate-spin" />
                        {harnessStatus}
                      </span>
                    ) : (
                      <>
                        <span className="w-1.5 h-1.5 rounded-full bg-slate-400 animate-bounce" style={{ animationDelay: '0ms' }} />
                        <span className="w-1.5 h-1.5 rounded-full bg-slate-400 animate-bounce" style={{ animationDelay: '150ms' }} />
                        <span className="w-1.5 h-1.5 rounded-full bg-slate-400 animate-bounce" style={{ animationDelay: '300ms' }} />
                      </>
                    )}
                  </div>
                </div>
              )}
              <div ref={chatEndRef} />
            </div>

            {/* Chat Input form */}
            <form onSubmit={handleSendMessage} className="p-3 bg-slate-950/50 border-t border-slate-900 flex gap-2">
              <input
                type="text"
                value={chatMessage}
                onChange={e => setChatMessage(e.target.value)}
                placeholder={config.phase === 'development' ? t.chatLocked : t.chatPlaceholder}
                className="flex-1 bg-slate-950 border border-slate-850 rounded-xl px-4 py-2 text-xs focus:outline-none focus:border-violet-500 placeholder-slate-600"
                disabled={isSending || config.phase === 'development'}
              />
              <button
                type="submit"
                disabled={isSending || config.phase === 'development'}
                className="p-2 bg-violet-600 hover:bg-violet-500 disabled:bg-slate-800 disabled:text-slate-600 text-white rounded-xl transition-colors"
              >
                {isSending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
              </button>
            </form>
          </div>
        </div>

        {/* Right Side: Document Tabs Workspace */}
        <div className="w-full md:w-auto flex-none md:flex-1 md:min-w-0 flex flex-col bg-slate-950 min-h-[550px] md:min-h-0">
          {/* Tab buttons */}
          <div className="bg-slate-950/40 border-b border-slate-900 px-6 py-2 flex items-center justify-between">
            <div className="flex gap-4">
              {[
                { id: 'spec', label: t.compiledSpecTab, icon: FileText },
                { id: 'devloop', label: t.devloopConsoleTab, icon: Terminal },
                { id: 'preview', label: t.previewTab, icon: Globe },
                { id: 'timeline', label: t.decisionTimelineTab, icon: BookOpen },
                { id: 'gaps', label: t.gapAuditorTab, icon: AlertTriangle },
                { id: 'diagnostics', label: t.diagnosticsTab, icon: Brain }
              ].map(tab => {
                const Icon = tab.icon;
                return (
                  <button
                    key={tab.id}
                    onClick={() => setActiveTab(tab.id as any)}
                    className={`flex items-center gap-1.5 py-2 text-xs font-semibold border-b-2 transition-all ${
                      activeTab === tab.id
                        ? 'border-violet-500 text-slate-200'
                        : 'border-transparent text-slate-500 hover:text-slate-350'
                    }`}
                  >
                    <Icon className="w-4 h-4" />
                    {tab.label}
                  </button>
                );
              })}
            </div>

            {/* Mini Audit Trigger */}
            <button
              id="gap-audit-btn"
              onClick={runGapAuditor}
              disabled={isAuditing}
              className="flex items-center gap-1 px-3 py-1 bg-slate-900 border border-slate-850 hover:bg-slate-800 rounded-lg text-[10px] text-slate-400 font-bold transition-all disabled:opacity-50"
            >
              {isAuditing ? <Loader2 className="w-3 h-3 animate-spin" /> : <AlertCircle className="w-3 h-3 text-amber-500" />}
              {t.runGapAudit}
            </button>
          </div>

          {/* Tab Contents */}
          <div className="flex-1 overflow-x-auto overflow-y-visible md:overflow-y-auto p-6">
            
            {/* A. Live Compiled Spec Viewer */}
            {activeTab === 'spec' && (
              <div className="max-w-3xl mx-auto space-y-6">
                {sections.map(section => (
                  <div
                    key={section.id}
                    className={`border border-slate-900 rounded-2xl p-6 transition-all relative group ${
                      editingSectionId === section.id ? 'bg-slate-950 border-violet-500' : 'bg-slate-900/20 hover:border-slate-800'
                    }`}
                  >
                    <div className="flex items-center justify-between border-b border-slate-900 pb-3 mb-4">
                      <div className="flex items-center gap-2">
                        <span className="text-xs font-bold text-slate-300">{section.title}</span>
                        <span className={`text-[9px] uppercase px-1.5 py-0.5 rounded font-black tracking-wider ${
                          section.id === 'core_spec' ? 'bg-emerald-500/20 text-emerald-400' : 'bg-violet-500/20 text-violet-400'
                        }`}>
                          {section.id === 'core_spec' ? 'Core' : 'Feature'}
                        </span>
                      </div>
                      
                      {/* Double click instruction */}
                      <span className="text-[10px] text-slate-600 select-none group-hover:block hidden">
                        {t.doubleClickToEdit}
                      </span>
                    </div>

                    {/* Content / Editor */}
                    {editingSectionId === section.id ? (
                      <div className="space-y-3">
                        <textarea
                          value={editingContent}
                          onChange={e => setEditingContent(e.target.value)}
                          rows={12}
                          className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-3 text-xs text-slate-300 font-mono focus:outline-none focus:border-violet-500 resize-y"
                        />
                        <div className="flex justify-end gap-2 text-xs">
                          <button
                            onClick={() => setEditingSectionId(null)}
                            className="px-3 py-1.5 bg-slate-900 hover:bg-slate-800 rounded-lg text-slate-400 font-bold"
                          >
                            {t.cancelBtn}
                          </button>
                          <button
                            id="save-spec-btn"
                            onClick={() => handleSaveEdit(section.id)}
                            className="px-3 py-1.5 bg-violet-600 hover:bg-violet-500 text-white rounded-lg font-bold"
                          >
                            {t.saveSpecBtn}
                          </button>
                        </div>
                      </div>
                    ) : (
                      <div
                        onDoubleClick={() => handleStartEditing(section)}
                        className="text-xs text-slate-300 leading-relaxed select-text cursor-pointer hover:bg-slate-900/10 p-4 rounded-xl border border-slate-900 bg-slate-950/20 markdown-content"
                        title="Double click to edit spec"
                        dangerouslySetInnerHTML={renderMarkdown(section.content || t.noContent)}
                      />
                    )}
                  </div>
                ))}
              </div>
            )}

            {/* B. DevLoop Console Tab */}
            {activeTab === 'devloop' && config?.phase === 'development' && (
              <div className="space-y-4 max-w-4xl mx-auto h-full flex flex-col">
                {/* AI Error Explanation Alert Card */}
                {devLoopExplanation && (
                  <div className="bg-red-950/30 border border-red-900/50 rounded-2xl p-5 relative overflow-hidden shadow-lg shrink-0">
                    <div className="absolute top-0 right-0 w-64 h-64 bg-red-500/5 rounded-full blur-3xl pointer-events-none" />
                    <div className="flex items-center gap-2 mb-3 pb-2 border-b border-red-900/20">
                      <AlertCircle className="w-5 h-5 text-red-400 animate-pulse" />
                      <span className="text-sm font-bold text-red-200">{t.errorExplanationTitle}</span>
                    </div>
                    <div
                      className="text-xs text-red-350 leading-relaxed select-text markdown-content max-h-[200px] overflow-y-auto"
                      dangerouslySetInnerHTML={renderMarkdown(devLoopExplanation)}
                    />
                  </div>
                )}

                <div className="h-[450px] md:h-full flex-1 flex flex-col border border-slate-900 bg-slate-950/80 rounded-2xl overflow-hidden shadow-2xl">
                  {/* Console actions */}
                  <div className="bg-slate-900/40 border-b border-slate-900 px-4 py-3 flex gap-2">
                    <button
                      onClick={() => runDevCommand('build')}
                      disabled={activeDevCommand !== null}
                      className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-950 border border-slate-800 hover:bg-slate-800 disabled:opacity-50 text-xs font-bold rounded-lg text-slate-300 transition-colors"
                    >
                      <Play className="w-3.5 h-3.5 text-violet-400" />
                      {t.runBuildBtn}
                    </button>
                    <button
                      onClick={() => runDevCommand('verify')}
                      disabled={activeDevCommand !== null}
                      className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-950 border border-slate-800 hover:bg-slate-800 disabled:opacity-50 text-xs font-bold rounded-lg text-slate-300 transition-colors"
                    >
                      <Check className="w-3.5 h-3.5 text-emerald-400" />
                      {t.runVerifyBtn}
                    </button>
                    <button
                      onClick={() => runDevCommand('launch')}
                      disabled={activeDevCommand !== null}
                      className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-950 border border-slate-800 hover:bg-slate-800 disabled:opacity-50 text-xs font-bold rounded-lg text-slate-300 transition-colors"
                    >
                      <Play className="w-3.5 h-3.5 text-blue-400 animate-pulse" />
                      {t.launchServerBtn}
                    </button>
                  </div>

                  {/* Logs Screen */}
                  <div className="flex-1 p-4 bg-black/95 font-mono text-xs text-slate-400 overflow-y-auto leading-relaxed select-text">
                    {consoleLogs.length === 0 ? (
                      <div className="text-slate-700 italic">{t.consoleIdle}</div>
                    ) : (
                      consoleLogs.map((log, idx) => (
                        <div
                          key={idx}
                          className={`whitespace-pre-wrap ${
                            log.type === 'stderr' ? 'text-red-400' : log.type === 'info' ? 'text-violet-400 font-bold' : 'text-slate-300'
                          }`}
                        >
                          {log.text}
                        </div>
                      ))
                    )}
                    <div ref={logsEndRef} />
                  </div>
                </div>
              </div>
            )}

            {/* E. Live App Preview Tab */}
            {activeTab === 'preview' && (
              <div className="h-[450px] md:h-full flex flex-col max-w-4xl mx-auto border border-slate-900 bg-slate-950/80 rounded-2xl overflow-hidden shadow-2xl animate-fade-in">
                {/* URL Bar */}
                <div className="bg-slate-900/40 border-b border-slate-900 px-4 py-3 flex gap-2 items-center justify-between">
                  <div className="flex items-center gap-2 flex-1">
                    <Globe className="w-4 h-4 text-violet-400 shrink-0" />
                    <input
                      type="text"
                      value={config?.phase === 'planning' ? '/api/project/mockup' : previewUrl}
                      onChange={e => setPreviewUrl(e.target.value)}
                      disabled={config?.phase === 'planning'}
                      placeholder={t.previewUrlPlaceholder}
                      className="flex-1 max-w-md bg-slate-950 border border-slate-850 rounded-lg px-3 py-1.5 text-xs text-slate-350 focus:outline-none focus:border-violet-500 font-mono disabled:opacity-70"
                    />
                    <button
                      type="button"
                      onClick={() => setIframeKey(prev => prev + 1)}
                      title={lang === 'ko' ? '새로고침' : 'Refresh Preview'}
                      className="p-1.5 hover:bg-slate-800 active:bg-slate-850 border border-slate-850 hover:border-slate-800 rounded-lg text-slate-400 hover:text-slate-200 transition-colors flex items-center justify-center shrink-0 cursor-pointer"
                    >
                      <RotateCw className={`w-3.5 h-3.5 ${isMockupUpdating ? 'animate-spin' : ''}`} />
                    </button>
                  </div>
                  {config?.phase === 'planning' && (
                    <div className="flex items-center gap-1.5 px-3 py-1 bg-slate-900/60 backdrop-blur-md border border-slate-800 rounded-full text-[10px] font-semibold text-slate-300 shadow-inner shrink-0">
                      <span className="relative flex h-2 w-2">
                        <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                        <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
                      </span>
                      <span>{lang === 'ko' ? '기획 시안 프로토타입' : 'Design Prototype'}</span>
                    </div>
                  )}
                </div>
                {/* Webpage Viewer Frame */}
                <div className="flex-1 bg-white relative min-h-[400px]">
                  <iframe
                    key={iframeKey}
                    src={config?.phase === 'planning' ? '/api/project/mockup' : previewUrl}
                    title="App Preview"
                    className="w-full h-full border-none bg-white"
                    sandbox="allow-same-origin allow-scripts allow-popups allow-forms"
                  />
                  {/* Mockup Updating Overlay */}
                  {isMockupUpdating && (
                    <div className="absolute inset-0 bg-slate-950/60 backdrop-blur-sm flex flex-col items-center justify-center gap-3 animate-fade-in z-10">
                      <div className="flex items-center justify-center p-3 bg-slate-900/80 border border-slate-800 rounded-2xl shadow-xl">
                        <Loader2 className="w-8 h-8 text-violet-500 animate-spin" />
                      </div>
                      <div className="flex flex-col items-center gap-1 text-center px-4">
                        <p className="text-sm font-semibold text-slate-200">
                          {lang === 'ko' ? '시안 업데이트 중...' : 'Updating Mockup...'}
                        </p>
                        <p className="text-xs text-slate-400">
                          {lang === 'ko' ? 'AI가 기획서 변경사항을 반영하여 시안을 새로 쓰고 있습니다.' : 'AI is rewriting the mockup based on changes.'}
                        </p>
                      </div>
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* Locked State for DevLoop during Planning Phase */}
            {config?.phase === 'planning' && activeTab === 'devloop' && (
              <div className="h-[450px] md:h-full flex flex-col items-center justify-center max-w-4xl mx-auto border border-slate-900 bg-slate-950/40 rounded-2xl p-8 text-center relative overflow-hidden shadow-2xl">
                <div className="absolute inset-0 bg-[radial-gradient(ellipse_60%_60%_at_50%_50%,rgba(139,92,246,0.05),rgba(255,255,255,0))]" />
                <div className="p-4 bg-slate-900/80 border border-slate-800 rounded-2xl mb-4 relative">
                  <Lock className="w-8 h-8 text-violet-400 animate-pulse" />
                </div>
                <h3 className="text-base font-bold text-slate-200 mb-2">
                  {lang === 'ko' ? '개발 단계 전용 기능입니다' : 'Locked in Planning Phase'}
                </h3>
                <p className="text-xs text-slate-400 max-w-md leading-relaxed">
                  {lang === 'ko'
                    ? '현재는 기획 설계 단계(PLANNING)입니다. 상단의 [개발 단계 전환(기획 잠금)] 버튼을 클릭하여 기획을 확정하고 개발 모드로 전환한 뒤에 코드를 빌드하고 개발 콘솔을 제어해 보세요.'
                    : 'These engineering tools are locked during the Planning Phase. Click the "Start Development (Lock Spec)" button at the top header to finalize your specifications and unlock local building, testing, and development command control.'}
                </p>
              </div>
            )}

            {/* C. Decision Timeline Tab */}
            {activeTab === 'timeline' && (
              <div className="max-w-2xl mx-auto">
                {criteriaMarkdown ? (
                  <div 
                    className="bg-slate-900/30 border border-slate-900 rounded-2xl p-6 text-xs text-slate-350 leading-relaxed select-text markdown-content"
                    dangerouslySetInnerHTML={renderMarkdown(criteriaMarkdown)}
                  />
                ) : (
                  <div className="text-center text-slate-650 py-10">{t.noDecisionLogs}</div>
                )}
              </div>
            )}

            {/* D. Gap Auditor Logs */}
            {activeTab === 'gaps' && (
              <div className="max-w-2xl mx-auto space-y-4">
                <div className="bg-slate-900/30 border border-slate-900 rounded-2xl p-6 relative overflow-hidden">
                  <div className="absolute top-0 right-0 w-64 h-64 bg-amber-500/5 rounded-full blur-3xl pointer-events-none" />
                  <div className="flex items-center gap-2 mb-4">
                    <AlertTriangle className="w-5 h-5 text-amber-500" />
                    <span className="text-sm font-bold text-slate-200">{t.gapReportTitle}</span>
                  </div>

                  {gapReview ? (
                    <div 
                      className="text-xs text-slate-350 leading-relaxed select-text markdown-content"
                      dangerouslySetInnerHTML={renderMarkdown(gapReview)}
                    />
                  ) : isAuditing ? (
                    <div className="flex flex-col items-center justify-center py-10 space-y-3">
                      <Loader2 className="w-8 h-8 text-violet-500 animate-spin" />
                      <span className="text-xs text-slate-400 font-medium">
                        {lang === 'ko' ? '기획서 무결성 및 모순 감사 진행 중...' : 'Auditing specifications for gaps & contradictions...'}
                      </span>
                    </div>
                  ) : (
                    <div className="text-xs text-slate-600 italic">
                      {t.gapReportDesc}
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* E. Local AI CLI Diagnostics Tab */}
            {activeTab === 'diagnostics' && (
              <div className="max-w-2xl mx-auto space-y-4">
                <div className="bg-slate-900/30 border border-slate-900 rounded-2xl p-6 relative overflow-hidden">
                  <div className="absolute top-0 right-0 w-64 h-64 bg-violet-500/5 rounded-full blur-3xl pointer-events-none" />
                  <div className="flex items-center justify-between border-b border-slate-900 pb-4 mb-4">
                    <div className="flex items-center gap-2">
                      <Brain className="w-5 h-5 text-violet-400" />
                      <span className="text-sm font-bold text-slate-200">{t.diagnosticsTitle}</span>
                    </div>
                    <button
                      onClick={handleRunDiagnostics}
                      disabled={isDiagnosing}
                      className="flex items-center gap-1.5 px-3 py-1.5 bg-violet-600 hover:bg-violet-500 disabled:opacity-50 text-xs text-white rounded-lg font-bold transition-all"
                    >
                      {isDiagnosing ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <RotateCw className="w-3.5 h-3.5" />}
                      {t.runDiagnosticsBtn}
                    </button>
                  </div>
                  <p className="text-xs text-slate-450 mb-6 leading-relaxed">
                    {t.diagnosticsDesc}
                  </p>

                  {diagnosticsReport ? (
                    <div className="space-y-3">
                      {diagnosticsReport.map((item: any) => (
                        <div key={item.provider} className="bg-slate-950/40 border border-slate-900 rounded-xl p-4 flex flex-col gap-2">
                          <div className="flex items-center justify-between">
                            <span className="text-xs font-bold text-slate-350 uppercase">{item.provider}</span>
                            <span className={`text-[10px] font-black px-2 py-0.5 rounded ${
                              item.status === 'ok' 
                                ? 'bg-emerald-500/20 text-emerald-400' 
                                : item.status === 'missing' 
                                ? 'bg-red-500/20 text-red-400' 
                                : 'bg-amber-500/20 text-amber-400'
                            }`}>
                              {item.status === 'ok' ? 'OK' : item.status === 'missing' ? 'MISSING' : 'EXPIRED'}
                            </span>
                          </div>
                          {item.reason && (
                            <p className="text-[10px] text-slate-500 leading-normal font-mono bg-slate-950/80 p-2.5 rounded-lg border border-slate-900">
                              {item.reason}
                            </p>
                          )}
                          {item.status !== 'ok' && (
                            <div className="text-[10px] text-slate-450 bg-slate-900/10 p-2 rounded-lg border border-slate-900/50">
                              <span className="font-bold text-violet-400">💡 복구 가이드:</span>{' '}
                              {item.provider === 'claude' && (
                                <span>시스템 터미널에 ANTHROPIC_API_KEY 환경변수가 올바르게 정의되어 있는지 확인하세요. export ANTHROPIC_API_KEY="your-key"</span>
                              )}
                              {item.provider === 'gemini' && (
                                <span>시스템 터미널에 GEMINI_API_KEY 환경변수가 올바르게 정의되어 있는지 확인하세요. export GEMINI_API_KEY="your-key"</span>
                              )}
                              {item.provider !== 'claude' && item.provider !== 'gemini' && (
                                <span>해당 CLI가 전역 PATH(예: /usr/local/bin)에 설치되어 있고 로그인되어 있는지 확인하세요. 또는 .env 파일에 LAO_PROVIDER_{item.provider.toUpperCase()}_CLI 경로를 수동 지정하십시오.</span>
                              )}
                            </div>
                          )}
                        </div>
                      ))}
                    </div>
                  ) : isDiagnosing ? (
                    <div className="flex flex-col items-center justify-center py-10 space-y-3">
                      <Loader2 className="w-8 h-8 text-violet-500 animate-spin" />
                      <span className="text-xs text-slate-400 font-medium">
                        {lang === 'ko' ? '로컬 CLI 상태 진단 중...' : 'Diagnosing local CLI statuses...'}
                      </span>
                    </div>
                  ) : (
                    <div className="text-xs text-slate-600 italic text-center py-6">
                      {lang === 'ko' ? '자가진단 실행 버튼을 클릭하여 진단을 시작하세요.' : 'Click Run Diagnostics to analyze environment.'}
                    </div>
                  )}
                </div>
              </div>
            )}

          </div>
        </div>
      </main>

      {/* Settings Modal */}
      {renderSettingsModal()}

      {/* Floating Toast notification */}
      {errorToast && (
        <div className={`fixed bottom-5 right-5 z-50 px-4.5 py-3 rounded-2xl shadow-xl border flex items-center gap-2 text-xs font-bold backdrop-blur-md transition-all duration-300 ${
          errorToast.type === 'error'
            ? 'bg-red-950/80 border-red-800 text-red-300'
            : errorToast.type === 'success'
            ? 'bg-emerald-950/80 border-emerald-800 text-emerald-300'
            : 'bg-violet-950/80 border-violet-800 text-violet-300'
        }`}>
          <AlertCircle className="w-4 h-4 shrink-0" />
          {errorToast.message}
        </div>
      )}
    </div>
  );
}
