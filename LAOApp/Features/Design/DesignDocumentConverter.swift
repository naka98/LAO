import Foundation
import LAODomain

// MARK: - DesignDocumentConverter

/// Converts a completed DesignWorkflow into a structured DesignDocument
/// optimized for AI development tool consumption (Claude Code, Codex, etc.).
///
/// Pure function with no side effects — safe to call from any context.
/// [Set] Converter trilogy entry point. This converter must run first — its DesignDocument output is
///       the shared input for `PlanDocumentConverter` (→ ImplementationPlanDocument) and
///       `TestDocumentConverter` (→ TestScenariosDocument).
enum DesignDocumentConverter {

    // MARK: - Public API

    static func convert(_ workflow: DesignWorkflow, requestId: UUID? = nil) -> DesignDocument {
        // Step 1: Filter — approved & completed items only
        let approved = approvedItems(from: workflow)

        // Step 2-3: Classify & Normalize
        let uuidToSlug = buildSlugMap(approved)
        let screens = approved.filter { $0.sectionType == "screen-spec" }
            .map { convertScreen($0, slugMap: uuidToSlug) }
        let models = approved.filter { $0.sectionType == "data-model" }
            .map { convertDataModel($0, slugMap: uuidToSlug) }
        let apis = approved.filter { $0.sectionType == "api-spec" }
            .map { convertAPI($0, slugMap: uuidToSlug) }
        let flows = approved.filter { $0.sectionType == "user-flow" }
            .map { convertUserFlow($0, slugMap: uuidToSlug, allScreens: screens) }

        // Step 5: Cross-references
        let allSpecIds = Set(screens.map(\.id) + models.map(\.id) + apis.map(\.id) + flows.map(\.id))
        let crossRefs = buildCrossReferences(
            workflow: workflow, slugMap: uuidToSlug,
            screens: screens, flows: flows, allSpecIds: allSpecIds
        )

        // Step 6: Implementation order
        let implOrder = computeImplementationOrder(
            workflow: workflow, slugMap: uuidToSlug, allSpecIds: allSpecIds
        )

        // Step 7: Global state design (electrical wiring diagram)
        let globalState = extractGlobalStateDesign(screens: screens, flows: flows)

        // Step 8: Assemble
        let techStack: [String: String]? = {
            if let ts = workflow.projectSpec?.techStack, !ts.isEmpty { return ts }
            return nil
        }()
        let refAnchors: [ReferenceAnchorOutput]? = workflow.referenceAnchors?.map {
            ReferenceAnchorOutput(
                category: $0.category, productName: $0.productName,
                aspect: $0.aspect, searchURL: $0.searchURL
            )
        }
        let meta = DesignMeta(
            projectName: workflow.projectSpec?.name ?? "Untitled",
            projectType: workflow.projectSpec?.type ?? "unknown",
            sourceRequestId: requestId?.uuidString ?? "",
            summary: workflow.directorSummary,
            techStack: techStack,
            referenceAnchors: refAnchors
        )

        return DesignDocument(
            meta: meta,
            screens: screens,
            dataModels: models,
            apiEndpoints: apis,
            userFlows: flows,
            crossReferences: crossRefs,
            implementationOrder: implOrder,
            globalStateDesign: globalState.stateEntities.isEmpty ? nil : globalState
        )
    }

    /// Render a DesignDocument to a single Markdown file optimized for AI dev tools.
    static func renderMarkdown(_ doc: DesignDocument) -> String {
        var md = "# \(doc.meta.projectName) — Design Specification\n\n"
        md += "**Type**: \(doc.meta.projectType)  \n"
        md += "**Generated**: \(ISO8601DateFormatter().string(from: doc.meta.generatedAt))  \n"
        md += "**Version**: \(doc.meta.version)\n\n"

        if let ts = doc.meta.techStack, !ts.isEmpty {
            md += "**Tech Stack**: \(ts.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }.joined(separator: " | "))\n\n"
        }

        if !doc.meta.summary.isEmpty {
            md += "## Overview\n\n\(doc.meta.summary)\n\n"
        }

        // Reference Anchors
        if let refs = doc.meta.referenceAnchors, !refs.isEmpty {
            md += "## Reference Anchors\n\n"
            md += "| Category | Product | Aspect | Search |\n"
            md += "|----------|---------|--------|--------|\n"
            for ref in refs {
                let searchLink = ref.searchURL.map { "[\(ref.productName)](\($0))" } ?? "-"
                md += "| \(ref.category) | \(ref.productName) | \(ref.aspect) | \(searchLink) |\n"
            }
            md += "\n> These products define the visual direction. Do NOT use emoji. Follow visual_spec in each screen spec.\n\n---\n\n"
        }

        // Table of Contents
        md += "## Table of Contents\n\n"
        if !doc.screens.isEmpty { md += "- [Screens](#screens) (\(doc.screens.count))\n" }
        if !doc.dataModels.isEmpty { md += "- [Data Models](#data-models) (\(doc.dataModels.count))\n" }
        if !doc.apiEndpoints.isEmpty { md += "- [API Endpoints](#api-endpoints) (\(doc.apiEndpoints.count))\n" }
        if !doc.userFlows.isEmpty { md += "- [User Flows](#user-flows) (\(doc.userFlows.count))\n" }
        if !doc.crossReferences.isEmpty { md += "- [Cross References](#cross-references)\n" }
        md += "- [Implementation Order](#implementation-order)\n\n"

        // Screens
        if !doc.screens.isEmpty {
            md += "---\n\n## Screens\n\n"
            for screen in doc.screens {
                md += renderScreenMarkdown(screen)
            }
        }

        // Data Models
        if !doc.dataModels.isEmpty {
            md += "---\n\n## Data Models\n\n"
            for model in doc.dataModels {
                md += renderDataModelMarkdown(model)
            }
        }

        // API Endpoints
        if !doc.apiEndpoints.isEmpty {
            md += "---\n\n## API Endpoints\n\n"
            for api in doc.apiEndpoints {
                md += renderAPIMarkdown(api)
            }
        }

        // User Flows
        if !doc.userFlows.isEmpty {
            md += "---\n\n## User Flows\n\n"
            for flow in doc.userFlows {
                md += renderUserFlowMarkdown(flow)
            }
        }

        // Cross References
        if !doc.crossReferences.isEmpty {
            md += "---\n\n## Cross References\n\n"
            md += "| Source | Relation | Target |\n|--------|----------|--------|\n"
            for ref in doc.crossReferences {
                let rel = ref.relationType.replacingOccurrences(of: "_", with: " ")
                md += "| [\(ref.sourceId)](#\(ref.sourceId)) | \(rel) | [\(ref.targetId)](#\(ref.targetId)) |\n"
            }
            md += "\n"
        }

        // Implementation Order
        md += "---\n\n## Implementation Order\n\n"
        for (i, group) in doc.implementationOrder.enumerated() {
            let items = group.map { "[\($0)](#\($0))" }.joined(separator: ", ")
            md += "\(i + 1). **Group \(i + 1)**: \(items)\n"
        }
        md += "\n"

        return md
    }

    // MARK: - Internal Types

    private struct ApprovedItem {
        let item: DeliverableItem
        let sectionType: String
        let sectionLabel: String
    }

    // MARK: - Step 1: Filter

    private static func approvedItems(from workflow: DesignWorkflow) -> [ApprovedItem] {
        workflow.deliverables.flatMap { section in
            section.items
                .filter { $0.directorVerdict == .confirmed && $0.status == .completed }
                .map { ApprovedItem(item: $0, sectionType: section.type, sectionLabel: section.label) }
        }
    }

    // MARK: - Step 4: Stable ID Generation

    private static func buildSlugMap(_ items: [ApprovedItem]) -> [UUID: String] {
        var map = [UUID: String]()
        var seen = Set<String>()

        for entry in items {
            let prefix: String
            switch entry.sectionType {
            case "screen-spec": prefix = "screen"
            case "data-model":  prefix = "model"
            case "api-spec":    prefix = "api"
            case "user-flow":   prefix = "flow"
            default:            prefix = "item"
            }

            var slug = "\(prefix)-\(slugify(entry.item.name))"

            // Deduplicate
            if seen.contains(slug) {
                var counter = 2
                while seen.contains("\(slug)-\(counter)") { counter += 1 }
                slug = "\(slug)-\(counter)"
            }

            seen.insert(slug)
            map[entry.item.id] = slug
        }

        return map
    }

    private static func slugify(_ text: String) -> String {
        let lower = text.lowercased()
        // Keep alphanumeric, Korean, and hyphens; replace spaces/underscores with hyphens
        let cleaned = lower
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        // Collapse multiple hyphens
        let components = cleaned.split(separator: "-").filter { !$0.isEmpty }
        let result = components.joined(separator: "-")
        return result.isEmpty ? "unnamed" : String(result.prefix(60))
    }

    // MARK: - Step 3: Normalize (spec dict → typed struct)

    private static func convertScreen(_ entry: ApprovedItem, slugMap: [UUID: String]) -> DesignScreenSpec {
        let spec = entry.item.spec
        let id = slugMap[entry.item.id] ?? "screen-unknown"

        let exitTo = extractStringArray(spec, keys: ["exit_to", "exitTo"])
        let components = extractJSONValueArray(spec, keys: ["components"])
        let interactions = extractJSONValueArray(spec, keys: ["interactions"])
        let states = extractStringDict(spec, keys: ["states"])
        let edgeCases = extractFlatStringArray(spec, keys: ["edge_cases", "edgeCases"])

        let knownKeys: Set<String> = [
            "purpose", "entry_condition", "entryCondition", "exit_to", "exitTo",
            "components", "interactions", "states", "edge_cases", "edgeCases",
            "summary", "suggested_refinements", "suggestedRefinements"
        ]
        let additional = collectAdditionalProperties(spec, excluding: knownKeys)

        return DesignScreenSpec(
            id: id,
            name: entry.item.name,
            purpose: extractString(spec, keys: ["purpose"]),
            entryCondition: extractString(spec, keys: ["entry_condition", "entryCondition"]),
            exitTo: exitTo,
            components: components,
            interactions: interactions,
            states: states,
            edgeCases: edgeCases,
            additionalProperties: additional
        )
    }

    private static func convertDataModel(_ entry: ApprovedItem, slugMap: [UUID: String]) -> DesignDataModelSpec {
        let spec = entry.item.spec
        let id = slugMap[entry.item.id] ?? "model-unknown"

        let fields = extractFields(spec)
        let relationships = extractRelationships(spec)
        let indexes = extractJSONValueArray(spec, keys: ["indexes"])
        let businessRules = extractFlatStringArray(spec, keys: ["business_rules", "businessRules"])

        let knownKeys: Set<String> = [
            "description", "fields", "relationships", "indexes",
            "business_rules", "businessRules", "summary",
            "edge_cases", "edgeCases", "suggested_refinements", "suggestedRefinements"
        ]
        let additional = collectAdditionalProperties(spec, excluding: knownKeys)

        return DesignDataModelSpec(
            id: id,
            name: entry.item.name,
            description: extractString(spec, keys: ["description"]),
            fields: fields,
            relationships: relationships,
            indexes: indexes,
            businessRules: businessRules,
            additionalProperties: additional
        )
    }

    private static func convertAPI(_ entry: ApprovedItem, slugMap: [UUID: String]) -> DesignAPISpec {
        let spec = entry.item.spec
        let id = slugMap[entry.item.id] ?? "api-unknown"

        let parameters = extractParameters(spec)
        let errorResponses = extractErrorResponses(spec)

        let knownKeys: Set<String> = [
            "method", "path", "description", "parameters",
            "request_body", "requestBody", "response",
            "error_responses", "errorResponses", "auth", "summary",
            "edge_cases", "edgeCases", "suggested_refinements", "suggestedRefinements"
        ]
        let additional = collectAdditionalProperties(spec, excluding: knownKeys)

        return DesignAPISpec(
            id: id,
            name: entry.item.name,
            method: extractString(spec, keys: ["method"]),
            path: extractString(spec, keys: ["path"]),
            description: extractString(spec, keys: ["description"]),
            parameters: parameters,
            requestBody: extractJSONValue(spec, keys: ["request_body", "requestBody"]),
            response: extractJSONValue(spec, keys: ["response"]),
            errorResponses: errorResponses,
            auth: extractString(spec, keys: ["auth"]),
            additionalProperties: additional
        )
    }

    private static func convertUserFlow(
        _ entry: ApprovedItem,
        slugMap: [UUID: String],
        allScreens: [DesignScreenSpec]
    ) -> DesignUserFlowSpec {
        let spec = entry.item.spec
        let id = slugMap[entry.item.id] ?? "flow-unknown"

        let steps = extractFlowSteps(spec)
        let decisionPoints = extractDecisionPoints(spec)
        let errorPaths = extractErrorPaths(spec)
        let relatedScreenNames = extractStringArray(spec, keys: ["related_screens", "relatedScreens"])

        // Resolve screen names to slugs where possible
        let screenNameToSlug = Dictionary(
            allScreens.map { ($0.name.lowercased(), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        let resolvedScreens = relatedScreenNames.map { name in
            screenNameToSlug[name.lowercased()] ?? name
        }

        let knownKeys: Set<String> = [
            "trigger", "steps", "decision_points", "decisionPoints",
            "success_outcome", "successOutcome", "error_paths", "errorPaths",
            "related_screens", "relatedScreens", "summary",
            "edge_cases", "edgeCases", "suggested_refinements", "suggestedRefinements"
        ]
        let additional = collectAdditionalProperties(spec, excluding: knownKeys)

        return DesignUserFlowSpec(
            id: id,
            name: entry.item.name,
            trigger: extractString(spec, keys: ["trigger"]),
            steps: steps,
            decisionPoints: decisionPoints,
            successOutcome: extractString(spec, keys: ["success_outcome", "successOutcome"]),
            errorPaths: errorPaths,
            relatedScreens: resolvedScreens,
            relatedAPIs: [],   // inferred from cross-references
            additionalProperties: additional
        )
    }

    // MARK: - Step 5: Cross-References

    private static func buildCrossReferences(
        workflow: DesignWorkflow,
        slugMap: [UUID: String],
        screens: [DesignScreenSpec],
        flows: [DesignUserFlowSpec],
        allSpecIds: Set<String>
    ) -> [DesignCrossReference] {
        var refs = [DesignCrossReference]()
        var seen = Set<String>()  // "sourceId|targetId|relation"

        func addRef(_ source: String, _ target: String, _ relation: String, _ desc: String? = nil) {
            let key = "\(source)|\(target)|\(relation)"
            guard seen.insert(key).inserted else { return }
            refs.append(DesignCrossReference(
                sourceId: source, targetId: target,
                relationType: relation, description: desc
            ))
        }

        // 5a: Explicit edges from workflow
        for edge in workflow.edges {
            guard let sourceSlug = slugMap[edge.sourceId],
                  let targetSlug = slugMap[edge.targetId] else { continue }
            addRef(sourceSlug, targetSlug, edge.relationType)
        }

        // 5b: Inferred from screen exit_to
        let allScreenIds = Set(screens.map(\.id))
        for screen in screens {
            for target in screen.exitTo {
                let targetSlug = matchSlug(target, in: allScreenIds)
                if let resolved = targetSlug {
                    addRef(screen.id, resolved, "navigates_to")
                }
            }
        }

        // 5c: Inferred from flow related screens
        for flow in flows {
            for screenRef in flow.relatedScreens {
                if allSpecIds.contains(screenRef) {
                    addRef(flow.id, screenRef, "uses")
                } else if let resolved = matchSlug(screenRef, in: allScreenIds) {
                    addRef(flow.id, resolved, "uses")
                }
            }
        }

        return refs
    }

    /// Try to match a name reference to an existing slug ID.
    private static func matchSlug(_ reference: String, in slugSet: Set<String>) -> String? {
        // Direct match
        if slugSet.contains(reference) { return reference }

        // Try prefixed match
        let lower = reference.lowercased()
        for slug in slugSet {
            let slugSuffix = slug.drop(while: { $0 != "-" }).dropFirst()  // "screen-login" → "login"
            if slugSuffix.lowercased() == lower { return slug }
            if slug.lowercased() == lower { return slug }
        }

        return nil
    }

    // MARK: - Step 6: Implementation Order

    private static func computeImplementationOrder(
        workflow: DesignWorkflow,
        slugMap: [UUID: String],
        allSpecIds: Set<String>
    ) -> [[String]] {
        let groups = workflow.computeParallelGroups()  // UUID → group number

        // Convert to slug-based groups
        var slugGroups = [Int: [String]]()
        for (uuid, groupNum) in groups {
            guard let slug = slugMap[uuid] else { continue }
            slugGroups[groupNum, default: []].append(slug)
        }

        // Items not in any group (no edges)
        let assignedSlugs = Set(slugGroups.values.flatMap { $0 })
        let unassigned = allSpecIds.subtracting(assignedSlugs)

        // Sort groups by number, add unassigned as first group if any
        var result = [[String]]()
        let sortedGroupNums = slugGroups.keys.sorted()

        if !unassigned.isEmpty && sortedGroupNums.isEmpty {
            // All items are independent — single group
            result.append(Array(unassigned).sorted())
        } else {
            for num in sortedGroupNums {
                var group = slugGroups[num] ?? []
                if num == sortedGroupNums.first {
                    // Merge unassigned into first group
                    group.append(contentsOf: unassigned)
                }
                result.append(group.sorted())
            }
            if sortedGroupNums.isEmpty && !unassigned.isEmpty {
                result.append(Array(unassigned).sorted())
            }
        }

        return result
    }

    // MARK: - Spec Field Extraction Helpers

    private static func extractString(_ spec: [String: AnyCodable], keys: [String]) -> String {
        for key in keys {
            if let val = spec[key]?.stringValue, !val.isEmpty { return val }
        }
        return ""
    }

    private static func extractStringArray(_ spec: [String: AnyCodable], keys: [String]) -> [String] {
        for key in keys {
            if let arr = spec[key]?.arrayValue {
                return arr.compactMap { item -> String? in
                    if let s = item as? String { return s }
                    if let ac = item as? AnyCodable { return ac.stringValue }
                    // Handle dict form like {"screen": "login", "label": "로그인"}
                    if let dict = (item as? AnyCodable)?.dictValue ?? (item as? [String: Any]) {
                        return (dict["screen"] as? String) ?? (dict["name"] as? String) ?? (dict["id"] as? String)
                    }
                    return "\(item)"
                }
            }
        }
        return []
    }

    private static func extractFlatStringArray(_ spec: [String: AnyCodable], keys: [String]) -> [String] {
        for key in keys {
            if let arr = spec[key]?.arrayValue {
                return arr.compactMap { item -> String? in
                    if let s = item as? String { return s }
                    if let ac = item as? AnyCodable { return ac.stringValue }
                    // Dict with primary text key
                    if let dict = (item as? AnyCodable)?.dictValue ?? (item as? [String: Any]) {
                        return (dict["case"] as? String) ?? (dict["scenario"] as? String) ?? (dict["description"] as? String)
                    }
                    return nil
                }
            }
        }
        return []
    }

    private static func extractStringDict(_ spec: [String: AnyCodable], keys: [String]) -> [String: String] {
        for key in keys {
            if let dict = spec[key]?.dictValue {
                return dict.compactMapValues { $0 as? String }
            }
        }
        return [:]
    }

    private static func extractJSONValue(_ spec: [String: AnyCodable], keys: [String]) -> JSONValue? {
        for key in keys {
            if let val = spec[key] {
                return anyToJSONValue(val.value)
            }
        }
        return nil
    }

    private static func extractJSONValueArray(_ spec: [String: AnyCodable], keys: [String]) -> [JSONValue] {
        for key in keys {
            if let arr = spec[key]?.arrayValue {
                return arr.map { anyToJSONValue($0) }
            }
        }
        return []
    }

    private static func extractFields(_ spec: [String: AnyCodable]) -> [DesignFieldSpec] {
        guard let fields = spec["fields"]?.arrayValue else { return [] }
        return fields.compactMap { item -> DesignFieldSpec? in
            guard let dict = (item as? AnyCodable)?.dictValue ?? (item as? [String: Any]) else { return nil }
            let name = (dict["name"] as? String) ?? ""
            guard !name.isEmpty else { return nil }
            return DesignFieldSpec(
                name: name,
                type: (dict["type"] as? String) ?? "String",
                required: (dict["required"] as? Bool) ?? false,
                description: (dict["description"] as? String) ?? ""
            )
        }
    }

    private static func extractRelationships(_ spec: [String: AnyCodable]) -> [DesignRelationshipSpec] {
        guard let rels = spec["relationships"]?.arrayValue else { return [] }
        return rels.compactMap { item -> DesignRelationshipSpec? in
            guard let dict = (item as? AnyCodable)?.dictValue ?? (item as? [String: Any]) else { return nil }
            let entity = (dict["entity"] as? String) ?? (dict["target"] as? String) ?? ""
            guard !entity.isEmpty else { return nil }
            return DesignRelationshipSpec(
                targetEntity: entity,
                type: (dict["type"] as? String) ?? "",
                description: (dict["description"] as? String) ?? ""
            )
        }
    }

    private static func extractParameters(_ spec: [String: AnyCodable]) -> [DesignParameterSpec] {
        guard let params = spec["parameters"]?.arrayValue else { return [] }
        return params.compactMap { item -> DesignParameterSpec? in
            guard let dict = (item as? AnyCodable)?.dictValue ?? (item as? [String: Any]) else { return nil }
            let name = (dict["name"] as? String) ?? ""
            guard !name.isEmpty else { return nil }
            return DesignParameterSpec(
                name: name,
                location: (dict["in"] as? String) ?? (dict["location"] as? String) ?? "query",
                type: (dict["type"] as? String) ?? "String",
                required: (dict["required"] as? Bool) ?? false,
                description: (dict["description"] as? String) ?? ""
            )
        }
    }

    private static func extractErrorResponses(_ spec: [String: AnyCodable]) -> [DesignErrorResponseSpec] {
        let keys = ["error_responses", "errorResponses"]
        for key in keys {
            if let errs = spec[key]?.arrayValue {
                return errs.compactMap { item -> DesignErrorResponseSpec? in
                    guard let dict = (item as? AnyCodable)?.dictValue ?? (item as? [String: Any]) else { return nil }
                    let code = (dict["code"] as? Int) ?? (dict["code"] as? NSNumber)?.intValue ?? 0
                    let message = (dict["message"] as? String) ?? ""
                    guard code > 0 else { return nil }
                    return DesignErrorResponseSpec(code: code, message: message)
                }
            }
        }
        return []
    }

    private static func extractFlowSteps(_ spec: [String: AnyCodable]) -> [DesignFlowStep] {
        guard let steps = spec["steps"]?.arrayValue else { return [] }
        return steps.enumerated().compactMap { (index, item) -> DesignFlowStep? in
            guard let dict = (item as? AnyCodable)?.dictValue ?? (item as? [String: Any]) else { return nil }
            let order = (dict["order"] as? Int) ?? (dict["order"] as? NSNumber)?.intValue ?? (index + 1)
            return DesignFlowStep(
                order: order,
                actor: (dict["actor"] as? String) ?? "",
                action: (dict["action"] as? String) ?? "",
                screenId: (dict["screenId"] as? String) ?? (dict["screen_id"] as? String)
            )
        }
    }

    private static func extractDecisionPoints(_ spec: [String: AnyCodable]) -> [DesignDecisionPoint] {
        let keys = ["decision_points", "decisionPoints"]
        for key in keys {
            if let dps = spec[key]?.arrayValue {
                return dps.compactMap { item -> DesignDecisionPoint? in
                    guard let dict = (item as? AnyCodable)?.dictValue ?? (item as? [String: Any]) else { return nil }
                    return DesignDecisionPoint(
                        condition: (dict["condition"] as? String) ?? "",
                        yes: (dict["yes"] as? String) ?? "",
                        no: (dict["no"] as? String) ?? ""
                    )
                }
            }
        }
        return []
    }

    private static func extractErrorPaths(_ spec: [String: AnyCodable]) -> [DesignErrorPath] {
        let keys = ["error_paths", "errorPaths"]
        for key in keys {
            if let paths = spec[key]?.arrayValue {
                return paths.compactMap { item -> DesignErrorPath? in
                    guard let dict = (item as? AnyCodable)?.dictValue ?? (item as? [String: Any]) else { return nil }
                    let atStep = (dict["at_step"] as? Int) ?? (dict["atStep"] as? Int) ?? (dict["at_step"] as? NSNumber)?.intValue ?? 0
                    return DesignErrorPath(
                        atStep: atStep,
                        error: (dict["error"] as? String) ?? (dict["condition"] as? String) ?? "",
                        handling: (dict["handling"] as? String) ?? (dict["action"] as? String) ?? ""
                    )
                }
            }
        }
        return []
    }

    // MARK: - Additional Properties

    private static func collectAdditionalProperties(
        _ spec: [String: AnyCodable],
        excluding knownKeys: Set<String>
    ) -> [String: JSONValue] {
        var result = [String: JSONValue]()
        for (key, val) in spec where !knownKeys.contains(key) {
            result[key] = anyToJSONValue(val.value)
        }
        return result
    }

    // MARK: - Any → JSONValue conversion

    private static func anyToJSONValue(_ value: Any) -> JSONValue {
        switch value {
        case is NSNull:
            return .null
        case let b as Bool:
            return .bool(b)
        case let n as NSNumber:
            return .number(n.doubleValue)
        case let i as Int:
            return .number(Double(i))
        case let d as Double:
            return .number(d)
        case let s as String:
            return .string(s)
        case let arr as [Any]:
            return .array(arr.map { anyToJSONValue($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { anyToJSONValue($0) })
        case let ac as AnyCodable:
            return anyToJSONValue(ac.value)
        default:
            return .string("\(value)")
        }
    }

    // MARK: - Markdown Rendering Helpers

    private static func renderScreenMarkdown(_ screen: DesignScreenSpec) -> String {
        var md = "### \(screen.id): \(screen.name)\n\n"

        if !screen.purpose.isEmpty { md += "**Purpose**: \(screen.purpose)\n\n" }
        if !screen.entryCondition.isEmpty { md += "**Entry**: \(screen.entryCondition)\n\n" }

        if !screen.exitTo.isEmpty {
            let links = screen.exitTo.map { "[\($0)](#\($0))" }
            md += "**Navigates to**: \(links.joined(separator: ", "))\n\n"
        }

        if !screen.components.isEmpty {
            md += "**Components**:\n\n"
            md += renderJSONComponentTree(screen.components, indent: 0)
            md += "\n"
        }

        if !screen.interactions.isEmpty {
            md += "**Interactions**:\n\n"
            for interaction in screen.interactions {
                if case .object(let dict) = interaction {
                    let trigger = dict["trigger"]?.stringValue ?? ""
                    let action = dict["action"]?.stringValue ?? ""
                    if !trigger.isEmpty { md += "- \(trigger) → \(action)\n" }
                }
            }
            md += "\n"
        }

        if !screen.states.isEmpty {
            md += "**States**:\n\n"
            for (state, desc) in screen.states.sorted(by: { $0.key < $1.key }) {
                md += "- **\(state)**: \(desc)\n"
            }
            md += "\n"
        }

        if !screen.edgeCases.isEmpty {
            md += "**Edge cases**:\n\n"
            for ec in screen.edgeCases { md += "- \(ec)\n" }
            md += "\n"
        }

        return md
    }

    private static func renderDataModelMarkdown(_ model: DesignDataModelSpec) -> String {
        var md = "### \(model.id): \(model.name)\n\n"

        if !model.description.isEmpty { md += "\(model.description)\n\n" }

        if !model.fields.isEmpty {
            md += "**Fields**:\n\n"
            md += "| Name | Type | Required | Description |\n|------|------|----------|-------------|\n"
            for field in model.fields {
                md += "| \(field.name) | \(field.type) | \(field.required ? "Yes" : "No") | \(field.description) |\n"
            }
            md += "\n"
        }

        if !model.relationships.isEmpty {
            md += "**Relationships**:\n\n"
            for rel in model.relationships {
                md += "- → \(rel.targetEntity) (\(rel.type))"
                if !rel.description.isEmpty { md += ": \(rel.description)" }
                md += "\n"
            }
            md += "\n"
        }

        if !model.businessRules.isEmpty {
            md += "**Business rules**:\n\n"
            for rule in model.businessRules { md += "- \(rule)\n" }
            md += "\n"
        }

        return md
    }

    private static func renderAPIMarkdown(_ api: DesignAPISpec) -> String {
        var md = "### \(api.id): \(api.name)\n\n"

        if !api.method.isEmpty && !api.path.isEmpty {
            md += "**Endpoint**: `\(api.method) \(api.path)`\n\n"
        }
        if !api.description.isEmpty { md += "\(api.description)\n\n" }

        if !api.parameters.isEmpty {
            md += "**Parameters**:\n\n"
            md += "| Name | In | Type | Required | Description |\n|------|-----|------|----------|-------------|\n"
            for p in api.parameters {
                md += "| \(p.name) | \(p.location) | \(p.type) | \(p.required ? "Yes" : "No") | \(p.description) |\n"
            }
            md += "\n"
        }

        if let body = api.requestBody {
            md += "**Request body**:\n\n```json\n\(renderJSONValue(body))\n```\n\n"
        }
        if let resp = api.response {
            md += "**Response**:\n\n```json\n\(renderJSONValue(resp))\n```\n\n"
        }

        if !api.errorResponses.isEmpty {
            md += "**Error responses**:\n\n"
            for err in api.errorResponses {
                md += "- `\(err.code)`: \(err.message)\n"
            }
            md += "\n"
        }

        if !api.auth.isEmpty { md += "**Auth**: \(api.auth)\n\n" }

        return md
    }

    private static func renderUserFlowMarkdown(_ flow: DesignUserFlowSpec) -> String {
        var md = "### \(flow.id): \(flow.name)\n\n"

        if !flow.trigger.isEmpty { md += "**Trigger**: \(flow.trigger)\n\n" }

        if !flow.steps.isEmpty {
            md += "**Steps**:\n\n"
            for step in flow.steps {
                var line = "\(step.order). [\(step.actor)] \(step.action)"
                if let screenId = step.screenId { line += " → [\(screenId)](#\(screenId))" }
                md += "\(line)\n"
            }
            md += "\n"
        }

        if !flow.decisionPoints.isEmpty {
            md += "**Decision points**:\n\n"
            for dp in flow.decisionPoints {
                md += "- If \(dp.condition): Yes → \(dp.yes) / No → \(dp.no)\n"
            }
            md += "\n"
        }

        if !flow.successOutcome.isEmpty { md += "**Success**: \(flow.successOutcome)\n\n" }

        if !flow.errorPaths.isEmpty {
            md += "**Error paths**:\n\n"
            for ep in flow.errorPaths {
                md += "- Step \(ep.atStep): \(ep.error) → \(ep.handling)\n"
            }
            md += "\n"
        }

        if !flow.relatedScreens.isEmpty {
            let links = flow.relatedScreens.map { "[\($0)](#\($0))" }
            md += "**Related screens**: \(links.joined(separator: ", "))\n\n"
        }

        return md
    }

    private static func renderJSONComponentTree(_ components: [JSONValue], indent: Int) -> String {
        var md = ""
        let prefix = String(repeating: "  ", count: indent)
        for comp in components {
            guard case .object(let dict) = comp else { continue }
            let name = dict["name"]?.stringValue ?? "?"
            let type = dict["type"]?.stringValue ?? ""
            let role = dict["role"]?.stringValue ?? ""
            md += "\(prefix)- **\(name)** (`\(type)`)"
            if !role.isEmpty { md += " — \(role)" }
            md += "\n"
            if case .array(let children) = dict["children"] {
                md += renderJSONComponentTree(children, indent: indent + 1)
            }
        }
        return md
    }

    private static func renderJSONValue(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    // MARK: - Global State Design Extraction

    /// Extracts app-wide state management design from screen specs and user flows.
    /// - Screens sharing state names → global entities
    /// - Flow steps across screens → state transitions
    /// - Screen → state dependency mapping
    static func extractGlobalStateDesign(
        screens: [DesignScreenSpec],
        flows: [DesignUserFlowSpec]
    ) -> GlobalStateDesign {
        // Step 1: Collect state names per screen
        var stateToScreens: [String: [String]] = [:]  // stateName → [screenId]
        for screen in screens {
            for (stateName, _) in screen.states {
                stateToScreens[stateName, default: []].append(screen.id)
            }
        }

        // Step 2: Build state entities — global if shared across 2+ screens, feature otherwise
        var stateEntities: [StateEntity] = []
        for (stateName, screenIds) in stateToScreens.sorted(by: { $0.key < $1.key }) {
            let type = screenIds.count >= 2 ? "global" : "feature"
            // Collect possible values from all screens that reference this state
            var possibleValues: [String] = []
            for screen in screens where screen.states[stateName] != nil {
                let desc = screen.states[stateName] ?? ""
                if !desc.isEmpty { possibleValues.append(desc) }
            }
            // Check for persistence hints in additionalProperties
            var persistence = "memory"
            for screen in screens where screen.states[stateName] != nil {
                if case .string(let hint) = screen.additionalProperties["state_management"] {
                    persistence = hint
                    break
                }
            }
            stateEntities.append(StateEntity(
                name: stateName, type: type, possibleValues: possibleValues,
                persistenceStrategy: persistence,
                description: "Used by \(screenIds.count) screen(s): \(screenIds.joined(separator: ", "))"
            ))
        }

        // Step 3: Infer state transitions from user flow steps (screen transitions)
        var stateTransitions: [StateTransition] = []
        for flow in flows {
            let sortedSteps = flow.steps.sorted { $0.order < $1.order }
            for i in 0..<(sortedSteps.count - 1) {
                guard let fromScreenId = sortedSteps[i].screenId,
                      let toScreenId = sortedSteps[i + 1].screenId,
                      fromScreenId != toScreenId else { continue }
                let fromScreen = screens.first { $0.id == fromScreenId }
                let toScreen = screens.first { $0.id == toScreenId }
                guard let fromStates = fromScreen?.states, let toStates = toScreen?.states else { continue }
                // If the target screen has states not present in source, infer a transition
                for stateName in toStates.keys where fromStates[stateName] == nil {
                    stateTransitions.append(StateTransition(
                        fromState: fromScreenId,
                        toState: "\(stateName)@\(toScreenId)",
                        trigger: sortedSteps[i + 1].action,
                        sideEffects: []
                    ))
                }
            }
        }

        // Step 4: Build screen-state mapping
        let screenStateMapping: [ScreenStateMapping] = screens.compactMap { screen in
            let required = Array(screen.states.keys).sorted()
            guard !required.isEmpty else { return nil }
            // State effects: states that this screen modifies (screens with exit navigation)
            let effects = screen.exitTo.flatMap { exitScreenId -> [String] in
                guard let target = screens.first(where: { $0.id == exitScreenId }) else { return [] }
                return Array(target.states.keys).filter { !screen.states.keys.contains($0) }
            }
            return ScreenStateMapping(
                screenId: screen.id,
                requiredStates: required,
                stateEffects: Array(Set(effects)).sorted()
            )
        }

        return GlobalStateDesign(
            stateEntities: stateEntities,
            stateTransitions: stateTransitions,
            screenStateMapping: screenStateMapping
        )
    }
}
