English | [한국어](handoff.ko.md)

# LAO Handoff Mechanism

Date: 2026-04-28

This document describes how a completed LAO design is handed off to a development AI (Claude Code, Codex). For the *principles* of handoff, see [Design Principles §3.4](design-principles.md). This document covers the *implementation*.

---

## 1. Overview

When a design workflow reaches the `completed` phase, LAO performs three actions in order:

1. **Export** — write a fixed set of design artifacts to the project's `.lao/{ideaId}/{requestId}/` directory (atomic move from a temp dir).
2. **Register MCP server** — write `.mcp.json` to the project root so any MCP-aware AI tool can auto-discover the LAO MCP server.
3. **Open in tool** (user-triggered) — when the user clicks "Open in Claude Code" or "Open in Codex", LAO writes a `.command` script to a temp directory, opens it via Finder, and macOS launches Terminal with the chosen CLI plus an initial prompt that points at `DESIGN_SPEC.md`.

The first two run automatically as part of `finish`. The third is explicit per-tool.

---

## 2. Export Artifacts

Location: `{project_root}/.lao/{ideaId}/{requestId}/`

The directory is replaced atomically — files are written to `.tmp-{uuid}/` first, then `moveItem` swaps it into place. If any write fails, the final directory keeps the previous export.

| File | Format | Role |
|---|---|---|
| `spec.json` | JSON | Approved deliverable items only (canonical filter) |
| `spec.md` | Markdown | Approved spec, structured per section type (screen / data-model / api-spec / user-flow) |
| `context.md` | Markdown | Planner judgment context — why approved, what was rejected |
| `design.json` | JSON | Structured `DesignDocument` — the canonical machine-readable design |
| `DESIGN_SPEC.md` | Markdown | Unified design spec optimized for AI consumption (this is what `Open in …` tells the AI to read first) |
| `brd.json` | JSON | Business Requirements Document. **Conditional** — skipped when no BRD source is available (see §2.1) |
| `BRD.md` | Markdown | Human-readable BRD. Same condition as `brd.json` |
| `plan.json` | JSON | Implementation plan derived from `design.json` |
| `PLAN.md` | Markdown | Human-readable implementation plan with phases and standards |
| `test.json` | JSON | Test scenarios derived from `design.json` |
| `TEST.md` | Markdown | Human-readable test scenarios grouped by priority |

`design.json` is validated against `DesignDocumentValidator`. Errors are surfaced in the Completed phase UI but **do not block** export — the file is still written, and the user sees an inline disclosure with the issue list.

### 2.1 Conditional BRD Skip

`brd.json` and `BRD.md` are skipped when:

- the cached BRD JSON is empty, **and**
- the cached design Brief JSON is empty or fails to decode as a `BriefBrdEnvelope`.

In other words, BRD is written only when the workflow actually produced a BRD (directly or extractable from the Brief). Other artifacts are always written.

---

## 3. `.mcp.json` Registration

Location: `{project_root}/.mcp.json` (project root, not under `.lao/`).

LAO **merges** into an existing `.mcp.json`. If the file exists, its `mcpServers` map is preserved and only the `lao-design` key is updated.

### 3.1 Two Server Entry Forms

The form depends on whether a built `LAOMCPServer` binary is found:

**(a) Binary found — preferred:**

```json
{
  "mcpServers": {
    "lao-design": {
      "type": "stdio",
      "command": "/path/to/LAOMCPServer",
      "args": ["--project-root", "/path/to/project"]
    }
  }
}
```

**(b) Binary not found — `swift run` fallback:**

```json
{
  "mcpServers": {
    "lao-design": {
      "type": "stdio",
      "command": "swift",
      "args": ["run", "--package-path", "/path/to/lao/package", "LAOMCPServer", "--project-root", "/path/to/project"]
    }
  }
}
```

The fallback works only when the host has the LAO source tree available locally with a resolvable `Package.swift`. On end-user machines without the source, ensure the binary is co-located with the app bundle so form (a) is selected.

### 3.2 Binary Lookup Order

`findMCPServerBinary()` resolves the path in this order:

1. **App bundle directory** — same directory as `Bundle.main.executableURL`, file name `LAOMCPServer`. This is the distribution and Xcode-build path.
2. **SPM build directory** — `{packageRoot}/.build/{*-apple-macosx*}/{debug|release}/LAOMCPServer`. Used during local development when the app is launched from inside the package tree.
3. If neither resolves, form (b) is written to `.mcp.json`.

---

## 4. `Open in …` Flow

Trigger: in the Completed phase, the buttons appear when `hasExportedDeliverables && hasSubstantiveExport` is true. Two tools are supported:

| Button | CLI command | Initial prompt |
|---|---|---|
| Open in Claude Code | `claude` | `Read .lao/{ideaId}/{requestId}/DESIGN_SPEC.md and implement the project according to the design specification.` |
| Open in Codex | `codex` | (same) |

Mechanism:

1. LAO writes `lao-handoff-{claude\|codex}.command` to the system temp directory.
2. The script `cd`s into the project root and runs the CLI with the initial prompt.
3. LAO opens the script via `NSWorkspace`, which delegates to Terminal.app per macOS default.
4. The CLI launches with the prompt already typed; the AI reads `DESIGN_SPEC.md` and may then call MCP tools/resources via the `lao-design` server registered in `.mcp.json`.

If the CLI is not on `PATH`, the Terminal session reports `command not found`. LAO surfaces a generic launch failure message via `handoffLaunchFailed`.

---

## 5. MCP Server Surface

Once registered, the `lao-design` server (built from `Packages/LAOMCPServer`) exposes design artifacts through standard MCP `resources` and `tools`. The server resolves the most recent `design.json` under `.lao/` and loads adjacent BRD / plan / test JSON if present.

### 5.1 Resources

Static:

| URI | Description |
|---|---|
| `lao://schema` | JSON Schema (Draft 2020-12) for `design.json` |
| `lao://design` | Full `design.json` |
| `lao://design/markdown` | `DESIGN_SPEC.md` rendering |
| `lao://tech-stack` | Project tech stack section of the design |
| `lao://brd` | `brd.json` |
| `lao://brd/markdown` | `BRD.md` rendering |
| `lao://plan` | `plan.json` |
| `lao://plan/markdown` | Implementation plan (Markdown) |
| `lao://test` | `test.json` |
| `lao://test/markdown` | Test scenarios (Markdown) |
| `lao://documents` | Full document set (BRD + design + plan + test) in one response |

Dynamic — one resource per item present in the loaded design:

| URI pattern | Description |
|---|---|
| `lao://screens/{id}` | Per-screen spec |
| `lao://models/{id}` | Per-data-model spec |
| `lao://apis/{id}` | Per-API spec |
| `lao://flows/{id}` | Per-user-flow spec |

When `brd.json` was skipped at export time, BRD-related resources return empty payloads from the `documents` aggregate; the URIs are still listed.

### 5.2 Tools

| Tool | Required input | Purpose |
|---|---|---|
| `get_implementation_plan` | — | Recommended build order: groups of spec IDs that can be built in parallel |
| `get_related_specs` | `spec_id` | All cross-referenced specs across screens / models / APIs / flows |
| `search_specs` | `query` | Keyword search across all specs |
| `get_implementation_context` | `spec_id` | Spec + related specs + tech stack + implementation notes for one item |
| `get_project_context` | — | BRD problem definition, tech stack, MVP scope |
| `get_test_scenarios` | `spec_id` (optional) | Test cases, optionally filtered by spec |
| `get_milestone_plan` | — | Milestones, phases, MVP scope, project standards, infrastructure notes |
| `reload_documents` | — | Re-read all design documents from disk after a fresh export |
| `reload_design` | — | Alias for `reload_documents` |

`reload_design` is preserved as an alias for older clients; new integrations should call `reload_documents`.

---

## 6. Prerequisites

For the `Open in …` flow:

- `claude` CLI on `PATH` — [Claude Code](https://docs.claude.com/en/docs/claude-code)
- `codex` CLI on `PATH` — [OpenAI Codex CLI](https://github.com/openai/codex)

For the `lao-design` MCP server to start automatically:

- A built `LAOMCPServer` co-located with the app bundle (preferred), **or**
- The LAO source tree with `swift` available on `PATH` (fallback).

End-user distribution should bundle `LAOMCPServer` so the fallback is never hit.

---

## 7. Troubleshooting

| Symptom | Likely cause |
|---|---|
| `brd.json` / `BRD.md` missing | The workflow did not produce a BRD — see §2.1. Other artifacts should still be present. |
| `Open in …` opens Terminal but the CLI immediately reports `command not found` | The chosen CLI is not on `PATH` in the user's login shell. |
| Development AI does not see the `lao-design` MCP server | `.mcp.json` was not refreshed in the project root, or the AI tool was launched from a different working directory. Re-run finish, or check `{project_root}/.mcp.json` for a `lao-design` entry. |
| MCP server resources are stale after a re-export | Call the `reload_documents` tool (or restart the AI session). |
| `.mcp.json` falls back to `swift run` on an end-user machine | `LAOMCPServer` binary is not next to the app executable. Bundle it with the app to switch to the binary form. |
