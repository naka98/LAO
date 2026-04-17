import Foundation
import LAODomain

// MARK: - TestDocumentConverter

/// Derives test scenarios from a completed DesignDocument.
/// Pure algorithmic derivation — no LLM calls.
enum TestDocumentConverter {

    // MARK: - Conversion

    static func convert(_ doc: DesignDocument) -> TestScenariosDocument {
        let meta = DocumentMeta(
            documentType: "test",
            projectName: doc.meta.projectName,
            sourceRequestId: doc.meta.sourceRequestId
        )

        var scenarios: [TestScenario] = []
        var idCounter = 0

        func nextId(_ prefix: String) -> String {
            idCounter += 1
            return "\(prefix)-\(idCounter)"
        }

        // 1. User flows → E2E test scenarios
        for flow in doc.userFlows {
            let steps = flow.steps.sorted { $0.order < $1.order }.map { step in
                TestStep(order: step.order, action: "\(step.actor): \(step.action)", expectedOutcome: "")
            }
            scenarios.append(TestScenario(
                id: nextId("test-e2e"),
                specId: flow.id,
                category: "e2e",
                name: "E2E: \(flow.name)",
                preconditions: flow.trigger.isEmpty ? [] : [flow.trigger],
                steps: steps,
                expectedResult: flow.successOutcome,
                priority: "critical"
            ))

            // Error paths → edge-case scenarios
            for errorPath in flow.errorPaths {
                scenarios.append(TestScenario(
                    id: nextId("test-edge"),
                    specId: flow.id,
                    category: "edge-case",
                    name: "Edge: \(flow.name) — \(errorPath.error)",
                    preconditions: flow.trigger.isEmpty ? [] : [flow.trigger],
                    steps: [TestStep(order: 1, action: "Trigger error at step \(errorPath.atStep)", expectedOutcome: errorPath.handling)],
                    expectedResult: errorPath.handling,
                    priority: "nice-to-have"
                ))
            }
        }

        // 2. Screen edge cases → edge-case test scenarios
        for screen in doc.screens {
            for edgeCase in screen.edgeCases {
                scenarios.append(TestScenario(
                    id: nextId("test-edge"),
                    specId: screen.id,
                    category: "edge-case",
                    name: "Edge: \(screen.name) — \(String(edgeCase.prefix(60)))",
                    preconditions: screen.entryCondition.isEmpty ? [] : [screen.entryCondition],
                    steps: [TestStep(order: 1, action: edgeCase, expectedOutcome: "Handled gracefully")],
                    expectedResult: "Edge case handled without crash or data loss",
                    priority: "nice-to-have"
                ))
            }
        }

        // 3. API endpoints → integration test scenarios
        for api in doc.apiEndpoints {
            // Happy path
            let methodPath = "\(api.method) \(api.path)".trimmingCharacters(in: .whitespaces)
            scenarios.append(TestScenario(
                id: nextId("test-int"),
                specId: api.id,
                category: "integration",
                name: "API: \(api.name) — happy path",
                preconditions: api.auth.isEmpty ? [] : ["Authenticated (\(api.auth))"],
                steps: [TestStep(order: 1, action: "Call \(methodPath) with valid parameters", expectedOutcome: "200 OK with expected response shape")],
                expectedResult: "Successful response matching API contract",
                priority: "important"
            ))

            // Error responses
            for errResp in api.errorResponses {
                scenarios.append(TestScenario(
                    id: nextId("test-int"),
                    specId: api.id,
                    category: "integration",
                    name: "API: \(api.name) — error \(errResp.code)",
                    preconditions: [],
                    steps: [TestStep(order: 1, action: "Trigger \(errResp.code) condition", expectedOutcome: "\(errResp.code): \(errResp.message)")],
                    expectedResult: "Returns \(errResp.code) with message: \(errResp.message)",
                    priority: "important"
                ))
            }
        }

        // 4. Data model business rules → unit test scenarios
        for model in doc.dataModels {
            for rule in model.businessRules {
                scenarios.append(TestScenario(
                    id: nextId("test-unit"),
                    specId: model.id,
                    category: "unit",
                    name: "Rule: \(model.name) — \(String(rule.prefix(60)))",
                    preconditions: [],
                    steps: [TestStep(order: 1, action: "Validate: \(rule)", expectedOutcome: "Rule enforced correctly")],
                    expectedResult: "Business rule \"\(rule)\" is enforced",
                    priority: "important"
                ))
            }
        }

        return TestScenariosDocument(meta: meta, scenarios: scenarios)
    }

    // MARK: - Markdown Rendering

    static func renderMarkdown(_ doc: TestScenariosDocument) -> String {
        var md = "# \(doc.meta.projectName) — Test Scenarios\n\n"
        md += "**Generated**: \(ISO8601DateFormatter().string(from: doc.meta.generatedAt))\n"
        md += "**Total scenarios**: \(doc.scenarios.count)\n\n"

        // Group by priority
        let priorityOrder = ["critical", "important", "nice-to-have"]
        let grouped = Dictionary(grouping: doc.scenarios, by: \.priority)

        for priority in priorityOrder {
            guard let scenarios = grouped[priority], !scenarios.isEmpty else { continue }
            md += "---\n\n## \(priority.capitalized) (\(scenarios.count))\n\n"

            // Sub-group by category
            let byCategory = Dictionary(grouping: scenarios, by: \.category)
            for (category, items) in byCategory.sorted(by: { $0.key < $1.key }) {
                md += "### \(category) (\(items.count))\n\n"
                for scenario in items {
                    md += "#### \(scenario.name)\n\n"
                    md += "- **Spec**: `\(scenario.specId)`\n"
                    if !scenario.preconditions.isEmpty {
                        md += "- **Preconditions**: \(scenario.preconditions.joined(separator: "; "))\n"
                    }
                    if !scenario.steps.isEmpty {
                        md += "- **Steps**:\n"
                        for step in scenario.steps {
                            md += "  \(step.order). \(step.action)"
                            if !step.expectedOutcome.isEmpty { md += " → \(step.expectedOutcome)" }
                            md += "\n"
                        }
                    }
                    md += "- **Expected**: \(scenario.expectedResult)\n\n"
                }
            }
        }

        return md
    }
}
