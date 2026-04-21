import Foundation

struct DesignDocumentWindowRoute: Hashable, Codable, Sendable {
    let sessionID: String
}

struct DesignDocumentItem: Identifiable {
    let id: UUID
    let title: String
    let icon: String
    let summary: String
    let content: String
    let completedAt: Date?
}

/// Bridges the completed-phase export to macOS's multi-window system.
/// Stores exported DesignDocumentItem arrays keyed by sessionID so `DesignDocumentWindowView`
/// (opened as a separate window scene) can fetch them after the window appears.
///
/// [Trigger] Populated by `DesignWorkflowViewModel` before opening the `designDocument` window scene.
/// [Sibling] `ActiveWorkflowCoordinator` — manages DesignWorkflowViewModel lifecycles across view
///           appearances; unrelated to document display.
@MainActor
final class DesignDocumentWindowCoordinator: ObservableObject {
    @Published private var payloads: [String: [DesignDocumentItem]] = [:]
    /// Pending document selection per session; observed by the window view.
    @Published var pendingSelection: [String: UUID] = [:]

    func show(_ items: [DesignDocumentItem], for sessionID: String, selecting itemID: UUID? = nil) {
        payloads[sessionID] = items
        if let itemID { pendingSelection[sessionID] = itemID }
    }

    func items(for sessionID: String) -> [DesignDocumentItem]? {
        payloads[sessionID]
    }

    /// Consume the pending selection for a session (returns once, then clears).
    func consumePendingSelection(for sessionID: String) -> UUID? {
        pendingSelection.removeValue(forKey: sessionID)
    }

    /// Remove stored data for a session when its document window closes.
    func cleanup(for sessionID: String) {
        payloads[sessionID] = nil
        pendingSelection.removeValue(forKey: sessionID)
    }
}
