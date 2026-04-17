import Foundation
import LAODomain
import SQLite3

public struct SQLiteStoreLocation: Hashable, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

public enum SQLiteBootstrapError: Error {
    case openDatabase(String)
    case executeStatement(String)
}

public enum SQLiteBootstrapSchema {
    /// v3 core tables that replace v2 tables with incompatible schemas.
    public static let v3CoreTables: [String] = [
        "projects", "agents", "skills"
    ]

    public static let v3Statements: [String] = [
        """
        CREATE TABLE IF NOT EXISTS projects (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT NOT NULL DEFAULT '',
          root_path TEXT NOT NULL DEFAULT '',
          created_at REAL NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS agents (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          role TEXT NOT NULL,
          provider TEXT NOT NULL,
          model TEXT NOT NULL,
          system_prompt TEXT NOT NULL DEFAULT ''
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS skills (
          id TEXT PRIMARY KEY,
          role TEXT NOT NULL,
          name TEXT NOT NULL,
          description TEXT NOT NULL DEFAULT '',
          created_at REAL NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS user_profile (
          key TEXT PRIMARY KEY DEFAULT 'singleton',
          name TEXT NOT NULL DEFAULT '',
          title TEXT NOT NULL DEFAULT '',
          bio TEXT NOT NULL DEFAULT ''
        );
        """,
        // Ensure exactly one row exists
        "INSERT OR IGNORE INTO user_profile (key) VALUES ('singleton');",
        """
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY DEFAULT 'singleton',
          cli_timeout_seconds INTEGER NOT NULL DEFAULT 600,
          cli_idle_timeout_seconds INTEGER NOT NULL DEFAULT 300,
          context_token_limit INTEGER NOT NULL DEFAULT 8000
        );
        """,
        "INSERT OR IGNORE INTO app_settings (key) VALUES ('singleton');",
        """
        CREATE TABLE IF NOT EXISTS provider_configs (
          id TEXT PRIMARY KEY,
          provider TEXT NOT NULL,
          status TEXT NOT NULL,
          default_model TEXT NOT NULL,
          enabled INTEGER NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS role_provider_routings (
          role TEXT PRIMARY KEY,
          provider TEXT NOT NULL,
          model TEXT NOT NULL,
          updated_at REAL NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS provider_cli_commands (
          provider TEXT PRIMARY KEY,
          command_template TEXT NOT NULL,
          executable_path TEXT,
          updated_at REAL NOT NULL
        );
        """,
        "PRAGMA foreign_keys = ON;"
    ]

    // MARK: - v5 Schema (Boards, Views, Memberships)

    public static let v5Statements: [String] = [
        """
        CREATE TABLE IF NOT EXISTS project_agent_memberships (
          id TEXT PRIMARY KEY,
          project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
          agent_id TEXT NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
          is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1)),
          created_at REAL NOT NULL
        );
        """,
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_project_agent_memberships_unique ON project_agent_memberships(project_id, agent_id);",
        "CREATE INDEX IF NOT EXISTS idx_project_agent_memberships_project ON project_agent_memberships(project_id);",

        """
        CREATE TABLE IF NOT EXISTS boards (
          id TEXT PRIMARY KEY,
          project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
          title TEXT NOT NULL,
          slug TEXT NOT NULL,
          type TEXT NOT NULL DEFAULT 'domain' CHECK (type IN ('domain', 'workflow')),
          description TEXT NOT NULL DEFAULT '',
          position INTEGER NOT NULL DEFAULT 0,
          is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1)),
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL,
          archived_at REAL
        );
        """,
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_boards_project_slug ON boards(project_id, slug);",
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_boards_one_default_per_project ON boards(project_id) WHERE is_default = 1 AND archived_at IS NULL;",
        "CREATE INDEX IF NOT EXISTS idx_boards_project_position ON boards(project_id, position);",

    ]

    // MARK: - v6 Schema (Design Sessions)

    public static let v6Statements: [String] = [
        """
        CREATE TABLE IF NOT EXISTS design_sessions (
          id TEXT PRIMARY KEY,
          project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
          board_id TEXT NOT NULL REFERENCES boards(id) ON DELETE CASCADE,
          title TEXT NOT NULL,
          task_description TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'planning',
          phase_name TEXT NOT NULL DEFAULT '',
          total_steps INTEGER NOT NULL DEFAULT 0,
          completed_steps INTEGER NOT NULL DEFAULT 0,
          director_agent_id TEXT, -- DEPRECATED: no longer used by the application
          triage_summary TEXT NOT NULL DEFAULT '',
          roadmap_json TEXT NOT NULL DEFAULT '[]',
          design_state_json TEXT NOT NULL DEFAULT '',
          api_call_count INTEGER NOT NULL DEFAULT 0,
          estimated_tokens INTEGER NOT NULL DEFAULT 0,
          created_at REAL NOT NULL DEFAULT 0,
          updated_at REAL NOT NULL DEFAULT 0
        );
        """,
        "CREATE INDEX IF NOT EXISTS idx_design_sessions_board ON design_sessions(board_id, status);",
        "CREATE INDEX IF NOT EXISTS idx_design_sessions_board_date ON design_sessions(board_id, created_at DESC);",
        "CREATE INDEX IF NOT EXISTS idx_design_sessions_project ON design_sessions(project_id, created_at DESC);",
    ]

    // MARK: - v7 Schema (Idea Board)

    public static let v7Statements: [String] = [
        """
        CREATE TABLE IF NOT EXISTS ideas (
          id TEXT PRIMARY KEY,
          project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
          title TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'draft',
          messages_json TEXT NOT NULL DEFAULT '[]',
          design_session_id TEXT,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL
        );
        """,
        "CREATE INDEX IF NOT EXISTS idx_ideas_project ON ideas(project_id, created_at DESC);",
    ]

    // MARK: - v8 Schema (Design Event Log)

    public static let v8Statements: [String] = [
        """
        CREATE TABLE IF NOT EXISTS design_events (
          id TEXT PRIMARY KEY,
          session_id TEXT NOT NULL REFERENCES design_sessions(id) ON DELETE CASCADE,
          event_type TEXT NOT NULL,
          payload_json TEXT,
          created_at REAL NOT NULL
        );
        """,
        "CREATE INDEX IF NOT EXISTS idx_design_events_session ON design_events(session_id, created_at DESC);",
    ]

    /// Seed default CLI command templates (INSERT OR IGNORE to avoid overwriting user customizations).
    public static let v3SeedStatements: [String] = [
        """
        INSERT OR IGNORE INTO provider_cli_commands (provider, command_template, executable_path, updated_at)
        VALUES ('claude', 'claude --model "$LAO_MODEL" -p "$LAO_PROMPT"', NULL, 0);
        """,
        """
        INSERT OR IGNORE INTO provider_cli_commands (provider, command_template, executable_path, updated_at)
        VALUES ('codex', 'codex exec -m "$LAO_MODEL" "$LAO_PROMPT"', NULL, 0);
        """,
        """
        INSERT OR IGNORE INTO provider_cli_commands (provider, command_template, executable_path, updated_at)
        VALUES ('gemini', 'gemini --model "$LAO_MODEL"', NULL, 0);
        """,
    ]
}

    public final class SQLiteStoreBootstrapper {
    public init() {}

    public func bootstrap(at location: SQLiteStoreLocation) throws {
        try FileManager.default.createDirectory(
            at: location.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var db: OpaquePointer?
        if sqlite3_open(location.url.path, &db) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw SQLiteBootstrapError.openDatabase(message)
        }

        defer { sqlite3_close(db) }

        // Detect v2 schema: if 'projects' table exists but lacks 'created_at', drop all core tables.
        if tableExists(db, name: "projects") && !columnExists(db, table: "projects", column: "created_at") {
            for table in SQLiteBootstrapSchema.v3CoreTables.reversed() {
                sqlite3_exec(db, "DROP TABLE IF EXISTS \(table);", nil, nil, nil)
            }
        }

        // Migrate: agents table previously had project_id; drop to recreate without it.
        if tableExists(db, name: "agents") && columnExists(db, table: "agents", column: "project_id") {
            sqlite3_exec(db, "DROP TABLE IF EXISTS agents;", nil, nil, nil)
        }

        try executeStatements(SQLiteBootstrapSchema.v3Statements, db: db)

        // Migrate additive columns after the base tables exist so fresh installs and upgrades converge.
        try addColumnIfMissing(db, table: "app_settings", column: "cli_idle_timeout_seconds", definition: "INTEGER NOT NULL DEFAULT 300")
        try addColumnIfMissing(db, table: "app_settings", column: "context_token_limit", definition: "INTEGER NOT NULL DEFAULT 4000")
        try addColumnIfMissing(db, table: "app_settings", column: "design_mockup_mode", definition: "TEXT NOT NULL DEFAULT 'directorDecides'")
        try addColumnIfMissing(db, table: "app_settings", column: "clarification_enabled", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfMissing(db, table: "app_settings", column: "language", definition: "TEXT NOT NULL DEFAULT 'en'")
        try addColumnIfMissing(db, table: "app_settings", column: "elaboration_concurrency", definition: "INTEGER NOT NULL DEFAULT 5")

        // v5 additive migration for projects and agents
        try addColumnIfMissing(db, table: "projects", column: "title", definition: "TEXT NOT NULL DEFAULT ''")
        try exec(db, sql: "UPDATE projects SET title = name WHERE title = '';")
        try addColumnIfMissing(db, table: "projects", column: "status", definition: "TEXT NOT NULL DEFAULT 'active'")
        try addColumnIfMissing(db, table: "projects", column: "updated_at", definition: "REAL NOT NULL DEFAULT 0")
        try exec(db, sql: "UPDATE projects SET updated_at = created_at WHERE updated_at = 0;")
        try addColumnIfMissing(db, table: "projects", column: "archived_at", definition: "REAL")
        try addColumnIfMissing(db, table: "projects", column: "tech_stack_json", definition: "TEXT NOT NULL DEFAULT '{}'")

        try addColumnIfMissing(db, table: "agents", column: "is_archived", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfMissing(db, table: "agents", column: "created_at", definition: "REAL NOT NULL DEFAULT 0")
        try addColumnIfMissing(db, table: "agents", column: "updated_at", definition: "REAL NOT NULL DEFAULT 0")
        try exec(db, sql: "UPDATE agents SET updated_at = created_at WHERE updated_at = 0;")

        // Agent tier + isEnabled migration
        try addColumnIfMissing(db, table: "agents", column: "tier", definition: "TEXT NOT NULL DEFAULT 'step'")
        try addColumnIfMissing(db, table: "agents", column: "is_enabled", definition: "INTEGER NOT NULL DEFAULT 1")
        // Migrate existing role-based agents: PM -> director, Planner -> directorFallback
        try exec(db, sql: "UPDATE agents SET tier = 'director' WHERE role = 'pm' AND tier = 'step';")
        try exec(db, sql: "UPDATE agents SET tier = 'directorFallback' WHERE role = 'planner' AND tier = 'step';")

        // Create v5 board/membership tables and indexes
        try executeStatements(SQLiteBootstrapSchema.v5Statements, db: db)

        // Ensure every project has a deterministic default board.
        try exec(db, sql: """
            INSERT OR IGNORE INTO boards (
              id, project_id, title, slug, type, description, position, is_default, created_at, updated_at, archived_at
            )
            SELECT
              projects.id,
              projects.id,
              'General',
              'general',
              'domain',
              'Default board',
              0,
              1,
              COALESCE(NULLIF(projects.updated_at, 0), projects.created_at),
              COALESCE(NULLIF(projects.updated_at, 0), projects.created_at),
              NULL
            FROM projects;
            """)

        // v6: Design Sessions
        try executeStatements(SQLiteBootstrapSchema.v6Statements, db: db)
        try addColumnIfMissing(db, table: "workflow_requests", column: "workflow_state_json", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfMissing(db, table: "workflow_requests", column: "api_call_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfMissing(db, table: "workflow_requests", column: "estimated_tokens", definition: "INTEGER NOT NULL DEFAULT 0")

        // v7: Idea Board
        try executeStatements(SQLiteBootstrapSchema.v7Statements, db: db)
        try addColumnIfMissing(db, table: "ideas", column: "api_call_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfMissing(db, table: "ideas", column: "total_input_chars", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfMissing(db, table: "ideas", column: "total_output_chars", definition: "INTEGER NOT NULL DEFAULT 0")

        // v8: Design Event Log
        try executeStatements(SQLiteBootstrapSchema.v8Statements, db: db)

        // v9: Rename legacy tables and columns to match Swift type names.
        // Table renames stay fire-and-forget: they only matter for legacy DBs
        // and a missing source table is the common case (no log noise from SQLite).
        sqlite3_exec(db, "ALTER TABLE workflow_requests RENAME TO design_sessions", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE workflow_events RENAME TO design_events", nil, nil, nil)
        // Column renames are guarded so fresh installs (where v6/v7/v8 already
        // created the new column names) don't trigger SQLite "no such column"
        // errors that macOS Unified Logging surfaces in the Xcode console.
        if columnExists(db, table: "design_events", column: "request_id") {
            try exec(db, sql: "ALTER TABLE design_events RENAME COLUMN request_id TO session_id")
        }
        if columnExists(db, table: "design_sessions", column: "workflow_state_json") {
            try exec(db, sql: "ALTER TABLE design_sessions RENAME COLUMN workflow_state_json TO design_state_json")
        }
        if columnExists(db, table: "ideas", column: "converted_request_id") {
            try exec(db, sql: "ALTER TABLE ideas RENAME COLUMN converted_request_id TO design_session_id")
        }

        // Rebuild indexes with new names (idempotent: DROP IF EXISTS + CREATE IF NOT EXISTS)
        sqlite3_exec(db, "DROP INDEX IF EXISTS idx_workflow_requests_board", nil, nil, nil)
        sqlite3_exec(db, "DROP INDEX IF EXISTS idx_workflow_requests_board_date", nil, nil, nil)
        sqlite3_exec(db, "DROP INDEX IF EXISTS idx_workflow_requests_project", nil, nil, nil)
        sqlite3_exec(db, "DROP INDEX IF EXISTS idx_workflow_events_request", nil, nil, nil)
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_design_sessions_board ON design_sessions(board_id, status)", nil, nil, nil)
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_design_sessions_board_date ON design_sessions(board_id, created_at DESC)", nil, nil, nil)
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_design_sessions_project ON design_sessions(project_id, created_at DESC)", nil, nil, nil)
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_design_events_session ON design_events(session_id, created_at DESC)", nil, nil, nil)

        // Repair: fresh installs created design_sessions via v6 but missed these columns
        // because the addColumnIfMissing calls above targeted the old 'workflow_requests' table.
        try addColumnIfMissing(db, table: "design_sessions", column: "design_state_json", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfMissing(db, table: "design_sessions", column: "api_call_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try addColumnIfMissing(db, table: "design_sessions", column: "estimated_tokens", definition: "INTEGER NOT NULL DEFAULT 0")

        // v10: BRD/CPS document storage for 6-document framework
        try addColumnIfMissing(db, table: "design_sessions", column: "brd_json", definition: "TEXT NOT NULL DEFAULT ''")
        try addColumnIfMissing(db, table: "design_sessions", column: "cps_json", definition: "TEXT NOT NULL DEFAULT ''")

        // v11: Design Brief — structured exploration output (brief = BRD + synthesis direction + key decisions)
        try addColumnIfMissing(db, table: "design_sessions", column: "design_brief_json", definition: "TEXT NOT NULL DEFAULT ''")

        // Seed default CLI commands if empty
        for statement in SQLiteBootstrapSchema.v3SeedStatements {
            sqlite3_exec(db, statement, nil, nil, nil)
        }
    }

    // MARK: - Schema Introspection

    private func tableExists(_ db: OpaquePointer?, name: String) -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name='\(name)' LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func columnExists(_ db: OpaquePointer?, table: String, column: String) -> Bool {
        let sql = "PRAGMA table_info(\(table));"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let raw = sqlite3_column_text(stmt, 1) {
                let colName = String(cString: raw)
                if colName == column { return true }
            }
        }
        return false
    }

    private func executeStatements(_ statements: [String], db: OpaquePointer?) throws {
        for statement in statements {
            try exec(db, sql: statement)
        }
    }

    private func addColumnIfMissing(_ db: OpaquePointer?, table: String, column: String, definition: String) throws {
        guard tableExists(db, name: table), !columnExists(db, table: table, column: column) else { return }
        try exec(db, sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
    }

    private func exec(_ db: OpaquePointer?, sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteBootstrapError.executeStatement(message)
        }
    }
}
