# LAO Operating Principles v0.9

Date: 2026-05-27

## 1. Purpose

LAO (Local AI Office) is **a workspace that converts raw ideas into structured, AI-execution-friendly design documents.**

It orchestrates specialized local CLI-based AI agents to draft modular specifications, surface architectural choices as interactive cards, and compile them into a unified specification (`spec_compiled.md`) ready for development.

```
Rough Idea → Auto-Sprout Specs → Resolve Decision Cards → Lock Spec → Code & Verify
```

Role separation:
* **LAO** = Design converter — organizes *what to build* and enforces tech stack guardrails.
* **Development AI** (e.g. Claude Code, Codex) = Implementer — reads the locked `spec_compiled.md` and generates code.

---

## 2. Core Philosophy

### 2.1 Document-Driven Workspace
To minimize cognitive fatigue, LAO avoids manual visual mindmap manipulation. The workflow centers around a split-screen layout displaying modular documents (specifications) and high-level architectural decision points.

### 2.2 Golden Rules (Technology Guardrails)
To prevent the AI from recommending inappropriate architectures, the workspace enforces strict technology guardrails (`goldenRules` in `lao.config.json`). All agent prompts inject these rules, ensuring that the sprouted specs conform (e.g., using SQLite instead of Docker or PostgreSQL).

### 2.3 Phase Lock Protocol
To prevent specification drift during development:
* **Planning Phase**: Specifications can be generated, updated, or edited. Decision cards are resolved.
* **Development Phase**: The compiled specification is locked in a read-only state. Development CLI tasks (build, launch, verify) are executed via the DevLoop console.

---

## 3. Directory & File-System Structure

All workspace information is stored locally under the `.lao/` folder in the project root:

```text
.lao/
├── lao.config.json           # Project tech guardrails, phase, and provider configurations
├── criteria.md               # Chronological log of approved choices and reasoning
├── spec_compiled.md          # Final combined core and active feature specifications
├── messages.json             # Chat history with the agent team
├── specs/
│   ├── core_spec.md          # Core architecture spec
│   └── features/
│       └── [feature_id].md   # Individual feature specs (YAML frontmatter + markdown)
└── decisions/
    └── [card_id].json        # Pending or decided Decision Cards proposed by Optionizer
```

---

## 4. Multi-Agent Roles

LAO uses specialized agent personas to collaborate on the specification:

1. **Director**: The coordinator. Routes incoming user messages, schedules step tasks, and manages overall project phase state.
2. **Specifier**: Drafts requirements. Sprouts the initial `core_spec.md` and feature markdown specs under `.lao/specs/features/`.
3. **Optionizer**: Identifies trade-offs. Scans the sprouted specs to generate `DecisionCard` options (e.g. choice of authentication method).
4. **Gap Detector**: Detects omissions. Audits specifications for inconsistencies or logical gaps, surfacing warnings to the user.

---

## 5. Development Loop Integration

The workspace includes a **DevLoop Console** where the developer can run commands (build, launch, verify) defined in `lao.config.json` directly from the Web UI. Outputs from stdout/stderr are streamed to the interface in real-time, allowing immediate verification of code against the locked specification.
