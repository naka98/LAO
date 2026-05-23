import { useState, useEffect, useMemo } from 'react';
import { MindmapCanvas } from './components/MindmapCanvas';
import { NodeDetailPanel } from './components/NodeDetailPanel';
import type { GraphNode, GraphEdge, NodeMessage, ParsedProposal } from './types';
import { Brain, FileText, BookOpen, Check, Plus, Settings } from 'lucide-react';

function App() {
  const [nodes, setNodes] = useState<GraphNode[]>([]);
  const [edges, setEdges] = useState<GraphEdge[]>([]);
  const [messages, setMessages] = useState<NodeMessage[]>([]);
  const [selectedNodeId, setSelectedNodeId] = useState<string | null>(null);
  
  // App UI States
  const [isSending, setIsSending] = useState(false);
  const [isCompiling, setIsCompiling] = useState(false);
  const [showLogModal, setShowLogModal] = useState(false);
  const [criteriaMarkdown, setCriteriaMarkdown] = useState('');
  const [compileResult, setCompileResult] = useState<{ success: boolean; filePath: string } | null>(null);
  
  // Onboarding States
  const [showOnboardingModal, setShowOnboardingModal] = useState(false);
  const [seedTitle, setSeedTitle] = useState('');
  const [seedBody, setSeedBody] = useState('');
  const [isInitializing, setIsInitializing] = useState(false);
  const [showOnboardingSettings, setShowOnboardingSettings] = useState(false);
  
  // Settings States
  const [settings, setSettings] = useState<any>({ provider: 'gemini', model: '' });
  const [showSettingsModal, setShowSettingsModal] = useState(false);
  const [formProvider, setFormProvider] = useState('gemini');
  const [formModel, setFormModel] = useState('');
  const [activeSettingsTab, setActiveSettingsTab] = useState<'global' | 'agents'>('global');
  const [formAgents, setFormAgents] = useState<{
    director: { provider: string; model: string };
    specifier: { provider: string; model: string };
    researcher: { provider: string; model: string };
    optionizer: { provider: string; model: string };
    gapDetector: { provider: string; model: string };
  }>({
    director: { provider: 'gemini', model: '' },
    specifier: { provider: 'gemini', model: '' },
    researcher: { provider: 'gemini', model: '' },
    optionizer: { provider: 'gemini', model: '' },
    gapDetector: { provider: 'gemini', model: '' },
  });
  
  // Routing chip & proposal simulation state
  const [routingStatus, setRoutingStatus] = useState<{
    isRouting: boolean;
    route?: 'specifier' | 'researcher' | 'optionizer' | 'gapDetector';
    reasoning?: string;
  }>({ isRouting: false });

  const [lastProposal, setLastProposal] = useState<ParsedProposal | undefined>(undefined);

  // 1. Fetch initial data on mount
  useEffect(() => {
    fetchMindmap();
    fetchSettings();
  }, []);

  const fetchSettings = async () => {
    try {
      const res = await fetch('/api/settings');
      if (res.ok) {
        const data = await res.json();
        setSettings(data);
        setFormProvider(data.provider);
        setFormModel(data.model);
        if (data.agents) {
          setFormAgents(data.agents);
        } else {
          setFormAgents({
            director: { provider: data.provider, model: data.model },
            specifier: { provider: data.provider, model: data.model },
            researcher: { provider: data.provider, model: data.model },
            optionizer: { provider: data.provider, model: data.model },
            gapDetector: { provider: data.provider, model: data.model },
          });
        }
      }
    } catch (e) {
      console.error('Error fetching settings:', e);
    }
  };

  const fetchMindmap = async () => {
    try {
      const res = await fetch('/api/mindmap');
      if (!res.ok) throw new Error('Failed to fetch mindmap');
      const data = await res.json();
      const loadedNodes = data.nodes || [];
      setNodes(loadedNodes);
      setEdges(data.edges || []);
      setMessages(data.messages || []);
      if (loadedNodes.length === 0) {
        setShowOnboardingModal(true);
      }
    } catch (e) {
      console.error('Error fetching mindmap data:', e);
    }
  };

  const handleCreateSeed = async (title: string, body: string) => {
    setIsInitializing(true);
    try {
      const now = new Date().toISOString();
      const seedNodeId = crypto.randomUUID();
      const seedNode: GraphNode = {
        id: seedNodeId,
        kind: 'seed',
        status: 'decided',
        branchRole: 'mainline',
        title,
        body,
        position: { x: 250, y: 250 },
        createdAt: now,
        updatedAt: now,
      };

      const initialNodes = [seedNode];
      const initialEdges: GraphEdge[] = [];
      const initialMessages: NodeMessage[] = [];

      // Save initial seed to the server
      const saveRes = await fetch('/api/mindmap', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          nodes: initialNodes,
          edges: initialEdges,
          messages: initialMessages,
          userProfile: {
            name: 'Designer',
            title: 'Product Creator',
            bio: body,
          },
        }),
      });

      if (!saveRes.ok) throw new Error('Failed to create seed node');

      // Set state locally so user sees the seed node immediately
      setNodes(initialNodes);
      setEdges(initialEdges);
      setMessages(initialMessages);
      setSelectedNodeId(seedNodeId);

      // Now trigger the automatic brainstorming chat query
      setRoutingStatus({ isRouting: true });

      const chatRes = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          nodeId: seedNodeId,
          message: `새로운 프로젝트를 시작했습니다. 다음 기획서의 내용을 바탕으로, 가장 먼저 논의해야 할 3가지 서로 다른 핵심 대안 노드를 제안해 주세요. 대안들은 반드시 세 개(3개)여야 하며, 'optionBranches' 코드 블록 형식으로 제목(title)과 요약(body)을 반환해 주십시오.`
        }),
      });

      if (!chatRes.ok) throw new Error('API server returned error during initial brainstorm');
      const data = await chatRes.json();

      setRoutingStatus({
        isRouting: false,
        route: data.route,
        reasoning: data.reasoning,
      });

      let currentNodes = data.mindmap.nodes || [];
      let currentEdges = data.mindmap.edges || [];
      const currentMessages = data.mindmap.messages || [];

      if (data.proposal && data.proposal.type === 'branches') {
        const proposals = data.proposal.proposals;
        const startY = seedNode.position.y - ((proposals.length - 1) * 120);
        const sproutedNodes: GraphNode[] = proposals.map((prop: any, idx: number) => ({
          id: crypto.randomUUID(),
          kind: 'option',
          status: 'pending',
          branchRole: 'candidate',
          title: prop.title,
          body: prop.body,
          position: { x: seedNode.position.x + 380, y: startY + (idx * 240) },
          createdAt: now,
          updatedAt: now,
        }));

        const sproutedEdges: GraphEdge[] = sproutedNodes.map((prop) => ({
          id: crypto.randomUUID(),
          fromNodeId: seedNodeId,
          toNodeId: prop.id,
          kind: 'parentChild',
          createdAt: now,
        }));

        currentNodes = [...currentNodes, ...sproutedNodes];
        currentEdges = [...currentEdges, ...sproutedEdges];

        // Save sprouted state to server
        await fetch('/api/mindmap', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            nodes: currentNodes,
            edges: currentEdges,
            messages: currentMessages,
            userProfile: {
              name: 'Designer',
              title: 'Product Creator',
              bio: body,
            },
          }),
        });
      }

      setNodes(currentNodes);
      setEdges(currentEdges);
      setMessages(currentMessages);
      setSelectedNodeId(seedNodeId);
      setShowOnboardingModal(false);

    } catch (e) {
      console.error('Onboarding init error:', e);
      // Fallback
      setShowOnboardingModal(false);
    } finally {
      setIsInitializing(false);
    }
  };

  const handleSaveSettings = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const res = await fetch('/api/settings', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          provider: formProvider,
          model: formModel,
          agents: formAgents,
        }),
      });
      if (res.ok) {
        const data = await res.json();
        setSettings(data.settings);
        setShowSettingsModal(false);
      }
    } catch (e) {
      console.error('Error saving settings:', e);
    }
  };

  // 2. Focused Node Selection
  const handleSelectNode = (nodeId: string | null) => {
    setSelectedNodeId(nodeId);
    setLastProposal(undefined); // reset proposals on node switch
  };

  // 3. User Node Drag Sync
  const handleNodeDragStop = async (id: string, position: { x: number; y: number }) => {
    const updatedNodes = nodes.map((node) => {
      if (node.id === id) {
        return { ...node, position, updatedAt: new Date().toISOString() };
      }
      return node;
    });

    setNodes(updatedNodes);

    try {
      await fetch('/api/mindmap', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          nodes: updatedNodes,
          edges,
          messages,
        }),
      });
    } catch (e) {
      console.error('Failed to sync node position to local server', e);
    }
  };

  // 4. Send Chat message and handle agent drama routing
  const handleSendMessage = async (messageText: string) => {
    if (!selectedNodeId) return;
    setIsSending(true);
    setLastProposal(undefined);

    // Trigger routing stage animation
    setRoutingStatus({ isRouting: true });

    try {
      // Simulate Director routing classification delay for UX drama (0.8s)
      await new Promise((resolve) => setTimeout(resolve, 800));

      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ nodeId: selectedNodeId, message: messageText }),
      });

      if (!res.ok) throw new Error('API server returned error');
      const data = await res.json();

      // Routing finished, show which step agent responded
      setRoutingStatus({
        isRouting: false,
        route: data.route,
        reasoning: data.reasoning,
      });

      // Update state
      setNodes(data.mindmap.nodes);
      setEdges(data.mindmap.edges);
      setMessages(data.mindmap.messages);

      // Check if the agent proposed sub-nodes or alternatives
      if (data.proposal && data.proposal.type !== 'none') {
        setLastProposal(data.proposal);
      }
    } catch (e) {
      console.error('Chat error:', e);
      setRoutingStatus({ isRouting: false });
    } finally {
      setIsSending(false);
    }
  };

  // 5. Adopt Node or Create Proposed branch
  const handleAdoptNode = async (adoptedId: string) => {
    if (!selectedNodeId) return;

    // Check if adoptedId is serialized JSON proposal from Step Agents
    if (adoptedId.startsWith('{')) {
      try {
        const parsed = JSON.parse(adoptedId);
        const now = new Date().toISOString();
        const parentNode = nodes.find(n => n.id === selectedNodeId);
        if (!parentNode) return;

        let newNodes: GraphNode[] = [];
        let newEdges: GraphEdge[] = [];

        if (parsed.type === 'child') {
          // Drill-down child node
          const newId = crypto.randomUUID();
          const childNode: GraphNode = {
            id: newId,
            kind: 'free',
            status: 'pending',
            branchRole: 'mainline',
            title: parsed.proposal.title,
            body: parsed.proposal.body,
            position: { x: parentNode.position.x + 380, y: parentNode.position.y },
            createdAt: now,
            updatedAt: now,
          };
          newNodes = [...nodes, childNode];
          newEdges = [...edges, {
            id: crypto.randomUUID(),
            fromNodeId: selectedNodeId,
            toNodeId: newId,
            kind: 'parentChild',
            createdAt: now,
          }];
        } else if (parsed.type === 'single-branch') {
          // Branching candidate
          const newId = crypto.randomUUID();
          const candidateNode: GraphNode = {
            id: newId,
            kind: 'option',
            status: 'pending',
            branchRole: 'candidate',
            title: parsed.proposal.title,
            body: parsed.proposal.body,
            position: { x: parentNode.position.x + 380, y: parentNode.position.y + (nodes.filter(n => n.kind === 'option').length * 240) - 240 },
            createdAt: now,
            updatedAt: now,
          };
          newNodes = [...nodes, candidateNode];
          newEdges = [...edges, {
            id: crypto.randomUUID(),
            fromNodeId: selectedNodeId,
            toNodeId: newId,
            kind: 'parentChild',
            createdAt: now,
          }];
        } else if (parsed.type === 'branches') {
          // Multiple branches proposed
          const startY = parentNode.position.y - ((parsed.proposals.length - 1) * 120);
          const proposals: GraphNode[] = parsed.proposals.map((prop: any, idx: number) => ({
            id: crypto.randomUUID(),
            kind: 'option',
            status: 'pending',
            branchRole: 'candidate',
            title: prop.title,
            body: prop.body,
            position: { x: parentNode.position.x + 380, y: startY + (idx * 240) },
            createdAt: now,
            updatedAt: now,
          }));

          newNodes = [...nodes, ...proposals];
          
          const newProposalsEdges: GraphEdge[] = proposals.map((prop) => ({
            id: crypto.randomUUID(),
            fromNodeId: selectedNodeId,
            toNodeId: prop.id,
            kind: 'parentChild',
            createdAt: now,
          }));
          newEdges = [...edges, ...newProposalsEdges];
        }

        // Save updated local map
        setNodes(newNodes);
        setEdges(newEdges);
        setLastProposal(undefined);

        await fetch('/api/mindmap', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ nodes: newNodes, edges: newEdges, messages }),
        });

      } catch (e) {
        console.error('Failed to create proposed nodes:', e);
      }
      return;
    }

    // Otherwise, adopt existing Candidate Node in canvas
    try {
      const nodeToAdopt = nodes.find(n => n.id === adoptedId);
      if (!nodeToAdopt) return;

      // Find siblings
      const parentEdge = edges.find(e => e.toNodeId === adoptedId && e.kind === 'parentChild');
      const parentNodeId = parentEdge ? parentEdge.fromNodeId : selectedNodeId;

      const siblingEdges = edges.filter(e => e.fromNodeId === parentNodeId && e.kind === 'parentChild');
      const siblingNodeIds = siblingEdges.map(e => e.toNodeId).filter(id => id !== adoptedId);

      const res = await fetch('/api/adopt', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          parentNodeId,
          adoptedNodeId: adoptedId,
          siblingNodeIds,
        }),
      });

      if (!res.ok) throw new Error('Adopt request failed');
      const data = await res.json();
      
      setNodes(data.mindmap.nodes);
      setEdges(data.mindmap.edges);
      setMessages(data.mindmap.messages);
      
      // Auto focus on the newly adopted mainline node
      setSelectedNodeId(adoptedId);
      setLastProposal(undefined);
    } catch (e) {
      console.error('Failed to adopt node:', e);
    }
  };

  // 6. Merge candidate sibling options
  const handleMergeNodes = async (candidateIds: string[]) => {
    if (!selectedNodeId) return;

    try {
      const res = await fetch('/api/merge', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          parentNodeId: selectedNodeId,
          candidateIds,
        }),
      });

      if (!res.ok) throw new Error('Merge request failed');
      const data = await res.json();

      setNodes(data.mindmap.nodes);
      setEdges(data.mindmap.edges);
      setMessages(data.mindmap.messages);
      
      // Auto focus on newly merged mainline node
      setSelectedNodeId(data.mergedNode.id);
      setLastProposal(undefined);
    } catch (e) {
      console.error('Failed to merge nodes:', e);
    }
  };

  // 7. Manual Add Free node
  const handleAddFreeNode = async () => {
    const now = new Date().toISOString();
    const newId = crypto.randomUUID();
    const rootNode = nodes.find(n => n.kind === 'seed') || nodes[0];
    
    const freeNode: GraphNode = {
      id: newId,
      kind: 'free',
      status: 'pending',
      branchRole: 'mainline',
      title: '새로운 기획 주제',
      body: '아이디어의 핵심 내용을 기술하세요.',
      position: {
        x: rootNode ? rootNode.position.x + 380 : 250,
        y: rootNode ? rootNode.position.y + 120 : 200,
      },
      createdAt: now,
      updatedAt: now,
    };

    const newNodes = [...nodes, freeNode];
    let newEdges = [...edges];

    // If root exists, link it
    if (rootNode) {
      newEdges.push({
        id: crypto.randomUUID(),
        fromNodeId: rootNode.id,
        toNodeId: newId,
        kind: 'parentChild',
        createdAt: now,
      });
    }

    setNodes(newNodes);
    setEdges(newEdges);

    try {
      await fetch('/api/mindmap', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ nodes: newNodes, edges: newEdges, messages }),
      });
    } catch (e) {
      console.error('Failed to create manual node', e);
    }
  };

  // 8. Compile Spec to Markdown File
  const handleCompileSpec = async () => {
    setIsCompiling(true);
    setCompileResult(null);

    try {
      const res = await fetch('/api/compile', { method: 'POST' });
      if (!res.ok) throw new Error('Compile failed');
      const data = await res.json();
      
      setCompileResult({
        success: data.success,
        filePath: data.filePath,
      });

      // Auto dismiss success toast after 4s
      setTimeout(() => setCompileResult(null), 4000);
    } catch (e) {
      console.error('Compile error:', e);
    } finally {
      setIsCompiling(false);
    }
  };

  // 9. Fetch and display Decision Logs (Criteria Modal)
  const handleViewDecisionLogs = async () => {
    try {
      const res = await fetch('/api/criteria');
      const data = await res.json();
      setCriteriaMarkdown(data.markdown || '# No decision criteria found.');
      setShowLogModal(true);
    } catch (e) {
      console.error('Criteria log loading error:', e);
    }
  };

  // 10. Update Node Title/Body Local Handler
  const handleUpdateNode = async (updatedNode: GraphNode) => {
    const updatedNodes = nodes.map(n => n.id === updatedNode.id ? updatedNode : n);
    setNodes(updatedNodes);

    try {
      await fetch('/api/mindmap', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ nodes: updatedNodes, edges, messages }),
      });
    } catch (e) {
      console.error('Failed to save edited node content', e);
    }
  };

  // Extract variables for focused node details panel
  const focusedNode = useMemo(() => {
    return nodes.find(n => n.id === selectedNodeId) || null;
  }, [nodes, selectedNodeId]);

  const focusedMessages = useMemo(() => {
    if (!selectedNodeId) return [];
    return messages.filter(m => m.nodeId === selectedNodeId);
  }, [messages, selectedNodeId]);

  // Find siblings of the selected node that are candidates
  const currentNodeCandidates = useMemo(() => {
    if (!selectedNodeId || !focusedNode || focusedNode.branchRole === 'candidate') return [];
    const parentEdge = edges.find(e => e.toNodeId === selectedNodeId && e.kind === 'parentChild');
    const parentNodeId = parentEdge ? parentEdge.fromNodeId : selectedNodeId;

    const siblingEdges = edges.filter(e => e.fromNodeId === parentNodeId && e.kind === 'parentChild');
    const siblingIds = siblingEdges.map(e => e.toNodeId).filter(id => id !== selectedNodeId);
    return nodes.filter(n => siblingIds.includes(n.id) && n.branchRole === 'candidate');
  }, [nodes, edges, selectedNodeId, focusedNode]);

  const seedNodeTitle = useMemo(() => {
    return nodes.find(n => n.kind === 'seed')?.title || 'LAO Studio';
  }, [nodes]);

  return (
    <div className="w-full h-screen flex flex-col bg-[#0b0d14]">
      
      {/* Header Bar */}
      <header className="h-14 border-b border-slate-900 bg-slate-950/80 backdrop-blur px-6 flex justify-between items-center z-10 shrink-0">
        <div className="flex items-center gap-2.5">
          <div className="w-7 h-7 rounded-lg bg-gradient-to-tr from-violet-600 to-indigo-600 flex items-center justify-center shadow-lg shadow-indigo-900/30">
            <Brain size={15} className="text-white" />
          </div>
          <div>
            <h1 className="text-sm font-semibold text-white tracking-wide m-0 leading-none">{seedNodeTitle}</h1>
            <span className="text-[9px] text-slate-500 font-medium">LAO 0.9 Mindmap Canvas</span>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {/* AI Settings button */}
          <button
            onClick={() => {
              setFormProvider(settings.provider);
              setFormModel(settings.model);
              if (settings.agents) {
                setFormAgents(settings.agents);
              }
              setActiveSettingsTab('global');
              setShowSettingsModal(true);
            }}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-slate-800 bg-slate-900/50 hover:bg-slate-800 text-[11px] font-semibold text-slate-300 transition-colors cursor-pointer"
          >
            <Settings size={13} /> AI Settings
          </button>

          {/* View Decisions button */}
          <button
            onClick={handleViewDecisionLogs}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-slate-800 bg-slate-900/50 hover:bg-slate-800 text-[11px] font-semibold text-slate-300 transition-colors"
          >
            <BookOpen size={13} /> Decision Logs
          </button>

          {/* Export Spec Document Button */}
          <button
            onClick={handleCompileSpec}
            disabled={isCompiling}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-violet-600 hover:bg-violet-500 disabled:bg-slate-800 text-[11px] font-bold text-white transition-colors cursor-pointer"
          >
            <FileText size={13} /> {isCompiling ? 'Compiling...' : 'Compile Spec'}
          </button>
        </div>
      </header>

      {/* Main Layout Area */}
      <div className="flex-1 flex min-h-0 relative">
        
        {/* React Flow Mindmap Canvas */}
        <MindmapCanvas
          nodes={nodes}
          edges={edges}
          selectedNodeId={selectedNodeId}
          onSelectNode={handleSelectNode}
          onNodeDragStop={handleNodeDragStop}
          onAddFreeNode={handleAddFreeNode}
        />

        {/* Focused Node Side Panel */}
        {focusedNode && (
          <NodeDetailPanel
            node={focusedNode}
            messages={focusedMessages}
            candidates={currentNodeCandidates}
            onSendMessage={handleSendMessage}
            onAdoptNode={handleAdoptNode}
            onMergeNodes={handleMergeNodes}
            onUpdateNode={handleUpdateNode}
            isSending={isSending}
            routingStatus={routingStatus}
            lastProposal={lastProposal}
            onClearProposal={() => setLastProposal(undefined)}
          />
        )}

        {/* Compile Success Toast Notification */}
        {compileResult && (
          <div className="absolute bottom-6 left-6 max-w-sm bg-slate-900 border border-emerald-500/30 rounded-lg p-4 shadow-2xl z-50 flex gap-3 animate-slide-in">
            <div className="w-6 h-6 rounded-full bg-emerald-950 flex items-center justify-center shrink-0">
              <Check size={14} className="text-emerald-400" />
            </div>
            <div>
              <h4 className="text-xs font-semibold text-white">Specification Compiled!</h4>
              <p className="text-[10px] text-slate-400 mt-0.5 leading-normal">
                설계서가 `.lao/spec_compiled.md`로 컴파일되었습니다. Claude Code에 바로 전달할 수 있습니다.
              </p>
            </div>
          </div>
        )}
      </div>

      {/* Decision Log Modal */}
      {showLogModal && (
        <div className="fixed inset-0 bg-slate-950/70 backdrop-blur-sm flex items-center justify-center z-50 p-4">
          <div className="w-full max-w-2xl bg-slate-900 border border-slate-800 rounded-xl flex flex-col max-h-[80vh] shadow-2xl">
            <div className="p-5 border-b border-slate-800 flex justify-between items-center">
              <h3 className="text-sm font-bold text-white flex items-center gap-2">
                <BookOpen size={16} className="text-violet-400" /> Accumulated Decision Criteria Log
              </h3>
              <button
                onClick={() => setShowLogModal(false)}
                className="text-xs text-slate-500 hover:text-slate-300"
              >
                Close
              </button>
            </div>
            <div className="flex-1 overflow-y-auto p-6 text-xs text-slate-300 leading-relaxed font-mono whitespace-pre-wrap">
              {criteriaMarkdown}
            </div>
          </div>
        </div>
      )}

      {/* Onboarding Seed Creation Modal */}
      {showOnboardingModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-md p-4 animate-fade-in">
          <div className="relative w-full max-w-md overflow-hidden rounded-2xl border border-slate-800 bg-slate-900/90 p-8 shadow-2xl backdrop-blur-xl transition-all duration-300">
            {/* Ambient gradients */}
            <div className="absolute -top-20 -left-20 w-44 h-44 rounded-full bg-violet-600/10 blur-3xl pointer-events-none"></div>
            <div className="absolute -bottom-20 -right-20 w-44 h-44 rounded-full bg-indigo-600/10 blur-3xl pointer-events-none"></div>

            {/* Modal Header */}
            <div className="relative mb-6 text-center">
              <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-tr from-violet-600 to-indigo-600 shadow-lg shadow-indigo-500/30">
                <Brain className="h-6 w-6 text-white animate-pulse" />
              </div>
              <h2 className="text-lg font-bold text-white tracking-wide">Create Project Seed</h2>
              <p className="mt-1 text-xs text-slate-400">
                새로운 기획 설계를 위한 시드 노드를 생성합니다.<br />
                제출하면 AI 참모들이 즉시 3가지 아이디어를 제안합니다.
              </p>
            </div>

            {/* Modal Body / Form */}
            {isInitializing ? (
              <div className="flex flex-col items-center justify-center py-8 space-y-4">
                <div className="relative flex items-center justify-center">
                  <div className="h-10 w-10 rounded-full border-4 border-slate-800 border-t-violet-500 animate-spin"></div>
                  <Brain className="absolute h-4 w-4 text-indigo-400 animate-pulse" />
                </div>
                <div className="text-center">
                  <p className="text-xs font-semibold text-white">AI 참모들 브레인스토밍 중...</p>
                  <p className="text-[10px] text-slate-500 mt-1">로컬 LLM이 프로젝트 시드에 달 수 있는 3가지 대안을 구상하고 있습니다.</p>
                </div>
              </div>
            ) : (
              <form
                onSubmit={async (e) => {
                  e.preventDefault();
                  if (seedTitle.trim() && seedBody.trim()) {
                    try {
                      await fetch('/api/settings', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                          provider: formProvider,
                          model: formModel,
                          agents: formAgents,
                        }),
                      });
                      setSettings({
                        provider: formProvider,
                        model: formModel,
                        agents: formAgents,
                      });
                    } catch (err) {
                      console.error('Error saving onboarding settings:', err);
                    }
                    handleCreateSeed(seedTitle.trim(), seedBody.trim());
                  }
                }}
                className="space-y-4 relative"
              >
                <div>
                  <label htmlFor="seedTitle" className="block text-[10px] font-bold uppercase tracking-wider text-slate-400 mb-1.5">
                    Project Name (Seed Title)
                  </label>
                  <input
                    type="text"
                    id="seedTitle"
                    value={seedTitle}
                    onChange={(e) => setSeedTitle(e.target.value)}
                    placeholder="예: AI 개인 비서 서비스 기획"
                    required
                    className="w-full px-3.5 py-2 rounded-lg border border-slate-800 bg-slate-950/60 text-xs text-white placeholder-slate-500 outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500/30 transition-all"
                  />
                </div>

                <div>
                  <label htmlFor="seedBody" className="block text-[10px] font-bold uppercase tracking-wider text-slate-400 mb-1.5">
                    Core Idea (Description)
                  </label>
                  <textarea
                    id="seedBody"
                    value={seedBody}
                    onChange={(e) => setSeedBody(e.target.value)}
                    placeholder="기획의 핵심 개념, 타겟 사용자, 해결하려는 문제 등을 간단히 작성해주세요."
                    required
                    rows={4}
                    className="w-full px-3.5 py-2 rounded-lg border border-slate-800 bg-slate-950/60 text-xs text-white placeholder-slate-500 outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500/30 transition-all resize-none"
                  />
                </div>

                {/* AI Settings Section (Collapsible) */}
                <div className="border border-slate-800 rounded-lg overflow-hidden bg-slate-950/20">
                  <button
                    type="button"
                    onClick={() => setShowOnboardingSettings(!showOnboardingSettings)}
                    className="w-full px-3.5 py-2.5 flex items-center justify-between text-left text-[10px] font-bold uppercase tracking-wider text-slate-400 hover:bg-slate-800/50 transition-colors cursor-pointer"
                  >
                    <span className="flex items-center gap-1.5">
                      <Settings size={12} className="text-violet-400" />
                      Configure AI CLI Settings (Recommended)
                    </span>
                    <span className="text-[9px] text-slate-500 font-semibold lowercase">
                      {showOnboardingSettings ? 'hide' : 'show'}
                    </span>
                  </button>

                  {showOnboardingSettings && (
                    <div className="p-3.5 border-t border-slate-800 bg-slate-950/40 space-y-3 animate-fade-in">
                      <div>
                        <label htmlFor="onboardProvider" className="block text-[9px] font-bold uppercase tracking-wider text-slate-500 mb-1">
                          Default Provider
                        </label>
                        <select
                          id="onboardProvider"
                          value={formProvider}
                          onChange={(e) => {
                            const val = e.target.value;
                            setFormProvider(val);
                            // Also sync formAgents providers as default fallback
                            setFormAgents(prev => {
                              const updated = { ...prev };
                              for (const key in updated) {
                                (updated as any)[key].provider = val;
                              }
                              return updated;
                            });
                          }}
                          className="w-full px-2.5 py-1.5 rounded-lg border border-slate-800 bg-slate-950 text-[11px] text-white outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500/30 transition-all cursor-pointer"
                        >
                          <option value="gemini">Gemini (CLI)</option>
                          <option value="claude">Claude (CLI)</option>
                          <option value="codex">Codex (CLI)</option>
                        </select>
                      </div>

                      <div>
                        <label htmlFor="onboardModel" className="block text-[9px] font-bold uppercase tracking-wider text-slate-500 mb-1">
                          Model Override (Optional)
                        </label>
                        <input
                          type="text"
                          id="onboardModel"
                          value={formModel}
                          onChange={(e) => setFormModel(e.target.value)}
                          placeholder="e.g. gemini-2.5-pro (empty for auto)"
                          className="w-full px-2.5 py-1.5 rounded-lg border border-slate-800 bg-slate-950 text-[11px] text-white placeholder-slate-700 outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500/30 transition-all"
                        />
                      </div>
                      
                      <p className="text-[9px] text-slate-500 leading-normal">
                        로컬 CLI 도구 및 오버라이드 모델을 기획 시작 전에 미리 설정할 수 있습니다. 각 에이전트별 세부 설정(Overrides)은 기획 시작 후 우측 상단 'AI Settings' 버튼을 통해 더욱 자세히 제어할 수 있습니다.
                      </p>
                    </div>
                  )}
                </div>

                <div className="pt-2">
                  <button
                    type="submit"
                    className="w-full py-2.5 rounded-lg bg-gradient-to-r from-violet-600 to-indigo-600 hover:from-violet-500 hover:to-indigo-500 text-white text-xs font-bold tracking-wider uppercase transition-all shadow-lg hover:shadow-indigo-500/20 active:scale-[0.98] cursor-pointer flex items-center justify-center gap-2"
                  >
                    <Plus size={14} /> Start Project
                  </button>
                </div>
              </form>
            )}
          </div>
        </div>
      )}

      {/* AI Settings Modal */}
      {showSettingsModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-md p-4 animate-fade-in">
          <div className="relative w-full max-w-lg overflow-hidden rounded-2xl border border-slate-800 bg-slate-900/90 p-8 shadow-2xl backdrop-blur-xl transition-all duration-300">
            {/* Ambient gradients */}
            <div className="absolute -top-20 -left-20 w-44 h-44 rounded-full bg-violet-600/10 blur-3xl pointer-events-none"></div>
            <div className="absolute -bottom-20 -right-20 w-44 h-44 rounded-full bg-indigo-600/10 blur-3xl pointer-events-none"></div>

            {/* Modal Header */}
            <div className="relative mb-6 flex items-center justify-between">
              <h2 className="text-sm font-bold text-white flex items-center gap-2">
                <Settings size={16} className="text-violet-400" /> Local AI CLI Settings
              </h2>
              <button
                onClick={() => setShowSettingsModal(false)}
                className="text-xs text-slate-500 hover:text-slate-300 cursor-pointer"
              >
                Close
              </button>
            </div>

            {/* Modal Body / Form */}
            <form onSubmit={handleSaveSettings} className="space-y-4 relative">
              {/* Tabs */}
              <div className="flex border-b border-slate-800 mb-5 relative z-10">
                <button
                  type="button"
                  onClick={() => setActiveSettingsTab('global')}
                  className={`flex-1 pb-2.5 text-[11px] font-bold uppercase tracking-wider transition-all cursor-pointer text-center ${
                    activeSettingsTab === 'global'
                      ? 'text-violet-400 border-b-2 border-violet-500'
                      : 'text-slate-500 hover:text-slate-350'
                  }`}
                >
                  Global Default
                </button>
                <button
                  type="button"
                  onClick={() => setActiveSettingsTab('agents')}
                  className={`flex-1 pb-2.5 text-[11px] font-bold uppercase tracking-wider transition-all cursor-pointer text-center ${
                    activeSettingsTab === 'agents'
                      ? 'text-violet-400 border-b-2 border-violet-500'
                      : 'text-slate-500 hover:text-slate-355'
                  }`}
                >
                  Agent Overrides
                </button>
              </div>

              {activeSettingsTab === 'global' && (
                <div className="space-y-4 animate-fade-in">
                  <div>
                    <label htmlFor="provider" className="block text-[10px] font-bold uppercase tracking-wider text-slate-400 mb-1.5">
                      Global Default Provider
                    </label>
                    <select
                      id="provider"
                      value={formProvider}
                      onChange={(e) => setFormProvider(e.target.value)}
                      className="w-full px-3.5 py-2.5 rounded-lg border border-slate-800 bg-slate-950 text-xs text-white outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500/30 transition-all cursor-pointer"
                    >
                      <option value="gemini">Gemini (CLI)</option>
                      <option value="claude">Claude (CLI)</option>
                      <option value="codex">Codex (CLI)</option>
                    </select>
                  </div>

                  <div>
                    <label htmlFor="model" className="block text-[10px] font-bold uppercase tracking-wider text-slate-400 mb-1.5">
                      Global Model Override (Optional)
                    </label>
                    <input
                      type="text"
                      id="model"
                      value={formModel}
                      onChange={(e) => setFormModel(e.target.value)}
                      placeholder="예: gemini-2.5-pro (비워두면 auto 기본값 사용)"
                      className="w-full px-3.5 py-2.5 rounded-lg border border-slate-800 bg-slate-950/60 text-xs text-white placeholder-slate-600 outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500/30 transition-all"
                    />
                    <p className="text-[9px] text-slate-500 mt-1 leading-normal">
                      공란으로 비워두시면 각 로컬 CLI 도구가 권장하는 최적의 기본 모델(`auto`)을 사용하게 됩니다.
                    </p>
                  </div>
                </div>
              )}

              {activeSettingsTab === 'agents' && (
                <div className="space-y-3 max-h-[300px] overflow-y-auto pr-1 animate-fade-in scrollbar-thin">
                  {([
                    { key: 'director', label: 'Director (Routing & Merge)' },
                    { key: 'specifier', label: 'Specifier Agent' },
                    { key: 'researcher', label: 'Researcher Agent' },
                    { key: 'optionizer', label: 'Optionizer Agent' },
                    { key: 'gapDetector', label: 'Gap Detector Agent' }
                  ] as const).map(({ key, label }) => (
                    <div key={key} className="p-3.5 rounded-xl border border-slate-800/80 bg-slate-950/40 space-y-2.5">
                      <div className="flex justify-between items-center">
                        <span className="text-[10px] font-bold text-violet-300 uppercase tracking-wider">{label}</span>
                      </div>
                      <div className="grid grid-cols-2 gap-2.5">
                        <div>
                          <select
                            value={formAgents[key]?.provider || 'gemini'}
                            onChange={(e) => setFormAgents({
                              ...formAgents,
                              [key]: { ...formAgents[key], provider: e.target.value }
                            })}
                            className="w-full px-2.5 py-1.5 rounded-lg border border-slate-800 bg-slate-950 text-[11px] text-white outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500/30 transition-all cursor-pointer"
                          >
                            <option value="gemini">Gemini</option>
                            <option value="claude">Claude</option>
                            <option value="codex">Codex</option>
                          </select>
                        </div>
                        <div>
                          <input
                            type="text"
                            value={formAgents[key]?.model || ''}
                            onChange={(e) => setFormAgents({
                              ...formAgents,
                              [key]: { ...formAgents[key], model: e.target.value }
                            })}
                            placeholder="Model override"
                            className="w-full px-2.5 py-1.5 rounded-lg border border-slate-800 bg-slate-950 text-[11px] text-white placeholder-slate-700 outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500/30 transition-all"
                          />
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}

              <div className="pt-2 flex gap-2">
                <button
                  type="button"
                  onClick={() => setShowSettingsModal(false)}
                  className="flex-1 py-2 rounded-lg border border-slate-800 hover:bg-slate-800 text-slate-300 text-xs font-semibold tracking-wider transition-all cursor-pointer text-center"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="flex-1 py-2 rounded-lg bg-gradient-to-r from-violet-600 to-indigo-600 hover:from-violet-500 hover:to-indigo-500 text-white text-xs font-bold tracking-wider uppercase transition-all shadow-lg hover:shadow-indigo-500/20 active:scale-[0.98] cursor-pointer text-center"
                >
                  Save Settings
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
