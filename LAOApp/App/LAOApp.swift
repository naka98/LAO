import LAORuntime
import SwiftUI
import UserNotifications
#if canImport(AppKit)
import AppKit
#endif

enum LAOWindowID {
    static let launcher = "lao-launcher"
    static let projectWorkspace = "lao-project"
    static let settings = "lao-settings"
    static let designDocument = "lao-design-document"
}

extension Notification.Name {
    static let laoDesignStatsChanged = Notification.Name("lao.designStatsChanged")
    static let laoWorkflowNeedsAttention = Notification.Name("lao.workflowNeedsAttention")
    static let laoDeepLinkRequest = Notification.Name("lao.deepLinkRequest")
    static let laoNavigateToRequest = Notification.Name("lao.navigateToRequest")
    static let laoLanguageChanged = Notification.Name("lao.languageChanged")
    /// Posted by LAONotificationDelegate when user taps a system notification.
    /// The delegate cannot call openWindow directly, so the launcher view observes this.
    static let laoSystemNotificationTapped = Notification.Name("lao.systemNotificationTapped")
    /// Posted when a project is deleted. Workspace windows for that project should close.
    static let laoProjectDeleted = Notification.Name("lao.projectDeleted")
    /// Posted when a project's folder path changes. Other windows should reload.
    static let laoProjectUpdated = Notification.Name("lao.projectUpdated")
}

@main
struct LAOApp: App {
    @NSApplicationDelegateAdaptor(LAOAppDelegate.self) private var appDelegate
    @StateObject private var launcherViewModel = ProjectLauncherViewModel(container: .liveOrPreview)
    @StateObject private var designDocumentWindowCoordinator = DesignDocumentWindowCoordinator()
    @State private var appLanguage: AppLanguage = {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: AppLanguage.userDefaultsKey) ?? "en") ?? .en
    }()
    private let windowLayoutMode = LAOWindowLayoutMode.current

    init() {
#if canImport(AppKit)
        NSApplication.shared.setActivationPolicy(.regular)
#endif
        SecurityScopedBookmarkStore.shared.restoreAllBookmarks()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        // 1) Project Launcher — single window showing the project list
        Window("LAO", id: LAOWindowID.launcher) {
            LanguageInjector(language: appLanguage) {
                ThemeInjector {
                    ProjectLauncherView(viewModel: launcherViewModel)
                }
            }
            .task {
                appDelegate.activeWorkflowCoordinator = launcherViewModel.container.activeWorkflowCoordinator
                await loadLanguage()
            }
            .onReceive(NotificationCenter.default.publisher(for: .laoLanguageChanged)) { notification in
                if let rawValue = notification.object as? String,
                   let lang = AppLanguage(rawValue: rawValue) {
                    appLanguage = lang
                }
            }
        }
        .defaultSize(
            width: windowLayoutMode.launcherDefaultSize.width,
            height: windowLayoutMode.launcherDefaultSize.height
        )

        // 2) Project Workspace — one window per project
        WindowGroup(id: LAOWindowID.projectWorkspace, for: ProjectWindowRoute.self) { route in
            LanguageInjector(language: appLanguage) {
                ThemeInjector {
                    ProjectWorkspaceView(
                        route: route.wrappedValue,
                        container: launcherViewModel.container
                    )
                    .environmentObject(designDocumentWindowCoordinator)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        .defaultSize(
            width: windowLayoutMode.workspaceDefaultSize.width,
            height: windowLayoutMode.workspaceDefaultSize.height
        )

        // 3) Settings
        Window("LAO Settings", id: LAOWindowID.settings) {
            LanguageInjector(language: appLanguage) {
                ThemeInjector {
                    GeneralSettingsTabView(container: launcherViewModel.container)
                        .frame(
                            minWidth: windowLayoutMode.settingsMinimumSize.width,
                            minHeight: windowLayoutMode.settingsMinimumSize.height
                        )
                }
            }
        }
        .restorationBehavior(.disabled)
        .defaultSize(
            width: windowLayoutMode.settingsDefaultSize.width,
            height: windowLayoutMode.settingsDefaultSize.height
        )

        // 4) Design Documents
        WindowGroup("Design Documents", id: LAOWindowID.designDocument, for: DesignDocumentWindowRoute.self) { route in
            LanguageInjector(language: appLanguage) {
                ThemeInjector {
                    DesignDocumentWindowView(
                        route: route.wrappedValue,
                        coordinator: designDocumentWindowCoordinator
                    )
                }
            }
        }
        .restorationBehavior(.disabled)
        .defaultSize(width: 700, height: 600)

        .commands {
            LauncherCommands()
            SettingsCommands()
            MenuCleanupCommands()
        }
    }

    private func loadLanguage() async {
        let settings = await launcherViewModel.container.appSettingsService.getSettings()
        if let lang = AppLanguage(rawValue: settings.language) {
            appLanguage = lang
            UserDefaults.standard.set(lang.rawValue, forKey: AppLanguage.userDefaultsKey)
        }
    }
}

// MARK: - Notification Delegate

/// Handles macOS notification taps and navigates to the relevant workflow request.
/// Cannot call openWindow directly (requires @Environment), so it posts a notification
/// that the launcher view observes.
@MainActor
final class LAONotificationDelegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    weak var launcherViewModel: ProjectLauncherViewModel?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let prefix = "lao-attention-"
        if identifier.hasPrefix(prefix),
           let uuid = UUID(uuidString: String(identifier.dropFirst(prefix.count))) {
            NotificationCenter.default.post(name: .laoSystemNotificationTapped, object: uuid)
        }
        completionHandler()
    }

    /// Show notification banners even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

private struct LauncherCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(AppLanguage.currentStrings.root.menuShowLauncher) {
                openWindow(id: LAOWindowID.launcher)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

private struct SettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(AppLanguage.currentStrings.root.menuSettings) {
                openWindow(id: LAOWindowID.settings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

/// Removes non-functional menu items caused by `.windowStyle(.hiddenTitleBar)`.
private struct MenuCleanupCommands: Commands {
    var body: some Commands {
        // View > Show Toolbar — no toolbar exists
        CommandGroup(replacing: .toolbar) { }
        // View > Toggle Sidebar — no NavigationSplitView sidebar
        CommandGroup(replacing: .sidebar) { }
        // Window > Show Tab Bar / Merge All Windows — no title bar = no tab bar
        CommandGroup(replacing: .windowList) { }
        // Help — no content
        CommandGroup(replacing: .help) { }
    }
}
