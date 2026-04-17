English | [한국어](operating-principles.ko.md)

# LAO Operating Principles v0.3

Date: 2026-03-23

## 1. Purpose

LAO (Leeway AI Office) is **a layer that converts plans into AI-execution-friendly design documents.**

Director and Step agents generate draft plans and present them for review. The decision-maker (user) judges and gives feedback on-screen, and the design is elaborated based on that input before being delivered to Claude Code/Codex via MCP.

From an output perspective, the core pipeline is:

**Screen plan → Common reference document → Development design draft**

Role separation:
* **LAO** = Design converter — organizes *what to build* and *how to deliver it*
* **Development AI** (Claude Code, Codex) = Implementer — converts the organized design into actual code

To achieve this, LAO is fundamentally an interpretation engine + structuring engine + quality maintenance engine.

Abstract request
→ Intent interpretation
→ Structuring
→ Role-specific detailing
→ Output
→ Validation
→ Delivery to development AI via MCP

Structured information preserves meaning under compression. In LLM-based systems, context is inevitably compressed — due to token limits, phase transitions, summaries, etc. Unstructured natural language dialogue loses nuance and context in this process, but structured data with explicit fields and hierarchy preserves its core even after compression.

When intent is accurately structured, the following follow naturally:

* Less semantic loss across hand-offs — context is maintained without the conversation swelling.
* Each role understands the work at an executable level, raising the average quality of outputs.
* Because the structure is repeatable, an expert-level workflow emerges.

---

## 2. Core Philosophy

### 2.1 Structuring Principle

* Unstructured intent is the root cause of failure in large tasks.
* Structuring provides compression resistance — data with explicit fields and hierarchy preserves its core under compression.
* Natural language loses nuance when compressed, but structured information can be reconstructed close to its original intent.
* Every transformation in LAO (idea → direction convergence → output skeleton → detailed spec) is a structuring step.

### 2.2 Context Management

* Structured deliverables are compression-resistant, so we anchor work on structured spec documents rather than long conversation histories.
* Each stage receives only the information it needs; unnecessary past context is not accumulated.
* A sliding window keeps recent dialogue only; prior context is preserved as structured data (Work Graph, Deliverable Spec).

### 2.3 Two-Stage Operation — IdeaBoard + Director Workflow

* Idea exploration (IdeaBoard) is separated from execution structuring (Director Workflow).
* In IdeaBoard, an expert panel proposes diverse directions and converges via dialogue with the user.
* On convergence, a Work Graph (entity + relationship) is extracted and passed to the Director Workflow as structured data.
* The Director Workflow generates detailed specs based on DeliverableSection / DeliverableItem.

### 2.4 Director-Centered Structuring

* The Director converts the user's unstructured intent into structured work information.
  * Ambiguous request → explicit goal and success criteria
  * Large chunk → hierarchical decomposition (DeliverableSection → DeliverableItem)
  * Natural language intent → actionable instructions per role
* The Director is responsible for interpretation, decomposition, delivery, and evaluation.
* The Director is a quality owner, but not the decider of final product direction.
* Final direction and key choices follow user approval.

### 2.5 Output Standards

* Outputs must be immediately usable in the next stage — not rough drafts.
* Every output must have clarity, consistency, executability, and verifiability.
* The goal is not a one-off artifact but a repeatable output system with a high average quality.

---

## 3. Operating Structure

LAO's base structure follows this hierarchy:

* Project
  * Board (request board)
    * Idea (IdeaBoard — idea exploration, main hub)
      * Expert Panel → Synthesis → Work Graph extraction
      * IdeaStatus lifecycle: `draft → exploring → explored → designing → designed / designFailed`
    * DesignSession (Director Workflow — execution structuring)
      * DirectorWorkflow
        * DeliverableSection
          * DeliverableItem
        * ItemEdge (Work Graph)

### 3.1 Project

A unit representing one product, feature group, or major objective.
Multiple ideas and workflow requests can be created within a project.
A project can optionally bind a local folder (rootPath) to provide file-exploration context.

### 3.2 Idea (IdeaBoard)

The stage where an expert panel explores the user's natural-language idea.

* When the user submits an idea, the Director AI composes a 3–5 member expert panel.
* Each expert proposes a different product direction (B2B vs B2C, MVP vs full-scale, etc.).
* The user has follow-up conversations with the panel as a whole or with individual experts.
* On Synthesis, the Director consolidates the final direction and extracts a Work Graph (entities + relationships).
* The synthesis result is converted into a DesignSession and passed to the design workflow.

### 3.3 DesignSession

> **Rename completed:** Both code level (`WorkflowRequest` → `DesignSession`, `WorkflowEvent` → `DesignEvent`) and DB table names (`workflow_requests` → `design_sessions`, `workflow_events` → `design_events`) have been renamed (schema v9).

A single work-request unit from the user. Created within a project, it contains:

* Task description (taskDescription)
* Director's initial analysis summary (triageSummary)
* Workflow state (workflowStateJSON) — the whole DirectorWorkflow serialized
* Pre-extracted graph passed from IdeaBoard (roadmapJSON)
* Usage tracking (apiCallCount, totalInputChars, totalOutputChars)

### 3.4 DirectorWorkflow

The runtime container for the workflow. It goes through these phases:

| Phase | Description |
|-------|-------------|
| `input` | Initial state — user is entering the task instruction |
| `analyzing` | Director runs automatic analysis + Deliverable skeleton + approach generation |
| `approachSelection` | 2–3 approach options are compared — user picks one |
| `planning` | Planner judgments + orchestration conversation + Item elaboration |
| `completed` | All items are complete |
| `failed` | Unrecoverable failure |

### 3.5 DeliverableSection

Groups of outputs by type. Available Section types:

* `screen-spec` — screen design
* `data-model` — data model
* `api-spec` — API design
* `user-flow` — user flow
* Others, dynamically determined by project type

Each Section contains multiple DeliverableItems.

### 3.6 DeliverableItem

The smallest unit where an actual spec is written.

Each Item contains:

* Title (title)
* Brief description (briefDescription)
* Detailed spec (spec) — type-specific JSON dictionary
* Status: pending → inProgress → completed, or needsRevision
* Parallel group (parallelGroup) — dependency order (1 = independent, 2+ = depends on earlier group)
* Assigned agent (lastAgentId, lastAgentLabel)
* Version tracking (version)
* Token usage (inputTokens, outputTokens, elaborationDurationMs)

### 3.7 ItemEdge (Work Graph)

A directed graph representing relationships between DeliverableItems.

Relation types:

* `depends_on` — A can only start after B completes
* `navigates_to` — screen A navigates to screen B
* `uses` — A calls/references B
* `refines` — A improves/extends B
* `replaces` — A replaces B
* `calls` — A calls B (additionally permitted in cross-references at the final DesignDocument stage)

Work Graphs are produced via two paths:
1. **IdeaBoard Synthesis** — entities/relationships are extracted from natural-language discussion during convergence → passed to the Director as `roadmapJSON`.
2. **Director Workflow** — generated together with the Deliverable structure during analysis, then extended via the `link_items` action during orchestration conversation.

---

## 4. Role Definitions

## 4.1 User

* Sets the goal and direction.
* Explores direction through dialogue with experts in IdeaBoard.
* Coordinates outputs through orchestration conversation in the Director Workflow.
* Decides final direction, priorities, and major changes.

## 4.2 Director

* Interprets the user's intent.
* Composes the expert panel in IdeaBoard, and consolidates the direction upon synthesis.
* Designs the Deliverable skeleton in the Director Workflow.
* Coordinates outputs with the user via orchestration conversation.
* Instructs Step Agents on Item elaboration.
* Manages the Work Graph (adding entities, linking relationships).

The Director must not:

* Change product direction unilaterally without user approval.
* Mark things complete without verification.
* Force ahead on ambiguous requests based on unilateral interpretation.

## 4.3 Step Agent

* Writes the spec for its assigned DeliverableItem.
* Generates a structured spec appropriate to the Item type (screen → components / interactions / states, data → fields / relationships / constraints, API → methods / paths / requests / responses, flow → triggers / steps / branches).
* References Work Graph relationships to maintain consistency with related Items.
* Explicitly states assumptions, risks, and unresolved issues.

---

## 5. Documents and Context System

### 5.1 Request Context

The user's original intent, goals, constraints, and expected outcomes.

Stored across the following fields in the workflow:

* taskDescription — original user request (with IdeaBoard conversation summary on conversion)
* triageSummary — Director's initial analysis summary
* roadmapJSON — pre-extracted Work Graph from IdeaBoard

### 5.2 Deliverable Spec

Stored in each DeliverableItem's `spec` field as type-specific JSON.

Core fields by type:
* **screen-spec**: component list, interactions, state model, layout
* **data-model**: field definitions, relationships, constraints, indexes
* **api-spec**: HTTP method, path, request/response schema, error codes
* **user-flow**: triggers, steps, branches, success/failure paths

### 5.3 Work Graph

Relationships between DeliverableItems are managed as an array of `ItemEdge`.
Relationship information is injected into Item elaboration prompts so that related Items' specs are referenced and consistency is maintained.

### 5.4 Orchestration Conversation (Chat History)

The dialogue record between Director and user. Stored in `DirectorWorkflow.chatHistory`.
Only the most recent 20 messages are included in prompts to prevent context bloat.

### 5.5 IdeaBoard Conversation Context

* **Whole-panel follow-up**: most recent Director summary + last 4 messages (sliding window)
* **Individual expert-card conversation**: last 8 messages (sliding window)

---

## 6. Quality Management Process

### 6.1 Idea Refinement

* Work begins from an idea.
* In IdeaBoard, the expert panel proposes diverse directions.
* The user refines direction via follow-up questions and individual expert conversations.
* Synthesis extracts the final direction and a Work Graph.

### 6.2 Automatic Analysis

* On entering the Director Workflow, the Director automatically generates a Deliverable skeleton and 2–3 approach options.
* If a pre-extracted Work Graph exists from IdeaBoard, it is used as the analysis starting point.
* Project type, section structure, item list, and relationships are derived in a single LLM call.

### 6.3 Approach Selection

* During the analysis phase, the Director generates 2–3 approach options (ApproachOption).
* Each approach includes a label, summary, pros/cons, project spec, and Deliverable skeleton.
* Once the user picks one, Planning begins with that approach's Deliverable structure.

### 6.4 Orchestration Coordination

* The user coordinates Deliverables via chat with the Director.
* The Director proposes actions such as:
  * `elaborate_item` — instruct a Step Agent to write an Item spec
  * `update_item` / `add_item` / `remove_item` — manage Items
  * `add_section` — add a Section
  * `link_items` — add a Work Graph relationship
  * `mark_complete` — signal workflow completion

### 6.5 Item Elaboration

* A Step Agent writes the detailed spec for its assigned Item.
* Sibling Items within the same Section and completed Items from other Sections are provided as context.
* Work Graph relationships are referenced to maintain consistency with related Items.
* A structured JSON spec is generated following per-type guidelines.

### 6.6 Agent Assignment

* The Director automatically assigns the most suitable Step Agent to each Item.
* Agent specialty (systemPrompt) is matched to Item type.
* UI Items → frontend-specialist Agent, data Items → backend-specialist Agent.

### 6.7 Consistency Check

* `buildConsistencyCheckPrompt` validates overall Deliverable consistency.
* Checks for missing Items, broken references, incomplete Items, and inconsistencies.

---

## 7. Automation and Approval Boundaries

### 7.1 Automatic Execution (no user intervention)

* Automatic analysis (Deliverable skeleton generation)
* Automatic Agent assignment
* Item Elaboration (parallel execution)
* Automatic Work Graph relationship detection
* Usage tracking

### 7.2 Director Autonomous Decisions

Actions the Director performs autonomously in response to user messages during orchestration:

* Item add / update / delete
* Section add
* Relationship linking
* Elaboration instruction

### 7.3 User Approval (explicit confirmation required)

* Product direction changes
* Workflow completion (mark_complete)
* Large-scale structural changes

Principle:

* Automation is for speed,
* Autonomous decisions are for flow continuity,
* Approval is for directional accuracy.

---

## 8. Operating Principles Summary

* LAO is a layer that converts plans into AI-execution-friendly design documents.
* Core pipeline: screen plan → common reference document → development design draft.
* LAO (design converter) and development AI (implementer) have separated roles.
* Accurately structuring the user's intent is the starting point of all operations.
* Structured information preserves meaning under compression.
* Natural-language exploration in IdeaBoard → Work Graph extraction → detailed spec generation in Director Workflow.
* Context is maintained via structured Deliverable Spec and Work Graph, not raw dialogue.
* Large work is decomposed into DeliverableSection → DeliverableItem.
* The Director is both the structurer of user intent and the quality owner.
* Outputs must be directly usable in the next stage.
* Completed designs are delivered to Claude Code/Codex via MCP.
* Automate what can be automated, but control direction via approval.

---

## 9. Items to Review for the Next Version

* Work-Graph-based Elaboration ordering optimization (topological sort)
* Automatic kickoff of downstream dependent Items when an Item completes (Completion Cascade)
* Stronger automatic consistency validation between Items
* Error propagation — automatic halt of downstream Items when one fails
* Reflect Work Graph relationships in Export/document generation
* Per-provider role allocation policy

---

This document converts LAO's philosophy statement into concrete operational rules. It will continue to be refined based on issues discovered in real-world use.
