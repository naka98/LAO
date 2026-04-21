import Foundation
import LAODomain

// MARK: - PlanDocumentConverter

/// Converts a DesignDocument into an ImplementationPlanDocument.
/// Pure algorithmic derivation — no LLM calls.
/// [Set] Part of the converter trilogy. Input: DesignDocument produced by `DesignDocumentConverter`.
///       Sibling: `TestDocumentConverter` derives test scenarios from the same DesignDocument.
enum PlanDocumentConverter {

    // MARK: - Conversion

    static func convert(_ doc: DesignDocument) -> ImplementationPlanDocument {
        let meta = DocumentMeta(
            documentType: "plan",
            projectName: doc.meta.projectName,
            sourceRequestId: doc.meta.sourceRequestId
        )

        let phases = buildPhases(from: doc)
        let milestones = buildMilestones(from: phases)
        let mvp = buildMVPScope(from: doc)
        let standards = buildProjectStandards(from: doc.meta)
        let infra = buildInfrastructureNotes(from: doc.meta)

        return ImplementationPlanDocument(
            meta: meta,
            milestones: milestones,
            mvpScope: mvp,
            phases: phases,
            projectStandards: standards,
            infrastructureNotes: infra
        )
    }

    // MARK: - Phases from Implementation Order

    private static func buildPhases(from doc: DesignDocument) -> [ImplementationPhase] {
        let allSpecs = collectAllSpecNames(from: doc)
        var phases: [ImplementationPhase] = []
        var previousIds: [String] = []

        for (index, group) in doc.implementationOrder.enumerated() {
            let specIds = group.filter { allSpecs[$0] != nil }
            guard !specIds.isEmpty else { continue }

            // Determine phase name from dominant spec type
            let name = phaseName(for: specIds, specNames: allSpecs, index: index)
            phases.append(ImplementationPhase(
                name: name,
                specIds: specIds,
                dependencies: previousIds,
                acceptanceCriteria: specIds.map { "[\($0)] implemented and tested" }
            ))
            previousIds = specIds
        }
        return phases
    }

    // MARK: - Milestones from Phases

    private static func buildMilestones(from phases: [ImplementationPhase]) -> [Milestone] {
        // Group phases into milestones by every 2 phases
        var milestones: [Milestone] = []
        let stride = max(1, (phases.count + 2) / 3)  // aim for ~3 milestones

        for i in Swift.stride(from: 0, to: phases.count, by: stride) {
            let end = min(i + stride, phases.count)
            let group = Array(phases[i..<end])
            let allSpecIds = group.flatMap(\.specIds)
            let name = i == 0 ? "Foundation" : (i + stride >= phases.count ? "Completion" : "Phase \(i / stride + 1)")

            milestones.append(Milestone(
                name: name,
                description: group.map(\.name).joined(separator: " + "),
                specIds: allSpecIds,
                acceptanceCriteria: ["All specs in this milestone pass acceptance criteria"]
            ))
        }
        return milestones
    }

    // MARK: - MVP Scope

    private static func buildMVPScope(from doc: DesignDocument) -> MVPScope {
        // First 2 implementation groups = MVP, rest = post-MVP
        let mvpGroupCount = min(2, doc.implementationOrder.count)
        let mvpIds = doc.implementationOrder.prefix(mvpGroupCount).flatMap { $0 }
        let postMvpIds = doc.implementationOrder.dropFirst(mvpGroupCount).flatMap { $0 }

        return MVPScope(
            includedSpecIds: mvpIds,
            excludedSpecIds: postMvpIds,
            rationale: mvpIds.isEmpty
                ? "No implementation order defined"
                : "First \(mvpGroupCount) group(s) form the MVP — foundational specs that other groups depend on"
        )
    }

    // MARK: - Project Standards (template-based from tech stack)

    private static func buildProjectStandards(from meta: DesignMeta) -> ProjectStandards {
        let techStack = meta.techStack ?? [:]
        let language = techStack["language"]?.lowercased() ?? ""
        let framework = techStack["framework"]?.lowercased() ?? ""
        let platform = techStack["platform"]?.lowercased() ?? ""

        // Template-based standards from tech stack
        if language.contains("swift") || framework.contains("swiftui") || platform.contains("ios") || platform.contains("macos") {
            return ProjectStandards(
                directoryStructure: "MVVM: Models/, Views/, ViewModels/, Services/, App/",
                namingConventions: "Types: PascalCase, properties/methods: camelCase, files: match primary type name",
                errorHandlingPattern: "Custom enum errors conforming to LocalizedError, async/await with do-catch",
                codingStyle: "Swift API Design Guidelines, MARK sections, Sendable conformance"
            )
        } else if language.contains("typescript") || framework.contains("react") || framework.contains("next") {
            return ProjectStandards(
                directoryStructure: "src/components/, src/hooks/, src/services/, src/types/, src/utils/",
                namingConventions: "Components: PascalCase, functions/variables: camelCase, files: match export name",
                errorHandlingPattern: "Error boundaries for UI, try-catch for async, custom error classes",
                codingStyle: "ESLint + Prettier, functional components, hooks-first"
            )
        } else if language.contains("python") || framework.contains("django") || framework.contains("flask") || framework.contains("fastapi") {
            return ProjectStandards(
                directoryStructure: "app/, models/, routes/, services/, tests/",
                namingConventions: "Classes: PascalCase, functions/variables: snake_case, modules: snake_case",
                errorHandlingPattern: "Custom exception hierarchy, structured error responses",
                codingStyle: "PEP 8, type hints, docstrings for public API"
            )
        }

        return ProjectStandards(
            directoryStructure: "Organize by feature or layer as appropriate for \(meta.projectType)",
            namingConventions: "Follow language conventions for \(language.isEmpty ? meta.projectType : language)",
            errorHandlingPattern: "Define custom error types, handle errors at appropriate boundaries",
            codingStyle: "Follow established conventions for the chosen tech stack"
        )
    }

    // MARK: - Infrastructure Notes

    private static func buildInfrastructureNotes(from meta: DesignMeta) -> InfrastructureNotes {
        let platform = meta.techStack?["platform"]?.lowercased() ?? ""

        if platform.contains("ios") || platform.contains("macos") {
            return InfrastructureNotes(
                deployment: "App Store / TestFlight distribution",
                cicd: "Xcode Cloud or GitHub Actions with xcodebuild",
                environment: "Debug / Release schemes, Info.plist configuration",
                migration: ""
            )
        } else if platform.contains("web") {
            return InfrastructureNotes(
                deployment: "Vercel / Netlify / Cloud hosting",
                cicd: "GitHub Actions: lint → test → build → deploy",
                environment: ".env files, environment-specific configs",
                migration: ""
            )
        }

        return InfrastructureNotes()
    }

    // MARK: - Helpers

    private static func collectAllSpecNames(from doc: DesignDocument) -> [String: String] {
        var names: [String: String] = [:]
        for s in doc.screens { names[s.id] = s.name }
        for m in doc.dataModels { names[m.id] = m.name }
        for a in doc.apiEndpoints { names[a.id] = a.name }
        for f in doc.userFlows { names[f.id] = f.name }
        return names
    }

    private static func phaseName(for specIds: [String], specNames: [String: String], index: Int) -> String {
        // Determine dominant type by prefix
        let types = specIds.map { id -> String in
            if id.hasPrefix("model-") { return "Data" }
            if id.hasPrefix("screen-") { return "UI" }
            if id.hasPrefix("api-") { return "API" }
            if id.hasPrefix("flow-") { return "Flow" }
            return "Misc"
        }
        let dominant = Dictionary(grouping: types, by: { $0 }).max(by: { $0.value.count < $1.value.count })?.key ?? "Phase"
        return "\(dominant) Layer (Group \(index + 1))"
    }

    // MARK: - Markdown Rendering

    static func renderMarkdown(_ plan: ImplementationPlanDocument) -> String {
        var md = "# \(plan.meta.projectName) — Implementation Plan\n\n"
        md += "**Generated**: \(ISO8601DateFormatter().string(from: plan.meta.generatedAt))\n\n"

        // MVP Scope
        md += "## MVP Scope\n\n"
        if !plan.mvpScope.includedSpecIds.isEmpty {
            md += "**Included**: \(plan.mvpScope.includedSpecIds.joined(separator: ", "))\n\n"
        }
        if !plan.mvpScope.excludedSpecIds.isEmpty {
            md += "**Post-MVP**: \(plan.mvpScope.excludedSpecIds.joined(separator: ", "))\n\n"
        }
        if !plan.mvpScope.rationale.isEmpty {
            md += "**Rationale**: \(plan.mvpScope.rationale)\n\n"
        }

        // Milestones
        if !plan.milestones.isEmpty {
            md += "---\n\n## Milestones\n\n"
            for (i, m) in plan.milestones.enumerated() {
                md += "### \(i + 1). \(m.name)\n\n"
                if !m.description.isEmpty { md += "\(m.description)\n\n" }
                if !m.specIds.isEmpty { md += "**Specs**: \(m.specIds.joined(separator: ", "))\n\n" }
            }
        }

        // Phases
        if !plan.phases.isEmpty {
            md += "---\n\n## Implementation Phases\n\n"
            for phase in plan.phases {
                md += "### \(phase.name)\n\n"
                md += "**Specs**: \(phase.specIds.joined(separator: ", "))\n\n"
                if !phase.dependencies.isEmpty {
                    md += "**Depends on**: \(phase.dependencies.joined(separator: ", "))\n\n"
                }
            }
        }

        // Project Standards
        md += "---\n\n## Project Standards\n\n"
        if !plan.projectStandards.directoryStructure.isEmpty {
            md += "**Directory Structure**: \(plan.projectStandards.directoryStructure)\n\n"
        }
        if !plan.projectStandards.namingConventions.isEmpty {
            md += "**Naming Conventions**: \(plan.projectStandards.namingConventions)\n\n"
        }
        if !plan.projectStandards.errorHandlingPattern.isEmpty {
            md += "**Error Handling**: \(plan.projectStandards.errorHandlingPattern)\n\n"
        }
        if !plan.projectStandards.codingStyle.isEmpty {
            md += "**Coding Style**: \(plan.projectStandards.codingStyle)\n\n"
        }

        // Infrastructure
        let infra = plan.infrastructureNotes
        if !infra.deployment.isEmpty || !infra.cicd.isEmpty || !infra.environment.isEmpty || !infra.migration.isEmpty {
            md += "---\n\n## Infrastructure\n\n"
            if !infra.deployment.isEmpty { md += "**Deployment**: \(infra.deployment)\n\n" }
            if !infra.cicd.isEmpty { md += "**CI/CD**: \(infra.cicd)\n\n" }
            if !infra.environment.isEmpty { md += "**Environment**: \(infra.environment)\n\n" }
            if !infra.migration.isEmpty { md += "**Migration**: \(infra.migration)\n\n" }
        }

        return md
    }
}
