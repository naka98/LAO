import AppKit
import Foundation
import SwiftUI

enum MarkdownSupport {
    static func containsMarkdown(_ content: String) -> Bool {
        // JSON is not markdown
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            return false
        }

        // Fast string-level checks first (O(n) scan, no splitting)
        if content.contains("**") || content.contains("`") { return true }

        let lines = content.components(separatedBy: "\n").prefix(200)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ")
                || trimmed.hasPrefix("## ")
                || trimmed.hasPrefix("### ")
                || trimmed.hasPrefix("- ")
                || trimmed.hasPrefix("> ")
                || trimmed.hasPrefix("```")
                || trimmed == "---"
                || trimmed == "***" {
                return true
            }
        }

        return false
    }
}

struct MarkdownTextView: View {
    @Environment(\.theme) private var theme

    let content: String
    var workspaceRootPath: String = ""
    var mentionNames: [String] = []
    var fontSize: CGFloat = 13
    var lineSpacing: CGFloat = 4

    @State private var cachedBlocks: [MdBlock] = []

    // MARK: - Cached Regex (compiled once)

    private static let boldOpenRegex = try! NSRegularExpression(pattern: #"\*\*([""''「」『』\(\[{<])"#)
    private static let boldCloseRegex = try! NSRegularExpression(pattern: #"([""''」』\)\]}>])\*\*"#)
    private static let urlRegex = try! NSRegularExpression(pattern: #"(?i)\bhttps?://[^\s<>()\[\]]+[^\s<>().,\]\)]"#)
    private static let filePathRegex = try! NSRegularExpression(pattern: #"(?<!\S)(/(?:[^\s\)\]\}\>,;:]+/)*[^\s\)\]\}\>,;:]+|\.lao/(?:[^\s\)\]\}\>,;:]+/)*[^\s\)\]\}\>,;:]+|(?:\./|\.\./)(?:[^\s\)\]\}\>,;:]+/)*[^\s\)\]\}\>,;:]+)(?::\d+(?::\d+)?)?"#)
    private static let lineSuffixRegex = try! NSRegularExpression(pattern: #":\d+(?::\d+)?$"#)
    private static let numberedListRegex = try! NSRegularExpression(pattern: #"^\d+\.\s+"#)

    var body: some View {
        if cachedBlocks.isEmpty && !content.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
        LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(Array(cachedBlocks.enumerated()), id: \.offset) { _, block in
                blockElementView(block)
            }
        }
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            if url.isFileURL {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            } else {
                NSWorkspace.shared.open(url)
            }
            return .handled
        })
        .onAppear { parseAsync(content) }
        .onChange(of: content) { _, newValue in parseAsync(newValue) }
    }

    private enum MdBlock {
        case h1(String)
        case h2(String)
        case h3(String)
        case h4(String)
        case bullet(String)
        case numbered(String, String)
        case codeBlock(String)
        case quote(String)
        case horizontalRule
        case table(header: [String], rows: [[String]])
        case text(String)
        case blank
    }

    private func parseAsync(_ text: String) {
        Task.detached { [text] in
            let blocks = Self.parseMarkdownBlocks(text)
            await MainActor.run { cachedBlocks = blocks }
        }
    }

    nonisolated private static func parseMarkdownBlocks(_ content: String) -> [MdBlock] {
        var result: [MdBlock] = []
        let lines = content.components(separatedBy: "\n")
        var inCode = false
        var codeLines: [String] = []
        var tableLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if !tableLines.isEmpty {
                    result.append(flushTable(&tableLines))
                }
                if inCode {
                    result.append(.codeBlock(codeLines.joined(separator: "\n")))
                    codeLines = []
                }
                inCode.toggle()
                continue
            }

            if inCode {
                codeLines.append(line)
                continue
            }

            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                tableLines.append(trimmed)
                continue
            }

            if !tableLines.isEmpty {
                result.append(flushTable(&tableLines))
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                result.append(.horizontalRule)
            } else if trimmed.hasPrefix("#### ") {
                result.append(.h4(String(trimmed.dropFirst(5))))
            } else if trimmed.hasPrefix("### ") {
                result.append(.h3(String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                result.append(.h2(String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                result.append(.h1(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("- ") {
                result.append(.bullet(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("* ") && !trimmed.hasPrefix("**") {
                result.append(.bullet(String(trimmed.dropFirst(2))))
            } else if let nsMatch = Self.numberedListRegex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  let match = Range(nsMatch.range, in: trimmed) {
                let number = String(trimmed[..<match.upperBound])
                let text = String(trimmed[match.upperBound...])
                result.append(.numbered(number, text))
            } else if trimmed.hasPrefix("> ") {
                result.append(.quote(String(trimmed.dropFirst(2))))
            } else if trimmed.isEmpty {
                result.append(.blank)
            } else {
                result.append(.text(line))
            }
        }

        if !tableLines.isEmpty {
            result.append(flushTable(&tableLines))
        }
        if inCode && !codeLines.isEmpty {
            result.append(.codeBlock(codeLines.joined(separator: "\n")))
        }

        return result
    }

    nonisolated private static func flushTable(_ lines: inout [String]) -> MdBlock {
        let parsed = lines
        lines = []
        var rows: [[String]] = []

        for line in parsed {
            let cells = parseTableRow(line)
            let isSeparator = cells.allSatisfy { cell in
                cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
            }
            if !isSeparator {
                rows.append(cells)
            }
        }

        guard !rows.isEmpty else { return .blank }
        return .table(header: rows[0], rows: Array(rows.dropFirst()))
    }

    nonisolated private static func parseTableRow(_ line: String) -> [String] {
        var stripped = line.trimmingCharacters(in: .whitespaces)
        if stripped.hasPrefix("|") {
            stripped = String(stripped.dropFirst())
        }
        if stripped.hasSuffix("|") {
            stripped = String(stripped.dropLast())
        }
        return stripped.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    @ViewBuilder
    private func blockElementView(_ block: MdBlock) -> some View {
        switch block {
        case .h1(let text):
            inlineMarkdownText(text)
                .font(.system(size: fontSize + 5, weight: .bold))
                .padding(.top, 4)

        case .h2(let text):
            inlineMarkdownText(text)
                .font(.system(size: fontSize + 3, weight: .semibold))
                .padding(.top, 2)

        case .h3(let text):
            inlineMarkdownText(text)
                .font(.system(size: fontSize + 1, weight: .semibold))
                .padding(.top, 2)

        case .h4(let text):
            inlineMarkdownText(text)
                .font(.system(size: fontSize, weight: .medium))
                .padding(.top, 1)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                    .font(.system(size: fontSize))
                inlineMarkdownText(text)
            }

        case .numbered(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(number)
                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.foregroundSecondary)
                inlineMarkdownText(text)
            }

        case .codeBlock(let code):
            let codeLines = code.components(separatedBy: "\n")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(codeLines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(size: max(fontSize - 1, 11), design: .monospaced))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(10)
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(theme.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .stroke(theme.borderSubtle, lineWidth: 1)
            )
            .padding(.vertical, 2)

        case .quote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(theme.accentPrimary.opacity(0.45))
                    .frame(width: 3)
                inlineMarkdownText(text)
                    .foregroundStyle(theme.foregroundSecondary)
            }
            .padding(.vertical, 1)

        case .horizontalRule:
            Divider()
                .padding(.vertical, 4)

        case .table(let header, let rows):
            tableView(header: header, rows: rows)

        case .text(let text):
            inlineMarkdownText(text)

        case .blank:
            Spacer()
                .frame(height: 4)
        }
    }

    @ViewBuilder
    private func tableView(header: [String], rows: [[String]]) -> some View {
        let columnCount = header.count

        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(0..<columnCount, id: \.self) { column in
                        inlineMarkdownText(header[column])
                            .font(.system(size: max(fontSize - 1, 11), weight: .semibold))
                            .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                }
                .background(Color.primary.opacity(0.06))

                Divider()

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { column in
                            let cell = column < row.count ? row[column] : ""
                            inlineMarkdownText(cell)
                                .font(.system(size: max(fontSize - 1, 11)))
                                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                        }
                    }

                    if rowIndex < rows.count - 1 {
                        Divider().opacity(0.5)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .padding(.vertical, 2)
    }

    private func inlineMarkdownText(_ text: String) -> some View {
        let attributed = inlineAttributedString(text)

        return Text(attributed)
            .font(.system(size: fontSize))
            .lineSpacing(lineSpacing)
    }

    private func inlineAttributedString(_ text: String) -> AttributedString {
        // Preprocess: insert zero-width spaces so Swift's markdown parser handles
        // bold/italic around punctuation (e.g. **"A"** → ** "A" ** internally)
        let preprocessed = preprocessBoldDelimiters(text)

        var attributed = (try? AttributedString(
            markdown: preprocessed,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)

        normalizeExistingLinks(in: &attributed)
        applyRawURLLinks(to: &attributed)
        if !workspaceRootPath.isEmpty {
            applyFilePathLinks(to: &attributed)
        }
        if !mentionNames.isEmpty {
            highlightMentions(in: &attributed)
        }

        return attributed
    }

    /// Fix bold/italic delimiters around punctuation characters.
    /// Swift's AttributedString(markdown:) fails on patterns like **"A"** or **'B'**
    /// because punctuation right after ** breaks CommonMark delimiter rules.
    /// Insert zero-width spaces to work around this.
    private func preprocessBoldDelimiters(_ text: String) -> String {
        var result = text
        let zwsp = "\u{200B}" // zero-width space

        result = Self.boldOpenRegex.stringByReplacingMatches(
            in: result, range: NSRange(result.startIndex..., in: result),
            withTemplate: "**\(zwsp)$1"
        )
        result = Self.boldCloseRegex.stringByReplacingMatches(
            in: result, range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1\(zwsp)**"
        )

        return result
    }

    private func normalizeExistingLinks(in attributed: inout AttributedString) {
        for run in attributed.runs {
            guard let url = run.link else { continue }
            let urlString = url.absoluteString

            if urlString.hasPrefix("file://")
                || urlString.hasPrefix("http://")
                || urlString.hasPrefix("https://") {
                continue
            }

            if urlString.hasPrefix("/") {
                attributed[run.range].link = URL(fileURLWithPath: urlString)
            } else {
                attributed[run.range].link = nil
            }
        }
    }

    private func applyRawURLLinks(to attributed: inout AttributedString) {
        let plain = String(attributed.characters)
        let nsPlain = plain as NSString
        let matches = Self.urlRegex.matches(in: plain, range: NSRange(location: 0, length: nsPlain.length))

        for match in matches.reversed() {
            let candidate = nsPlain.substring(with: match.range)
            guard let url = URL(string: candidate),
                  let swiftRange = Range(match.range, in: plain),
                  let attributedRange = Range(swiftRange, in: attributed) else { continue }
            attributed[attributedRange].link = url
        }
    }

    private func applyFilePathLinks(to attributed: inout AttributedString) {
        let plain = String(attributed.characters)
        let nsPlain = plain as NSString
        let matches = Self.filePathRegex.matches(in: plain, range: NSRange(location: 0, length: nsPlain.length))

        for match in matches.reversed() {
            let candidate = nsPlain.substring(with: match.range)
            guard let url = resolvedFileURL(for: candidate),
                  let swiftRange = Range(match.range, in: plain),
                  let attributedRange = Range(swiftRange, in: attributed) else { continue }
            attributed[attributedRange].link = url
        }
    }

    private func resolvedFileURL(for candidate: String) -> URL? {
        let filePath = strippedLineSuffix(from: candidate)
        let resolvedPath: String

        if filePath.hasPrefix("/") {
            resolvedPath = filePath
        } else if filePath.hasPrefix(".lao/") || filePath.hasPrefix("./") || filePath.hasPrefix("../") {
            guard !workspaceRootPath.isEmpty else { return nil }
            resolvedPath = URL(fileURLWithPath: workspaceRootPath)
                .appendingPathComponent(filePath)
                .standardizedFileURL
                .path
        } else {
            return nil
        }

        guard FileManager.default.fileExists(atPath: resolvedPath) else { return nil }
        return URL(fileURLWithPath: resolvedPath)
    }

    private func strippedLineSuffix(from candidate: String) -> String {
        let nsCandidate = candidate as NSString
        let range = NSRange(location: 0, length: nsCandidate.length)
        return Self.lineSuffixRegex.stringByReplacingMatches(in: candidate, range: range, withTemplate: "")
    }

    private func highlightMentions(in attributed: inout AttributedString) {
        let names = mentionNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        guard !names.isEmpty else { return }

        let escaped = names.map(NSRegularExpression.escapedPattern(for:))
        let pattern = "@(" + escaped.joined(separator: "|") + ")"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let plain = String(attributed.characters)
        let nsPlain = plain as NSString
        let matches = regex.matches(in: plain, range: NSRange(location: 0, length: nsPlain.length))

        for match in matches.reversed() {
            guard let swiftRange = Range(match.range, in: plain),
                  let attributedRange = Range(swiftRange, in: attributed) else { continue }
            attributed[attributedRange].foregroundColor = theme.accentPrimary
        }
    }
}

struct MarkdownActionToolbar: View {
    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang

    let hasMarkdown: Bool
    let markdownOn: Bool
    let copyText: String
    let onToggleMarkdown: (() -> Void)?

    @State private var didCopyContent = false

    var body: some View {
        HStack(spacing: 4) {
            if hasMarkdown, let onToggleMarkdown {
                Button(action: onToggleMarkdown) {
                    Text("MD")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))  // intentional: monospaced badge
                        .foregroundStyle(markdownOn ? theme.accentPrimary : theme.foregroundSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous)
                                .fill(markdownOn ? theme.accentPrimary.opacity(0.1) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous)
                                .stroke(
                                    markdownOn ? theme.accentPrimary.opacity(0.3) : theme.borderSubtle,
                                    lineWidth: 0.5
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(markdownOn ? lang.common.plainText : lang.common.markdown)
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyText, forType: .string)
                didCopyContent = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    didCopyContent = false
                }
            } label: {
                Image(systemName: didCopyContent ? "checkmark" : "doc.on.doc")
                    .font(AppTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(didCopyContent ? theme.positiveAccent : theme.foregroundSecondary)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous)
                            .fill(didCopyContent ? theme.positiveAccent.opacity(0.1) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.xs, style: .continuous)
                            .stroke(theme.borderSubtle, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help(lang.common.copy)
        }
    }
}
