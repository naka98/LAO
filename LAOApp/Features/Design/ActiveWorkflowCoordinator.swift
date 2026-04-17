import Foundation
import LAODomain
import UserNotifications

/// Keeps DesignWorkflowViewModels alive across view appearances/disappearances,
/// enabling background workflow execution while the user browses the request board.
///
/// When a workflow reaches a state requiring user intervention (decision, design review,
/// plan review, completion, failure), a notification is posted so the UI can show a badge.
///
/// Also manages a per-project execution queue so that only one workflow runs per project
/// at a time, avoiding filesystem and API contention.
@Observable @MainActor
final class ActiveWorkflowCoordinator {

    /// Active ViewModels keyed by request UUID.
    var viewModels: [UUID: DesignWorkflowViewModel] = [:]

    /// Request IDs that need user attention (blocking state reached while backgrounded).
    private(set) var requestsNeedingAttention: Set<UUID> = []

    /// Cached attention count per project for O(1) badge lookup.
    private(set) var attentionCountPerProject: [UUID: Int] = [:]

    // MARK: - Open Window Tracking

    private static let openWindowsKey = "lao.openProjectWindowIds"

    /// When true, `didSet` on `openProjectWindowIds` skips UserDefaults writes.
    /// Set during app termination to prevent window-close callbacks from
    /// overwriting the snapshot saved in `applicationShouldTerminate`.
    var isTerminating = false

    /// Project IDs that currently have an open workspace window.
    /// Workspace views register on appear and deregister on window close.
    /// Persisted to UserDefaults so windows can be restored on next launch.
    var openProjectWindowIds: Set<UUID> = [] {
        didSet {
            guard !isTerminating else { return }
            persistOpenWindows()
        }
    }

    func persistOpenWindows() {
        let array = openProjectWindowIds.map { $0.uuidString }
        UserDefaults.standard.set(array, forKey: Self.openWindowsKey)
    }

    static func loadPersistedOpenWindows() -> Set<UUID> {
        guard let array = UserDefaults.standard.stringArray(forKey: openWindowsKey) else { return [] }
        return Set(array.compactMap { UUID(uuidString: $0) })
    }

    // MARK: - Pending Deep Links

    /// Deep-link targets keyed by project ID.  When a workspace window opens for
    /// a project that has a pending deep link, the view consumes and clears it.
    /// This avoids the race between `openWindow` and notification delivery.
    var pendingDeepLinks: [UUID: UUID] = [:]

    /// Store a deep link for a project. The matching workspace view will consume it.
    func setPendingDeepLink(projectId: UUID, requestId: UUID) {
        pendingDeepLinks[projectId] = requestId
    }

    /// Consume the pending deep link for a project (returns requestId once, then clears).
    func consumePendingDeepLink(projectId: UUID) -> UUID? {
        pendingDeepLinks.removeValue(forKey: projectId)
    }

    // MARK: - Per-Project Execution Queue

    /// Ordered queue of request IDs waiting to execute, keyed by project ID.
    private(set) var executionQueue: [UUID: [UUID]] = [:]

    /// Currently executing request ID per project.
    private(set) var activePerProject: [UUID: UUID] = [:]

    // MARK: - ViewModel Lifecycle

    /// Returns an existing ViewModel for the request, or creates and registers a new one.
    func viewModel(
        for requestId: UUID,
        container: AppContainer,
        project: Project,
        ideaId: UUID? = nil
    ) -> DesignWorkflowViewModel {
        if let existing = viewModels[requestId] {
            if let ideaId { existing.backfillIdeaId(ideaId) }
            return existing
        }
        let vm = DesignWorkflowViewModel(
            container: container,
            project: project,
            requestId: requestId,
            ideaId: ideaId
        )
        vm.coordinatorRequestId = requestId
        viewModels[requestId] = vm
        return vm
    }

    /// Remove a ViewModel when the request is deleted or workflow is fully done and user has seen it.
    func remove(requestId: UUID) {
        if let projectId = viewModels[requestId]?.project.id {
            cleanUpAttention(requestId: requestId, projectId: projectId)
        }
        viewModels[requestId] = nil
        // Remove from queue if present
        for (projectId, var queue) in executionQueue {
            queue.removeAll { $0 == requestId }
            executionQueue[projectId] = queue.isEmpty ? nil : queue
        }
        // Clear active slot if this was the active request, and start next queued request
        for (projectId, activeId) in activePerProject where activeId == requestId {
            activePerProject[projectId] = nil
            dequeueNext(projectId: projectId)
        }
    }

    /// Mark a request as needing user attention (called by ViewModel when a blocking state is reached).
    /// Posts an internal notification for UI updates and a macOS system notification for active alerting.
    func markNeedsAttention(requestId: UUID, message: String? = nil) {
        guard let vm = viewModels[requestId] else { return }
        let wasNew = requestsNeedingAttention.insert(requestId).inserted
        if wasNew {
            attentionCountPerProject[vm.project.id, default: 0] += 1
        }
        NotificationCenter.default.post(name: .laoWorkflowNeedsAttention, object: requestId)
        // Trigger UI refresh so attention badge appears immediately
        NotificationCenter.default.post(name: .laoDesignStatsChanged, object: nil)

        // macOS system notification
        let content = UNMutableNotificationContent()
        content.title = "LAO Design"
        content.body = message
            ?? viewModels[requestId]?.workflow?.taskDescription.prefix(80).description
            ?? AppLanguage.currentStrings.root.workflowNeedsAttention
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lao-attention-\(requestId.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Clear the attention flag when the user opens the request.
    func clearAttention(requestId: UUID) {
        if let projectId = viewModels[requestId]?.project.id {
            cleanUpAttention(requestId: requestId, projectId: projectId)
        }
        NotificationCenter.default.post(name: .laoDesignStatsChanged, object: nil)
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["lao-attention-\(requestId.uuidString)"]
        )
    }

    /// Check if a given request currently needs user attention.
    func needsAttention(_ requestId: UUID) -> Bool {
        requestsNeedingAttention.contains(requestId)
    }

    /// Clean up completed/failed workflows to free memory.
    /// Called when a workspace window closes.
    func pruneInactive() {
        for (id, vm) in viewModels {
            let phase = vm.workflow?.phase
            if phase == .completed || phase == .failed {
                cleanUpAttention(requestId: id, projectId: vm.project.id)
                viewModels[id] = nil
            }
        }
    }

    /// Scoped variant: only prune inactive VMs belonging to the given project.
    func pruneInactive(for projectId: UUID) {
        for (id, vm) in viewModels where vm.project.id == projectId {
            let phase = vm.workflow?.phase
            if phase == .completed || phase == .failed {
                cleanUpAttention(requestId: id, projectId: projectId)
                viewModels[id] = nil
            }
        }
    }

    /// Remove a request from attention tracking if present.
    /// Shared by pruneInactive variants and remove(requestId:).
    private func cleanUpAttention(requestId: UUID, projectId: UUID) {
        if requestsNeedingAttention.remove(requestId) != nil {
            attentionCountPerProject[projectId, default: 1] -= 1
            if attentionCountPerProject[projectId] == 0 {
                attentionCountPerProject[projectId] = nil
            }
        }
    }

    // MARK: - Queue Management

    /// Enqueue a request for execution. If no other request is running for the same project,
    /// it starts immediately. Otherwise it's queued and will auto-start when the current one finishes.
    /// Returns `true` if the request can start immediately, `false` if queued.
    @discardableResult
    func enqueue(requestId: UUID, projectId: UUID) -> Bool {
        // Already active — allow re-entry
        if activePerProject[projectId] == requestId {
            return true
        }

        // Nothing running for this project — start immediately
        if activePerProject[projectId] == nil {
            activePerProject[projectId] = requestId
            return true
        }

        // Already in queue — don't double-add
        if executionQueue[projectId]?.contains(requestId) == true {
            return false
        }

        // Add to queue
        executionQueue[projectId, default: []].append(requestId)
        return false
    }

    /// Mark the current request as finished for the project and start the next queued request.
    /// Called when a workflow reaches completed or failed state.
    func dequeueNext(projectId: UUID) {
        activePerProject[projectId] = nil
        // Don't prune here — the user may still be viewing the completed/failed VM.
        // Pruning happens when the workspace window closes via pruneInactive().

        guard var queue = executionQueue[projectId], !queue.isEmpty else { return }

        let nextRequestId = queue.removeFirst()
        executionQueue[projectId] = queue.isEmpty ? nil : queue
        activePerProject[projectId] = nextRequestId

        // Auto-start the queued workflow
        if let vm = viewModels[nextRequestId] {
            vm.startAnalysis()
        }
    }

    /// Check if a request is currently queued (waiting, not yet executing).
    func isQueued(_ requestId: UUID) -> Bool {
        executionQueue.values.contains { $0.contains(requestId) }
    }

    /// Return the queue position (1-based) for a queued request, or nil if not queued.
    func queuePosition(_ requestId: UUID) -> Int? {
        for queue in executionQueue.values {
            if let idx = queue.firstIndex(of: requestId) {
                return idx + 1
            }
        }
        return nil
    }
}
