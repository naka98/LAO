import Foundation
import LAODomain

// `GraphNode` / `GraphEdge` are explicitly module-qualified for the same name-collision reason
// the rest of the v0.8 node graph code uses LAODomain. prefixes (v0.7 WorkGraphView.swift
// defines internal types with the same identifiers).

/// Top-level shape written out when the user exports a v0.8 node graph workflow (Step 5d-1).
///
/// The export is a **raw snapshot** — every persisted node, edge, and message is included
/// verbatim with no projection or rewriting. Consumers (MCP server, future AI executor,
/// auditors) are expected to walk the structure themselves to assemble whatever shape they
/// need: mainline-only deliverables, reasoning trail for explainability, archived branches
/// for what-if analysis, etc.
///
/// Why raw and not pre-curated?
/// - The mindmap is the source of truth for v0.8; converting to a v0.7 `DesignDocument`
///   shape pre-commits us to a particular interpretation of "what survived the discussion".
/// - The schema can grow over time: bumping `schemaVersion` and adding fields stays backwards
///   compatible without forcing every consumer to upgrade in lock-step.
/// - LAO's mission ("행간 없는 정형 출력") is satisfied by the JSON being complete and
///   structured — it doesn't have to look like a spec doc to be useful to AI executors.
struct NodeGraphExport: Codable, Sendable {
    /// Bumped any time the export shape changes in a way consumers must notice.
    let schemaVersion: Int
    /// Wall-clock timestamp when the export file was produced.
    let exportedAt: Date
    let ideaId: UUID
    let ideaTitle: String
    let workflow: NodeGraphWorkflow
    let nodes: [LAODomain.GraphNode]
    let edges: [LAODomain.GraphEdge]
    let messages: [NodeMessage]
}

/// JSON encoder configured for human-readable, diffable graph exports — ISO8601 dates,
/// pretty-printed output with sorted keys.
enum NodeGraphExportEncoder {
    static func make() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
