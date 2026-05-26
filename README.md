# LAO (Local AI Office)

LAO is a platform-independent, developer-first AI design workflow application built with **Node.js (Express)** and **React (Vite)**. It transforms raw ideas into AI-ready, structured specifications by running local command-line interface (CLI) AI clients on your machine.

---

## Architecture Transition Rationale (React Flow -> Document-Driven Workspace)

LAO was originally designed with a visual React Flow mindmap canvas. In v0.9, we transitioned to a **Document-Driven Guided Planning Workspace** to resolve key technical and operational challenges:
1. **Reduced Cognitive Load**: Instead of micromanaging complex graph nodes and connections, the user interacts with clean document previews and high-level decision cards.
2. **Strict Guardrails (Golden Rules)**: Enforces technology guardrails (e.g. SQLite only, no Docker) by injecting them directly into the specialized agent prompts.
3. **Prevention of Spec-Code Drift**: Introduces a manual "Handover Gate" that locks the compiled specification into a read-only state during development.

---

## Key Features

1. **Local CLI AI Engine**: Executes queries using your locally configured CLI clients (`gemini`, `claude`, `codex`, `agy`) via shell processes. All prompt contents are handled through secure temp files.
2. **Multi-Agent Collaboration**: Features a centralized "Director" agent routing inputs to specialized step agents:
   * **Specifier**: Drafts system requirements and structures components modularly.
   * **Researcher**: Explores implementation patterns and tech stacks.
   * **Optionizer**: Generates architectural choices as interactive Decision Cards.
   * **Gap Detector**: Scans specifications for omissions or contradictions.
3. **Controlled Setup Wizard**: A glassmorphic onboarding screen where you define your project name, rough idea, automation level, and Golden Rules.
4. **Interactive Decision Cards**: Resolve architectural choices proposed by the Optionizer. Your selections are logged into the decision criteria file.
5. **Split-Screen Workspace Layout**:
   * **Left Panel**: Setup wizard, pending Decision Cards, and warning alerts.
   * **Right Panel**: Real-time live compiled specification viewer (editable during Planning Phase), DevLoop Console logs, and Decision Timeline logs.
6. **Real-time SSE Token Streaming**: Experience smooth token streaming typing effects on node conversation chats.
7. **Developer Loop Console**: Run shell commands (build, verify, launch, UI check) directly from the Web UI, streaming outputs in real-time.
8. **Decision Log Timeline**: Traces chronological decision adoption paths from `.lao/criteria.md`.
9. **Compiled Spec Viewer**: View compiled specifications live or edit them inline.

---

## Project Structure

```
LAO/
├── cli/                 # Express backend server & CLI AI runner
│   ├── src/
│   │   ├── agents/      # Orchestrator & agent prompt templates
│   │   ├── compiler.ts  # Spec compiler to Markdown
│   │   ├── gemini.ts    # Spawn shell CLI client runner
│   │   ├── index.ts     # Express endpoints & SSE stream routes
│   │   └── storage.ts   # Persistent settings/spec storage under .lao/
│   └── package.json
└── web/                 # React Web UI (Vanilla CSS layout)
    ├── src/
    │   ├── App.tsx      # Main application dashboard
    │   └── types.ts     # Shared TS types
    └── package.json
```

---

## Quick Start & Installation

### Prerequisites
* **Node.js** v18.0.0 or higher
* **npm** v9.0.0 or higher
* Local AI CLI clients installed and authenticated:
  * **Gemini CLI**: `gemini`
  * **Claude CLI**: `claude` (Claude Engineer)
  * **Codex CLI**: `codex`

### Setup & Launch

You can set up, install, and compile the entire workspace (both the CLI backend and Web UI) with a single command from the project root.

#### Option A: Using npm
```bash
# Install dependencies and build the workspace automatically
npm install

# Start the application
npm start
```

#### Option B: Using Yarn
```bash
# Install dependencies and build the workspace automatically
yarn install

# Start the application
yarn start
```

* The backend will launch at `http://localhost:4000`.
* On macOS, it will automatically open the Web UI in your default browser.

---

## Environmental Configurations

You can configure default providers using a `.env` file in the `cli` folder:
```env
LAO_PROVIDER=gemini       # Selected tool (gemini | claude | codex | agy)
LAO_MODEL=                # Override model if required
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

