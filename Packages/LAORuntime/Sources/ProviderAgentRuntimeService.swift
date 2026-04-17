import Foundation
import LAODomain
import LAOServices
import os

private let runtimeLog = Logger(subsystem: "com.leeway.lao", category: "Runtime")

public final class ProviderBackedCLIAgentRunner: CLIAgentRunner, @unchecked Sendable {
    private let providerRegistryService: ProviderRegistryService
    private let appSettingsService: AppSettingsService?
    private let environment: [String: String]

    // MARK: - CLI Command Cache
    private var cachedCLICommands: [ProviderKey: ProviderCLICommand]?
    private var cliCommandsCacheTime: Date = .distantPast
    private let cliCommandsCacheLock = NSLock()
    private let cliCommandsCacheTTL: TimeInterval = 60

    public init(
        providerRegistryService: ProviderRegistryService,
        appSettingsService: AppSettingsService? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.providerRegistryService = providerRegistryService
        self.appSettingsService = appSettingsService
        self.environment = environment
    }

    /// Returns cached CLI commands if still valid, otherwise fetches fresh.
    private func resolvedCLICommands() async -> [ProviderKey: ProviderCLICommand] {
        let (cached, isValid) = cliCommandsCacheLock.withLock {
            (cachedCLICommands, Date().timeIntervalSince(cliCommandsCacheTime) < cliCommandsCacheTTL)
        }

        if let cached, isValid { return cached }

        let fresh = Dictionary(
            uniqueKeysWithValues: await providerRegistryService
                .listProviderCLICommands()
                .map { ($0.provider, $0) }
        )
        cliCommandsCacheLock.withLock {
            cachedCLICommands = fresh
            cliCommandsCacheTime = Date()
        }
        return fresh
    }

    public func run(agent: Agent, prompt: String, projectId: UUID, rootPath: String, jsonSchema: String? = nil) async throws -> String {
        let provider = agent.provider
        let model = agent.model

        // Ensure the app has sandbox-scoped access to the project directory.
        if !rootPath.isEmpty {
            SecurityScopedBookmarkStore.shared.startAccessing(path: rootPath)
        }

        let cliCommandByProvider = await resolvedCLICommands()

        guard let commandConfig = commandConfiguration(for: provider, cliCommandByProvider: cliCommandByProvider) else {
            throw ProviderRequestError(status: "missing_cli_command")
        }

        let normalizedTemplate = normalizedCLICommandTemplate(
            provider: provider,
            commandTemplate: commandConfig.commandTemplate
        )
        let executableCommand = applyExecutablePathOverride(
            to: normalizedTemplate,
            executablePathOverride: commandConfig.executablePathOverride
        )

        // Write JSON Schema to a temp file when provided (Codex/Claude use file-based schema injection).
        var schemaFileURL: URL?
        if let schema = jsonSchema, (provider == .codex || provider == .claude) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("lao_schema_\(UUID().uuidString).json")
            try schema.write(to: url, atomically: true, encoding: .utf8)
            schemaFileURL = url
        }
        defer { if let url = schemaFileURL { try? FileManager.default.removeItem(at: url) } }

        // Inject JSON Schema enforcement flags when a schema is provided.
        let finalCommand: String
        if jsonSchema != nil {
            finalCommand = injectSchemaFlags(command: executableCommand, provider: provider, schemaFilePath: schemaFileURL?.path)
        } else {
            finalCommand = executableCommand
        }

        // Write prompt to a temp file so providers can pipe it via stdin,
        // avoiding ARG_MAX limits when the prompt is very large.
        let promptFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lao_prompt_\(UUID().uuidString).txt")
        try prompt.write(to: promptFileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: promptFileURL) }

        runtimeLog.debug("CLI run command: \(finalCommand.prefix(300), privacy: .public)")

        let execution = try await executeShell(
            finalCommand,
            workingDirectory: rootPath.isEmpty ? nil : rootPath,
            extraEnvironment: [
                "LAO_PROVIDER": provider.rawValue,
                "LAO_MODEL": model,
                "LAO_PROMPT_FILE": promptFileURL.path,
                "LAO_TIER": agent.tier.rawValue,
                "LAO_PROJECT_ID": projectId.uuidString,
            ]
        )

        if execution.exitCode != 0 {
            try throwCLIExitError(execution: execution, agent: agent)
        }

        let stdoutOutput = execution.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdoutOutput.isEmpty {
            // When --json-schema + --output-format json is used, stdout is a JSON wrapper.
            // Extract structured_output if present; fall back to result or raw text.
            if jsonSchema != nil, provider == .claude,
               let data = stdoutOutput.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let so = json["structured_output"] {
                    if let soString = so as? String, !soString.isEmpty {
                        return soString
                    }
                    if let soObj = so as? [String: Any],
                       let soData = try? JSONSerialization.data(withJSONObject: soObj),
                       let soString = String(data: soData, encoding: .utf8) {
                        return soString
                    }
                }
                if let result = json["result"] as? String, !result.isEmpty {
                    return result
                }
            }
            return stdoutOutput
        }

        let stderrOutput = execution.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderrOutput.isEmpty {
            return stderrOutput
        }

        throw ProviderRequestError(status: "empty_cli_output")
    }

    // MARK: - Streaming Run

    public func runStreaming(
        agent: Agent,
        prompt: String,
        projectId: UUID,
        rootPath: String,
        jsonSchema: String? = nil,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let provider = agent.provider
        let model = agent.model

        if !rootPath.isEmpty {
            SecurityScopedBookmarkStore.shared.startAccessing(path: rootPath)
        }

        let cliCommandByProvider = await resolvedCLICommands()

        guard let commandConfig = commandConfiguration(for: provider, cliCommandByProvider: cliCommandByProvider) else {
            throw ProviderRequestError(status: "missing_cli_command")
        }

        let normalizedTemplate = normalizedCLICommandTemplate(
            provider: provider,
            commandTemplate: commandConfig.commandTemplate
        )
        let executableCommand = applyExecutablePathOverride(
            to: normalizedTemplate,
            executablePathOverride: commandConfig.executablePathOverride
        )

        // Provider-specific: inject streaming output format flags
        let usesJSONLParsing = (provider == .claude || provider == .codex)
        let streamingCommand = injectStreamingFlags(command: executableCommand, provider: provider)

        // Write JSON Schema to a temp file when provided (Codex/Claude use file-based schema injection).
        var schemaFileURL: URL?
        if let schema = jsonSchema, (provider == .codex || provider == .claude) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("lao_schema_\(UUID().uuidString).json")
            try schema.write(to: url, atomically: true, encoding: .utf8)
            schemaFileURL = url
        }
        defer { if let url = schemaFileURL { try? FileManager.default.removeItem(at: url) } }

        // Inject JSON Schema enforcement flags when a schema is provided.
        let finalCommand: String
        if jsonSchema != nil {
            finalCommand = injectSchemaFlags(command: streamingCommand, provider: provider, schemaFilePath: schemaFileURL?.path)
        } else {
            finalCommand = streamingCommand
        }

        // For Claude/Codex: parse JSONL events to extract text deltas
        // For Gemini: pass raw stdout through (already streams text)
        let streamParser: CLIStreamLineParser? = usesJSONLParsing
            ? CLIStreamLineParser(provider: provider, onText: onChunk)
            : nil

        let chunkHandler: @Sendable (String) -> Void
        if let sp = streamParser {
            chunkHandler = { chunk in sp.feed(chunk) }
        } else {
            chunkHandler = onChunk
        }

        // Write prompt to a temp file so providers can pipe it via stdin,
        // avoiding ARG_MAX limits when the prompt is very large.
        let promptFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("lao_prompt_\(UUID().uuidString).txt")
        try prompt.write(to: promptFileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: promptFileURL) }

        runtimeLog.debug("CLI stream command: \(finalCommand.prefix(300), privacy: .public)")

        let execution = try await executeShell(
            finalCommand,
            workingDirectory: rootPath.isEmpty ? nil : rootPath,
            extraEnvironment: [
                "LAO_PROVIDER": provider.rawValue,
                "LAO_MODEL": model,
                "LAO_PROMPT_FILE": promptFileURL.path,
                "LAO_TIER": agent.tier.rawValue,
                "LAO_PROJECT_ID": projectId.uuidString,
            ],
            onStdoutChunk: chunkHandler
        )

        if execution.exitCode != 0 {
            try throwCLIExitError(execution: execution, agent: agent, streamParser: streamParser)
        }

        // For JSONL providers, use reconstructed text from parsed events.
        // Avoid returning the raw JSON event stream as the final assistant message.
        if let sp = streamParser {
            let parsed = sp.finalText().trimmingCharacters(in: .whitespacesAndNewlines)
            if !parsed.isEmpty { return parsed }
        }

        let stdoutOutput = execution.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdoutOutput.isEmpty {
            if !usesJSONLParsing || !Self.looksLikeJSONEventStream(stdoutOutput) {
                return stdoutOutput
            }
        }

        let stderrOutput = execution.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderrOutput.isEmpty { return stderrOutput }

        throw ProviderRequestError(status: "empty_cli_output")
    }

    private static func looksLikeJSONEventStream(_ output: String) -> Bool {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("\"type\":\"thread.started\"")
            || trimmed.contains("\"type\":\"turn.started\"")
            || trimmed.contains("\"type\":\"item.completed\"")
            || trimmed.contains("\"type\":\"turn.completed\"") {
            return true
        }

        let lines = trimmed
            .split(whereSeparator: \.isNewline)
            .prefix(5)
        guard !lines.isEmpty else { return false }
        return lines.allSatisfy { line in
            let candidate = line.trimmingCharacters(in: .whitespaces)
            return candidate.hasPrefix("{") && candidate.hasSuffix("}")
        }
    }

    /// Inject provider-specific flags for streaming JSONL output.
    func injectStreamingFlags(command: String, provider: ProviderKey) -> String {
        var cmd = command
        switch provider {
        case .claude:
            // Claude partial text arrives only when stream-json is paired with partial messages.
            var flagsToInsert = ""
            if !cmd.contains("--verbose") {
                flagsToInsert += " --verbose"
            }
            if !cmd.contains("--include-partial-messages") {
                flagsToInsert += " --include-partial-messages"
            }
            if !cmd.contains("--output-format") {
                flagsToInsert += " --output-format stream-json"
            }

            if !flagsToInsert.isEmpty {
                if let range = cmd.range(of: "--dangerously-skip-permissions") {
                    cmd.insert(contentsOf: flagsToInsert, at: range.upperBound)
                } else if let range = cmd.range(of: "claude") {
                    cmd.insert(contentsOf: flagsToInsert, at: range.upperBound)
                }
            }
        case .codex:
            // Add --json for JSONL event streaming
            if !cmd.contains("--json") {
                if let range = cmd.range(of: "codex exec") {
                    cmd.insert(contentsOf: " --json", at: range.upperBound)
                }
            }
        case .gemini:
            break // Already streams text by default
        }
        return cmd
    }

    /// Inject provider-specific flags for JSON Schema enforcement.
    /// Called by both `run()` and `runStreaming()` when a schema is provided.
    ///
    /// - Parameter schemaFilePath: Temp file path containing the JSON Schema (used by Codex and Claude).
    func injectSchemaFlags(command: String, provider: ProviderKey, schemaFilePath: String?) -> String {
        var cmd = command
        switch provider {
        case .codex:
            // Codex CLI: --output-schema expects a file path to a JSON Schema file.
            guard let filePath = schemaFilePath else { return cmd }
            if !cmd.contains("--output-schema") {
                if let range = cmd.range(of: "codex exec") {
                    cmd.insert(contentsOf: " --output-schema '\(filePath)'", at: range.upperBound)
                }
            }
        case .claude:
            // Claude CLI: --json-schema forces the LLM to return valid JSON matching the schema.
            // Uses $(cat file) to avoid ARG_MAX issues with large inline JSON.
            // --output-format json is required for non-streaming calls; stream-json (already injected
            // by injectStreamingFlags in the streaming path) also works.
            guard let filePath = schemaFilePath else { return cmd }
            if !cmd.contains("--json-schema") {
                let schemaFlag = " --json-schema \"$(cat '\(filePath)')\""
                if let range = cmd.range(of: "--dangerously-skip-permissions") {
                    cmd.insert(contentsOf: schemaFlag, at: range.upperBound)
                } else if let range = cmd.range(of: "claude") {
                    cmd.insert(contentsOf: schemaFlag, at: range.upperBound)
                }
            }
            // Ensure --output-format is present (json for non-streaming, stream-json for streaming).
            if !cmd.contains("--output-format") {
                cmd += " --output-format json"
            }
        case .gemini:
            break // No CLI-level schema enforcement available
        }
        return cmd
    }

    // MARK: - Command Configuration

    private struct CLICommandConfiguration {
        let commandTemplate: String
        let executablePathOverride: String?
    }

    private func commandConfiguration(
        for provider: ProviderKey,
        cliCommandByProvider: [ProviderKey: ProviderCLICommand]
    ) -> CLICommandConfiguration? {
        if let configured = cliCommandByProvider[provider] {
            let commandTemplate = configured.commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !commandTemplate.isEmpty {
                let path = configured.executablePathOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedPath = path?.isEmpty == true ? nil : path
                return CLICommandConfiguration(
                    commandTemplate: commandTemplate,
                    executablePathOverride: normalizedPath
                )
            }
        }

        let fallbackCommand: String?
        switch provider {
        case .codex:
            fallbackCommand = environment["LAO_PROVIDER_CODEX_CLI"]
        case .claude:
            fallbackCommand = environment["LAO_PROVIDER_CLAUDE_CLI"]
        case .gemini:
            fallbackCommand = environment["LAO_PROVIDER_GEMINI_CLI"]
        }

        guard let fallbackCommand = fallbackCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
              !fallbackCommand.isEmpty else {
            return nil
        }
        return CLICommandConfiguration(commandTemplate: fallbackCommand, executablePathOverride: nil)
    }

    func normalizedCLICommandTemplate(
        provider: ProviderKey,
        commandTemplate: String
    ) -> String {
        var normalized = commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider == .gemini {
            // Auto-approve file writes in headless mode (equivalent to Claude's --dangerously-skip-permissions).
            // --yolo enables sandbox by default (requires Docker/Podman), so we explicitly
            // disable it with --sandbox false to run directly on the host filesystem.
            if !normalized.contains("--yolo") && !normalized.contains("--approval-mode"),
               normalized.contains("gemini") {
                normalized = normalized.replacingOccurrences(
                    of: "gemini",
                    with: "gemini --yolo --sandbox false",
                    range: normalized.range(of: "gemini")
                )
            }
            let hasPromptArg = normalized.contains("--prompt") || normalized.contains(" -p ")
            if !hasPromptArg, normalized.contains("gemini") {
                // Pipe the prompt from a temp file via stdin instead of passing it as
                // a command-line argument.  This avoids exceeding macOS ARG_MAX when
                // the prompt is very large (e.g. multi-step Design plans).
                normalized = "cat \"$LAO_PROMPT_FILE\" | " + normalized
            } else if normalized.contains("\"$LAO_PROMPT\"") {
                // Legacy template used $LAO_PROMPT (no longer set); replace with file read.
                normalized = normalized
                    .replacingOccurrences(of: "\"$LAO_PROMPT\"", with: "\"$(cat \"$LAO_PROMPT_FILE\")\"")
            }
            return normalized
        }

        // Claude CLI: allow tool use without interactive permission prompts
        if provider == .claude {
            if !normalized.contains("--dangerously-skip-permissions"),
               normalized.contains("claude") {
                normalized = normalized.replacingOccurrences(
                    of: "claude",
                    with: "claude --dangerously-skip-permissions --allowedTools Bash",
                    range: normalized.range(of: "claude")
                )
            } else if !normalized.contains("--allowedTools"),
                      let range = normalized.range(of: "--dangerously-skip-permissions") {
                // Already has --dangerously-skip-permissions added previously — append Bash allowance
                normalized.replaceSubrange(range, with: "--dangerously-skip-permissions --allowedTools Bash")
            }
            // Replace inline $LAO_PROMPT with a file-read so the prompt travels
            // through argv at exec-time (read from a small temp file) rather than
            // being baked into the environment.  Combined with the removal of
            // LAO_PROMPT from extraEnvironment this keeps total exec size well
            // within macOS ARG_MAX (~1 MB).
            let hasPromptFlag = normalized.contains(" -p ") || normalized.contains(" --prompt ")
            if !hasPromptFlag, !normalized.contains("$LAO_PROMPT_FILE") {
                normalized += " -p \"$(cat \"$LAO_PROMPT_FILE\")\""
            } else {
                normalized = normalized
                    .replacingOccurrences(of: "\"$LAO_PROMPT\"", with: "\"$(cat \"$LAO_PROMPT_FILE\")\"")
            }
            return normalized
        }

        guard provider == .codex else { return normalized }

        // Ensure `codex exec` subcommand exists
        if !normalized.contains("codex exec") {
            if let range = normalized.range(of: "codex ") {
                normalized.replaceSubrange(range, with: "codex exec ")
            }
        }

        // Override unsupported global defaults like `model_reasoning_effort = "xhigh"`
        // with a Codex-compatible value unless the command already specifies one.
        if !normalized.contains("model_reasoning_effort")
            && !normalized.contains("reasoning.effort"),
           let range = normalized.range(of: "codex exec") {
            normalized.replaceSubrange(range, with: "codex exec -c model_reasoning_effort='high'")
        }

        // Inject required flags if missing
        if !normalized.contains("--skip-git-repo-check"),
           let range = normalized.range(of: "codex exec") {
            normalized.replaceSubrange(range, with: "codex exec --skip-git-repo-check")
        }
        // Allow writing to workspace (default is read-only sandbox)
        if !normalized.contains("-s ") && !normalized.contains("--sandbox"),
           let range = normalized.range(of: "codex exec") {
            normalized.replaceSubrange(range, with: "codex exec -s workspace-write")
        }

        // Replace inline $LAO_PROMPT with a file-read so the prompt travels
        // through argv at exec-time rather than the environment.
        let hasPromptArg = normalized.contains("\"$LAO_PROMPT\"")
        if hasPromptArg {
            normalized = normalized
                .replacingOccurrences(of: "\"$LAO_PROMPT\"", with: "\"$(cat \"$LAO_PROMPT_FILE\")\"")
        } else if !normalized.contains("$LAO_PROMPT_FILE") {
            // No prompt placeholder found — append as positional arg
            normalized += " \"$(cat \"$LAO_PROMPT_FILE\")\""
        }

        return normalized
    }

    private func applyExecutablePathOverride(
        to commandTemplate: String,
        executablePathOverride: String?
    ) -> String {
        guard let overridePath = executablePathOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
              !overridePath.isEmpty,
              let tokenRange = leadingCommandTokenRange(in: commandTemplate)
        else {
            return commandTemplate
        }

        var replaced = commandTemplate
        replaced.replaceSubrange(tokenRange, with: shellSingleQuoted(overridePath))
        return replaced
    }

    private func leadingCommandTokenRange(in command: String) -> Range<String.Index>? {
        var start = command.startIndex
        while start < command.endIndex, command[start] == " " || command[start] == "\t" {
            start = command.index(after: start)
        }
        guard start < command.endIndex else { return nil }

        let first = command[start]
        if first == "\"" || first == "'" {
            var cursor = command.index(after: start)
            while cursor < command.endIndex {
                if command[cursor] == first {
                    return start..<command.index(after: cursor)
                }
                cursor = command.index(after: cursor)
            }
            return start..<command.endIndex
        }

        var cursor = start
        while cursor < command.endIndex, command[cursor] != " ", command[cursor] != "\t" {
            cursor = command.index(after: cursor)
        }
        return start..<cursor
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    // MARK: - CLI Exit Error

    /// Build and throw a `ProviderRequestError` from a non-zero CLI exit.
    /// Centralizes the exit-code error path shared by `run()` and `runStreaming()`.
    private func throwCLIExitError(
        execution: ShellExecutionResult,
        agent: Agent,
        streamParser: CLIStreamLineParser? = nil
    ) throws -> Never {
        let stderr = execution.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = execution.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var combinedParts: [String] = []
        if let streamError = streamParser?.capturedErrorMessage() {
            combinedParts.append(streamError)
        }
        if !stderr.isEmpty { combinedParts.append(stderr) }
        if !stdout.isEmpty { combinedParts.append(stdout) }
        let combinedOutput = combinedParts.joined(separator: "\n")
        let status = statusFromCLIError(exitCode: execution.exitCode, stderr: stderr, stdout: stdout)
        let label = "\(agent.provider.rawValue)/\(agent.model)"
        throw ProviderRequestError(status: status, detail: combinedOutput.isEmpty ? nil : combinedOutput, agentLabel: label)
    }

    // MARK: - Error Classification

    func statusFromCLIError(exitCode: Int32, stderr: String, stdout: String = "") -> String {
        let diagnosticOutput = classificationOutput(stderr: stderr, stdout: stdout)
        let normalized = diagnosticOutput.lowercased()
        let fullOutput = [stderr, stdout]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .lowercased()

        // Shared pattern matching — applied to both timeouts and normal exits.
        // Check the output for recognizable error patterns regardless of exit code,
        // so that a timeout caused by an auth hang still reports "auth_failed".
        if isTopLevelCLINotFound(normalized, fullOutput: fullOutput) {
            return "cli_not_found"
        }
        if normalized.contains("rate limit") || normalized.contains("too many requests")
            || normalized.contains("capacity") || normalized.contains("resource_exhausted") {
            return "rate_limited"
        }
        if isMCPAuthFailure(normalized) {
            return "mcp_auth_failed"
        }
        if normalized.contains("authentication failed")
            || normalized.contains("failed to authenticate")
            || normalized.contains("authentication_error")
            || normalized.contains("token has expired")
            || normalized.contains("check your api key or login status")
            || normalized.contains("invalid api key")
            || normalized.contains("incorrect api key")
            || normalized.contains("not logged in")
            || normalized.contains("login required")
            || normalized.contains("unauthorized")
            || normalized.contains("forbidden") {
            return "auth_failed"
        }
        if normalized.contains("not supported") || normalized.contains("model not found")
            || normalized.contains("does not exist") || normalized.contains("invalid model")
            || normalized.contains("modelnotfounderror") || normalized.contains("unknown model") {
            return "model_not_supported"
        }
        if normalized.contains("permission denied") || normalized.contains("read-only")
            || normalized.contains("operation not permitted") {
            return "permission_denied"
        }

        if normalized.contains("waiting for initial output") {
            return "cli_timeout_no_output"
        }
        if normalized.contains("became idle") || normalized.contains("max runtime") {
            return "cli_timeout_slow"
        }

        // Exit code -1 means our timer killed the process (timeout).
        if exitCode == -1 {
            // Distinguish: CLI was working (partial output on stdout or stderr)
            // vs never started (no output at all).
            // Codex CLI logs startup activity (MCP servers, file reads) to stderr
            // while stdout stays empty until the final response, so we must check both.
            // Exclude our own injected "CLI timed out" message from the stderr check.
            let hasStdout = !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let realStderr = normalized
                .replacingOccurrences(of: "cli timed out after \\d+s", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let hasRealStderr = !realStderr.isEmpty
            return (hasStdout || hasRealStderr) ? "cli_timeout_slow" : "cli_timeout_no_output"
        }

        if normalized.contains("timed out") || normalized.contains("cli timed out") {
            return "cli_timeout_slow"
        }

        return "cli_exit_\(exitCode)"
    }

    private func classificationOutput(stderr: String, stdout: String) -> String {
        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStderr.isEmpty {
            return trimmedStderr
        }

        let lines = stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let diagnosticLines = lines.filter { line in
            let lowercased = line.lowercased()
            guard !looksLikeConversationTranscript(line) else { return false }
            return lowercased.contains("error")
                || lowercased.contains("failed")
                || lowercased.contains("unauthorized")
                || lowercased.contains("forbidden")
                || lowercased.contains("invalid")
                || lowercased.contains("timed out")
                || lowercased.contains("permission denied")
                || lowercased.hasPrefix("mcp:")
        }

        if !diagnosticLines.isEmpty {
            return diagnosticLines.suffix(20).joined(separator: "\n")
        }

        return lines.suffix(20).joined(separator: "\n")
    }

    private func looksLikeConversationTranscript(_ line: String) -> Bool {
        line.hasPrefix("[") && line.contains("]:")
    }

    private func isMCPAuthFailure(_ normalized: String) -> Bool {
        let hasMCPMarker = normalized.contains("mcp:")
            || normalized.contains("mcp client")
            || normalized.contains("mcp startup")
        guard hasMCPMarker else { return false }

        return normalized.contains("auth error")
            || normalized.contains("token refresh failed")
            || normalized.contains("invalid refresh token")
            || normalized.contains("invalid_grant")
            || normalized.contains("oauth")
    }

    private func isTopLevelCLINotFound(_ normalized: String, fullOutput: String) -> Bool {
        let hasMissingExecutableMarker = normalized.contains("command not found")
            || normalized.contains("not recognized")
            || normalized.contains("no such file or directory")
        guard hasMissingExecutableMarker else { return false }
        return !containsProviderStartupMarkers(fullOutput)
    }

    private func containsProviderStartupMarkers(_ normalized: String) -> Bool {
        normalized.contains("openai codex v")
            || normalized.contains("workdir:")
            || normalized.contains("model:")
            || normalized.contains("provider:")
            || normalized.contains("approval:")
            || normalized.contains("sandbox:")
            || normalized.contains("reasoning effort:")
            || normalized.contains("reasoning summaries:")
            || normalized.contains("session id:")
            || normalized.contains("mcp:")
    }

    // MARK: - Shell Execution

    /// Hard cap for a single CLI run. Startup and idle timeouts are handled separately.
    /// Priority: LAO_CLI_TIMEOUT env var > Settings DB value > default (600s).
    static let cliTimeoutValue: TimeInterval = 600
    static let cliStartupTimeoutValue: TimeInterval = 120
    static let cliInactivityTimeoutValue: TimeInterval = 300

    private func resolveHardTimeout() async -> TimeInterval {
        // 1. Environment variable takes highest priority
        if let envStr = ProcessInfo.processInfo.environment["LAO_CLI_TIMEOUT"],
           let seconds = TimeInterval(envStr), seconds > 0 {
            return seconds
        }
        // 2. Persisted settings from DB
        if let service = appSettingsService {
            let settings = await service.getSettings()
            return TimeInterval(settings.cliTimeoutSeconds)
        }
        // 3. Default
        return Self.cliTimeoutValue
    }

    private func resolveStartupTimeout(hardTimeout: TimeInterval) -> TimeInterval {
        if let envStr = ProcessInfo.processInfo.environment["LAO_CLI_STARTUP_TIMEOUT"],
           let seconds = TimeInterval(envStr), seconds > 0 {
            return min(seconds, hardTimeout)
        }
        return min(Self.cliStartupTimeoutValue, hardTimeout)
    }

    private func resolveInactivityTimeout(hardTimeout: TimeInterval) async -> TimeInterval {
        if let envStr = ProcessInfo.processInfo.environment["LAO_CLI_IDLE_TIMEOUT"],
           let seconds = TimeInterval(envStr), seconds > 0 {
            return min(seconds, hardTimeout)
        }
        if let service = appSettingsService {
            let settings = await service.getSettings()
            return min(TimeInterval(settings.cliIdleTimeoutSeconds), hardTimeout)
        }
        return min(Self.cliInactivityTimeoutValue, hardTimeout)
    }

    private func executeShell(
        _ command: String,
        workingDirectory: String? = nil,
        extraEnvironment: [String: String],
        onStdoutChunk: (@Sendable (String) -> Void)? = nil
    ) async throws -> ShellExecutionResult {
        let hardTimeout = await resolveHardTimeout()
        let startupTimeout = resolveStartupTimeout(hardTimeout: hardTimeout)
        let inactivityTimeout = await resolveInactivityTimeout(hardTimeout: hardTimeout)
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdoutCollector = ShellOutputCollector()
            let stderrCollector = ShellOutputCollector()
            let resumeGuard = ResumeOnce()
            let timeoutCoordinator = ShellTimeoutCoordinator()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            if let dir = workingDirectory, FileManager.default.fileExists(atPath: dir) {
                process.currentDirectoryURL = URL(fileURLWithPath: dir)
            } else {
                process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            }

            var mergedEnvironment = environment
            for (key, value) in extraEnvironment {
                mergedEnvironment[key] = value
            }
            let effectivePath = normalizedExecutablePATH(current: mergedEnvironment["PATH"])
            mergedEnvironment["PATH"] = effectivePath
            process.environment = mergedEnvironment
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let activityTimer = DispatchSource.makeTimerSource()
            let hardTimer = DispatchSource.makeTimerSource()

            func finishWithTimeout(kind: ShellTimeoutKind) {
                if process.isRunning { process.terminate() }
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                activityTimer.cancel()
                hardTimer.cancel()
                if resumeGuard.tryConsume() {
                    let stdout = String(decoding: stdoutCollector.snapshot(), as: UTF8.self)
                    let stderr = String(decoding: stderrCollector.snapshot(), as: UTF8.self)
                    let timeoutMessage = kind.message(
                        startupTimeout: startupTimeout,
                        inactivityTimeout: inactivityTimeout,
                        hardTimeout: hardTimeout
                    )
                    let combinedStderr = [stderr, timeoutMessage]
                        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        .joined(separator: "\n")
                    continuation.resume(
                        returning: ShellExecutionResult(
                            exitCode: -1,
                            stdout: stdout,
                            stderr: combinedStderr
                        )
                    )
                }
            }

            let stdoutDecoder = UTF8ChunkDecoder()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stdoutCollector.append(chunk)
                timeoutCoordinator.recordActivity(
                    on: activityTimer,
                    inactivityTimeout: inactivityTimeout,
                    hardTimer: hardTimer
                )
                if let callback = onStdoutChunk,
                   let text = stdoutDecoder.decode(chunk) {
                    callback(text)
                }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                stderrCollector.append(chunk)
                timeoutCoordinator.recordActivity(
                    on: activityTimer,
                    inactivityTimeout: inactivityTimeout,
                    hardTimer: hardTimer
                )
            }

            // Startup/idle timeout: before first activity it waits for initial output,
            // after any stdout/stderr activity it becomes an inactivity timeout.
            activityTimer.schedule(deadline: .now() + startupTimeout)
            activityTimer.setEventHandler {
                guard let kind = timeoutCoordinator.consumeActivityTimeoutKind() else { return }
                finishWithTimeout(kind: kind)
            }

            // Hard cap: always terminate runs that exceed the maximum total runtime.
            hardTimer.schedule(deadline: .now() + hardTimeout)
            hardTimer.setEventHandler {
                guard timeoutCoordinator.consumeHardTimeout() else { return }
                finishWithTimeout(kind: .hardCap)
            }
            activityTimer.resume()
            hardTimer.resume()

            process.terminationHandler = { finished in
                timeoutCoordinator.markFinished()
                activityTimer.cancel()
                hardTimer.cancel()
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let stdoutRemaining = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrRemaining = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                stdoutCollector.append(stdoutRemaining)
                stderrCollector.append(stderrRemaining)

                // Forward remaining stdout to the streaming callback so the
                // stream parser can process any data that arrived after the
                // readabilityHandler was cleared.
                if let callback = onStdoutChunk {
                    if !stdoutRemaining.isEmpty,
                       let text = stdoutDecoder.decode(stdoutRemaining) {
                        callback(text)
                    }
                    // Flush any incomplete trailing bytes from previous chunks.
                    if let flushed = stdoutDecoder.flush() {
                        callback(flushed)
                    }
                }

                if resumeGuard.tryConsume() {
                    continuation.resume(
                        returning: ShellExecutionResult(
                            exitCode: finished.terminationStatus,
                            stdout: String(decoding: stdoutCollector.snapshot(), as: UTF8.self),
                            stderr: String(decoding: stderrCollector.snapshot(), as: UTF8.self)
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                timeoutCoordinator.markFinished()
                activityTimer.cancel()
                hardTimer.cancel()
                if resumeGuard.tryConsume() {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func normalizedExecutablePATH(current: String?) -> String {
        // NSHomeDirectory() returns the sandbox container path in sandboxed apps.
        // We need the real user home for CLI tools installed via brew/npm/etc.
        let sandboxHome = NSHomeDirectory()
        let realHome = ProcessInfo.processInfo.environment["HOME"]
            ?? (getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir) })
            ?? sandboxHome

        var defaults = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(realHome)/.local/bin",
        ]
        // If sandbox home differs from real home, also add the sandbox path
        if sandboxHome != realHome {
            defaults.append("\(sandboxHome)/.local/bin")
        }

        var seen = Set<String>()
        var ordered: [String] = []

        for entry in (current ?? "").split(separator: ":").map(String.init) {
            guard !entry.isEmpty, !seen.contains(entry) else { continue }
            seen.insert(entry)
            ordered.append(entry)
        }

        for entry in defaults {
            guard !seen.contains(entry) else { continue }
            seen.insert(entry)
            ordered.append(entry)
        }

        return ordered.joined(separator: ":")
    }
}

// MARK: - JSONL Stream Parser

/// Parses JSONL (newline-delimited JSON) events from Claude `--output-format stream-json`
/// and Codex `--json` to extract incremental text for real-time streaming.
/// Gemini streams plain text — no parsing needed.
final class CLIStreamLineParser: @unchecked Sendable {
    private let provider: ProviderKey
    private let onText: @Sendable (String) -> Void
    private var lineBuffer = ""
    private var accumulatedText = ""
    private var emittedSnapshotCount = 0
    private var lastSnapshotText = ""
    private var lastErrorMessage: String?
    /// JSON Schema structured output from the final result event (Claude --json-schema).
    private var structuredOutput: String?
    private let lock = NSLock()

    init(provider: ProviderKey, onText: @escaping @Sendable (String) -> Void) {
        self.provider = provider
        self.onText = onText
    }

    /// Feed a raw stdout chunk. Complete lines are parsed; partial lines are buffered.
    func feed(_ chunk: String) {
        var displayUpdates: [String] = []
        lock.lock()
        lineBuffer += chunk

        while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[lineBuffer.startIndex..<newlineIndex])
            lineBuffer = String(lineBuffer[lineBuffer.index(after: newlineIndex)...])
            applyParsedOutput(from: line, collectingInto: &displayUpdates)
        }
        lock.unlock()

        for update in displayUpdates {
            onText(update)
        }
    }

    /// The full text reconstructed from parsed events.
    /// When `--json-schema` was used, prefers the structured output over accumulated text.
    func finalText() -> String {
        var displayUpdates: [String] = []
        lock.lock()
        if !lineBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            applyParsedOutput(from: lineBuffer, collectingInto: &displayUpdates)
            lineBuffer.removeAll()
        }
        // Prefer structured_output (from --json-schema) over accumulated natural language text.
        let result = structuredOutput ?? accumulatedText
        lock.unlock()

        for update in displayUpdates {
            onText(update)
        }
        return result
    }

    /// Error message captured from a provider error event (e.g. Claude `type: "error"`).
    /// Only meaningful when the CLI exits with a non-zero code.
    func capturedErrorMessage() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return lastErrorMessage
    }

    // MARK: - Per-provider extraction

    private enum DisplayUpdate {
        case delta(String)
        case snapshot(String)
    }

    private struct ParsedStreamOutput {
        let displayUpdate: DisplayUpdate?
        let finalDelta: String?
        let finalMessage: String?
    }

    private func applyParsedOutput(from line: String, collectingInto updates: inout [String]) {
        guard let parsed = extractOutput(from: line) else { return }
        if let delta = parsed.finalDelta {
            accumulatedText += delta
        }
        if let message = parsed.finalMessage {
            // Only replace accumulated text if the final message is at least as long,
            // preventing a short trailing agent_message from discarding prior content.
            if message.count >= accumulatedText.count {
                accumulatedText = message
            } else {
                let accLen = accumulatedText.count
                runtimeLog.warning("Skipped short finalMessage (\(message.count, privacy: .public)) — keeping accumulated (\(accLen, privacy: .public))")
            }
        }
        if let display = formattedDisplayChunk(for: parsed.displayUpdate) {
            updates.append(display)
        }
    }

    private func extractOutput(from line: String) -> ParsedStreamOutput? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.hasPrefix("{") else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        switch provider {
        case .claude:  return extractClaudeText(json)
        case .codex:   return extractCodexOutput(json)
        case .gemini:  return nil
        }
    }

    /// Claude `--output-format stream-json` format:
    /// `{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"..."}}`
    private func extractClaudeText(_ json: [String: Any]) -> ParsedStreamOutput? {
        if let type = json["type"] as? String, type == "stream_event",
           let event = json["event"] as? [String: Any] {
            return extractClaudeStreamEvent(event)
        }

        // Legacy direct content_block_delta
        if let type = json["type"] as? String, type == "content_block_delta",
           let delta = json["delta"] as? [String: Any],
           let deltaType = delta["type"] as? String, deltaType == "text_delta",
           let text = delta["text"] as? String {
            return ParsedStreamOutput(displayUpdate: .delta(text), finalDelta: text, finalMessage: nil)
        }

        // Final assistant payload with completed text blocks
        if let type = json["type"] as? String, type == "assistant",
           let message = json["message"] as? [String: Any] {
            // Detect synthetic/failed responses that indicate the API call was never made
            if let model = message["model"] as? String, model == "<synthetic>" {
                lastErrorMessage = "Provider returned a synthetic response — verify API key and provider settings."
            }
            if let content = message["content"] as? [[String: Any]] {
                let text = content
                    .compactMap { block -> String? in
                        guard let blockType = block["type"] as? String, blockType == "text" else { return nil }
                        return block["text"] as? String
                    }
                    .joined()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    let shouldDisplay = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    return ParsedStreamOutput(
                        displayUpdate: shouldDisplay ? .snapshot(text) : nil,
                        finalDelta: nil,
                        finalMessage: text
                    )
                }
            }
        }

        // Wrapped in result message (final event with full text)
        if let type = json["type"] as? String, type == "result" {
            // --json-schema: structured_output contains the schema-validated JSON
            if let so = json["structured_output"] {
                if let soString = so as? String, !soString.isEmpty {
                    structuredOutput = soString
                } else if let soDict = so as? [String: Any],
                          let soData = try? JSONSerialization.data(withJSONObject: soDict),
                          let soString = String(data: soData, encoding: .utf8) {
                    structuredOutput = soString
                }
            }
            if let result = json["result"] as? String, !result.isEmpty {
                // Only use this if we haven't accumulated anything yet (fallback)
                let isEmpty = accumulatedText.isEmpty
                return isEmpty
                    ? ParsedStreamOutput(displayUpdate: nil, finalDelta: nil, finalMessage: result)
                    : nil
            }
        }

        // Error event: {"type":"error","error":{"type":"...","message":"..."}}
        if let type = json["type"] as? String, type == "error",
           let errorObj = json["error"] as? [String: Any],
           let message = errorObj["message"] as? String {
            lastErrorMessage = message
            return nil
        }

        return nil
    }

    private func extractClaudeStreamEvent(_ event: [String: Any]) -> ParsedStreamOutput? {
        guard let type = event["type"] as? String else { return nil }

        if type == "content_block_delta",
           let delta = event["delta"] as? [String: Any],
           let deltaType = delta["type"] as? String, deltaType == "text_delta",
           let text = delta["text"] as? String {
            return ParsedStreamOutput(displayUpdate: .delta(text), finalDelta: text, finalMessage: nil)
        }

        // Error event nested inside stream_event wrapper
        if type == "error",
           let errorObj = event["error"] as? [String: Any],
           let message = errorObj["message"] as? String {
            lastErrorMessage = message
            return nil
        }

        // Result event nested inside stream_event wrapper (--json-schema final output)
        if type == "result" {
            if let so = event["structured_output"] {
                if let soString = so as? String, !soString.isEmpty {
                    structuredOutput = soString
                } else if let soDict = so as? [String: Any],
                          let soData = try? JSONSerialization.data(withJSONObject: soDict),
                          let soString = String(data: soData, encoding: .utf8) {
                    structuredOutput = soString
                }
            }
            if let result = event["result"] as? String, !result.isEmpty {
                let isEmpty = accumulatedText.isEmpty
                return isEmpty
                    ? ParsedStreamOutput(displayUpdate: nil, finalDelta: nil, finalMessage: result)
                    : nil
            }
            return nil
        }

        return nil
    }

    /// Codex `--json` JSONL format:
    /// includes both delta events and completed items.
    private func extractCodexOutput(_ json: [String: Any]) -> ParsedStreamOutput? {
        guard let type = json["type"] as? String else { return nil }

        // "item.output_text.delta" contains incremental text
        if type == "item.output_text.delta",
           let text = json["text"] as? String {
            return ParsedStreamOutput(displayUpdate: .delta(text), finalDelta: text, finalMessage: nil)
        }

        // "response.output_text.delta"
        if type == "response.output_text.delta",
           let delta = json["delta"] as? String {
            return ParsedStreamOutput(displayUpdate: .delta(delta), finalDelta: delta, finalMessage: nil)
        }

        guard type == "item.completed",
              let item = json["item"] as? [String: Any],
              let itemType = item["type"] as? String else {
            return nil
        }

        if itemType == "reasoning",
           let text = item["text"] as? String,
           let summary = summarizedCodexReasoning(text) {
            return ParsedStreamOutput(displayUpdate: .snapshot(summary), finalDelta: nil, finalMessage: nil)
        }

        if itemType == "agent_message",
           let text = item["text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            runtimeLog.info("Codex agent_message: len=\(text.count, privacy: .public) accumulated=\(self.accumulatedText.count, privacy: .public)")
            return ParsedStreamOutput(displayUpdate: .snapshot(text), finalDelta: nil, finalMessage: text)
        }

        return nil
    }

    private func formattedDisplayChunk(for update: DisplayUpdate?) -> String? {
        guard let update else { return nil }

        switch update {
        case .delta(let text):
            guard !text.isEmpty else { return nil }
            return text

        case .snapshot(let text):
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, normalized != lastSnapshotText else { return nil }
            lastSnapshotText = normalized
            let prefix = emittedSnapshotCount == 0 ? "" : "\n"
            emittedSnapshotCount += 1
            return prefix + normalized
        }
    }

    private func summarizedCodexReasoning(_ text: String) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "__", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        guard let firstLine = lines.first else { return nil }
        if firstLine.count <= 120 { return firstLine }

        let sentence = firstLine
            .split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let sentence, !sentence.isEmpty, sentence.count <= 120 {
            return sentence
        }

        return String(firstLine.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Supporting Types

private enum ShellTimeoutKind {
    case noOutput
    case idle
    case hardCap

    func message(startupTimeout: TimeInterval, inactivityTimeout: TimeInterval, hardTimeout: TimeInterval) -> String {
        switch self {
        case .noOutput:
            return "CLI timed out waiting for initial output after \(Int(startupTimeout))s"
        case .idle:
            return "CLI became idle for \(Int(inactivityTimeout))s"
        case .hardCap:
            return "CLI exceeded max runtime of \(Int(hardTimeout))s"
        }
    }
}

private final class ShellTimeoutCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var sawActivity = false
    private var finished = false

    func recordActivity(on timer: DispatchSourceTimer, inactivityTimeout: TimeInterval, hardTimer: DispatchSourceTimer? = nil) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        let isFirstActivity = !sawActivity
        sawActivity = true
        lock.unlock()
        timer.schedule(deadline: .now() + inactivityTimeout)
        // Once streaming starts, cancel the hard cap — rely on inactivity timeout instead.
        if isFirstActivity, let hardTimer = hardTimer {
            hardTimer.cancel()
        }
    }

    func consumeActivityTimeoutKind() -> ShellTimeoutKind? {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return nil }
        finished = true
        return sawActivity ? .idle : .noOutput
    }

    func consumeHardTimeout() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return false }
        finished = true
        return true
    }

    func markFinished() {
        lock.lock()
        finished = true
        lock.unlock()
    }
}

private final class ShellOutputCollector: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let copy = data
        lock.unlock()
        return copy
    }
}

/// Decodes raw byte chunks into valid UTF-8 strings, carrying over
/// incomplete multi-byte sequences (up to 3 trailing bytes) to the next chunk.
/// Prevents data loss when pipe `readabilityHandler` splits mid-character.
private final class UTF8ChunkDecoder: @unchecked Sendable {
    private var pending = Data()
    private let lock = NSLock()

    /// Append raw bytes and return the decodable UTF-8 string.
    /// Incomplete trailing bytes (1-3) are kept for the next call.
    func decode(_ chunk: Data) -> String? {
        lock.lock()
        defer { lock.unlock() }

        pending.append(chunk)
        guard !pending.isEmpty else { return nil }

        // An incomplete UTF-8 sequence can be at most 3 bytes at the end.
        let maxTrim = min(3, pending.count)
        for trim in 0...maxTrim {
            let end = pending.count - trim
            let candidate = pending[pending.startIndex..<pending.index(pending.startIndex, offsetBy: end)]
            if let str = String(data: candidate, encoding: .utf8) {
                pending = Data(pending[pending.index(pending.startIndex, offsetBy: end)...])
                return str.isEmpty ? nil : str
            }
        }
        // All attempts failed — not valid UTF-8. Drop to avoid infinite accumulation.
        pending.removeAll()
        return nil
    }

    /// Flush any remaining bytes at process termination (lossy — best effort).
    func flush() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty else { return nil }
        let str = String(decoding: pending, as: UTF8.self)
        pending.removeAll()
        return str.isEmpty ? nil : str
    }
}

private struct ShellExecutionResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var consumed = false
    func tryConsume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !consumed else { return false }
        consumed = true
        return true
    }
}

public struct ProviderRequestError: Error, LocalizedError {
    public let status: String
    public let detail: String?
    /// Identifies the provider/model that failed (e.g. "claude/claude-sonnet-4-5-20250514").
    public let agentLabel: String?

    public init(status: String, detail: String? = nil, agentLabel: String? = nil) {
        self.status = status
        self.detail = detail
        self.agentLabel = agentLabel
    }

    public var errorDescription: String? {
        let base: String
        switch status {
        case "missing_cli_command":
            base = "No CLI command configured for this provider."
        case "cli_not_found":
            base = "CLI executable not found."
        case "cli_timeout_slow":
            base = "CLI timed out after showing activity. The process may have stalled or exceeded the maximum runtime."
        case "cli_timeout_no_output":
            base = "CLI produced no output before timing out. The CLI may have failed to start or is stuck during initialization."
        case "rate_limited":
            base = "Rate limited by provider."
        case "mcp_auth_failed":
            base = "A configured MCP server failed to authenticate."
        case "permission_denied":
            base = "Permission denied — cannot write to project directory."
        case "model_not_supported":
            base = "Model not supported by this provider."
        case "auth_failed":
            base = "Authentication failed."
        case "empty_cli_output":
            base = "CLI returned empty output."
        default:
            if status.hasPrefix("cli_exit_") {
                let code = status.replacingOccurrences(of: "cli_exit_", with: "")
                base = "CLI exited with code \(code)."
            } else {
                base = "Provider error: \(status)"
            }
        }
        // Prepend agent label so the user knows which provider/model failed
        let labeled = agentLabel.map { "[\($0)] \(base)" } ?? base
        // Append first meaningful line of CLI output for diagnosis (truncated).
        if let detail = detail, !detail.isEmpty {
            let firstLine = Self.summarizedDetailLine(from: detail)
            let truncated = firstLine.count > 200 ? String(firstLine.prefix(200)) + "…" : firstLine
            return truncated.isEmpty ? labeled : "\(labeled)\n\(truncated)"
        }
        return labeled
    }

    private static func summarizedDetailLine(from detail: String) -> String {
        let lines = detail.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Prefer a human-readable diagnostic line; fall back to first non-JSON line
        return lines.first(where: isDiagnosticDetailLine)
            ?? lines.first(where: { !$0.hasPrefix("{") })
            ?? ""
    }

    private static func isDiagnosticDetailLine(_ line: String) -> Bool {
        let normalized = line.lowercased()
        if normalized == "--------" || normalized == "user" || normalized == "assistant" || normalized == "codex" {
            return false
        }
        // Claude/Codex CLI stream-json protocol events are metadata, not diagnostics
        if normalized.hasPrefix("{") && normalized.contains("\"type\":") {
            return false
        }
        return !normalized.hasPrefix("openai codex v")
            && !normalized.hasPrefix("workdir:")
            && !normalized.hasPrefix("model:")
            && !normalized.hasPrefix("provider:")
            && !normalized.hasPrefix("approval:")
            && !normalized.hasPrefix("sandbox:")
            && !normalized.hasPrefix("reasoning effort:")
            && !normalized.hasPrefix("reasoning summaries:")
            && !normalized.hasPrefix("session id:")
            && !normalized.hasPrefix("tokens used")
    }
}
