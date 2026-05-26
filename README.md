# LAO (Local AI Office)

LAO is a platform-independent, developer-first AI design workflow application built with **Node.js (Express)** and **React (Vite + React Flow)**. It transforms raw ideas into AI-ready, structured specifications by running local command-line interface (CLI) AI clients on your machine.

---

## Architecture Transition Rationale (macOS Native -> CLI + WebUI)

LAO was originally designed as a macOS-native SwiftUI application. In v0.9, we successfully migrated to a **Node.js Express CLI + React Flow Web UI** architecture to resolve key technical and operational challenges:
1. **Cross-Platform Portability**: Moving away from macOS-specific system frameworks ensures developers on Windows, Linux, and macOS can run and benefit from the local AI office workspace seamlessly.
2. **Robust Local DevLoop Integration**: Spawning subprocesses and piping stdout/stderr streams to the browser is significantly more reliable and flexible under a Node.js runtime compared to macOS sandbox restrictions.
3. **Enhanced Visualization & UX**: Leveraging the React Flow ecosystem allowed us to create a highly responsive, custom-themed interactive canvas that handles dynamic branch sprouting, merging, and layout calculations efficiently.

---

## Key Features

1. **Local CLI AI Engine**: Executes queries using your locally configured CLI clients (`claude`, `gemini`, `codex`) via shell processes. All prompt contents are handled through secure temp files to circumvent terminal length constraints.
2. **Multi-Agent Collaboration**: Features a centralized "Director" agent routing inputs to specialized step agents:
   * **Specifier**: Drafts system requirements and structures components.
   * **Researcher**: Analyzes libraries, patterns, and system logic.
   * **Optionizer**: Generates architectural choices and alternative branches.
   * **Gap Detector**: Discovers missing edges, edge-cases, and logical holes.
3. **Interactive React Flow Mindmap**: Explore concepts visually. Candidate branches can be spawned, adopted into the mainline, or merged together.
4. **Onboarding Seed Wizard**: Zero-configuration start. Launch a new project and sprout candidate nodes instantly using the glassmorphic setup wizard.
5. **Multi-Provider UI Overrides**: Configure and swap providers/models (Claude, Gemini, Codex) globally or override options for specific agent roles on the fly.
6. **Real-time SSE Token Streaming**: Experience smooth token streaming typing effects on node conversation chats.
7. **Developer Loop Console**: Run shell commands (build, verify, launch, UI check) directly from the Web UI, streaming stdout/stderr outputs to a dark console view in real-time.
8. **Decision Log Timeline**: Parses `.lao/criteria.md` to trace decision adoption paths chronologically as visual cards.
9. **Compiled Spec Viewer**: View compiled specifications live, copy content to clipboard, or download `spec_compiled.md` files.

---

## Project Structure

```
LAO/
├── cli/                 # Express backend server & CLI AI runner
│   ├── src/
│   │   ├── agents/      # Orchestrator & agent prompt templates
│   │   ├── compiler.ts  # Mindmap compiler to Markdown
│   │   ├── gemini.ts    # Spawn shell CLI client runner
│   │   ├── index.ts     # Express endpoints & SSE stream routes
│   │   └── storage.ts   # Persistent settings/mindmap storage
│   └── package.json
└── web/                 # React Flow Web UI
    ├── src/
    │   ├── App.tsx      # Main application page
    │   └── components/  # React subcomponents (Onboarding, NodeDetail, Settings)
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

1. **Install dependencies**:
   ```bash
   # Install CLI backend dependencies
   cd cli
   npm install

   # Install Web UI dependencies
   cd ../web
   npm install
   ```

2. **Build projects**:
   ```bash
   # Compile Web UI static files
   cd ../web
   npm run build

   # Compile CLI backend
   cd ../cli
   npm run build
   ```

3. **Start the application**:
   ```bash
   cd ../cli
   npm start
   ```
   * The backend will launch at `http://localhost:4000`.
   * On macOS, it will automatically open the Web UI in your default browser.

---

## Environmental Configurations

You can configure default providers using a `.env` file in the `cli` folder:
```env
LAO_PROVIDER=gemini       # Selected tool (gemini | claude | codex)
LAO_MODEL=                # Override model if required
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
