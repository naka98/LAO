#!/usr/bin/env node
import express from 'express';
import cors from 'cors';
import * as fs from 'fs';
import * as path from 'path';
import { exec, spawn } from 'child_process';
import { StorageManager } from './storage';
import { AgentOrchestrator } from './agents/orchestrator';
import { SpecCompiler } from './compiler';
import { activeProcesses, getShellInfo } from './gemini';
import { randomUUID } from 'crypto';
import { NodeMessage } from './models';

const app = express();
const PORT = process.env.PORT || 4000;
const PROJECT_ROOT = process.cwd();

const storage = new StorageManager(PROJECT_ROOT);
const orchestrator = new AgentOrchestrator();

// Middleware
app.use(cors());
app.use(express.json());

// Initialize Storage on start
storage.initStorage(path.basename(PROJECT_ROOT));

// 1. Get Project Config
app.get('/api/project/config', (req, res) => {
  try {
    const config = storage.readConfig();
    res.json(config);
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 2. Save Project Config
app.post('/api/project/config', (req, res) => {
  try {
    const config = req.body;
    storage.writeConfig(config);
    res.json({ success: true, config });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 3. Switch Project Phase (Lock/Unlock specs)
app.post('/api/project/phase', (req, res) => {
  try {
    const { phase } = req.body;
    if (!phase || !['planning', 'development'].includes(phase)) {
      return res.status(400).json({ error: 'Invalid phase value' });
    }
    const config = storage.readConfig();
    config.phase = phase;
    storage.writeConfig(config);
    res.json({ success: true, config });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 4. Get Specs Sections
app.get('/api/specs', (req, res) => {
  try {
    const sections = storage.readSpecs();
    res.json(sections);
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 5. Edit Spec Section (Direct user edit or update)
app.post('/api/specs/edit', (req, res) => {
  try {
    const { id, title, content, status } = req.body;
    if (!id || !title) {
      return res.status(400).json({ error: 'id and title are required' });
    }
    const sections = storage.readSpecs();
    const existing = sections.find(s => s.id === id);
    
    const now = new Date().toISOString();
    const updatedSection = {
      id,
      title,
      content,
      status: status || 'active',
      createdAt: existing ? existing.createdAt : now,
      updatedAt: now
    };
    
    storage.writeSpecSection(updatedSection);

    // Re-compile
    const updatedSections = storage.readSpecs();
    const config = storage.readConfig();
    const md = SpecCompiler.compile(config, updatedSections);
    storage.writeCompiledSpec(md);

    res.json({ success: true, section: updatedSection });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 6. Delete (Deprecate) Spec Section
app.post('/api/specs/delete', (req, res) => {
  try {
    const { id } = req.body;
    if (!id) {
      return res.status(400).json({ error: 'id is required' });
    }
    storage.deleteSpecSection(id);

    // Re-compile
    const updatedSections = storage.readSpecs();
    const config = storage.readConfig();
    const md = SpecCompiler.compile(config, updatedSections);
    storage.writeCompiledSpec(md);

    res.json({ success: true });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 7. Get Decision Cards
app.get('/api/decisions', (req, res) => {
  try {
    const decisions = storage.readDecisions();
    res.json(decisions);
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 8. Resolve Decision Card
app.post('/api/decisions/resolve', (req, res) => {
  try {
    const { cardId, approvedOptionName, reason } = req.body;
    if (!cardId || !approvedOptionName) {
      return res.status(400).json({ error: 'cardId and approvedOptionName are required' });
    }
    
    const decisions = storage.readDecisions();
    const card = decisions.find(c => c.id === cardId);
    if (!card) {
      return res.status(404).json({ error: 'Decision card not found' });
    }

    // Set approval status
    card.options.forEach(opt => {
      opt.approved = opt.name === approvedOptionName;
    });
    card.status = 'decided';
    card.reason = reason || `Developer approved ${approvedOptionName}`;
    card.updatedAt = new Date().toISOString();

    storage.writeDecision(card);

    // Log in criteria.md
    storage.appendCriterion(`${card.section} - ${card.title}`, card.reason || '');

    res.json({ success: true, card });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 9. Get Criteria Log
app.get('/api/criteria', (req, res) => {
  try {
    const markdown = storage.readCriteria();
    res.json({ markdown });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 10. Get Chat Messages
app.get('/api/messages', (req, res) => {
  try {
    const messages = storage.readMessages();
    res.json(messages);
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 11. Compile Specifications
app.post('/api/specs/compile', (req, res) => {
  try {
    const config = storage.readConfig();
    const sections = storage.readSpecs();
    const markdown = SpecCompiler.compile(config, sections);
    const filePath = storage.writeCompiledSpec(markdown);
    res.json({ success: true, filePath, markdown });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 12. Submit Rough Idea / Intake (Autopilot Sprout)
app.post('/api/project/intake', async (req, res) => {
  try {
    const { projectName, projectDesc, automationLevel, goldenRules } = req.body;
    if (!projectName || !projectDesc) {
      return res.status(400).json({ error: 'projectName and projectDesc are required' });
    }

    // Clear specs directory to start fresh
    const specsPath = path.join(PROJECT_ROOT, '.lao', 'specs');
    if (fs.existsSync(specsPath)) {
      const files = fs.readdirSync(specsPath);
      for (const file of files) {
        if (file.endsWith('.md')) {
          fs.unlinkSync(path.join(specsPath, file));
        }
      }
      const featuresPath = path.join(specsPath, 'features');
      if (fs.existsSync(featuresPath)) {
        const featFiles = fs.readdirSync(featuresPath);
        for (const file of featFiles) {
          if (file.endsWith('.md')) {
            fs.unlinkSync(path.join(featuresPath, file));
          }
        }
      }
    }
    
    // Clear decisions folder
    const decPath = path.join(PROJECT_ROOT, '.lao', 'decisions');
    if (fs.existsSync(decPath)) {
      const files = fs.readdirSync(decPath);
      for (const file of files) {
        if (file.endsWith('.json')) {
          fs.unlinkSync(path.join(decPath, file));
        }
      }
    }

    // Initialize config
    const config = storage.initStorage(String(projectName), String(projectDesc));
    config.projectName = String(projectName);
    config.projectDesc = String(projectDesc);
    config.sprouted = true;
    config.automationLevel = automationLevel || 'supervised';
    if (goldenRules) {
      config.goldenRules = goldenRules;
    }
    config.phase = 'planning';
    storage.writeConfig(config);

    // 1. Sprout spec sections using AI
    const sprouted = await orchestrator.runIntakeSprout(config);

    // Save core spec
    const now = new Date().toISOString();
    storage.writeSpecSection({
      id: 'core_spec',
      title: 'Core Architecture Spec',
      content: sprouted.coreSpec,
      status: 'active',
      createdAt: now,
      updatedAt: now
    });

    // Save spawned features
    sprouted.features.forEach(feat => {
      storage.writeSpecSection(feat);
    });

    // 2. Propose decision cards if needed
    let decisions: any[] = [];
    if (config.automationLevel !== 'autopilot') {
      const allSections = storage.readSpecs();
      decisions = await orchestrator.runOptionizerFork(config, allSections);
      decisions.forEach(card => {
        storage.writeDecision(card);
      });
    }

    // 3. Compile
    const allSections = storage.readSpecs();
    const markdown = SpecCompiler.compile(config, allSections);
    storage.writeCompiledSpec(markdown);

    res.json({
      success: true,
      config,
      sections: allSections,
      decisions
    });
  } catch (error: any) {
    console.error('Intake API Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 13. Gap check review
app.get('/api/project/gap-check', async (req, res) => {
  try {
    const config = storage.readConfig();
    const sections = storage.readSpecs();
    const review = await orchestrator.runGapDetectorReview(config, sections);
    res.json({ review });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 14. Chat SSE streaming responder
app.get('/api/chat/stream', async (req, res) => {
  try {
    const { message } = req.query;
    if (!message) {
      return res.status(400).send('message is required');
    }

    const config = storage.readConfig();
    const sections = storage.readSpecs();
    const messages = storage.readMessages();

    // Prevent chat if spec is locked
    if (config.phase === 'development') {
      return res.status(400).send('Specification is locked during development');
    }

    const messageStr = String(message);
    const now = new Date().toISOString();

    // Write user message to store
    const userMsg: NodeMessage = {
      id: randomUUID(),
      author: 'user',
      content: messageStr,
      createdAt: now
    };
    messages.push(userMsg);
    storage.writeMessages(messages);

    // Set SSE headers
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.flushHeaders();

    const result = await orchestrator.routeAndRespondStream({
      config,
      sections,
      chatHistory: messages.slice(0, -1),
      userMessage: messageStr,
      onChunk: (chunkEvent) => {
        res.write(`data: ${JSON.stringify(chunkEvent)}\n\n`);
      }
    });

    // Write agent response to store
    const agentMsg: NodeMessage = {
      id: randomUUID(),
      author: result.route,
      content: result.prose,
      createdAt: new Date().toISOString()
    };
    messages.push(agentMsg);
    storage.writeMessages(messages);

    // Process spec update if returned
    if (result.specUpdate) {
      const existing = sections.find(s => s.id === result.specUpdate!.sectionId);
      const updatedSection = {
        id: result.specUpdate.sectionId,
        title: result.specUpdate.title || (existing ? existing.title : 'Untitled Feature'),
        content: result.specUpdate.content,
        status: existing ? existing.status : 'active',
        createdAt: existing ? existing.createdAt : now,
        updatedAt: now
      };
      storage.writeSpecSection(updatedSection);

      // Recompile
      const recompiledSections = storage.readSpecs();
      const md = SpecCompiler.compile(config, recompiledSections);
      storage.writeCompiledSpec(md);
    }

    // Send final completed payload
    const finalEvent = {
      type: 'done',
      route: result.route,
      reasoning: result.reasoning,
      prose: result.prose,
      specUpdate: result.specUpdate,
      messages,
      sections: storage.readSpecs()
    };
    
    res.write(`data: ${JSON.stringify(finalEvent)}\n\n`);
    res.end();
  } catch (error: any) {
    console.error('Chat Stream API Error:', error);
    res.write(`data: ${JSON.stringify({ type: 'error', error: error.message })}\n\n`);
    res.end();
  }
});

// 15. Run Developer Loop shell commands (SSE streaming)
app.get('/api/devloop/run', async (req, res) => {
  try {
    const { kind } = req.query;
    if (!kind || !['build', 'launch', 'verify', 'uiCheck'].includes(kind as string)) {
      return res.status(400).send('invalid command kind');
    }

    const config = storage.readConfig();
    const devLoop = config.developerLoop || {
      buildCommand: 'npm run build',
      launchCommand: 'npm start',
      verifyCommand: 'npm test',
      uiCheckCommand: ''
    };

    let command = '';
    if (kind === 'build') command = devLoop.buildCommand;
    else if (kind === 'launch') command = devLoop.launchCommand;
    else if (kind === 'verify') command = devLoop.verifyCommand;
    else if (kind === 'uiCheck') command = devLoop.uiCheckCommand;

    if (!command.trim()) {
      return res.status(400).send('Command is not configured');
    }

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.flushHeaders();

    res.write(`data: ${JSON.stringify({ type: 'start', command })}\n\n`);

    const { shell, args: shellArgs } = getShellInfo();

    const child = spawn(shell, [...shellArgs, command], {
      cwd: PROJECT_ROOT,
      env: process.env,
    });

    if (child.stdout) {
      child.stdout.on('data', (data) => {
        res.write(`data: ${JSON.stringify({ type: 'stdout', chunk: data.toString() })}\n\n`);
      });
    }

    if (child.stderr) {
      child.stderr.on('data', (data) => {
        res.write(`data: ${JSON.stringify({ type: 'stderr', chunk: data.toString() })}\n\n`);
      });
    }

    child.on('close', (code) => {
      res.write(`data: ${JSON.stringify({ type: 'exit', code: code ?? 0 })}\n\n`);
      res.end();
    });

    child.on('error', (err) => {
      res.write(`data: ${JSON.stringify({ type: 'error', error: err.message })}\n\n`);
      res.end();
    });
  } catch (error: any) {
    console.error('DevLoop Execution error:', error);
    res.write(`data: ${JSON.stringify({ type: 'error', error: error.message })}\n\n`);
    res.end();
  }
});

// Serve WebUI client assets statically
const webDistPath = path.join(__dirname, '../../web/dist');
app.use(express.static(webDistPath));

app.get(/.*/, (req, res, next) => {
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
  
  exec(`open ${url}`, (err) => {
    if (err) {
      console.log(`Could not automatically open browser. Please visit ${url} manually.`);
    }
  });
});
