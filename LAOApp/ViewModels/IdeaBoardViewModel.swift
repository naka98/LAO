import Foundation
import LAODomain
import LAOServices

/// Identifiable error payload surfaced via SwiftUI `.alert(...)`. Replaces the
/// previous global top-banner approach for local CRUD failures.
struct ErrorAlert: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

@Observable @MainActor
final class IdeaBoardViewModel {
    let container: AppContainer
    let projectId: UUID

    var ideas: [Idea] = []
    var isLoading = true
    var searchText = ""
    var statusFilter: IdeaStatus? = nil
    var requestMetrics: [UUID: (calls: Int, tokens: Int)] = [:]
    var errorAlert: ErrorAlert?

    init(container: AppContainer, projectId: UUID) {
        self.container = container
        self.projectId = projectId
    }

    var filteredIdeas: [Idea] {
        ideas.filter { idea in
            let matchesSearch = searchText.isEmpty
                || idea.title.localizedCaseInsensitiveContains(searchText)
            let matchesStatus: Bool
            if let filter = statusFilter {
                // .converted is a legacy synonym for .designing; .referencing shows under .analyzed filter
                let normalizedFilter = filter == .converted ? IdeaStatus.designing : filter
                let normalizedStatus: IdeaStatus
                switch idea.status {
                case .converted: normalizedStatus = .designing
                case .referencing: normalizedStatus = .analyzed
                default: normalizedStatus = idea.status
                }
                matchesStatus = normalizedStatus == normalizedFilter
            } else {
                matchesStatus = true
            }
            return matchesSearch && matchesStatus
        }
    }

    // MARK: - Load

    func loadIdeas() async {
        ideas = await container.ideaService.listIdeas(projectId: projectId)
        isLoading = false

        // Sync idea status from linked request status + load metrics
        var metrics: [UUID: (calls: Int, tokens: Int)] = [:]
        for (index, idea) in ideas.enumerated() where idea.designSessionId != nil {
            if let req = await container.designSessionService.getRequest(id: idea.designSessionId!) {
                metrics[idea.id] = (calls: req.apiCallCount, tokens: req.estimatedTokens)

                // Sync idea status from request status
                let expectedStatus: IdeaStatus = switch req.status {
                case .completed: .designed
                case .failed: .designFailed
                default: .designing
                }
                let currentStatus = idea.status
                if currentStatus != expectedStatus && (currentStatus == .converted || currentStatus == .designing || currentStatus == .designed || currentStatus == .designFailed) {
                    ideas[index].status = expectedStatus
                    try? await container.ideaService.updateIdeaStatus(id: idea.id, status: expectedStatus)
                }
            }
        }
        requestMetrics = metrics
    }

    // MARK: - CRUD

    /// Creates a blank idea and returns it for immediate navigation.
    func createBlankIdea(title: String) async -> Idea? {
        let idea = Idea(projectId: projectId, title: title)
        do {
            let created = try await container.ideaService.createIdea(idea)
            ideas.insert(created, at: 0)
            return created
        } catch {
            let lang = AppLanguage.currentStrings
            errorAlert = ErrorAlert(title: lang.ideaBoard.createFailed, detail: error.localizedDescription)
            return nil
        }
    }

    func deleteIdea(_ id: UUID) async {
        do {
            try await container.ideaService.deleteIdea(id: id)
            ideas.removeAll { $0.id == id }
        } catch {
            let lang = AppLanguage.currentStrings
            errorAlert = ErrorAlert(title: lang.ideaBoard.deleteFailed, detail: error.localizedDescription)
        }
    }
}
