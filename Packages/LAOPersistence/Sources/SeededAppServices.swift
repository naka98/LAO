import Foundation
import LAODomain
import LAOServices
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum LAOStoreLocationResolver {
    public static func defaultLocation(fileManager: FileManager = .default) throws -> SQLiteStoreLocation {
        if let overridePath = ProcessInfo.processInfo.environment["LAO_STORE_PATH"],
           !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: overridePath)
            let directory = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return SQLiteStoreLocation(url: url)
        }

        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let subdirectory = Bundle.main.bundleIdentifier ?? "LAO"
        let root = appSupport.appendingPathComponent(subdirectory, isDirectory: true)
        return SQLiteStoreLocation(url: root.appendingPathComponent("lao.sqlite"))
    }
}

public enum SeededSQLiteStoreError: Error {
    case prepare(String)
    case step(String)
    case missingData(String)
    case decode(String)
}

extension SeededSQLiteStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .prepare(let message):
            return "SQLite prepare failed: \(message)"
        case .step(let message):
            return "SQLite step failed: \(message)"
        case .missingData(let message):
            return "Missing data: \(message)"
        case .decode(let message):
            return "Decode failed: \(message)"
        }
    }
}

// MARK: - v3 SQLite Store

public actor SeededSQLiteStore {
    private let location: SQLiteStoreLocation

    public init(location: SQLiteStoreLocation) throws {
        self.location = location
        try SQLiteStoreBootstrapper().bootstrap(at: location)
    }

    // MARK: - Projects

    public func listProjects() throws -> [Project] {
        try withDatabase { db in
            let sql = "SELECT id, name, description, root_path, created_at, tech_stack_json FROM projects ORDER BY created_at DESC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            defer { sqlite3_finalize(stmt) }

            var results: [Project] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(Project(
                    id: UUID(uuidString: columnText(stmt, index: 0)) ?? UUID(),
                    name: columnText(stmt, index: 1),
                    description: columnText(stmt, index: 2),
                    rootPath: columnText(stmt, index: 3),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4)),
                    techStackJSON: columnText(stmt, index: 5)
                ))
            }
            return results
        }
    }

    public func createProject(name: String, rootPath: String) throws -> Project {
        let project = Project(name: name, rootPath: rootPath)
        try withDatabase { db in
            try Self.execute(db, sql: "INSERT INTO projects (id, name, description, root_path, created_at, tech_stack_json) VALUES (?, ?, ?, ?, ?, ?);",
                           bindings: [project.id.uuidString, project.name, project.description, project.rootPath, "\(project.createdAt.timeIntervalSince1970)", project.techStackJSON])
        }
        return project
    }

    public func updateProject(_ project: Project) throws {
        try withDatabase { db in
            try Self.execute(db, sql: "UPDATE projects SET name = ?, description = ?, root_path = ?, tech_stack_json = ? WHERE id = ?;",
                           bindings: [project.name, project.description, project.rootPath, project.techStackJSON, project.id.uuidString])
        }
    }

    public func deleteProject(id: UUID) throws {
        try withDatabase { db in
            try Self.execute(db, sql: "PRAGMA foreign_keys = ON;", bindings: [])
            try Self.execute(db, sql: "DELETE FROM projects WHERE id = ?;", bindings: [id.uuidString])
        }
    }

    // MARK: - Agents

    public func listAgents() throws -> [Agent] {
        try withDatabase { db in
            let sql = "SELECT id, name, role, provider, model, system_prompt, tier, is_enabled FROM agents ORDER BY name ASC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            defer { sqlite3_finalize(stmt) }

            var results: [Agent] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(Agent(
                    id: UUID(uuidString: columnText(stmt, index: 0)) ?? UUID(),
                    name: columnText(stmt, index: 1),
                    tier: AgentTier(rawValue: columnText(stmt, index: 6)) ?? .step,
                    provider: ProviderKey(rawValue: columnText(stmt, index: 3)) ?? .claude,
                    model: columnText(stmt, index: 4),
                    systemPrompt: columnText(stmt, index: 5),
                    isEnabled: sqlite3_column_int(stmt, 7) != 0
                ))
            }
            return results
        }
    }

    public func createAgent(_ agent: Agent) throws -> Agent {
        try withDatabase { db in
            try Self.execute(db, sql: """
                INSERT INTO agents (id, name, role, provider, model, system_prompt, tier, is_enabled) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                """, bindings: [agent.id.uuidString, agent.name, agent.tier.rawValue, agent.provider.rawValue, agent.model, agent.systemPrompt, agent.tier.rawValue, agent.isEnabled ? "1" : "0"])
        }
        return agent
    }

    public func updateAgent(_ agent: Agent) throws {
        try withDatabase { db in
            try Self.execute(db, sql: "UPDATE agents SET name = ?, role = ?, provider = ?, model = ?, system_prompt = ?, tier = ?, is_enabled = ? WHERE id = ?;",
                           bindings: [agent.name, agent.tier.rawValue, agent.provider.rawValue, agent.model, agent.systemPrompt, agent.tier.rawValue, agent.isEnabled ? "1" : "0", agent.id.uuidString])
        }
    }

    public func deleteAgent(id: UUID) throws {
        try withDatabase { db in
            try Self.execute(db, sql: "DELETE FROM agents WHERE id = ?;", bindings: [id.uuidString])
        }
    }

    // MARK: - Skills

    public func listAllSkills() throws -> [Skill] {
        try withDatabase { db in
            let sql = "SELECT id, role, name, description, created_at FROM skills ORDER BY role ASC, name ASC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            defer { sqlite3_finalize(stmt) }

            var results: [Skill] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(Skill(
                    id: UUID(uuidString: columnText(stmt, index: 0)) ?? UUID(),
                    role: AgentRole(rawValue: columnText(stmt, index: 1)) ?? .pm,
                    name: columnText(stmt, index: 2),
                    skillDescription: columnText(stmt, index: 3),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
                ))
            }
            return results
        }
    }

    public func listSkills(role: AgentRole) throws -> [Skill] {
        try withDatabase { db in
            let sql = "SELECT id, role, name, description, created_at FROM skills WHERE role = ? ORDER BY name ASC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            sqlite3_bind_text(stmt, 1, role.rawValue, -1, sqliteTransient)
            defer { sqlite3_finalize(stmt) }

            var results: [Skill] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(Skill(
                    id: UUID(uuidString: columnText(stmt, index: 0)) ?? UUID(),
                    role: AgentRole(rawValue: columnText(stmt, index: 1)) ?? role,
                    name: columnText(stmt, index: 2),
                    skillDescription: columnText(stmt, index: 3),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
                ))
            }
            return results
        }
    }

    public func createSkill(_ skill: Skill) throws -> Skill {
        try withDatabase { db in
            try Self.execute(db, sql: "INSERT INTO skills (id, role, name, description, created_at) VALUES (?, ?, ?, ?, ?);",
                           bindings: [skill.id.uuidString, skill.role.rawValue, skill.name, skill.skillDescription, "\(skill.createdAt.timeIntervalSince1970)"])
        }
        return skill
    }

    public func updateSkill(_ skill: Skill) throws {
        try withDatabase { db in
            try Self.execute(db, sql: "UPDATE skills SET role = ?, name = ?, description = ? WHERE id = ?;",
                           bindings: [skill.role.rawValue, skill.name, skill.skillDescription, skill.id.uuidString])
        }
    }

    public func deleteSkill(id: UUID) throws {
        try withDatabase { db in
            try Self.execute(db, sql: "DELETE FROM skills WHERE id = ?;", bindings: [id.uuidString])
        }
    }

    // MARK: - User Profile

    public func getUserProfile() throws -> UserProfile {
        try withDatabase { db in
            let sql = "SELECT name, title, bio FROM user_profile WHERE key = 'singleton';"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            defer { sqlite3_finalize(stmt) }

            if sqlite3_step(stmt) == SQLITE_ROW {
                return UserProfile(
                    name: columnText(stmt, index: 0),
                    title: columnText(stmt, index: 1),
                    bio: columnText(stmt, index: 2)
                )
            }
            return UserProfile()
        }
    }

    public func updateUserProfile(_ profile: UserProfile) throws {
        try withDatabase { db in
            try Self.execute(db, sql: """
                INSERT INTO user_profile (key, name, title, bio) VALUES ('singleton', ?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET name = excluded.name, title = excluded.title, bio = excluded.bio;
                """, bindings: [profile.name, profile.title, profile.bio])
        }
    }

    // MARK: - App Settings

    public func getAppSettings() throws -> AppSettings {
        try withDatabase { db in
            let sql = "SELECT cli_timeout_seconds, cli_idle_timeout_seconds, context_token_limit, language, elaboration_concurrency FROM app_settings WHERE key = 'singleton';"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            defer { sqlite3_finalize(stmt) }

            if sqlite3_step(stmt) == SQLITE_ROW {
                return AppSettings(
                    cliTimeoutSeconds: Int(sqlite3_column_int(stmt, 0)),
                    cliIdleTimeoutSeconds: Int(sqlite3_column_int(stmt, 1)),
                    contextTokenLimit: Int(sqlite3_column_int(stmt, 2)),
                    language: columnText(stmt, index: 3),
                    elaborationConcurrency: Int(sqlite3_column_int(stmt, 4))
                )
            }
            return AppSettings()
        }
    }

    public func updateAppSettings(_ settings: AppSettings) throws {
        try withDatabase { db in
            try Self.execute(db, sql: """
                INSERT INTO app_settings (key, cli_timeout_seconds, cli_idle_timeout_seconds, context_token_limit, language, elaboration_concurrency) VALUES ('singleton', ?, ?, ?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET cli_timeout_seconds = excluded.cli_timeout_seconds, cli_idle_timeout_seconds = excluded.cli_idle_timeout_seconds, context_token_limit = excluded.context_token_limit, language = excluded.language, elaboration_concurrency = excluded.elaboration_concurrency;
                """, bindings: [String(settings.cliTimeoutSeconds), String(settings.cliIdleTimeoutSeconds), String(settings.contextTokenLimit), settings.language, String(settings.elaborationConcurrency)])
        }
    }

    // MARK: - Provider Config

    public func listProviderConfigs() throws -> [ProviderConfig] {
        try withDatabase { db in
            let sql = "SELECT id, provider, status, default_model, enabled FROM provider_configs ORDER BY provider ASC;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            defer { sqlite3_finalize(stmt) }

            var results: [ProviderConfig] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(ProviderConfig(
                    id: UUID(uuidString: columnText(stmt, index: 0)) ?? UUID(),
                    provider: ProviderKey(rawValue: columnText(stmt, index: 1)) ?? .claude,
                    status: ProviderStatus(rawValue: columnText(stmt, index: 2)) ?? .unconfigured,
                    defaultModel: columnText(stmt, index: 3),
                    enabled: sqlite3_column_int(stmt, 4) != 0
                ))
            }
            return results
        }
    }

    public func listRoleRoutings() throws -> [AgentRoleRouting] {
        try withDatabase { db in
            let sql = "SELECT role, provider, model FROM role_provider_routings;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            defer { sqlite3_finalize(stmt) }

            var results: [AgentRoleRouting] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(AgentRoleRouting(
                    role: AgentRole(rawValue: columnText(stmt, index: 0)) ?? .pm,
                    provider: ProviderKey(rawValue: columnText(stmt, index: 1)) ?? .claude,
                    model: columnText(stmt, index: 2)
                ))
            }
            return results
        }
    }

    public func listProviderCLICommands() throws -> [ProviderCLICommand] {
        try withDatabase { db in
            let sql = "SELECT provider, command_template, executable_path FROM provider_cli_commands;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            defer { sqlite3_finalize(stmt) }

            var results: [ProviderCLICommand] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(ProviderCLICommand(
                    provider: ProviderKey(rawValue: columnText(stmt, index: 0)) ?? .claude,
                    commandTemplate: columnText(stmt, index: 1),
                    executablePathOverride: nullableColumnText(stmt, index: 2)
                ))
            }
            return results
        }
    }

    public func updateProviderDefaultModel(provider: ProviderKey, model: String) throws {
        try withDatabase { db in
            try Self.execute(db, sql: "UPDATE provider_configs SET default_model = ? WHERE provider = ?;",
                           bindings: [model, provider.rawValue])
        }
    }

    public func upsertRoleRouting(_ routing: AgentRoleRouting) throws {
        try withDatabase { db in
            try Self.execute(db, sql: """
                INSERT INTO role_provider_routings (role, provider, model, updated_at) VALUES (?, ?, ?, ?)
                ON CONFLICT(role) DO UPDATE SET provider = excluded.provider, model = excluded.model, updated_at = excluded.updated_at;
                """, bindings: [routing.role.rawValue, routing.provider.rawValue, routing.model, "\(Date().timeIntervalSince1970)"])
        }
    }

    public func upsertProviderCLICommand(provider: ProviderKey, commandTemplate: String, executablePathOverride: String?) throws {
        try withDatabase { db in
            try Self.execute(db, sql: """
                INSERT INTO provider_cli_commands (provider, command_template, executable_path, updated_at) VALUES (?, ?, ?, ?)
                ON CONFLICT(provider) DO UPDATE SET command_template = excluded.command_template, executable_path = excluded.executable_path, updated_at = excluded.updated_at;
                """, bindings: [provider.rawValue, commandTemplate, executablePathOverride, "\(Date().timeIntervalSince1970)"])
        }
    }

    // MARK: - v5 Boards

    public func listBoards(projectId: UUID) throws -> [Board] {
        try withDatabase { db in
            let sql = """
                SELECT id, project_id, title, slug, type, description, position, is_default, created_at, updated_at, archived_at
                FROM boards
                WHERE project_id = ? AND archived_at IS NULL
                ORDER BY is_default DESC, position ASC, created_at ASC;
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            sqlite3_bind_text(stmt, 1, projectId.uuidString, -1, sqliteTransient)
            defer { sqlite3_finalize(stmt) }

            var results: [Board] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(Self.readBoardRow(stmt))
            }
            return results
        }
    }

    public func createBoard(_ board: Board) throws -> Board {
        try withDatabase { db in
            try Self.execute(db, sql: """
                INSERT INTO boards (id, project_id, title, slug, type, description, position, is_default, created_at, updated_at, archived_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """,
                bindings: [
                    board.id.uuidString, board.projectId.uuidString, board.title, board.slug, board.type.rawValue,
                    board.description, "\(board.position)", board.isDefault ? "1" : "0",
                    "\(board.createdAt.timeIntervalSince1970)", "\(board.updatedAt.timeIntervalSince1970)",
                    board.archivedAt.map { "\($0.timeIntervalSince1970)" }
                ])
        }
        return board
    }

    public func updateBoard(_ board: Board) throws {
        try withDatabase { db in
            try Self.execute(db, sql: """
                UPDATE boards
                SET title = ?, slug = ?, type = ?, description = ?, position = ?, is_default = ?, updated_at = ?, archived_at = ?
                WHERE id = ?;
                """,
                bindings: [
                    board.title, board.slug, board.type.rawValue, board.description,
                    "\(board.position)", board.isDefault ? "1" : "0",
                    "\(Date().timeIntervalSince1970)", board.archivedAt.map { "\($0.timeIntervalSince1970)" },
                    board.id.uuidString
                ])
        }
    }

    public func archiveBoard(id: UUID, archivedAt: Date?) throws {
        try withDatabase { db in
            try Self.execute(db, sql: """
                UPDATE boards
                SET archived_at = ?, is_default = CASE WHEN ? IS NULL THEN is_default ELSE 0 END, updated_at = ?
                WHERE id = ?;
                """,
                bindings: [
                    archivedAt.map { "\($0.timeIntervalSince1970)" },
                    archivedAt.map { "\($0.timeIntervalSince1970)" },
                    "\(Date().timeIntervalSince1970)",
                    id.uuidString
                ])
        }
    }

    private static func readBoardRow(_ stmt: OpaquePointer?) -> Board {
        let archivedAtRaw = sqlite3_column_type(stmt, 10) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 10)
        return Board(
            id: UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0))) ?? UUID(),
            projectId: UUID(uuidString: String(cString: sqlite3_column_text(stmt, 1))) ?? UUID(),
            title: String(cString: sqlite3_column_text(stmt, 2)),
            slug: String(cString: sqlite3_column_text(stmt, 3)),
            type: BoardType(rawValue: String(cString: sqlite3_column_text(stmt, 4))) ?? .domain,
            description: String(cString: sqlite3_column_text(stmt, 5)),
            position: Int(sqlite3_column_int(stmt, 6)),
            isDefault: sqlite3_column_int(stmt, 7) != 0,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9)),
            archivedAt: archivedAtRaw.map { Date(timeIntervalSince1970: $0) }
        )
    }

    // MARK: - v5 Project Agent Memberships

    public func listProjectAgentMemberships(projectId: UUID) throws -> [ProjectAgentMembership] {
        try withDatabase { db in
            let sql = """
                SELECT id, project_id, agent_id, created_at
                FROM project_agent_memberships
                WHERE project_id = ?
                ORDER BY created_at ASC;
                """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            sqlite3_bind_text(stmt, 1, projectId.uuidString, -1, sqliteTransient)
            defer { sqlite3_finalize(stmt) }

            var results: [ProjectAgentMembership] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(Self.readProjectAgentMembershipRow(stmt))
            }
            return results
        }
    }

    public func createProjectAgentMembership(projectId: UUID, agentId: UUID) throws -> ProjectAgentMembership {
        let membership = ProjectAgentMembership(projectId: projectId, agentId: agentId)
        try withDatabase { db in
            try Self.execute(db, sql: """
                INSERT OR IGNORE INTO project_agent_memberships (id, project_id, agent_id, created_at)
                VALUES (?, ?, ?, ?);
                """, bindings: [
                    membership.id.uuidString,
                    membership.projectId.uuidString,
                    membership.agentId.uuidString,
                    "\(membership.createdAt.timeIntervalSince1970)"
                ])
        }
        return membership
    }

    public func deleteProjectAgentMembership(id: UUID) throws {
        try withDatabase { db in
            try Self.execute(db, sql: "DELETE FROM project_agent_memberships WHERE id = ?;", bindings: [id.uuidString])
        }
    }

    private static func readProjectAgentMembershipRow(_ stmt: OpaquePointer?) -> ProjectAgentMembership {
        ProjectAgentMembership(
            id: UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0))) ?? UUID(),
            projectId: UUID(uuidString: String(cString: sqlite3_column_text(stmt, 1))) ?? UUID(),
            agentId: UUID(uuidString: String(cString: sqlite3_column_text(stmt, 2))) ?? UUID(),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))
        )
    }

    // MARK: - Design Sessions

    /// Lightweight list query -- excludes heavy `design_state_json` to keep memory low when many sessions exist.
    /// Supports optional status filter and pagination via LIMIT/OFFSET.
    public func listDesignSessions(projectId: UUID, status: DesignSessionStatus? = nil, limit: Int = .max, offset: Int = 0) throws -> [DesignSession] {
        try withDatabase { db in
            var sql = """
            SELECT id, project_id, board_id, title, task_description, status, phase_name,
                   total_steps, completed_steps, triage_summary, roadmap_json,
                   api_call_count, estimated_tokens, created_at, updated_at
            FROM design_sessions WHERE project_id = ?
            """
            var bindIndex: Int32 = 2
            if status != nil {
                sql += " AND status = ?"
                bindIndex += 1
            }
            sql += " ORDER BY created_at DESC LIMIT ? OFFSET ?;"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, projectId.uuidString, -1, sqliteTransient)
            var nextBind: Int32 = 2
            if let status {
                sqlite3_bind_text(stmt, nextBind, status.rawValue, -1, sqliteTransient)
                nextBind += 1
            }
            sqlite3_bind_int64(stmt, nextBind, Int64(limit))
            sqlite3_bind_int64(stmt, nextBind + 1, Int64(offset))

            var results: [DesignSession] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(DesignSession(
                    id: UUID(uuidString: columnText(stmt, index: 0)) ?? UUID(),
                    projectId: UUID(uuidString: columnText(stmt, index: 1)) ?? UUID(),
                    boardId: UUID(uuidString: columnText(stmt, index: 2)) ?? UUID(),
                    title: columnText(stmt, index: 3),
                    taskDescription: columnText(stmt, index: 4),
                    status: DesignSessionStatus(rawValue: columnText(stmt, index: 5)) ?? .planning,
                    phaseName: columnText(stmt, index: 6),
                    totalSteps: Int(sqlite3_column_int(stmt, 7)),
                    completedSteps: Int(sqlite3_column_int(stmt, 8)),
                    triageSummary: columnText(stmt, index: 9),
                    roadmapJSON: columnText(stmt, index: 10),
                    designStateJSON: "",  // Not loaded for list queries -- use getRequest() for full data
                    apiCallCount: Int(sqlite3_column_int(stmt, 11)),
                    estimatedTokens: Int(sqlite3_column_int(stmt, 12)),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 13)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 14))
                ))
            }
            return results
        }
    }

    /// Cross-project query returning requests whose status matches any of the given values.
    /// Lightweight: excludes `design_state_json` (same as `listDesignSessions`).
    public func listDesignSessionsByStatuses(_ statuses: [DesignSessionStatus]) throws -> [DesignSession] {
        guard !statuses.isEmpty else { return [] }
        return try withDatabase { db in
            let placeholders = statuses.map { _ in "?" }.joined(separator: ", ")
            let sql = """
            SELECT id, project_id, board_id, title, task_description, status, phase_name,
                   total_steps, completed_steps, triage_summary, roadmap_json,
                   api_call_count, estimated_tokens, created_at, updated_at
            FROM design_sessions WHERE status IN (\(placeholders))
            ORDER BY updated_at DESC;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            defer { sqlite3_finalize(stmt) }

            for (i, status) in statuses.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), status.rawValue, -1, sqliteTransient)
            }

            var results: [DesignSession] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(DesignSession(
                    id: UUID(uuidString: columnText(stmt, index: 0)) ?? UUID(),
                    projectId: UUID(uuidString: columnText(stmt, index: 1)) ?? UUID(),
                    boardId: UUID(uuidString: columnText(stmt, index: 2)) ?? UUID(),
                    title: columnText(stmt, index: 3),
                    taskDescription: columnText(stmt, index: 4),
                    status: DesignSessionStatus(rawValue: columnText(stmt, index: 5)) ?? .planning,
                    phaseName: columnText(stmt, index: 6),
                    totalSteps: Int(sqlite3_column_int(stmt, 7)),
                    completedSteps: Int(sqlite3_column_int(stmt, 8)),
                    triageSummary: columnText(stmt, index: 9),
                    roadmapJSON: columnText(stmt, index: 10),
                    designStateJSON: "",  // Not loaded for list queries
                    apiCallCount: Int(sqlite3_column_int(stmt, 11)),
                    estimatedTokens: Int(sqlite3_column_int(stmt, 12)),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 13)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 14))
                ))
            }
            return results
        }
    }

    public func getDesignSession(id: UUID) throws -> DesignSession? {
        try withDatabase { db in
            let sql = """
            SELECT id, project_id, board_id, title, task_description, status, phase_name,
                   total_steps, completed_steps, triage_summary, roadmap_json,
                   design_state_json, api_call_count, estimated_tokens, created_at, updated_at,
                   brd_json, cps_json, design_brief_json
            FROM design_sessions WHERE id = ? LIMIT 1;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, sqliteTransient)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return DesignSession(
                id: UUID(uuidString: columnText(stmt, index: 0)) ?? UUID(),
                projectId: UUID(uuidString: columnText(stmt, index: 1)) ?? UUID(),
                boardId: UUID(uuidString: columnText(stmt, index: 2)) ?? UUID(),
                title: columnText(stmt, index: 3),
                taskDescription: columnText(stmt, index: 4),
                status: DesignSessionStatus(rawValue: columnText(stmt, index: 5)) ?? .planning,
                phaseName: columnText(stmt, index: 6),
                totalSteps: Int(sqlite3_column_int(stmt, 7)),
                completedSteps: Int(sqlite3_column_int(stmt, 8)),
                triageSummary: columnText(stmt, index: 9),
                roadmapJSON: columnText(stmt, index: 10),
                brdJSON: columnText(stmt, index: 16),
                designBriefJSON: columnText(stmt, index: 18),
                cpsJSON: columnText(stmt, index: 17),
                designStateJSON: columnText(stmt, index: 11),
                apiCallCount: Int(sqlite3_column_int(stmt, 12)),
                estimatedTokens: Int(sqlite3_column_int(stmt, 13)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 14)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 15))
            )
        }
    }

    public func createDesignSession(_ request: DesignSession) throws -> DesignSession {
        try withDatabase { db in
            try Self.execute(db, sql: """
            INSERT INTO design_sessions (
                id, project_id, board_id, title, task_description, status, phase_name,
                total_steps, completed_steps, triage_summary, roadmap_json,
                design_state_json, api_call_count, estimated_tokens, created_at, updated_at,
                brd_json, cps_json, design_brief_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, bindings: [
                request.id.uuidString,
                request.projectId.uuidString,
                request.boardId.uuidString,
                request.title,
                request.taskDescription,
                request.status.rawValue,
                request.phaseName,
                "\(request.totalSteps)",
                "\(request.completedSteps)",
                request.triageSummary,
                request.roadmapJSON,
                request.designStateJSON,
                "\(request.apiCallCount)",
                "\(request.estimatedTokens)",
                "\(request.createdAt.timeIntervalSince1970)",
                "\(request.updatedAt.timeIntervalSince1970)",
                request.brdJSON,
                request.cpsJSON,
                request.designBriefJSON,
            ])
        }
        return request
    }

    public func updateDesignSession(_ request: DesignSession) throws {
        try withDatabase { db in
            try Self.execute(db, sql: """
            UPDATE design_sessions SET
                title = ?, task_description = ?, status = ?, phase_name = ?,
                total_steps = ?, completed_steps = ?,
                triage_summary = ?, roadmap_json = ?, design_state_json = ?,
                api_call_count = ?, estimated_tokens = ?,
                updated_at = ?,
                brd_json = ?, cps_json = ?, design_brief_json = ?
            WHERE id = ?;
            """, bindings: [
                request.title,
                request.taskDescription,
                request.status.rawValue,
                request.phaseName,
                "\(request.totalSteps)",
                "\(request.completedSteps)",
                request.triageSummary,
                request.roadmapJSON,
                request.designStateJSON,
                "\(request.apiCallCount)",
                "\(request.estimatedTokens)",
                "\(Date().timeIntervalSince1970)",
                request.brdJSON,
                request.cpsJSON,
                request.designBriefJSON,
                request.id.uuidString,
            ])
        }
    }

    public func deleteDesignSession(id: UUID) throws {
        try withDatabase { db in
            try Self.execute(db, sql: "DELETE FROM design_sessions WHERE id = ?;", bindings: [id.uuidString])
        }
    }

    // MARK: - Idea Board CRUD (v7)

    public func listIdeas(projectId: UUID, limit: Int = .max, offset: Int = 0) throws -> [Idea] {
        try withDatabase { db in
            let sql = """
            SELECT id, project_id, title, status, design_session_id,
                   api_call_count, total_input_chars, total_output_chars,
                   created_at, updated_at
            FROM ideas WHERE project_id = ?
            ORDER BY created_at DESC LIMIT ? OFFSET ?;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, projectId.uuidString, -1, sqliteTransient)
            sqlite3_bind_int64(stmt, 2, Int64(limit))
            sqlite3_bind_int64(stmt, 3, Int64(offset))

            var results: [Idea] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let convertedIdStr = columnText(stmt, index: 4)
                results.append(Idea(
                    id: UUID(uuidString: columnText(stmt, index: 0)) ?? UUID(),
                    projectId: UUID(uuidString: columnText(stmt, index: 1)) ?? UUID(),
                    title: columnText(stmt, index: 2),
                    status: IdeaStatus(rawValue: columnText(stmt, index: 3)) ?? .draft,
                    messagesJSON: "",  // Not loaded for list queries
                    designSessionId: convertedIdStr.isEmpty ? nil : UUID(uuidString: convertedIdStr),
                    apiCallCount: Int(sqlite3_column_int(stmt, 5)),
                    totalInputChars: Int(sqlite3_column_int(stmt, 6)),
                    totalOutputChars: Int(sqlite3_column_int(stmt, 7)),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8)),
                    updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))
                ))
            }
            return results
        }
    }

    public func getIdea(id: UUID) throws -> Idea? {
        try withDatabase { db in
            let sql = """
            SELECT id, project_id, title, status, messages_json, design_session_id,
                   api_call_count, total_input_chars, total_output_chars,
                   created_at, updated_at
            FROM ideas WHERE id = ? LIMIT 1;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id.uuidString, -1, sqliteTransient)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let convertedIdStr = columnText(stmt, index: 5)
            return Idea(
                id: UUID(uuidString: columnText(stmt, index: 0)) ?? UUID(),
                projectId: UUID(uuidString: columnText(stmt, index: 1)) ?? UUID(),
                title: columnText(stmt, index: 2),
                status: IdeaStatus(rawValue: columnText(stmt, index: 3)) ?? .draft,
                messagesJSON: columnText(stmt, index: 4),
                designSessionId: convertedIdStr.isEmpty ? nil : UUID(uuidString: convertedIdStr),
                apiCallCount: Int(sqlite3_column_int(stmt, 6)),
                totalInputChars: Int(sqlite3_column_int(stmt, 7)),
                totalOutputChars: Int(sqlite3_column_int(stmt, 8)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10))
            )
        }
    }

    public func createIdea(_ idea: Idea) throws -> Idea {
        try withDatabase { db in
            try Self.execute(db, sql: """
            INSERT INTO ideas (id, project_id, title, status, messages_json, design_session_id,
                               api_call_count, total_input_chars, total_output_chars, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, bindings: [
                idea.id.uuidString,
                idea.projectId.uuidString,
                idea.title,
                idea.status.rawValue,
                idea.messagesJSON,
                idea.designSessionId?.uuidString ?? "",
                "\(idea.apiCallCount)",
                "\(idea.totalInputChars)",
                "\(idea.totalOutputChars)",
                "\(idea.createdAt.timeIntervalSince1970)",
                "\(idea.updatedAt.timeIntervalSince1970)",
            ])
        }
        return idea
    }

    public func updateIdea(_ idea: Idea) throws {
        try withDatabase { db in
            try Self.execute(db, sql: """
            UPDATE ideas SET
                title = ?, status = ?, messages_json = ?, design_session_id = ?,
                api_call_count = ?, total_input_chars = ?, total_output_chars = ?, updated_at = ?
            WHERE id = ?;
            """, bindings: [
                idea.title,
                idea.status.rawValue,
                idea.messagesJSON,
                idea.designSessionId?.uuidString ?? "",
                "\(idea.apiCallCount)",
                "\(idea.totalInputChars)",
                "\(idea.totalOutputChars)",
                "\(Date().timeIntervalSince1970)",
                idea.id.uuidString,
            ])
        }
    }

    public func updateIdeaStatus(id: UUID, status: IdeaStatus) throws {
        try withDatabase { db in
            try Self.execute(db, sql: """
            UPDATE ideas SET status = ?, updated_at = ? WHERE id = ?;
            """, bindings: [
                status.rawValue,
                "\(Date().timeIntervalSince1970)",
                id.uuidString,
            ])
        }
    }

    public func deleteIdea(id: UUID) throws {
        try withDatabase { db in
            try Self.execute(db, sql: "DELETE FROM ideas WHERE id = ?;", bindings: [id.uuidString])
        }
    }

    // MARK: - Design Event Log (v8)

    public func listDesignEvents(sessionId: UUID, limit: Int = .max, offset: Int = 0) throws -> [DesignEvent] {
        try withDatabase { db in
            let sql = """
            SELECT id, session_id, event_type, payload_json, created_at
            FROM design_events WHERE session_id = ?
            ORDER BY created_at DESC LIMIT ? OFFSET ?;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw SeededSQLiteStoreError.prepare(Self.lastError(db))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, sessionId.uuidString, -1, sqliteTransient)
            sqlite3_bind_int64(stmt, 2, Int64(limit))
            sqlite3_bind_int64(stmt, 3, Int64(offset))

            var results: [DesignEvent] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let payloadStr = columnText(stmt, index: 3)
                results.append(DesignEvent(
                    id: UUID(uuidString: columnText(stmt, index: 0)) ?? UUID(),
                    sessionId: UUID(uuidString: columnText(stmt, index: 1)) ?? UUID(),
                    eventType: columnText(stmt, index: 2),
                    payloadJSON: payloadStr.isEmpty ? nil : payloadStr,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
                ))
            }
            return results
        }
    }

    public func appendDesignEvent(_ event: DesignEvent) throws {
        try withDatabase { db in
            try Self.execute(db, sql: """
            INSERT INTO design_events (id, session_id, event_type, payload_json, created_at)
            VALUES (?, ?, ?, ?, ?);
            """, bindings: [
                event.id.uuidString,
                event.sessionId.uuidString,
                event.eventType,
                event.payloadJSON,
                "\(event.createdAt.timeIntervalSince1970)",
            ])
        }
    }

    public func deleteDesignEvents(sessionId: UUID) throws {
        try withDatabase { db in
            try Self.execute(db, sql: "DELETE FROM design_events WHERE session_id = ?;", bindings: [sessionId.uuidString])
        }
    }

    // MARK: - SQLite Utilities

    private func withDatabase<T>(_ body: (OpaquePointer?) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open(location.url.path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown open error"
            sqlite3_close(db)
            throw SQLiteBootstrapError.openDatabase(message)
        }
        defer { sqlite3_close(db) }
        return try body(db)
    }

    private static func execute(_ db: OpaquePointer?, sql: String, bindings: [String?]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SeededSQLiteStoreError.prepare(lastError(db))
        }
        defer { sqlite3_finalize(statement) }

        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            if let value {
                guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
                    throw SeededSQLiteStoreError.step("Failed to bind text.")
                }
            } else {
                guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                    throw SeededSQLiteStoreError.step("Failed to bind null.")
                }
            }
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SeededSQLiteStoreError.step(lastError(db))
        }
    }

    private static func lastError(_ db: OpaquePointer?) -> String {
        guard let db else { return "Unknown SQLite error" }
        return String(cString: sqlite3_errmsg(db))
    }

    private func columnText(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let raw = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: raw)
    }

    private func nullableColumnText(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return columnText(statement, index: index)
    }
}

// MARK: - v3 Service Implementations

public final class SQLiteProjectService: ProjectService, @unchecked Sendable {
    private let store: SeededSQLiteStore
    public init(store: SeededSQLiteStore) { self.store = store }

    public func listProjects() async -> [Project] { (try? await store.listProjects()) ?? [] }
    public func createProject(name: String, rootPath: String) async throws -> Project { try await store.createProject(name: name, rootPath: rootPath) }
    public func updateProject(_ project: Project) async throws { try await store.updateProject(project) }
    public func deleteProject(id: UUID) async throws { try await store.deleteProject(id: id) }
}

public final class SQLiteAgentService: AgentService, @unchecked Sendable {
    private let store: SeededSQLiteStore
    public init(store: SeededSQLiteStore) { self.store = store }

    public func listAgents() async -> [Agent] { (try? await store.listAgents()) ?? [] }
    public func createAgent(_ agent: Agent) async throws -> Agent { try await store.createAgent(agent) }
    public func updateAgent(_ agent: Agent) async throws { try await store.updateAgent(agent) }
    public func deleteAgent(id: UUID) async throws { try await store.deleteAgent(id: id) }
}

public final class SQLiteSkillService: SkillService, @unchecked Sendable {
    private let store: SeededSQLiteStore
    public init(store: SeededSQLiteStore) { self.store = store }

    public func listSkills() async -> [Skill] { (try? await store.listAllSkills()) ?? [] }
    public func listSkills(role: AgentRole) async -> [Skill] { (try? await store.listSkills(role: role)) ?? [] }
    public func createSkill(_ skill: Skill) async throws -> Skill { try await store.createSkill(skill) }
    public func updateSkill(_ skill: Skill) async throws { try await store.updateSkill(skill) }
    public func deleteSkill(id: UUID) async throws { try await store.deleteSkill(id: id) }
}

public final class SQLiteUserProfileService: UserProfileService, @unchecked Sendable {
    private let store: SeededSQLiteStore
    public init(store: SeededSQLiteStore) { self.store = store }

    public func getProfile() async -> UserProfile { (try? await store.getUserProfile()) ?? UserProfile() }
    public func updateProfile(_ profile: UserProfile) async throws { try await store.updateUserProfile(profile) }
}

public final class SQLiteAppSettingsService: AppSettingsService, @unchecked Sendable {
    private let store: SeededSQLiteStore
    public init(store: SeededSQLiteStore) { self.store = store }

    public func getSettings() async -> AppSettings { (try? await store.getAppSettings()) ?? AppSettings() }
    public func updateSettings(_ settings: AppSettings) async throws { try await store.updateAppSettings(settings) }
}

public final class SQLiteProviderRegistryService: ProviderRegistryService, @unchecked Sendable {
    private let store: SeededSQLiteStore
    public init(store: SeededSQLiteStore) { self.store = store }

    public func listConfigs() async -> [ProviderConfig] { (try? await store.listProviderConfigs()) ?? [] }
    public func listRoleRoutings() async -> [AgentRoleRouting] { (try? await store.listRoleRoutings()) ?? [] }
    public func listProviderCLICommands() async -> [ProviderCLICommand] { (try? await store.listProviderCLICommands()) ?? [] }
    public func updateProviderDefaultModel(provider: ProviderKey, model: String) async throws { try await store.updateProviderDefaultModel(provider: provider, model: model) }
    public func upsertRoleRouting(_ routing: AgentRoleRouting) async throws { try await store.upsertRoleRouting(routing) }
    public func upsertProviderCLICommand(provider: ProviderKey, commandTemplate: String, executablePathOverride: String?) async throws {
        try await store.upsertProviderCLICommand(provider: provider, commandTemplate: commandTemplate, executablePathOverride: executablePathOverride)
    }
    public func validate(_ provider: ProviderKey) async -> ProviderValidationResult {
        ProviderValidationResult(provider: provider, status: .unconfigured, message: "Validation not yet implemented")
    }
}

// MARK: - v5 Service Implementations

public final class SQLiteBoardService: BoardService, @unchecked Sendable {
    private let store: SeededSQLiteStore
    public init(store: SeededSQLiteStore) { self.store = store }

    public func listBoards(projectId: UUID) async -> [Board] { (try? await store.listBoards(projectId: projectId)) ?? [] }
    public func createBoard(_ board: Board) async throws -> Board { try await store.createBoard(board) }
    public func updateBoard(_ board: Board) async throws { try await store.updateBoard(board) }
    public func archiveBoard(id: UUID, archivedAt: Date?) async throws { try await store.archiveBoard(id: id, archivedAt: archivedAt) }
}

public final class SQLiteProjectAgentMembershipService: ProjectAgentMembershipService, @unchecked Sendable {
    private let store: SeededSQLiteStore
    public init(store: SeededSQLiteStore) { self.store = store }

    public func listMemberships(projectId: UUID) async -> [ProjectAgentMembership] {
        (try? await store.listProjectAgentMemberships(projectId: projectId)) ?? []
    }

    public func createMembership(projectId: UUID, agentId: UUID) async throws -> ProjectAgentMembership {
        try await store.createProjectAgentMembership(projectId: projectId, agentId: agentId)
    }

    public func deleteMembership(id: UUID) async throws {
        try await store.deleteProjectAgentMembership(id: id)
    }
}

// MARK: - v6 Service Implementations

public final class SQLiteDesignSessionService: DesignSessionService, @unchecked Sendable {
    private let store: SeededSQLiteStore
    public init(store: SeededSQLiteStore) { self.store = store }

    public func listSessions(projectId: UUID, status: DesignSessionStatus?, limit: Int, offset: Int) async -> [DesignSession] {
        (try? await store.listDesignSessions(projectId: projectId, status: status, limit: limit, offset: offset)) ?? []
    }
    public func listRequestsByStatuses(_ statuses: [DesignSessionStatus]) async -> [DesignSession] {
        (try? await store.listDesignSessionsByStatuses(statuses)) ?? []
    }
    public func getRequest(id: UUID) async -> DesignSession? { try? await store.getDesignSession(id: id) }
    public func createRequest(_ request: DesignSession) async throws -> DesignSession { try await store.createDesignSession(request) }
    public func updateRequest(_ request: DesignSession) async throws { try await store.updateDesignSession(request) }
    public func deleteRequest(id: UUID) async throws { try await store.deleteDesignSession(id: id) }
}

// MARK: - v7 Service Implementations

public final class SQLiteIdeaService: IdeaService, @unchecked Sendable {
    private let store: SeededSQLiteStore
    public init(store: SeededSQLiteStore) { self.store = store }

    public func listIdeas(projectId: UUID, limit: Int, offset: Int) async -> [Idea] {
        (try? await store.listIdeas(projectId: projectId, limit: limit, offset: offset)) ?? []
    }
    public func getIdea(id: UUID) async -> Idea? { try? await store.getIdea(id: id) }
    public func createIdea(_ idea: Idea) async throws -> Idea { try await store.createIdea(idea) }
    public func updateIdea(_ idea: Idea) async throws { try await store.updateIdea(idea) }
    public func updateIdeaStatus(id: UUID, status: IdeaStatus) async throws { try await store.updateIdeaStatus(id: id, status: status) }
    public func deleteIdea(id: UUID) async throws { try await store.deleteIdea(id: id) }
}

// MARK: - v8 Service Implementations

public final class SQLiteDesignEventService: DesignEventService, @unchecked Sendable {
    private let store: SeededSQLiteStore
    public init(store: SeededSQLiteStore) { self.store = store }

    public func listEvents(sessionId: UUID, limit: Int, offset: Int) async -> [DesignEvent] {
        (try? await store.listDesignEvents(sessionId: sessionId, limit: limit, offset: offset)) ?? []
    }
    public func appendEvent(_ event: DesignEvent) async throws { try await store.appendDesignEvent(event) }
    public func deleteEvents(sessionId: UUID) async throws { try await store.deleteDesignEvents(sessionId: sessionId) }
}
