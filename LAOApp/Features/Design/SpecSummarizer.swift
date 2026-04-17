import Foundation

/// Extracts natural-language summaries from DeliverableItem.spec dictionaries.
/// Pure deterministic logic — no LLM calls. Used by inspector context cards and canvas node cards
/// to show human-readable descriptions instead of raw counts.
enum SpecSummarizer {

    // MARK: - Screen Spec

    /// Component names from screen spec: "이메일 입력, 비밀번호 입력, 로그인 버튼"
    static func componentNames(_ spec: [String: AnyCodable], max: Int = 4) -> String {
        guard let components = spec["components"]?.arrayValue else { return "" }
        let names = components.compactMap { item -> String? in
            guard let dict = item as? [String: Any] else { return nil }
            return dict["name"] as? String
        }.filter { !$0.isEmpty }
        return joinedWithOverflow(names, max: max)
    }

    /// Interaction descriptions: "로그인 버튼 탭 → 인증 처리"
    static func interactionDescriptions(_ spec: [String: AnyCodable], max: Int = 3) -> String {
        guard let interactions = spec["interactions"]?.arrayValue else { return "" }
        let descriptions = interactions.compactMap { item -> String? in
            guard let dict = item as? [String: Any] else { return nil }
            let trigger = dict["trigger"] as? String
            let action = dict["action"] as? String
            if let t = trigger, let a = action, !t.isEmpty, !a.isEmpty {
                return "\(t) → \(a)"
            }
            return trigger ?? action
        }.filter { !$0.isEmpty }
        return joinedWithOverflow(descriptions, max: max, separator: "\n")
    }

    /// State names: "기본, 로딩 중, 오류"
    static func stateNames(_ spec: [String: AnyCodable]) -> String {
        if let dict = spec["states"]?.dictValue {
            let names = dict.keys.sorted()
            return joinedWithOverflow(names, max: 5)
        }
        if let arr = spec["states"]?.arrayValue {
            let names = arr.compactMap { item -> String? in
                if let dict = item as? [String: Any] { return dict["name"] as? String }
                return item as? String
            }
            return joinedWithOverflow(names, max: 5)
        }
        return ""
    }

    // MARK: - Data Model Spec

    /// Business summary: "사용자 정보 저장 — 이메일, 비밀번호, 프로필"
    static func dataModelSummary(_ spec: [String: AnyCodable]) -> String {
        let fieldNames = extractFieldNames(spec)
        let desc = spec["description"]?.stringValue ?? ""
        if desc.isEmpty && fieldNames.isEmpty { return "" }
        if desc.isEmpty { return joinedWithOverflow(fieldNames, max: 5) }
        if fieldNames.isEmpty { return desc }
        return "\(desc) — \(joinedWithOverflow(fieldNames, max: 4))"
    }

    /// Relationship target names from data-model spec.
    static func relationshipTargets(_ spec: [String: AnyCodable]) -> String {
        guard let rels = spec["relationships"]?.arrayValue else { return "" }
        let targets = rels.compactMap { item -> String? in
            guard let dict = item as? [String: Any] else { return nil }
            return (dict["entity"] as? String) ?? (dict["target"] as? String) ?? (dict["name"] as? String)
        }.filter { !$0.isEmpty }
        return joinedWithOverflow(targets, max: 4)
    }

    // MARK: - API Spec

    /// Business description. Falls back to method+path if no description.
    static func apiSummary(_ spec: [String: AnyCodable]) -> String {
        if let desc = spec["description"]?.stringValue, !desc.isEmpty { return desc }
        let method = spec["method"]?.stringValue?.uppercased() ?? ""
        let path = spec["path"]?.stringValue ?? spec["endpoint"]?.stringValue ?? ""
        if method.isEmpty && path.isEmpty { return "" }
        return "\(method) \(path)".trimmingCharacters(in: .whitespaces)
    }

    // MARK: - User Flow Spec

    /// Step narrative: "1. 이메일 입력\n2. 비밀번호 입력\n3. 로그인 탭"
    static func flowNarrative(_ spec: [String: AnyCodable], max: Int = 5) -> String {
        guard let steps = spec["steps"]?.arrayValue, !steps.isEmpty else { return "" }
        var lines: [String] = []
        for (idx, step) in steps.prefix(max).enumerated() {
            if let dict = step as? [String: Any], let action = dict["action"] as? String, !action.isEmpty {
                lines.append("\(idx + 1). \(action)")
            }
        }
        if steps.count > max {
            lines.append("+\(steps.count - max)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Universal

    /// One-line business label for any section type. Used by canvas node cards.
    static func businessLabel(sectionType: String, spec: [String: AnyCodable]) -> String {
        switch sectionType {
        case "screen-spec":
            return spec["purpose"]?.stringValue ?? ""
        case "data-model":
            return spec["description"]?.stringValue ?? joinedWithOverflow(extractFieldNames(spec), max: 3)
        case "api-spec":
            return apiSummary(spec)
        case "user-flow":
            return spec["trigger"]?.stringValue ?? ""
        default:
            return spec["description"]?.stringValue ?? ""
        }
    }

    // MARK: - Helpers

    private static func extractFieldNames(_ spec: [String: AnyCodable]) -> [String] {
        guard let fields = spec["fields"]?.arrayValue else { return [] }
        return fields.compactMap { item -> String? in
            guard let dict = item as? [String: Any] else { return nil }
            return dict["name"] as? String
        }.filter { !$0.isEmpty }
    }

    private static func joinedWithOverflow(_ items: [String], max: Int, separator: String = ", ") -> String {
        guard !items.isEmpty else { return "" }
        let shown = Array(items.prefix(max))
        let overflow = items.count - max
        if overflow > 0 {
            return shown.joined(separator: separator) + " " + AppLanguage.currentStrings.design.moreItemsFormat(overflow)
        }
        return shown.joined(separator: separator)
    }
}
