import Foundation
import LAODomain
import LAOServices

/// Per-window ViewModel for a Project Workspace.
/// Each project window creates its own instance scoped to a single project.
@MainActor
final class ProjectWorkspaceViewModel: ObservableObject {
    let container: AppContainer
    let projectId: UUID

    @Published var project: Project?
    @Published var hasMissingFolder = false
    @Published var errorMessage: String?

    init(container: AppContainer, projectId: UUID) {
        self.container = container
        self.projectId = projectId
    }

    /// Load the project from DB and ensure a default board exists.
    func bootstrap() async {
        let projects = await container.projectService.listProjects()
        project = projects.first(where: { $0.id == projectId })

        hasMissingFolder = project.map {
            !FileManager.default.fileExists(atPath: $0.rootPath)
        } ?? true

        await ensureDefaultBoard()
    }

    /// Creates a default "General" board for the project if none exists.
    private func ensureDefaultBoard() async {
        let loaded = await container.boardService.listBoards(projectId: projectId)
        guard loaded.isEmpty else { return }

        do {
            _ = try await container.boardService.createBoard(
                Board(
                    projectId: projectId,
                    title: AppLanguage.currentStrings.root.defaultBoardTitle,
                    slug: "general",
                    type: .domain,
                    description: AppLanguage.currentStrings.root.defaultBoardDescription,
                    position: 0,
                    isDefault: true
                )
            )
        } catch {
            errorMessage = "Failed to create default board: \(error.localizedDescription)"
        }
    }
}
