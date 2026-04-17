import Foundation
import LAODomain

// MARK: - Core Service Protocols

public protocol ProjectService: Sendable {
    func listProjects() async -> [Project]
    func createProject(name: String, rootPath: String) async throws -> Project
    func updateProject(_ project: Project) async throws
    func deleteProject(id: UUID) async throws
}

public protocol AgentService: Sendable {
    func listAgents() async -> [Agent]
    func createAgent(_ agent: Agent) async throws -> Agent
    func updateAgent(_ agent: Agent) async throws
    func deleteAgent(id: UUID) async throws
}

public protocol SkillService: Sendable {
    func listSkills() async -> [Skill]
    func listSkills(role: AgentRole) async -> [Skill]
    func createSkill(_ skill: Skill) async throws -> Skill
    func updateSkill(_ skill: Skill) async throws
    func deleteSkill(id: UUID) async throws
}

public protocol UserProfileService: Sendable {
    func getProfile() async -> UserProfile
    func updateProfile(_ profile: UserProfile) async throws
}

public protocol AppSettingsService: Sendable {
    func getSettings() async -> AppSettings
    func updateSettings(_ settings: AppSettings) async throws
}

public protocol ProjectDeveloperLoopService: Sendable {
    func suggestedPreset(for project: Project) async -> DeveloperLoopPreset?
    func run(_ kind: DeveloperLoopCommandKind, for project: Project) async throws -> DeveloperLoopRunResult
    func runLoop(for project: Project) async throws -> [DeveloperLoopRunResult]
}

// MARK: - Board & Views

public protocol BoardService: Sendable {
    func listBoards(projectId: UUID) async -> [Board]
    func createBoard(_ board: Board) async throws -> Board
    func updateBoard(_ board: Board) async throws
    func archiveBoard(id: UUID, archivedAt: Date?) async throws
}

public protocol ProjectAgentMembershipService: Sendable {
    func listMemberships(projectId: UUID) async -> [ProjectAgentMembership]
    func createMembership(projectId: UUID, agentId: UUID) async throws -> ProjectAgentMembership
    func deleteMembership(id: UUID) async throws
}

// MARK: - Provider & CLI

public protocol ProviderRegistryService: Sendable {
    func listConfigs() async -> [ProviderConfig]
    func listRoleRoutings() async -> [AgentRoleRouting]
    func listProviderCLICommands() async -> [ProviderCLICommand]
    func updateProviderDefaultModel(provider: ProviderKey, model: String) async throws
    func upsertRoleRouting(_ routing: AgentRoleRouting) async throws
    func upsertProviderCLICommand(
        provider: ProviderKey,
        commandTemplate: String,
        executablePathOverride: String?
    ) async throws
    func validate(_ provider: ProviderKey) async -> ProviderValidationResult
}

public protocol CLIAgentRunner: Sendable {
    /// Run a CLI agent and return the complete output.
    /// - Parameter jsonSchema: Optional JSON Schema string to enforce structured output via CLI flags.
    func run(agent: Agent, prompt: String, projectId: UUID, rootPath: String, jsonSchema: String?) async throws -> String

    /// Streaming variant — calls `onChunk` with incremental stdout text as it arrives.
    /// Returns the final complete output (same as `run`).
    /// - Parameter jsonSchema: Optional JSON Schema string to enforce structured output via CLI flags.
    func runStreaming(
        agent: Agent,
        prompt: String,
        projectId: UUID,
        rootPath: String,
        jsonSchema: String?,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String
}

public extension CLIAgentRunner {
    // Backwards-compatible overload: callers without jsonSchema pass nil.
    func run(agent: Agent, prompt: String, projectId: UUID, rootPath: String) async throws -> String {
        try await run(agent: agent, prompt: prompt, projectId: projectId, rootPath: rootPath, jsonSchema: nil)
    }

    // Backwards-compatible overload: callers without jsonSchema pass nil.
    func runStreaming(
        agent: Agent,
        prompt: String,
        projectId: UUID,
        rootPath: String,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await runStreaming(agent: agent, prompt: prompt, projectId: projectId, rootPath: rootPath, jsonSchema: nil, onChunk: onChunk)
    }

    /// Default: fall back to non-streaming `run()` for providers that don't support streaming.
    func runStreaming(
        agent: Agent,
        prompt: String,
        projectId: UUID,
        rootPath: String,
        jsonSchema: String?,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await run(agent: agent, prompt: prompt, projectId: projectId, rootPath: rootPath, jsonSchema: jsonSchema)
    }
}

// MARK: - Idea Board

public protocol IdeaService: Sendable {
    /// Lightweight list — excludes `messagesJSON`.
    func listIdeas(projectId: UUID, limit: Int, offset: Int) async -> [Idea]
    func getIdea(id: UUID) async -> Idea?
    func createIdea(_ idea: Idea) async throws -> Idea
    func updateIdea(_ idea: Idea) async throws
    /// Lightweight status-only update — safe to call with list-loaded Idea objects
    /// that do not carry messagesJSON.
    func updateIdeaStatus(id: UUID, status: IdeaStatus) async throws
    func deleteIdea(id: UUID) async throws
}

public extension IdeaService {
    func listIdeas(projectId: UUID) async -> [Idea] {
        await listIdeas(projectId: projectId, limit: .max, offset: 0)
    }
}

// MARK: - Design Session

public protocol DesignSessionService: Sendable {
    /// Lightweight list query — excludes heavy `designStateJSON` column.
    /// Supports optional status filter and pagination.
    func listSessions(projectId: UUID, status: DesignSessionStatus?, limit: Int, offset: Int) async -> [DesignSession]
    /// Cross-project query: returns requests matching any of the given statuses.
    /// Lightweight — excludes `designStateJSON`. Used for session recovery on app launch.
    func listRequestsByStatuses(_ statuses: [DesignSessionStatus]) async -> [DesignSession]
    func getRequest(id: UUID) async -> DesignSession?
    func createRequest(_ request: DesignSession) async throws -> DesignSession
    func updateRequest(_ request: DesignSession) async throws
    func deleteRequest(id: UUID) async throws
}

public extension DesignSessionService {
    /// Convenience overload: loads all sessions without filter.
    func listSessions(projectId: UUID) async -> [DesignSession] {
        await listSessions(projectId: projectId, status: nil, limit: .max, offset: 0)
    }
}

// MARK: - Design Event Service

public protocol DesignEventService: Sendable {
    func listEvents(sessionId: UUID, limit: Int, offset: Int) async -> [DesignEvent]
    func appendEvent(_ event: DesignEvent) async throws
    func deleteEvents(sessionId: UUID) async throws
}
