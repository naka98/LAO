import React, { useState, useRef, useEffect } from 'react';
import type { GraphNode, NodeMessage, ParsedProposal, NodeMessageAuthor } from '../types';
import { Send, User, Brain, AlertCircle, Check, GitMerge, Square } from 'lucide-react';

interface NodeDetailPanelProps {
  node: GraphNode;
  messages: NodeMessage[];
  candidates: GraphNode[]; // siblings that are candidates
  onSendMessage: (message: string) => Promise<void>;
  onAdoptNode: (adoptedId: string) => Promise<void>;
  onMergeNodes: (candidateIds: string[]) => Promise<void>;
  onUpdateNode: (updatedNode: GraphNode) => void;
  isSending: boolean;
  routingStatus: {
    isRouting: boolean;
    route?: 'specifier' | 'researcher' | 'optionizer' | 'gapDetector';
    reasoning?: string;
  };
  lastProposal?: ParsedProposal;
  onClearProposal: () => void;
  onCancelGeneration?: () => void;
}

const getAuthorMeta = (author: NodeMessageAuthor) => {
  switch (author) {
    case 'user':
      return { label: 'User', bg: 'bg-indigo-600', text: 'text-white', icon: User };
    case 'director':
      return { label: 'Director', bg: 'bg-slate-700', text: 'text-slate-200', icon: Brain };
    case 'specifier':
      return { label: 'Specifier', bg: 'bg-purple-600', text: 'text-purple-100', icon: Brain };
    case 'researcher':
      return { label: 'Researcher', bg: 'bg-sky-600', text: 'text-sky-100', icon: Brain };
    case 'optionizer':
      return { label: 'Optionizer', bg: 'bg-emerald-600', text: 'text-emerald-100', icon: Brain };
    case 'gapDetector':
      return { label: 'Gap Detector', bg: 'bg-rose-600', text: 'text-rose-100', icon: AlertCircle };
  }
};

export const NodeDetailPanel: React.FC<NodeDetailPanelProps> = ({
  node,
  messages,
  candidates,
  onSendMessage,
  onAdoptNode,
  onMergeNodes,
  onUpdateNode,
  isSending,
  routingStatus,
  lastProposal,
  onClearProposal,
  onCancelGeneration,
}) => {
  const [inputMsg, setInputMsg] = useState('');
  const [isEditing, setIsEditing] = useState(false);
  const [editTitle, setEditTitle] = useState(node.title);
  const [editBody, setEditBody] = useState(node.body);
  const chatEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setEditTitle(node.title);
    setEditBody(node.body);
    setIsEditing(false);
  }, [node]);

  useEffect(() => {
    chatEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, routingStatus]);

  const handleSend = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!inputMsg.trim() || isSending) return;
    const msg = inputMsg;
    setInputMsg('');
    await onSendMessage(msg);
  };

  const handleSaveEdit = () => {
    onUpdateNode({
      ...node,
      title: editTitle,
      body: editBody,
      updatedAt: new Date().toISOString(),
    });
    setIsEditing(false);
  };

  const isCandidateNode = node.branchRole === 'candidate';

  return (
    <div className="w-full flex flex-col h-full relative z-10">
      
      {/* Node Meta Details Header */}
      <div className="p-5 border-b border-slate-800 flex flex-col gap-3">
        {isEditing ? (
          <div className="flex flex-col gap-2">
            <input
              type="text"
              className="bg-slate-950 border border-slate-800 rounded px-3 py-1.5 text-sm text-white focus:outline-none focus:border-violet-500"
              value={editTitle}
              onChange={(e) => setEditTitle(e.target.value)}
            />
            <textarea
              className="bg-slate-950 border border-slate-800 rounded px-3 py-1.5 text-xs text-slate-300 focus:outline-none focus:border-violet-500 h-20 resize-none"
              value={editBody}
              onChange={(e) => setEditBody(e.target.value)}
            />
            <div className="flex gap-2 justify-end mt-1">
              <button
                onClick={() => setIsEditing(false)}
                className="px-3 py-1 text-xs rounded bg-slate-800 text-slate-400 hover:bg-slate-700"
              >
                Cancel
              </button>
              <button
                onClick={handleSaveEdit}
                className="px-3 py-1 text-xs rounded bg-violet-600 text-white hover:bg-violet-500"
              >
                Save
              </button>
            </div>
          </div>
        ) : (
          <div>
            <div className="flex justify-between items-start mb-1">
              <span className="text-[10px] uppercase tracking-wider font-bold text-violet-400">
                {node.kind} node ({node.branchRole})
              </span>
              <button
                onClick={() => setIsEditing(true)}
                className="text-[11px] text-slate-400 hover:text-white"
              >
                Edit
              </button>
            </div>
            <h2 className="text-lg font-semibold text-white leading-tight mb-2">{node.title}</h2>
            {node.body ? (
              <p className="text-xs text-slate-400 leading-relaxed max-h-24 overflow-y-auto pr-1">
                {node.body}
              </p>
            ) : (
              <p className="text-xs text-slate-500 italic">*(No details specified. Talk to AI to elaborate.)*</p>
            )}
          </div>
        )}

        {/* Adopt option for Candidate Node */}
        {isCandidateNode && (
          <button
            onClick={() => onAdoptNode(node.id)}
            className="w-full mt-2 py-2 px-4 rounded bg-violet-600 hover:bg-violet-500 text-white text-xs font-semibold flex items-center justify-center gap-1.5 shadow-lg shadow-violet-950/20"
          >
            <Check size={14} /> Adopt as Mainline Choice
          </button>
        )}

        {/* Sibling Candidates Merge Action */}
        {!isCandidateNode && candidates.length > 0 && (
          <div className="mt-2 p-3 bg-slate-950/50 border border-slate-800/80 rounded-lg">
            <span className="text-[10px] font-semibold text-slate-400 block mb-1">
              🌿 Available Alternative Branches ({candidates.length})
            </span>
            <p className="text-[9px] text-slate-500 leading-normal mb-2.5">
              이 노드의 하위 대안들이 캔버스 오른쪽에 생성되었습니다. 원하는 대안을 개별 채택(Adopt)하거나, 여러 대안을 합치려면 병합(Merge)을 누르세요.
            </p>
            <div className="flex flex-col gap-1.5">
              {candidates.map((c) => (
                <div key={c.id} className="flex justify-between items-center text-xs bg-slate-900 px-2.5 py-1.5 rounded border border-slate-800">
                  <span className="truncate max-w-[200px] text-slate-300 font-medium">{c.title}</span>
                  <button
                    onClick={() => onAdoptNode(c.id)}
                    className="text-[10px] text-violet-400 hover:text-violet-300 font-semibold"
                  >
                    Adopt
                  </button>
                </div>
              ))}
              {candidates.length >= 2 && (
                <button
                  onClick={() => onMergeNodes(candidates.map(c => c.id))}
                  className="w-full mt-1.5 py-1.5 rounded border border-slate-700 bg-slate-800/50 text-[10px] font-bold text-slate-300 hover:bg-slate-700 flex items-center justify-center gap-1"
                >
                  <GitMerge size={12} /> Merge All into Synthesized Node
                </button>
              )}
            </div>
          </div>
        )}
      </div>

      {/* Chat Messages */}
      <div className="flex-1 overflow-y-auto p-5 space-y-4">
        {messages.length === 0 ? (
          <div className="h-full flex flex-col items-center justify-center p-2 text-center text-slate-500 space-y-4">
            <div className="flex flex-col items-center">
              <Brain size={32} className="text-slate-600 mb-2 animate-bounce" />
              <p className="text-xs font-semibold text-slate-400">참모들과의 대화가 없습니다.</p>
              <p className="text-[9px] text-slate-500 mt-1 max-w-[280px]">
                기획 질문을 하시면 AI 디렉터가 최적의 참모를 자동 지정하여 실시간으로 답변해 줍니다.
              </p>
            </div>
            
            <div className="w-full space-y-2.5 mt-2">
              <span className="text-[9px] font-bold text-violet-400 uppercase tracking-wider block text-left mb-1.5">
                🚀 빠른 추천 질문 (클릭 시 자동 전송)
              </span>
              <div className="grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={() => onSendMessage("이 기획의 구체적인 아키텍처와 흐름을 자세히 설계해줘.")}
                  className="p-2.5 rounded-lg border border-purple-500/10 bg-purple-950/10 hover:bg-purple-950/20 hover:border-purple-500/30 text-left text-[10px] leading-normal transition-all cursor-pointer"
                >
                  <span className="font-bold text-purple-300 block mb-0.5">💡 구체화 (Specifier)</span>
                  <span className="text-[9px] text-slate-500 line-clamp-2">상세 아키텍처 및 세부 컴포넌트 설계 요청</span>
                </button>

                <button
                  type="button"
                  onClick={() => onSendMessage("이 하위 레벨에서 취할 수 있는 또 다른 대안 3가지를 제안해줘.")}
                  className="p-2.5 rounded-lg border border-emerald-500/10 bg-emerald-950/10 hover:bg-emerald-950/20 hover:border-emerald-500/30 text-left text-[10px] leading-normal transition-all cursor-pointer"
                >
                  <span className="font-bold text-emerald-300 block mb-0.5">🌿 대안 제시 (Optionizer)</span>
                  <span className="text-[9px] text-slate-500 line-clamp-2">선택 가능한 갈림길(Branch) 3가지 생성</span>
                </button>

                <button
                  type="button"
                  onClick={() => onSendMessage("이 설계와 관련된 오픈소스 프로젝트나 업계 표준 사례가 있을까?")}
                  className="p-2.5 rounded-lg border border-sky-500/10 bg-sky-950/10 hover:bg-sky-950/20 hover:border-sky-500/30 text-left text-[10px] leading-normal transition-all cursor-pointer"
                >
                  <span className="font-bold text-sky-300 block mb-0.5">🔍 레퍼런스 조사 (Researcher)</span>
                  <span className="text-[9px] text-slate-500 line-clamp-2">기술 스택 레퍼런스 및 벤치마킹 조사</span>
                </button>

                <button
                  type="button"
                  onClick={() => onSendMessage("이 흐름에서 발생할 수 있는 취약점이나 엣지 케이스가 있는지 검토해줘.")}
                  className="p-2.5 rounded-lg border border-rose-500/10 bg-rose-950/10 hover:bg-rose-950/20 hover:border-rose-500/30 text-left text-[10px] leading-normal transition-all cursor-pointer"
                >
                  <span className="font-bold text-rose-300 block mb-0.5">⚠️ 공백 점검 (Gap Detector)</span>
                  <span className="text-[9px] text-slate-500 line-clamp-2">누락된 설계 및 예외적 케이스 검토</span>
                </button>
              </div>
            </div>
          </div>
        ) : (
          messages.map((msg) => {
            const meta = getAuthorMeta(msg.author);
            const isUser = msg.author === 'user';
            const Icon = meta.icon;

            return (
              <div key={msg.id} className={`flex gap-3 ${isUser ? 'flex-row-reverse' : ''}`}>
                <div className={`w-8 h-8 rounded-full flex items-center justify-center shrink-0 ${meta.bg}`}>
                  <Icon size={14} className={meta.text} />
                </div>
                <div className={`flex flex-col max-w-[80%] ${isUser ? 'items-end' : ''}`}>
                  <span className="text-[10px] text-slate-500 font-medium mb-1">{meta.label}</span>
                  <div className={`p-3 rounded-lg text-xs leading-relaxed ${isUser ? 'bg-indigo-600 text-white rounded-tr-none' : 'bg-slate-800 text-slate-200 rounded-tl-none border border-slate-700/50'}`}>
                    {msg.content}
                  </div>
                </div>
              </div>
            );
          })
        )}

        {/* 5인 극장 라우팅 애니메이션 칩 */}
        {routingStatus.isRouting && (
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-full bg-slate-700 animate-pulse flex items-center justify-center shrink-0">
              <Brain size={14} className="text-white" />
            </div>
            <div className="flex flex-col gap-1 max-w-[80%]">
              <span className="text-[10px] text-slate-500 font-semibold flex items-center gap-1">
                Director Analysis...
              </span>
              <div className="bg-slate-800 border border-slate-700/80 p-3 rounded-lg rounded-tl-none text-xs text-slate-300 italic flex items-center gap-2">
                <div className="w-1.5 h-1.5 rounded-full bg-violet-500 animate-ping"></div>
                질문에 적절한 최적의 에이전트를 매칭하고 있습니다.
              </div>
            </div>
          </div>
        )}

        {/* Selected agent response animation */}
        {!routingStatus.isRouting && routingStatus.route && isSending && (
          <div className="flex items-center gap-3">
            <div className={`w-8 h-8 rounded-full flex items-center justify-center shrink-0 animate-pulse ${getAuthorMeta(routingStatus.route).bg}`}>
              <Brain size={14} className="text-white" />
            </div>
            <div className="flex flex-col gap-1 max-w-[80%]">
              <span className="text-[10px] text-slate-500 font-semibold">
                Director Routed to <strong className="text-violet-400 capitalize">{routingStatus.route}</strong>
              </span>
              <div className="bg-slate-800 border border-slate-700 p-2.5 rounded-lg text-[10px] text-slate-400 leading-normal">
                Reasoning: &ldquo;{routingStatus.reasoning}&rdquo;
              </div>
              <div className="bg-slate-800 border border-slate-700/80 p-3 rounded-lg rounded-tl-none text-xs text-slate-300 italic flex items-center gap-2 mt-1">
                {routingStatus.route} 가 답변을 작성하는 중입니다...
              </div>
            </div>
          </div>
        )}

        <div ref={chatEndRef} />
      </div>

      {/* Optional proposals from last AI response */}
      {lastProposal && (
        <div className="px-5 py-3 bg-slate-950/80 border-t border-slate-800/80 flex flex-col gap-2 relative">
          <button
            onClick={onClearProposal}
            className="absolute top-2 right-3 text-[10px] text-slate-500 hover:text-slate-300"
          >
            Dismiss
          </button>
          
          {lastProposal.type === 'child' && (
            <div>
              <span className="text-[10px] font-bold text-violet-400 block mb-1">💡 Drill-down Sub-topic Proposal</span>
              <div className="bg-slate-900 border border-violet-500/30 p-2.5 rounded flex justify-between items-center gap-4">
                <div className="flex-1 min-w-0">
                  <h4 className="text-xs font-semibold text-white truncate">{lastProposal.proposal.title}</h4>
                  <p className="text-[10px] text-slate-400 line-clamp-1">{lastProposal.proposal.body}</p>
                </div>
                <button
                  onClick={() => onAdoptNode(JSON.stringify(lastProposal))}
                  className="px-2.5 py-1 text-[10px] font-bold rounded bg-violet-600 text-white hover:bg-violet-500 shrink-0"
                >
                  Create
                </button>
              </div>
            </div>
          )}

          {lastProposal.type === 'branches' && (
            <div>
              <span className="text-[10px] font-bold text-purple-400 block mb-1">🌿 Parallel Alternative Branches Suggested</span>
              <div className="flex flex-col gap-1.5">
                {lastProposal.proposals.map((prop, idx) => (
                  <div key={idx} className="bg-slate-900 border border-purple-500/20 p-2.5 rounded flex justify-between items-center gap-4">
                    <div className="flex-1 min-w-0">
                      <h4 className="text-xs font-semibold text-white truncate">{prop.title}</h4>
                      <p className="text-[10px] text-slate-400 line-clamp-1">{prop.body}</p>
                    </div>
                    <button
                      onClick={() => onAdoptNode(JSON.stringify({ type: 'single-branch', proposal: prop }))}
                      className="px-2.5 py-1 text-[10px] font-bold rounded bg-purple-950 border border-purple-800 text-purple-200 hover:bg-purple-900 shrink-0"
                    >
                      Branch
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Input Form */}
      <form onSubmit={handleSend} className="p-4 border-t border-slate-800 bg-slate-950 flex gap-2">
        <input
          type="text"
          placeholder={isSending ? "AI 참모가 답변을 작성하고 있습니다..." : "참모들에게 기획 방향을 지시하거나 질문해보세요..."}
          className="flex-1 bg-slate-900 border border-slate-800 rounded-lg px-4 py-2.5 text-xs text-white focus:outline-none focus:border-violet-500 placeholder-slate-600"
          value={inputMsg}
          onChange={(e) => setInputMsg(e.target.value)}
          disabled={isSending}
        />
        {isSending && onCancelGeneration ? (
          <button
            type="button"
            onClick={onCancelGeneration}
            className="p-2.5 rounded-lg bg-rose-600 hover:bg-rose-500 text-white transition-colors cursor-pointer flex items-center justify-center shrink-0"
            title="생성 중단"
          >
            <Square size={14} fill="currentColor" />
          </button>
        ) : (
          <button
            type="submit"
            disabled={!inputMsg.trim() || isSending}
            className="p-2.5 rounded-lg bg-violet-600 hover:bg-violet-500 text-white disabled:bg-slate-800 disabled:text-slate-600 transition-colors flex items-center justify-center shrink-0"
          >
            <Send size={14} />
          </button>
        )}
      </form>
    </div>
  );
};
