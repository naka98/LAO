import LAODomain
import LAOServices
import SwiftUI

/// Project hub view for the full idea lifecycle:
/// idea list → idea discussion → Design workflow (structuring).
struct IdeaBoardView: View {
    let project: Project
    let container: AppContainer

    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang
    @State private var viewModel: IdeaBoardViewModel
    @State private var selectedIdeaId: UUID?
    @State private var activeDetailVM: IdeaDetailViewModel?
    @State private var activeDesignRequestId: UUID?

    init(project: Project, container: AppContainer) {
        self.project = project
        self.container = container
        self._viewModel = State(initialValue: IdeaBoardViewModel(
            container: container,
            projectId: project.id
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if let requestId = activeDesignRequestId {
                // Phase 3: Design workflow (structuring the idea)
                DesignWorkflowView(
                    project: project,
                    container: container,
                    requestId: requestId,
                    ideaId: activeIdea?.id,
                    onClose: {
                        activeDesignRequestId = nil
                        selectedIdeaId = nil
                        Task { await viewModel.loadIdeas() }
                    }
                )
            } else if let ideaId = selectedIdeaId {
                // Phase 2: Idea discussion with experts
                ideaDetailView(ideaId: ideaId)
            } else {
                // Phase 1: Idea list
                ideaListView
            }
        }
        .laoWindowBackground()
        .task {
            await viewModel.loadIdeas()
            // Consume any pending deep link stored by the launcher before
            // this view's .onReceive was attached (handles window-opening race).
            if let pendingRequestId = container.activeWorkflowCoordinator
                .consumePendingDeepLink(projectId: project.id) {
                activeDesignRequestId = pendingRequestId
                selectedIdeaId = nil
            }
        }
        .onChange(of: selectedIdeaId) { oldValue, newValue in
            if newValue == nil, oldValue != nil {
                // Keep activeDetailVM alive so background tasks continue
                Task { await viewModel.loadIdeas() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .laoDeepLinkRequest)) { notification in
            if let payload = notification.object as? DeepLinkPayload,
               payload.projectId == project.id {
                activeDesignRequestId = payload.requestId
                selectedIdeaId = nil
            }
        }
    }

    // MARK: - Header

    private var activeIdea: Idea? {
        if let id = selectedIdeaId {
            return viewModel.ideas.first { $0.id == id }
        }
        if let requestId = activeDesignRequestId {
            return viewModel.ideas.first { $0.designSessionId == requestId }
        }
        return nil
    }

    private var isShowingDesign: Bool {
        if activeDesignRequestId != nil { return true }
        if let idea = activeIdea, selectedIdeaId != nil {
            let designStatuses: Set<IdeaStatus> = [.converted, .designing, .designed, .designFailed]
            return designStatuses.contains(idea.status) && idea.designSessionId != nil
        }
        return false
    }

    private var headerTitle: String {
        if isShowingDesign {
            if let name = activeIdea?.title, !name.isEmpty {
                return "\(lang.design.panelTitle) — \(name)"
            }
            return lang.design.panelTitle
        } else if selectedIdeaId != nil {
            if let name = activeIdea?.title, !name.isEmpty {
                return name
            }
            return lang.ideaBoard.boardTitle
        }
        return lang.ideaBoard.boardTitle
    }

    private var headerBar: some View {
        PanelHeaderBar(
            title: headerTitle,
            subtitle: project.name,
            backAction: headerBackAction
        ) {
            if selectedIdeaId == nil && activeDesignRequestId == nil {
                Button {
                    Task {
                        let created = await viewModel.createBlankIdea(title: lang.ideaBoard.newIdeaDefaultTitle)
                        if let created { selectedIdeaId = created.id }
                    }
                } label: {
                    Label(lang.ideaBoard.newIdea, systemImage: "plus")
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }
        }
    }

    private var headerBackAction: (() -> Void)? {
        if activeDesignRequestId != nil {
            return {
                activeDesignRequestId = nil
                selectedIdeaId = nil
                Task { await viewModel.loadIdeas() }
            }
        } else if selectedIdeaId != nil {
            return { selectedIdeaId = nil }
        }
        return nil
    }

    // MARK: - Idea List

    private var ideaListView: some View {
        VStack(spacing: 0) {
            // Search + filter bar
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundMuted)
                    TextField(lang.ideaBoard.searchPlaceholder, text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(AppTheme.Typography.label)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(theme.surfaceSubtle)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))

                // Status filter chips
                HStack(spacing: 6) {
                    FilterChipButton(title: lang.ideaBoard.filterAll, isSelected: viewModel.statusFilter == nil) {
                        viewModel.statusFilter = nil
                    }
                    FilterChipButton(title: lang.ideaBoard.filterDraft, isSelected: viewModel.statusFilter == .draft) {
                        viewModel.statusFilter = .draft
                    }
                    FilterChipButton(title: lang.ideaBoard.filterAnalyzed, isSelected: viewModel.statusFilter == .analyzed) {
                        viewModel.statusFilter = .analyzed
                    }
                    FilterChipButton(title: lang.ideaBoard.filterConverted, isSelected: viewModel.statusFilter == .designing) {
                        viewModel.statusFilter = .designing
                    }
                    FilterChipButton(title: lang.ideaBoard.filterDesigned, isSelected: viewModel.statusFilter == .designed) {
                        viewModel.statusFilter = .designed
                    }
                    FilterChipButton(title: lang.ideaBoard.filterDesignFailed, isSelected: viewModel.statusFilter == .designFailed) {
                        viewModel.statusFilter = .designFailed
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.top, AppTheme.Spacing.l)
            .padding(.bottom, 10)

            Divider()

            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.filteredIdeas.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.filteredIdeas) { idea in
                                ideaCard(idea)
                                    .onTapGesture {
                                        handleIdeaTap(idea)
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            Task {
                                                await viewModel.deleteIdea(idea.id)
                                                if selectedIdeaId == idea.id {
                                                    selectedIdeaId = nil
                                                }
                                            }
                                        } label: {
                                            Label(lang.common.delete_, systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(AppTheme.Spacing.xl)
                    }
                }
            }
        }
    }

    private func ideaCard(_ idea: Idea) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(idea.title)
                        .font(AppTheme.Typography.heading)
                        .lineLimit(1)
                    Spacer()
                    switch idea.status {
                    case .converted, .designing:
                        BadgeView(title: lang.ideaBoard.converted, tone: .blue)
                    case .designed:
                        BadgeView(title: lang.ideaBoard.designComplete, tone: .green)
                    case .designFailed:
                        BadgeView(title: lang.ideaBoard.designFailed, tone: .red)
                    default:
                        EmptyView()
                    }
                }

                HStack(spacing: 8) {
                    Text(idea.createdAt, format: .dateTime.year().month().day().hour().minute())
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundTertiary)

                    let wfMetrics = viewModel.requestMetrics[idea.id]
                    let totalCalls = idea.apiCallCount + (wfMetrics?.calls ?? 0)
                    let totalTokens = idea.estimatedTokens + (wfMetrics?.tokens ?? 0)
                    MetricsRow(apiCalls: totalCalls, tokens: totalTokens)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            lang.ideaBoard.noIdeasTitle,
            systemImage: "lightbulb",
            description: Text(lang.ideaBoard.noIdeasDescription)
        )
    }

    // MARK: - Idea Detail

    @ViewBuilder
    private func ideaDetailView(ideaId: UUID) -> some View {
        let idea = viewModel.ideas.first(where: { $0.id == ideaId })

        // Design-phase idea → show Design workflow directly
        let isInDesign = idea?.status == .converted || idea?.status == .designing || idea?.status == .designed || idea?.status == .designFailed
        if let idea, isInDesign, let requestId = idea.designSessionId {
            DesignWorkflowView(
                project: project,
                container: container,
                requestId: requestId,
                ideaId: idea.id,
                onClose: {
                    activeDesignRequestId = nil
                    selectedIdeaId = nil
                    Task { await viewModel.loadIdeas() }
                }
            )
        } else {
            // Active idea → show discussion view
            let vm = resolveDetailVM(ideaId: ideaId, idea: idea)
            IdeaDetailView(viewModel: vm)
                .id(ideaId)
        }
    }

    private func resolveDetailVM(ideaId: UUID, idea: Idea?) -> IdeaDetailViewModel {
        if let existing = activeDetailVM, existing.idea.id == ideaId {
            return existing
        }
        // Preserve the ideaId so loadFullIdea() fetches the correct record from DB.
        // Fallback Idea must NOT use a random UUID — that would create a phantom record.
        let resolved = idea ?? Idea(id: ideaId, projectId: project.id, title: "")
        let newVM = IdeaDetailViewModel(
            container: container,
            project: project,
            idea: resolved
        )
        activeDetailVM = newVM
        return newVM
    }

    // MARK: - Actions

    /// Tapping a design-phase idea goes directly to its workflow.
    private func handleIdeaTap(_ idea: Idea) {
        let isInDesign = idea.status == .converted || idea.status == .designing || idea.status == .designed || idea.status == .designFailed
        if isInDesign, let requestId = idea.designSessionId {
            activeDesignRequestId = requestId
        } else {
            selectedIdeaId = idea.id
        }
    }
}
