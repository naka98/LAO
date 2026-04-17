import Foundation
import LAODomain
import LAOServices

// MARK: - Fallback Agent Runner

/// Result of a fallback agent streaming run.
struct FallbackRunResult: Sendable {
    let response: String
    let agent: Agent
    /// 0 = primary succeeded, >0 = fallback agent succeeded.
    let attemptIndex: Int
    /// Failed attempts before the successful one (for cost tracking).
    let failedAttempts: [FailedAttempt]

    struct FailedAttempt: Sendable {
        let agent: Agent
        let promptLength: Int
    }
}

/// Run a streaming CLI call with automatic fallback across ordered agents.
///
/// Each agent is tried in order. On failure, the next agent is tried.
/// Returns the first successful result along with metadata about failed attempts.
///
/// - Parameters:
///   - agents: Ordered list of agents to try (primary first, fallbacks after).
///   - runner: The CLI agent runner to execute commands.
///   - prompt: The prompt to send to the agent.
///   - jsonSchema: Optional JSON Schema for structured output enforcement.
///   - projectId: The project identifier.
///   - rootPath: The project root path.
///   - onAttemptStart: Called before each attempt on MainActor (for UI updates like agent labels).
///   - streamHandler: Called with accumulated streaming text.
/// - Returns: The successful result including response, agent, and failed attempt history.
func runWithAgentFallback(
    agents: [Agent],
    runner: CLIAgentRunner,
    prompt: String,
    jsonSchema: String? = nil,
    projectId: UUID,
    rootPath: String,
    onAttemptStart: (@Sendable @MainActor (Agent, _ attemptIndex: Int) -> Void)? = nil,
    streamHandler: @Sendable @escaping (String) -> Void
) async throws -> FallbackRunResult {
    guard !agents.isEmpty else {
        throw FallbackRunError.noAgent
    }

    var failedAttempts: [FallbackRunResult.FailedAttempt] = []
    var lastError: Error?

    for (index, agent) in agents.enumerated() {
        do {
            await onAttemptStart?(agent, index)
            let accumulator = StreamAccumulator()
            let response = try await runner.runStreaming(
                agent: agent,
                prompt: prompt,
                projectId: projectId,
                rootPath: rootPath,
                jsonSchema: jsonSchema
            ) { chunk in
                let text = accumulator.append(chunk)
                streamHandler(text)
            }
            return FallbackRunResult(
                response: response,
                agent: agent,
                attemptIndex: index,
                failedAttempts: failedAttempts
            )
        } catch {
            failedAttempts.append(FallbackRunResult.FailedAttempt(
                agent: agent, promptLength: prompt.count
            ))
            lastError = error
            continue
        }
    }
    throw lastError ?? FallbackRunError.noAgent
}

enum FallbackRunError: LocalizedError {
    case noAgent

    var errorDescription: String? {
        "No AI agent is configured. Go to Settings > Agents to set up a provider."
    }
}
