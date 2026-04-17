import AppKit
import Combine
import Foundation
import LAODomain
import LAORuntime
import LAOServices

/// ViewModel for the Project Launcher window.
/// Manages the project list and provides workflow status badges per project.
@MainActor
final class ProjectLauncherViewModel: ObservableObject {
    let container: AppContainer
    /// Strong reference to keep the notification delegate alive (UNUserNotificationCenter.delegate is weak).
    let notificationDelegate = LAONotificationDelegate()

    @Published var projects: [Project] = []
    @Published var errorMessage: String?
    @Published var projectsWithMissingFolders: Set<UUID> = []
    @Published var isBootstrapping = true
    /// Cached badge data per project, updated reactively via refreshBadges().
    @Published var badges: [UUID: WorkflowBadge] = [:]

    init(container: AppContainer) {
        self.container = container
    }

    // MARK: - Project List

    func loadProjects() async {
        projects = await container.projectService.listProjects()
        validateProjectFolders()
    }

    func validateProjectFolders() {
        projectsWithMissingFolders = Set(
            projects
                .filter { !FileManager.default.fileExists(atPath: $0.rootPath) }
                .map { $0.id }
        )
    }

    func addProjectViaFolderPicker() async {
        let lang = AppLanguage.currentStrings
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = lang.root.addProject
        panel.message = lang.root.selectProjectFolder

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        SecurityScopedBookmarkStore.shared.saveBookmark(for: url)

        let folderName = url.lastPathComponent
        let rootPath = url.path

        if projects.contains(where: { $0.rootPath == rootPath }) {
            errorMessage = lang.root.folderAlreadyAdded
            return
        }

        do {
            let project = try await container.projectService.createProject(name: folderName, rootPath: rootPath)
            projects.insert(project, at: 0)
            refreshBadges()
        } catch {
            errorMessage = lang.root.failedToAddProjectFormat(error.localizedDescription)
        }
    }

    func deleteProject(id: UUID) async {
        do {
            try await container.projectService.deleteProject(id: id)
            projects.removeAll(where: { $0.id == id })
            refreshBadges()
            NotificationCenter.default.post(name: .laoProjectDeleted, object: id)
        } catch {
            let lang = AppLanguage.currentStrings
            errorMessage = lang.root.failedToDeleteProjectFormat(error.localizedDescription)
        }
    }

    func reSelectProjectFolder(for projectId: UUID) async {
        let lang = AppLanguage.currentStrings
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = lang.root.selectFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard var project = projects.first(where: { $0.id == projectId }) else { return }
        project.rootPath = url.path

        SecurityScopedBookmarkStore.shared.saveBookmark(for: url)
        do {
            try await container.projectService.updateProject(project)
            await loadProjects()
            NotificationCenter.default.post(name: .laoProjectUpdated, object: projectId)
        } catch {
            errorMessage = lang.root.failedToUpdateFolderFormat(error.localizedDescription)
        }
    }

    // MARK: - Workflow Status Badges

    struct WorkflowBadge {
        let running: Int
        let queued: Int
        let attention: Int
    }

    /// Recompute badges for all projects. Called when workflow state changes.
    func refreshBadges() {
        let coord = container.activeWorkflowCoordinator
        var updated: [UUID: WorkflowBadge] = [:]
        for project in projects {
            let pid = project.id
            let running = coord.activePerProject[pid] != nil ? 1 : 0
            let queued = coord.executionQueue[pid]?.count ?? 0
            let attention = coord.attentionCountPerProject[pid] ?? 0
            if running > 0 || queued > 0 || attention > 0 {
                updated[pid] = WorkflowBadge(running: running, queued: queued, attention: attention)
            }
        }
        badges = updated
    }

    // MARK: - Window Restoration

    /// On app launch, restore previously-open project windows (persisted in UserDefaults)
    /// and any projects with active workflows in the DB.
    func restoreOpenWindows(using openWindow: (ProjectWindowRoute) -> Void) async {
        let persisted = ActiveWorkflowCoordinator.loadPersistedOpenWindows()
        let activeFromDB = await container.designSessionService
            .listRequestsByStatuses([.executing, .reviewing])
        let activeProjectIds = Set(activeFromDB.map(\.projectId))

        let toRestore = persisted.union(activeProjectIds)
        let allProjects = Set(projects.map(\.id))
        let alreadyOpen = container.activeWorkflowCoordinator.openProjectWindowIds

        for pid in toRestore where allProjects.contains(pid) && !alreadyOpen.contains(pid) {
            openWindow(ProjectWindowRoute(projectId: pid))
        }
    }

    // MARK: - Deep Link Navigation

    /// Navigate to a specific workflow request by opening the project's workspace window
    /// and posting a scoped deep-link notification.
    func navigateToRequest(id requestId: UUID, using openWindow: (ProjectWindowRoute) -> Void) async {
        guard let request = await container.designSessionService.getRequest(id: requestId) else { return }

        let projectId = request.projectId
        let windowAlreadyOpen = container.activeWorkflowCoordinator
            .openProjectWindowIds.contains(projectId)

        // Store the deep link so a newly-opening workspace view can consume it
        // via consumePendingDeepLink() in its .task modifier.
        container.activeWorkflowCoordinator.setPendingDeepLink(
            projectId: projectId, requestId: requestId)

        // Open (or focus) the project workspace window and bring LAO to the foreground.
        // This is essential for system notification taps where LAO may be behind other apps.
        openWindow(ProjectWindowRoute(projectId: projectId))
        NSApp.activate(ignoringOtherApps: true)

        // For already-open windows, post the notification immediately —
        // their .onReceive is already attached so no delay is needed.
        // New windows will consume pendingDeepLinks in .task instead.
        if windowAlreadyOpen {
            let payload = DeepLinkPayload(projectId: projectId, requestId: requestId)
            NotificationCenter.default.post(name: .laoDeepLinkRequest, object: payload)
        }
    }
}
