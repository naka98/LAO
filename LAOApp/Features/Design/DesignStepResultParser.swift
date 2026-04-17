import Foundation
import LAODomain
import os

private let parserLog = Logger(subsystem: "com.leeway.lao", category: "DesignParser")

/// Pure parsing utilities for Design workflow output.
/// Handles analysis responses, chat responses, item elaboration, and legacy step results.
enum DesignStepResultParser {

    // MARK: - Legacy Step Result (kept for backward compatibility)

    /// Parsed step result: clean output text + optional decision + structured output.
    struct StepResult {
        let cleanOutput: String
        let decision: DesignDecision?
        let stepSummary: String?
        let keyDeliverables: [String]
        let keyFindings: [String]
    }

    /// Parse step output: extract [STEP_RESULT] JSON block, return clean text + decision.
    static func parse(from output: String) -> StepResult {
        if let result = parseStructuredResult(from: output) {
            return result
        }

        if let decision = parseLegacyDecision(from: output) {
            let cleanOutput = output.components(separatedBy: "[DECISION_NEEDED]").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? output
            return StepResult(cleanOutput: cleanOutput, decision: decision, stepSummary: nil, keyDeliverables: [], keyFindings: [])
        }

        return StepResult(cleanOutput: output, decision: nil, stepSummary: nil, keyDeliverables: [], keyFindings: [])
    }

    // MARK: - Analysis Response Parsing

    /// Parse Design analysis response from [ANALYSIS_RESULT] marker.
    /// Falls back to extracting JSON from the entire output if no marker found.
    static func parseAnalysisResponse(from output: String) -> DesignAnalysisResponse? {
        let marker = "[ANALYSIS_RESULT]"

        let jsonBlock: String
        if output.contains(marker) {
            let parts = output.components(separatedBy: marker)
            guard parts.count >= 2 else {
                parserLog.warning("Analysis marker found but no content after it")
                return nil
            }
            let rawBlock = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let extracted = extractJSON(from: rawBlock) else {
                parserLog.warning("Analysis marker found but JSON extraction failed — raw prefix: \(String(rawBlock.prefix(300)), privacy: .public)")
                return nil
            }
            jsonBlock = extracted
        } else {
            // Try to find JSON directly in the output
            parserLog.info("No [ANALYSIS_RESULT] marker — attempting direct JSON extraction")
            guard let extracted = extractJSON(from: output) else {
                parserLog.warning("No JSON found in output — len=\(output.count, privacy: .public) prefix: \(String(output.prefix(300)), privacy: .public)")
                return nil
            }
            jsonBlock = extracted
        }

        let result = decodeWithSanitization(DesignAnalysisResponse.self, from: jsonBlock)
        if result == nil {
            parserLog.error("DesignAnalysisResponse decode failed — JSON len=\(jsonBlock.count) prefix: \(String(jsonBlock.prefix(1000)), privacy: .public)")
        }
        return result
    }

    /// Extract the human-readable message portion (before the marker) from analysis output.
    static func extractAnalysisMessage(from output: String) -> String {
        let marker = "[ANALYSIS_RESULT]"
        if output.contains(marker) {
            return output.components(separatedBy: marker).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? output
        }
        return output
    }

    // MARK: - Skeleton Response Parsing

    /// Parse skeleton generation response from [SKELETON_RESULT] marker.
    /// Returns deliverables, relationships, and uncertainties for the selected approach.
    static func parseSkeletonResponse(from output: String) -> DesignSkeletonResponse? {
        let marker = "[SKELETON_RESULT]"

        let jsonBlock: String
        if output.contains(marker) {
            let parts = output.components(separatedBy: marker)
            guard parts.count >= 2 else {
                parserLog.warning("Skeleton marker found but no content after it")
                return nil
            }
            let rawBlock = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let extracted = extractJSON(from: rawBlock) else {
                parserLog.warning("Skeleton marker found but JSON extraction failed — raw prefix: \(String(rawBlock.prefix(300)), privacy: .public)")
                return nil
            }
            jsonBlock = extracted
        } else {
            parserLog.info("No [SKELETON_RESULT] marker — attempting direct JSON extraction")
            // When --json-schema is used, the response is pure JSON. Try decoding
            // directly before extractJSON, which can mis-detect backticks inside
            // JSON string values as code fences.
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{"),
               let directResult = decodeWithSanitization(DesignSkeletonResponse.self, from: trimmed) {
                return directResult
            }
            guard let extracted = extractJSON(from: output) else {
                parserLog.warning("No JSON found in skeleton output — len=\(output.count, privacy: .public) prefix: \(String(output.prefix(300)), privacy: .public)")
                return nil
            }
            jsonBlock = extracted
        }

        let result = decodeWithSanitization(DesignSkeletonResponse.self, from: jsonBlock)
        if result == nil {
            parserLog.error("DesignSkeletonResponse decode failed — JSON prefix: \(String(jsonBlock.prefix(1000)), privacy: .public)")
        }
        return result
    }

    // MARK: - Skeleton Graph Response Parsing

    /// Parse skeleton graph response from [SKELETON_GRAPH] marker.
    /// Returns relationships and uncertainties for the skeleton items.
    static func parseSkeletonGraphResponse(from output: String) -> DesignSkeletonGraphResponse? {
        let marker = "[SKELETON_GRAPH]"

        let jsonBlock: String
        if output.contains(marker) {
            let parts = output.components(separatedBy: marker)
            guard parts.count >= 2 else {
                parserLog.warning("Skeleton graph marker found but no content after it")
                return nil
            }
            let rawBlock = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let extracted = extractJSON(from: rawBlock) else {
                parserLog.warning("Skeleton graph marker found but JSON extraction failed — raw prefix: \(String(rawBlock.prefix(300)), privacy: .public)")
                return nil
            }
            jsonBlock = extracted
        } else {
            parserLog.info("No [SKELETON_GRAPH] marker — attempting direct JSON extraction")
            guard let extracted = extractJSON(from: output) else {
                parserLog.warning("No JSON found in skeleton graph output — len=\(output.count, privacy: .public) prefix: \(String(output.prefix(300)), privacy: .public)")
                return nil
            }
            jsonBlock = extracted
        }

        let result = decodeWithSanitization(DesignSkeletonGraphResponse.self, from: jsonBlock)
        if result == nil {
            parserLog.error("DesignSkeletonGraphResponse decode failed — JSON prefix: \(String(jsonBlock.prefix(1000)), privacy: .public)")
        }
        return result
    }

    // MARK: - Skeleton Relationships Response Parsing

    /// Parse skeleton relationships response from [SKELETON_RELATIONSHIPS] marker.
    static func parseSkeletonRelationshipsResponse(from output: String) -> DesignSkeletonRelationshipsResponse? {
        let marker = "[SKELETON_RELATIONSHIPS]"

        let jsonBlock: String
        if output.contains(marker) {
            let parts = output.components(separatedBy: marker)
            guard parts.count >= 2 else {
                parserLog.warning("Skeleton relationships marker found but no content after it")
                return nil
            }
            let rawBlock = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let extracted = extractJSON(from: rawBlock) else {
                parserLog.warning("Skeleton relationships marker found but JSON extraction failed — raw prefix: \(String(rawBlock.prefix(300)), privacy: .public)")
                return nil
            }
            jsonBlock = extracted
        } else {
            parserLog.info("No [SKELETON_RELATIONSHIPS] marker — attempting direct JSON extraction")
            guard let extracted = extractJSON(from: output) else {
                parserLog.warning("No JSON found in skeleton relationships output — len=\(output.count, privacy: .public) prefix: \(String(output.prefix(300)), privacy: .public)")
                return nil
            }
            jsonBlock = extracted
        }

        let result = decodeWithSanitization(DesignSkeletonRelationshipsResponse.self, from: jsonBlock)
        if result == nil {
            parserLog.error("DesignSkeletonRelationshipsResponse decode failed — JSON prefix: \(String(jsonBlock.prefix(1000)), privacy: .public)")
        }
        return result
    }

    // MARK: - Skeleton Uncertainties Response Parsing

    /// Parse skeleton uncertainties response from [SKELETON_UNCERTAINTIES] marker.
    static func parseSkeletonUncertaintiesResponse(from output: String) -> DesignSkeletonUncertaintiesResponse? {
        let marker = "[SKELETON_UNCERTAINTIES]"

        let jsonBlock: String
        if output.contains(marker) {
            let parts = output.components(separatedBy: marker)
            guard parts.count >= 2 else {
                parserLog.warning("Skeleton uncertainties marker found but no content after it")
                return nil
            }
            let rawBlock = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let extracted = extractJSON(from: rawBlock) else {
                parserLog.warning("Skeleton uncertainties marker found but JSON extraction failed — raw prefix: \(String(rawBlock.prefix(300)), privacy: .public)")
                return nil
            }
            jsonBlock = extracted
        } else {
            parserLog.info("No [SKELETON_UNCERTAINTIES] marker — attempting direct JSON extraction")
            guard let extracted = extractJSON(from: output) else {
                parserLog.warning("No JSON found in skeleton uncertainties output — len=\(output.count, privacy: .public) prefix: \(String(output.prefix(300)), privacy: .public)")
                return nil
            }
            jsonBlock = extracted
        }

        let result = decodeWithSanitization(DesignSkeletonUncertaintiesResponse.self, from: jsonBlock)
        if result == nil {
            parserLog.error("DesignSkeletonUncertaintiesResponse decode failed — JSON prefix: \(String(jsonBlock.prefix(1000)), privacy: .public)")
        }
        return result
    }

    // MARK: - Consistency Check Response Parsing

    /// Parse structured consistency check response (issues array + summary).
    static func parseConsistencyCheckResponse(from output: String) -> ConsistencyCheckResponse? {
        if let jsonString = extractJSON(from: output),
           let response = decodeWithSanitization(ConsistencyCheckResponse.self, from: jsonString) {
            return response
        }
        // Try the entire output as JSON
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return decodeWithSanitization(ConsistencyCheckResponse.self, from: trimmed)
    }

    // MARK: - Chat Response Parsing

    /// Parse Design chat response from [DIRECTOR_RESPONSE] marker.
    /// Returns message + optional orchestration actions.
    static func parseChatResponse(from output: String) -> DesignChatResponse? {
        let marker = "[DIRECTOR_RESPONSE]"

        if output.contains(marker) {
            let parts = output.components(separatedBy: marker)
            guard parts.count >= 2 else { return nil }
            let rawBlock = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let jsonString = extractJSON(from: rawBlock) else {
                // No JSON block — treat the whole response as a plain message
                let message = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                return DesignChatResponse(message: message.isEmpty ? output : message, actions: nil)
            }
            return decodeWithSanitization(DesignChatResponse.self, from: jsonString)
        }

        // Try to parse the entire output as JSON
        if let jsonString = extractJSON(from: output),
           let response = decodeWithSanitization(DesignChatResponse.self, from: jsonString) {
            return response
        }

        // Plain text response — no actions
        return DesignChatResponse(
            message: output.trimmingCharacters(in: .whitespacesAndNewlines),
            actions: nil
        )
    }

    /// Extract the human-readable message portion from chat output.
    static func extractChatMessage(from output: String) -> String {
        let marker = "[DIRECTOR_RESPONSE]"
        if output.contains(marker) {
            return output.components(separatedBy: marker).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? output
        }
        return output
    }

    // MARK: - Item Elaboration Parsing

    /// Parse step agent item elaboration response from [ITEM_SPEC] marker.
    /// Uses multi-stage fallback: 1) [ITEM_SPEC] marker, 2) any JSON code block, 3) entire response as JSON.
    static func parseItemSpec(from output: String) -> [String: AnyCodable]? {
        // Stage 1: Try existing [ITEM_SPEC] marker
        let marker = "[ITEM_SPEC]"
        if output.contains(marker) {
            let parts = output.components(separatedBy: marker)
            if parts.count >= 2 {
                let rawBlock = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if let extracted = extractJSON(from: rawBlock) {
                    if let response = decodeWithSanitization(ItemElaborationResponse.self, from: extracted) {
                        return response.spec
                    }
                    if let dict = decodeWithSanitization([String: AnyCodable].self, from: extracted) {
                        return dict
                    }
                }
            }
        }

        // Stage 2: Try extracting any JSON code block (```json ... ```)
        if let extracted = extractJSON(from: output) {
            if let response = decodeWithSanitization(ItemElaborationResponse.self, from: extracted) {
                return response.spec
            }
            if let dict = decodeWithSanitization([String: AnyCodable].self, from: extracted) {
                // If the dict has a "spec" key, use its value
                if let specValue = dict["spec"], let specDict = specValue.dictValue {
                    return AnyCodable.from(jsonDict: specDict)
                }
                return dict
            }
        }

        // Stage 3: Try parsing entire response as JSON (trimmed)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let response = decodeWithSanitization(ItemElaborationResponse.self, from: trimmed) {
            return response.spec
        }
        if let dict = decodeWithSanitization([String: AnyCodable].self, from: trimmed) {
            if let specValue = dict["spec"], let specDict = specValue.dictValue {
                return AnyCodable.from(jsonDict: specDict)
            }
            return dict
        }

        // Stage 4: Extract all balanced JSON objects and try each one (largest first)
        let allObjects = extractAllBalancedJSONObjects(from: output)
        let sortedBySize = allObjects.sorted { $0.count > $1.count }
        for candidate in sortedBySize {
            if let response = decodeWithSanitization(ItemElaborationResponse.self, from: candidate) {
                return response.spec
            }
            if let dict = decodeWithSanitization([String: AnyCodable].self, from: candidate) {
                if let specValue = dict["spec"], let specDict = specValue.dictValue {
                    return AnyCodable.from(jsonDict: specDict)
                }
                // If has enough keys, accept as spec directly
                if dict.count >= 2 {
                    return dict
                }
            }
        }

        return nil
    }

    // MARK: - Item Elaboration with Uncertainties

    /// Parse step agent output returning both spec and any uncertainties the agent surfaced.
    static func parseItemSpecWithUncertainties(from output: String) -> (spec: [String: AnyCodable]?, uncertainties: [DesignAnalysisResponse.UncertaintySpec]) {
        let uncertainties = parseUncertainties(from: output)
        // Strip [UNCERTAINTIES] block before parsing spec to avoid interference
        let cleanedOutput = stripUncertaintiesBlock(from: output)
        let spec = parseItemSpec(from: cleanedOutput)
        return (spec, uncertainties)
    }

    /// Parse [UNCERTAINTIES] block from step agent output.
    static func parseUncertainties(from output: String) -> [DesignAnalysisResponse.UncertaintySpec] {
        let startMarker = "[UNCERTAINTIES]"
        let endMarker = "[/UNCERTAINTIES]"

        guard let startRange = output.range(of: startMarker),
              let endRange = output.range(of: endMarker, range: startRange.upperBound..<output.endIndex) else {
            return []
        }

        let rawBlock = String(output[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to parse as JSON array
        let jsonString = extractJSON(from: rawBlock) ?? rawBlock
        guard let data = jsonString.data(using: .utf8) else { return [] }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        if let specs = try? decoder.decode([DesignAnalysisResponse.UncertaintySpec].self, from: data) {
            return specs
        }

        // Try with sanitization
        if let sanitized = sanitizeJSON(jsonString),
           let sanitizedData = sanitized.data(using: .utf8),
           let specs = try? decoder.decode([DesignAnalysisResponse.UncertaintySpec].self, from: sanitizedData) {
            return specs
        }

        return []
    }

    /// Remove [UNCERTAINTIES]...[/UNCERTAINTIES] block from output.
    private static func stripUncertaintiesBlock(from output: String) -> String {
        guard let startRange = output.range(of: "[UNCERTAINTIES]"),
              let endRange = output.range(of: "[/UNCERTAINTIES]", range: startRange.upperBound..<output.endIndex) else {
            return output
        }
        var result = output
        result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - JSON Extraction Utilities

    /// Extract JSON string from a block (code fence or raw braces).
    static func extractJSON(from block: String) -> String? {
        if let fenceStart = block.range(of: "```json", options: .caseInsensitive),
           let fenceEnd = block.range(of: "```", range: fenceStart.upperBound..<block.endIndex) {
            return String(block[fenceStart.upperBound..<fenceEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let fenceStart = block.range(of: "```"),
           let fenceEnd = block.range(of: "```", range: fenceStart.upperBound..<block.endIndex) {
            return String(block[fenceStart.upperBound..<fenceEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Pick the largest balanced JSON object (not the last) to handle
        // cases where the LLM appends commentary after the main JSON block.
        let allObjects = extractAllBalancedJSONObjects(from: block)
        return allObjects.max(by: { $0.count < $1.count })
    }

    /// Attempt to fix common JSON issues: escape literal newlines/tabs inside string values,
    /// remove trailing commas before `}` or `]`.
    static func sanitizeJSON(_ raw: String) -> String? {
        // Strip comments (// and /* */) that are outside JSON string values.
        let stripped: String = {
            var out: [Character] = []
            var inStr = false
            var esc = false
            let chars = Array(raw)
            var i = 0
            while i < chars.count {
                let ch = chars[i]
                if esc {
                    esc = false
                    out.append(ch)
                    i += 1
                    continue
                }
                if ch == "\\" && inStr {
                    esc = true
                    out.append(ch)
                    i += 1
                    continue
                }
                if ch == "\"" {
                    inStr.toggle()
                    out.append(ch)
                    i += 1
                    continue
                }
                if !inStr {
                    // Single-line comment: // ... until end of line
                    if ch == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                        // Skip to end of line
                        i += 2
                        while i < chars.count && chars[i] != "\n" { i += 1 }
                        continue
                    }
                    // Block comment: /* ... */
                    if ch == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                        i += 2
                        while i + 1 < chars.count {
                            if chars[i] == "*" && chars[i + 1] == "/" { i += 2; break }
                            i += 1
                        }
                        continue
                    }
                }
                out.append(ch)
                i += 1
            }
            return String(out)
        }()

        // Escape literal control characters inside JSON string values.
        var result: [Character] = []
        var inString = false
        var escaped = false
        for ch in stripped {
            if escaped {
                escaped = false
                result.append(ch)
                continue
            }
            if ch == "\\" && inString {
                escaped = true
                result.append(ch)
                continue
            }
            if ch == "\"" {
                inString.toggle()
                result.append(ch)
                continue
            }
            if inString {
                switch ch {
                case "\n": result.append(contentsOf: "\\n")
                case "\r": result.append(contentsOf: "\\r")
                case "\t": result.append(contentsOf: "\\t")
                default:   result.append(ch)
                }
            } else {
                result.append(ch)
            }
        }
        var sanitized = String(result)
        // Remove trailing commas before } or ]
        sanitized = sanitized.replacingOccurrences(
            of: ",\\s*([}\\]])",
            with: "$1",
            options: .regularExpression
        )
        // Verify it's now parseable
        guard let data = sanitized.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return nil
        }
        return sanitized
    }

    // MARK: - Private Helpers

    /// Decode a Codable type from a JSON string, with automatic sanitization fallback.
    private static func decodeWithSanitization<T: Codable>(_ type: T.Type, from jsonString: String) -> T? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Try direct decode (snake_case strategy)
        if let data = jsonString.data(using: .utf8) {
            do {
                return try decoder.decode(type, from: data)
            } catch {
                parserLog.debug("Decode \(String(describing: type), privacy: .public) snake_case failed: \(String(describing: error), privacy: .public)")
            }
        }

        // Try with sanitization (snake_case strategy)
        if let sanitized = sanitizeJSON(jsonString),
           let data = sanitized.data(using: .utf8) {
            do {
                return try decoder.decode(type, from: data)
            } catch {
                parserLog.debug("Decode \(String(describing: type), privacy: .public) sanitized+snake_case failed: \(String(describing: error), privacy: .public)")
            }
        }

        // Try without snake_case conversion (in case keys are already camelCase)
        let plainDecoder = JSONDecoder()
        if let data = jsonString.data(using: .utf8) {
            do {
                return try plainDecoder.decode(type, from: data)
            } catch {
                parserLog.warning("Decode \(String(describing: type), privacy: .public) all strategies failed — last error: \(String(describing: error), privacy: .public)")
            }
        }

        return nil
    }

    /// Structured JSON response from step execution.
    private struct StepResultJSON: Codable {
        let needs_decision: Bool?
        let decision: DecisionJSON?
        let step_summary: String?
        let key_deliverables: [String]?
        let key_findings: [String]?

        struct DecisionJSON: Codable {
            let title: String
            let body: String
            let options: [String]
        }
    }

    private static func extractJSONFromBlock(_ block: String) -> String? {
        extractJSON(from: block)
    }

    /// Find the last balanced `{...}` object in `text` using depth counting.
    /// Handles braces inside JSON string values correctly via quote/escape tracking.
    /// Returns the last complete object -- AI responses typically place the JSON payload last.
    private static func extractBalancedJSONObject(from text: String) -> String? {
        var lastCandidate: String?
        var searchFrom = text.startIndex

        while searchFrom < text.endIndex {
            guard let openIdx = text[searchFrom...].firstIndex(of: "{") else { break }

            var depth = 0
            var inString = false
            var escaped = false
            var idx = openIdx

            while idx < text.endIndex {
                let ch = text[idx]
                if escaped {
                    escaped = false
                } else if ch == "\\" && inString {
                    escaped = true
                } else if ch == "\"" {
                    inString.toggle()
                } else if !inString {
                    if ch == "{" { depth += 1 }
                    else if ch == "}" {
                        depth -= 1
                        if depth == 0 {
                            lastCandidate = String(text[openIdx...idx])
                            break
                        }
                    }
                }
                idx = text.index(after: idx)
            }

            searchFrom = text.index(after: openIdx)
        }

        return lastCandidate
    }

    /// Find ALL balanced `{...}` objects in `text` using depth counting.
    /// Returns every complete top-level JSON object found, for Stage 4 fallback parsing.
    private static func extractAllBalancedJSONObjects(from text: String) -> [String] {
        var results: [String] = []
        var searchFrom = text.startIndex

        while searchFrom < text.endIndex {
            guard let openIdx = text[searchFrom...].firstIndex(of: "{") else { break }

            var depth = 0
            var inString = false
            var escaped = false
            var idx = openIdx

            while idx < text.endIndex {
                let ch = text[idx]
                if escaped { escaped = false }
                else if ch == "\\" && inString { escaped = true }
                else if ch == "\"" { inString.toggle() }
                else if !inString {
                    if ch == "{" { depth += 1 }
                    else if ch == "}" {
                        depth -= 1
                        if depth == 0 {
                            results.append(String(text[openIdx...idx]))
                            break
                        }
                    }
                }
                idx = text.index(after: idx)
            }

            searchFrom = text.index(after: openIdx)
        }

        return results
    }

    /// Parse [STEP_RESULT] JSON blocks from output.
    private static func parseStructuredResult(from output: String) -> StepResult? {
        let marker = "[STEP_RESULT]"
        guard output.contains(marker) else { return nil }

        let parts = output.components(separatedBy: marker)
        guard parts.count >= 2 else { return nil }

        let cleanOutput = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)

        var decision: DesignDecision?
        var stepSummary: String?
        var keyDeliverables: [String] = []
        var keyFindings: [String] = []

        for blockIndex in 1..<parts.count {
            let rawBlock = parts[blockIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let jsonString = extractJSONFromBlock(rawBlock),
                  let data = jsonString.data(using: .utf8) else { continue }

            if let parsed = try? JSONDecoder().decode(StepResultJSON.self, from: data) {
                if stepSummary == nil, let summary = parsed.step_summary, !summary.isEmpty {
                    stepSummary = summary
                }
                if keyDeliverables.isEmpty, let deliverables = parsed.key_deliverables, !deliverables.isEmpty {
                    keyDeliverables = deliverables
                }
                if keyFindings.isEmpty, let findings = parsed.key_findings, !findings.isEmpty {
                    keyFindings = findings
                }
                if decision == nil, parsed.needs_decision == true, let d = parsed.decision {
                    let options = d.options.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    decision = DesignDecision(title: d.title, body: d.body, options: options)
                }
            }
        }

        return StepResult(cleanOutput: cleanOutput, decision: decision, stepSummary: stepSummary, keyDeliverables: keyDeliverables, keyFindings: keyFindings)
    }

    /// Fallback: parse legacy [DECISION_NEEDED] text format.
    private static func parseLegacyDecision(from output: String) -> DesignDecision? {
        let marker = "[DECISION_NEEDED]"
        guard let markerRange = output.range(of: marker) else { return nil }

        let block = String(output[markerRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Try JSON in the block
        if let jsonString = extractJSON(from: block),
           let data = jsonString.data(using: .utf8),
           let parsed = try? JSONDecoder().decode(StepResultJSON.DecisionJSON.self, from: data) {
            let options = parsed.options.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return DesignDecision(title: parsed.title, body: parsed.body, options: options)
        }

        // Fallback: text-based parsing
        let lines = block.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var title = "Decision Required"
        var body = ""
        var options: [String] = []
        var currentOption: String? = nil

        func flushOption() {
            if let opt = currentOption?.trimmingCharacters(in: .whitespacesAndNewlines), !opt.isEmpty {
                options.append(opt)
            }
            currentOption = nil
        }

        for line in lines {
            let stripped = line.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .trimmingCharacters(in: .whitespaces)
            let lower = stripped.lowercased()

            if lower.hasPrefix("title:") {
                flushOption()
                title = String(stripped.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("body:") {
                flushOption()
                body = String(stripped.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("option") {
                flushOption()
                if let colonIndex = stripped.firstIndex(of: ":") {
                    currentOption = String(stripped[stripped.index(after: colonIndex)...])
                        .trimmingCharacters(in: .whitespaces)
                } else {
                    currentOption = ""
                }
            } else if currentOption != nil {
                currentOption! += (currentOption!.isEmpty ? "" : "\n") + line
            }
        }
        flushOption()

        guard !options.isEmpty || !body.isEmpty else { return nil }
        return DesignDecision(title: title, body: body, options: options)
    }
}
