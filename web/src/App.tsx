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
  ArrowRight
} from 'lucide-react';
import type { SpecSection, DecisionCard, NodeMessage, ProjectConfig, GoldenRules } from './types';

export default function App() {
  // App Core States
  const [config, setConfig] = useState<ProjectConfig | null>(null);
  const [sections, setSections] = useState<SpecSection[]>([]);
  const [decisions, setDecisions] = useState<DecisionCard[]>([]);
  const [messages, setMessages] = useState<NodeMessage[]>([]);
  const [criteriaMarkdown, setCriteriaMarkdown] = useState<string>('');
  const [gapReview, setGapReview] = useState<string>('');

  // UI States
  const [activeTab, setActiveTab] = useState<'spec' | 'devloop' | 'timeline' | 'gaps'>('spec');
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
  const activeEventSourceRef = useRef<EventSource | null>(null);
  const logsEndRef = useRef<HTMLDivElement | null>(null);
  const chatEndRef = useRef<HTMLDivElement | null>(null);

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
        
        if (configData.projectName) {
          // Fetch specs, decisions, criteria, messages
          const [resSpecs, resDecs, resCriteria, resMessages] = await Promise.all([
            fetch('/api/specs'),
            fetch('/api/decisions'),
            fetch('/api/criteria'),
            fetch('/api/messages')
          ]);

          if (resSpecs.ok) setSections(await resSpecs.json());
          if (resDecs.ok) setDecisions(await resDecs.json());
          if (resCriteria.ok) {
            const data = await resCriteria.json();
            setCriteriaMarkdown(data.markdown);
          }
          if (resMessages.ok) setMessages(await resMessages.json());

          // Trigger compilation
          compileSpecs();
        }
      }
    } catch (e) {
      showToast('Error loading project workspace', 'error');
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

  // 2. Intake Sprouting
  const handleIntakeSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!intakeProjectName.trim() || !intakeDesc.trim()) {
      return showToast('Project Name and Rough Idea are required', 'warning');
    }
    setIsInitializing(true);
    try {
      const res = await fetch('/api/project/intake', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          projectName: intakeProjectName,
          projectDesc: intakeDesc,
          automationLevel: intakeLevel,
          goldenRules: intakeGoldenRules
        })
      });

      if (!res.ok) throw new Error('Intake failed');
      const data = await res.json();
      setConfig(data.config);
      setFormConfig(data.config);
      setSections(data.sections || []);
      setDecisions(data.decisions || []);
      setMessages([]);
      setCriteriaMarkdown('');
      compileSpecs();
      showToast('Specs sprouted successfully conforming to Golden Rules!', 'success');
    } catch (e: any) {
      showToast(`Initialization failed: ${e.message}`, 'error');
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
        showToast(`Decision resolved: ${optionName}`, 'success');
        fetchProjectData();
      }
    } catch (e) {
      showToast('Failed to resolve decision', 'error');
    }
  };

  // 4. Edit Spec Section
  const handleStartEditing = (section: SpecSection) => {
    if (config?.phase === 'development') {
      return showToast('Specifications are locked during development phase', 'warning');
    }
    setEditingSectionId(section.id);
    setEditingContent(section.content);
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
        showToast('Section updated successfully', 'success');
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
            ? 'Specifications LOCKED. Development phase active!'
            : 'Specifications UNLOCKED. Planning phase active.',
          'success'
        );
      }
    } catch (e) {
      showToast('Failed to change phase lock', 'error');
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
        showToast('Gap Audit completed successfully.', 'success');
      }
    } catch (e) {
      showToast('Gap Audit failed', 'error');
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
          fetchProjectData(); // Reload full states (spec, features, messages)
        } else if (data.type === 'error') {
          eventSource.close();
          setIsSending(false);
          setRoutingStatus({ isRouting: false });
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
      showToast('SSE connection closed or lost', 'error');
    };
  };

  // 8. Run DevLoop command
  const runDevCommand = (kind: 'build' | 'launch' | 'verify') => {
    setConsoleLogs([]);
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

  // Render Loader screen during initialization
  if (isInitializing) {
    return (
      <div className="min-h-screen bg-slate-950 flex flex-col items-center justify-center text-slate-100 p-6">
        <div className="bg-slate-900/60 backdrop-blur-xl border border-slate-800 p-8 rounded-2xl max-w-md w-full text-center shadow-2xl relative overflow-hidden">
          <div className="absolute inset-0 bg-gradient-to-tr from-violet-500/10 via-transparent to-emerald-500/10 animate-pulse pointer-events-none" />
          <Loader2 className="w-12 h-12 text-violet-500 animate-spin mx-auto mb-6" />
          <h2 className="text-xl font-bold text-slate-200 mb-2">Orchestrating AI Agents...</h2>
          <p className="text-sm text-slate-400">
            Specifier is drafting core specs, Optionizer is spawning decision forks, and Gap Detector is scanning the initial files. Please wait.
          </p>
        </div>
      </div>
    );
  }

  // Render Intake Wizard if no active project config exists
  if (!config || !config.projectName) {
    return (
      <div className="min-h-screen bg-slate-950 flex items-center justify-center p-4">
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_80%_at_50%_-20%,rgba(120,119,198,0.25),rgba(255,255,255,0))]" />
        
        <form onSubmit={handleIntakeSubmit} className="relative bg-slate-900/60 backdrop-blur-xl border border-slate-800 rounded-3xl p-8 max-w-2xl w-full shadow-2xl overflow-hidden">
          <div className="absolute top-0 right-0 w-64 h-64 bg-violet-600/10 rounded-full blur-3xl pointer-events-none" />
          <div className="absolute bottom-0 left-0 w-64 h-64 bg-emerald-600/10 rounded-full blur-3xl pointer-events-none" />

          {/* Heading */}
          <div className="flex items-center gap-3 mb-6">
            <div className="p-3 bg-violet-500/10 border border-violet-500/20 rounded-2xl">
              <Brain className="w-8 h-8 text-violet-400" />
            </div>
            <div>
              <h1 className="text-2xl font-black text-slate-100 tracking-tight">Launch New Project</h1>
              <p className="text-sm text-slate-400">Transform a rough seed idea into compiled specs & code</p>
            </div>
          </div>

          <div className="space-y-5">
            {/* Project Name */}
            <div>
              <label className="block text-xs font-semibold uppercase tracking-wider text-slate-400 mb-2">Project Name</label>
              <input
                type="text"
                placeholder="e.g. Local Database WebUI"
                value={intakeProjectName}
                onChange={e => setIntakeProjectName(e.target.value)}
                className="w-full bg-slate-950 border border-slate-800 rounded-xl px-4 py-3 text-slate-100 placeholder-slate-600 focus:outline-none focus:border-violet-500 transition-colors"
                required
              />
            </div>

            {/* Rough Idea */}
            <div>
              <label className="block text-xs font-semibold uppercase tracking-wider text-slate-400 mb-2">Rough Seed Idea</label>
              <textarea
                placeholder="Type your rough idea here... e.g. A lightweight web-based console to view and query local SQLite files with schema diagrams."
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
                Golden Rules Presets (Technology Guardrails)
              </span>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-[10px] uppercase font-bold text-slate-500 mb-1">Frontend</label>
                  <input
                    type="text"
                    value={intakeGoldenRules.frontend}
                    onChange={e => setIntakeGoldenRules(prev => ({ ...prev, frontend: e.target.value }))}
                    className="w-full bg-slate-950 border border-slate-850 rounded-lg px-2.5 py-1.5 text-xs text-slate-300 focus:outline-none focus:border-violet-500"
                  />
                </div>
                <div>
                  <label className="block text-[10px] uppercase font-bold text-slate-500 mb-1">Backend</label>
                  <input
                    type="text"
                    value={intakeGoldenRules.backend}
                    onChange={e => setIntakeGoldenRules(prev => ({ ...prev, backend: e.target.value }))}
                    className="w-full bg-slate-950 border border-slate-850 rounded-lg px-2.5 py-1.5 text-xs text-slate-300 focus:outline-none focus:border-violet-500"
                  />
                </div>
                <div>
                  <label className="block text-[10px] uppercase font-bold text-slate-500 mb-1">Database</label>
                  <input
                    type="text"
                    value={intakeGoldenRules.database}
                    onChange={e => setIntakeGoldenRules(prev => ({ ...prev, database: e.target.value }))}
                    className="w-full bg-slate-950 border border-slate-850 rounded-lg px-2.5 py-1.5 text-xs text-slate-300 focus:outline-none focus:border-violet-500"
                  />
                </div>
                <div>
                  <label className="block text-[10px] uppercase font-bold text-slate-500 mb-1">Constraints</label>
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
              <label className="block text-xs font-semibold uppercase tracking-wider text-slate-400 mb-2">Automation Level</label>
              <div className="grid grid-cols-3 gap-3">
                {[
                  { value: 'supervised', label: 'Supervised (상)', desc: 'Wait for approvals (Default)' },
                  { value: 'interactive', label: 'Interactive (중)', desc: 'Proceed and notify' },
                  { value: 'autopilot', label: 'Autopilot (하)', desc: 'Full hands-off build' }
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
            type="submit"
            className="w-full bg-violet-600 hover:bg-violet-500 text-white font-bold py-3.5 px-6 rounded-xl mt-6 transition-colors flex items-center justify-center gap-2 shadow-lg shadow-violet-600/20"
          >
            <Sparkles className="w-4 h-4 animate-pulse" />
            Sprout Core Specifications
          </button>
        </form>

        {/* Floating toast */}
        {errorToast && (
          <div className="fixed bottom-5 right-5 bg-red-600/90 text-white px-4 py-2.5 rounded-xl shadow-lg border border-red-500 flex items-center gap-2 text-sm backdrop-blur-md">
            <AlertCircle className="w-4 h-4" />
            {errorToast.message}
          </div>
        )}
      </div>
    );
  }

  // Active Main Dashboard View
  const pendingDecisions = decisions.filter(d => d.status === 'pending');

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col font-sans">
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_60%_50%_at_50%_-10%,rgba(120,119,198,0.15),rgba(255,255,255,0))] pointer-events-none" />

      {/* Header Bar */}
      <header className="relative z-10 border-b border-slate-900 bg-slate-950/60 backdrop-blur-md px-6 py-4 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="p-2.5 bg-violet-500/10 border border-violet-500/20 rounded-xl">
            <Brain className="w-6 h-6 text-violet-400" />
          </div>
          <div>
            <h1 className="text-lg font-black tracking-tight text-slate-200">{config.projectName}</h1>
            <p className="text-xs text-slate-400 max-w-sm truncate">{config.projectDesc}</p>
          </div>
        </div>

        {/* Phase / Lock Gate & Controls */}
        <div className="flex items-center gap-4">
          {/* Phase Badge */}
          <div className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full border text-xs font-semibold ${
            config.phase === 'development'
              ? 'bg-emerald-500/10 border-emerald-500/20 text-emerald-400'
              : 'bg-amber-500/10 border-amber-500/20 text-amber-400'
          }`}>
            {config.phase === 'development' ? <Lock className="w-3.5 h-3.5" /> : <Unlock className="w-3.5 h-3.5" />}
            {config.phase === 'development' ? 'DEVELOPMENT (LOCKED)' : 'PLANNING (EDITABLE)'}
          </div>

          {/* Start Dev Transition CTA */}
          <button
            onClick={togglePhaseLock}
            className={`flex items-center gap-1.5 px-4 py-2 rounded-xl text-xs font-bold transition-all shadow-md ${
              config.phase === 'development'
                ? 'bg-amber-600 hover:bg-amber-500 text-white'
                : 'bg-emerald-600 hover:bg-emerald-500 text-white shadow-emerald-600/10'
            }`}
          >
            {config.phase === 'development' ? 'Unlock Planning' : 'Start Development (Lock Spec)'}
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
      <main className="flex-1 flex overflow-hidden">
        {/* Left Side: Wizard Wizard / Decision Cards deck & Chat */}
        <div className="w-2/5 border-r border-slate-900 bg-slate-950/20 flex flex-col p-6 space-y-6 overflow-y-auto">
          {/* 1. Decision Card Section */}
          <div className="flex-none">
            <span className="block text-xs font-bold uppercase tracking-wider text-slate-400 mb-3 flex items-center gap-1.5">
              <GitBranch className="w-4 h-4 text-violet-400" />
              Decision Cards Deck ({pendingDecisions.length})
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
                          onClick={() => handleResolveDecision(card.id, opt.name)}
                          className="w-full bg-slate-950 border border-slate-850 hover:bg-slate-900/60 p-3 rounded-xl text-left transition-colors border-l-2 hover:border-l-violet-500"
                        >
                          <span className="block text-xs font-bold text-slate-300 flex items-center justify-between">
                            {opt.name}
                            <ArrowRight className="w-3 h-3 text-slate-500" />
                          </span>
                          <span className="block text-[10px] text-slate-500 mt-1">{opt.desc}</span>
                        </button>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="bg-slate-900/20 border border-slate-900 rounded-2xl p-6 text-center text-xs text-slate-500">
                All option forks resolved! The design aligns with the Golden Rules.
              </div>
            )}
          </div>

          {/* 2. Interactive Agent Chat Widget */}
          <div className="flex-1 flex flex-col bg-slate-900/30 border border-slate-900 rounded-2xl overflow-hidden min-h-[300px]">
            {/* Chat header */}
            <div className="bg-slate-900/40 border-b border-slate-900 px-4 py-3 flex items-center justify-between">
              <span className="text-xs font-bold uppercase tracking-wider text-slate-400 flex items-center gap-1.5">
                <Brain className="w-3.5 h-3.5 text-violet-400" />
                Office Agent Chat
              </span>

              {/* Streaming routing chip */}
              {routingStatus.isRouting && (
                <div className="text-[10px] text-violet-400 animate-pulse bg-violet-950/20 border border-violet-850 px-2 py-0.5 rounded-full">
                  Director routing...
                </div>
              )}
              {routingStatus.route && (
                <div className="text-[10px] text-emerald-400 bg-emerald-950/20 border border-emerald-850 px-2 py-0.5 rounded-full capitalize">
                  {routingStatus.route} responding...
                </div>
              )}
            </div>

            {/* Chat Messages */}
            <div className="flex-1 p-4 overflow-y-auto space-y-4 text-xs">
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
                    <div className={`p-3 rounded-2xl ${
                      msg.author === 'user'
                        ? 'bg-violet-600 text-white rounded-tr-none'
                        : 'bg-slate-900 text-slate-300 rounded-tl-none border border-slate-800/80'
                    }`}>
                      {msg.content}
                    </div>
                  </div>
                ))
              )}
              <div ref={chatEndRef} />
            </div>

            {/* Chat Input form */}
            <form onSubmit={handleSendMessage} className="p-3 bg-slate-950/50 border-t border-slate-900 flex gap-2">
              <input
                type="text"
                value={chatMessage}
                onChange={e => setChatMessage(e.target.value)}
                placeholder={config.phase === 'development' ? 'Chat locked in development phase' : 'Ask Specifier / Researcher / Gap Detector...'}
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
        <div className="flex-1 flex flex-col bg-slate-950">
          {/* Tab buttons */}
          <div className="bg-slate-950/40 border-b border-slate-900 px-6 py-2 flex items-center justify-between">
            <div className="flex gap-4">
              {[
                { id: 'spec', label: 'Compiled Spec', icon: FileText },
                { id: 'devloop', label: 'DevLoop Console', icon: Terminal },
                { id: 'timeline', label: 'Decision Timeline', icon: BookOpen },
                { id: 'gaps', label: 'Gap Auditor Logs', icon: AlertTriangle }
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
              onClick={runGapAuditor}
              disabled={isAuditing}
              className="flex items-center gap-1 px-3 py-1 bg-slate-900 border border-slate-850 hover:bg-slate-800 rounded-lg text-[10px] text-slate-400 font-bold transition-all disabled:opacity-50"
            >
              {isAuditing ? <Loader2 className="w-3 h-3 animate-spin" /> : <AlertCircle className="w-3 h-3 text-amber-500" />}
              Run Gap Audit
            </button>
          </div>

          {/* Tab Contents */}
          <div className="flex-1 overflow-y-auto p-6">
            
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
                        Double-click content to edit
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
                            Cancel
                          </button>
                          <button
                            onClick={() => handleSaveEdit(section.id)}
                            className="px-3 py-1.5 bg-violet-600 hover:bg-violet-500 text-white rounded-lg font-bold"
                          >
                            Save Spec Section
                          </button>
                        </div>
                      </div>
                    ) : (
                      <div
                        onDoubleClick={() => handleStartEditing(section)}
                        className="text-xs text-slate-400 leading-relaxed font-mono whitespace-pre-wrap select-text cursor-pointer hover:bg-slate-900/10 p-2 rounded-lg"
                        title="Double click to edit spec"
                      >
                        {section.content || '*(No details specified yet)*'}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}

            {/* B. DevLoop Console Tab */}
            {activeTab === 'devloop' && (
              <div className="h-full flex flex-col max-w-4xl mx-auto border border-slate-900 bg-slate-950/80 rounded-2xl overflow-hidden shadow-2xl">
                {/* Console actions */}
                <div className="bg-slate-900/40 border-b border-slate-900 px-4 py-3 flex gap-2">
                  <button
                    onClick={() => runDevCommand('build')}
                    disabled={activeDevCommand !== null}
                    className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-950 border border-slate-800 hover:bg-slate-800 disabled:opacity-50 text-xs font-bold rounded-lg text-slate-300 transition-colors"
                  >
                    <Play className="w-3.5 h-3.5 text-violet-400" />
                    Run Build
                  </button>
                  <button
                    onClick={() => runDevCommand('verify')}
                    disabled={activeDevCommand !== null}
                    className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-950 border border-slate-800 hover:bg-slate-800 disabled:opacity-50 text-xs font-bold rounded-lg text-slate-300 transition-colors"
                  >
                    <Check className="w-3.5 h-3.5 text-emerald-400" />
                    Run Verify (Tests)
                  </button>
                  <button
                    onClick={() => runDevCommand('launch')}
                    disabled={activeDevCommand !== null}
                    className="flex items-center gap-1.5 px-3 py-1.5 bg-slate-950 border border-slate-800 hover:bg-slate-800 disabled:opacity-50 text-xs font-bold rounded-lg text-slate-300 transition-colors"
                  >
                    <Play className="w-3.5 h-3.5 text-blue-400 animate-pulse" />
                    Launch Server
                  </button>
                </div>

                {/* Logs Screen */}
                <div className="flex-1 p-4 bg-black/95 font-mono text-xs text-slate-400 overflow-y-auto leading-relaxed select-text min-h-[300px]">
                  {consoleLogs.length === 0 ? (
                    <div className="text-slate-700 italic">Console idle. Trigger a DevLoop build or verification command...</div>
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
            )}

            {/* C. Decision Timeline Tab */}
            {activeTab === 'timeline' && (
              <div className="max-w-2xl mx-auto">
                {criteriaMarkdown ? (
                  <div className="bg-slate-900/30 border border-slate-900 rounded-2xl p-6 font-mono text-xs text-slate-400 leading-relaxed select-text whitespace-pre-wrap">
                    {criteriaMarkdown}
                  </div>
                ) : (
                  <div className="text-center text-slate-650 py-10">No decision logs found. Resolve a Decision Card to log criteria.</div>
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
                    <span className="text-sm font-bold text-slate-200">Specification Gap Report</span>
                  </div>

                  {gapReview ? (
                    <div className="font-mono text-xs text-slate-400 leading-relaxed whitespace-pre-wrap select-text">
                      {gapReview}
                    </div>
                  ) : (
                    <div className="text-xs text-slate-600 italic">
                      Click the "Run Gap Audit" button at the top right to verify all specifications against architectural guardrails.
                    </div>
                  )}
                </div>
              </div>
            )}

          </div>
        </div>
      </main>

      {/* Settings Modal */}
      {showSettings && formConfig && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <form onSubmit={saveSettings} className="bg-slate-900 border border-slate-800 rounded-3xl p-6 max-w-xl w-full shadow-2xl relative">
            <button
              type="button"
              onClick={() => setShowSettings(false)}
              className="absolute top-4 right-4 p-1.5 bg-slate-950 border border-slate-850 hover:bg-slate-800 rounded-lg text-slate-400 hover:text-slate-200"
            >
              <X className="w-4 h-4" />
            </button>

            {/* Modal Heading */}
            <div className="flex items-center gap-2.5 mb-5">
              <Settings className="w-5 h-5 text-violet-400" />
              <h2 className="text-base font-bold text-slate-100">Project Configuration</h2>
            </div>

            {/* Tab selection */}
            <div className="flex gap-2 border-b border-slate-850 mb-4 text-xs font-semibold">
              {[
                { id: 'global', label: 'Global Presets' },
                { id: 'agents', label: 'Agent Customization' },
                { id: 'devloop', label: 'DevLoop Commands' }
              ].map(t => (
                <button
                  key={t.id}
                  type="button"
                  onClick={() => setSettingsTab(t.id as any)}
                  className={`pb-2 px-1 border-b-2 transition-all ${
                    settingsTab === t.id
                      ? 'border-violet-500 text-slate-200'
                      : 'border-transparent text-slate-500 hover:text-slate-350'
                  }`}
                >
                  {t.label}
                </button>
              ))}
            </div>

            <div className="space-y-4 max-h-[350px] overflow-y-auto pr-1">
              {/* Tab Content: Global Settings */}
              {settingsTab === 'global' && (
                <div className="space-y-3.5 text-xs">
                  <div>
                    <label className="block font-semibold text-slate-400 mb-1">Global AI Provider</label>
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
                    </select>
                  </div>

                  <div>
                    <label className="block font-semibold text-slate-400 mb-1">Model Override (Optional)</label>
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
                    <label className="block font-semibold text-slate-300 mb-2">Golden Rules Constraints</label>
                    <div className="grid grid-cols-2 gap-3">
                      <div>
                        <label className="block text-[10px] text-slate-500 uppercase font-bold mb-1">Frontend</label>
                        <input
                          type="text"
                          value={formConfig.goldenRules.frontend}
                          onChange={e => setFormConfig(prev => ({
                            ...prev!,
                            goldenRules: { ...prev!.goldenRules, frontend: e.target.value }
                          }))}
                          className="w-full bg-slate-950 border border-slate-850 rounded-lg px-2.5 py-1.5 text-slate-300 text-xs"
                        />
                      </div>
                      <div>
                        <label className="block text-[10px] text-slate-500 uppercase font-bold mb-1">Backend</label>
                        <input
                          type="text"
                          value={formConfig.goldenRules.backend}
                          onChange={e => setFormConfig(prev => ({
                            ...prev!,
                            goldenRules: { ...prev!.goldenRules, backend: e.target.value }
                          }))}
                          className="w-full bg-slate-950 border border-slate-850 rounded-lg px-2.5 py-1.5 text-slate-300 text-xs"
                        />
                      </div>
                      <div>
                        <label className="block text-[10px] text-slate-500 uppercase font-bold mb-1">Database</label>
                        <input
                          type="text"
                          value={formConfig.goldenRules.database}
                          onChange={e => setFormConfig(prev => ({
                            ...prev!,
                            goldenRules: { ...prev!.goldenRules, database: e.target.value }
                          }))}
                          className="w-full bg-slate-950 border border-slate-850 rounded-lg px-2.5 py-1.5 text-slate-300 text-xs"
                        />
                      </div>
                      <div>
                        <label className="block text-[10px] text-slate-500 uppercase font-bold mb-1">Constraints</label>
                        <input
                          type="text"
                          value={formConfig.goldenRules.additional}
                          onChange={e => setFormConfig(prev => ({
                            ...prev!,
                            goldenRules: { ...prev!.goldenRules, additional: e.target.value }
                          }))}
                          className="w-full bg-slate-950 border border-slate-850 rounded-lg px-2.5 py-1.5 text-slate-300 text-xs"
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
                        <span className="font-bold text-slate-300 capitalize">{roleKey} Agent</span>
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
                          </select>
                          <input
                            type="text"
                            value={formConfig.settings.agents[typedKey].model}
                            onChange={e => setFormConfig(prev => {
                              const agents = { ...prev!.settings.agents };
                              agents[typedKey] = { ...agents[typedKey], model: e.target.value };
                              return { ...prev!, settings: { ...prev!.settings, agents } };
                            })}
                            placeholder="default model"
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
                    <label className="block font-semibold text-slate-400 mb-1">Build Command</label>
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
                    <label className="block font-semibold text-slate-400 mb-1">Verify (Test) Command</label>
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
                    <label className="block font-semibold text-slate-400 mb-1">Launch Command</label>
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
                Close
              </button>
              <button
                type="submit"
                className="px-4 py-2 bg-violet-600 hover:bg-violet-500 rounded-xl text-white font-bold"
              >
                Save Config
              </button>
            </div>
          </form>
        </div>
      )}

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
