import LAODomain

extension Agent {
    /// Format a list of enabled step agents for inclusion in Design prompts.
    static func promptDescription(for agents: [Agent], snippetLength: Int = 100) -> String {
        let stepAgents = agents.filter { $0.tier == .step && $0.isEnabled }
        if stepAgents.isEmpty { return "No step agents available." }
        return stepAgents.map { agent in
            var desc = "- id: \"\(agent.id.uuidString)\", name: \"\(agent.name)\", provider: \(agent.provider.rawValue), model: \(agent.model)"
            if !agent.systemPrompt.isEmpty {
                let snippet = String(agent.systemPrompt.prefix(snippetLength))
                desc += ", instruction: \"\(snippet)\""
            }
            return desc
        }.joined(separator: "\n")
    }
}
