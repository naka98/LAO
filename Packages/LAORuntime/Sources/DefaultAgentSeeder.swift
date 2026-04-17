import Foundation
import LAODomain
import LAOServices

public final class DefaultAgentSeeder: @unchecked Sendable {
    private let agentService: AgentService

    public init(agentService: AgentService) {
        self.agentService = agentService
    }

    /// Detect installed CLI tools and create default agents.
    /// Skips if agents already exist.
    public func seedDefaultAgents() async throws -> [Agent] {
        let existing = await agentService.listAgents()
        guard existing.isEmpty else { return existing }

        let installed = detectInstalledCLIs()
        guard !installed.isEmpty else { return [] }

        var seeded: [Agent] = []
        for entry in installed {
            let agent = Agent(
                name: entry.name,
                tier: entry.tier,
                provider: entry.provider,
                model: entry.model,
                systemPrompt: entry.systemPrompt
            )
            let created = try await agentService.createAgent(agent)
            seeded.append(created)
        }
        return seeded
    }

    // MARK: - CLI Detection

    private struct CLIEntry {
        let provider: ProviderKey
        let name: String
        let tier: AgentTier
        let model: String
        var systemPrompt: String = ""
    }

    /// Model tier: top for core reasoning, mid for analysis, light for simple tasks.
    private enum ModelTier {
        case top, mid, light
    }

    /// Models available per provider, organized by capability tier.
    private struct ProviderModels {
        let provider: ProviderKey
        let top: String
        let mid: String
        let light: String

        func model(for tier: ModelTier) -> String {
            switch tier {
            case .top:   return top
            case .mid:   return mid
            case .light: return light
            }
        }
    }

    private func detectInstalledCLIs() -> [CLIEntry] {
        // Provider model tiers
        let providerModelMap: [(binary: String, models: ProviderModels)] = [
            ("claude", ProviderModels(provider: .claude, top: "claude-opus-4-6",           mid: "claude-sonnet-4-6",         light: "claude-haiku-4-5")),
            ("codex",  ProviderModels(provider: .codex,  top: "gpt-5.4",       mid: "gpt-5.3-codex",          light: "gpt-5.2-codex")),
            ("gemini", ProviderModels(provider: .gemini, top: "gemini-2.5-pro", mid: "gemini-2.5-flash", light: "gemini-2.5-flash-lite")),
        ]

        // Detect which CLI binaries are installed.
        // Use Process("which") to work inside App Sandbox (FileManager can't access /opt/homebrew/bin etc.)
        var available: [ProviderModels] = []
        for entry in providerModelMap {
            if isCLIAvailable(entry.binary) {
                available.append(entry.models)
            }
        }

        // Fallback: if no CLI detected (sandbox restriction), seed with Claude defaults
        if available.isEmpty {
            available.append(providerModelMap[0].models)  // Claude as default
        }

        // Create tier-based agents: Design (top) + Fallback (mid) + Step agents
        let primary = available[0]
        var results: [CLIEntry] = [
            CLIEntry(provider: primary.provider, name: "Director", tier: .director, model: primary.model(for: .top)),
            CLIEntry(provider: primary.provider, name: "Fallback", tier: .directorFallback, model: primary.model(for: .mid)),
        ]

        // Provider-specific expertise descriptions for Design agent assignment
        let providerExpertise: [ProviderKey: String] = [
            .claude: "Nuanced analysis, creative ideation, complex reasoning. Best for UX strategy, product direction, qualitative evaluation.",
            .codex: "Code generation, technical architecture, systematic design. Best for API specs, data models, implementation planning.",
            .gemini: "Data analysis, fast iteration, structured output. Best for rapid prototyping, data-driven insights, broad exploration.",
        ]

        // Create a step agent for each available provider
        for models in available {
            results.append(CLIEntry(
                provider: models.provider,
                name: "\(models.provider.rawValue.capitalized) Step",
                tier: .step,
                model: models.model(for: .mid),
                systemPrompt: providerExpertise[models.provider] ?? ""
            ))
        }

        return results
    }

    /// Returns which provider CLIs are currently installed on this machine.
    public func installedProviders() -> Set<ProviderKey> {
        var result: Set<ProviderKey> = []
        let checks: [(String, ProviderKey)] = [
            ("claude", .claude),
            ("codex", .codex),
            ("gemini", .gemini),
        ]
        for (binary, provider) in checks {
            if isCLIAvailable(binary) {
                result.insert(provider)
            }
        }
        return result
    }

    /// Check CLI availability using `which` — works inside App Sandbox.
    private func isCLIAvailable(_ binary: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [binary]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Provide PATH so `which` can find binaries in common locations
        let home = NSHomeDirectory()
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:/usr/bin:/bin"
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
