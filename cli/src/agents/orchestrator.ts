import { MindmapData, GraphNode, GraphEdge, NodeMessage, NodeMessageAuthor } from '../models';
import { GeminiClient } from '../gemini';
import { PromptBuilder, ParsedProposal } from './promptBuilder';
import { randomUUID } from 'crypto';

export interface RouteAndRespondResult {
  route: 'specifier' | 'researcher' | 'optionizer' | 'gapDetector';
  reasoning: string;
  prose: string;
  proposal: ParsedProposal;
  updatedData: MindmapData;
}

export class AgentOrchestrator {
  private geminiClient: GeminiClient;

  constructor() {
    this.geminiClient = new GeminiClient();
  }

  /**
   * Routes the client message and gets a response from the designated step agent.
   */
  public async routeAndRespond(params: {
    data: MindmapData;
    projectName: string;
    projectDesc: string;
    focusedNodeId: string;
    userMessage: string;
  }): Promise<RouteAndRespondResult> {
    const data = JSON.parse(JSON.stringify(params.data)) as MindmapData; // deep clone
    const focusedNode = data.nodes.find(n => n.id === params.focusedNodeId);
    if (!focusedNode) {
      throw new Error(`Focused node not found: ${params.focusedNodeId}`);
    }

    const seedNode = data.nodes.find(n => n.kind === 'seed') || focusedNode;

    // Filter chat history for this node
    const nodeHistory = data.messages.filter(m => m.nodeId === params.focusedNodeId);

    // Save user message to history first
    const userMsgId = randomUUID();
    const now = new Date().toISOString();
    const userMsg: NodeMessage = {
      id: userMsgId,
      nodeId: params.focusedNodeId,
      author: 'user',
      content: params.userMessage,
      createdAt: now,
    };
    data.messages.push(userMsg);
    nodeHistory.push(userMsg);

    // 1. Director Routing
    const directorPrompt = PromptBuilder.buildDirectorRoutingPrompt({
      projectName: params.projectName,
      projectDesc: params.projectDesc,
      ideaTitle: seedNode.title,
      focusedNode,
      chatHistory: nodeHistory.slice(0, -1), // skip the latest user msg for classification context
      userMessage: params.userMessage,
    });

    let route: 'specifier' | 'researcher' | 'optionizer' | 'gapDetector' = 'specifier';
    let routingReason = 'Vague intent fallback';

    try {
      const directorResponseRaw = await this.geminiClient.generateText({
        prompt: directorPrompt,
        jsonMode: true,
        role: 'director',
      });

      const parsedRouting = JSON.parse(directorResponseRaw);
      if (
        parsedRouting.route &&
        ['specifier', 'researcher', 'optionizer', 'gapDetector'].includes(parsedRouting.route)
      ) {
        route = parsedRouting.route;
        routingReason = parsedRouting.reasoning || '';
      }
    } catch (e) {
      console.warn('Director routing failed or parsed incorrectly. Falling back to specifier.', e);
    }

    // 2. Step Agent Response
    const stepPrompt = PromptBuilder.buildStepPrompt({
      agentType: route,
      projectName: params.projectName,
      projectDesc: params.projectDesc,
      ideaTitle: seedNode.title,
      focusedNode,
      chatHistory: nodeHistory,
      userProfile: data.userProfile || { name: 'Designer', title: 'Product Creator', bio: '' },
    });

    const stepResponseRaw = await this.geminiClient.generateText({
      prompt: stepPrompt,
      jsonMode: false,
      role: route,
    });

    // 3. Extract Optional Proposals
    const { prose, kind } = PromptBuilder.extractAnyProposal(stepResponseRaw);

    // 4. Save Agent Message to history
    const agentMsgId = randomUUID();
    const agentMsg: NodeMessage = {
      id: agentMsgId,
      nodeId: params.focusedNodeId,
      author: route as NodeMessageAuthor,
      content: prose,
      createdAt: new Date().toISOString(),
    };
    data.messages.push(agentMsg);

    focusedNode.updatedAt = new Date().toISOString();

    return {
      route,
      reasoning: routingReason,
      prose,
      proposal: kind,
      updatedData: data,
    };
  }

  /**
   * Generates comparative reasoning when user adopts a node, saving the log.
   */
  public async generateAdoptionReason(params: {
    data: MindmapData;
    projectName: string;
    projectDesc: string;
    parentNodeId: string;
    adoptedNodeId: string;
    siblingNodeIds: string[];
  }): Promise<{ reasoning: string; updatedData: MindmapData }> {
    const data = JSON.parse(JSON.stringify(params.data)) as MindmapData;
    
    const parentNode = data.nodes.find(n => n.id === params.parentNodeId);
    const adoptedNode = data.nodes.find(n => n.id === params.adoptedNodeId);
    const siblingNodes = data.nodes.filter(n => params.siblingNodeIds.includes(n.id));

    if (!parentNode || !adoptedNode) {
      throw new Error('Parent or adopted node not found');
    }

    const seedNode = data.nodes.find(n => n.kind === 'seed') || parentNode;
    const history = data.messages.filter(m => m.nodeId === params.parentNodeId);

    const prompt = PromptBuilder.buildAdoptionReasoningPrompt({
      projectName: params.projectName,
      projectDesc: params.projectDesc,
      ideaTitle: seedNode.title,
      parentNode,
      adopted: adoptedNode,
      siblings: siblingNodes,
      chatHistory: history,
    });

    let reasoning = `Adopted ${adoptedNode.title} as mainline.`;
    try {
      reasoning = await this.geminiClient.generateText({ prompt, role: 'director' });
    } catch (e) {
      console.warn('Failed to generate adoption reason from Gemini, using fallback.', e);
    }

    // Add Director explanation message
    const msgId = randomUUID();
    data.messages.push({
      id: msgId,
      nodeId: params.parentNodeId,
      author: 'director',
      content: `[Adoption Decision] ${reasoning}`,
      createdAt: new Date().toISOString(),
    });

    // Mark adopted node status as decided and mainline
    adoptedNode.status = 'decided';
    adoptedNode.branchRole = 'mainline';
    adoptedNode.updatedAt = new Date().toISOString();

    // Sibling nodes become dimmed and archived/candidate
    siblingNodes.forEach(sibling => {
      sibling.status = 'folded';
      sibling.branchRole = 'archived';
      sibling.updatedAt = new Date().toISOString();
    });

    return {
      reasoning,
      updatedData: data,
    };
  }

  /**
   * Merges multiple candidate nodes into one mainline node.
   */
  public async mergeNodes(params: {
    data: MindmapData;
    projectName: string;
    projectDesc: string;
    parentNodeId: string;
    candidateIds: string[];
  }): Promise<{ mergedNode: GraphNode; updatedData: MindmapData }> {
    const data = JSON.parse(JSON.stringify(params.data)) as MindmapData;

    const parentNode = data.nodes.find(n => n.id === params.parentNodeId);
    const candidates = data.nodes.filter(n => params.candidateIds.includes(n.id));

    if (!parentNode || candidates.length === 0) {
      throw new Error('Parent node or candidates not found');
    }

    const seedNode = data.nodes.find(n => n.kind === 'seed') || parentNode;
    const history = data.messages.filter(m => m.nodeId === params.parentNodeId);

    const prompt = PromptBuilder.buildMergePrompt({
      projectName: params.projectName,
      projectDesc: params.projectDesc,
      ideaTitle: seedNode.title,
      parentNode,
      candidates,
      chatHistory: history,
    });

    let mergedTitle = 'Merged Concept';
    let mergedBody = 'Synthesized from multiple choices.';
    let reasoning = 'Merged selected nodes.';

    try {
      const responseRaw = await this.geminiClient.generateText({ prompt, jsonMode: true, role: 'director' });
      const parsed = JSON.parse(responseRaw);
      mergedTitle = parsed.title || mergedTitle;
      mergedBody = parsed.body || mergedBody;
      reasoning = parsed.reasoning || reasoning;
    } catch (e) {
      console.warn('Merge synthesis call failed, using default fallback.', e);
    }

    const now = new Date().toISOString();
    const mergedNodeId = randomUUID();

    // Create the merged node
    const mergedNode: GraphNode = {
      id: mergedNodeId,
      kind: 'free',
      status: 'decided',
      branchRole: 'mainline',
      title: mergedTitle,
      body: mergedBody,
      position: {
        x: parentNode.position.x + 200,
        y: parentNode.position.y,
      },
      createdAt: now,
      updatedAt: now,
    };

    data.nodes.push(mergedNode);

    // Create parent -> child edge
    const parentEdge: GraphEdge = {
      id: randomUUID(),
      fromNodeId: params.parentNodeId,
      toNodeId: mergedNodeId,
      kind: 'parentChild',
      createdAt: now,
    };
    data.edges.push(parentEdge);

    // Create 'supersedes' edges from candidates to mergedNode, and change candidates to archived
    candidates.forEach(candidate => {
      candidate.status = 'folded';
      candidate.branchRole = 'archived';
      candidate.updatedAt = now;

      data.edges.push({
        id: randomUUID(),
        fromNodeId: candidate.id,
        toNodeId: mergedNodeId,
        kind: 'supersedes',
        createdAt: now,
      });
    });

    // Add Director explanation message
    data.messages.push({
      id: randomUUID(),
      nodeId: params.parentNodeId,
      author: 'director',
      content: `[Merge Synthesis] ${reasoning}`,
      createdAt: now,
    });

    return {
      mergedNode,
      updatedData: data,
    };
  }
}
