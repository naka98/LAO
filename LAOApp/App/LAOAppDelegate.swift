import AppKit

/// Handles app-level lifecycle events that SwiftUI Scene API does not cover,
/// such as guarding Cmd+Q when workflows are actively running.
@MainActor
final class LAOAppDelegate: NSObject, NSApplicationDelegate {
    var activeWorkflowCoordinator: ActiveWorkflowCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable automatic window tabbing — the app uses hiddenTitleBar,
        // so tab-related menu items ("Show Tab Bar", "Show All Tabs") are non-functional.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coord = activeWorkflowCoordinator else {
            return .terminateNow
        }

        // Persist open window state before quitting so they can be restored on next launch.
        // Set isTerminating to prevent subsequent window-close callbacks from overwriting
        // this snapshot with progressively smaller sets.
        coord.persistOpenWindows()
        coord.isTerminating = true

        guard !coord.activePerProject.isEmpty else {
            return .terminateNow
        }

        let lang = AppLanguage.currentStrings
        let count = coord.activePerProject.count
        let alert = NSAlert()
        alert.messageText = lang.root.activeWorkflowsQuitTitle
        alert.informativeText = lang.root.activeWorkflowsQuitMessageFormat(count)
        alert.addButton(withTitle: lang.root.quitButton)
        alert.addButton(withTitle: lang.common.cancel)
        alert.alertStyle = .warning

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            return .terminateNow
        }
        // User cancelled quit — resume normal persistence.
        coord.isTerminating = false
        return .terminateCancel
    }
}
