import Foundation
import LAODomain
import SwiftUI

// MARK: - Workflow Phase

enum DesignPhase: String, Codable, Equatable {
    case input              // user input pending
    case analyzing          // auto analysis + skeleton generation
    case approachSelection  // approach comparison — user picks one of 2-3 options
    case generatingSkeleton // skeleton structure generation (Phase A)
    case generatingGraph    // relationship + uncertainty graph generation (Phase B)
    case planning           // planner judges items, requests elaboration, approves results
    case completed
    case failed

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "reviewing", "working": self = .planning   // legacy → planning
        default:
            guard let v = DesignPhase(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown DesignPhase: \(raw)")
            }
            self = v
        }
    }
}

// MARK: - Phase-Gate Validation

/// Result of a phase-gate check — determines whether a phase transition is allowed.
struct PhaseGateResult: Equatable {
    let canProceed: Bool
    let blockers: [String]    // must-meet conditions that are NOT met (blocks transition)
    let warnings: [String]    // should-meet conditions (non-blocking, informational)

    static let pass = PhaseGateResult(canProceed: true, blockers: [], warnings: [])
}

/// Phase-gate checker — validates readiness before phase transitions.
///
/// [Scope] Workflow-level gate. Evaluates a whole DesignWorkflow to decide if it may advance a phase.
/// [Trigger] `DesignWorkflowViewModel.requestStructureApproval` / `confirmStructureApproval`.
/// [Sibling]
///   - `SpecReadinessValidator` — item-level spec field completeness (not phase-level).
///   - `DesignDocumentValidator` — post-export structural check on the produced DesignDocument.
enum PhaseGateChecker {

    /// Gate for planning → completed (wraps existing completionBlockers).
    static func gateForCompletion(_ workflow: DesignWorkflow) -> PhaseGateResult {
        let blockers = workflow.completionBlockers
        return PhaseGateResult(
            canProceed: blockers.isEmpty,
            blockers: blockers,
            warnings: []
        )
    }

    /// Gate for REFINE → SPECIFY (Structure Approval).
    /// Validates the skeleton structure is ready for detailed elaboration.
    static func gateForStructureApproval(_ workflow: DesignWorkflow) -> PhaseGateResult {
        var blockers: [String] = []
        var warnings: [String] = []

        // Must have items to elaborate
        if workflow.activeItemCount == 0 {
            blockers.append("noActiveItems")
        }

        // Blocking uncertainties must be resolved
        let blockingUncertainties = workflow.uncertainties.filter {
            $0.isUncertainty && $0.priority == .blocking && $0.status == .pending
        }
        if !blockingUncertainties.isEmpty {
            blockers.append("unresolvedBlockingUncertainties")
        }

        // All items should be reviewed by planner (not unreviewed)
        if workflow.unreviewedItemCount > 0 {
            blockers.append("unreviewedItems")
        }

        // Warnings: important uncertainties
        let importantUnresolved = workflow.uncertainties.filter {
            $0.isUncertainty && $0.priority == .important && $0.status == .pending
        }
        if !importantUnresolved.isEmpty {
            warnings.append("unresolvedImportantUncertainties")
        }

        return PhaseGateResult(canProceed: blockers.isEmpty, blockers: blockers, warnings: warnings)
    }
}

// MARK: - Planner Verdict

/// Planner agent's phase-gate verdict on a DeliverableItem.
/// Controls whether the item proceeds to elaboration (approved), needs rework (rejected/unreviewed).
/// [Distinction] `DesignVerdict` is the *decision-maker's* directional judgment on item inclusion/exclusion
///               and is independent of spec technical readiness. PlannerVerdict is agent-internal only.
enum PlannerVerdict: String, Codable, Equatable {
    case unreviewed        // not yet reviewed by planner
    case approved          // planner accepts current state
    case rejected          // planner removes this item

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "needsElaboration", "deferred": self = .unreviewed  // legacy → unreviewed
        default:
            guard let v = PlannerVerdict(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown PlannerVerdict: \(raw)")
            }
            self = v
        }
    }
}

// MARK: - Design Verdict (decision-maker facing)

/// Decision-maker's directional judgment — independent of spec technical readiness.
/// Unlike PlannerVerdict (which includes .rejected for deletion), this enum captures
/// only the decision-maker's assessment of whether an item belongs in the project.
enum DesignVerdict: String, Codable, Equatable {
    case pending        // 검토 대기 — not yet reviewed by decision-maker
    case confirmed      // 확인됨 — "this item is needed"
    case needsRevision  // 수정 요청 — directional change requested
    case excluded       // 제외 — "이 항목은 불필요하다"
}

// MARK: - Uncertainty Escalation

/// Type of uncertainty the Design or Step agent has surfaced.
enum UncertaintyType: String, Codable, Equatable {
    case question        // 간단한 질문 → 텍스트 답변 기대
    case suggestion      // Design가 제안 → 승인/거절
    case discussion      // 복잡한 주제 → 채팅 대화 필요
    case informationGap  // 컨텍스트 부족 → 사용자가 정보 제공
}

/// Priority of an uncertainty escalation.
enum UncertaintyPriority: String, Codable, Equatable {
    case blocking   // 이 아이템 진행 불가
    case important  // 마무리 전 해결 필요, 다른 아이템은 진행 가능
    case advisory   // 참고 수준, 워크플로우 계속 진행
}

/// Universal meta-condition that triggered an uncertainty.
/// Layer 1 of the 2-tier uncertainty detection framework.
enum UncertaintyAxiom: String, Codable, Equatable, CaseIterable {
    case multipleInterpretations  // 해석이 2개 이상 가능
    case missingInput             // 결정에 필요한 입력값 부재
    case conflictsWithAgreement   // 기존 합의와 충돌
    case ungroundedAssumption     // 근거 없이 그럴듯하게 메우고 있음
    case notVerifiable            // 검증 가능한 상태가 아님
    case highImpactIfWrong        // 틀렸을 때 피해가 큼 (priority 증폭기)
}

// MARK: - Spec Readiness (agent-internal)

/// Technical readiness of a deliverable's spec — managed by the director agent,
/// not exposed directly to the decision-maker.
enum SpecReadiness: String, Codable, Equatable {
    case notValidated   // not yet elaborated
    case incomplete     // has error-level validation issues
    case ready          // no blocking issues
}

/// One-line summary of spec readiness for decision-maker display.
struct ReadinessSummary {
    let percentage: Int              // 0-100
    let blockingCount: Int
    let issueKeys: [(key: String, itemName: String)]  // up to 3, for view-layer localization
}

// MARK: - AnyCodable (type-erased JSON value)

/// Lightweight type-erased wrapper for arbitrary JSON values within deliverable specs.
struct AnyCodable: Codable, Equatable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported AnyCodable value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (is NSNull, is NSNull):
            return true
        case let (l as Bool, r as Bool):
            return l == r
        case let (l as Int, r as Int):
            return l == r
        case let (l as Double, r as Double):
            return l == r
        case let (l as Int, r as Double):
            return Double(l) == r
        case let (l as Double, r as Int):
            return l == Double(r)
        case let (l as String, r as String):
            return l == r
        case let (l as [Any], r as [Any]):
            guard l.count == r.count else { return false }
            return zip(l, r).allSatisfy { AnyCodable($0) == AnyCodable($1) }
        case let (l as [String: Any], r as [String: Any]):
            guard l.count == r.count else { return false }
            return l.allSatisfy { key, val in
                guard let rVal = r[key] else { return false }
                return AnyCodable(val) == AnyCodable(rVal)
            }
        default:
            return false
        }
    }

    // MARK: - Convenience

    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var boolValue: Bool? { value as? Bool }
    var arrayValue: [Any]? { value as? [Any] }
    var dictValue: [String: Any]? { value as? [String: Any] }

    /// Convert to pretty-printed JSON string for display.
    func toJSONString(prettyPrinted: Bool = true) -> String? {
        guard let data = try? JSONEncoder.anyCodablePretty.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Create from a raw JSON dictionary.
    static func from(jsonDict: [String: Any]) -> [String: AnyCodable] {
        jsonDict.mapValues { AnyCodable($0) }
    }
}

private extension JSONEncoder {
    static let anyCodablePretty: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

// MARK: - Project Spec

struct ProjectSpec: Codable, Equatable {
    var name: String
    var type: String            // "ios-app", "web-app", "api-server", etc.
    var techStack: [String: String]?  // e.g. ["language": "Swift", "framework": "SwiftUI", "platform": "macOS 15+"]
    var sourceIdeaId: String?
    var sourceDirection: String?

    init(name: String, type: String, techStack: [String: String]? = nil, sourceIdeaId: String? = nil, sourceDirection: String? = nil) {
        self.name = name
        self.type = type
        self.techStack = techStack
        self.sourceIdeaId = sourceIdeaId
        self.sourceDirection = sourceDirection
    }
}

// MARK: - Approach Option (7-step reasoning output)

/// One of 2-3 approaches generated by the Design during analysis.
/// The decision-maker compares these in a side-by-side panel and picks one.
struct ApproachOption: Identifiable, Codable, Equatable {
    let id: UUID
    let label: String                       // "접근 방식 A: 단일 화면 플로우"
    let summary: String                     // 2-3 sentence overview
    let pros: [String]
    let cons: [String]
    let risks: [String]
    let estimatedComplexity: String         // "low" | "medium" | "high"
    let isRecommended: Bool
    let reasoning: String                   // why this approach was proposed / recommended
    let deliverables: [DeliverableSection]
    let relationships: [ItemEdge]?
    let hiddenRequirements: [String]

    init(
        id: UUID = UUID(),
        label: String,
        summary: String,
        pros: [String] = [],
        cons: [String] = [],
        risks: [String] = [],
        estimatedComplexity: String = "medium",
        isRecommended: Bool = false,
        reasoning: String = "",
        deliverables: [DeliverableSection] = [],
        relationships: [ItemEdge]? = nil,
        hiddenRequirements: [String] = []
    ) {
        self.id = id
        self.label = label
        self.summary = summary
        self.pros = pros
        self.cons = cons
        self.risks = risks
        self.estimatedComplexity = estimatedComplexity
        self.isRecommended = isRecommended
        self.reasoning = reasoning
        self.deliverables = deliverables
        self.relationships = relationships
        self.hiddenRequirements = hiddenRequirements
    }
}

// MARK: - Deliverable Item Status

enum DeliverableItemStatus: String, Codable, Equatable {
    case pending         // skeleton only
    case inProgress      // step agent elaborating
    case completed       // done
    case needsRevision   // user requested changes
}

// MARK: - Deliverable Item

struct DeliverableItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var status: DeliverableItemStatus
    var version: Int
    var spec: [String: AnyCodable]  // flexible JSON structure per item type
    var briefDescription: String?
    var createdAt: Date
    var updatedAt: Date

    // Planner judgment (internal — drives rejection/export filtering)
    var plannerVerdict: PlannerVerdict = .unreviewed
    var plannerNotes: String?

    // Decision-maker layer
    var directorVerdict: DesignVerdict = .pending
    var specReadiness: SpecReadiness = .notValidated

    // Per-item cost/time/agent tracking
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var elaborationDurationMs: Int = 0
    var lastAgentId: UUID?
    var lastAgentLabel: String?
    var parallelGroup: Int?
    var scenarioGroup: String?

    /// Alias for `directorVerdict` — stored key is kept for JSON backward compatibility.
    var designVerdict: DesignVerdict {
        get { directorVerdict }
        set { directorVerdict = newValue }
    }

    // Convergence monitoring: counts confirmed↔needsRevision transitions
    var verdictFlipCount: Int = 0

    // Decision-maker's revision reason (set via popover)
    var revisionNote: String?

    // Last elaboration error (shown in inspector for retry UX)
    var lastElaborationError: String?

    // Streaming checkpoint (crash resilience)
    var partialOutput: String?
    var lastCheckpoint: Date?

    init(
        id: UUID = UUID(),
        name: String,
        status: DeliverableItemStatus = .pending,
        version: Int = 0,
        spec: [String: AnyCodable] = [:],
        briefDescription: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        plannerVerdict: PlannerVerdict = .unreviewed,
        plannerNotes: String? = nil,
        directorVerdict: DesignVerdict = .pending,
        specReadiness: SpecReadiness = .notValidated,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        elaborationDurationMs: Int = 0,
        lastAgentId: UUID? = nil,
        lastAgentLabel: String? = nil,
        parallelGroup: Int? = nil,
        scenarioGroup: String? = nil,
        verdictFlipCount: Int = 0,
        revisionNote: String? = nil,
        lastElaborationError: String? = nil,
        partialOutput: String? = nil,
        lastCheckpoint: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.version = version
        self.spec = spec
        self.briefDescription = briefDescription
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.plannerVerdict = plannerVerdict
        self.plannerNotes = plannerNotes
        self.directorVerdict = directorVerdict
        self.specReadiness = specReadiness
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.elaborationDurationMs = elaborationDurationMs
        self.lastAgentId = lastAgentId
        self.lastAgentLabel = lastAgentLabel
        self.parallelGroup = parallelGroup
        self.scenarioGroup = scenarioGroup
        self.verdictFlipCount = verdictFlipCount
        self.revisionNote = revisionNote
        self.lastElaborationError = lastElaborationError
        self.partialOutput = partialOutput
        self.lastCheckpoint = lastCheckpoint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        status = try container.decodeIfPresent(DeliverableItemStatus.self, forKey: .status) ?? .pending
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
        spec = try container.decodeIfPresent([String: AnyCodable].self, forKey: .spec) ?? [:]
        briefDescription = try container.decodeIfPresent(String.self, forKey: .briefDescription)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        plannerVerdict = try container.decodeIfPresent(PlannerVerdict.self, forKey: .plannerVerdict) ?? .unreviewed
        plannerNotes = try container.decodeIfPresent(String.self, forKey: .plannerNotes)
        // Migration: derive directorVerdict from legacy plannerVerdict if absent
        if let dv = try container.decodeIfPresent(DesignVerdict.self, forKey: .directorVerdict) {
            directorVerdict = dv
        } else {
            switch plannerVerdict {
            case .unreviewed: directorVerdict = .pending
            case .approved:   directorVerdict = .confirmed
            case .rejected:   directorVerdict = .excluded
            }
        }
        specReadiness = try container.decodeIfPresent(SpecReadiness.self, forKey: .specReadiness) ?? .notValidated
        inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        elaborationDurationMs = try container.decodeIfPresent(Int.self, forKey: .elaborationDurationMs) ?? 0
        lastAgentId = try container.decodeIfPresent(UUID.self, forKey: .lastAgentId)
        lastAgentLabel = try container.decodeIfPresent(String.self, forKey: .lastAgentLabel)
        parallelGroup = try container.decodeIfPresent(Int.self, forKey: .parallelGroup)
        scenarioGroup = try container.decodeIfPresent(String.self, forKey: .scenarioGroup)
        lastElaborationError = try container.decodeIfPresent(String.self, forKey: .lastElaborationError)
        partialOutput = try container.decodeIfPresent(String.self, forKey: .partialOutput)
        lastCheckpoint = try container.decodeIfPresent(Date.self, forKey: .lastCheckpoint)
        revisionNote = try container.decodeIfPresent(String.self, forKey: .revisionNote)
    }
}

// MARK: - Item Edge (Work Graph)

enum EdgeRelationType {
    static let dependsOn   = "depends_on"
    static let refines     = "refines"
    static let replaces    = "replaces"
    static let navigatesTo = "navigates_to"
    static let uses        = "uses"

    static let all = [dependsOn, refines, replaces, navigatesTo, uses]
}

struct ItemEdge: Codable, Equatable, Identifiable {
    let id: UUID
    let sourceId: UUID
    let targetId: UUID
    let relationType: String  // use EdgeRelationType constants

    init(id: UUID = UUID(), sourceId: UUID, targetId: UUID, relationType: String) {
        self.id = id
        self.sourceId = sourceId
        self.targetId = targetId
        self.relationType = relationType
    }
}

// MARK: - Scenario Cluster (connected component in work graph)

/// A group of cross-section items connected by edges, representing a functional scenario.
struct ScenarioCluster: Identifiable {
    let id: UUID
    /// Display name — derived from the primary (root or largest-degree) item.
    let name: String
    /// Items in this cluster, ordered: root items first, then by section type.
    let items: [(item: DeliverableItem, sectionType: String)]
    /// Distinct section types present in this cluster.
    var sectionTypes: Set<String> { Set(items.map(\.sectionType)) }
    /// Verdict progress.
    var approvedCount: Int { items.filter { $0.item.plannerVerdict == .approved }.count }
    var confirmedCount: Int { items.filter { $0.item.directorVerdict == .confirmed }.count }
    var pendingCount: Int { items.filter { $0.item.directorVerdict == .pending }.count }
    var activeCount: Int { items.filter { $0.item.plannerVerdict != .rejected }.count }
}

// MARK: - Deliverable Section

struct DeliverableSection: Identifiable, Codable, Equatable {
    let id: UUID
    var type: String        // "screen-spec", "data-model", "api-spec", "user-flow", etc.
    var label: String       // human-readable: "화면 설계", "데이터 모델", etc.
    var items: [DeliverableItem]

    init(id: UUID = UUID(), type: String, label: String, items: [DeliverableItem] = []) {
        self.id = id
        self.type = type
        self.label = label
        self.items = items
    }

    // MARK: - Convenience

    var completedCount: Int { items.filter { $0.status == .completed }.count }
    var totalCount: Int { items.count }
    var isComplete: Bool { !items.isEmpty && completedCount == totalCount }

    var approvedCount: Int { items.filter { $0.plannerVerdict == .approved }.count }
    var unreviewedCount: Int { items.filter { $0.plannerVerdict == .unreviewed }.count }
    var confirmedCount: Int { items.filter { $0.directorVerdict == .confirmed }.count }
    var pendingReviewCount: Int { items.filter { $0.directorVerdict == .pending && $0.plannerVerdict != .rejected }.count }
    var activeItems: [DeliverableItem] {
        items.filter { $0.plannerVerdict != .rejected }
    }

    /// Items approved for export: confirmed by decision-maker AND elaboration completed.
    /// This is the single canonical filter for all export outputs (spec.json, spec.md, design.json).
    var exportableItems: [DeliverableItem] {
        items.filter { $0.directorVerdict == .confirmed && $0.status == .completed }
    }

    func item(byId id: UUID) -> DeliverableItem? {
        items.first { $0.id == id }
    }

    mutating func updateItem(_ updated: DeliverableItem) {
        guard let idx = items.firstIndex(where: { $0.id == updated.id }) else { return }
        items[idx] = updated
    }

    // MARK: - Section Type Styling

    static func sectionColor(_ type: String) -> Color {
        switch type {
        case "screen-spec":  return .blue
        case "data-model":   return .green
        case "api-spec":     return .orange
        case "user-flow":    return .purple
        case "component":    return .teal
        default:             return .gray
        }
    }

    static func sectionIcon(_ type: String) -> String {
        switch type {
        case "screen-spec":  return "rectangle.on.rectangle"
        case "data-model":   return "cylinder"
        case "api-spec":     return "arrow.left.arrow.right"
        case "user-flow":    return "arrow.triangle.branch"
        case "component":    return "puzzlepiece"
        default:             return "doc"
        }
    }
}

// MARK: - Spec Readiness Validation

/// A single issue found during spec readiness validation.
struct SpecReadinessIssue: Identifiable {
    let id = UUID()
    let itemId: UUID
    let itemName: String
    let sectionType: String
    let severity: Severity
    let message: String

    enum Severity { case error, warning }
}

/// Validates that a DeliverableItem's spec contains the required fields
/// for its section type, so AI dev tools can consume it.
///
/// [Scope] Per-item. Runs against a single `DeliverableItem` during elaboration.
/// [Trigger] `DesignWorkflowViewModel` item-update and elaboration-response handlers;
///           also `DesignWorkflow.hasBlockingIssues` for workflow-wide rollups.
/// [Sibling]
///   - `PhaseGateChecker` — workflow-level phase transition gate, not per-item.
///   - `DesignDocumentValidator` — document-structure validation at export time.
enum SpecReadinessValidator {

    /// Validate a single item and return any issues.
    static func validate(item: DeliverableItem, sectionType: String) -> [SpecReadinessIssue] {
        guard item.plannerVerdict != .rejected else { return [] }
        guard item.status == .completed else { return [] }

        let spec = item.spec
        var issues: [SpecReadinessIssue] = []

        func require(_ key: String, label: String) {
            if spec[key] == nil {
                issues.append(.init(itemId: item.id, itemName: item.name, sectionType: sectionType,
                                    severity: .error, message: "\(label) missing"))
            }
        }

        func requireNonEmptyArray(_ key: String, label: String) {
            if let arr = spec[key]?.arrayValue {
                if arr.isEmpty {
                    issues.append(.init(itemId: item.id, itemName: item.name, sectionType: sectionType,
                                        severity: .error, message: "\(label) is empty"))
                }
            } else if spec[key] == nil {
                issues.append(.init(itemId: item.id, itemName: item.name, sectionType: sectionType,
                                    severity: .error, message: "\(label) missing"))
            }
        }

        func warnIfMissing(_ key: String, label: String) {
            if spec[key] == nil {
                issues.append(.init(itemId: item.id, itemName: item.name, sectionType: sectionType,
                                    severity: .warning, message: "\(label) not specified"))
            }
        }

        switch sectionType {
        case "screen-spec":
            requireNonEmptyArray("components", label: "components")
            warnIfMissing("purpose", label: "purpose")
            warnIfMissing("interactions", label: "interactions")
            warnIfMissing("states", label: "states")

        case "data-model":
            requireNonEmptyArray("fields", label: "fields")
            // Check that fields have types beyond just "string"
            if let fields = spec["fields"]?.arrayValue, !fields.isEmpty {
                let types = fields.compactMap { field -> String? in
                    let dict = (field as? AnyCodable)?.dictValue ?? (field as? [String: Any])
                    return dict?["type"] as? String
                }
                let uniqueTypes = Set(types.map { $0.lowercased() })
                if uniqueTypes.count == 1 && types.count > 2 {
                    issues.append(.init(itemId: item.id, itemName: item.name, sectionType: sectionType,
                                        severity: .warning,
                                        message: "All fields have identical type '\(types.first ?? "")' — may need refinement"))
                }
                // Check fields have names
                let unnamed = fields.filter { field in
                    let dict = (field as? AnyCodable)?.dictValue ?? (field as? [String: Any])
                    return (dict?["name"] as? String)?.isEmpty != false
                }
                if !unnamed.isEmpty {
                    issues.append(.init(itemId: item.id, itemName: item.name, sectionType: sectionType,
                                        severity: .error, message: "\(unnamed.count) field(s) without name"))
                }
            }
            warnIfMissing("relationships", label: "relationships")

        case "api-spec":
            require("method", label: "HTTP method")
            require("path", label: "endpoint path")
            warnIfMissing("response", label: "response schema")
            warnIfMissing("error_responses", label: "error responses")

        case "user-flow":
            requireNonEmptyArray("steps", label: "steps")
            warnIfMissing("trigger", label: "trigger")
            warnIfMissing("success_outcome", label: "success outcome")

        default:
            // Unknown section type — just check spec isn't empty
            if spec.isEmpty {
                issues.append(.init(itemId: item.id, itemName: item.name, sectionType: sectionType,
                                    severity: .error, message: "spec is empty"))
            }
        }

        return issues
    }

    /// Validate all approved items in a workflow.
    static func validateWorkflow(_ wf: DesignWorkflow) -> [SpecReadinessIssue] {
        wf.deliverables.flatMap { section in
            section.items.flatMap { validate(item: $0, sectionType: section.type) }
        }
    }

    /// Early-exit check: returns true as soon as any error-severity issue is found.
    static func hasBlockingIssues(_ wf: DesignWorkflow) -> Bool {
        for section in wf.deliverables {
            for item in section.items {
                let issues = validate(item: item, sectionType: section.type)
                if issues.contains(where: { $0.severity == .error }) { return true }
            }
        }
        return false
    }

    /// Translate a technical spec issue into a simplified key + item name,
    /// so the view layer can apply localized formatting.
    static func simplifyIssueKey(_ issue: SpecReadinessIssue) -> (key: String, itemName: String) {
        let msg = issue.message.lowercased()
        let key: String
        if msg.contains("components") {
            key = "components_missing"
        } else if msg.contains("field") && msg.contains("name") {
            key = "fields_unnamed"
        } else if msg.contains("field") {
            key = "fields_missing"
        } else if msg.contains("http method") || msg.contains("endpoint") {
            key = "api_method_missing"
        } else if msg.contains("steps") {
            key = "steps_missing"
        } else if msg.contains("spec is empty") {
            key = "spec_empty"
        } else {
            key = "generic"
        }
        return (key, issue.itemName)
    }
}

// MARK: - Team Member

struct DesignTeamMember: Identifiable, Codable {
    let id: UUID
    var name: String
    var role: String
    var responsibility: String
    var resolvedAgent: Agent?
    var fallbackInfo: String?
    var agentReason: String?

    init(
        id: UUID = UUID(),
        name: String,
        role: String = "",
        responsibility: String,
        resolvedAgent: Agent? = nil,
        fallbackInfo: String? = nil,
        agentReason: String? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.responsibility = responsibility
        self.resolvedAgent = resolvedAgent
        self.fallbackInfo = fallbackInfo
        self.agentReason = agentReason
    }
}

// MARK: - Step Status

enum DesignStepStatus: String, Codable, Equatable {
    case pending
    case inProgress
    case awaitingDecision
    case completed
    case failed
    case skipped
}

// MARK: - Structured Step Output

struct StepStructuredOutput: Codable, Equatable {
    var summary: String
    var deliverables: [String]
    var findings: [String]
}

// MARK: - Workflow Step

/// Represents a unit of agent work — used for item elaboration tasks.
struct DesignWorkflowStep: Identifiable, Codable {
    let id: UUID
    var sequence: Int
    var title: String
    var description: String
    var goal: String
    var assignedMemberIndex: Int
    var status: DesignStepStatus
    var prompt: String
    var output: String
    var structuredOutput: StepStructuredOutput?
    var decision: DesignDecision?
    var retryCount: Int
    var lastFailureReason: String?
    var startedAt: Date?
    var completedAt: Date?
    var previewItems: [PreviewItem]
    var verificationResult: VerificationResult?
    var parallelGroup: Int?
    /// Links this step to a deliverable item being elaborated.
    var deliverableItemId: UUID?

    init(
        id: UUID = UUID(),
        sequence: Int,
        title: String,
        description: String,
        goal: String,
        assignedMemberIndex: Int,
        status: DesignStepStatus = .pending,
        prompt: String = "",
        output: String = "",
        structuredOutput: StepStructuredOutput? = nil,
        decision: DesignDecision? = nil,
        retryCount: Int = 0,
        lastFailureReason: String? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        previewItems: [PreviewItem] = [],
        verificationResult: VerificationResult? = nil,
        parallelGroup: Int? = nil,
        deliverableItemId: UUID? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.title = title
        self.description = description
        self.goal = goal
        self.assignedMemberIndex = assignedMemberIndex
        self.status = status
        self.prompt = prompt
        self.output = output
        self.structuredOutput = structuredOutput
        self.decision = decision
        self.retryCount = retryCount
        self.lastFailureReason = lastFailureReason
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.previewItems = previewItems
        self.verificationResult = verificationResult
        self.parallelGroup = parallelGroup
        self.deliverableItemId = deliverableItemId
    }
}

// MARK: - Decision

enum DesignDecisionStatus: String, Codable, Equatable {
    case pending
    case approved
    case rejected
}

struct DesignDecision: Identifiable, Equatable, Codable {
    let id: UUID
    var title: String
    var body: String
    var options: [String]
    var status: DesignDecisionStatus
    var selectedOption: String?
    var isAutonomous: Bool
    var reasoning: String

    // Uncertainty escalation fields (optional, backward-compatible)
    var escalationType: UncertaintyType?
    var priority: UncertaintyPriority
    var relatedItemId: UUID?
    var resolvedAt: Date?
    var userResponse: String?
    var autonomousReasoning: String?
    var triggeredAxiom: UncertaintyAxiom?

    /// True when this decision represents an uncertainty escalation.
    var isUncertainty: Bool { escalationType != nil }

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        options: [String] = [],
        status: DesignDecisionStatus = .pending,
        selectedOption: String? = nil,
        isAutonomous: Bool = false,
        reasoning: String = "",
        escalationType: UncertaintyType? = nil,
        priority: UncertaintyPriority = .important,
        relatedItemId: UUID? = nil,
        resolvedAt: Date? = nil,
        userResponse: String? = nil,
        autonomousReasoning: String? = nil,
        triggeredAxiom: UncertaintyAxiom? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.options = options
        self.status = status
        self.selectedOption = selectedOption
        self.isAutonomous = isAutonomous
        self.reasoning = reasoning
        self.escalationType = escalationType
        self.priority = priority
        self.relatedItemId = relatedItemId
        self.resolvedAt = resolvedAt
        self.userResponse = userResponse
        self.autonomousReasoning = autonomousReasoning
        self.triggeredAxiom = triggeredAxiom
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        options = try container.decode([String].self, forKey: .options)
        status = try container.decode(DesignDecisionStatus.self, forKey: .status)
        selectedOption = try container.decodeIfPresent(String.self, forKey: .selectedOption)
        isAutonomous = try container.decodeIfPresent(Bool.self, forKey: .isAutonomous) ?? false
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning) ?? ""
        escalationType = try container.decodeIfPresent(UncertaintyType.self, forKey: .escalationType)
        priority = try container.decodeIfPresent(UncertaintyPriority.self, forKey: .priority) ?? .important
        relatedItemId = try container.decodeIfPresent(UUID.self, forKey: .relatedItemId)
        resolvedAt = try container.decodeIfPresent(Date.self, forKey: .resolvedAt)
        userResponse = try container.decodeIfPresent(String.self, forKey: .userResponse)
        autonomousReasoning = try container.decodeIfPresent(String.self, forKey: .autonomousReasoning)
        triggeredAxiom = try container.decodeIfPresent(UncertaintyAxiom.self, forKey: .triggeredAxiom)
    }
}

// MARK: - Design Chat Message

struct DesignChatMessage: Identifiable, Codable {
    let id: UUID
    var role: Role
    var content: String
    let createdAt: Date

    enum Role: String, Codable {
        case user
        case design = "director"
        case system     // for status messages (e.g. "Elaborating screen-001...")
    }

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

// MARK: - Reference Image Data (carried through design pipeline)

struct ReferenceImageData: Codable {
    let category: String
    let productName: String
    let aspect: String
    let searchURL: String?
    let addedDuring: String
}

// MARK: - Workflow Container

struct DesignWorkflow: Codable {
    var phase: DesignPhase
    var taskDescription: String
    var projectSpec: ProjectSpec?
    var deliverables: [DeliverableSection]
    var teamMembers: [DesignTeamMember]
    var steps: [DesignWorkflowStep]           // active agent work queue
    var directorSummary: String
    var apiCallCount: Int                       // number of CLI agent invocations
    var totalInputChars: Int                    // sum of prompt characters sent
    var totalOutputChars: Int                   // sum of response characters received
    var providerUsage: [String: ProviderUsageStats]?  // ProviderKey.rawValue → per-provider stats
    var chatHistory: [DesignChatMessage]
    var edges: [ItemEdge]                       // work graph: item-to-item relationships
    var uncertainties: [DesignDecision]        // uncertainty escalation queue

    // Approach selection (7-step reasoning output)
    var approachOptions: [ApproachOption]?       // 2-3 approaches from analysis
    var selectedApproachId: UUID?                // user's chosen approach
    var hiddenRequirements: [String]             // inferred unstated requirements

    // Analysis checkpoint for crash resilience
    var partialAnalysisOutput: String?           // streamed analysis text before completion

    // Reference anchors from exploration phase
    var referenceAnchors: [ReferenceImageData]?

    // Design Freeze — records when the approach was confirmed and skeleton generation began
    var designFreezeAt: Date?

    // Structure Approval — records when the REFINE phase ended and SPECIFY began
    var structureApprovedAt: Date?

    /// Whether the skeleton structure has been approved for detailed elaboration.
    var isStructureApproved: Bool {
        structureApprovedAt != nil
    }

    // MARK: - Transient lookup caches (not persisted)
    private(set) var edgeIndex: [UUID: [ItemEdge]] = [:]
    private(set) var itemLookup: [UUID: (sectionIndex: Int, itemIndex: Int)] = [:]

    /// Monotonically increasing counter tracking structural mutations (not persisted).
    /// Used by syncToRequest to skip redundant serialization when nothing changed.
    private(set) var mutationCounter: Int = 0

    private enum CodingKeys: String, CodingKey {
        case phase, taskDescription, projectSpec, deliverables, teamMembers,
             steps, directorSummary, apiCallCount, totalInputChars, totalOutputChars,
             providerUsage, chatHistory, edges, uncertainties,
             approachOptions, selectedApproachId, hiddenRequirements,
             partialAnalysisOutput, referenceAnchors, designFreezeAt, structureApprovedAt
    }

    /// Alias for `directorSummary` — stored key is kept for JSON backward compatibility.
    var designSummary: String {
        get { directorSummary }
        set { directorSummary = newValue }
    }

    /// Estimated token count (input + output chars / 4)
    var estimatedTokens: Int {
        (totalInputChars + totalOutputChars) / 4
    }

    /// Total deliverable items across all sections.
    var totalItemCount: Int {
        deliverables.reduce(0) { $0 + $1.totalCount }
    }

    /// Completed deliverable items across all sections.
    var completedItemCount: Int {
        deliverables.reduce(0) { $0 + $1.completedCount }
    }

    /// Whether all deliverable items are completed.
    var allItemsCompleted: Bool {
        totalItemCount > 0 && completedItemCount == totalItemCount
    }

    /// Count of active items (excluding rejected).
    var activeItemCount: Int {
        deliverables.reduce(0) { $0 + $1.activeItems.count }
    }

    /// Count of planner-approved items across all sections.
    var approvedItemCount: Int {
        deliverables.reduce(0) { $0 + $1.approvedCount }
    }

    /// Count of items not yet reviewed by planner.
    var unreviewedItemCount: Int {
        deliverables.reduce(0) { $0 + $1.unreviewedCount }
    }

    /// Count of decision-maker-confirmed items across all sections.
    var confirmedItemCount: Int {
        deliverables.reduce(0) { $0 + $1.confirmedCount }
    }

    /// Count of items pending decision-maker review.
    var pendingReviewCount: Int {
        deliverables.reduce(0) { $0 + $1.pendingReviewCount }
    }

    /// True when all active items are confirmed by the decision-maker.
    var allItemsConfirmed: Bool {
        activeItemCount > 0 && confirmedItemCount == activeItemCount
    }

    /// True when all active (non-rejected) items are confirmed, have no blocking spec issues,
    /// and at least one item is exportable (confirmed + completed with elaborated content).
    var readyForCompletion: Bool {
        allItemsConfirmed && !hasBlockingSpecIssues
        && !deliverables.flatMap(\.exportableItems).isEmpty
    }

    /// Reasons why `readyForCompletion` is false (empty when ready).
    var completionBlockers: [String] {
        var result: [String] = []
        if !allItemsConfirmed { result.append("unconfirmedItems") }
        if hasBlockingSpecIssues { result.append("blockingSpecIssues") }
        if deliverables.flatMap(\.exportableItems).isEmpty { result.append("noExportableItems") }
        return result
    }

    // MARK: - Convergence Metrics

    /// Convergence rate: confirmed / active (0.0 ~ 1.0)
    var convergenceRate: Double {
        guard activeItemCount > 0 else { return 0 }
        return Double(confirmedItemCount) / Double(activeItemCount)
    }

    /// Number of items with oscillating verdicts (verdictFlipCount >= 2).
    var oscillatingItemCount: Int {
        deliverables.flatMap(\.items)
            .filter { $0.plannerVerdict != .rejected && $0.verdictFlipCount >= 2 }
            .count
    }

    /// Whether any items show oscillation patterns.
    var hasOscillationWarning: Bool {
        oscillatingItemCount > 0
    }

    /// Readiness summary for decision-maker display — translates spec validation into a percentage and hints.
    var readinessSummary: ReadinessSummary {
        let active = deliverables.flatMap(\.activeItems)
        guard !active.isEmpty else {
            return ReadinessSummary(percentage: 0, blockingCount: 0, issueKeys: [])
        }
        let allIssues = specReadinessIssues
        let errors = allIssues.filter { $0.severity == .error }
        let itemsWithErrors = Set(errors.map(\.itemId))
        let readyCount = active.filter { !itemsWithErrors.contains($0.id) }.count
        let pct = (readyCount * 100) / active.count
        let keys = errors.map { SpecReadinessValidator.simplifyIssueKey($0) }
        return ReadinessSummary(
            percentage: pct,
            blockingCount: errors.count,
            issueKeys: keys
        )
    }

    /// Spec readiness issues for all approved items.
    var specReadinessIssues: [SpecReadinessIssue] {
        SpecReadinessValidator.validateWorkflow(self)
    }

    /// True if any approved item has a severity-error spec issue (early-exit, avoids full validation).
    var hasBlockingSpecIssues: Bool {
        SpecReadinessValidator.hasBlockingIssues(self)
    }

    // MARK: - Uncertainty Queries

    /// Pending uncertainties awaiting user resolution.
    var pendingUncertainties: [DesignDecision] {
        uncertainties.filter { $0.isUncertainty && $0.status == .pending }
    }

    /// Blocking uncertainties that prevent item elaboration.
    var blockingUncertainties: [DesignDecision] {
        uncertainties.filter { $0.isUncertainty && $0.status == .pending && $0.priority == .blocking }
    }

    /// Autonomously resolved uncertainties (shown collapsed in UI).
    var autonomousUncertainties: [DesignDecision] {
        uncertainties.filter { $0.isUncertainty && $0.isAutonomous && $0.status != .pending }
    }

    /// Uncertainties related to a specific deliverable item.
    func uncertainties(for itemId: UUID) -> [DesignDecision] {
        uncertainties.filter { $0.isUncertainty && $0.relatedItemId == itemId }
    }

    /// Pending uncertainties for a specific item.
    func pendingUncertainties(for itemId: UUID) -> [DesignDecision] {
        uncertainties.filter { $0.isUncertainty && $0.status == .pending && $0.relatedItemId == itemId }
    }

    /// Resolve an uncertainty in-place.
    mutating func resolveUncertainty(_ id: UUID, transform: (inout DesignDecision) -> Void) {
        guard let idx = uncertainties.firstIndex(where: { $0.id == id }) else { return }
        transform(&uncertainties[idx])
        mutationCounter += 1
    }

    /// Transition to a new phase, incrementing mutationCounter so the change is persisted.
    mutating func transitionTo(_ newPhase: DesignPhase) {
        phase = newPhase
        mutationCounter += 1
    }

    /// Record API usage, incrementing mutationCounter so the change is persisted.
    /// - Parameters:
    ///   - provider: The provider that handled this call (nil = unknown/legacy).
    ///   - succeeded: Whether the call produced a usable response.
    mutating func recordUsage(promptLength: Int, responseLength: Int,
                              provider: ProviderKey? = nil, succeeded: Bool = true) {
        apiCallCount += 1
        totalInputChars += promptLength
        totalOutputChars += responseLength
        if let provider {
            var stats = (providerUsage ?? [:])[provider.rawValue] ?? ProviderUsageStats()
            stats.callCount += 1
            stats.inputChars += promptLength
            stats.outputChars += responseLength
            if !succeeded { stats.failedCallCount += 1 }
            if providerUsage == nil { providerUsage = [:] }
            providerUsage?[provider.rawValue] = stats
        }
        mutationCounter += 1
    }

    /// Append a chat message, incrementing mutationCounter so the change is persisted.
    mutating func appendChatMessage(_ message: DesignChatMessage) {
        chatHistory.append(message)
        mutationCounter += 1
    }

    /// Items with no incoming edges — entry points in the work graph.
    var rootItemIds: Set<UUID> {
        let allTargetIds = Set(edges.map(\.targetId))
        let allItemIds = Set(deliverables.flatMap { $0.items.map(\.id) })
        return allItemIds.subtracting(allTargetIds)
    }

    func teamMember(for step: DesignWorkflowStep) -> DesignTeamMember? {
        guard step.assignedMemberIndex >= 0,
              step.assignedMemberIndex < teamMembers.count else { return nil }
        return teamMembers[step.assignedMemberIndex]
    }

    /// Rebuild transient lookup caches after any structural change.
    mutating func rebuildIndexes() {
        var eidx: [UUID: [ItemEdge]] = [:]
        for edge in edges {
            eidx[edge.sourceId, default: []].append(edge)
            eidx[edge.targetId, default: []].append(edge)
        }
        edgeIndex = eidx

        var iidx: [UUID: (sectionIndex: Int, itemIndex: Int)] = [:]
        for (si, section) in deliverables.enumerated() {
            for (ii, item) in section.items.enumerated() {
                iidx[item.id] = (si, ii)
            }
        }
        itemLookup = iidx
    }

    /// Find a deliverable item by ID across all sections.
    func findItem(byId itemId: UUID) -> (sectionIndex: Int, itemIndex: Int, item: DeliverableItem)? {
        if let loc = itemLookup[itemId] {
            let si = loc.sectionIndex, ii = loc.itemIndex
            guard si < deliverables.count, ii < deliverables[si].items.count else { return nil }
            return (si, ii, deliverables[si].items[ii])
        }
        // Fallback linear search
        for (si, section) in deliverables.enumerated() {
            if let ii = section.items.firstIndex(where: { $0.id == itemId }) {
                return (si, ii, section.items[ii])
            }
        }
        return nil
    }

    /// Find a deliverable section by type.
    func section(byType type: String) -> DeliverableSection? {
        deliverables.first { $0.type == type }
    }

    /// Update a deliverable item in-place.
    mutating func updateItem(_ itemId: UUID, transform: (inout DeliverableItem) -> Void) {
        for si in deliverables.indices {
            if let ii = deliverables[si].items.firstIndex(where: { $0.id == itemId }) {
                transform(&deliverables[si].items[ii])
                mutationCounter += 1
                return
            }
        }
    }

    /// All edges connected to a specific item (as source or target).
    func edges(for itemId: UUID) -> [ItemEdge] {
        edgeIndex[itemId] ?? edges.filter { $0.sourceId == itemId || $0.targetId == itemId }
    }

    /// Append an edge only if an identical relationship doesn't already exist.
    /// Returns `true` if the edge was added, `false` if duplicate or cycle detected.
    @discardableResult
    mutating func addEdgeIfNew(_ edge: ItemEdge) -> Bool {
        let duplicate = edges.contains {
            $0.sourceId == edge.sourceId &&
            $0.targetId == edge.targetId &&
            $0.relationType == edge.relationType
        }
        guard !duplicate else { return false }

        // Reject depends_on edges that would create cycles
        if edge.relationType == EdgeRelationType.dependsOn {
            if wouldCreateCycle(sourceId: edge.sourceId, targetId: edge.targetId) {
                return false
            }
        }

        edges.append(edge)
        mutationCounter += 1
        rebuildIndexes()
        return true
    }

    /// Remove an edge by its ID.
    mutating func removeEdge(id: UUID) {
        edges.removeAll { $0.id == id }
        mutationCounter += 1
        rebuildIndexes()
    }

    /// Remove all edges involving a specific item (for item deletion cleanup).
    mutating func removeEdges(involving itemId: UUID) {
        edges.removeAll { $0.sourceId == itemId || $0.targetId == itemId }
        mutationCounter += 1
        rebuildIndexes()
    }

    /// Check whether adding a depends_on edge from sourceId to targetId would create a cycle.
    /// Uses iterative DFS from targetId, following only depends_on edges, checking if we can reach sourceId.
    func wouldCreateCycle(sourceId: UUID, targetId: UUID) -> Bool {
        var visited = Set<UUID>()
        var stack = [targetId]

        while let current = stack.popLast() {
            if current == sourceId { return true }
            guard !visited.contains(current) else { continue }
            visited.insert(current)

            for edge in edges where edge.sourceId == current && edge.relationType == EdgeRelationType.dependsOn {
                stack.append(edge.targetId)
            }
        }
        return false
    }

    /// Count of items transitively dependent on the given item via depends_on edges.
    /// BFS follows reverse depends_on direction: if A depends_on B, then deferring B impacts A.
    func downstreamImpactCount(for itemId: UUID) -> Int {
        var visited = Set<UUID>()
        var queue = [itemId]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            for edge in edges where edge.targetId == current && edge.relationType == EdgeRelationType.dependsOn {
                guard !visited.contains(edge.sourceId) else { continue }
                visited.insert(edge.sourceId)
                queue.append(edge.sourceId)
            }
        }
        return visited.count
    }

    /// Compute scenario clusters by finding connected components across all edge types.
    /// Each cluster groups items linked by any relation (depends_on, navigates_to, uses, etc.)
    /// regardless of section type, enabling "feature-level" review.
    func computeScenarioClusters(scenarioSuffix: String = "scenario", moreFormat: @escaping (Int) -> String = { n in "+\(n) more" }) -> [ScenarioCluster] {
        let allItems = deliverables.flatMap { sec in sec.items.map { (item: $0, sectionType: sec.type) } }
        let allIds = Set(allItems.map(\.item.id))
        guard !allIds.isEmpty else { return [] }

        // Union-Find
        var parent = [UUID: UUID]()
        var rank = [UUID: Int]()
        for id in allIds { parent[id] = id; rank[id] = 0 }

        func find(_ x: UUID) -> UUID {
            var root = x
            while parent[root] != root { root = parent[root]! }
            var curr = x
            while curr != root { let next = parent[curr]!; parent[curr] = root; curr = next }
            return root
        }
        func union(_ a: UUID, _ b: UUID) {
            let ra = find(a), rb = find(b)
            guard ra != rb else { return }
            if rank[ra]! < rank[rb]! { parent[ra] = rb }
            else if rank[ra]! > rank[rb]! { parent[rb] = ra }
            else { parent[rb] = ra; rank[ra]! += 1 }
        }

        // Union all edges (all relation types, undirected)
        for edge in edges {
            guard allIds.contains(edge.sourceId), allIds.contains(edge.targetId) else { continue }
            union(edge.sourceId, edge.targetId)
        }

        // Collect components
        var components = [UUID: [(item: DeliverableItem, sectionType: String)]]()
        for entry in allItems {
            let root = find(entry.item.id)
            components[root, default: []].append(entry)
        }

        // Build clusters — pending decisions first within each cluster,
        // clusters with pending items first across the list
        let roots = rootItemIds
        return components.map { (root, members) in
            // Sort: pending verdict first, then root items, then by section type
            let sorted = members.sorted { a, b in
                let aPending = a.item.directorVerdict == .pending
                let bPending = b.item.directorVerdict == .pending
                if aPending != bPending { return aPending }
                let aIsRoot = roots.contains(a.item.id)
                let bIsRoot = roots.contains(b.item.id)
                if aIsRoot != bIsRoot { return aIsRoot }
                if a.sectionType != b.sectionType { return a.sectionType < b.sectionType }
                if a.item.name != b.item.name { return a.item.name < b.item.name }
                return a.item.id.uuidString < b.item.id.uuidString
            }
            // Name: LLM scenarioGroup → heuristic suffix → verbatim item name
            let scenarioGroupNames = sorted.compactMap(\.item.scenarioGroup)
            let name: String
            if !scenarioGroupNames.isEmpty {
                let counts = Dictionary(grouping: scenarioGroupNames, by: { $0 }).mapValues(\.count)
                let maxCount = counts.values.max() ?? 0
                name = counts.filter { $0.value == maxCount }.keys.sorted().first ?? scenarioGroupNames[0]
            } else {
                let baseName = sorted.first(where: { roots.contains($0.item.id) })?.item.name ?? sorted.first?.item.name ?? "Cluster"
                let sectionTypeCount = Set(sorted.map(\.sectionType)).count
                if sorted.count > 1 && sectionTypeCount >= 2 {
                    name = "\(baseName) \(scenarioSuffix)"
                } else if sorted.count > 1 {
                    name = "\(baseName) \(moreFormat(sorted.count - 1))"
                } else {
                    name = baseName
                }
            }
            return ScenarioCluster(id: root, name: name, items: sorted)
        }.sorted { a, b in
            let aPending = a.pendingCount
            let bPending = b.pendingCount
            if aPending != bPending { return aPending > bPending }
            if a.items.count != b.items.count { return a.items.count > b.items.count }
            if a.name != b.name { return a.name < b.name }
            return a.id.uuidString < b.id.uuidString
        }
    }

    /// Compute parallel execution groups from depends_on edges using Kahn's algorithm.
    /// Returns a dictionary mapping itemId → group number (0-indexed).
    /// Items with no dependencies get group 0; items depending on group-0 items get group 1, etc.
    func computeParallelGroups() -> [UUID: Int] {
        let allItems = deliverables.flatMap(\.items)
        let allIds = Set(allItems.map(\.id))

        var inDegree = [UUID: Int]()
        var dependents = [UUID: [UUID]]()  // target → [sources that depend on it]

        for id in allIds {
            inDegree[id] = 0
            dependents[id] = []
        }

        for edge in edges where edge.relationType == EdgeRelationType.dependsOn {
            guard allIds.contains(edge.sourceId), allIds.contains(edge.targetId) else { continue }
            inDegree[edge.sourceId, default: 0] += 1
            dependents[edge.targetId, default: []].append(edge.sourceId)
        }

        var groups = [UUID: Int]()
        var currentGroup = allIds.filter { inDegree[$0] == 0 }
        var groupNumber = 0

        while !currentGroup.isEmpty {
            var nextGroup = [UUID]()
            for id in currentGroup {
                groups[id] = groupNumber
                for dependent in dependents[id, default: []] {
                    inDegree[dependent, default: 1] -= 1
                    if inDegree[dependent] == 0 {
                        nextGroup.append(dependent)
                    }
                }
            }
            currentGroup = Set(nextGroup)
            groupNumber += 1
        }

        // Handle any items not yet assigned (orphaned or in residual cycles)
        for id in allIds where groups[id] == nil {
            groups[id] = groupNumber
        }

        return groups
    }

    init(
        phase: DesignPhase = .input,
        taskDescription: String = "",
        projectSpec: ProjectSpec? = nil,
        deliverables: [DeliverableSection] = [],
        teamMembers: [DesignTeamMember] = [],
        steps: [DesignWorkflowStep] = [],
        directorSummary: String = "",
        apiCallCount: Int = 0,
        totalInputChars: Int = 0,
        totalOutputChars: Int = 0,
        chatHistory: [DesignChatMessage] = [],
        edges: [ItemEdge] = [],
        uncertainties: [DesignDecision] = [],
        approachOptions: [ApproachOption]? = nil,
        selectedApproachId: UUID? = nil,
        hiddenRequirements: [String] = []
    ) {
        self.phase = phase
        self.taskDescription = taskDescription
        self.projectSpec = projectSpec
        self.deliverables = deliverables
        self.teamMembers = teamMembers
        self.steps = steps
        self.directorSummary = directorSummary
        self.apiCallCount = apiCallCount
        self.totalInputChars = totalInputChars
        self.totalOutputChars = totalOutputChars
        self.chatHistory = chatHistory
        self.edges = edges
        self.uncertainties = uncertainties
        self.approachOptions = approachOptions
        self.selectedApproachId = selectedApproachId
        self.hiddenRequirements = hiddenRequirements
        rebuildIndexes()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phase = try container.decode(DesignPhase.self, forKey: .phase)
        taskDescription = try container.decode(String.self, forKey: .taskDescription)
        projectSpec = try container.decodeIfPresent(ProjectSpec.self, forKey: .projectSpec)
        deliverables = try container.decodeIfPresent([DeliverableSection].self, forKey: .deliverables) ?? []
        teamMembers = try container.decodeIfPresent([DesignTeamMember].self, forKey: .teamMembers) ?? []
        steps = try container.decodeIfPresent([DesignWorkflowStep].self, forKey: .steps) ?? []
        directorSummary = try container.decodeIfPresent(String.self, forKey: .directorSummary) ?? ""
        apiCallCount = try container.decodeIfPresent(Int.self, forKey: .apiCallCount) ?? 0
        totalInputChars = try container.decodeIfPresent(Int.self, forKey: .totalInputChars) ?? 0
        totalOutputChars = try container.decodeIfPresent(Int.self, forKey: .totalOutputChars) ?? 0
        chatHistory = try container.decodeIfPresent([DesignChatMessage].self, forKey: .chatHistory) ?? []
        edges = try container.decodeIfPresent([ItemEdge].self, forKey: .edges) ?? []
        uncertainties = try container.decodeIfPresent([DesignDecision].self, forKey: .uncertainties) ?? []
        approachOptions = try container.decodeIfPresent([ApproachOption].self, forKey: .approachOptions)
        selectedApproachId = try container.decodeIfPresent(UUID.self, forKey: .selectedApproachId)
        hiddenRequirements = try container.decodeIfPresent([String].self, forKey: .hiddenRequirements) ?? []
        referenceAnchors = try container.decodeIfPresent([ReferenceImageData].self, forKey: .referenceAnchors)
        rebuildIndexes()
    }
}

// MARK: - Output Preview

enum PreviewType: String, Codable, Equatable {
    case webPage        // HTML -> WKWebView
    case image          // PNG/JPG -> NSImage
    case terminal       // raw text output
}

struct PreviewItem: Identifiable, Codable, Equatable {
    let id: UUID
    var type: PreviewType
    var title: String
    var filePath: String            // relative path from project root
    var absolutePath: String        // computed at runtime -- excluded from Codable

    private enum CodingKeys: String, CodingKey {
        case id, type, title, filePath
    }

    init(
        id: UUID = UUID(),
        type: PreviewType,
        title: String,
        filePath: String,
        absolutePath: String = ""
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.filePath = filePath
        self.absolutePath = absolutePath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(PreviewType.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        filePath = try container.decode(String.self, forKey: .filePath)
        absolutePath = ""  // recomputed at runtime
    }
}

// MARK: - Build/Test Verification

enum DetectedProjectType: String, Codable {
    case swiftPackage       // Package.swift
    case xcodeProject       // .xcodeproj
    case nodeJS             // package.json
    case python             // pyproject.toml / setup.py
    case unknown
}

struct VerificationResult: Codable, Equatable {
    var buildExitCode: Int32
    var buildOutput: String
    var testExitCode: Int32?
    var testOutput: String?
    var overallPassed: Bool
    var failureSummary: String

    init(
        buildExitCode: Int32,
        buildOutput: String,
        testExitCode: Int32? = nil,
        testOutput: String? = nil,
        overallPassed: Bool,
        failureSummary: String = ""
    ) {
        self.buildExitCode = buildExitCode
        self.buildOutput = buildOutput
        self.testExitCode = testExitCode
        self.testOutput = testOutput
        self.overallPassed = overallPassed
        self.failureSummary = failureSummary
    }
}

// MARK: - Design Analysis Response (auto-analysis + skeleton)

struct DesignAnalysisResponse: Codable {
    let projectSpec: ProjectSpecJSON
    let message: String?
    let uncertainties: [UncertaintySpec]?

    // New: approach-based analysis (7-step reasoning)
    let hiddenRequirements: [String]?
    let approaches: [ApproachSpec]?

    // Legacy: direct deliverables (backward-compatible — used when approaches is absent)
    let deliverables: [DeliverableSectionSpec]?
    let relationships: [RelationshipSpec]?

    /// Returns the recommended approach, or the first one, or nil if no approaches.
    var recommendedApproach: ApproachSpec? {
        approaches?.first(where: { $0.recommended == true }) ?? approaches?.first
    }

    /// True if response uses the new approach-based format.
    var hasApproaches: Bool {
        guard let a = approaches else { return false }
        return a.count > 0
    }

    struct ProjectSpecJSON: Codable {
        let name: String?
        let type: String
        let techStack: [String: String]?
    }

    struct ApproachSpec: Codable {
        let label: String
        let summary: String
        let pros: [String]?
        let cons: [String]?
        let risks: [String]?
        let estimatedComplexity: String?
        let recommended: Bool?
        let reasoning: String?
        let sectionTypes: [String]?              // hint: ["screen-spec", "data-model", ...]
        let deliverables: [DeliverableSectionSpec]?  // nil when split into skeleton call
        let relationships: [RelationshipSpec]?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            label = try container.decode(String.self, forKey: .label)
            summary = try container.decode(String.self, forKey: .summary)
            pros = try container.decodeIfPresent([String].self, forKey: .pros)
            cons = try container.decodeIfPresent([String].self, forKey: .cons)
            risks = try container.decodeIfPresent([String].self, forKey: .risks)
            estimatedComplexity = try container.decodeIfPresent(String.self, forKey: .estimatedComplexity)
            recommended = try container.decodeIfPresent(Bool.self, forKey: .recommended)
            reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)
            sectionTypes = try container.decodeIfPresent([String].self, forKey: .sectionTypes)
            relationships = try container.decodeIfPresent([RelationshipSpec].self, forKey: .relationships)

            // GPT may output deliverables as an array or a dictionary keyed by type
            if let arr = try? container.decodeIfPresent([DeliverableSectionSpec].self, forKey: .deliverables) {
                deliverables = arr
            } else if let dict = try? container.decodeIfPresent([String: [ItemSkeleton]].self, forKey: .deliverables) {
                deliverables = dict.map { DeliverableSectionSpec(type: $0.key, label: $0.key, items: $0.value) }
            } else {
                deliverables = nil
            }
        }
    }

    struct DeliverableSectionSpec: Codable {
        let type: String?
        let label: String?
        let items: [ItemSkeleton]?
    }

    struct ItemSkeleton: Codable {
        let name: String
        let briefDescription: String?
        let parallelGroup: Int?
        let plannerQuestion: String?
        let scenarioGroup: String?
        let components: [[String: String]]?  // Screen-spec wireframe hint
        let purpose: String?                  // Screen purpose (used by StoryboardScreenCard)

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            briefDescription = try container.decodeIfPresent(String.self, forKey: .briefDescription)
            parallelGroup = try container.decodeIfPresent(Int.self, forKey: .parallelGroup)
            plannerQuestion = try container.decodeIfPresent(String.self, forKey: .plannerQuestion)
            scenarioGroup = try container.decodeIfPresent(String.self, forKey: .scenarioGroup)
            components = try container.decodeIfPresent([[String: String]].self, forKey: .components)
            purpose = try container.decodeIfPresent(String.self, forKey: .purpose)
        }
    }

    struct RelationshipSpec: Codable {
        let sourceName: String
        let targetName: String
        let relationType: String
    }

    struct UncertaintySpec: Codable {
        let type: String             // "question", "suggestion", "discussion", "information_gap"
        let priority: String?        // "blocking", "important", "advisory"
        let title: String
        let body: String
        let options: [String]?
        let relatedItemName: String? // resolved to item ID after analysis
        let triggeredBy: String?     // UncertaintyAxiom rawValue

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            priority = try container.decodeIfPresent(String.self, forKey: .priority)
            title = try container.decode(String.self, forKey: .title)
            body = try container.decode(String.self, forKey: .body)
            relatedItemName = try container.decodeIfPresent(String.self, forKey: .relatedItemName)
            triggeredBy = try container.decodeIfPresent(String.self, forKey: .triggeredBy)

            // GPT may output options as [String] or [{label, description, ...}]
            if let strings = try? container.decode([String].self, forKey: .options) {
                options = strings
            } else if let dicts = try? container.decode([[String: String]].self, forKey: .options) {
                options = dicts.compactMap { $0["label"] ?? $0["title"] ?? $0.values.first }
            } else {
                options = nil
            }
        }
    }
}

/// Response from the skeleton structure call (stage 2a — items only).
struct DesignSkeletonResponse: Codable {
    let deliverables: [DesignAnalysisResponse.DeliverableSectionSpec]
    let relationships: [DesignAnalysisResponse.RelationshipSpec]?
    let uncertainties: [DesignAnalysisResponse.UncertaintySpec]?
}

/// Response from the skeleton graph call (stage 2b — relationships + uncertainties).
struct DesignSkeletonGraphResponse: Codable {
    let relationships: [DesignAnalysisResponse.RelationshipSpec]?
    let uncertainties: [DesignAnalysisResponse.UncertaintySpec]?
}

/// Response from the skeleton relationships call (stage 2b-1 — relationships only).
struct DesignSkeletonRelationshipsResponse: Codable {
    let relationships: [DesignAnalysisResponse.RelationshipSpec]?
}

/// Response from the skeleton uncertainties call (stage 2b-2 — uncertainties only).
struct DesignSkeletonUncertaintiesResponse: Codable {
    let uncertainties: [DesignAnalysisResponse.UncertaintySpec]?
}

// MARK: - Consistency Check Response

struct ConsistencyCheckResponse: Codable {
    let issues: [ConsistencyIssue]
    let summary: String
}

struct ConsistencyIssue: Codable, Identifiable {
    let id: String              // "issue-1", "issue-2", …
    let severity: String        // "critical", "warning", "info"
    let category: String        // "missing_item", "broken_reference", "incomplete_item", "inconsistency"
    let description: String
    let affectedItems: [String] // item names for display
    let suggestedFix: String
}

// MARK: - Design Chat Response (orchestration commands)

struct DesignChatResponse: Codable {
    let message: String
    let actions: [DesignActionJSON]?

    struct DesignActionJSON: Codable {
        let type: String            // "elaborate_item", "update_item", "add_item", "remove_item", "add_section", "link_items", "unlink_items", "mark_complete", "raise_uncertainty"
        let sectionType: String?
        let itemId: String?         // UUID string
        let itemName: String?       // for add_item
        let changes: [String: AnyCodable]?  // for update_item
        let sectionLabel: String?   // for add_section
        let items: [DesignAnalysisResponse.ItemSkeleton]?  // for add_section
        let agentId: String?        // optional step agent UUID for elaborate_item
        let sourceItemId: String?   // for link_items
        let targetItemId: String?   // for link_items
        let relationType: String?   // for link_items (e.g. "depends_on", "refines", "replaces")
        // Uncertainty escalation fields
        let uncertaintyType: String?   // "question", "suggestion", "discussion", "information_gap"
        let priority: String?          // "blocking", "important", "advisory"
        let title: String?             // for raise_uncertainty
        let body: String?              // for raise_uncertainty
        let options: [String]?         // for raise_uncertainty (suggestion type)
        let triggeredBy: String?       // UncertaintyAxiom rawValue for raise_uncertainty
    }
}

/// Typed action parsed from DesignActionJSON.
enum DesignAction {
    case elaborateItem(sectionType: String, itemId: UUID, agentId: UUID?)
    case updateItem(sectionType: String, itemId: UUID, changes: [String: AnyCodable])
    case addItem(sectionType: String, name: String, briefDescription: String?)
    case removeItem(sectionType: String, itemId: UUID)
    case addSection(type: String, label: String, items: [DesignAnalysisResponse.ItemSkeleton])
    case linkItems(sourceId: UUID, targetId: UUID, relationType: String)
    case unlinkItems(sourceId: UUID, targetId: UUID, relationType: String?)
    case markComplete
    case raiseUncertainty(type: UncertaintyType, priority: UncertaintyPriority, relatedItemId: UUID?, title: String, body: String, options: [String], triggeredAxiom: UncertaintyAxiom?)

    /// Parse from JSON action, resolving item IDs from workflow context.
    static func from(json: DesignChatResponse.DesignActionJSON, workflow: DesignWorkflow) -> DesignAction? {
        switch json.type {
        case "elaborate_item":
            guard let sectionType = json.sectionType,
                  let itemIdStr = json.itemId,
                  let itemId = UUID(uuidString: itemIdStr) else { return nil }
            let agentId = json.agentId.flatMap { UUID(uuidString: $0) }
            return .elaborateItem(sectionType: sectionType, itemId: itemId, agentId: agentId)

        case "update_item":
            guard let sectionType = json.sectionType,
                  let itemIdStr = json.itemId,
                  let itemId = UUID(uuidString: itemIdStr) else { return nil }
            // Strict JSON schema (DesignJSONSchemas.chat) omits the free-form
            // `changes` object, so the LLM can't emit it directly. It instead
            // encodes update values into the flat fields that the schema does
            // allow — `itemName` for the new name and `body` for the new
            // brief description / spec summary. Accept both shapes: prefer an
            // explicit `changes` dict when present, otherwise reconstruct one
            // from the flat fields.
            var resolved: [String: AnyCodable] = json.changes ?? [:]
            if resolved["name"] == nil,
               let name = json.itemName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                resolved["name"] = AnyCodable(name)
            }
            if resolved["briefDescription"] == nil,
               let body = json.body?.trimmingCharacters(in: .whitespacesAndNewlines),
               !body.isEmpty {
                resolved["briefDescription"] = AnyCodable(body)
            }
            guard !resolved.isEmpty else { return nil }
            return .updateItem(sectionType: sectionType, itemId: itemId, changes: resolved)

        case "add_item":
            guard let sectionType = json.sectionType,
                  let name = json.itemName else { return nil }
            return .addItem(sectionType: sectionType, name: name, briefDescription: nil)

        case "remove_item":
            guard let sectionType = json.sectionType,
                  let itemIdStr = json.itemId,
                  let itemId = UUID(uuidString: itemIdStr) else { return nil }
            return .removeItem(sectionType: sectionType, itemId: itemId)

        case "add_section":
            guard let type = json.sectionType,
                  let label = json.sectionLabel else { return nil }
            return .addSection(type: type, label: label, items: json.items ?? [])

        case "link_items":
            guard let srcStr = json.sourceItemId,
                  let srcId = UUID(uuidString: srcStr),
                  let tgtStr = json.targetItemId,
                  let tgtId = UUID(uuidString: tgtStr),
                  let relation = json.relationType else { return nil }
            return .linkItems(sourceId: srcId, targetId: tgtId, relationType: relation)

        case "unlink_items":
            guard let srcStr = json.sourceItemId,
                  let srcId = UUID(uuidString: srcStr),
                  let tgtStr = json.targetItemId,
                  let tgtId = UUID(uuidString: tgtStr) else { return nil }
            return .unlinkItems(sourceId: srcId, targetId: tgtId, relationType: json.relationType)

        case "mark_complete":
            return .markComplete

        case "raise_uncertainty":
            guard let typeStr = json.uncertaintyType,
                  let uType = UncertaintyType(rawValue: typeStr),
                  let titleStr = json.title,
                  let bodyStr = json.body else { return nil }
            let uPriority = json.priority.flatMap { UncertaintyPriority(rawValue: $0) } ?? .important
            let relatedId = json.itemId.flatMap { UUID(uuidString: $0) }
            let axiom = json.triggeredBy.flatMap { UncertaintyAxiom(rawValue: $0) }
            return .raiseUncertainty(
                type: uType, priority: uPriority, relatedItemId: relatedId,
                title: titleStr, body: bodyStr, options: json.options ?? [],
                triggeredAxiom: axiom)

        default:
            return nil
        }
    }

    /// Human-readable description for display in revision review overlay.
    var displayDescription: String {
        switch self {
        case .elaborateItem(_, let itemId, _):
            return "Re-elaborate item \(itemId.uuidString.prefix(8))"
        case .updateItem(_, _, let changes):
            let keys = changes.keys.sorted().joined(separator: ", ")
            return "Update: \(keys)"
        case .addItem(_, let name, _):
            return "Add: \(name)"
        case .removeItem(_, _):
            return "Remove item"
        case .addSection(_, let label, _):
            return "Add section: \(label)"
        case .linkItems(_, _, let rel):
            return "Link items (\(rel))"
        case .unlinkItems(_, _, _):
            return "Unlink items"
        case .markComplete:
            return "Mark complete"
        case .raiseUncertainty(_, _, _, let title, _, _, _):
            return "Raise question: \(title)"
        }
    }
}

// MARK: - Item Elaboration Response (step agent output)

struct ItemElaborationResponse: Codable {
    let spec: [String: AnyCodable]
    let summary: String?
}
