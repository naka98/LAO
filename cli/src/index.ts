#!/usr/bin/env node
import express from 'express';
import cors from 'cors';
import * as fs from 'fs';
import * as path from 'path';
import { exec, spawn } from 'child_process';
import { StorageManager } from './storage';
import { AgentOrchestrator } from './agents/orchestrator';
import { SpecCompiler } from './compiler';
import { activeProcesses, getShellInfo, GeminiClient } from './gemini';
import { randomUUID } from 'crypto';
import { NodeMessage } from './models';
import { MockupGenerator } from './agents/mockupGenerator';
import { PlanningHarness } from './agents/harness';

const app = express();
const PORT = process.env.PORT || 4000;
const PROJECT_ROOT = process.cwd();

const storage = new StorageManager(PROJECT_ROOT);
const orchestrator = new AgentOrchestrator();

// 글로벌 Mockup 스로틀 타이머
let mockupTimeout: NodeJS.Timeout | null = null;

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
app.post('/api/project/phase', async (req, res) => {
  try {
    const { phase } = req.body;
    if (!phase || !['planning', 'development'].includes(phase)) {
      return res.status(400).json({ error: 'Invalid phase value' });
    }
    const config = storage.readConfig();
    config.phase = phase;
    storage.writeConfig(config);

    let tasksGenerated = false;
    if (phase === 'development') {
      const existingTasks = storage.readTasksRaw();
      if (!existingTasks.trim()) {
        const sections = storage.readSpecs();
        const generatedTasks = await orchestrator.runTaskSprout(config, sections);
        storage.writeTasksRaw(generatedTasks);
        tasksGenerated = true;
      }
    }

    res.json({ success: true, config, tasksGenerated });
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
// 12. Submit Rough Idea / Intake (Autopilot Propose Options)
app.post('/api/project/intake/propose', async (req, res) => {
  try {
    const { projectName, projectDesc, automationLevel, goldenRules, provider, model, feedback } = req.body;
    if (!projectName || !projectDesc) {
      return res.status(400).json({ error: 'projectName and projectDesc are required' });
    }

    // Only clear on first run (no feedback)
    if (!feedback) {
      storage.clearOnboardingFiles();
    }

    // Initialize config
    const config = storage.initStorage(String(projectName), String(projectDesc));
    config.projectName = String(projectName);
    config.projectDesc = String(projectDesc);
    config.sprouted = false;
    config.automationLevel = automationLevel || 'supervised';
    if (goldenRules) {
      config.goldenRules = goldenRules;
    }
    if (provider) {
      config.settings.provider = provider;
      Object.keys(config.settings.agents).forEach(role => {
        config.settings.agents[role as keyof typeof config.settings.agents].provider = provider;
      });
    }
    if (model !== undefined) {
      config.settings.model = model;
      Object.keys(config.settings.agents).forEach(role => {
        config.settings.agents[role as keyof typeof config.settings.agents].model = model;
      });
    }
    config.phase = 'planning';
    config.onboardingStep = 2; // Move to step 2 (selection)
    storage.writeConfig(config);

    // 1. Sprout three distinct planning options using AI
    const proposals = await orchestrator.runIntakeDivergence(config, feedback);

    // Save proposals and update config
    storage.writeProposals(proposals);
    config.proposals = proposals;
    storage.writeConfig(config);

    res.json({
      success: true,
      config,
      proposals
    });
  } catch (error: any) {
    console.error('Intake Propose API Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// 12.5. Confirm Chosen Option and Sprout Core Spec + Features
app.post('/api/project/intake/select', async (req, res) => {
  try {
    const { selectedOptionKey, userAdjustments } = req.body;
    if (!selectedOptionKey || !['A', 'B', 'C'].includes(selectedOptionKey)) {
      return res.status(400).json({ error: 'Valid selectedOptionKey (A, B, or C) is required' });
    }

    const config = storage.readConfig();
    const proposals = storage.readProposals();
    if (!proposals) {
      return res.status(400).json({ error: 'No active proposals found. Please run intake/propose first.' });
    }

    const chosenOption = proposals.options[selectedOptionKey as 'A' | 'B' | 'C'];
    config.selectedOptionKey = selectedOptionKey;
    config.onboardingStep = 3;
    storage.writeConfig(config);

    // 1. Sprout spec sections using AI, conforming to chosen option and custom adjustments
    const sprouted = await orchestrator.runIntakeSprout(config, chosenOption, userAdjustments);

    // Save core spec as draft
    const now = new Date().toISOString();
    const coreSpecSection = {
      id: 'core_spec',
      title: 'Core Architecture Spec',
      content: sprouted.coreSpec,
      status: 'active' as const,
      createdAt: now,
      updatedAt: now
    };
    storage.writeDraftSpecSection(coreSpecSection);

    // Save spawned features as draft
    sprouted.features.forEach(feat => {
      storage.writeDraftSpecSection(feat);
    });

    // Commit specs from draft (since intake sprout already handles harness internally)
    storage.commitDraftSpecSection('core_spec');
    sprouted.features.forEach(feat => {
      storage.commitDraftSpecSection(feat.id);
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

    // Set sprouted true
    config.sprouted = true;
    storage.writeConfig(config);

    res.json({
      success: true,
      config,
      sections: allSections,
      decisions
    });
  } catch (error: any) {
    console.error('Intake Select API Error:', error);
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

// 13.2. Local environment diagnostics
app.get('/api/diagnostics', async (req, res) => {
  try {
    const report = await PlanningHarness.runDiagnostics();
    res.json(report);
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 13.5. Serve design mockup HTML for preview during planning phase
app.get('/api/project/mockup', (req, res) => {
  try {
    const mockupPath = path.join(PROJECT_ROOT, '.lao', 'mockup.html');
    if (!fs.existsSync(mockupPath)) {
      return res.status(404).send('Mockup file not found at .lao/mockup.html. Please ensure it is generated.');
    }
    res.sendFile(mockupPath, { dotfiles: 'allow' });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 14. Chat SSE streaming responder
app.get('/api/chat/stream', async (req, res) => {
  const controller = new AbortController();
  const signal = controller.signal;

  req.on('close', () => {
    console.log('[LAO Core] SSE Chat stream client closed request, aborting execution...');
    controller.abort();
  });

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
    const requestUuid = randomUUID().substring(0, 8);

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
        if (!signal.aborted) {
          res.write(`data: ${JSON.stringify(chunkEvent)}\n\n`);
        }
      },
      abortSignal: signal,
      requestUuid
    });

    if (signal.aborted) {
      res.end();
      return;
    }

    // Write agent response to store
    const agentMsg: NodeMessage = {
      id: randomUUID(),
      author: result.route,
      content: result.prose,
      createdAt: new Date().toISOString()
    };
    messages.push(agentMsg);
    storage.writeMessages(messages);

    // Process spec update if returned (샌드박스 드래프트 스테이징 및 원자적 커밋)
    if (result.specUpdate) {
      const existing = sections.find(s => s.id === result.specUpdate!.sectionId);
      const updatedSection = {
        id: result.specUpdate.sectionId,
        title: result.specUpdate.title || (existing ? existing.title : 'Untitled Feature'),
        content: result.specUpdate.content,
        status: (existing ? existing.status : 'active') as 'active' | 'deprecated',
        createdAt: existing ? existing.createdAt : now,
        updatedAt: now
      };

      try {
        // 1. 임시 드래프트 파일 작성 (요청 UUID 별 격리)
        storage.writeDraftSpecSection(updatedSection, requestUuid);

        if (!result.validationErrors) {
          // 2. 검증 성공 시 정식 파일로 커밋 승격
          storage.commitDraftSpecSection(updatedSection.id, requestUuid);

          // Recompile
          const recompiledSections = storage.readSpecs();
          const md = SpecCompiler.compile(config, recompiledSections);
          storage.writeCompiledSpec(md);
        } else {
          // 3. 검증 실패 시 드래프트 파일 롤백(제거)
          console.warn('[LAO Core] specUpdate rejected due to validation failures:', result.validationErrors);
          storage.rollbackDraftSpecSection(updatedSection.id, requestUuid);
        }
      } catch (writeErr) {
        console.error('[LAO Core] Error writing/committing spec update:', writeErr);
        try {
          storage.rollbackDraftSpecSection(updatedSection.id, requestUuid);
        } catch (cleanupErr) {
          console.error('[LAO Core] Failed to cleanup draft file after exception:', cleanupErr);
        }
        throw writeErr;
      }
    }

    const shouldUpdateMockup = (!!result.specUpdate && !result.validationErrors) || 
      /디자인|스타일|테마|색상|ui|버튼|레이아웃|화면|미리보기|다크|화이트|폰트|글꼴|우선순위|mockup|preview|style|theme|color|dark|light/i.test(messageStr);

    if (shouldUpdateMockup) {
      // Write chunk to stream notifying of mockup generation
      res.write(`data: ${JSON.stringify({ type: 'content', chunk: '\n\n*(AI가 5초의 스로틀 대기 후 변경된 기획안 시안 미리보기를 갱신합니다...)*' })}\n\n`);
      res.write(`data: ${JSON.stringify({ type: 'mockup_updating' })}\n\n`);

      if (mockupTimeout) clearTimeout(mockupTimeout);
      mockupTimeout = setTimeout(async () => {
        try {
          const currentSections = storage.readSpecs();
          await MockupGenerator.generateOrUpdate(PROJECT_ROOT, config, currentSections, messageStr);
          console.log('[LAO Core] Mockup rendering updated after 5s debounce.');
        } catch (err: any) {
          console.error('[LAO Core] Mockup generation failed:', err);
        }
      }, 5000); // 5초 디바운싱(스로틀 가드)
    }

    // Send final completed payload
    const finalEvent = {
      type: 'done',
      route: result.route,
      reasoning: result.reasoning,
      prose: result.prose,
      specUpdate: result.specUpdate,
      validationErrors: result.validationErrors, // 검증 에러 목록 전송
      messages,
      sections: storage.readSpecs()
    };
    
    res.write(`data: ${JSON.stringify(finalEvent)}\n\n`);
    res.end();
  } catch (error: any) {
    console.error('Chat Stream API Error:', error);
    if (!signal.aborted) {
      res.write(`data: ${JSON.stringify({ type: 'error', error: error.message })}\n\n`);
    }
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
    if (config.phase !== 'development') {
      return res.status(400).send('DevLoop commands are only available in the development phase');
    }
    const devLoop = config.developerLoop || {
      buildCommand: 'npm run build',
      launchCommand: 'npx -y http-server web/dist -p 3000',
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

    let accumulatedStdout = '';
    let accumulatedStderr = '';

    if (child.stdout) {
      child.stdout.on('data', (data) => {
        const chunk = data.toString();
        accumulatedStdout += chunk;
        res.write(`data: ${JSON.stringify({ type: 'stdout', chunk })}\n\n`);
      });
    }

    if (child.stderr) {
      child.stderr.on('data', (data) => {
        const chunk = data.toString();
        accumulatedStderr += chunk;
        res.write(`data: ${JSON.stringify({ type: 'stderr', chunk })}\n\n`);
      });
    }

    child.on('close', async (code) => {
      if (code !== 0) {
        try {
          const geminiClient = new GeminiClient();
          const prompt = `실행한 명령어: ${command}\n\n[실행 로그 (stderr)]\n${accumulatedStderr}\n\n[실행 로그 (stdout)]\n${accumulatedStdout}\n\n위 명령어가 실행 중 실패했습니다. 개발자가 이 에러를 쉽게 이해하고 대처할 수 있도록, 원인 분석과 대처 방법을 친절하고 구체적인 한국어(Korean)로 설명해주세요.`;
          
          res.write(`data: ${JSON.stringify({ type: 'stdout', chunk: '\n[AI 오류 분석 시작...]\n' })}\n\n`);
          const explanation = await geminiClient.generateText({
            prompt,
          });
          res.write(`data: ${JSON.stringify({ type: 'explanation', text: explanation })}\n\n`);
        } catch (e: any) {
          console.error('[LAO Core] AI explanation error:', e);
          res.write(`data: ${JSON.stringify({ type: 'explanation', text: `AI 오류 분석 중 에러가 발생했습니다: ${e.message}` })}\n\n`);
        }
      }
      res.write(`data: ${JSON.stringify({ type: 'exit', code: code ?? 0 })}\n\n`);
      res.end();
    });

    child.on('error', async (err) => {
      try {
        const geminiClient = new GeminiClient();
        const prompt = `실행하려던 명령어: ${command}\n\n오류 내용:\n${err.message}\n\n명령어를 실행하지 못하고 spawn 에러가 발생했습니다. 원인과 해결 방법을 한국어로 설명해주세요.`;
        const explanation = await geminiClient.generateText({ prompt });
        res.write(`data: ${JSON.stringify({ type: 'explanation', text: explanation })}\n\n`);
      } catch (e: any) {
        console.error('[LAO Core] AI explanation error on child error:', e);
      }
      res.write(`data: ${JSON.stringify({ type: 'error', error: err.message })}\n\n`);
      res.end();
    });
  } catch (error: any) {
    console.error('DevLoop Execution error:', error);
    res.write(`data: ${JSON.stringify({ type: 'error', error: error.message })}\n\n`);
    res.end();
  }
});

// 16. Get Checklist Tasks
app.get('/api/tasks', (req, res) => {
  try {
    const raw = storage.readTasksRaw();
    const parsed = storage.readTasksParsed();
    res.json({ raw, parsed });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 17. Toggle Checklist Task
app.post('/api/tasks/toggle', (req, res) => {
  try {
    const { index, status } = req.body;
    if (index === undefined || !status) {
      return res.status(400).json({ error: 'index and status are required' });
    }
    storage.updateTaskStatus(Number(index), status);
    const raw = storage.readTasksRaw();
    const parsed = storage.readTasksParsed();
    res.json({ success: true, raw, parsed });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
  }
});

// 18. Generate/Re-generate Checklist Tasks
app.post('/api/tasks/generate', async (req, res) => {
  try {
    const config = storage.readConfig();
    const sections = storage.readSpecs();
    const generatedTasks = await orchestrator.runTaskSprout(config, sections);
    storage.writeTasksRaw(generatedTasks);
    const parsed = storage.readTasksParsed();
    res.json({ success: true, raw: generatedTasks, parsed });
  } catch (error: any) {
    res.status(500).json({ error: error.message });
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
