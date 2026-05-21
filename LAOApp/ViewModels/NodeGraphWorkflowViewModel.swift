import Foundation
import LAODomain
import LAOServices

// `GraphNode` and `GraphEdge` are explicitly module-qualified throughout this file
// because LAOApp/Features/Design/WorkGraphView.swift defines internal types of the
// same name for the v0.7 work graph visualization. Until v0.7 is retired we keep the
// two namespaces isolated by qualifying our v0.8 references.

/// v0.8 node graph workflow ViewModel.
///
/// Owns the workflow / nodes / edges for a single graph-mode idea. On first entry,
/// bootstraps a workflow with one seed node (the idea title) and 6 weak starter roots
/// (사용자/핵심 기능/사용 흐름/결정/위험/성공 기준). Subsequent entries just load.
@Observable @MainActor
final class NodeGraphWorkflowViewModel {
    let container: AppContainer
    let projectId: UUID
    let ideaId: UUID
    let ideaTitle: String

    var workflow: NodeGraphWorkflow?
    var nodes: [LAODomain.GraphNode] = []
    var edges: [LAODomain.GraphEdge] = []
    var isLoading = true
    var errorAlert: ErrorAlert?

    init(container: AppContainer, projectId: UUID, ideaId: UUID, ideaTitle: String) {
        self.container = container
        self.projectId = projectId
        self.ideaId = ideaId
        self.ideaTitle = ideaTitle
    }

    /// Loads existing workflow + nodes + edges. If no workflow exists for this idea, bootstraps it.
    func loadOrBootstrap() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let workflow: NodeGraphWorkflow
            if let existing = await container.nodeGraphService.getWorkflow(ideaId: ideaId) {
                workflow = existing
            } else {
                workflow = try await bootstrap()
            }
            self.workflow = workflow
            self.nodes = await container.nodeGraphService.listNodes(workflowId: workflow.id)
            self.edges = await container.nodeGraphService.listEdges(workflowId: workflow.id)
        } catch {
            let lang = AppLanguage.currentStrings
            errorAlert = ErrorAlert(
                title: lang.ideaBoard.nodeGraphBootstrapFailedFormat(error.localizedDescription),
                detail: ""
            )
        }
    }

    private func bootstrap() async throws -> NodeGraphWorkflow {
        let lang = AppLanguage.currentStrings
        let created = try await container.nodeGraphService.createWorkflow(
            NodeGraphWorkflow(ideaId: ideaId, projectId: projectId)
        )

        let seedTitle = ideaTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? lang.ideaBoard.newIdeaDefaultTitle
            : ideaTitle
        let seed = try await container.nodeGraphService.createNode(
            LAODomain.GraphNode(
                workflowId: created.id,
                kind: .seed,
                status: .exploring,
                title: seedTitle
            )
        )

        let starterLabels: [String] = [
            lang.ideaBoard.nodeGraphStarterUsers,
            lang.ideaBoard.nodeGraphStarterFeatures,
            lang.ideaBoard.nodeGraphStarterFlow,
            lang.ideaBoard.nodeGraphStarterDecisions,
            lang.ideaBoard.nodeGraphStarterRisks,
            lang.ideaBoard.nodeGraphStarterSuccess,
        ]
        for label in starterLabels {
            let starter = try await container.nodeGraphService.createNode(
                LAODomain.GraphNode(
                    workflowId: created.id,
                    kind: .starter,
                    status: .pending,
                    title: label
                )
            )
            _ = try await container.nodeGraphService.createEdge(
                LAODomain.GraphEdge(
                    workflowId: created.id,
                    fromNodeId: seed.id,
                    toNodeId: starter.id,
                    kind: .parentChild
                )
            )
        }
        return created
    }

    var seedNode: LAODomain.GraphNode? { nodes.first { $0.kind == .seed } }

    /// Starters in deterministic display order (creation time).
    var starterNodes: [LAODomain.GraphNode] {
        nodes.filter { $0.kind == .starter }.sorted { $0.createdAt < $1.createdAt }
    }
}
