import LAODomain
import LAOServices
import SwiftUI

// MARK: - TechStackEditorView

/// Compact popover editor for a project's tech stack.
/// Persists changes immediately via `ProjectService.updateProject(_:)`.
struct TechStackEditorView: View {
    @Binding var project: Project
    let container: AppContainer

    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang
    @State private var language = ""
    @State private var framework = ""
    @State private var platform = ""
    @State private var database = ""
    @State private var other = ""
    @State private var showSaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(lang.design.techStackTitle)
                .font(AppTheme.Typography.heading)

            Text(lang.design.techStackDescription)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(theme.foregroundSecondary)

            VStack(alignment: .leading, spacing: 8) {
                stackField(lang.design.techStackLanguage, text: $language, placeholder: lang.design.techStackLanguagePlaceholder)
                stackField(lang.design.techStackFramework, text: $framework, placeholder: lang.design.techStackFrameworkPlaceholder)
                stackField(lang.design.techStackPlatform, text: $platform, placeholder: lang.design.techStackPlatformPlaceholder)
                stackField(lang.design.techStackDatabase, text: $database, placeholder: lang.design.techStackDatabasePlaceholder)
                stackField(lang.design.techStackOther, text: $other, placeholder: lang.design.techStackOtherPlaceholder)
            }

            HStack {
                Spacer()
                if showSaved {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.positiveAccent)
                        Text(lang.common.saved)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(theme.foregroundSecondary)
                    }
                }
                Button(lang.common.save) {
                    Task { await save() }
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { loadFromProject() }
    }

    // MARK: - Helpers

    private func stackField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(AppTheme.Typography.caption.weight(.medium))
                .foregroundStyle(theme.foregroundTertiary)
                .frame(width: 72, alignment: .trailing)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(AppTheme.Typography.bodySecondary)
        }
    }

    private func loadFromProject() {
        let ts = project.techStack
        language = ts["language"] ?? ""
        framework = ts["framework"] ?? ""
        platform = ts["platform"] ?? ""
        database = ts["database"] ?? ""
        other = ts["other"] ?? ""
    }

    private func save() async {
        var dict: [String: String] = [:]
        let trimmed: [(String, String)] = [
            ("language", language), ("framework", framework),
            ("platform", platform), ("database", database), ("other", other)
        ]
        for (key, value) in trimmed {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { dict[key] = v }
        }

        if let data = try? JSONEncoder().encode(dict),
           let json = String(data: data, encoding: .utf8) {
            project.techStackJSON = json
        }

        try? await container.projectService.updateProject(project)

        withAnimation { showSaved = true }
        try? await Task.sleep(for: .seconds(1.5))
        withAnimation { showSaved = false }
    }
}
