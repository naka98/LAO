import { memo } from 'react';
import { Handle, Position } from '@xyflow/react';
import type { Node, NodeProps } from '@xyflow/react';
import type { GraphNodeKind, GraphNodeStatus, GraphNodeBranchRole } from '../types';

export type CustomNodeData = {
  title: string;
  body: string;
  kind: GraphNodeKind;
  status: GraphNodeStatus;
  branchRole: GraphNodeBranchRole;
  isSelected?: boolean;
};

export type CustomNode = Node<CustomNodeData, 'custom'>;

const getKindEmoji = (kind: GraphNodeKind): string => {
  switch (kind) {
    case 'seed': return '💡';
    case 'starter': return '🚀';
    case 'decision': return '⚖️';
    case 'option': return '🌿';
    case 'research': return '🔍';
    case 'gap': return '⚠️';
    case 'free': default: return '✏️';
  }
};

const getKindColorClass = (kind: GraphNodeKind): string => {
  switch (kind) {
    case 'seed': return 'from-purple-500 to-indigo-500';
    case 'starter': return 'from-blue-500 to-teal-500';
    case 'decision': return 'from-amber-500 to-orange-500';
    case 'option': return 'from-emerald-500 to-green-500';
    case 'research': return 'from-sky-500 to-indigo-500';
    case 'gap': return 'from-rose-500 to-red-500';
    case 'free': default: return 'from-gray-500 to-slate-500';
  }
};

export const CustomNodeComponent = memo(({ data, selected }: NodeProps<CustomNode>) => {
  const { title, body, kind, status, branchRole, isSelected } = data;

  const isArchived = branchRole === 'archived';
  const isCandidate = branchRole === 'candidate';
  const isExploring = status === 'exploring';
  
  // Outer border & shadow logic based on role and status
  let outerClass = "relative min-w-[220px] max-w-[280px] rounded-xl p-4 transition-all duration-300 ";
  
  if (isArchived) {
    outerClass += "bg-slate-900/40 border border-slate-800 text-slate-500 opacity-50 shadow-none";
  } else if (kind === 'seed') {
    outerClass += "bg-slate-900/90 border-2 border-indigo-500 text-white shadow-[0_0_15px_rgba(99,102,241,0.2)]";
  } else if (isCandidate) {
    outerClass += "bg-slate-900/70 border border-dashed border-purple-400 text-purple-100 shadow-[0_0_8px_rgba(192,132,252,0.15)]";
  } else if (isExploring) {
    outerClass += "bg-slate-900/90 border-2 border-emerald-400 text-white animate-pulse shadow-[0_0_12px_rgba(52,211,153,0.3)]";
  } else {
    // Normal mainline node
    outerClass += "bg-slate-900/80 border border-slate-700 text-slate-200 shadow-md";
  }

  // Selected border highlight from react-flow focus or selected flag
  if ((selected || isSelected) && !isArchived) {
    outerClass += " ring-2 ring-violet-500 ring-offset-2 ring-offset-slate-950";
  }

  return (
    <div className={outerClass}>
      {/* Handles for Flow mapping */}
      <Handle
        type="target"
        position={Position.Left}
        className="w-2.5 h-2.5 !bg-slate-600 border-2 border-slate-950"
      />
      
      {/* Node Kind Header Ribbon */}
      <div className="flex items-center gap-1.5 mb-2">
        <span className="text-sm">{getKindEmoji(kind)}</span>
        <span className={`text-[10px] uppercase font-bold tracking-wider px-1.5 py-0.5 rounded text-white bg-gradient-to-r ${getKindColorClass(kind)}`}>
          {kind}
        </span>
        {isCandidate && (
          <span className="text-[9px] uppercase font-semibold px-1 py-0.5 rounded bg-purple-950/80 text-purple-300 border border-purple-800">
            Candidate
          </span>
        )}
      </div>

      {/* Title */}
      <h3 className={`font-semibold text-sm leading-tight mb-1 truncate ${isArchived ? 'line-through text-slate-600' : 'text-white'}`}>
        {title}
      </h3>

      {/* Body */}
      {body && (
        <p className={`text-[11px] leading-relaxed line-clamp-3 ${isArchived ? 'text-slate-600' : 'text-slate-400'}`}>
          {body}
        </p>
      )}

      <Handle
        type="source"
        position={Position.Right}
        className="w-2.5 h-2.5 !bg-slate-600 border-2 border-slate-950"
      />
    </div>
  );
});

CustomNodeComponent.displayName = 'CustomNodeComponent';
