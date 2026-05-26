import React, { useEffect, useMemo } from 'react';
import {
  ReactFlow,
  MiniMap,
  Controls,
  Background,
  useNodesState,
  useEdgesState,
  BackgroundVariant,
  Panel,
} from '@xyflow/react';
import type { Node, Edge } from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import { CustomNodeComponent } from './CustomNode';
import type { GraphNode, GraphEdge } from '../types';
import { Plus } from 'lucide-react';

interface MindmapCanvasProps {
  nodes: GraphNode[];
  edges: GraphEdge[];
  selectedNodeId: string | null;
  onSelectNode: (nodeId: string | null) => void;
  onNodeDragStop: (id: string, position: { x: number; y: number }) => void;
  onAddFreeNode: () => void;
}

const nodeTypes = {
  custom: CustomNodeComponent,
};

export const MindmapCanvas: React.FC<MindmapCanvasProps> = ({
  nodes,
  edges,
  selectedNodeId,
  onSelectNode,
  onNodeDragStop,
  onAddFreeNode,
}) => {
  const [flowNodes, setFlowNodes, onNodesChange] = useNodesState<Node>([]);
  const [flowEdges, setFlowEdges, onEdgesChange] = useEdgesState<Edge>([]);

  // Map LAO nodes to React Flow nodes format
  const mappedNodes = useMemo(() => {
    return nodes.map((node) => ({
      id: node.id,
      type: 'custom',
      position: node.position,
      data: {
        title: node.title,
        body: node.body,
        kind: node.kind,
        status: node.status,
        branchRole: node.branchRole,
        isSelected: node.id === selectedNodeId,
      },
    }));
  }, [nodes, selectedNodeId]);

  // Map LAO edges to React Flow edges format
  const mappedEdges = useMemo(() => {
    return edges.map((edge) => {
      let strokeColor = '#2a2f42';
      let strokeDash = undefined;

      if (edge.kind === 'supersedes') {
        strokeColor = '#e11d48'; // red
        strokeDash = '5,5';
      } else if (edge.kind === 'sibling') {
        strokeColor = '#a855f7'; // purple
        strokeDash = '3,3';
      } else if (edge.kind === 'reference') {
        strokeColor = '#0ea5e9'; // sky-blue
        strokeDash = '4,4';
      }

      return {
        id: edge.id,
        source: edge.fromNodeId,
        target: edge.toNodeId,
        type: 'smoothstep',
        style: {
          stroke: strokeColor,
          strokeWidth: 2,
          strokeDasharray: strokeDash,
        },
      };
    });
  }, [edges]);

  // Sync state whenever props change
  useEffect(() => {
    setFlowNodes(mappedNodes);
  }, [mappedNodes, setFlowNodes]);

  useEffect(() => {
    setFlowEdges(mappedEdges);
  }, [mappedEdges, setFlowEdges]);

  return (
    <div className="flex-1 h-full relative">
      <ReactFlow
        nodes={flowNodes}
        edges={flowEdges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        nodeTypes={nodeTypes}
        onNodeClick={(_, node) => onSelectNode(node.id)}
        onPaneClick={() => onSelectNode(null)}
        onNodeDragStop={(_, node) => onNodeDragStop(node.id, node.position)}
        fitView
      >
        <Background variant={BackgroundVariant.Dots} gap={16} size={1} />
        <Controls />
        <MiniMap
          nodeColor={(n) => {
            const data = n.data as any;
            if (data?.kind === 'seed') return '#6366f1';
            if (data?.branchRole === 'archived') return '#1e293b';
            if (data?.branchRole === 'candidate') return '#c084fc';
            return '#334155';
          }}
          maskColor="rgba(11, 13, 20, 0.7)"
          className="!bg-slate-900 border border-slate-800"
        />

        {/* Floating panel for Canvas actions */}
        <Panel position="top-left" className="flex gap-2">
          <button
            onClick={onAddFreeNode}
            className="flex items-center gap-1 px-3 py-2 rounded-lg bg-slate-900 border border-slate-800 hover:bg-slate-800 text-xs font-semibold text-slate-200 shadow-lg cursor-pointer transition-colors"
          >
            <Plus size={14} /> Add Free Node
          </button>
        </Panel>
      </ReactFlow>
    </div>
  );
};
