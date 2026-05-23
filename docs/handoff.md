English | [한국어](handoff.ko.md)

# LAO Handoff Mechanism

Date: 2026-05-23

This document describes how design specifications generated in LAO are handed off to development AI agents (such as Claude Code or Codex). 

---

## 1. Overview

In LAO 0.9, the legacy Swift-based MCP server (`LAOMCPServer`) and native macOS `.command` file launchers have been retired. They are replaced by a **highly portable, simplified Markdown-based compilation model**.

The handoff workflow operates as follows:
1. **Compilation** — The user's visual mindmap decisions are compiled by the backend Express server into a unified Markdown specification document (`spec_compiled.md`) in the `{project_root}/.lao/` folder.
2. **Review & Extraction** — The Web UI provides a dedicated **Spec** tab containing:
   * **Monospace Log Viewer**: Real-time rendering of the compiled specification.
   * **Copy**: Copy the complete specification to your clipboard.
   * **Download**: Save `spec_compiled.md` locally to your machine.
3. **AI Intake** — Developers feed the compiled `spec_compiled.md` file or its copied contents directly into their preferred CLI coding agents (Claude Code, Codex, etc.) as prompt context.

---

## 2. Specification Compilation

* **Output Location**: `{project_root}/.lao/spec_compiled.md`
* **Trigger Endpoint**: `POST /api/compile` (triggered automatically when entering the **Spec** tab in the Web UI).

The compilation engine gathers all mainline decided nodes (filtering out candidate/archived alternatives) and constructs a structured Markdown document containing:
* Core project goals & idea details.
* Detailed system requirements, screens, data models, and API specifications.
* Decision rationale logs for each node adoption.

---

## 3. Feeding to CLI AI Agents (Handoff Flow)

Once the specification is compiled and saved or copied, it can be passed directly to local CLI-based AI tools:

### Option A: Direct File Reference (Recommended)
Launch your CLI agent in your project root, pointing it directly at the compiled spec file:

* **Claude Code**:
  ```bash
  claude -p "Read .lao/spec_compiled.md and implement the requirements."
  ```
* **Codex CLI**:
  ```bash
  codex exec "Implement the features specified in .lao/spec_compiled.md"
  ```

### Option B: Monospace Copy
1. Navigate to the **Spec** tab in the LAO Web UI.
2. Click **Copy** to copy the full compiled spec to the clipboard.
3. Paste the contents directly into your AI chat session or prompt file to instruct the agent.

---

## 4. Rationale for Simplification

The transition from a custom Swift MCP Server to a clean Markdown-based handoff was driven by three goals:
1. **Zero Setup Overhead**: Removing the need for Xcode, Swift package compilation, or `.mcp.json` registration allows the system to run on Windows, Linux, or macOS with zero installation friction.
2. **Maximum AI Compatibility**: Modern AI agents ingest Markdown documents natively and efficiently without requiring custom stdio tool APIs.
3. **No Sandbox Restrictions**: Reading a single file from the local workspace avoids sandboxing and permission limitations on end-user machines.
