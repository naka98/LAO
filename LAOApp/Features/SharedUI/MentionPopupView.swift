import LAODomain
import SwiftUI

/// Popup view showing agent autocomplete results for @mention input.
struct MentionPopupView: View {
    @Environment(\.theme) private var theme

    let agents: [Agent]
    let query: String
    let onSelect: (Agent) -> Void

    private var filtered: [Agent] {
        if query.isEmpty {
            return agents
        }
        return agents.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.tier.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        if !filtered.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(filtered) { agent in
                    Button {
                        onSelect(agent)
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(theme.accentPrimary)
                                    .frame(width: 22, height: 22)
                                Text(String(agent.name.prefix(1)).uppercased())
                                    .font(AppTheme.Typography.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            Text(agent.name)
                                .font(AppTheme.Typography.body)
                            BadgeView(title: agent.tier.displayName, tone: .neutral)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if agent.id != filtered.last?.id {
                        Divider().padding(.horizontal, 10)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(theme.surfacePrimary)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .stroke(theme.borderSubtle, lineWidth: 1)
            )
            .frame(maxWidth: 280)
        }
    }
}

// MARK: - Mention Parsing Utility

enum MentionParser {
    /// Extracts @mentions from a comment string and returns matching agent IDs.
    static func extractMentionedAgentIds(from text: String, agents: [Agent]) -> [UUID] {
        // Match @Name patterns (alphanumeric, hyphens, underscores)
        let pattern = "@([\\w-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        var agentIds: [UUID] = []
        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let mentionName = String(text[nameRange])

            // Match by name (case-insensitive) or role
            if let agent = agents.first(where: {
                $0.name.localizedCaseInsensitiveCompare(mentionName) == .orderedSame
                    || $0.tier.rawValue.localizedCaseInsensitiveCompare(mentionName) == .orderedSame
            }) {
                if !agentIds.contains(agent.id) {
                    agentIds.append(agent.id)
                }
            }
        }
        return agentIds
    }

    /// Finds the current @mention query being typed (text after the last @ that isn't complete).
    static func activeMentionQuery(in text: String) -> String? {
        // Find the last @ that isn't followed by a space before the end
        guard let lastAt = text.lastIndex(of: "@") else { return nil }
        let afterAt = text[text.index(after: lastAt)...]

        // If there's a space after the @, the mention is complete
        if afterAt.contains(" ") || afterAt.contains("\n") { return nil }

        // Check that @ is at start or preceded by whitespace
        if lastAt != text.startIndex {
            let charBefore = text[text.index(before: lastAt)]
            if !charBefore.isWhitespace && !charBefore.isNewline { return nil }
        }

        return String(afterAt)
    }
}
