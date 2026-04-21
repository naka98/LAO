import AppKit
import LAODomain
import LAORuntime
import LAOServices
import SwiftUI

/// Per-project workspace window view.
/// Each project gets its own independent window containing the full idea lifecycle.
struct ProjectWorkspaceView: View {
    let route: ProjectWindowRoute?
    let container: AppContainer

    @StateObject private var viewModel: ProjectWorkspaceViewModel
    @State private var isBootstrapping = true
    @State private var showCloseConfirmation = false

    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang

    private let windowLayoutMode = LAOWindowLayoutMode.current

    init(route: ProjectWindowRoute?, container: AppContainer) {
        self.route = route
        self.container = container
        let pid = route?.projectId ?? UUID()
        _viewModel = StateObject(wrappedValue:
            ProjectWorkspaceViewModel(container: container, projectId: pid))
    }

    var body: some View {
        Group {
            if isBootstrapping {
                ContentUnavailableView(
                    lang.root.preparingWorkspace,
                    systemImage: "hourglass",
                    description: Text(lang.root.loadingProjects)
                )
                .accessibilityIdentifier("workspace-bootstrapping")
            } else if let project = viewModel.project {
                if viewModel.hasMissingFolder {
                    ContentUnavailableView {
                        Label(lang.root.projectNotFound, systemImage: "questionmark.folder")
                    } description: {
                        Text(lang.root.projectFolderMissingDescription)
                    } actions: {
                        Button(lang.root.reSelectFolder) {
                            Task { await reSelectFolder(for: project.id) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .accessibilityIdentifier("workspace-folder-missing")
                } else {
                    IdeaBoardView(
                        project: project,
                        container: container
                    )
                    .id(project.id)
                    .accessibilityIdentifier("workspace-idea-board")
                }
            } else {
                ContentUnavailableView(
                    lang.root.noProjectSelected,
                    systemImage: "folder",
                    description: Text(lang.root.noProjectDescription)
                )
            }
        }
        .frame(
            minWidth: windowLayoutMode.workspaceMinimumSize.width,
            minHeight: windowLayoutMode.workspaceMinimumSize.height
        )
        .background(WindowTitle(
            title: viewModel.project?.name ?? "LAO",
            identifier: "lao-project-\(viewModel.projectId.uuidString)"
        ))
        .background(
            WindowCloseGuard(
                shouldPreventClose: { hasActiveWorkflow },
                onCloseAttempt: { showCloseConfirmation = true },
                onWindowClose: {
                    container.activeWorkflowCoordinator.openProjectWindowIds.remove(viewModel.projectId)
                    container.activeWorkflowCoordinator.pruneInactive(for: viewModel.projectId)
                }
            )
        )
        .onAppear {
            container.activeWorkflowCoordinator.openProjectWindowIds.insert(viewModel.projectId)
        }
        .confirmationDialog(
            lang.root.activeWorkflowTitle,
            isPresented: $showCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button(lang.root.closeAnywayButton, role: .destructive) {
                // Workflow continues in the background via ActiveWorkflowCoordinator.
                // Force-close the window.
                NSApp.keyWindow?.close()
            }
            Button(lang.common.cancel, role: .cancel) { }
        } message: {
            Text(lang.root.workflowRunningCloseMessage)
        }
        .task {
            isBootstrapping = true
            await viewModel.bootstrap()
            isBootstrapping = false
            // If the project no longer exists (e.g. restored window for a deleted project),
            // close the window automatically.
            if viewModel.project == nil {
                closeOwnWindow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .laoProjectDeleted)) { notification in
            if let deletedId = notification.object as? UUID, deletedId == viewModel.projectId {
                container.activeWorkflowCoordinator.openProjectWindowIds.remove(viewModel.projectId)
                closeOwnWindow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .laoProjectUpdated)) { notification in
            if let updatedId = notification.object as? UUID, updatedId == viewModel.projectId {
                Task { await viewModel.bootstrap() }
            }
        }
    }

    private var hasActiveWorkflow: Bool {
        container.activeWorkflowCoordinator.activePerProject[viewModel.projectId] != nil
    }

    /// Close this view's own NSWindow by matching the identifier injected via WindowTitle.
    /// Avoids relying on NSApp.keyWindow, which may point to the launcher when the
    /// close is triggered remotely (e.g. project deletion from the launcher's context menu).
    private func closeOwnWindow() {
        let id = NSUserInterfaceItemIdentifier("lao-project-\(viewModel.projectId.uuidString)")
        NSApp.windows.first { $0.identifier == id }?.close()
    }

    // MARK: - Actions

    private func reSelectFolder(for projectId: UUID) async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = lang.root.selectFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard var project = viewModel.project else { return }
        project.rootPath = url.path

        SecurityScopedBookmarkStore.shared.saveBookmark(for: url)
        do {
            try await container.projectService.updateProject(project)
            await viewModel.bootstrap()
            NotificationCenter.default.post(name: .laoProjectUpdated, object: projectId)
        } catch {
            viewModel.errorMessage = lang.root.failedToUpdateFolderFormat(error.localizedDescription)
        }
    }
}
