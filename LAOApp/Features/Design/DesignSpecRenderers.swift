import SwiftUI
import LAODomain

// MARK: - Structured Spec Renderers (extracted from DesignWorkflowView)

extension DesignWorkflowView {

    /// Type-aware spec rendering — presents spec data in a human-readable structure based on section type.
    @ViewBuilder func structuredSpecView(spec: [String: AnyCodable], sectionType: String) -> some View {
        switch sectionType {
        case "screen-spec":
            screenSpecView(spec)
        case "api-spec":
            apiSpecView(spec)
        case "data-model":
            dataModelSpecView(spec)
        case "user-flow":
            userFlowSpecView(spec)
        default:
            specView(spec)
        }
    }

    // MARK: screen-spec renderer

    func screenSpecView(_ spec: [String: AnyCodable]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Purpose
            if let purpose = spec["purpose"]?.stringValue {
                specSectionBlock(title: lang.design.specPurpose, icon: "target") {
                    Text(purpose).font(AppTheme.Typography.bodySecondary).textSelection(.enabled)
                }
            }
            // Entry condition
            if let entry = spec["entry_condition"]?.stringValue {
                specSectionBlock(title: lang.design.specEntry, icon: "arrow.right.to.line") {
                    Text(entry).font(AppTheme.Typography.bodySecondary).textSelection(.enabled)
                }
            }
            // Exit targets
            if let exitTo = spec["exit_to"] {
                specSectionBlock(title: lang.design.specExitTo, icon: "arrow.right.square") {
                    if let arr = exitTo.arrayValue {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(arr.enumerated()), id: \.offset) { _, dest in
                                Text("· \(readableText(dest))")
                                    .font(AppTheme.Typography.bodySecondary)
                                    .foregroundStyle(theme.foregroundPrimary)
                                    .textSelection(.enabled)
                            }
                        }
                    } else if let s = exitTo.stringValue {
                        Text(s).font(AppTheme.Typography.bodySecondary).textSelection(.enabled)
                    }
                }
            }
            // Components — hierarchy tree if children present, flat table otherwise
            if let comps = spec["components"]?.arrayValue, !comps.isEmpty {
                let hasChildren = comps.contains { ($0 as? [String: Any])?["children"] != nil }
                specSectionBlock(title: lang.design.specComponents, icon: "square.stack") {
                    if hasChildren {
                        // Tree view for hierarchical components
                        VStack(alignment: .leading, spacing: 1) {
                            componentTreeView(comps, depth: 0)
                        }
                    } else {
                        // Role-centric component list — role is primary label, name/type are secondary
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(comps.enumerated()), id: \.offset) { _, comp in
                                if let dict = comp as? [String: Any] {
                                    let name = dict["name"] as? String ?? "-"
                                    let type = (dict["type"] as? String ?? "").lowercased()
                                    let role = dict["role"] as? String
                                    HStack(spacing: 6) {
                                        Image(systemName: inspectorComponentIcon(for: type))
                                            .font(.caption2)
                                            .foregroundStyle(theme.accentPrimary)
                                            .frame(width: 16)
                                        VStack(alignment: .leading, spacing: 1) {
                                            if let role, !role.isEmpty {
                                                Text(role).font(AppTheme.Typography.bodySecondary.weight(.medium))
                                                Text(name).font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundTertiary)
                                            } else {
                                                Text(name).font(AppTheme.Typography.bodySecondary.weight(.medium))
                                            }
                                        }
                                        Spacer()
                                        Text(dict["type"] as? String ?? "")
                                            .font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundTertiary)
                                    }
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(theme.surfaceSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                        }
                    }
                }
            }
            // Interactions — rendered as readable sentence cards
            if let interactions = spec["interactions"]?.arrayValue, !interactions.isEmpty {
                specSectionBlock(title: lang.design.specInteractions, icon: "hand.tap") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(interactions.enumerated()), id: \.offset) { _, inter in
                            if let dict = inter as? [String: Any] {
                                let trigger = dict["trigger"] as? String ?? "?"
                                let action = dict["action"] as? String ?? "?"
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "hand.tap")
                                        .font(.system(size: 10)).foregroundStyle(.blue.opacity(0.6))
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(trigger).font(AppTheme.Typography.bodySecondary.weight(.semibold))
                                        Text(action).font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary)
                                    }
                                }
                                .padding(.vertical, 4).padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(theme.surfaceSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                }
            }
            // States — color-coded visual cards
            if let states = spec["states"]?.dictValue, !states.isEmpty {
                specSectionBlock(title: lang.design.specStates, icon: "switch.2") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(states.keys.sorted(), id: \.self) { state in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(ScreenCardHelper.stateColor(state))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 3)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(state).font(AppTheme.Typography.bodySecondary.weight(.semibold))
                                    if let val = states[state] {
                                        Text(readableText(val))
                                            .font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary)
                                    }
                                }
                            }
                            .padding(.vertical, 3).padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ScreenCardHelper.stateColor(state).opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
            specAnnotationSection(spec, key: "edge_cases", title: lang.design.specEdgeCases,
                icon: "exclamationmark.triangle", accentColor: theme.warningAccent,
                primaryKeys: ["case", "scenario"], secondaryKeys: ["handling", "response"])
            specAnnotationSection(spec, key: "suggested_refinements", title: lang.design.specSuggestedRefinements,
                icon: "lightbulb", accentColor: .orange,
                primaryKeys: ["area", "field"], secondaryKeys: ["suggestion", "description"])
            // Remaining keys not handled above
            let handledKeys: Set<String> = ["purpose", "entry_condition", "exit_to", "components", "interactions", "states", "edge_cases", "suggested_refinements", "summary"]
            let remaining = spec.filter { !handledKeys.contains($0.key) }
            if !remaining.isEmpty {
                specView(remaining)
            }
        }
    }

    // MARK: api-spec renderer

    func apiSpecView(_ spec: [String: AnyCodable]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Method + Path (support "endpoint" as alias for "path")
            HStack(spacing: 8) {
                if let method = spec["method"]?.stringValue {
                    Text(method.uppercased())
                        .font(.caption.weight(.bold).monospaced())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(apiMethodColor(method))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if let path = spec["path"]?.stringValue ?? spec["endpoint"]?.stringValue {
                    Text(path).font(.caption.monospaced()).textSelection(.enabled)
                }
                Spacer()
            }
            // Description
            if let desc = spec["description"]?.stringValue {
                Text(desc).font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary).textSelection(.enabled)
            }
            // Auth
            if let auth = spec["auth"]?.stringValue {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill").font(AppTheme.Typography.iconMedium)
                    Text(auth).font(AppTheme.Typography.bodySecondary)
                }.foregroundStyle(theme.warningAccent)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(theme.warningAccent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            // Parameters (query/path/header params)
            if let params = spec["parameters"]?.arrayValue, !params.isEmpty {
                specSectionBlock(title: lang.design.specParameters, icon: "list.bullet.clipboard") {
                    VStack(alignment: .leading, spacing: 2) {
                        // Header row
                        HStack(spacing: 0) {
                            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                            Text("In").frame(width: 50, alignment: .leading)
                            Text("Type").frame(width: 60, alignment: .leading)
                            Text("Req").frame(width: 30, alignment: .center)
                            Text("Description").frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.foregroundTertiary)
                            .padding(.horizontal, 4).padding(.bottom, 2)
                        ForEach(Array(params.enumerated()), id: \.offset) { _, param in
                            if let dict = param as? [String: Any] {
                                HStack(spacing: 0) {
                                    Text(dict["name"] as? String ?? "-")
                                        .font(.caption2.monospaced())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(dict["in"] as? String ?? "-")
                                        .font(.caption2)
                                        .foregroundStyle(theme.foregroundTertiary)
                                        .frame(width: 50, alignment: .leading)
                                    Text(dict["type"] as? String ?? "-")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(theme.accentPrimary)
                                        .frame(width: 60, alignment: .leading)
                                    let req = dict["required"] as? Bool ?? false
                                    Image(systemName: req ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(req ? theme.positiveAccent : theme.foregroundTertiary)
                                        .frame(width: 30, alignment: .center)
                                    Text(dict["description"] as? String ?? "")
                                        .font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.padding(.horizontal, 4).padding(.vertical, 2)
                                    .background(theme.surfaceSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                            }
                        }
                    }
                }
            }
            // Request body
            if let reqBody = spec["request_body"] {
                specSectionBlock(title: lang.design.specRequestBody, icon: "arrow.up.doc") {
                    specFieldsOrJSON(reqBody)
                }
            }
            // Response
            if let response = spec["response"] {
                specSectionBlock(title: lang.design.specResponse, icon: "arrow.down.doc") {
                    specFieldsOrJSON(response)
                }
            }
            // Error responses
            if let errors = spec["error_responses"]?.arrayValue, !errors.isEmpty {
                specSectionBlock(title: lang.design.specErrorResponses, icon: "exclamationmark.triangle") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(errors.enumerated()), id: \.offset) { _, err in
                            if let dict = err as? [String: Any] {
                                HStack(alignment: .top, spacing: 6) {
                                    if let code = dict["status"] ?? dict["code"] {
                                        Text(readableText(code))
                                            .font(.caption2.monospaced().weight(.medium))
                                            .foregroundStyle(theme.warningAccent)
                                    }
                                    Text(dict["description"] as? String ?? dict["message"] as? String ?? "-")
                                        .font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary)
                                }
                            } else {
                                Text("• \(readableText(err))").font(AppTheme.Typography.bodySecondary)
                            }
                        }
                    }
                }
            }
            specAnnotationSection(spec, key: "edge_cases", title: lang.design.specEdgeCases,
                icon: "exclamationmark.triangle", accentColor: theme.warningAccent,
                primaryKeys: ["case", "scenario"], secondaryKeys: ["handling", "response"])
            specAnnotationSection(spec, key: "suggested_refinements", title: lang.design.specSuggestedRefinements,
                icon: "lightbulb", accentColor: .orange,
                primaryKeys: ["area", "field"], secondaryKeys: ["suggestion", "description"])
            // Remaining keys
            let handledKeys: Set<String> = ["method", "path", "endpoint", "description", "auth", "parameters", "request_body", "response", "error_responses", "edge_cases", "suggested_refinements", "summary"]
            let remaining = spec.filter { !handledKeys.contains($0.key) }
            if !remaining.isEmpty { specView(remaining) }
        }
    }

    // MARK: data-model renderer

    func dataModelSpecView(_ spec: [String: AnyCodable]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Description
            if let desc = spec["description"]?.stringValue {
                Text(desc).font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary).textSelection(.enabled)
            }
            // Fields table
            if let fields = spec["fields"]?.arrayValue, !fields.isEmpty {
                specSectionBlock(title: lang.design.specFields, icon: "list.bullet.rectangle") {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 0) {
                            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Type").frame(width: 70, alignment: .leading)
                            Text("Req").frame(width: 30, alignment: .center)
                            Text("Description").frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.foregroundTertiary)
                            .padding(.horizontal, 4).padding(.bottom, 2)
                        ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                            if let dict = field as? [String: Any] {
                                HStack(spacing: 0) {
                                    Text(dict["name"] as? String ?? "-")
                                        .font(.caption2.monospaced())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(dict["type"] as? String ?? "-")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(theme.accentPrimary)
                                        .frame(width: 70, alignment: .leading)
                                    let req = dict["required"] as? Bool ?? false
                                    Image(systemName: req ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(req ? theme.positiveAccent : theme.foregroundTertiary)
                                        .frame(width: 30, alignment: .center)
                                    Text(dict["description"] as? String ?? "")
                                        .font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.padding(.horizontal, 4).padding(.vertical, 2)
                                    .background(theme.surfaceSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                            }
                        }
                    }
                }
            }
            // Relationships
            if let rels = spec["relationships"]?.arrayValue, !rels.isEmpty {
                specSectionBlock(title: lang.design.specRelationships, icon: "arrow.triangle.branch") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(rels.enumerated()), id: \.offset) { _, rel in
                            if let dict = rel as? [String: Any] {
                                HStack(spacing: 6) {
                                    Text(dict["entity"] as? String ?? "?")
                                        .font(AppTheme.Typography.bodySecondary.weight(.medium))
                                    Text(dict["type"] as? String ?? "?")
                                        .font(.caption2.monospaced())
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(theme.accentPrimary.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                    Text(dict["description"] as? String ?? "")
                                        .font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary)
                                }
                            }
                        }
                    }
                }
            }
            // Indexes
            if let indexes = spec["indexes"]?.arrayValue, !indexes.isEmpty {
                specSectionBlock(title: lang.design.specIndexes, icon: "tablecells") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(indexes.enumerated()), id: \.offset) { _, idx in
                            if let dict = idx as? [String: Any] {
                                HStack(spacing: 6) {
                                    if let fields = dict["fields"] as? [String] {
                                        Text(fields.joined(separator: ", "))
                                            .font(.caption2.monospaced())
                                    }
                                    if let unique = dict["unique"] as? Bool, unique {
                                        Text("UNIQUE").font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(theme.warningAccent)
                                            .padding(.horizontal, 4).padding(.vertical, 1)
                                            .background(theme.warningAccent.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 2))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // Business rules
            if let rules = spec["business_rules"]?.arrayValue, !rules.isEmpty {
                specSectionBlock(title: lang.design.specBusinessRules, icon: "checklist") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                            HStack(alignment: .top, spacing: 4) {
                                Text("•").font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundMuted)
                                Text(readableText(rule)).font(AppTheme.Typography.bodySecondary).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            specAnnotationSection(spec, key: "edge_cases", title: lang.design.specEdgeCases,
                icon: "exclamationmark.triangle", accentColor: theme.warningAccent,
                primaryKeys: ["case", "scenario"], secondaryKeys: ["handling", "response"])
            specAnnotationSection(spec, key: "suggested_refinements", title: lang.design.specSuggestedRefinements,
                icon: "lightbulb", accentColor: .orange,
                primaryKeys: ["area", "field"], secondaryKeys: ["suggestion", "description"])
            // Remaining
            let handledKeys: Set<String> = ["description", "fields", "relationships", "indexes", "business_rules", "edge_cases", "suggested_refinements", "summary"]
            let remaining = spec.filter { !handledKeys.contains($0.key) }
            if !remaining.isEmpty { specView(remaining) }
        }
    }

    // MARK: user-flow renderer

    func userFlowSpecView(_ spec: [String: AnyCodable]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Trigger
            if let trigger = spec["trigger"]?.stringValue {
                specSectionBlock(title: lang.design.specTrigger, icon: "bolt.fill") {
                    Text(trigger).font(AppTheme.Typography.bodySecondary).textSelection(.enabled)
                }
            }
            // Steps
            if let steps = spec["steps"]?.arrayValue, !steps.isEmpty {
                specSectionBlock(title: lang.design.specSteps, icon: "list.number") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(i + 1)")
                                    .font(.caption2.weight(.bold).monospaced())
                                    .foregroundStyle(theme.accentPrimary)
                                    .frame(width: 16, alignment: .trailing)
                                Text(readableText(step)).font(AppTheme.Typography.bodySecondary).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            // Decision points
            if let decisions = spec["decision_points"]?.arrayValue, !decisions.isEmpty {
                specSectionBlock(title: lang.design.specDecisionPoints, icon: "arrow.triangle.branch") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(decisions.enumerated()), id: \.offset) { _, dec in
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "rhombus.fill").font(AppTheme.Typography.iconSmall).foregroundStyle(theme.warningAccent)
                                Text(readableText(dec)).font(AppTheme.Typography.bodySecondary).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            // Success outcome
            if let success = spec["success_outcome"]?.stringValue {
                specSectionBlock(title: lang.design.specSuccessOutcome, icon: "checkmark.circle") {
                    Text(success).font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.positiveAccent).textSelection(.enabled)
                }
            }
            // Error paths
            if let errors = spec["error_paths"]?.arrayValue, !errors.isEmpty {
                specSectionBlock(title: lang.design.specErrorPaths, icon: "exclamationmark.triangle") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(errors.enumerated()), id: \.offset) { _, err in
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(theme.warningAccent)
                                Text(readableText(err)).font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary)
                            }
                        }
                    }
                }
            }
            // Related screens
            if let screens = spec["related_screens"]?.arrayValue, !screens.isEmpty {
                specSectionBlock(title: lang.design.specRelatedScreens, icon: "rectangle.on.rectangle") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(screens.enumerated()), id: \.offset) { _, screen in
                            Text("· \(readableText(screen))")
                                .font(AppTheme.Typography.bodySecondary)
                                .foregroundStyle(theme.foregroundPrimary)
                        }
                    }
                }
            }
            specAnnotationSection(spec, key: "edge_cases", title: lang.design.specEdgeCases,
                icon: "exclamationmark.triangle", accentColor: theme.warningAccent,
                primaryKeys: ["case", "scenario"], secondaryKeys: ["handling", "response"])
            specAnnotationSection(spec, key: "suggested_refinements", title: lang.design.specSuggestedRefinements,
                icon: "lightbulb", accentColor: .orange,
                primaryKeys: ["area", "field"], secondaryKeys: ["suggestion", "description"])
            // Remaining
            let handledKeys: Set<String> = ["trigger", "steps", "decision_points", "success_outcome", "error_paths", "related_screens", "edge_cases", "suggested_refinements", "summary"]
            let remaining = spec.filter { !handledKeys.contains($0.key) }
            if !remaining.isEmpty { specView(remaining) }
        }
    }

    // MARK: - Spec Renderer Helpers

    /// Titled section block for structured spec display.
    func specSectionBlock<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(theme.accentPrimary)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(theme.accentPrimary)
            }
            content()
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
    }

    /// Tree renderer for hierarchical components (screen-spec).
    func componentTreeView(_ components: [Any], depth: Int) -> some View {
        let flat = flattenComponentTree(components, depth: depth)
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(flat.enumerated()), id: \.offset) { _, entry in
                let d = entry.depth
                let dict = entry.dict
                let isLast = entry.isLastSibling
                let name = dict["name"] as? String ?? "?"
                let type = dict["type"] as? String ?? ""
                let role = dict["role"] as? String ?? ""
                let indent = String(repeating: "  ", count: d)
                let branch = d > 0 ? (isLast ? "└ " : "├ ") : ""
                HStack(spacing: 4) {
                    Text("\(indent)\(branch)\(name)")
                        .font(.caption2.monospaced())
                    if !type.isEmpty {
                        Text(type)
                            .font(.caption2.monospaced())
                            .foregroundStyle(theme.accentPrimary)
                    }
                    if !role.isEmpty {
                        Text("— \(role)")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(theme.foregroundSecondary)
                    }
                }
                .padding(.horizontal, 4).padding(.vertical, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Flat entry for component tree rendering.
    struct ComponentTreeEntry {
        let depth: Int
        let dict: [String: Any]
        let isLastSibling: Bool
    }

    /// Recursively flattens hierarchical components into a list with depth and last-sibling info.
    func flattenComponentTree(_ components: [Any], depth: Int) -> [ComponentTreeEntry] {
        var result: [ComponentTreeEntry] = []
        let dicts = components.compactMap { $0 as? [String: Any] }
        for (i, dict) in dicts.enumerated() {
            let isLast = i == dicts.count - 1
            result.append(ComponentTreeEntry(depth: depth, dict: dict, isLastSibling: isLast))
            if let children = dict["children"] as? [[String: Any]] {
                result.append(contentsOf: flattenComponentTree(children, depth: depth + 1))
            }
        }
        return result
    }

    /// Renders an AnyCodable value as a fields list (if array of dicts) or pretty-printed JSON.
    @ViewBuilder func specFieldsOrJSON(_ value: AnyCodable) -> some View {
        if let arr = value.arrayValue {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(arr.enumerated()), id: \.offset) { _, el in
                    if let dict = el as? [String: Any] {
                        HStack(spacing: 6) {
                            Text(dict["name"] as? String ?? dict["field"] as? String ?? "-")
                                .font(.caption2.monospaced().weight(.medium))
                            if let type = dict["type"] as? String {
                                Text(type).font(.caption2.monospaced()).foregroundStyle(theme.accentPrimary)
                            }
                            if let desc = dict["description"] as? String {
                                Text(desc).font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundSecondary)
                            }
                        }
                    } else {
                        Text("• \(readableText(el))").font(AppTheme.Typography.caption)
                    }
                }
            }
        } else if let jsonStr = value.toJSONString() {
            let lines = jsonStr.components(separatedBy: "\n")
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Color for HTTP method badges.
    func apiMethodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET":    return .blue
        case "POST":   return .green
        case "PUT":    return .orange
        case "PATCH":  return .orange
        case "DELETE": return .red
        default:       return .secondary
        }
    }

    /// Icon for component type — mirrors GraphNodeViews componentIcon logic.
    func inspectorComponentIcon(for type: String) -> String {
        if type.contains("textfield") || type.contains("search") { return "magnifyingglass" }
        if type.contains("securefield") { return "lock" }
        if type.contains("button") { return "hand.tap" }
        if type.contains("image") { return "photo" }
        if type.contains("map") { return "map" }
        if type.contains("list") || type.contains("scroll") || type.contains("table") { return "list.bullet" }
        if type.contains("form") { return "doc.plaintext" }
        if type.contains("text") || type.contains("label") { return "textformat" }
        if type.contains("navigationbar") || type.contains("navbar") { return "menubar.rectangle" }
        if type.contains("tabbar") || type.contains("tabview") { return "rectangle.split.3x1" }
        if type.contains("toggle") || type.contains("switch") { return "switch.2" }
        if type.contains("picker") || type.contains("select") { return "chevron.up.chevron.down" }
        return "square"
    }

    // MARK: - Shared spec annotation renderer (edge_cases, suggested_refinements, etc.)

    /// Generic renderer for spec annotation arrays like edge_cases and suggested_refinements.
    @ViewBuilder func specAnnotationSection(
        _ spec: [String: AnyCodable],
        key: String,
        title: String,
        icon: String,
        accentColor: Color,
        primaryKeys: [String],
        secondaryKeys: [String]
    ) -> some View {
        if let items = spec[key]?.arrayValue, !items.isEmpty {
            specSectionBlock(title: title, icon: icon) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        if let dict = item as? [String: Any] {
                            let primary = primaryKeys.lazy.compactMap { dict[$0] as? String }.first ?? ""
                            let secondary = secondaryKeys.lazy.compactMap { dict[$0] as? String }.first ?? ""
                            VStack(alignment: .leading, spacing: 3) {
                                if !primary.isEmpty {
                                    HStack(alignment: .top, spacing: 5) {
                                        Image(systemName: icon)
                                            .font(.system(size: 10))
                                            .foregroundStyle(accentColor)
                                        Text(primary)
                                            .font(AppTheme.Typography.bodySecondary.weight(.semibold))
                                    }
                                }
                                if !secondary.isEmpty {
                                    Text(secondary)
                                        .font(AppTheme.Typography.bodySecondary)
                                        .foregroundStyle(theme.foregroundPrimary)
                                }
                            }
                            .padding(.vertical, 5).padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(accentColor.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            HStack(alignment: .top, spacing: 5) {
                                Image(systemName: icon)
                                    .font(.system(size: 10))
                                    .foregroundStyle(accentColor)
                                Text(readableText(item))
                                    .font(AppTheme.Typography.bodySecondary)
                            }
                            .padding(.vertical, 5).padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(accentColor.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
        }
    }

    /// Extracts human-readable text from an `Any` value.
    func readableText(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let n = value as? Int { return "\(n)" }
        if let n = value as? Double { return "\(n)" }
        if let b = value as? Bool { return b ? "true" : "false" }
        if let dict = value as? [String: Any] {
            let nameVal = dict["name"] as? String
            let descVal = dict["description"] as? String ?? dict["desc"] as? String
            let titleVal = dict["title"] as? String ?? dict["label"] as? String
            if let name = nameVal, let desc = descVal {
                return "\(name) — \(desc)"
            }
            if let title = titleVal { return title }
            if let name = nameVal { return name }
            if let desc = descVal { return desc }
            if let id = dict["id"] as? String { return id }
            if dict.count == 1, let (k, v) = dict.first {
                return "\(k): \(readableText(v))"
            }
        }
        return "\(value)"
    }

    @ViewBuilder func specView(_ spec: [String: AnyCodable]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(spec.keys.sorted(), id: \.self) { key in
                specRow(key: key, value: spec[key]!)
            }
        }
    }

    func specRow(key: String, value: AnyCodable) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key).font(AppTheme.Typography.bodySecondary.weight(.semibold)).foregroundStyle(theme.accentPrimary)
            if let s = value.stringValue { Text(s).font(AppTheme.Typography.bodySecondary).textSelection(.enabled) }
            else if let i = value.intValue { Text("\(i)").font(AppTheme.Typography.bodySecondary.monospaced()) }
            else if let b = value.boolValue { Text(b ? "true" : "false").font(AppTheme.Typography.bodySecondary.monospaced()) }
            else if let arr = value.arrayValue {
                ForEach(Array(arr.enumerated()), id: \.offset) { _, el in
                    HStack(alignment: .top, spacing: 4) {
                        Text("•").font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundMuted)
                        Text(readableText(el)).font(AppTheme.Typography.bodySecondary)
                    }
                }
            } else if let jsonStr = value.toJSONString() {
                let lines = jsonStr.components(separatedBy: "\n")
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
    }
}
