import { useState, useEffect, useMemo, useRef } from 'react';
import { MindmapCanvas } from './components/MindmapCanvas';
import { NodeDetailPanel } from './components/NodeDetailPanel';
import type { GraphNode, GraphEdge, NodeMessage, ParsedProposal } from './types';
import { Brain, FileText, BookOpen, Check, Plus, Settings, AlertCircle, Menu, X, HelpCircle, ShieldCheck } from 'lucide-react';

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
  const [errorToast, setErrorToast] = useState<{ message: string; type: string } | null>(null);
  const activeEventSourceRef = useRef<EventSource | null>(null);

  // Responsive / Onboarding States
  const [isSidebarOpen, setIsSidebarOpen] = useState(true);
  const [showHelpModal, setShowHelpModal] = useState(false);
  const [showHeaderMenu, setShowHeaderMenu] = useState(false);
  
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
  const [activeSettingsTab, setActiveSettingsTab] = useState<'global' | 'agents' | 'devloop'>('global');
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

  // Right sidebar tab state
  const [activePanelTab, setActivePanelTab] = useState<'detail' | 'timeline' | 'spec' | 'devloop'>('detail');

  // Decision Timeline States
  const [decisionLogs, setDecisionLogs] = useState<{ date: string; title: string; reasoning: string }[]>([]);
  const [isLoadingDecisions, setIsLoadingDecisions] = useState(false);

  // Spec Viewer States
  const [specMarkdown, setSpecMarkdown] = useState('');
  const [isLoadingSpec, setIsLoadingSpec] = useState(false);

  // DevLoop Console States
  const [devLoopLogs, setDevLoopLogs] = useState<{ type: 'stdout' | 'stderr' | 'info' | 'start' | 'exit' | 'error'; text: string }[]>([]);
  const [activeDevLoopCommand, setActiveDevLoopCommand] = useState<string | null>(null);
  const [formBuildCommand, setFormBuildCommand] = useState('npm run build');
  const [formLaunchCommand, setFormLaunchCommand] = useState('npm start');
  const [formVerifyCommand, setFormVerifyCommand] = useState('npm test');
  const [formUiCheckCommand, setFormUiCheckCommand] = useState('');
  
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

  // Auto-dismiss error toast
  useEffect(() => {
    if (errorToast) {
      const timer = setTimeout(() => setErrorToast(null), 6000);
      return () => clearTimeout(timer);
    }
  }, [errorToast]);

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
        if (data.developerLoop) {
          setFormBuildCommand(data.developerLoop.buildCommand || 'npm run build');
          setFormLaunchCommand(data.developerLoop.launchCommand || 'npm start');
          setFormVerifyCommand(data.developerLoop.verifyCommand || 'npm test');
          setFormUiCheckCommand(data.developerLoop.uiCheckCommand || '');
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
          developerLoop: {
            buildCommand: formBuildCommand,
            launchCommand: formLaunchCommand,
            verifyCommand: formVerifyCommand,
            uiCheckCommand: formUiCheckCommand,
          }
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

  // 4. Send Chat message and handle agent drama routing (Streaming SSE)
  const handleSendMessage = async (messageText: string) => {
    if (!selectedNodeId) return;
    setIsSending(true);
    setLastProposal(undefined);

    // Append user message locally first for instant feedback
    const tempUserMsgId = crypto.randomUUID();
    const userMsg: NodeMessage = {
      id: tempUserMsgId,
      nodeId: selectedNodeId,
      author: 'user',
      content: messageText,
      createdAt: new Date().toISOString(),
    };
    setMessages((prev) => [...prev, userMsg]);

    // Trigger routing stage animation
    setRoutingStatus({ isRouting: true });

    let tempAgentMsgId = crypto.randomUUID();
    let currentAgentText = '';
    
    const url = `/api/chat/stream?nodeId=${encodeURIComponent(selectedNodeId)}&message=${encodeURIComponent(messageText)}`;
    const eventSource = new EventSource(url);
    activeEventSourceRef.current = eventSource;

    eventSource.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === 'routing') {
          setRoutingStatus({
            isRouting: false,
            route: data.route,
            reasoning: data.reasoning,
          });
          
          // Append the agent typing message
          const initialAgentMsg: NodeMessage = {
            id: tempAgentMsgId,
            nodeId: selectedNodeId,
            author: data.route,
            content: '',
            createdAt: new Date().toISOString(),
          };
          setMessages((prev) => [...prev, initialAgentMsg]);
        } else if (data.type === 'content') {
          currentAgentText += data.chunk;
          setMessages((prev) =>
            prev.map((msg) =>
              msg.id === tempAgentMsgId ? { ...msg, content: currentAgentText } : msg
            )
          );
        } else if (data.type === 'done') {
          eventSource.close();
          activeEventSourceRef.current = null;
          setNodes(data.mindmap.nodes);
          setEdges(data.mindmap.edges);
          setMessages(data.mindmap.messages);
          if (data.proposal && data.proposal.type !== 'none') {
            setLastProposal(data.proposal);
          }
          setIsSending(false);
        } else if (data.type === 'error') {
          console.error('SSE backend error:', data.error);
          let userFriendlyMsg = data.error;
          if (data.error.includes('cli_not_found')) {
            userFriendlyMsg = '로컬 AI CLI 도구를 찾을 수 없습니다. 설치 상태 및 환경 변수(PATH)를 확인하십시오.';
          } else if (data.error.includes('auth_failed')) {
            userFriendlyMsg = '로컬 CLI 도구의 로그인 정보가 올바르지 않거나 유실되었습니다. 터미널에서 로그인을 확인해 주십시오.';
          }
          setErrorToast({ message: userFriendlyMsg, type: 'error' });
          eventSource.close();
          activeEventSourceRef.current = null;
          setRoutingStatus({ isRouting: false });
          setIsSending(false);
          // Remove local message on error
          setMessages((prev) => prev.filter(m => m.id !== tempUserMsgId && m.id !== tempAgentMsgId));
        }
      } catch (err) {
        console.error('SSE parse error:', err);
      }
    };

    eventSource.onerror = (err) => {
      console.error('EventSource error:', err);
      setErrorToast({ message: '로컬 서버와의 연결에 실패했거나 대화 처리 중 에러가 발생했습니다.', type: 'error' });
      eventSource.close();
      activeEventSourceRef.current = null;
      setRoutingStatus({ isRouting: false });
      setIsSending(false);
      // Remove local message on error
      setMessages((prev) => prev.filter(m => m.id !== tempUserMsgId && m.id !== tempAgentMsgId));
    };
  };

  // 4.5. Cancel Running AI Agent Chat Generation
  const handleCancelGeneration = async () => {
    if (!selectedNodeId) return;

    // Close the SSE stream immediately on the frontend
    if (activeEventSourceRef.current) {
      activeEventSourceRef.current.close();
      activeEventSourceRef.current = null;
    }

    setIsSending(false);
    setRoutingStatus({ isRouting: false });

    // Tell the backend to kill the spawned child process for this node
    try {
      await fetch('/api/chat/cancel', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ nodeId: selectedNodeId }),
      });
      setErrorToast({ message: 'AI 답변 생성이 중단되었습니다.', type: 'info' });
    } catch (e: any) {
      console.error('Failed to cancel generation:', e);
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

  // 9b. Fetch and parse decision logs for Timeline Card View
  const fetchDecisionLogs = async () => {
    setIsLoadingDecisions(true);
    try {
      const res = await fetch('/api/criteria');
      if (res.ok) {
        const data = await res.json();
        const md = data.markdown || '';
        const entries: { date: string; title: string; reasoning: string }[] = [];
        
        const sections = md.split('## [Decision] ');
        for (const sec of sections) {
          if (!sec.trim()) continue;
          const lines = sec.split('\n');
          const title = lines[0].trim();
          
          let date = '';
          let reasoning = '';
          
          for (const line of lines) {
            if (line.includes('**Date**:')) {
              date = line.replace(/- \*\*Date\*\*:\s*/, '').trim();
            } else if (line.includes('**Reasoning**:')) {
              reasoning = line.replace(/- \*\*Reasoning\*\*:\s*/, '').trim();
            }
          }
          
          if (!reasoning) {
            const reasonIdx = sec.indexOf('**Reasoning**:');
            if (reasonIdx !== -1) {
              reasoning = sec.substring(reasonIdx + 14).trim();
            }
          }

          entries.push({
            date: date || new Date().toISOString(),
            title,
            reasoning: reasoning || 'No reasoning details provided.',
          });
        }
        
        entries.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
        setDecisionLogs(entries);
      }
    } catch (e) {
      console.error('Error fetching criteria log:', e);
    } finally {
      setIsLoadingDecisions(false);
    }
  };

  // 9c. Fetch and compile spec document
  const fetchSpecText = async () => {
    setIsLoadingSpec(true);
    try {
      const compileRes = await fetch('/api/compile', { method: 'POST' });
      if (compileRes.ok) {
        const data = await compileRes.json();
        setSpecMarkdown(data.markdown || '');
      }
    } catch (e) {
      console.error('Error fetching spec document:', e);
    } finally {
      setIsLoadingSpec(false);
    }
  };

  // 9d. Copy Spec to Clipboard
  const handleCopySpec = () => {
    navigator.clipboard.writeText(specMarkdown);
    alert('Spec document copied to clipboard!');
  };

  // 9e. Download Spec Document
  const handleDownloadSpec = () => {
    const element = document.createElement("a");
    const file = new Blob([specMarkdown], {type: 'text/markdown'});
    element.href = URL.createObjectURL(file);
    element.download = "spec_compiled.md";
    document.body.appendChild(element);
    element.click();
    document.body.removeChild(element);
  };

  // 9f. Run DevLoop command via SSE
  const handleRunDevLoopCommand = (kind: 'build' | 'launch' | 'verify' | 'uiCheck') => {
    setActiveDevLoopCommand(kind);
    setDevLoopLogs([]);
    
    const url = `/api/devloop/run?kind=${kind}`;
    const eventSource = new EventSource(url);
    
    eventSource.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === 'start') {
          setDevLoopLogs([{ type: 'start', text: `> Running: ${data.command}` }]);
        } else if (data.type === 'stdout') {
          setDevLoopLogs((prev) => [...prev, { type: 'stdout', text: data.chunk }]);
        } else if (data.type === 'stderr') {
          setDevLoopLogs((prev) => [...prev, { type: 'stderr', text: data.chunk }]);
        } else if (data.type === 'exit') {
          setDevLoopLogs((prev) => [...prev, { type: 'exit', text: `\n> Command finished with exit code ${data.code}` }]);
          eventSource.close();
          setActiveDevLoopCommand(null);
        } else if (data.type === 'error') {
          setDevLoopLogs((prev) => [...prev, { type: 'error', text: `\n> Error: ${data.error}` }]);
          eventSource.close();
          setActiveDevLoopCommand(null);
        }
      } catch (err) {
        console.error('DevLoop SSE parse error:', err);
      }
    };
    
    eventSource.onerror = (err) => {
      console.error('DevLoop EventSource error:', err);
      setDevLoopLogs((prev) => [...prev, { type: 'error', text: `\n> EventSource connection closed.` }]);
      eventSource.close();
      setActiveDevLoopCommand(null);
    };
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

  // 11. Tab Switch & Collapsible Sidebar Handler (VS Code Style)
  const handleTabClick = (tab: 'detail' | 'timeline' | 'spec' | 'devloop') => {
    if (activePanelTab === tab && isSidebarOpen) {
      setIsSidebarOpen(false);
    } else {
      setIsSidebarOpen(true);
      setActivePanelTab(tab);
      if (tab === 'timeline') {
        fetchDecisionLogs();
      } else if (tab === 'spec') {
        fetchSpecText();
      }
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

  // Developer Handover Audit Calculations
  const handoverAudit = useMemo(() => {
    const hasCandidatesLeft = nodes.some(n => n.branchRole === 'candidate');
    const mainlineNodes = nodes.filter(n => n.branchRole === 'mainline' || n.kind === 'seed');
    const unelaboratedNodesCount = mainlineNodes.filter(node => !messages.some(m => m.nodeId === node.id)).length;
    const hasGapDetectorAudited = messages.some(m => m.author === 'gapDetector');
    
    let completedChecks = 0;
    if (!hasCandidatesLeft) completedChecks++;
    if (mainlineNodes.length > 0 && unelaboratedNodesCount === 0) completedChecks++;
    if (hasGapDetectorAudited) completedChecks++;
    const readinessPercentage = Math.round((completedChecks / 3) * 100);
    
    let progressColorClass = 'from-rose-500 to-amber-500';
    let statusText = '추가 설계 및 검수 필요';
    if (readinessPercentage >= 100) {
      progressColorClass = 'from-emerald-500 to-teal-500';
      statusText = '개발 인도 준비 완료!';
    } else if (readinessPercentage >= 50) {
      progressColorClass = 'from-violet-500 to-indigo-500';
      statusText = '기본 구체화 완료, 보완 필요';
    }

    return {
      hasCandidatesLeft,
      mainlineNodesCount: mainlineNodes.length,
      unelaboratedNodesCount,
      hasGapDetectorAudited,
      readinessPercentage,
      progressColorClass,
      statusText
    };
  }, [nodes, messages]);

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

        {/* Desktop Header Buttons (>= 768px) */}
        <div className="md:flex hidden items-center gap-2">
          {/* Help Guide button */}
          <button
            onClick={() => setShowHelpModal(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-slate-800 bg-slate-900/50 hover:bg-slate-800 text-[11px] font-semibold text-slate-300 hover:text-white transition-colors cursor-pointer"
          >
            <HelpCircle size={13} className="text-violet-400" /> Help Guide
          </button>

          {/* AI Settings button */}
          <button
            onClick={() => {
              setFormProvider(settings.provider);
              setFormModel(settings.model);
              if (settings.agents) {
                setFormAgents(settings.agents);
              }
              if (settings.developerLoop) {
                setFormBuildCommand(settings.developerLoop.buildCommand || 'npm run build');
                setFormLaunchCommand(settings.developerLoop.launchCommand || 'npm start');
                setFormVerifyCommand(settings.developerLoop.verifyCommand || 'npm test');
                setFormUiCheckCommand(settings.developerLoop.uiCheckCommand || '');
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
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-slate-800 bg-slate-900/50 hover:bg-slate-800 text-[11px] font-semibold text-slate-300 transition-colors cursor-pointer"
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

        {/* Mobile Header Menu Button (< 768px) */}
        <div className="md:hidden block relative">
          <button
            onClick={() => setShowHeaderMenu(!showHeaderMenu)}
            className="p-1.5 rounded-lg border border-slate-800 bg-slate-900/50 text-slate-300 hover:bg-slate-800 cursor-pointer"
          >
            {showHeaderMenu ? <X size={16} /> : <Menu size={16} />}
          </button>

          {/* Mobile Dropdown Menu */}
          {showHeaderMenu && (
            <div className="absolute right-0 mt-2 w-48 bg-slate-900 border border-slate-800 rounded-xl shadow-2xl p-2 z-50 flex flex-col gap-1 animate-fade-in">
              <button
                onClick={() => {
                  setShowHelpModal(true);
                  setShowHeaderMenu(false);
                }}
                className="w-full flex items-center gap-2 px-3 py-2 text-left rounded-lg text-xs font-semibold text-slate-300 hover:bg-slate-800 cursor-pointer"
              >
                <HelpCircle size={14} className="text-violet-400" /> Help Guide
              </button>
              
              <button
                onClick={() => {
                  setFormProvider(settings.provider);
                  setFormModel(settings.model);
                  if (settings.agents) {
                    setFormAgents(settings.agents);
                  }
                  if (settings.developerLoop) {
                    setFormBuildCommand(settings.developerLoop.buildCommand || 'npm run build');
                    setFormLaunchCommand(settings.developerLoop.launchCommand || 'npm start');
                    setFormVerifyCommand(settings.developerLoop.verifyCommand || 'npm test');
                    setFormUiCheckCommand(settings.developerLoop.uiCheckCommand || '');
                  }
                  setActiveSettingsTab('global');
                  setShowSettingsModal(true);
                  setShowHeaderMenu(false);
                }}
                className="w-full flex items-center gap-2 px-3 py-2 text-left rounded-lg text-xs font-semibold text-slate-300 hover:bg-slate-800 cursor-pointer"
              >
                <Settings size={14} /> AI Settings
              </button>

              <button
                onClick={() => {
                  handleViewDecisionLogs();
                  setShowHeaderMenu(false);
                }}
                className="w-full flex items-center gap-2 px-3 py-2 text-left rounded-lg text-xs font-semibold text-slate-300 hover:bg-slate-800 cursor-pointer"
              >
                <BookOpen size={14} /> Decision Logs
              </button>

              <button
                onClick={() => {
                  handleCompileSpec();
                  setShowHeaderMenu(false);
                }}
                disabled={isCompiling}
                className="w-full flex items-center gap-2 px-3 py-2 text-left rounded-lg text-xs font-bold text-violet-400 hover:bg-slate-800 disabled:opacity-50 cursor-pointer"
              >
                <FileText size={14} /> {isCompiling ? 'Compiling...' : 'Compile Spec'}
              </button>
            </div>
          )}
        </div>
      </header>

      {/* Main Layout Area */}
      <div className="flex-1 flex min-h-0 relative overflow-hidden">
        
        {/* React Flow Mindmap Canvas */}
        <MindmapCanvas
          nodes={nodes}
          edges={edges}
          selectedNodeId={selectedNodeId}
          onSelectNode={handleSelectNode}
          onNodeDragStop={handleNodeDragStop}
          onAddFreeNode={handleAddFreeNode}
        />

        {/* Collapsed Sidebar Menu Toggle Indicator for Mobile Overlay */}
        {!isSidebarOpen && (
          <button
            onClick={() => setIsSidebarOpen(true)}
            className="absolute top-4 right-4 z-20 p-2.5 rounded-xl border border-slate-800 bg-slate-900/90 text-violet-400 hover:text-violet-300 shadow-2xl cursor-pointer"
            title="상세 패널 열기"
          >
            <Brain size={16} className="animate-pulse" />
          </button>
        )}

        {/* Right Sidebar Container */}
        <div className={`border-l border-slate-800 bg-slate-900/40 backdrop-blur-xl flex min-h-0 z-10 shrink-0 transition-all duration-300 
          ${isSidebarOpen 
            ? 'md:w-[450px] w-[calc(100vw-3rem)] md:relative absolute right-0 top-0 h-full' 
            : 'w-12 md:relative absolute right-0 top-0 h-full'
          }`}
        >
          
          {/* Vertical Tab Bar (Left Edge of sidebar) */}
          <div className="w-12 border-r border-slate-800 bg-slate-950/40 flex flex-col items-center py-4 gap-4 shrink-0">
            <button
              onClick={() => handleTabClick('detail')}
              title="Node Detail"
              className={`p-2 rounded-lg transition-all cursor-pointer ${
                isSidebarOpen && activePanelTab === 'detail'
                  ? 'bg-violet-600/20 text-violet-400 border border-violet-500/30'
                  : 'text-slate-500 hover:text-slate-300'
              }`}
            >
              <Brain size={16} />
            </button>
            <button
              onClick={() => handleTabClick('timeline')}
              title="Decision Timeline"
              className={`p-2 rounded-lg transition-all cursor-pointer ${
                isSidebarOpen && activePanelTab === 'timeline'
                  ? 'bg-violet-600/20 text-violet-400 border border-violet-500/30'
                  : 'text-slate-500 hover:text-slate-300'
              }`}
            >
              <BookOpen size={16} />
            </button>
            <button
              onClick={() => handleTabClick('spec')}
              title="Specification Document"
              className={`p-2 rounded-lg transition-all cursor-pointer ${
                isSidebarOpen && activePanelTab === 'spec'
                  ? 'bg-violet-600/20 text-violet-400 border border-violet-500/30'
                  : 'text-slate-500 hover:text-slate-300'
              }`}
            >
              <FileText size={16} />
            </button>
            <button
              onClick={() => handleTabClick('devloop')}
              title="Developer Loop Console"
              className={`p-2 rounded-lg transition-all cursor-pointer ${
                isSidebarOpen && activePanelTab === 'devloop'
                  ? 'bg-violet-600/20 text-violet-400 border border-violet-500/30'
                  : 'text-slate-500 hover:text-slate-300'
              }`}
            >
              <Settings size={16} />
            </button>
          </div>

          {/* Panel Content Pane */}
          {isSidebarOpen && (
            <div className="flex-1 flex flex-col min-h-0 bg-slate-900/60 overflow-hidden">
            {activePanelTab === 'detail' && (
              focusedNode ? (
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
                  onCancelGeneration={handleCancelGeneration}
                />
              ) : (
                <div className="flex-1 flex flex-col items-center justify-center p-8 text-center text-slate-500 space-y-2">
                  <Brain size={32} className="text-slate-700 animate-pulse" />
                  <p className="text-xs font-semibold">노드 상세 정보</p>
                  <p className="text-[10px] text-slate-500 max-w-[200px]">캔버스에서 노드를 선택하시면 에이전트 대화 및 대안 관리 패널이 활성화됩니다.</p>
                </div>
              )
            )}

            {activePanelTab === 'timeline' && (
              <div className="flex-1 flex flex-col min-h-0 p-6">
                <h3 className="text-xs font-bold text-white uppercase tracking-wider mb-4 flex items-center gap-2">
                  <BookOpen size={14} className="text-violet-400" /> Decision Timeline
                </h3>
                {isLoadingDecisions ? (
                  <div className="flex-1 flex items-center justify-center">
                    <div className="h-6 w-6 rounded-full border-2 border-slate-800 border-t-violet-500 animate-spin"></div>
                  </div>
                ) : decisionLogs.length === 0 ? (
                  <div className="flex-1 flex flex-col items-center justify-center text-slate-500 text-center space-y-2">
                    <p className="text-xs">채택된 의사결정이 없습니다.</p>
                    <p className="text-[9px] text-slate-650 max-w-[200px]">캔버스에서 자식/후보 노드를 '채택(Adopt)'하면 의사결정 이력이 기록됩니다.</p>
                  </div>
                ) : (
                  <div className="flex-1 overflow-y-auto space-y-4 pr-1 relative pl-4 border-l border-slate-800/80 scrollbar-thin">
                    {decisionLogs.map((log, idx) => (
                      <div key={idx} className="relative space-y-1.5 pb-2">
                        {/* Timeline dot */}
                        <div className="absolute -left-[21px] top-1.5 h-2.5 w-2.5 rounded-full bg-violet-500 border-2 border-slate-900 shadow-[0_0_8px_rgba(139,92,246,0.5)]"></div>
                        <div className="text-[9px] text-slate-500 font-semibold">{new Date(log.date).toLocaleString()}</div>
                        <div className="text-xs font-bold text-white leading-snug">{log.title}</div>
                        <div className="p-2.5 rounded-lg border border-slate-800/60 bg-slate-950/30 text-[10px] text-slate-400 leading-relaxed whitespace-pre-line">{log.reasoning}</div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}

            {activePanelTab === 'spec' && (
              <div className="flex-1 flex flex-col min-h-0 p-6">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-xs font-bold text-white uppercase tracking-wider flex items-center gap-2">
                    <FileText size={14} className="text-violet-400" /> Compiled Spec
                  </h3>
                  <div className="flex gap-2">
                    <button
                      onClick={handleCopySpec}
                      className="px-2 py-1 rounded border border-slate-850 hover:bg-slate-800 text-[10px] font-bold text-slate-300 cursor-pointer transition-all"
                    >
                      Copy
                    </button>
                    <button
                      onClick={handleDownloadSpec}
                      className="px-2 py-1 rounded bg-violet-600/30 border border-violet-500/30 hover:bg-violet-600/40 text-[10px] font-bold text-violet-300 cursor-pointer transition-all"
                    >
                      Download
                    </button>
                  </div>
                </div>

                {/* Developer Handover Audit Widget */}
                <div className="mb-4 p-4 rounded-xl border border-slate-800/80 bg-slate-950/40 backdrop-blur-md space-y-3 shrink-0">
                  <div className="flex justify-between items-center text-[10px] font-bold text-slate-400 uppercase tracking-wider">
                    <span className="flex items-center gap-1.5">
                      <ShieldCheck size={13} className="text-violet-400" /> Developer Handover Audit
                    </span>
                    <span className="text-[9px] px-1.5 py-0.5 rounded bg-slate-900 border border-slate-800 font-semibold lowercase text-slate-500">
                      readiness checker
                    </span>
                  </div>

                  <div className="space-y-1.5">
                    <div className="flex justify-between items-center text-xs">
                      <span className="font-semibold text-white">{handoverAudit.statusText}</span>
                      <span className="font-bold text-violet-400">{handoverAudit.readinessPercentage}%</span>
                    </div>
                    <div className="w-full h-1.5 bg-slate-950 rounded-full overflow-hidden">
                      <div 
                        className={`h-full bg-gradient-to-r ${handoverAudit.progressColorClass} transition-all duration-500`} 
                        style={{ width: `${handoverAudit.readinessPercentage}%` }}
                      />
                    </div>
                  </div>

                  <div className="pt-1.5 border-t border-slate-900 space-y-2">
                    {/* Check 1: Candidates Left */}
                    <div className="flex items-start gap-2 text-[10px] leading-normal">
                      <span className="text-xs shrink-0 mt-0.5">
                        {handoverAudit.hasCandidatesLeft ? '⚠️' : '✅'}
                      </span>
                      <div>
                        <span className={`font-bold block ${handoverAudit.hasCandidatesLeft ? 'text-slate-400' : 'text-slate-200'}`}>
                          의사결정 완결성 (분기 정리)
                        </span>
                        <span className="text-slate-500 text-[9px]">
                          {handoverAudit.hasCandidatesLeft 
                            ? '미결정된 대안 후보 노드(점선)가 남아 있습니다. 채택/아카이브 필요.' 
                            : '모든 후보 갈림길의 의사결정이 정상 완료되었습니다.'}
                        </span>
                      </div>
                    </div>

                    {/* Check 2: Elaboration */}
                    <div className="flex items-start gap-2 text-[10px] leading-normal">
                      <span className="text-xs shrink-0 mt-0.5">
                        {handoverAudit.unelaboratedNodesCount > 0 ? '⚠️' : '✅'}
                      </span>
                      <div>
                        <span className={`font-bold block ${handoverAudit.unelaboratedNodesCount > 0 ? 'text-slate-400' : 'text-slate-200'}`}>
                          설계 구체성 (메인라인 대화율)
                        </span>
                        <span className="text-slate-500 text-[9px]">
                          {handoverAudit.unelaboratedNodesCount > 0 
                            ? `구체화되지 않은 기획 노드가 ${handoverAudit.unelaboratedNodesCount}개 존재합니다. 참모들과의 대화가 필요합니다.` 
                            : '모든 mainline 기획 노드가 최소 1회 이상의 에이전트 피드백을 수렴하였습니다.'}
                        </span>
                      </div>
                    </div>

                    {/* Check 3: Gap Detector Audit */}
                    <div className="flex items-start gap-2 text-[10px] leading-normal">
                      <span className="text-xs shrink-0 mt-0.5">
                        {handoverAudit.hasGapDetectorAudited ? '✅' : '⚠️'}
                      </span>
                      <div>
                        <span className={`font-bold block ${!handoverAudit.hasGapDetectorAudited ? 'text-slate-400' : 'text-slate-200'}`}>
                          예외 처리 검수 (Gap Detector)
                        </span>
                        <span className="text-slate-500 text-[9px]">
                          {!handoverAudit.hasGapDetectorAudited 
                            ? '예외 처리 및 엣지 케이스가 아직 검수되지 않았습니다. Gap Detector 참모 호출을 권장합니다.' 
                            : '에러 복구 및 예외 상태 규칙에 대한 Gap Detector 참모 검수가 완료되었습니다.'}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>

                {isLoadingSpec ? (
                  <div className="flex-1 flex items-center justify-center">
                    <div className="h-6 w-6 rounded-full border-2 border-slate-800 border-t-violet-500 animate-spin"></div>
                  </div>
                ) : !specMarkdown ? (
                  <div className="flex-1 flex flex-col items-center justify-center text-slate-500 text-center space-y-2">
                    <p className="text-xs">작성된 명세서가 없습니다.</p>
                    <button
                      onClick={fetchSpecText}
                      className="px-3 py-1.5 rounded-lg bg-violet-600 hover:bg-violet-500 text-[10px] font-bold text-white transition-all cursor-pointer"
                    >
                      명세서 생성하기
                    </button>
                  </div>
                ) : (
                  <div className="flex-1 overflow-y-auto pr-1 bg-slate-950/30 rounded-xl border border-slate-850 p-4 font-mono text-[10px] text-slate-350 leading-relaxed whitespace-pre-wrap select-text scrollbar-thin">
                    {specMarkdown}
                  </div>
                )}
              </div>
            )}

            {activePanelTab === 'devloop' && (
              <div className="flex-1 flex flex-col min-h-0 p-6">
                <h3 className="text-xs font-bold text-white uppercase tracking-wider mb-4 flex items-center gap-2">
                  <Settings size={14} className="text-violet-400" /> DevLoop Console
                </h3>

                {/* Grid of command actions */}
                <div className="grid grid-cols-2 gap-2 mb-4">
                  {([
                    { key: 'build', label: 'Build Project', desc: 'npm run build' },
                    { key: 'verify', label: 'Verify/Test', desc: 'npm run test' },
                    { key: 'launch', label: 'Launch/Start', desc: 'npm start' },
                    { key: 'uiCheck', label: 'UI Check', desc: 'ui check' }
                  ] as const).map(({ key, label, desc }) => {
                    const presetCmd = settings.developerLoop?.[`${key}Command`] || desc;
                    const isRunning = activeDevLoopCommand === key;
                    const isAnyRunning = activeDevLoopCommand !== null;
                    return (
                      <button
                        key={key}
                        disabled={isAnyRunning && !isRunning}
                        onClick={() => handleRunDevLoopCommand(key)}
                        className={`p-3 rounded-xl border text-left flex flex-col justify-between transition-all ${
                          isRunning
                            ? 'bg-violet-600/30 border-violet-500 text-white animate-pulse'
                            : 'bg-slate-950/40 border-slate-850 hover:border-slate-700 text-slate-300 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer'
                        }`}
                      >
                        <span className="text-[10px] font-bold uppercase tracking-wider">{label}</span>
                        <span className="text-[9px] text-slate-500 mt-1 font-mono truncate w-full">{presetCmd || 'not configured'}</span>
                      </button>
                    );
                  })}
                </div>

                {/* Console Terminal View */}
                <div className="flex-1 flex flex-col min-h-0 border border-slate-850 bg-slate-950 rounded-xl overflow-hidden shadow-2xl relative">
                  {/* Console Header */}
                  <div className="px-4 py-2 border-b border-slate-850 bg-slate-950 flex justify-between items-center text-[9px] text-slate-500 font-bold uppercase tracking-wider">
                    <span>Console Log Output</span>
                    <button
                      onClick={() => setDevLoopLogs([])}
                      className="text-slate-600 hover:text-slate-400 cursor-pointer"
                    >
                      Clear
                    </button>
                  </div>

                  {/* Console Log Area */}
                  <div className="flex-1 p-4 font-mono text-[10px] overflow-y-auto space-y-1 select-text scrollbar-thin">
                    {devLoopLogs.length === 0 ? (
                      <div className="text-slate-600 italic">No logs. Run a DevLoop command to view output...</div>
                    ) : (
                      devLoopLogs.map((log, idx) => {
                        let colorClass = 'text-slate-400';
                        if (log.type === 'stderr') colorClass = 'text-red-400 font-semibold';
                        if (log.type === 'info') colorClass = 'text-violet-400 font-bold';
                        if (log.type === 'start') colorClass = 'text-cyan-400 font-bold border-b border-slate-800 pb-1 mb-1';
                        if (log.type === 'exit') colorClass = 'text-emerald-400 font-bold border-t border-slate-800 pt-1 mt-1';
                        if (log.type === 'error') colorClass = 'text-rose-500 font-black';
                        return (
                          <div key={idx} className={`${colorClass} whitespace-pre-wrap`}>
                            {log.text}
                          </div>
                        );
                      })
                    )}
                  </div>
                </div>
              </div>
            )}
          </div>
        )}
      </div>

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

        {/* Error/Info Toast Notification */}
        {errorToast && (
          <div className={`absolute bottom-6 left-6 max-w-sm border rounded-lg p-4 shadow-2xl z-50 flex gap-3 animate-slide-in ${
            errorToast.type === 'error' 
              ? 'bg-slate-900 border-red-500/30 shadow-red-950/20' 
              : 'bg-slate-900 border-cyan-500/30 shadow-cyan-950/20'
          }`}>
            <div className={`w-6 h-6 rounded-full flex items-center justify-center shrink-0 ${
              errorToast.type === 'error' ? 'bg-red-950/50' : 'bg-cyan-950/50'
            }`}>
              {errorToast.type === 'error' ? (
                <AlertCircle size={14} className="text-red-400" />
              ) : (
                <Check size={14} className="text-cyan-400" />
              )}
            </div>
            <div className="flex-1">
              <h4 className="text-xs font-semibold text-white">
                {errorToast.type === 'error' ? '오류 발생' : '알림'}
              </h4>
              <p className="text-[10px] text-slate-450 mt-0.5 leading-normal">
                {errorToast.message}
              </p>
            </div>
            <button 
              onClick={() => setErrorToast(null)} 
              className="text-[10px] text-slate-500 hover:text-slate-350 cursor-pointer align-top shrink-0"
            >
              닫기
            </button>
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
                          <option value="agy">Antigravity (AGY)</option>
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
                      : 'text-slate-500 hover:text-slate-355'
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
                <button
                  type="button"
                  onClick={() => setActiveSettingsTab('devloop')}
                  className={`flex-1 pb-2.5 text-[11px] font-bold uppercase tracking-wider transition-all cursor-pointer text-center ${
                    activeSettingsTab === 'devloop'
                      ? 'text-violet-400 border-b-2 border-violet-500'
                      : 'text-slate-500 hover:text-slate-355'
                  }`}
                >
                  DevLoop Presets
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
                      <option value="agy">Antigravity (AGY)</option>
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
                            <option value="agy">Antigravity (AGY)</option>
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

              {activeSettingsTab === 'devloop' && (
                <div className="space-y-4 animate-fade-in max-h-[300px] overflow-y-auto pr-1 scrollbar-thin">
                  <div>
                    <label htmlFor="buildCommand" className="block text-[10px] font-bold uppercase tracking-wider text-slate-400 mb-1.5">
                      Build Project Command
                    </label>
                    <input
                      type="text"
                      id="buildCommand"
                      value={formBuildCommand}
                      onChange={(e) => setFormBuildCommand(e.target.value)}
                      placeholder="e.g. npm run build"
                      className="w-full px-3.5 py-2.5 rounded-lg border border-slate-800 bg-slate-950/60 text-xs text-white placeholder-slate-700 outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500/30 transition-all"
                    />
                  </div>

                  <div>
                    <label htmlFor="verifyCommand" className="block text-[10px] font-bold uppercase tracking-wider text-slate-400 mb-1.5">
                      Verify/Test Command
                    </label>
                    <input
                      type="text"
                      id="verifyCommand"
                      value={formVerifyCommand}
                      onChange={(e) => setFormVerifyCommand(e.target.value)}
                      placeholder="e.g. npm run test"
                      className="w-full px-3.5 py-2.5 rounded-lg border border-slate-800 bg-slate-950/60 text-xs text-white placeholder-slate-700 outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500/30 transition-all"
                    />
                  </div>

                  <div>
                    <label htmlFor="launchCommand" className="block text-[10px] font-bold uppercase tracking-wider text-slate-400 mb-1.5">
                      Launch/Start Command
                    </label>
                    <input
                      type="text"
                      id="launchCommand"
                      value={formLaunchCommand}
                      onChange={(e) => setFormLaunchCommand(e.target.value)}
                      placeholder="e.g. npm start"
                      className="w-full px-3.5 py-2.5 rounded-lg border border-slate-800 bg-slate-950/60 text-xs text-white placeholder-slate-700 outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500/30 transition-all"
                    />
                  </div>

                  <div>
                    <label htmlFor="uiCheckCommand" className="block text-[10px] font-bold uppercase tracking-wider text-slate-400 mb-1.5">
                      UI Check Command (Optional)
                    </label>
                    <input
                      type="text"
                      id="uiCheckCommand"
                      value={formUiCheckCommand}
                      onChange={(e) => setFormUiCheckCommand(e.target.value)}
                      placeholder="e.g. npx playwright test"
                      className="w-full px-3.5 py-2.5 rounded-lg border border-slate-800 bg-slate-950/60 text-xs text-white placeholder-slate-700 outline-none focus:border-violet-500 focus:ring-1 focus:ring-violet-500/30 transition-all"
                    />
                  </div>
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

      {/* 전역 도움말 모달 */}
      {showHelpModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/80 backdrop-blur-md p-4 animate-fade-in">
          <div className="relative w-full max-w-lg overflow-hidden rounded-2xl border border-slate-800 bg-slate-900/95 p-6 shadow-2xl backdrop-blur-xl">
            {/* Ambient gradients */}
            <div className="absolute -top-20 -left-20 w-44 h-44 rounded-full bg-violet-600/10 blur-3xl pointer-events-none"></div>
            <div className="absolute -bottom-20 -right-20 w-44 h-44 rounded-full bg-indigo-600/10 blur-3xl pointer-events-none"></div>

            <div className="relative flex justify-between items-center mb-4 border-b border-slate-800 pb-3">
              <h3 className="text-sm font-bold text-white flex items-center gap-2">
                <HelpCircle size={16} className="text-violet-400" /> LAO Studio 사용 가이드
              </h3>
              <button
                onClick={() => setShowHelpModal(false)}
                className="text-xs text-slate-500 hover:text-slate-300 cursor-pointer"
              >
                닫기
              </button>
            </div>

            <div className="relative space-y-4 max-h-[60vh] overflow-y-auto pr-1 text-xs text-slate-300 leading-relaxed scrollbar-thin">
              <div className="space-y-1.5">
                <h4 className="font-bold text-white flex items-center gap-1.5">🌱 1. 프로젝트 시작 (Seed)</h4>
                <p className="text-[11px] text-slate-400 pl-4">
                  첫 프로젝트 로드 시 제목과 핵심 주제를 입력하고 생성하면, 3가지 초기 대안(Option) 노드가 캔버스에 생성됩니다.
                </p>
              </div>

              <div className="space-y-1.5">
                <h4 className="font-bold text-white flex items-center gap-1.5">🌿 2. 대안 채택 (Adopt & Merge)</h4>
                <p className="text-[11px] text-slate-400 pl-4">
                  비교 대상 중 마음에 드는 대안 노드를 선택하고 <strong>Adopt as Mainline Choice</strong>를 누르면 메인라인 기획으로 채택되며, 결정 로그(Decision Log)에 기록됩니다. 여러 대안을 합치고 싶다면 <strong>Merge All</strong>을 활용할 수 있습니다.
                </p>
              </div>

              <div className="space-y-1.5">
                <h4 className="font-bold text-white flex items-center gap-1.5">💬 3. AI 참모 에이전트와 대화</h4>
                <p className="text-[11px] text-slate-400 pl-4">
                  메인라인 노드에 질문을 보내면 AI 디렉터가 내용을 분석하여 아래 4대 스텝 참모에게 자동 전달합니다:
                </p>
                <ul className="list-disc list-inside pl-6 space-y-1 text-[10px] text-slate-400">
                  <li><strong className="text-purple-355 font-bold">Specifier (구체화)</strong>: 모호한 기획 내용을 상세 아키텍처나 기능으로 명세화</li>
                  <li><strong className="text-emerald-355 font-bold">Optionizer (대안 제시)</strong>: 결정하기 어려운 부분에 대해 2~4가지 선택 분기점 제시</li>
                  <li><strong className="text-sky-355 font-bold">Researcher (레퍼런스 조사)</strong>: 관련 오픈소스, 타사 유사 기능 및 업계 표준 조사</li>
                  <li><strong className="text-rose-355 font-bold">Gap Detector (공백 감지)</strong>: 설계 누락, 보안 취약점, 엣지 케이스 점검</li>
                </ul>
              </div>

              <div className="space-y-1.5">
                <h4 className="font-bold text-white flex items-center gap-1.5">📝 4. 명세서 컴파일 (Compile Spec)</h4>
                <p className="text-[11px] text-slate-400 pl-4">
                  마인드맵 기획 확장이 완료되면 헤더의 <strong>Compile Spec</strong> 버튼을 눌러 전체 Decided 트리 구조와 의사결정 기록을 하나의 깔끔한 Markdown 명세서 파일(`.lao/spec_compiled.md`)로 빌드할 수 있습니다.
                </p>
              </div>
            </div>

            <div className="mt-5 border-t border-slate-800 pt-3 flex justify-end">
              <button
                onClick={() => setShowHelpModal(false)}
                className="px-4 py-1.5 rounded-lg bg-violet-600 hover:bg-violet-500 text-white font-bold text-[10px] cursor-pointer transition-all"
              >
                이해했습니다
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
