import Foundation
import LAODomain

/// Model catalog: fallback → local cache → litellm + CLI validation on refresh.
public final class ModelCatalogService: @unchecked Sendable {

    public struct ModelEntry: Sendable {
        public let name: String
        public let supportsReasoning: Bool

        public init(name: String, supportsReasoning: Bool) {
            self.name = name
            self.supportsReasoning = supportsReasoning
        }
    }

    /// Progress callback: (providerName, currentIndex, totalCount)
    public var onValidationProgress: (@Sendable (String, Int, Int) -> Void)?

    // MARK: - URLs

    /// Full model catalog from litellm (2,600+ models).
    private static let litellmURL = URL(
        string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    )!

    // MARK: - State

    /// In-memory validated model list per provider.
    private var cache: [ProviderKey: [ModelEntry]] = [:]

    /// Known invalid models per provider (to skip re-validation).
    private var invalidModels: [String: Set<String>] = [:]

    public init() {
        if let (models, invalid) = Self.loadLocalCache() {
            cache = models
            invalidModels = invalid
        }
    }

    // MARK: - Public API

    /// Returns validated models for a provider, or hardcoded fallback.
    public func models(for provider: ProviderKey) -> [ModelEntry] {
        if let cached = cache[provider], !cached.isEmpty {
            return cached
        }
        return Self.fallbackModels(for: provider)
    }

    /// Full refresh: fetch litellm → diff against local cache → CLI validate new models → merge & save.
    @discardableResult
    public func refresh() async -> Bool {
        // 1. Fetch full catalog from litellm
        let litellmModels = await fetchLitellmCatalog()
        guard !litellmModels.isEmpty else { return false }

        // 2. For each provider, find NEW models not in valid or invalid sets
        for provider in ProviderKey.allCases {
            guard let candidates = litellmModels[provider], !candidates.isEmpty else { continue }

            let validNames = Set(cache[provider]?.map(\.name) ?? [])
            let invalidNames = invalidModels[provider.rawValue] ?? []

            let newModels = candidates.filter {
                !validNames.contains($0.name) && !invalidNames.contains($0.name)
            }

            if newModels.isEmpty { continue }

            // 3. CLI validate only new models
            let results = await validateModels(newModels, provider: provider)

            // 4. Merge results
            var currentValid = cache[provider] ?? []
            for (model, result) in results {
                switch result {
                case .valid:
                    currentValid.append(model)
                case .invalid:
                    invalidModels[provider.rawValue, default: []].insert(model.name)
                case .skipped:
                    // Auth/rate-limit — add to valid optimistically
                    currentValid.append(model)
                }
            }
            cache[provider] = Self.sortModels(currentValid)
        }

        // 5. Save updated cache
        saveCache()
        return true
    }

    // MARK: - Litellm Fetch

    private func fetchLitellmCatalog() async -> [ProviderKey: [ModelEntry]] {
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.litellmURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return [:]
            }

            var result: [ProviderKey: [ModelEntry]] = [.claude: [], .codex: [], .gemini: []]

            for (key, value) in json {
                guard let dict = value as? [String: Any],
                      let litellmProvider = dict["litellm_provider"] as? String,
                      let mode = dict["mode"] as? String,
                      mode == "chat" || mode == "responses"
                else { continue }

                let supportsReasoning = dict["supports_reasoning"] as? Bool ?? false

                switch litellmProvider {
                case "anthropic":
                    if Self.isRelevantModel(key) {
                        result[.claude]?.append(ModelEntry(name: key, supportsReasoning: supportsReasoning))
                    }
                case "openai":
                    if Self.isRelevantModel(key) {
                        result[.codex]?.append(ModelEntry(name: key, supportsReasoning: supportsReasoning))
                    }
                case "gemini":
                    let name = key.hasPrefix("gemini/") ? String(key.dropFirst(7)) : key
                    if Self.isRelevantModel(name) {
                        result[.gemini]?.append(ModelEntry(name: name, supportsReasoning: supportsReasoning))
                    }
                default:
                    break
                }
            }
            return result
        } catch {
            return [:]
        }
    }

    // MARK: - CLI Validation

    private enum ValidationResult {
        case valid, invalid, skipped
    }

    private func validateModels(
        _ models: [ModelEntry], provider: ProviderKey
    ) async -> [(ModelEntry, ValidationResult)] {
        let providerName = provider.rawValue.capitalized
        var results: [(ModelEntry, ValidationResult)] = []

        for (index, model) in models.enumerated() {
            onValidationProgress?(providerName, index + 1, models.count)
            let result = await validateSingleModel(provider: provider, modelName: model.name)
            results.append((model, result))
        }
        return results
    }

    private func validateSingleModel(provider: ProviderKey, modelName: String) async -> ValidationResult {
        let escaped = modelName.replacingOccurrences(of: "\"", with: "\\\"")
        let command: String
        switch provider {
        case .claude:
            command = "claude --model \"\(escaped)\" -p \"ok\""
        case .codex:
            command = "codex exec --skip-git-repo-check -c model_reasoning_effort='high' -m \"\(escaped)\" \"ok\""
        case .gemini:
            command = "gemini --model \"\(escaped)\" -p \"ok\""
        }

        let result = await shellExec(command, timeout: 30)
        if result.exitCode == 0 { return .valid }

        let output = (result.stderr + " " + result.stdout).lowercased()

        if output.contains("auth") || output.contains("unauthorized")
            || output.contains("expired") || output.contains("forbidden")
            || output.contains("api key") || output.contains("login") {
            return .skipped
        }
        if output.contains("not found") || output.contains("does not exist")
            || output.contains("invalid model") || output.contains("not available")
            || output.contains("not supported")
            || output.contains("modelnotfounderror") || output.contains("unknown model") {
            return .invalid
        }
        if output.contains("rate limit") || output.contains("too many requests")
            || output.contains("capacity") || output.contains("resource_exhausted") {
            return .skipped
        }
        return .skipped
    }

    // MARK: - Shell Execution

    private struct ShellResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func shellExec(_ command: String, timeout: TimeInterval) async -> ShellResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let guard_ = ResumeOnce()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            var env = ProcessInfo.processInfo.environment
            // Use real home dir, not sandbox container path
            let realHome = env["HOME"]
                ?? (getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir) })
                ?? NSHomeDirectory()
            let extra = ["/opt/homebrew/bin", "/usr/local/bin", "\(realHome)/.local/bin"]
            let current = (env["PATH"] ?? "").split(separator: ":").map(String.init)
            var seen = Set<String>()
            var unique: [String] = []
            for p in (extra + current) where !seen.contains(p) {
                seen.insert(p)
                unique.append(p)
            }
            env["PATH"] = unique.joined(separator: ":")
            process.environment = env
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

            let timer = DispatchSource.makeTimerSource()
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler { if process.isRunning { process.terminate() } }
            timer.resume()

            process.terminationHandler = { finished in
                timer.cancel()
                let out = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if guard_.tryConsume() {
                    continuation.resume(returning: ShellResult(exitCode: finished.terminationStatus, stdout: out, stderr: err))
                }
            }

            do {
                try process.run()
            } catch {
                timer.cancel()
                if guard_.tryConsume() {
                    continuation.resume(returning: ShellResult(exitCode: -1, stdout: "", stderr: error.localizedDescription))
                }
            }
        }
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

    // MARK: - Filtering

    private static func isRelevantModel(_ name: String) -> Bool {
        if name.hasPrefix("ft:") { return false }
        if name.contains("exp-") { return false }
        if name.contains("preview") && !name.hasSuffix("-preview") { return false }
        if name.contains("realtime") { return false }
        if name.contains("audio") { return false }
        if name.contains("dall-e") { return false }
        if name.contains("tts") { return false }
        if name.contains("whisper") { return false }
        if name.contains("embedding") { return false }
        if name.contains("gemma") { return false }
        if name.contains("learnlm") { return false }
        if name.contains("live") { return false }
        if name.contains("vision") && !name.contains("pro-vision") { return false }

        let datePattern = /\d{4}-\d{2}-\d{2}/
        if name.contains(datePattern) { return false }

        let versionPattern = /-\d{3}$/
        if name.contains(versionPattern) { return false }

        return true
    }

    private static func sortModels(_ models: [ModelEntry]) -> [ModelEntry] {
        models.sorted { a, b in
            if a.supportsReasoning != b.supportsReasoning { return a.supportsReasoning }
            return a.name > b.name
        }
    }

    // MARK: - Fallback

    private static func fallbackModels(for provider: ProviderKey) -> [ModelEntry] {
        switch provider {
        case .claude:
            return [
                ModelEntry(name: "claude-opus-4-6", supportsReasoning: true),
                ModelEntry(name: "claude-sonnet-4-6", supportsReasoning: true),
                ModelEntry(name: "claude-haiku-4-5", supportsReasoning: false),
            ]
        case .codex:
            return [
                ModelEntry(name: "gpt-5.4", supportsReasoning: true),
                ModelEntry(name: "gpt-5.3-codex", supportsReasoning: false),
                ModelEntry(name: "gpt-5.2-codex", supportsReasoning: false),
            ]
        case .gemini:
            return [
                ModelEntry(name: "gemini-2.5-pro", supportsReasoning: true),
                ModelEntry(name: "gemini-2.5-flash", supportsReasoning: true),
                ModelEntry(name: "gemini-2.5-flash-lite", supportsReasoning: false),
            ]
        }
    }

    // MARK: - Persistence

    private static var cacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let subdirectory = Bundle.main.bundleIdentifier ?? "LAO"
        return appSupport.appendingPathComponent(subdirectory, isDirectory: true)
    }

    private static var localCacheURL: URL {
        cacheDirectory.appendingPathComponent("validated_models.json")
    }

    private func saveCache() {
        var json: [String: Any] = [
            "version": 1,
            "updated_at": ISO8601DateFormatter().string(from: Date()).prefix(10).description,
        ]

        let mapping: [(ProviderKey, String)] = [(.claude, "claude"), (.codex, "codex"), (.gemini, "gemini")]
        for (provider, key) in mapping {
            let entries = cache[provider] ?? []
            json[key] = entries.map { entry -> [String: Any] in
                ["name": entry.name, "reasoning": entry.supportsReasoning]
            }
        }

        if !invalidModels.isEmpty {
            var invalidJSON: [String: [String]] = [:]
            for (key, names) in invalidModels {
                invalidJSON[key] = names.sorted()
            }
            json["invalid"] = invalidJSON
        }

        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return }

        do {
            try FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: Self.localCacheURL, options: .atomic)
        } catch {
            // silently fail
        }
    }

    private static func parseValidatedJSON(_ data: Data) -> (models: [ProviderKey: [ModelEntry]], invalid: [String: Set<String>]?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var result: [ProviderKey: [ModelEntry]] = [:]
        let mapping: [(String, ProviderKey)] = [("claude", .claude), ("codex", .codex), ("gemini", .gemini)]

        for (jsonKey, provider) in mapping {
            guard let models = json[jsonKey] as? [[String: Any]] else { continue }
            result[provider] = models.compactMap { dict in
                guard let name = dict["name"] as? String else { return nil }
                let reasoning = dict["reasoning"] as? Bool ?? false
                return ModelEntry(name: name, supportsReasoning: reasoning)
            }
        }

        var invalid: [String: Set<String>]?
        if let invalidJSON = json["invalid"] as? [String: [String]] {
            invalid = [:]
            for (key, names) in invalidJSON {
                invalid?[key] = Set(names)
            }
        }

        return result.isEmpty ? nil : (result, invalid)
    }

    private static func loadLocalCache() -> (models: [ProviderKey: [ModelEntry]], invalid: [String: Set<String>])? {
        guard let data = try? Data(contentsOf: localCacheURL),
              let parsed = parseValidatedJSON(data)
        else { return nil }
        return (parsed.models, parsed.invalid ?? [:])
    }
}
