import SwiftUI

struct DesignDocumentWindowView: View {
    let route: DesignDocumentWindowRoute?
    @ObservedObject var coordinator: DesignDocumentWindowCoordinator

    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang
    @State private var selectedItemID: UUID?
    @State private var docMdOn = true

    private var items: [DesignDocumentItem] {
        guard let sessionID = route?.sessionID else { return [] }
        return coordinator.items(for: sessionID) ?? []
    }

    private var itemsById: [UUID: DesignDocumentItem] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            detailContent
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            if let sessionID = route?.sessionID,
               let pending = coordinator.consumePendingSelection(for: sessionID) {
                selectedItemID = pending
            } else if selectedItemID == nil {
                selectedItemID = items.first?.id
            }
        }
        .onChange(of: coordinator.pendingSelection) { _, pending in
            guard let sessionID = route?.sessionID,
                  let targetID = pending[sessionID] else { return }
            selectedItemID = targetID
            coordinator.pendingSelection.removeValue(forKey: sessionID)
        }
        .onDisappear {
            if let sessionID = route?.sessionID {
                coordinator.cleanup(for: sessionID)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(items, selection: $selectedItemID) { item in
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(theme.accentPrimary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(AppTheme.Typography.bodySecondary.weight(.medium))
                        .lineLimit(1)

                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(theme.foregroundSecondary)
                            .lineLimit(2)
                    }

                    if let date = item.completedAt {
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                            .font(AppTheme.Typography.detail)
                            .foregroundStyle(theme.foregroundTertiary)
                    }
                }
            }
            .padding(.vertical, 4)
            .tag(item.id)
        }
        .listStyle(.sidebar)
        .navigationTitle(lang.common.documents)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if let id = selectedItemID, let item = itemsById[id] {
            documentContentView(item)
                .id(item.id)
        } else {
            ContentUnavailableView(lang.design.selectDocument, systemImage: "doc.text", description: Text(lang.design.selectDocumentHint))
        }
    }

    private static func prettyPrintJSON(_ content: String) -> String {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
              let str = String(data: pretty, encoding: .utf8) else {
            return content
        }
        return str
    }

    private func looksLikeJSON(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }

    private func documentContentView(_ item: DesignDocumentItem) -> some View {
        let isJSON = looksLikeJSON(item.content)
        let hasMarkdown = isJSON ? false : MarkdownSupport.containsMarkdown(item.content)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(item.title, systemImage: item.icon)
                        .font(AppTheme.Typography.heading)

                    Spacer()

                    MarkdownActionToolbar(
                        hasMarkdown: hasMarkdown,
                        markdownOn: docMdOn,
                        copyText: item.content,
                        onToggleMarkdown: { docMdOn.toggle() }
                    )
                }

                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundSecondary)
                }

                Divider()

                if isJSON {
                    let pretty = Self.prettyPrintJSON(item.content)
                    let lines = pretty.components(separatedBy: "\n")
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                Text(line.isEmpty ? " " : line)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .padding(10)
                    }
                } else if docMdOn && hasMarkdown {
                    MarkdownTextView(content: item.content, fontSize: 12, lineSpacing: 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let lines = item.content.components(separatedBy: "\n")
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}
