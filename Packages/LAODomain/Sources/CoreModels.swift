import Foundation

// MARK: - Shared Enums

public enum StatusTone: String, Codable, Sendable, CaseIterable {
    case neutral
    case blue
    case green
    case amber
    case red
    case purple
}

public enum ProviderKey: String, Codable, Sendable, CaseIterable, Identifiable {
    case codex
    case claude
    case gemini

    public var id: String { rawValue }
}

/// Per-provider API usage statistics for cost tracking.
public struct ProviderUsageStats: Codable, Sendable, Hashable {
    public var callCount: Int
    public var inputChars: Int
    public var outputChars: Int
    public var failedCallCount: Int

    public init(callCount: Int = 0, inputChars: Int = 0,
                outputChars: Int = 0, failedCallCount: Int = 0) {
        self.callCount = callCount
        self.inputChars = inputChars
        self.outputChars = outputChars
        self.failedCallCount = failedCallCount
    }
}

public enum ProviderStatus: String, Codable, Sendable, CaseIterable {
    case unconfigured
    case valid
    case invalid
    case offline
    case rateLimited = "rate_limited"
}

public enum AgentRole: String, Codable, Sendable, CaseIterable, Identifiable {
    case pm
    case planner
    case designer
    case dev
    case qa
    case research
    case marketer
    case reviewer

    public var id: String { rawValue }
}

public enum AgentTier: String, Codable, Sendable, CaseIterable, Identifiable {
    case director
    case directorFallback
    case step

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .director: return "Director"
        case .directorFallback: return "Fallback"
        case .step: return "Step"
        }
    }
}

// MARK: - v5 Core Enums

public enum BoardType: String, Codable, Sendable, CaseIterable {
    case domain
    case workflow
}

// MARK: - v6 Design Session Enums

public enum DesignSessionStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case planning
    case reviewing
    case executing
    case completed
    case failed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .planning: return "Planning"
        case .reviewing: return "Reviewing"
        case .executing: return "Executing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    public var tone: StatusTone {
        switch self {
        case .planning: return .blue
        case .reviewing: return .amber
        case .executing: return .purple
        case .completed: return .green
        case .failed: return .red
        }
    }
}

// MARK: - UI Support

public struct StatusBadge: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let title: String
    public let tone: StatusTone

    public init(id: UUID = UUID(), title: String, tone: StatusTone = .neutral) {
        self.id = id
        self.title = title
        self.tone = tone
    }
}

// MARK: - Core Models

public struct Project: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var description: String
    public var rootPath: String
    public let createdAt: Date
    /// JSON-encoded tech stack info, e.g. `{"language":"Swift","framework":"SwiftUI","platform":"macOS 15+"}`.
    public var techStackJSON: String

    public init(id: UUID = UUID(), name: String, description: String = "", rootPath: String = "", createdAt: Date = Date(), techStackJSON: String = "{}") {
        self.id = id
        self.name = name
        self.description = description
        self.rootPath = rootPath
        self.createdAt = createdAt
        self.techStackJSON = techStackJSON
    }

    /// Decoded tech stack dictionary. Returns empty dict on parse failure.
    public var techStack: [String: String] {
        guard let data = techStackJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }
}

public struct Agent: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var tier: AgentTier
    public var provider: ProviderKey
    public var model: String
    public var systemPrompt: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        tier: AgentTier = .step,
        provider: ProviderKey,
        model: String,
        systemPrompt: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.tier = tier
        self.provider = provider
        self.model = model
        self.systemPrompt = systemPrompt
        self.isEnabled = isEnabled
    }
}

// MARK: - v5 Core Models

public struct Board: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let projectId: UUID
    public var title: String
    public var slug: String
    public var type: BoardType
    public var description: String
    public var position: Int
    public var isDefault: Bool
    public let createdAt: Date
    public var updatedAt: Date
    public var archivedAt: Date?

    public init(
        id: UUID = UUID(),
        projectId: UUID,
        title: String,
        slug: String,
        type: BoardType = .domain,
        description: String = "",
        position: Int = 0,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.slug = slug
        self.type = type
        self.description = description
        self.position = position
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }
}

public struct ProjectAgentMembership: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let projectId: UUID
    public let agentId: UUID
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        projectId: UUID,
        agentId: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.agentId = agentId
        self.createdAt = createdAt
    }
}

// MARK: - v6 Design Session Models

public struct DesignSession: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var projectId: UUID
    public var boardId: UUID
    public var title: String
    public var taskDescription: String
    public var status: DesignSessionStatus
    public var phaseName: String
    public var totalSteps: Int
    public var completedSteps: Int
    public var triageSummary: String
    public var roadmapJSON: String
    public var brdJSON: String
    public var designBriefJSON: String
    public var cpsJSON: String
    public var designStateJSON: String
    public var apiCallCount: Int
    public var estimatedTokens: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        projectId: UUID,
        boardId: UUID,
        title: String,
        taskDescription: String,
        status: DesignSessionStatus = .planning,
        phaseName: String = "",
        totalSteps: Int = 0,
        completedSteps: Int = 0,
        triageSummary: String = "",
        roadmapJSON: String = "[]",
        brdJSON: String = "",
        designBriefJSON: String = "",
        cpsJSON: String = "",
        designStateJSON: String = "",
        apiCallCount: Int = 0,
        estimatedTokens: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.boardId = boardId
        self.title = title
        self.taskDescription = taskDescription
        self.status = status
        self.phaseName = phaseName
        self.totalSteps = totalSteps
        self.completedSteps = completedSteps
        self.triageSummary = triageSummary
        self.roadmapJSON = roadmapJSON
        self.brdJSON = brdJSON
        self.designBriefJSON = designBriefJSON
        self.cpsJSON = cpsJSON
        self.designStateJSON = designStateJSON
        self.apiCallCount = apiCallCount
        self.estimatedTokens = estimatedTokens
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - v7 Idea Board Models

public enum IdeaStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case analyzing
    case analyzed
    case referencing    // unified reference anchor curation phase
    case converted      // legacy — treated as synonym for .designing
    case designing
    case designed
    case designFailed
}

public struct Idea: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var projectId: UUID
    public var title: String
    public var status: IdeaStatus
    public var messagesJSON: String
    public var designSessionId: UUID?
    public var apiCallCount: Int
    public var totalInputChars: Int
    public var totalOutputChars: Int
    public let createdAt: Date
    public var updatedAt: Date

    /// Estimated token count (input + output chars / 4)
    public var estimatedTokens: Int {
        (totalInputChars + totalOutputChars) / 4
    }

    public init(
        id: UUID = UUID(),
        projectId: UUID,
        title: String,
        status: IdeaStatus = .draft,
        messagesJSON: String = "[]",
        designSessionId: UUID? = nil,
        apiCallCount: Int = 0,
        totalInputChars: Int = 0,
        totalOutputChars: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.status = status
        self.messagesJSON = messagesJSON
        self.designSessionId = designSessionId
        self.apiCallCount = apiCallCount
        self.totalInputChars = totalInputChars
        self.totalOutputChars = totalOutputChars
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - User Profile

public struct UserProfile: Hashable, Codable, Sendable {
    public var name: String
    public var title: String
    public var bio: String

    public init(name: String = "", title: String = "", bio: String = "") {
        self.name = name
        self.title = title
        self.bio = bio
    }

    /// True when the user hasn't filled in any fields yet.
    public var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - App Settings

public struct AppSettings: Hashable, Codable, Sendable {
    /// Hard cap for a single CLI run.
    public var cliTimeoutSeconds: Int
    /// Idle timeout — kill CLI if no new output for this many seconds.
    public var cliIdleTimeoutSeconds: Int
    /// Budget for recent conversation history included in agent prompts. Range: 4000–20000.
    public var contextTokenLimit: Int
    /// UI language code: "en" or "ko". Default is English.
    public var language: String
    /// Maximum number of items elaborated simultaneously during design. Range: 1–10.
    public var elaborationConcurrency: Int

    public init(cliTimeoutSeconds: Int = 600, cliIdleTimeoutSeconds: Int = 300, contextTokenLimit: Int = 8000, language: String = "en", elaborationConcurrency: Int = 5) {
        self.cliTimeoutSeconds = max(30, cliTimeoutSeconds)
        self.cliIdleTimeoutSeconds = max(30, cliIdleTimeoutSeconds)
        self.contextTokenLimit = min(20000, max(4000, contextTokenLimit))
        self.language = language
        self.elaborationConcurrency = max(1, min(10, elaborationConcurrency))
    }
}

// MARK: - Developer Loop

public enum DeveloperLoopCommandKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case build
    case launch
    case verify
    case uiCheck = "ui_check"
    case fullLoop = "full_loop"

    public var id: String { rawValue }
}

public struct DeveloperLoopPreset: Hashable, Codable, Sendable {
    public var title: String
    public var summary: String
    public var buildCommand: String
    public var launchCommand: String
    public var verifyCommand: String
    public var uiCheckCommand: String
    public var uiSnapshotDirectory: String?

    public init(
        title: String,
        summary: String,
        buildCommand: String,
        launchCommand: String,
        verifyCommand: String,
        uiCheckCommand: String,
        uiSnapshotDirectory: String? = nil
    ) {
        self.title = title
        self.summary = summary
        self.buildCommand = buildCommand
        self.launchCommand = launchCommand
        self.verifyCommand = verifyCommand
        self.uiCheckCommand = uiCheckCommand
        self.uiSnapshotDirectory = uiSnapshotDirectory
    }
}

public struct DeveloperLoopRunResult: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let kind: DeveloperLoopCommandKind
    public let succeeded: Bool
    public let command: String
    public let exitCode: Int32
    public let output: String
    public let artifactPath: String?
    public let startedAt: Date
    public let finishedAt: Date

    public init(
        id: UUID = UUID(),
        kind: DeveloperLoopCommandKind,
        succeeded: Bool,
        command: String,
        exitCode: Int32,
        output: String,
        artifactPath: String? = nil,
        startedAt: Date,
        finishedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.succeeded = succeeded
        self.command = command
        self.exitCode = exitCode
        self.output = output
        self.artifactPath = artifactPath
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}

// MARK: - Skills

public struct Skill: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var role: AgentRole
    public var name: String
    public var skillDescription: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        role: AgentRole,
        name: String,
        skillDescription: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.name = name
        self.skillDescription = skillDescription
        self.createdAt = createdAt
    }
}

// MARK: - Provider Config Models

public struct ProviderConfig: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let provider: ProviderKey
    public let status: ProviderStatus
    public let defaultModel: String
    public let enabled: Bool

    public init(
        id: UUID = UUID(),
        provider: ProviderKey,
        status: ProviderStatus,
        defaultModel: String,
        enabled: Bool
    ) {
        self.id = id
        self.provider = provider
        self.status = status
        self.defaultModel = defaultModel
        self.enabled = enabled
    }
}

public struct ProviderValidationResult: Hashable, Codable, Sendable {
    public let provider: ProviderKey
    public let status: ProviderStatus
    public let message: String

    public init(provider: ProviderKey, status: ProviderStatus, message: String) {
        self.provider = provider
        self.status = status
        self.message = message
    }
}

public struct AgentRoleRouting: Identifiable, Hashable, Codable, Sendable {
    public let role: AgentRole
    public let provider: ProviderKey
    public let model: String

    public var id: String { role.rawValue }

    public init(role: AgentRole, provider: ProviderKey, model: String) {
        self.role = role
        self.provider = provider
        self.model = model
    }
}

public struct ProviderCLICommand: Identifiable, Hashable, Codable, Sendable {
    public let provider: ProviderKey
    public let commandTemplate: String
    public let executablePathOverride: String?

    public var id: String { provider.rawValue }

    public init(
        provider: ProviderKey,
        commandTemplate: String,
        executablePathOverride: String? = nil
    ) {
        self.provider = provider
        self.commandTemplate = commandTemplate
        self.executablePathOverride = executablePathOverride
    }
}

// MARK: - Design Event Log

/// Append-only event record for design session audit trail.
public struct DesignEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let sessionId: UUID
    public let eventType: String
    public let payloadJSON: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        eventType: String,
        payloadJSON: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.eventType = eventType
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
    }
}

/// Constants for design event types.
public enum DesignEventType {
    public static let analysisStarted = "analysis_started"
    public static let analysisCompleted = "analysis_completed"
    public static let analysisFailed = "analysis_failed"
    public static let elaborationStarted = "elaboration_started"
    public static let elaborationCompleted = "elaboration_completed"
    public static let elaborationFailed = "elaboration_failed"
    public static let verdictChanged = "verdict_changed"
    public static let itemAdded = "item_added"
    public static let itemRemoved = "item_removed"
    public static let edgeAdded = "edge_added"
    public static let edgeRemoved = "edge_removed"
    public static let workflowCompleted = "workflow_completed"
    public static let deliverablesExported = "deliverables_exported"
    public static let uncertaintyRaised = "uncertainty_raised"
    public static let uncertaintyResolved = "uncertainty_resolved"
    public static let uncertaintyDismissed = "uncertainty_dismissed"
    public static let uncertaintyAutoResolved = "uncertainty_auto_resolved"
    public static let convergenceOscillation = "convergence_oscillation"
}
