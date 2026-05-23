export type GraphNodeKind = 'seed' | 'starter' | 'free' | 'decision' | 'option' | 'research' | 'gap';
export type GraphNodeStatus = 'pending' | 'exploring' | 'decided' | 'dimmed' | 'folded';
export type GraphNodeBranchRole = 'mainline' | 'candidate' | 'archived';

export interface Position {
  x: number;
  y: number;
}

export interface GraphNode {
  id: string;
  kind: GraphNodeKind;
  status: GraphNodeStatus;
  branchRole: GraphNodeBranchRole;
  title: string;
  body: string;
  position: Position;
  createdAt: string;
  updatedAt: string;
}

export type GraphEdgeKind = 'parentChild' | 'sibling' | 'reference' | 'supersedes';

export interface GraphEdge {
  id: string;
  fromNodeId: string;
  toNodeId: string;
  kind: GraphEdgeKind;
  createdAt: string;
}

export type NodeMessageAuthor = 'user' | 'director' | 'specifier' | 'researcher' | 'optionizer' | 'gapDetector';

export interface NodeMessage {
  id: string;
  nodeId: string;
  author: NodeMessageAuthor;
  content: string;
  createdAt: string;
}

export interface UserProfile {
  name: string;
  title: string;
  bio: string;
}

export interface MindmapData {
  nodes: GraphNode[];
  edges: GraphEdge[];
  messages: NodeMessage[];
  userProfile?: UserProfile;
}

export interface NodeProposal {
  title: string;
  body: string;
}

export type ParsedProposal =
  | { type: 'none' }
  | { type: 'child'; proposal: NodeProposal }
  | { type: 'branches'; proposals: NodeProposal[] };
