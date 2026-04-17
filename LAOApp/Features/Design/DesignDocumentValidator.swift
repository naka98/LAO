import Foundation
import LAODomain

// MARK: - Design Document Validator

/// Validates a DesignDocument for structural correctness before export.
enum DesignDocumentValidator {

    struct Issue: CustomStringConvertible {
        let path: String
        let message: String
        let severity: Severity

        var description: String { "[\(severity)] \(path): \(message)" }
    }

    enum Severity: String { case error, warning }

    static func validate(_ doc: DesignDocument) -> [Issue] {
        var issues = [Issue]()

        // Collect all spec IDs
        var allIds = [String]()
        var idCounts = [String: Int]()

        func checkPrefix(_ id: String, expected: String, path: String) {
            allIds.append(id)
            idCounts[id, default: 0] += 1
            if !id.hasPrefix(expected) {
                issues.append(Issue(
                    path: path, message: "ID '\(id)' should start with '\(expected)'", severity: .error
                ))
            }
        }

        // Validate ID prefixes
        for (i, s) in doc.screens.enumerated() {
            checkPrefix(s.id, expected: "screen-", path: "screens[\(i)]")
        }
        for (i, m) in doc.dataModels.enumerated() {
            checkPrefix(m.id, expected: "model-", path: "dataModels[\(i)]")
        }
        for (i, a) in doc.apiEndpoints.enumerated() {
            checkPrefix(a.id, expected: "api-", path: "apiEndpoints[\(i)]")
        }
        for (i, f) in doc.userFlows.enumerated() {
            checkPrefix(f.id, expected: "flow-", path: "userFlows[\(i)]")
        }

        // Duplicate IDs
        let allIdSet = Set(allIds)
        for (id, count) in idCounts where count > 1 {
            issues.append(Issue(
                path: "ids", message: "Duplicate ID '\(id)' appears \(count) times", severity: .error
            ))
        }

        // Cross-reference integrity
        let allowedRelations: Set<String> = ["navigates_to", "depends_on", "uses", "calls", "refines", "replaces"]
        for (i, ref) in doc.crossReferences.enumerated() {
            if !allIdSet.contains(ref.sourceId) {
                issues.append(Issue(
                    path: "crossReferences[\(i)]",
                    message: "sourceId '\(ref.sourceId)' not found in document",
                    severity: .error
                ))
            }
            if !allIdSet.contains(ref.targetId) {
                issues.append(Issue(
                    path: "crossReferences[\(i)]",
                    message: "targetId '\(ref.targetId)' not found in document",
                    severity: .error
                ))
            }
            if !allowedRelations.contains(ref.relationType) {
                issues.append(Issue(
                    path: "crossReferences[\(i)]",
                    message: "Unknown relationType '\(ref.relationType)'",
                    severity: .warning
                ))
            }
        }

        // Implementation order references
        for (gi, group) in doc.implementationOrder.enumerated() {
            for id in group {
                if !allIdSet.contains(id) {
                    issues.append(Issue(
                        path: "implementationOrder[\(gi)]",
                        message: "ID '\(id)' not found in document",
                        severity: .error
                    ))
                }
            }
        }

        // Meta warnings
        if doc.meta.projectName.isEmpty || doc.meta.projectName == "Untitled" {
            issues.append(Issue(
                path: "meta.projectName",
                message: "Project name is empty or default",
                severity: .warning
            ))
        }

        return issues
    }
}
