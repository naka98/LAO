import Foundation
import LAODomain
import LAOServices

enum DemoSeedMode: String {
    case founder
    case empty

    static var current: DemoSeedMode? {
        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "--demo-seed"),
           arguments.indices.contains(arguments.index(after: flagIndex)) {
            return DemoSeedMode(rawValue: arguments[arguments.index(after: flagIndex)].lowercased())
        }

        if let envValue = ProcessInfo.processInfo.environment["LAO_DEMO_SEED"]?.lowercased() {
            return DemoSeedMode(rawValue: envValue)
        }

        return nil
    }

    var projectName: String {
        switch self {
        case .founder: return "[Demo] Founder OS"
        case .empty: return "[Demo] Empty Workspace"
        }
    }

    func seedIfNeeded(container: AppContainer) async throws -> UUID {
        print("[LAO Demo] seed start mode=\(rawValue)")
        let existingProjects = await container.projectService.listProjects()
        if let project = existingProjects.first(where: { $0.name == projectName }) {
            print("[LAO Demo] reusing project id=\(project.id.uuidString)")
            try FileManager.default.createDirectory(
                at: demoRootURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let board = try await ensureBoard(in: project, container: container)
            let agents = await container.agentService.listAgents()
            let seededAgents = try await ensureCoreMemberships(in: project, container: container, agents: agents)
            try await ensureScenarioContent(
                project: project,
                board: board,
                container: container,
                agents: seededAgents
            )
            return project.id
        }

        let rootURL = demoRootURL
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let project = try await container.projectService.createProject(
            name: projectName,
            rootPath: rootURL.path
        )
        print("[LAO Demo] created project id=\(project.id.uuidString)")

        let board = try await ensureBoard(in: project, container: container)

        let agents = await container.agentService.listAgents()
        let seededAgents: [AgentTier: Agent] = try await ensureCoreMemberships(in: project, container: container, agents: agents)

        try await ensureScenarioContent(
            project: project,
            board: board,
            container: container,
            agents: seededAgents
        )

        return project.id
    }

    private var boardDescription: String {
        switch self {
        case .founder:
            return "Founder demo board for Discuss / Decide / Build checks"
        case .empty:
            return "Empty demo board for first-run and empty-state checks"
        }
    }

    private var demoRootURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lao-demo")
            .appendingPathComponent(rawValue)
    }

    private func ensureCoreMemberships(
        in project: Project,
        container: AppContainer,
        agents: [Agent]
    ) async throws -> [AgentTier: Agent] {
        let desiredTiers: [AgentTier] = [.director, .directorFallback, .step]
        var found: [AgentTier: Agent] = [:]

        for tier in desiredTiers {
            if let agent = agents.first(where: { $0.tier == tier }) {
                found[tier] = agent
                _ = try? await container.projectAgentMembershipService.createMembership(projectId: project.id, agentId: agent.id)
            }
        }

        return found
    }

    private func ensureBoard(
        in project: Project,
        container: AppContainer
    ) async throws -> Board {
        let existingBoards = await container.boardService.listBoards(projectId: project.id)
        if let board = existingBoards.first(where: { $0.isDefault || $0.title == "General" }) {
            print("[LAO Demo] reusing board id=\(board.id.uuidString)")
            return board
        }

        let board = try await container.boardService.createBoard(
            Board(
                projectId: project.id,
                title: AppLanguage.currentStrings.root.defaultBoardTitle,
                slug: "general",
                type: .domain,
                description: boardDescription,
                position: 0,
                isDefault: true
            )
        )
        print("[LAO Demo] created board id=\(board.id.uuidString)")
        return board
    }

    private func ensureScenarioContent(
        project: Project,
        board: Board,
        container: AppContainer,
        agents: [AgentTier: Agent]
    ) async throws {
        // Scenario content seeding reserved for future use.
        // The founder mode now uses Design workflow requests instead of Posts.
    }
}
