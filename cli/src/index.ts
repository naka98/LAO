import express from 'express';
import cors from 'cors';
import * as path from 'path';
import { exec } from 'child_process';
import { StorageManager } from './storage';
import { AgentOrchestrator } from './agents/orchestrator';
import { SpecCompiler } from './compiler';

const app = express();
const PORT = process.env.PORT || 4000;
const PROJECT_ROOT = process.cwd(); // Run CLI server in the user's active directory

const storage = new StorageManager(PROJECT_ROOT);
const orchestrator = new AgentOrchestrator();

// Middleware
app.use(cors());
app.use(express.json());

// Initialize Storage on start
storage.initStorage(path.basename(PROJECT_ROOT));

// 1. Get Mindmap Data
app.get('/api/mindmap', (req, res) => {
  try {
    const data = storage.readMindmap();
    res.json(data);
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 2. Save Mindmap Data
app.post('/api/mindmap', (req, res) => {
  try {
    const data = req.body;
    storage.writeMindmap(data);
    res.json({ success: true });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 3. Send Message / AI Agent Chat & Routing
app.post('/api/chat', async (req, res) => {
  try {
    const { nodeId, message } = req.body;
    if (!nodeId || !message) {
      return res.status(400).json({ error: 'nodeId and message are required' });
    }

    const data = storage.readMindmap();
    const seedNode = data.nodes.find(n => n.kind === 'seed');
    const projectName = seedNode ? seedNode.title : path.basename(PROJECT_ROOT);
    const projectDesc = data.userProfile?.bio || '';

    const result = await orchestrator.routeAndRespond({
      data,
      projectName,
      projectDesc,
      focusedNodeId: nodeId,
      userMessage: message,
    });

    // Save updated data
    storage.writeMindmap(result.updatedData);

    res.json({
      route: result.route,
      reasoning: result.reasoning,
      prose: result.prose,
      proposal: result.proposal,
      mindmap: result.updatedData,
    });
  } catch (error: any) {
    console.error('Chat API Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 4. Adopt a Candidate Node as Mainline
app.post('/api/adopt', async (req, res) => {
  try {
    const { parentNodeId, adoptedNodeId, siblingNodeIds } = req.body;
    if (!parentNodeId || !adoptedNodeId) {
      return res.status(400).json({ error: 'parentNodeId and adoptedNodeId are required' });
    }

    const data = storage.readMindmap();
    const seedNode = data.nodes.find(n => n.kind === 'seed');
    const projectName = seedNode ? seedNode.title : path.basename(PROJECT_ROOT);
    const projectDesc = data.userProfile?.bio || '';

    const result = await orchestrator.generateAdoptionReason({
      data,
      projectName,
      projectDesc,
      parentNodeId,
      adoptedNodeId,
      siblingNodeIds: siblingNodeIds || [],
    });

    // Log this adoption inside criteria.md
    const adoptedNode = data.nodes.find(n => n.id === adoptedNodeId);
    if (adoptedNode) {
      storage.appendCriterion(adoptedNode.title, result.reasoning);
    }

    // Save updated data
    storage.writeMindmap(result.updatedData);

    res.json({
      success: true,
      reasoning: result.reasoning,
      mindmap: result.updatedData,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 5. Merge Candidate Nodes
app.post('/api/merge', async (req, res) => {
  try {
    const { parentNodeId, candidateIds } = req.body;
    if (!parentNodeId || !candidateIds || !Array.isArray(candidateIds) || candidateIds.length === 0) {
      return res.status(400).json({ error: 'parentNodeId and candidateIds array are required' });
    }

    const data = storage.readMindmap();
    const seedNode = data.nodes.find(n => n.kind === 'seed');
    const projectName = seedNode ? seedNode.title : path.basename(PROJECT_ROOT);
    const projectDesc = data.userProfile?.bio || '';

    const result = await orchestrator.mergeNodes({
      data,
      projectName,
      projectDesc,
      parentNodeId,
      candidateIds,
    });

    storage.writeMindmap(result.updatedData);

    res.json({
      success: true,
      mergedNode: result.mergedNode,
      mindmap: result.updatedData,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 6. Compile Mindmap to Markdown Specification Document
app.post('/api/compile', (req, res) => {
  try {
    const data = storage.readMindmap();
    const markdown = SpecCompiler.compile(data);
    const filePath = storage.writeCompiledSpec(markdown);
    res.json({
      success: true,
      filePath,
      markdown,
    });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 7. Get Decision Log (Criteria.md)
app.get('/api/criteria', (req, res) => {
  try {
    const markdown = storage.readCriteria();
    res.json({ markdown });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 8. Get CLI settings
app.get('/api/settings', (req, res) => {
  try {
    const settings = storage.readSettings();
    res.json(settings);
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 9. Save CLI settings
app.post('/api/settings', (req, res) => {
  try {
    const { provider, model, agents } = req.body;
    if (!provider) {
      return res.status(400).json({ error: 'provider is required' });
    }
    const updatedSettings = {
      provider,
      model: model || '',
      agents,
    };
    storage.writeSettings(updatedSettings);
    res.json({ success: true, settings: updatedSettings });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// Serve WebUI client assets statically if they exist (production fallback)
const webDistPath = path.join(__dirname, '../../web/dist');
app.use(express.static(webDistPath));

app.get(/.*/, (req, res, next) => {
  // If request is not for API, serve index.html
  if (req.path.startsWith('/api')) {
    return next();
  }
  res.sendFile(path.join(webDistPath, 'index.html'), (err) => {
    if (err) {
      res.status(404).send('Web UI not compiled. Run "npm run build" in web directory.');
    }
  });
});

// Start listening
app.listen(PORT, () => {
  console.log(`==========================================`);
  console.log(`  LAO 0.9 Core Engine running locally!`);
  console.log(`  Project path: ${PROJECT_ROOT}`);
  console.log(`  API Endpoint: http://localhost:${PORT}`);
  console.log(`==========================================`);

  const url = `http://localhost:${PORT}`;
  
  // Auto-open browser in Mac (since user OS is Mac)
  exec(`open ${url}`, (err) => {
    if (err) {
      console.log(`Could not automatically open browser. Please visit ${url} manually.`);
    }
  });
});
