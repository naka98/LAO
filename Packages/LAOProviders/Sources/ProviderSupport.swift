import Foundation
import LAODomain
import LAOServices

public enum ProviderRegistryMutationError: Error {
    case unsupported
}

public final class StaticProviderRegistryService: ProviderRegistryService {
    private let configs: [ProviderConfig]
    private let roleRoutings: [AgentRoleRouting]
    private let cliCommands: [ProviderCLICommand]

    public init(
        configs: [ProviderConfig],
        roleRoutings: [AgentRoleRouting]? = nil,
        cliCommands: [ProviderCLICommand]? = nil
    ) {
        self.configs = configs
        self.roleRoutings = roleRoutings ?? Self.defaultRoleRoutings(configs: configs)
        self.cliCommands = cliCommands ?? []
    }

    public func listConfigs() async -> [ProviderConfig] {
        configs
    }

    public func listRoleRoutings() async -> [AgentRoleRouting] {
        roleRoutings
    }

    public func listProviderCLICommands() async -> [ProviderCLICommand] {
        cliCommands
    }

    public func updateProviderDefaultModel(provider _: ProviderKey, model _: String) async throws {
        throw ProviderRegistryMutationError.unsupported
    }

    public func upsertRoleRouting(_: AgentRoleRouting) async throws {
        throw ProviderRegistryMutationError.unsupported
    }

    public func upsertProviderCLICommand(
        provider _: ProviderKey,
        commandTemplate _: String,
        executablePathOverride _: String?
    ) async throws {
        throw ProviderRegistryMutationError.unsupported
    }

    public func validate(_ provider: ProviderKey) async -> ProviderValidationResult {
        let config = configs.first(where: { $0.provider == provider })
        return ProviderValidationResult(
            provider: provider,
            status: config?.status ?? .unconfigured,
            message: config == nil ? "Provider is not configured." : "Validation scaffold only."
        )
    }

    private static func defaultRoleRoutings(configs: [ProviderConfig]) -> [AgentRoleRouting] {
        let modelByProvider = Dictionary(uniqueKeysWithValues: configs.map { ($0.provider, $0.defaultModel) })

        return [
            AgentRoleRouting(role: .pm, provider: .claude, model: modelByProvider[.claude] ?? "claude-sonnet"),
            AgentRoleRouting(role: .planner, provider: .claude, model: modelByProvider[.claude] ?? "claude-sonnet"),
            AgentRoleRouting(role: .dev, provider: .codex, model: modelByProvider[.codex] ?? "codex-latest"),
            AgentRoleRouting(role: .designer, provider: .claude, model: modelByProvider[.claude] ?? "claude-sonnet"),
            AgentRoleRouting(role: .qa, provider: .gemini, model: modelByProvider[.gemini] ?? "gemini-2.0-flash"),
            AgentRoleRouting(role: .research, provider: .gemini, model: modelByProvider[.gemini] ?? "gemini-2.0-flash"),
            AgentRoleRouting(role: .marketer, provider: .claude, model: modelByProvider[.claude] ?? "claude-sonnet"),
            AgentRoleRouting(role: .reviewer, provider: .gemini, model: modelByProvider[.gemini] ?? "gemini-2.0-flash"),
        ]
    }
}
