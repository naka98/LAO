import Foundation

public struct StructuredDecisionSummary: Hashable, Codable, Sendable {
    public var oneLiner: String
    public var context: String
    public var options: [String]
    public var recommendation: String
    public var risk: String
    public var resultingTasks: [String]

    public init(
        oneLiner: String = "",
        context: String = "",
        options: [String] = [],
        recommendation: String = "",
        risk: String = "",
        resultingTasks: [String] = []
    ) {
        self.oneLiner = oneLiner
        self.context = context
        self.options = options
        self.recommendation = recommendation
        self.risk = risk
        self.resultingTasks = resultingTasks
    }

    public var isMeaningful: Bool {
        !oneLiner.isEmpty
            || !context.isEmpty
            || !options.isEmpty
            || !recommendation.isEmpty
            || !risk.isEmpty
            || !resultingTasks.isEmpty
    }

    public static func parse(_ summary: String) -> StructuredDecisionSummary? {
        guard summary.contains("##") else { return nil }

        var result = StructuredDecisionSummary()
        var currentSection = ""
        var currentContent: [String] = []

        func flush() {
            let text = currentContent
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let key = currentSection
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            switch key {
            case let value where value.contains("one-line") || value == "summary":
                result.oneLiner = text
            case let value where value.contains("context"):
                result.context = text
            case let value where value.contains("option"):
                result.options = bulletLines(from: text)
            case let value where value.contains("recommend"):
                result.recommendation = text
            case let value where value.contains("risk"):
                result.risk = text
            case let value where value.contains("task"):
                result.resultingTasks = bulletLines(from: text)
            default:
                break
            }

            currentContent = []
        }

        for line in summary.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                flush()
                currentSection = String(line.dropFirst(3))
            } else {
                currentContent.append(line)
            }
        }
        flush()

        return result.isMeaningful ? result : nil
    }

    private static func bulletLines(from text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map {
                if $0.hasPrefix("- ") {
                    return String($0.dropFirst(2))
                }
                return $0
            }
            .filter { !$0.isEmpty }
    }
}
