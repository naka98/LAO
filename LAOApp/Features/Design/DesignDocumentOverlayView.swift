import SwiftUI

/// Full-screen overlay that displays design documents inside the workflow view
/// instead of opening a separate window.
struct DesignDocumentOverlayView: View {
    let items: [DesignDocumentItem]
    let onDismiss: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang
    @State private var selectedItemID: UUID?
    @State private var docMdOn = true

    private var itemsById: [UUID: DesignDocumentItem] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    var body: some View {
        ZStack {
            // Dimmed background — tap to dismiss
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Document panel
            HStack(spacing: 0) {
                sidebar
                Divider()
                detailContent
            }
            .frame(minWidth: 700, maxWidth: 1200, minHeight: 500, maxHeight: 800)
            .background(theme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 8)
        }
        .onExitCommand { onDismiss() }
        .onAppear {
            if selectedItemID == nil {
                selectedItemID = items.first?.id
            }
        }
        .transition(.opacity)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang.common.documents)
                    .font(AppTheme.Typography.heading)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(theme.foregroundTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { item in
                        sidebarRow(item)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 240)
    }

    private func sidebarRow(_ item: DesignDocumentItem) -> some View {
        let isSelected = selectedItemID == item.id
        return Button {
            selectedItemID = item.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(isSelected ? theme.accentPrimary : theme.foregroundSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(AppTheme.Typography.bodySecondary.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? theme.foregroundPrimary : theme.foregroundSecondary)

                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(theme.foregroundTertiary)
                            .lineLimit(2)
                    }

                    if let date = item.completedAt {
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                            .font(AppTheme.Typography.detail)
                            .foregroundStyle(theme.foregroundTertiary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                    .fill(isSelected ? theme.accentPrimary.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if let id = selectedItemID, let item = itemsById[id] {
            LazyDocumentContentView(item: item, docMdOn: $docMdOn)
        } else {
            ContentUnavailableView(
                lang.design.selectDocument,
                systemImage: "doc.text",
                description: Text(lang.design.selectDocumentHint)
            )
        }
    }
}

// MARK: - Lazy Document Content

/// Prepares heavy content (JSON pretty-print, line splitting) off the main thread
/// so that switching between documents feels instant.
private struct LazyDocumentContentView: View {
    let item: DesignDocumentItem
    @Binding var docMdOn: Bool

    @Environment(\.theme) private var theme
    @State private var preparedLines: [String]?
    @State private var isJSON = false
    @State private var hasMarkdown = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundSecondary)
                }
                Divider()
                contentBody
            }
            .padding(24)
        }
        .task(id: item.id) {
            // Reset immediately so stale content from previous doc doesn't linger
            preparedLines = nil
            let content = item.content
            let result = await Task.detached(priority: .userInitiated) {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                let json = (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
                    || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
                let md = json ? false : MarkdownSupport.containsMarkdown(content)
                let lines: [String]
                if json {
                    let pretty = prettyPrintJSON(content)
                    lines = pretty.components(separatedBy: "\n")
                } else if !md {
                    lines = content.components(separatedBy: "\n")
                } else {
                    lines = []
                }
                return (lines, json, md)
            }.value
            preparedLines = result.0
            isJSON = result.1
            hasMarkdown = result.2
        }
    }

    private var header: some View {
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
    }

    @ViewBuilder
    private var contentBody: some View {
        if let lines = preparedLines {
            if isJSON {
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
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else {
            // Loading state while content is being prepared
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 60)
        }
    }
}

private func prettyPrintJSON(_ content: String) -> String {
    guard let data = content.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data),
          let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
          let str = String(data: pretty, encoding: .utf8) else {
        return content
    }
    return str
}
