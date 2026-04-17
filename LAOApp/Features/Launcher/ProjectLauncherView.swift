import AppKit
import LAODomain
import LAOServices
import SwiftUI
import UserNotifications

/// Project Launcher window — a standalone project list with workflow status badges.
/// Double-clicking a project opens its dedicated workspace window.
struct ProjectLauncherView: View {
    @ObservedObject var viewModel: ProjectLauncherViewModel
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.lang) private var lang

    var body: some View {
        VStack(spacing: 0) {
            projectList
        }
        .frame(minWidth: 320, minHeight: 500)
        .laoWindowBackground()
        .task {
            viewModel.notificationDelegate.launcherViewModel = viewModel
            UNUserNotificationCenter.current().delegate = viewModel.notificationDelegate

            viewModel.isBootstrapping = true
            await viewModel.container.skillSeeder.seedDefaultSkills()
            _ = try? await viewModel.container.agentSeeder.seedDefaultAgents()

            let demoProjectId: UUID?
            if let demoMode = DemoSeedMode.current {
                do {
                    demoProjectId = try await demoMode.seedIfNeeded(container: viewModel.container)
                    print("[LAO Demo] seeded mode=\(demoMode.rawValue) project=\(demoProjectId?.uuidString ?? "nil")")
                } catch {
                    demoProjectId = nil
                    print("[LAO Demo] seed failed mode=\(demoMode.rawValue) error=\(error)")
                }
            } else {
                demoProjectId = nil
            }

            await viewModel.loadProjects()
            viewModel.refreshBadges()

            if let demoProjectId {
                openWindow(value: ProjectWindowRoute(projectId: demoProjectId))
            }

            // Restore previously-open project windows and any with active workflows.
            await viewModel.restoreOpenWindows(using: { openWindow(value: $0) })

            viewModel.isBootstrapping = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .laoNavigateToRequest)) { notification in
            if let requestId = notification.object as? UUID {
                Task {
                    await viewModel.navigateToRequest(id: requestId) { route in
                        openWindow(value: route)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .laoDesignStatsChanged)) { _ in
            viewModel.refreshBadges()
        }
        .onReceive(NotificationCenter.default.publisher(for: .laoWorkflowNeedsAttention)) { _ in
            viewModel.refreshBadges()
        }
        .onReceive(NotificationCenter.default.publisher(for: .laoProjectUpdated)) { _ in
            Task {
                await viewModel.loadProjects()
                viewModel.refreshBadges()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .laoSystemNotificationTapped)) { notification in
            if let requestId = notification.object as? UUID {
                Task {
                    await viewModel.navigateToRequest(id: requestId) { route in
                        openWindow(value: route)
                    }
                }
            }
        }
    }

    // MARK: - Project List

    private var projectList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(lang.root.projects)
                    .font(AppTheme.Typography.sectionTitle.weight(.semibold))
                Spacer()
                Button {
                    Task { await viewModel.addProjectViaFolderPicker() }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(lang.root.addProjectHelp)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            if viewModel.isBootstrapping {
                Spacer()
                ProgressView()
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if viewModel.projects.isEmpty {
                Spacer()
                ContentUnavailableView(
                    lang.root.noProjectSelected,
                    systemImage: "folder",
                    description: Text(lang.root.noProjectDescription)
                )
                Spacer()
            } else {
                List(viewModel.projects) { project in
                    projectRow(project)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            openProjectWindow(project)
                        }
                        .onTapGesture(count: 1) {
                            // Single tap does nothing special in the launcher
                        }
                        .contextMenu {
                            Button {
                                openProjectWindow(project)
                            } label: {
                                Label(lang.root.open, systemImage: "macwindow")
                            }

                            if !project.rootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button(lang.common.revealInFinder) {
                                    revealProjectInFinder(project)
                                }
                            }

                            Divider()

                            Button(lang.root.removeFromApp, role: .destructive) {
                                Task { await viewModel.deleteProject(id: project.id) }
                            }
                        }
                }
                .listStyle(.sidebar)
            }

            // Footer
            VStack(spacing: 0) {
                Divider()
                Button {
                    openWindow(id: LAOWindowID.settings)
                } label: {
                    Label(lang.common.settings, systemImage: "gearshape")
                        .font(AppTheme.Typography.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.foregroundSecondary)
            }
            .background(theme.surfacePrimary.opacity(0.5))
        }
    }

    // MARK: - Project Row

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(AppTheme.Typography.heading)
                Text(project.rootPath)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(theme.foregroundSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if viewModel.projectsWithMissingFolders.contains(project.id) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(AppTheme.Typography.caption)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func openProjectWindow(_ project: Project) {
        let coord = viewModel.container.activeWorkflowCoordinator
        if coord.openProjectWindowIds.contains(project.id) {
            let windowId = NSUserInterfaceItemIdentifier("lao-project-\(project.id.uuidString)")
            if let existing = NSApp.windows.first(where: { $0.identifier == windowId && $0.isVisible }) {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
        openWindow(value: ProjectWindowRoute(projectId: project.id))
    }

    private func revealProjectInFinder(_ project: Project) {
        let trimmedPath = project.rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        let url = URL(fileURLWithPath: trimmedPath, isDirectory: true)
        // Missing folder is already signalled by the row's warning icon
        // (projectsWithMissingFolders); no need for a redundant top toast.
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
