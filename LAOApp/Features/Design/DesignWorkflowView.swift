import AppKit
import LAODomain
import LAOServices
import SwiftUI

struct DesignWorkflowView: View {
    let project: Project
    let container: AppContainer
    var requestId: UUID?
    var ideaId: UUID?
    var onClose: (() -> Void)?

    @Environment(\.theme) var theme
    @Environment(\.lang) var lang
    @Environment(\.openWindow) var openWindow
    @EnvironmentObject var designDocumentCoordinator: DesignDocumentWindowCoordinator
    @State var vm: DesignWorkflowViewModel
    @State var documentSessionID = UUID().uuidString
    @State var taskDescriptionExpanded = false
    @State var uncertaintyResponses: [UUID: String] = [:]
    @State var selectedSuggestionOption: [UUID: String] = [:]
    @State var showReanalyzeConfirmation = false
    @State var specIssuesExpanded = false
    @State var scrollToUncertaintyId: UUID?
    @State var showRevisionOverlay = false
    @State var revisionTargetItemId: UUID?
    @State var showUncertaintyDiscussOverlay = false
    @State var discussingUncertaintyId: UUID?
    @State var showElaborationProgressOverlay = false
    @State var showDocumentOverlay = false
    @State var documentOverlayItems: [DesignDocumentItem] = []

    init(project: Project, container: AppContainer, requestId: UUID? = nil, ideaId: UUID? = nil, onClose: (() -> Void)? = nil) {
        self.project = project
        self.container = container
        self.requestId = requestId
        self.ideaId = ideaId
        self.onClose = onClose
        if let rid = requestId {
            self._vm = State(initialValue: container.activeWorkflowCoordinator.viewModel(
                for: rid, container: container, project: project, ideaId: ideaId))
        } else {
            self._vm = State(initialValue: DesignWorkflowViewModel(container: container, project: project))
        }
    }

    private var isEmbedded: Bool { onClose != nil }

    var body: some View {
        VStack(spacing: 0) {
            if !isEmbedded { header; Divider() }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 900, minHeight: 500)
        .laoWindowBackground()
        .overlay(alignment: .top) { errorOverlay }
        .overlay { if let step = vm.finishingStep, !showElaborationProgressOverlay { finishingOverlay(step: step) } }
        .overlay {
            if vm.showConsistencyReview {
                ConsistencyReviewOverlay(
                    vm: vm,
                    onExport: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vm.showConsistencyReview = false
                        }
                        Task { await vm.proceedWithExport() }
                    }
                )
                .transition(.opacity)
            }
        }
        .overlay {
            if showDocumentOverlay {
                DesignDocumentOverlayView(
                    items: documentOverlayItems,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDocumentOverlay = false
                        }
                        documentOverlayItems = []
                    }
                )
            }
        }
        .overlay {
            if showRevisionOverlay, let targetId = revisionTargetItemId,
               let (_, _, item) = vm.workflow?.findItem(byId: targetId) {
                RevisionReviewOverlay(
                    itemId: targetId,
                    itemName: item.name,
                    vm: vm,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRevisionOverlay = false
                        }
                        revisionTargetItemId = nil
                    }
                )
                .transition(.opacity)
            }
        }
        .overlay {
            if showUncertaintyDiscussOverlay,
               let uId = discussingUncertaintyId,
               let uncertainty = vm.workflow?.uncertainties.first(where: { $0.id == uId }) {
                UncertaintyDiscussOverlay(
                    uncertaintyId: uId,
                    uncertainty: uncertainty,
                    vm: vm,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showUncertaintyDiscussOverlay = false
                        }
                        discussingUncertaintyId = nil
                    }
                )
                .transition(.opacity)
            }
        }
        .overlay {
            if vm.showStructureApproval {
                structureApprovalOverlay
                    .transition(.opacity)
            }
        }
        .overlay {
            if vm.showFinishApproval {
                finishApprovalOverlay
                    .transition(.opacity)
            }
        }
        .overlay {
            if showElaborationProgressOverlay {
                ElaborationProgressOverlay(
                    vm: vm,
                    onDismiss: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showElaborationProgressOverlay = false
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .accessibilityIdentifier("design-workflow-view")
        .task {
            await vm.loadAgents()
            if let rid = requestId {
                container.activeWorkflowCoordinator.clearAttention(requestId: rid)
                await vm.loadFromRequest()
            }
            // Auto-restore: re-show overlay for failed or interrupted items.
            // Fully-elaborated state no longer auto-triggers finishWorkflow — the user
            // explicitly invokes it via the morphed header "Export" button (which routes
            // through the finish-approval overlay).
            if let wf = vm.workflow,
               wf.phase != .completed,
               wf.isStructureApproved,
               !vm.isElaborating,
               !vm.isPreElaboration {
                let hasFailedItems = wf.deliverables.flatMap(\.items).contains {
                    $0.status == .needsRevision && !vm.activeItemWorks.keys.contains($0.id)
                }
                if hasFailedItems {
                    // Failed items exist — show overlay so user can retry or proceed
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showElaborationProgressOverlay = true
                    }
                } else if wf.allItemsConfirmed,
                          !wf.deliverables.flatMap(\.exportableItems).isEmpty {
                    let hasIncompleteItems = wf.deliverables.flatMap(\.items).contains {
                        $0.designVerdict != .excluded && ($0.status == .pending || $0.status == .needsRevision)
                    }
                    if hasIncompleteItems {
                        // Interrupted elaboration — show overlay so user can resume
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showElaborationProgressOverlay = true
                        }
                    }
                    // else: fully elaborated. The header "Export" button is now visible
                    // for the user to trigger finish explicitly.
                }
            }
        }
        .onAppear { vm.lang = lang }
        .onChange(of: lang.common.save) { _, _ in vm.lang = lang }
        .onChange(of: vm.isElaborating) { wasElaborating, isNow in
            if !wasElaborating && isNow {
                if !vm.inspectorVisible {
                    withAnimation(.easeInOut(duration: 0.2)) { vm.inspectorVisible = true }
                }
            }
            if wasElaborating && !isNow {
                // Elaboration complete — overlay auto-chains into finishWorkflow
            }
        }
        .onChange(of: vm.showConsistencyReview) { _, show in
            // Consistency issues found — dismiss elaboration overlay to show consistency review
            if show && showElaborationProgressOverlay {
                withAnimation(.easeInOut(duration: 0.2)) { showElaborationProgressOverlay = false }
            }
        }
        .onChange(of: vm.workflow?.phase) { _, phase in
            // Workflow completed — dismiss elaboration overlay
            if phase == .completed && showElaborationProgressOverlay {
                withAnimation(.easeInOut(duration: 0.2)) { showElaborationProgressOverlay = false }
            }
        }
        .onDisappear {
            // Back navigation: cancel any in-flight LLM calls so they don't keep
            // running invisibly. User resumes via the header action on re-entry.
            // gracefulStop() covers executionTask cancel + inProgress→pending +
            // activeItemWorks clear + flushSync, so it subsumes the plain flush case
            // when elaboration or preparation is active.
            if vm.finishingStep == .consistencyCheck {
                vm.cancelFinishingConsistencyCheck()
            }
            let ref = vm
            if vm.isElaborating || vm.isPreparingElaboration {
                Task { await ref.gracefulStop() }
            } else {
                Task { await ref.flushSync() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: AppTheme.Spacing.m) {
            Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(theme.accentPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.design.panelTitle).font(.headline)
                Text(project.name).font(.subheadline).foregroundStyle(theme.foregroundSecondary)
            }
            Spacer()
            if let wf = vm.workflow {
                Text(wf.phase.rawValue.capitalized).font(.caption.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(theme.accentPrimary.opacity(0.15))
                    .foregroundStyle(theme.accentPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xs))
                let p = vm.progress
                if p.total > 0 { Text("\(p.completed)/\(p.total)").font(.caption).foregroundStyle(theme.foregroundSecondary) }
            }
            if vm.isAnalyzing || vm.isGeneratingSkeleton || vm.isGeneratingGraph || vm.isElaborating || vm.isFinishing {
                Button { Task { await vm.gracefulStop() } } label: {
                    Label(lang.common.stop, systemImage: "stop.circle.fill")
                }.foregroundStyle(theme.criticalAccent).buttonStyle(.bordered).tint(theme.criticalAccent)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xl).padding(.vertical, AppTheme.Spacing.m)
    }

    @ViewBuilder private var errorOverlay: some View {
        if let error = vm.errorMessage,
           vm.workflow?.phase != .failed,
           vm.workflow?.phase != .generatingSkeleton,
           vm.workflow?.phase != .generatingGraph {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.criticalAccent)
                Text(error)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                Spacer()
                Button(lang.common.dismiss) { vm.dismissError() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(16)
            .background(theme.criticalSoftFill)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                    .stroke(theme.criticalAccent.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .padding(.horizontal, AppTheme.Spacing.l)
            .padding(.top, 60)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Content Router

    @ViewBuilder private var content: some View {
        if vm.isLoadingRequest {
            centeredProgress(lang.design.loadingWorkflow)
        } else if vm.isRestoredRequest {
            restoredRequestPhase
        } else if vm.isQueuedForExecution {
            queuedPhase
        } else {
            switch vm.workflow?.phase {
            case nil, .input:        inputPhase
            case .analyzing:         analyzingPhase
            case .approachSelection: approachSelectionPhase
            case .generatingSkeleton: skeletonStructurePhase
            case .generatingGraph:   skeletonGraphPhase
            case .planning:          planningPhase
            case .completed:         completedPhase
            case .failed:            failedPhase
            }
        }
    }

    private func centeredProgress(_ label: String) -> some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(label).font(.subheadline).foregroundStyle(theme.foregroundSecondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var queuedPhase: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(lang.design.queued).font(.headline)
            Text(lang.design.queuedDescription)
                .font(.subheadline).foregroundStyle(theme.foregroundSecondary).multilineTextAlignment(.center)
            if let rid = requestId, let pos = container.activeWorkflowCoordinator.queuePosition(rid) {
                BadgeView(title: lang.design.queuePositionFormat(pos), tone: .neutral)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var restoredRequestPhase: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let req = vm.restoredRequest {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(req.title).font(.title3.weight(.bold))
                            BadgeView(title: localizedStatusName(req.status), tone: req.status.tone)
                        }; Spacer()
                    }
                    Divider()
                    SurfaceCard(title: lang.design.workInstruction) {
                        Text(vm.taskInput).font(.body).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Button { vm.restartWorkflow() } label: {
                    Label(lang.design.restartWorkflow, systemImage: "arrow.counterclockwise")
                }.buttonStyle(PrimaryActionButtonStyle())
            }.padding(24).frame(maxWidth: 640, alignment: .leading)
        }.frame(maxWidth: .infinity)
    }

    // MARK: - Input Phase

    private var inputPhase: some View {
        VStack { Spacer()
            VStack(spacing: AppTheme.Spacing.l) {
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(theme.accentPrimary)
                Text(lang.design.describeProject).font(.title3.weight(.semibold))
                Text(lang.design.inputDescription)
                    .font(.subheadline).foregroundStyle(theme.foregroundSecondary).multilineTextAlignment(.center).frame(maxWidth: 500)
                VStack(spacing: AppTheme.Spacing.s) {
                    TextEditor(text: $vm.taskInput).font(.body).scrollContentBackground(.hidden)
                        .padding(12).frame(minHeight: 120, maxHeight: 200)
                        .background(theme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.medium).stroke(theme.borderSubtle, lineWidth: 1))
                    Button { vm.startAnalysis() } label: {
                        Label(lang.design.start, systemImage: "arrow.right.circle.fill")
                    }.buttonStyle(PrimaryActionButtonStyle())
                        .disabled(vm.taskInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.frame(maxWidth: 500)
            }; Spacer()
        }.frame(maxWidth: .infinity)
    }

    // MARK: - Analyzing Phase

    private var analyzingPhase: some View {
        VStack(spacing: AppTheme.Spacing.l) { Spacer()
            ProgressView().controlSize(.large)
            Text(lang.design.analyzingHeadline).font(.headline)
            if !vm.currentAgentLabel.isEmpty {
                Label(vm.currentAgentLabel, systemImage: "cpu").font(.caption).foregroundStyle(theme.foregroundSecondary)
            }
            if !vm.analysisStreamOutput.isEmpty {
                ScrollView {
                    Text(vm.analysisStreamOutput).font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.frame(maxWidth: 600, maxHeight: 250).background(theme.surfaceSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                    .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.small).stroke(theme.borderSubtle, lineWidth: 1))
            }
            Button { vm.stopDesignTask() } label: {
                Label(lang.common.stop, systemImage: "stop.circle.fill")
            }.buttonStyle(.bordered).foregroundStyle(theme.criticalAccent).tint(theme.criticalAccent)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private var skeletonStructurePhase: some View {
        VStack(spacing: AppTheme.Spacing.l) { Spacer()
            if vm.isGeneratingSkeleton {
                // Generating structure — show streaming text
                ProgressView().controlSize(.large)
                Text(lang.design.generatingSkeletonHeadline).font(.headline)
                if !vm.currentAgentLabel.isEmpty {
                    Label(vm.currentAgentLabel, systemImage: "cpu").font(.caption).foregroundStyle(theme.foregroundSecondary)
                }
                if !vm.skeletonStreamOutput.isEmpty {
                    ScrollView {
                        Text(vm.skeletonStreamOutput).font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }.frame(maxWidth: 600, maxHeight: 250).background(theme.surfaceSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                        .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.small).stroke(theme.borderSubtle, lineWidth: 1))
                }
            } else {
                // Generation stopped or failed — show retry
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 36)).foregroundStyle(theme.foregroundSecondary)
                Text(lang.design.generatingSkeletonHeadline).font(.headline)
                if let e = vm.errorMessage {
                    Text(e).font(.subheadline).foregroundStyle(theme.foregroundSecondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 400)
                }
                Button { vm.retrySkeletonGeneration() } label: {
                    Label(lang.common.retry, systemImage: "arrow.counterclockwise")
                }.buttonStyle(PrimaryActionButtonStyle())
            }
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private var skeletonGraphPhase: some View {
        VStack(spacing: AppTheme.Spacing.l) { Spacer()
            Text(lang.design.generatingSkeletonHeadline).font(.headline)
            skeletonPreviewList
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                subtaskStatusRow(
                    label: lang.design.analyzingRelationships,
                    status: vm.relationshipsStatus
                )
                subtaskStatusRow(
                    label: lang.design.analyzingUncertainties,
                    status: vm.uncertaintiesStatus
                )
            }
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    /// Compact preview of skeleton items generated in Phase A, shown while Phase B runs.
    private var skeletonPreviewList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.s) {
                ForEach(vm.skeletonPreviewSections, id: \.id) { section in
                    Text(section.label).font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(theme.foregroundPrimary)
                    ForEach(section.items, id: \.id) { item in
                        HStack(spacing: AppTheme.Spacing.s) {
                            Image(systemName: "doc.text").foregroundStyle(theme.foregroundTertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.caption).fontWeight(.medium)
                                if let desc = item.briefDescription, !desc.isEmpty {
                                    Text(desc).font(.caption2).foregroundStyle(theme.foregroundSecondary)
                                }
                            }
                        }.padding(.leading, AppTheme.Spacing.m)
                    }
                }
            }.padding(AppTheme.Spacing.m)
        }.frame(maxWidth: 500, maxHeight: 300).background(theme.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.small).stroke(theme.borderSubtle, lineWidth: 1))
    }

    /// Row showing a subtask's current status (loading/done/failed) with an icon.
    @ViewBuilder
    private func subtaskStatusRow(
        label: String,
        status: DesignWorkflowViewModel.SubtaskStatus
    ) -> some View {
        HStack(spacing: AppTheme.Spacing.s) {
            switch status {
            case .idle:
                Image(systemName: "circle").foregroundStyle(theme.foregroundTertiary)
            case .loading:
                ProgressView().controlSize(.small)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
            Text(statusText(label: label, status: status))
                .font(.caption)
                .foregroundStyle(status == .failed ? .red : theme.foregroundSecondary)
        }
    }

    private func statusText(
        label: String,
        status: DesignWorkflowViewModel.SubtaskStatus
    ) -> String {
        switch status {
        case .idle: return label
        case .loading: return "\(label)..."
        case .done(let count): return "\(label) (\(count))"
        case .failed: return "\(label) — Failed"
        }
    }

    // MARK: - Planning Phase (Summary Diff View)

    private var planningPhase: some View {
        VStack(spacing: 0) {
            planningHeader
                .background(theme.surfacePrimary)
                .zIndex(1)
            Divider().zIndex(1)
            HStack(spacing: 0) {
                switch vm.planningViewMode {
                case .canvas:    canvasPlanningBody
                case .list:      listPlanningBody
                }

                // Shared inspector panel (works in both canvas and list mode)
                if vm.inspectorVisible {
                    Divider()
                    canvasInspectorPanel
                        .frame(width: 300)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Canvas Planning Body

    private var canvasPlanningBody: some View {
        ZStack(alignment: .topLeading) {
            if let wf = vm.workflow, !wf.deliverables.isEmpty {
                WorkGraphView(
                    workflow: wf,
                    selectedItemId: vm.selectedItemId,
                    isMinimapMode: false,
                    onSelectItem: { id in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vm.selectedItemId = (vm.selectedItemId == id) ? nil : id
                            if vm.selectedItemId != nil { vm.inspectorVisible = true }
                        }
                    },
                    onAddEdge: { sourceId, targetId, relationType in
                        vm.addUserEdge(sourceId: sourceId, targetId: targetId, relationType: relationType)
                    }
                )
            } else {
                ContentUnavailableView(lang.design.noDeliverables, systemImage: "doc.text",
                                       description: Text(lang.design.noDeliverablesHint))
            }
        }
        .clipShape(Rectangle())
        .contentShape(Rectangle())
        .layoutPriority(1)
    }

    // MARK: - List Planning Body

    private var listPlanningBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let wf = vm.workflow, !wf.taskDescription.isEmpty {
                    taskDescriptionBanner(wf.taskDescription)
                }
                if let wf = vm.workflow, !wf.deliverables.isEmpty {
                    summaryItemList(wf)
                } else {
                    ContentUnavailableView(lang.design.noDeliverables, systemImage: "doc.text",
                                           description: Text(lang.design.noDeliverablesHint))
                }
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }
        .layoutPriority(1)
    }

    // MARK: - Helpers

    func openDocumentOverlay(selecting targetID: UUID? = nil) {
        Task {
            let items = await vm.gatherDocumentItems()
            guard !items.isEmpty else { return }
            documentOverlayItems = items
            withAnimation(.easeInOut(duration: 0.2)) {
                showDocumentOverlay = true
            }
        }
    }

    func localizedStatusName(_ status: DesignSessionStatus) -> String {
        switch status {
        case .planning: return lang.designSession.statusPlanning
        case .reviewing: return lang.designSession.statusReviewing
        case .executing: return lang.designSession.statusExecuting
        case .completed: return lang.designSession.statusCompleted
        case .failed: return lang.designSession.statusFailed
        }
    }

    func formattedTokens(_ t: Int) -> String {
        t >= 1000 ? String(format: "%.1fk", Double(t) / 1000.0) : "\(t)"
    }
}
