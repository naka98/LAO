# LAO (Leeway AI Office)

LAO turns rough product ideas into locked, AI-ready specifications before coding agents start implementation.

---

## Why LAO?

Coding agents are powerful, but vague chats often become drifting implementations.  
LAO adds a planning layer between idea and code.

```
Idea ➔ Spec Sprout ➔ Decision Cards ➔ Spec Lock ➔ DevLoop
```

---

## Who is it for?

- **Developers** using Claude Code, Codex, Gemini CLI, Cursor, or other local AI agents (fully configurable).
- **Solo builders** who want structured planning before implementation.
- **Teams** that want reusable project specs instead of scattered AI chats.

---

## Core Concepts

- **Local CLI AI Engine**: Harnesses local CLIs for ultra-fast runs with minimal orchestration overhead.
- **Director + Specialized Agents**: Specialized step agents led by a routing Director.
- **Golden Rules**: Programmatic constraints enforced on specifications.
- **Decision Cards**: Micro-decisions agreed on before locking requirements.
- **Compiled Spec**: The single source of truth for the project.
- **Handover Gate**: The read-only lock reducing spec-code drift.
- **DevLoop Console**: Local execution, building, and verification loop.

---

## Quick Start for Existing CLI Users

### Prerequisites
- Node.js v18.0.0 or higher
- Configurable local AI CLI clients (`gemini`, `claude`, `codex`, `cursor` etc.) authenticated

### 1. Install globally
You can install LAO directly from GitHub:

```bash
# Using yarn
yarn global add git+https://github.com/naka98/LAO.git

# OR Using npm
npm install -g git+https://github.com/naka98/LAO.git
```

### 2. Run the office
Navigate to your project root folder and launch LAO:

```bash
lao
```
LAO will start on port `4000` and automatically open the guided planning workspace in your browser (`http://localhost:4000`).

---

## Learn More

- 📄 [Why LAO?](./docs/why-lao.md)
- 📐 [Architecture Rationale](./docs/v0.9_architecture.md)
- ⚙️ [Operating Principles](./docs/operating-principles.md)

<details>
<summary>🛠️ Local Development (Contributing)</summary>

If you want to clone the repository and run it locally for development:

```bash
# Clone the repository
git clone https://github.com/naka98/LAO.git
cd LAO

# Install dependencies & start
npm install # or yarn install
npm start   # or yarn start
```
</details>

<details>
<summary>⚙️ Deep Dive & Technical Highlights (v0.9.3)</summary>

### 1. Local CLI AI Engine & E2BIG Bypass
- Executes local CLI tools (`gemini`, `claude`, etc.) via non-login shells (`-c`) to minimize startup latency down to 10ms.
- Uses file redirection (`<`) instead of command substitution to bypass UNIX `ARG_MAX` limits (`E2BIG`), allowing massive specification prompts.

### 2. Concurrency Control (Spawn Queue)
- Limits active AI tasks to `maxConcurrency = 2` to prevent CPU freeze and SQLite database locks (`SQLITE_BUSY`).
- Evicts redundant requests and kills orphans automatically after 90 seconds.

### 3. Planning Harness & Self-Correction
- Automated Linter checks specifications for formatting constraints (e.g., Given-When-Then criteria).
- Performs up to 3 self-correction loops using AI feedback injection.
- Integrates with a local `RULES.md` in the project root to enforce tech-stack boundaries.

### 4. Human-In-The-Loop (HITL) Interventions
- Renders detailed warnings on the UI if self-correction fails 3 times.
- Features a **[Force Commit]** bypass option to let developers manually override errors.

### 5. Multi-Agent & Context Budgeting
- Centralized Director routes work to step agents.
- Slices context to send only relevant parts of specifications to keep prompt tokens within the budget.

### 6. DevLoop Console & SSE Streaming
- Runs `build`, `launch`, and `verify` commands in the console.
- Streams live progress diagnostics directly to the browser UI via Server-Sent Events (SSE) to prevent user wait fatigue.

</details>
