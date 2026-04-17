import Foundation

public extension AgentRole {
    var meetingRoleTitle: String {
        switch self {
        case .pm:
            return "PM"
        case .planner:
            return "Planner"
        case .designer:
            return "Designer"
        case .dev:
            return "Developer"
        case .qa:
            return "QA"
        case .research:
            return "Researcher"
        case .marketer:
            return "Marketer"
        case .reviewer:
            return "Reviewer"
        }
    }
}

public enum MeetingMentionResolver {
    public static func parseMentionedAgents(in text: String, agents: [Agent]) -> [Agent] {
        MentionAliasIndex(agents: agents).mentionedAgents(in: text)
    }

    public static func normalizeAgentMentions(in text: String, agents: [Agent]) -> String {
        MentionAliasIndex(agents: agents).normalizeMentions(in: text)
    }

    public static func exactMentionToken(for agent: Agent) -> String {
        "@\(agent.name)"
    }
}

private struct MentionAliasIndex {
    private struct ExactAlias {
        let alias: String
        let normalized: String
        let agent: Agent
    }

    private struct MentionMatch {
        let range: Range<String.Index>
        let replacement: String
        let agent: Agent
    }

    private let agentsById: [UUID: Agent]
    private let exactAliases: [ExactAlias]
    private let normalizedAliases: [String: Agent]
    private let fuzzyAliasesByAgentId: [UUID: Set<String>]

    init(agents: [Agent]) {
        self.agentsById = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })

        let tierCounts = Dictionary(grouping: agents, by: \.tier).mapValues(\.count)
        var exactBuckets: [String: [Agent]] = [:]
        var exactEntries: [ExactAlias] = []
        var fuzzyBuckets: [String: [Agent]] = [:]
        var fuzzyByAgentId: [UUID: Set<String>] = [:]

        for agent in agents {
            for alias in Self.aliases(for: agent, tierCounts: tierCounts) {
                let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = Self.normalizedToken(trimmed)
                guard !trimmed.isEmpty, !normalized.isEmpty else { continue }

                exactBuckets[normalized, default: []].append(agent)
                fuzzyBuckets[normalized, default: []].append(agent)
                exactEntries.append(ExactAlias(alias: trimmed, normalized: normalized, agent: agent))
                fuzzyByAgentId[agent.id, default: []].insert(normalized)
            }
        }

        self.exactAliases = exactEntries
            .filter { exactBuckets[$0.normalized]?.count == 1 }
            .sorted {
                if $0.alias.count != $1.alias.count {
                    return $0.alias.count > $1.alias.count
                }
                return $0.alias.localizedCaseInsensitiveCompare($1.alias) == .orderedAscending
            }

        var normalizedAliases: [String: Agent] = [:]
        for (alias, mappedAgents) in fuzzyBuckets where mappedAgents.count == 1 {
            normalizedAliases[alias] = mappedAgents[0]
        }
        self.normalizedAliases = normalizedAliases
        self.fuzzyAliasesByAgentId = fuzzyByAgentId
    }

    func mentionedAgents(in text: String) -> [Agent] {
        var resolved: [Agent] = []
        var seen: Set<UUID> = []
        for match in scanMentions(in: text) {
            if seen.insert(match.agent.id).inserted {
                resolved.append(match.agent)
            }
        }
        return resolved
    }

    func normalizeMentions(in text: String) -> String {
        let matches = scanMentions(in: text)
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = text.startIndex
        for match in matches {
            if cursor < match.range.lowerBound {
                result += String(text[cursor..<match.range.lowerBound])
            }
            result += match.replacement
            cursor = match.range.upperBound
        }
        if cursor < text.endIndex {
            result += String(text[cursor...])
        }
        return result
    }

    private func scanMentions(in text: String) -> [MentionMatch] {
        guard text.contains("@") else { return [] }

        var matches: [MentionMatch] = []
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "@" else {
                index = text.index(after: index)
                continue
            }

            if index > text.startIndex {
                let previous = text[text.index(before: index)]
                if !Self.isBoundary(previous) {
                    index = text.index(after: index)
                    continue
                }
            }

            let afterAt = text.index(after: index)
            guard afterAt <= text.endIndex else { break }

            if let exactMatch = matchExactAlias(in: text, afterAt: afterAt) {
                matches.append(
                    MentionMatch(
                        range: index..<exactMatch.upperBound,
                        replacement: MeetingMentionResolver.exactMentionToken(for: exactMatch.agent),
                        agent: exactMatch.agent
                    )
                )
                index = exactMatch.upperBound
                continue
            }

            if let singleToken = matchSingleToken(in: text, afterAt: afterAt),
               let resolved = resolveSingleToken(singleToken.token) {
                matches.append(
                    MentionMatch(
                        range: index..<singleToken.upperBound,
                        replacement: MeetingMentionResolver.exactMentionToken(for: resolved.agent) + resolved.suffix,
                        agent: resolved.agent
                    )
                )
                index = singleToken.upperBound
                continue
            }

            index = afterAt
        }

        return matches
    }

    private func matchExactAlias(
        in text: String,
        afterAt: String.Index
    ) -> (upperBound: String.Index, agent: Agent)? {
        let remaining = text[afterAt...]
        for entry in exactAliases {
            guard let range = remaining.range(
                of: entry.alias,
                options: [.anchored, .caseInsensitive, .diacriticInsensitive]
            ) else { continue }

            let upperBound = range.upperBound
            if upperBound < text.endIndex, !Self.isBoundary(text[upperBound]) {
                continue
            }
            return (upperBound, entry.agent)
        }
        return nil
    }

    private func matchSingleToken(
        in text: String,
        afterAt: String.Index
    ) -> (token: String, upperBound: String.Index)? {
        guard afterAt < text.endIndex else { return nil }

        var cursor = afterAt
        while cursor < text.endIndex, !Self.isBoundary(text[cursor]) {
            cursor = text.index(after: cursor)
        }

        guard afterAt < cursor else { return nil }
        return (String(text[afterAt..<cursor]), cursor)
    }

    private func resolveSingleToken(_ token: String) -> (agent: Agent, suffix: String)? {
        if let agent = resolveExactToken(token) {
            return (agent, "")
        }

        let characters = Array(token)
        guard characters.count >= 2 else { return nil }

        let maxSuffixLength = min(3, characters.count - 1)
        for suffixLength in 1...maxSuffixLength {
            let suffixChars = characters.suffix(suffixLength)
            guard suffixChars.allSatisfy(Self.isHangul) else { continue }

            let base = String(characters.dropLast(suffixLength))
            guard let agent = resolveCoreToken(base) else { continue }
            return (agent, String(suffixChars))
        }

        if let agent = resolveApproximateToken(token) {
            return (agent, "")
        }

        return nil
    }

    private func resolveCoreToken(_ token: String) -> Agent? {
        let normalized = Self.normalizedToken(token)
        guard !normalized.isEmpty else { return nil }

        if let exact = resolveExactToken(token) {
            return exact
        }

        return resolveApproximateToken(token)
    }

    private func resolveExactToken(_ token: String) -> Agent? {
        let normalized = Self.normalizedToken(token)
        guard !normalized.isEmpty else { return nil }

        if let exact = normalizedAliases[normalized] {
            return exact
        }
        return nil
    }

    private func resolveApproximateToken(_ token: String) -> Agent? {
        let normalized = Self.normalizedToken(token)
        guard !normalized.isEmpty else { return nil }

        if normalized.count >= 3 {
            let prefixMatches: Set<UUID> = Set(
                normalizedAliases.compactMap { entry in
                    let alias = entry.key
                    let agent = entry.value
                    guard alias.count >= 3 else { return nil }
                    guard alias.hasPrefix(normalized) || normalized.hasPrefix(alias) else { return nil }
                    return agent.id
                }
            )
            if prefixMatches.count == 1, let id = prefixMatches.first {
                return agentsById[id]
            }
        }

        guard normalized.count >= 4 else { return nil }
        let threshold = normalized.count >= 8 ? 2 : 1
        var best: (agent: Agent, distance: Int)?
        var tied = false

        for (agentId, aliases) in fuzzyAliasesByAgentId {
            guard let agent = agentsById[agentId] else { continue }
            let distances = aliases.map { Self.levenshteinDistance(between: normalized, and: $0) }
            guard let distance = distances.min(), distance <= threshold else { continue }

            if let current = best {
                if distance < current.distance {
                    best = (agent, distance)
                    tied = false
                } else if distance == current.distance, current.agent.id != agent.id {
                    tied = true
                }
            } else {
                best = (agent, distance)
                tied = false
            }
        }

        guard tied == false else { return nil }
        return best?.agent
    }

    private static func aliases(for agent: Agent, tierCounts: [AgentTier: Int]) -> [String] {
        var aliases: [String] = [agent.name]
        if tierCounts[agent.tier] == 1 {
            aliases.append(contentsOf: tierAliases(for: agent.tier))
        }
        return Array(Set(aliases))
    }

    private static func tierAliases(for tier: AgentTier) -> [String] {
        switch tier {
        case .director:
            return ["Director", "PM", "디렉터", "매니저"]
        case .directorFallback:
            return ["Fallback", "폴백"]
        case .step:
            return ["Step", "Worker", "스텝"]
        }
    }

    private static func normalizedToken(_ token: String) -> String {
        String(token.unicodeScalars.filter(CharacterSet.alphanumerics.contains))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func isHangul(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            (0xAC00...0xD7A3).contains(scalar.value) || (0x1100...0x11FF).contains(scalar.value)
        }
    }

    private static func isBoundary(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return true
            }
            if scalar == "-" || scalar == "_" || scalar == "." || scalar == "/" {
                return false
            }
            return CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar)
        }
    }

    private static func levenshteinDistance(between lhs: String, and rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        guard !lhsChars.isEmpty else { return rhsChars.count }
        guard !rhsChars.isEmpty else { return lhsChars.count }

        var previous = Array(0...rhsChars.count)
        for (i, lhsChar) in lhsChars.enumerated() {
            var current = [i + 1]
            current.reserveCapacity(rhsChars.count + 1)

            for (j, rhsChar) in rhsChars.enumerated() {
                let substitutionCost = lhsChar == rhsChar ? 0 : 1
                current.append(
                    min(
                        previous[j + 1] + 1,
                        current[j] + 1,
                        previous[j] + substitutionCost
                    )
                )
            }

            previous = current
        }
        return previous[rhsChars.count]
    }
}
