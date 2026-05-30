# LAO (Leeway AI Office)

LAO is a platform-independent, developer-first AI design workflow application built with **Node.js (Express)** and **React (Vite)**. It transforms raw ideas into AI-ready, structured specifications by running local command-line interface (CLI) AI clients on your machine.

---

## Architecture Transition Rationale (React Flow -> Document-Driven Workspace)

LAO was originally designed with a visual React Flow mindmap canvas. In v0.9, we transitioned to a **Document-Driven Guided Planning Workspace** to resolve key technical and operational challenges:
1. **Reduced Cognitive Load**: Instead of micromanaging complex graph nodes and connections, the user interacts with clean document previews and high-level decision cards.
2. **Strict Guardrails (Golden Rules)**: Enforces technology guardrails (e.g. SQLite only, no Docker) by injecting them directly into the specialized agent prompts.
3. **Prevention of Spec-Code Drift**: Introduces a manual "Handover Gate" that locks the compiled specification into a read-only state during development.

---

## Key Features (v0.9.3)

1. **Local CLI AI Engine & E2BIG Bypass**: 
   * Executes queries using locally configured CLI clients (`gemini`, `claude`, `codex`, `agy`, `cursor`) via zsh processes. Uses a **non-login shell (`-c`) to minimize startup latency down to 10ms**, bypassing homebrew/node environment reloading lags.
   * Leverages shell file redirection (`<`) instead of command substitution to **completely bypass UNIX `ARG_MAX` environment limits (`E2BIG` errors)**, allowing large prompt payloads.
2. **Planning Harness & Self-Correction**:
   * Programmatically asserts (Linter) sprouted or updated specs for formatting constraints (e.g., given-when-then acceptance criteria, out of scope section).
   * Runs up to 3 self-correction iterations injecting harness feedback directly into prompt buffers.
3. **Sequential Execution Queue (Spawn Queue)**:
   * Throttles active process spawning to `maxConcurrency = 2` to prevent macOS freeze and CLI SQLite database locks (`SQLITE_BUSY`).
   * Evicts duplicate pending mockup requests and cleans up orphan processes via a 90-second timeout force-kill (`SIGKILL`).
4. **Human-In-The-Loop (HITL) Intervention UI**:
   * Renders a warning box with specific validation errors on the chat interface when 3 self-correction loops fail.
   * Provides a **[Force Commit]** bypass button, letting the developer manually override harness rules and save the specification as-is.
5. **Multi-Agent Collaboration**: Features a centralized "Director" agent routing inputs to specialized step agents, applying **Context Budgeting** to slice and send only relevant spec files.
6. **Real-time SSE Status Streaming**: Streams active agent and harness pipeline diagnostics (e.g., *"🔍 [Harness] Asserting Given-When-Then rules..."*) directly to the loader terminal to lower user waiting fatigue.
7. **5-Second Mockup Debouncing**: Throttles mockup preview generation (`MockupGenerator`) behind a 5-second debounce timer to prevent system fans from overheating during high-frequency chats.

---

## Project Structure

```
LAO/
├── cli/                 # Express backend server & CLI AI runner
│   ├── src/
│   │   ├── agents/      # Orchestrator, prompt builder, mockup generator, & harness
│   │   │   ├── harness.ts      # [NEW] PlanningHarness (specification validator & diagnostics)
│   │   │   ├── orchestrator.ts # Orchestrator for agent routing & self-correction loop
│   │   │   └── promptBuilder.ts# Prompt templates with error feedback injection
│   │   ├── compiler.ts  # Spec compiler to Markdown
│   │   ├── gemini.ts    # Spawn shell CLI client runner, stdin piping, & JSON normalizer
│   │   ├── index.ts     # Express endpoints, SSE stream routes, & debounce throttle
│   │   ├── scheduler.ts # [NEW] SpawnQueueManager (Concurrency scheduler & CPU protector)
│   │   └── storage.ts   # Persistent settings/spec storage under .lao/
│   └── package.json
└── web/                 # React Web UI (Vanilla CSS layout)
    ├── src/
    │   ├── App.tsx      # Main application dashboard, status streaming, & HITL panel
    │   └── types.ts     # Shared TS types
    └── package.json
```

---

## Quick Start & Installation

### Prerequisites
* **Node.js** v18.0.0 or higher
* **npm** v9.0.0 or higher
* **Yarn** (optional) - if using Yarn for package management
* Local AI CLI clients installed and authenticated:
  * **Gemini CLI**: `gemini` (default)
  * **Claude CLI**: `claude` (Claude Engineer)
  * **Codex CLI**: `codex`
  * **Antigravity CLI**: `agy` (optional)
  * **Cursor CLI**: `cursor` (Cursor Agent CLI) (optional)

### Setup & Launch
```bash
# Install dependencies and build the workspace automatically
npm install

# Start the application (running on port 4000)
npm start
```

---

## Environmental Configurations

You can configure default providers and specify custom CLI execution paths using a `.env` file in the `cli` folder:

```env
# Default provider and model override
LAO_PROVIDER=gemini       # Selected tool (gemini | claude | codex | agy | cursor)
LAO_MODEL=                # Override model if required

# [v0.9.3 added] Custom local CLI executable paths (if not automatically resolved in PATH)
LAO_PROVIDER_CLAUDE_CLI=/opt/homebrew/bin/claude
LAO_PROVIDER_GEMINI_CLI=/usr/local/bin/gemini
LAO_PROVIDER_CODEX_CLI=
LAO_PROVIDER_CURSOR_CLI=
LAO_PROVIDER_AGY_CLI=
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
