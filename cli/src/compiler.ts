import { MindmapData, GraphNode, GraphEdge } from './models';

export class SpecCompiler {
  /**
   * Compiles the active nodes of the mindmap into a single, cohesive Markdown document.
   * Traverses the tree hierarchy starting from the seed node.
   */
  public static compile(data: MindmapData): string {
    const seedNode = data.nodes.find((n) => n.kind === 'seed');
    if (!seedNode) {
      return '# LAO Specification\n\nNo seed node found in this mindmap.';
    }

    // Build parent-child adjacency list
    const parentToChildren = new Map<string, string[]>();
    const nodeMap = new Map<string, GraphNode>();

    data.nodes.forEach((node) => {
      nodeMap.set(node.id, node);
    });

    data.edges.forEach((edge) => {
      if (edge.kind === 'parentChild') {
        const children = parentToChildren.get(edge.fromNodeId) || [];
        children.push(edge.toNodeId);
        parentToChildren.set(edge.fromNodeId, children);
      }
    });

    const visited = new Set<string>();
    const markdownLines: string[] = [];

    // Header
    markdownLines.push(`# LAO Specification: ${seedNode.title}`);
    markdownLines.push(`*Generated at: ${new Date().toISOString()}*`);
    markdownLines.push('');
    if (data.userProfile) {
      markdownLines.push(`**Creator**: ${data.userProfile.name} (${data.userProfile.title})`);
      markdownLines.push(`**Project Context**: ${data.userProfile.bio}`);
      markdownLines.push('');
    }
    markdownLines.push('---');
    markdownLines.push('');

    // Start DFS traversal from seed node (level 1)
    this.traverseNode({
      nodeId: seedNode.id,
      depth: 1,
      nodeMap,
      parentToChildren,
      visited,
      markdownLines,
      data,
    });

    // Append decision log summary at the bottom if any criteria exist
    const decisionMsgs = data.messages.filter(
      (m) => m.author === 'director' && m.content.startsWith('[Adoption Decision]')
    );

    if (decisionMsgs.length > 0) {
      markdownLines.push('## Appendix: Decision Log & Rationale');
      markdownLines.push('Below are the comparative rationales kept during branch adoptions:');
      markdownLines.push('');
      decisionMsgs.forEach((msg) => {
        const node = nodeMap.get(msg.nodeId);
        const nodeRef = node ? ` (on node *${node.title}*)` : '';
        markdownLines.push(`> [!NOTE]`);
        markdownLines.push(`> **Decision${nodeRef}**: ${msg.content.replace('[Adoption Decision]', '').trim()}`);
        markdownLines.push(`> *Recorded: ${new Date(msg.createdAt).toLocaleDateString()}*`);
        markdownLines.push('');
      });
    }

    return markdownLines.join('\n');
  }

  private static traverseNode(params: {
    nodeId: string;
    depth: number;
    nodeMap: Map<string, GraphNode>;
    parentToChildren: Map<string, string[]>;
    visited: Set<string>;
    markdownLines: string[];
    data: MindmapData;
  }): void {
    if (params.visited.has(params.nodeId)) return;
    params.visited.add(params.nodeId);

    const node = params.nodeMap.get(params.nodeId);
    if (!node) return;

    // Skip archived/dimmed nodes in core document flow to keep it clean
    if (node.branchRole === 'archived' || node.status === 'dimmed') {
      return;
    }

    // Markdown Headers: Level 1 (#) is project root, L2 (##) is L1 nodes, L3 (###) is L2 nodes, etc.
    const headerPrefix = '#'.repeat(Math.min(params.depth, 6));
    
    // Add Node Kind badge
    let kindBadge = `\`[${node.kind.toUpperCase()}]\``;
    if (node.branchRole === 'candidate') {
      kindBadge += ' `[CANDIDATE]`';
    }

    params.markdownLines.push(`${headerPrefix} ${node.title} ${kindBadge}`);
    params.markdownLines.push('');
    
    if (node.body) {
      params.markdownLines.push(node.body);
      params.markdownLines.push('');
    } else {
      params.markdownLines.push('*(No content specified yet)*');
      params.markdownLines.push('');
    }

    // Embed latest message or conversation summary if helpful
    const recentMessages = params.data.messages
      .filter((m) => m.nodeId === node.id && m.author !== 'user')
      .slice(-2);

    if (recentMessages.length > 0) {
      params.markdownLines.push('**Recent Discussions & Decisions:**');
      recentMessages.forEach((msg) => {
        params.markdownLines.push(`- **${msg.author}**: ${msg.content}`);
      });
      params.markdownLines.push('');
    }

    params.markdownLines.push('---');
    params.markdownLines.push('');

    // Traverse children
    const childrenIds = params.parentToChildren.get(params.nodeId) || [];
    
    // Sort children: decided first, then mainline, then candidates
    const childrenNodes = childrenIds
      .map((id) => params.nodeMap.get(id))
      .filter((n): n is GraphNode => !!n)
      .sort((a, b) => {
        if (a.branchRole === 'mainline' && b.branchRole !== 'mainline') return -1;
        if (a.branchRole !== 'mainline' && b.branchRole === 'mainline') return 1;
        return 0;
      });

    childrenNodes.forEach((child) => {
      this.traverseNode({
        nodeId: child.id,
        depth: params.depth + 1,
        nodeMap: params.nodeMap,
        parentToChildren: params.parentToChildren,
        visited: params.visited,
        markdownLines: params.markdownLines,
        data: params.data,
      });
    });
  }
}
