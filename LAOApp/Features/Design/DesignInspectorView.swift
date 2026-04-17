// MARK: - Canvas Inspector Panel & Related Views (extracted from DesignWorkflowView)

import SwiftUI
import LAODomain

extension DesignWorkflowView {

    // MARK: - Canvas Inspector Panel

    var canvasInspectorPanel: some View {
        VStack(spacing: 0) {
            inspectorStatusBanner

            // Inspector header
            HStack(spacing: 8) {
                if let itemId = vm.selectedItemId,
                   let (_, _, item) = vm.workflow?.findItem(byId: itemId) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { vm.selectedItemId = nil }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.accentPrimary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).font(.headline).lineLimit(1)
                        Text(lang.design.inspectorItemReview)
                            .font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundTertiary)
                    }
                } else {
                    Text(lang.design.inspectorPendingDecisions).font(.headline)
                }
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.2)) { vm.inspectorVisible = false } } label: {
                    Image(systemName: "sidebar.right")
                        .foregroundStyle(theme.foregroundSecondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()

            // Inspector content
            ScrollViewReader { inspectorProxy in
                ScrollView {
                    if let itemId = vm.selectedItemId,
                       let (si, _, item) = vm.workflow?.findItem(byId: itemId) {
                        let section = vm.workflow!.deliverables[si]
                        inspectorItemDetail(item, sectionType: section.type, sectionLabel: section.label)
                    } else {
                        inspectorOverview
                    }
                }
                .onChange(of: scrollToUncertaintyId) { _, newId in
                    if let id = newId {
                        withAnimation { inspectorProxy.scrollTo(id, anchor: .center) }
                        scrollToUncertaintyId = nil
                    }
                }
            }

        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Inspector Status Banner

    @ViewBuilder
    var inspectorStatusBanner: some View {
        if let wf = vm.workflow, wf.phase == .planning {
            let blocking = wf.blockingUncertainties
            let pendingReview = wf.pendingReviewCount
            let allConfirmed = wf.allItemsConfirmed

            if !blocking.isEmpty {
                // P1: Blocking questions
                inspectorBannerRow(
                    icon: "exclamationmark.octagon.fill",
                    text: lang.design.bannerBlockingQuestions(blocking.count),
                    color: theme.criticalAccent
                ) {
                    vm.selectedItemId = nil
                    scrollToUncertaintyId = blocking.first?.id
                }
                Divider()
            } else if pendingReview > 0 && !vm.isElaborating {
                // P2: Pending review
                inspectorBannerRow(
                    icon: "eye.circle.fill",
                    text: lang.design.bannerPendingReview(pendingReview),
                    color: theme.warningAccent
                ) {
                    // Navigate to first pending item
                    if let firstPending = wf.deliverables.lazy
                        .flatMap(\.items)
                        .first(where: { $0.directorVerdict == .pending && $0.plannerVerdict != .rejected }) {
                        vm.selectedItemId = firstPending.id
                    }
                }
                Divider()
            } else if allConfirmed && vm.isPreElaboration {
                // P3: All confirmed, ready to start
                inspectorBannerRow(
                    icon: "checkmark.circle.fill",
                    text: lang.design.bannerAllConfirmedReady,
                    color: theme.positiveAccent,
                    action: nil
                )
                Divider()
            } else if vm.isElaborating && !vm.isRevisionElaborating {
                // P4: Elaboration in progress (excludes single-item revision re-elaboration)
                let completed = wf.deliverables.flatMap(\.items).filter { $0.status == .completed }.count
                let total = wf.deliverables.flatMap(\.items).filter { $0.directorVerdict == .confirmed }.count
                inspectorBannerRow(
                    icon: nil,
                    text: lang.design.bannerElaborating(completed, total),
                    color: theme.accentPrimary,
                    showSpinner: true,
                    action: nil
                )
                Divider()
            } else if vm.isSpecifyPhase && allConfirmed && vm.hasSubstantiveExport && !vm.showConsistencyReview && !vm.hasIncompleteElaborationItems {
                // P5: Export ready — hidden when consistency review overlay is open or incomplete items remain.
                // Tappable so the user can recover if the auto-chain (elaboration →
                // finishWorkflow) was interrupted (cancellation, view re-creation, etc.).
                inspectorBannerRow(
                    icon: "doc.badge.arrow.up.fill",
                    text: lang.design.bannerExportReady,
                    color: theme.positiveAccent,
                    action: vm.isFinishing ? nil : {
                        Task { await vm.finishWorkflow() }
                    }
                )
                Divider()
            }
        }
    }

    /// Reusable single-row banner renderer for inspector status.
    private func inspectorBannerRow(
        icon: String?,
        text: String,
        color: Color,
        showSpinner: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        let content = HStack(spacing: 8) {
            if showSpinner {
                ProgressView()
                    .controlSize(.small)
                    .tint(color)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(text)
                .font(AppTheme.Typography.caption)
                .fontWeight(.medium)
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer()
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(color.opacity(0.08))

        if let action {
            return AnyView(
                Button(action: action) { content }
                    .buttonStyle(.plain)
            )
        } else {
            return AnyView(content)
        }
    }

    // MARK: - Inspector Item Detail

    func inspectorItemDetail(_ item: DeliverableItem, sectionType: String, sectionLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section type label
            HStack(spacing: 6) {
                Image(systemName: sectionIcon(sectionType))
                    .font(AppTheme.Typography.caption).foregroundStyle(sectionColor(sectionType))
                Text(sectionLabel)
                    .font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundSecondary)
                Spacer()
            }

            // Brief description
            if let desc = item.briefDescription, !desc.isEmpty {
                Text(desc).font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary)
            }

            // Context summary card — decision-maker-facing overview (purpose, navigation, counts)
            if !item.spec.isEmpty {
                inspectorContextCard(item.spec, sectionType: sectionType)
            }

            // Action buttons (hidden during elaboration)
            if item.status == .inProgress, let work = vm.activeItemWorks[item.id] {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(lang.design.statusInProgress)
                            .font(AppTheme.Typography.bodySecondary.weight(.medium))
                            .foregroundStyle(theme.accentPrimary)
                        Spacer()
                        Text(work.agentLabel)
                            .font(AppTheme.Typography.detail)
                            .foregroundStyle(theme.foregroundTertiary)
                    }
                }
                .padding(10)
                .background(theme.accentPrimary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                inspectorActions(item)
            }

            // Revision note display + re-review button
            if item.designVerdict == .needsRevision, let note = item.revisionNote, !note.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(theme.warningAccent)
                            .font(AppTheme.Typography.bodySecondary)
                        Text(note)
                            .font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary)
                    }
                    Button {
                        vm.beginRevisionReview(for: item.id)
                        revisionTargetItemId = item.id
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRevisionOverlay = true
                        }
                    } label: {
                        Label(lang.design.revisionReviewTitle, systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(theme.warningAccent).controlSize(.small)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.warningAccent.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Elaboration failure detail + retry
            if item.status == .needsRevision, let errorMsg = item.lastElaborationError {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.criticalAccent)
                        Text(lang.design.elaborationFailed)
                            .font(AppTheme.Typography.caption.weight(.semibold))
                    }
                    Text(errorMsg)
                        .font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundPrimary)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.criticalAccent.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button {
                        vm.retryElaboration(item.id)
                    } label: {
                        Label(lang.design.retryElaboration, systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(theme.accentPrimary).controlSize(.small)
                }
                Divider()
            }

            // Uncertainty escalations for this item
            inspectorUncertainties(item.id)

            Divider()

            // Connected items (edges)
            if let wf = vm.workflow {
                inspectorConnections(item.id, workflow: wf)
            }

            Divider()

            // Technical details — collapsed by default for decision-maker
            if !item.spec.isEmpty {
                DisclosureGroup {
                    // Readiness indicator moved here from decision-maker row
                    HStack(spacing: 6) {
                        readinessIndicator(item)
                        Text(readinessLabelText(item.specReadiness))
                            .font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundTertiary)
                    }
                    // Agent & performance metadata
                    HStack(spacing: 8) {
                        if let agent = item.lastAgentLabel {
                            Label(agent, systemImage: "person.crop.circle")
                                .font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundTertiary)
                        }
                        if item.elaborationDurationMs > 0 {
                            let seconds = Double(item.elaborationDurationMs) / 1000.0
                            Label(String(format: "%.1fs", seconds), systemImage: "clock")
                                .font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundTertiary)
                        }
                        if let group = item.parallelGroup {
                            Label("G\(group)", systemImage: "square.grid.2x2")
                                .font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundTertiary)
                        }
                    }
                    structuredSpecView(spec: item.spec, sectionType: sectionType)
                    if let wf = vm.workflow {
                        inspectorTechnicalStructure(item.id, workflow: wf)
                    }
                } label: {
                    Label(lang.design.technicalDetail, systemImage: "gearshape")
                        .font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundTertiary)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundMuted)
                    Text(lang.design.noSpecYet).font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundTertiary)
                }.padding(.vertical, 6)
            }
        }
        .padding(16)
    }

    // MARK: - Inspector Context Summary Card

    /// Compact summary card that lets decision-makers grasp item intent at a glance,
    /// without scrolling through detailed spec sections.
    @ViewBuilder
    func inspectorContextCard(_ spec: [String: AnyCodable], sectionType: String) -> some View {
        if contextCardHasContent(spec, sectionType: sectionType) {
            VStack(alignment: .leading, spacing: 8) {
                // Section-type-specific summary
                switch sectionType {
                case "screen-spec":
                    screenContextCard(spec)
                case "api-spec":
                    apiContextCard(spec)
                case "data-model":
                    dataModelContextCard(spec)
                case "user-flow":
                    userFlowContextCard(spec)
                default:
                    EmptyView()
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.accentPrimary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
        }
    }

    /// Check whether the context card would render any visible content for the given spec.
    private func contextCardHasContent(_ spec: [String: AnyCodable], sectionType: String) -> Bool {
        switch sectionType {
        case "screen-spec":
            return spec["purpose"]?.stringValue != nil
                || spec["entry_condition"]?.stringValue?.isEmpty == false
                || spec["exit_to"]?.arrayValue?.isEmpty == false
                || !SpecSummarizer.componentNames(spec).isEmpty
        case "api-spec":
            return spec["description"]?.stringValue?.isEmpty == false
                || spec["method"]?.stringValue != nil
        case "data-model":
            return spec["purpose"]?.stringValue != nil
                || spec["fields"]?.arrayValue?.isEmpty == false
        case "user-flow":
            return spec["trigger"]?.stringValue != nil
                || !SpecSummarizer.flowNarrative(spec).isEmpty
                || spec["success_outcome"]?.stringValue?.isEmpty == false
        default:
            return false
        }
    }

    func screenContextCard(_ spec: [String: AnyCodable]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Purpose (prominent, full text)
            if let purpose = spec["purpose"]?.stringValue {
                Text(purpose).font(.callout).foregroundStyle(.primary)
            }
            // Navigation context: entry
            if let entry = spec["entry_condition"]?.stringValue, !entry.isEmpty {
                Label(entry, systemImage: "arrow.right.to.line")
                    .font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundSecondary)
            }
            // Navigation context: exit targets (vertical list)
            if let exitTo = spec["exit_to"]?.arrayValue, !exitTo.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Label(lang.design.contextNavigatesTo, systemImage: "arrow.right.square")
                        .font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundSecondary)
                    ForEach(Array(exitTo.prefix(5).enumerated()), id: \.offset) { _, dest in
                        Text("· \(readableText(dest))")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(theme.foregroundSecondary)
                    }
                    if exitTo.count > 5 {
                        Text(lang.design.nMoreFormat(exitTo.count - 5))
                            .font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundTertiary)
                    }
                }
            }
            // Decision-maker-facing natural language summaries
            let compNames = SpecSummarizer.componentNames(spec)
            let interactionDesc = SpecSummarizer.interactionDescriptions(spec)
            let stateDesc = SpecSummarizer.stateNames(spec)
            if !compNames.isEmpty {
                summaryRow(icon: "square.stack", label: lang.design.componentListLabel, text: compNames)
            }
            if !interactionDesc.isEmpty {
                summaryRow(icon: "hand.tap", label: lang.design.interactionListLabel, text: interactionDesc)
            }
            if !stateDesc.isEmpty {
                summaryRow(icon: "switch.2", label: lang.design.stateListLabel, text: stateDesc)
            }
        }
    }

    func apiContextCard(_ spec: [String: AnyCodable]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Business description first (decision-maker-facing)
            if let desc = spec["description"]?.stringValue, !desc.isEmpty {
                Text(desc).font(.callout).foregroundStyle(.primary)
            }
            // Method + Path as secondary reference
            HStack(spacing: 6) {
                if let method = spec["method"]?.stringValue {
                    Text(method.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(apiMethodColor(method))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                Text(spec["path"]?.stringValue ?? spec["endpoint"]?.stringValue ?? "")
                    .font(AppTheme.Typography.detail.monospaced()).foregroundStyle(theme.foregroundTertiary)
            }
            // Auth badge
            if let auth = spec["auth"]?.stringValue, !auth.isEmpty {
                Label(auth, systemImage: "lock.fill")
                    .font(AppTheme.Typography.caption).foregroundStyle(theme.warningAccent)
            }
        }
    }

    func dataModelContextCard(_ spec: [String: AnyCodable]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let desc = spec["description"]?.stringValue, !desc.isEmpty {
                Text(desc).font(.callout).foregroundStyle(.primary)
            }
            let fieldSummary = SpecSummarizer.dataModelSummary(spec)
            if !fieldSummary.isEmpty, spec["description"]?.stringValue != nil {
                // Show field names when description is already shown separately
                let fieldNames = SpecSummarizer.componentNames(spec) // reuse: extracts "name" from fields
                let names = spec["fields"]?.arrayValue?.compactMap { ($0 as? [String: Any])?["name"] as? String }.filter { !$0.isEmpty } ?? []
                if !names.isEmpty {
                    summaryRow(icon: "list.bullet", label: lang.design.fieldListLabel, text: names.prefix(5).joined(separator: ", ") + (names.count > 5 ? " " + lang.design.moreItemsFormat(names.count - 5) : ""))
                }
            } else if !fieldSummary.isEmpty {
                // No description — show combined summary
                summaryRow(icon: "list.bullet", label: lang.design.fieldListLabel, text: fieldSummary)
            }
            let relTargets = SpecSummarizer.relationshipTargets(spec)
            if !relTargets.isEmpty {
                summaryRow(icon: "link", label: lang.design.connections, text: relTargets)
            }
        }
    }

    func userFlowContextCard(_ spec: [String: AnyCodable]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let trigger = spec["trigger"]?.stringValue {
                Label(trigger, systemImage: "play.circle")
                    .font(AppTheme.Typography.bodySecondary).foregroundStyle(.primary).lineLimit(2)
            }
            let narrative = SpecSummarizer.flowNarrative(spec)
            if !narrative.isEmpty {
                summaryRow(icon: "list.number", label: lang.design.narrativeStepsLabel, text: narrative)
            }
            if let outcome = spec["success_outcome"]?.stringValue, !outcome.isEmpty {
                Label("→ \(outcome)", systemImage: "checkmark.circle")
                    .font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundSecondary).lineLimit(2)
            }
        }
    }

    /// Small badge with icon + text, used in context summary cards.
    func contextBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(AppTheme.Typography.detail).lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(color.opacity(0.8))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// Labeled description row for decision-maker-facing context cards.
    func summaryRow(icon: String, label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: icon)
                .font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundTertiary)
            Text(text).font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary).lineLimit(3)
        }
    }

    // MARK: - Inspector Actions

    func inspectorActions(_ item: DeliverableItem) -> some View {
        VStack(spacing: 8) {
            // Confirm — "이 항목이 필요합니다" (toggle)
            Button {
                vm.setDesignVerdict(item.id, item.designVerdict == .confirmed ? .pending : .confirmed)
            } label: {
                Label(item.designVerdict == .confirmed ? lang.design.verdictConfirmed : lang.design.verdictConfirm,
                      systemImage: item.designVerdict == .confirmed ? "checkmark.circle.fill" : "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(item.designVerdict == .confirmed ? theme.positiveAccent : nil)
            .controlSize(.small)

            // Hide revision/exclude when confirmed — un-confirm first to access them
            if item.designVerdict != .confirmed {
                HStack(spacing: 8) {
                    // Request revision — opens review overlay
                    Button {
                        vm.beginRevisionReview(for: item.id)
                        revisionTargetItemId = item.id
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showRevisionOverlay = true
                        }
                    } label: {
                        Label(item.designVerdict == .needsRevision
                                  ? lang.design.verdictNeedsRevision
                                  : lang.design.verdictRequestRevision,
                              systemImage: item.designVerdict == .needsRevision
                                  ? "pencil.circle.fill" : "pencil.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(item.designVerdict == .needsRevision ? theme.warningAccent : theme.accentPrimary)
                    .controlSize(.small)

                    // Exclude (verdict toggle)
                    Button {
                        vm.setDesignVerdict(item.id, item.designVerdict == .excluded ? .pending : .excluded)
                    } label: {
                        Label(item.designVerdict == .excluded ? lang.design.verdictExcluded : lang.design.verdictExclude,
                              systemImage: item.designVerdict == .excluded ? "xmark.circle.fill" : "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(.secondary).controlSize(.small)
                }
            }
        }
    }

    // MARK: - Inspector Uncertainties

    @ViewBuilder
    func inspectorUncertainties(_ itemId: UUID) -> some View {
        let itemUncertainties = vm.workflow?.uncertainties(for: itemId) ?? []
        if !itemUncertainties.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "questionmark.diamond.fill")
                        .foregroundStyle(theme.warningAccent)
                    Text(lang.design.uncertaintyTitle)
                        .font(AppTheme.Typography.caption.weight(.semibold))
                    Spacer()
                    let pendingCount = itemUncertainties.filter { $0.status == .pending }.count
                    if pendingCount > 0 {
                        Text(lang.design.uncertaintyCountFormat(pendingCount))
                            .font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundTertiary)
                    }
                }

                ForEach(itemUncertainties) { uncertainty in
                    uncertaintyCard(uncertainty)
                        .id(uncertainty.id)
                }
            }
        }
    }

    @ViewBuilder
    func uncertaintyCard(_ uncertainty: DesignDecision) -> some View {
        let isPending = uncertainty.status == .pending
        let isAuto = uncertainty.isAutonomous

        VStack(alignment: .leading, spacing: 6) {
            // Header: type badge + priority badge
            HStack(spacing: 4) {
                uncertaintyTypeBadge(uncertainty.escalationType ?? .question)
                uncertaintyPriorityBadge(uncertainty.priority)
                Spacer()
                if isAuto {
                    Text(lang.design.uncertaintyAutoResolved)
                        .font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundSecondary)
                }
            }

            // Title and body
            Text(uncertainty.title).font(AppTheme.Typography.bodySecondary.weight(.medium))
                .foregroundStyle(isPending ? theme.foregroundPrimary : theme.foregroundSecondary)
            Text(uncertainty.body).font(AppTheme.Typography.bodySecondary)
                .foregroundStyle(isPending ? theme.foregroundPrimary : theme.foregroundTertiary)
                .lineLimit(isPending ? nil : 2)

            // Resolution controls
            if isPending {
                uncertaintyResolutionControls(uncertainty)
            } else if isAuto, let reasoning = uncertainty.autonomousReasoning {
                // Collapsed autonomous reasoning with reopen
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reasoning).font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary)
                        Button(lang.design.uncertaintyReopen) {
                            vm.reopenUncertainty(uncertainty.id)
                        }
                        .font(AppTheme.Typography.caption).buttonStyle(.bordered).controlSize(.small)
                    }
                } label: {
                    let summary = uncertainty.selectedOption
                        ?? uncertainty.userResponse
                        ?? String(reasoning.prefix(60))
                    Text(summary).font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary)
                }
                .font(AppTheme.Typography.bodySecondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .fill(isPending ? theme.warningSoftFill : theme.surfaceSubtle)
        )
        .opacity(isPending ? 1.0 : 0.7)
    }

    @ViewBuilder
    func uncertaintyResolutionControls(_ uncertainty: DesignDecision) -> some View {
        let uType = uncertainty.escalationType ?? .question
        let hasOptions = !uncertainty.options.isEmpty
        VStack(alignment: .leading, spacing: 4) {
            // Options — show radio buttons whenever options exist, regardless of type
            if hasOptions {
                let selected = selectedSuggestionOption[uncertainty.id]
                ForEach(uncertainty.options, id: \.self) { option in
                    Button {
                        selectedSuggestionOption[uncertainty.id] = (selected == option) ? nil : option
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: selected == option ? "circle.inset.filled" : "circle")
                                .font(.system(size: 10))
                                .foregroundStyle(selected == option ? theme.accentPrimary : theme.foregroundTertiary)
                                .frame(width: 14, height: 14)
                            Text(option)
                                .font(AppTheme.Typography.bodySecondary)
                                .foregroundStyle(theme.foregroundPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            // Text input — for non-suggestion types, or when no options available
            if uType != .suggestion || !hasOptions {
                HStack(spacing: 4) {
                    TextField(lang.design.uncertaintyResponsePlaceholder, text: uncertaintyResponseBinding(uncertainty.id))
                        .textFieldStyle(.roundedBorder)
                        .font(AppTheme.Typography.caption)
                        .controlSize(.small)
                }
            }
            // Action buttons — unified: dismiss + discuss + resolve
            HStack(spacing: 6) {
                Spacer()
                if uncertainty.priority != .blocking {
                    Button(lang.design.uncertaintyDismiss) {
                        vm.dismissUncertainty(uncertainty.id)
                    }
                    .font(AppTheme.Typography.caption).buttonStyle(.bordered).controlSize(.small)
                    .tint(.secondary)
                }
                Button(lang.design.uncertaintyDiscuss) {
                    vm.beginUncertaintyDiscussion(uncertainty.id)
                    discussingUncertaintyId = uncertainty.id
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showUncertaintyDiscussOverlay = true
                    }
                }
                .font(AppTheme.Typography.caption).buttonStyle(.bordered).controlSize(.small)
                .tint(theme.accentPrimary)
                if hasOptions {
                    // Resolve with selected option
                    Button(lang.design.uncertaintyResolve) {
                        if let option = selectedSuggestionOption[uncertainty.id] {
                            vm.resolveUncertainty(uncertainty.id, selectedOption: option)
                            selectedSuggestionOption.removeValue(forKey: uncertainty.id)
                        }
                    }
                    .font(AppTheme.Typography.caption).buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(selectedSuggestionOption[uncertainty.id] == nil)
                } else {
                    // Resolve with text response
                    Button(lang.design.uncertaintyResolve) {
                        let response = uncertaintyResponses[uncertainty.id] ?? ""
                        guard !response.isEmpty else { return }
                        vm.resolveUncertaintyWithText(uncertainty.id, response: response)
                        uncertaintyResponses.removeValue(forKey: uncertainty.id)
                    }
                    .font(AppTheme.Typography.caption).buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled((uncertaintyResponses[uncertainty.id] ?? "").isEmpty)
                }
            }
            .padding(.top, 2)
        }
    }

    func uncertaintyResponseBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { uncertaintyResponses[id] ?? "" },
            set: { uncertaintyResponses[id] = $0 }
        )
    }

    @ViewBuilder
    func uncertaintyTypeBadge(_ type: UncertaintyType) -> some View {
        let (label, icon): (String, String) = {
            switch type {
            case .question:       return (lang.design.uncertaintyQuestion, "questionmark.circle")
            case .suggestion:     return (lang.design.uncertaintySuggestion, "lightbulb")
            case .discussion:     return (lang.design.uncertaintyDiscussion, "bubble.left.and.bubble.right")
            case .informationGap: return (lang.design.uncertaintyInfoGap, "info.circle")
            }
        }()
        Label(label, systemImage: icon)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(theme.infoSoftFill))
    }

    @ViewBuilder
    func uncertaintyPriorityBadge(_ priority: UncertaintyPriority) -> some View {
        let (label, color): (String, Color) = {
            switch priority {
            case .blocking:  return (lang.design.uncertaintyBlocking, theme.criticalAccent)
            case .important: return (lang.design.uncertaintyImportant, theme.warningAccent)
            case .advisory:  return (lang.design.uncertaintyAdvisory, .secondary)
            }
        }()
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().stroke(color, lineWidth: 0.5))
    }

    // MARK: - Inspector Connections

    func inspectorConnections(_ itemId: UUID, workflow wf: DesignWorkflow) -> some View {
        let edges = wf.edges(for: itemId)
        return Group {
            if !edges.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lang.design.connections).font(AppTheme.Typography.caption.weight(.semibold)).foregroundStyle(theme.foregroundSecondary)
                    ForEach(edges) { edge in
                        let otherId = edge.sourceId == itemId ? edge.targetId : edge.sourceId
                        let direction = edge.sourceId == itemId ? "arrow.right" : "arrow.left"
                        if let (si, _, other) = wf.findItem(byId: otherId) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { vm.selectedItemId = otherId }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: direction).font(.system(size: 10)).foregroundStyle(theme.foregroundMuted)
                                    Text(relationLabel(edge.relationType)).font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundSecondary)
                                    Image(systemName: sectionIcon(wf.deliverables[si].type))
                                        .font(.system(size: 10)).foregroundStyle(sectionColor(wf.deliverables[si].type))
                                    Text(other.name).font(AppTheme.Typography.caption).lineLimit(1)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Inspector Technical Structure

    /// Shows data-model, api-spec, and user-flow items connected to the selected primary node.
    @ViewBuilder
    func inspectorTechnicalStructure(_ itemId: UUID, workflow wf: DesignWorkflow) -> some View {
        let technicalTypes: Set<String> = ["data-model", "api-spec", "user-flow"]
        let edges = wf.edges(for: itemId)
        let techItems: [(edge: ItemEdge, item: DeliverableItem, sectionType: String)] = edges.compactMap { edge in
            let otherId = edge.sourceId == itemId ? edge.targetId : edge.sourceId
            guard let (si, _, other) = wf.findItem(byId: otherId) else { return nil }
            let secType = wf.deliverables[si].type
            guard technicalTypes.contains(secType) else { return nil }
            return (edge, other, secType)
        }

        if !techItems.isEmpty {
            Divider()
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "gearshape.2").font(AppTheme.Typography.caption)
                Text(lang.design.technicalStructure)
                    .font(AppTheme.Typography.caption.weight(.semibold))
                Text("(\(techItems.count))")
                    .font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundTertiary)
            }
            .foregroundStyle(theme.foregroundSecondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(techItems, id: \.item.id) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: sectionIcon(entry.sectionType))
                                .font(.system(size: 11)).foregroundStyle(sectionColor(entry.sectionType))
                            Text(entry.item.name)
                                .font(AppTheme.Typography.caption.weight(.medium)).lineLimit(2)
                            Spacer()
                            statusBadge(entry.item.status)
                        }
                        if let desc = entry.item.briefDescription, !desc.isEmpty {
                            Text(desc).font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundSecondary).lineLimit(2)
                        }
                        // Compact spec preview
                        if !entry.item.spec.isEmpty {
                            technicalSpecPreview(entry.item.spec, sectionType: entry.sectionType)
                        }
                    }
                    .padding(8)
                    .background(theme.surfaceSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { vm.selectedItemId = entry.item.id } }
                }
            }
        }
    }

    /// Compact preview of a technical spec in the inspector.
    @ViewBuilder
    func technicalSpecPreview(_ spec: [String: AnyCodable], sectionType: String) -> some View {
        switch sectionType {
        case "data-model":
            if let fields = spec["fields"]?.arrayValue {
                let names = fields.prefix(4).compactMap { field -> String? in
                    let dict = (field as? AnyCodable)?.dictValue ?? (field as? [String: Any])
                    return dict?["name"] as? String
                }
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet").font(AppTheme.Typography.iconSmall).foregroundStyle(theme.foregroundTertiary)
                    Text(names.joined(separator: ", ") + (fields.count > 4 ? " +\(fields.count - 4)" : ""))
                        .font(.system(size: 11)).foregroundStyle(theme.foregroundTertiary).lineLimit(1)
                }
            }
        case "api-spec":
            if let method = spec["method"]?.stringValue, let path = spec["path"]?.stringValue {
                HStack(spacing: 4) {
                    Text(method).font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.blue.opacity(0.7))
                    Text(path).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.foregroundTertiary).lineLimit(1)
                }
            }
        case "user-flow":
            if let steps = spec["steps"]?.arrayValue {
                let names = steps.prefix(4).compactMap { step -> String? in
                    let dict = (step as? AnyCodable)?.dictValue ?? (step as? [String: Any])
                    return dict?["name"] as? String ?? dict?["label"] as? String
                }
                if !names.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch").font(AppTheme.Typography.iconSmall).foregroundStyle(theme.foregroundTertiary)
                        Text(names.joined(separator: " → ") + (steps.count > 4 ? " +\(steps.count - 4)" : ""))
                            .font(.system(size: 11)).foregroundStyle(theme.foregroundTertiary).lineLimit(1)
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Inspector Overview (no item selected)

    var inspectorOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Active elaboration summary
            if vm.isElaborating && !vm.isRevisionElaborating {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(lang.design.elaborationProgressFormat(
                            vm.workflow?.completedItemCount ?? 0, vm.workflow?.totalItemCount ?? 0))
                            .font(AppTheme.Typography.caption.weight(.semibold))
                            .foregroundStyle(theme.accentPrimary)
                    }
                    ForEach(Array(vm.activeItemWorks.values), id: \.itemId) { work in
                        HStack(spacing: 6) {
                            Circle().fill(theme.accentPrimary).frame(width: 6, height: 6)
                            Text(work.itemName).font(AppTheme.Typography.caption).lineLimit(1)
                            Spacer()
                            Text(work.agentLabel).font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundTertiary)
                        }
                    }
                }
                .padding(10)
                .background(theme.infoSoftFill)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            }

            // Post-elaboration review guide
            if !vm.isElaborating, let wf = vm.workflow,
               wf.pendingReviewCount > 0, wf.completedItemCount > 0 {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3).foregroundStyle(theme.accentPrimary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lang.design.reviewGuide(wf.pendingReviewCount))
                            .font(AppTheme.Typography.caption)
                        Button(lang.design.reviewFirstPending) {
                            if let first = wf.deliverables.flatMap(\.items)
                                .first(where: { $0.designVerdict == .pending && $0.status == .completed }) {
                                withAnimation(.easeInOut(duration: 0.2)) { vm.selectedItemId = first.id }
                            }
                        }
                        .font(AppTheme.Typography.caption.weight(.medium))
                        .buttonStyle(.bordered).tint(theme.accentPrimary).controlSize(.small)
                    }
                }
                .padding(10)
                .background(theme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            }

            if let wf = vm.workflow {
                // Progress summary
                VStack(alignment: .leading, spacing: 8) {
                    Text(lang.design.progressItemsFormat(wf.confirmedItemCount, wf.activeItemCount))
                        .font(.callout.weight(.medium))

                    // Section breakdown
                    ForEach(wf.deliverables.filter { !$0.items.isEmpty }, id: \.id) { section in
                        HStack(spacing: 6) {
                            Image(systemName: sectionIcon(section.type))
                                .font(.system(size: 10)).foregroundStyle(sectionColor(section.type))
                            Text(section.label).font(AppTheme.Typography.caption)
                            Spacer()
                            Text("\(section.confirmedCount)/\(section.activeItems.count)")
                                .font(AppTheme.Typography.detail.monospaced()).foregroundStyle(theme.foregroundSecondary)
                        }
                    }
                }

                // Oscillation warning — only shown when items have flip-flopping verdicts
                if wf.hasOscillationWarning {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                        Text(lang.design.oscillationWarningFormat(wf.oscillatingItemCount))
                            .font(AppTheme.Typography.detail)
                    }
                    .foregroundStyle(.orange)
                }

                if wf.allItemsConfirmed && !vm.isElaborating && !vm.isPreparingElaboration {
                    let hasExportable = !wf.deliverables.flatMap(\.exportableItems).isEmpty
                    if vm.isPreElaboration {
                        // Pre-elaboration: banner already shows "All confirmed — ready to start"
                        EmptyView()
                    } else if hasExportable {
                        // Exportable items exist but workflow not yet completed (e.g. app restart).
                        // Auto-trigger is handled once in DesignWorkflowView.task, not here.
                        EmptyView()
                    } else {
                        // Items confirmed but not yet elaborated — show elaboration start card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title3).foregroundStyle(theme.warningAccent)
                                Text(lang.design.reviewComplete)
                                    .font(.callout.weight(.semibold))
                            }
                            Text(lang.design.pendingElaborationGuide)
                                .font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundSecondary)
                            Button {
                                vm.elaborateRemainingItems()
                            } label: {
                                Label(lang.design.startElaborationAction, systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(theme.warningAccent)
                            .controlSize(.regular)
                        }
                        .padding(14)
                        .background(theme.warningAccent.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                                .stroke(theme.warningAccent.opacity(0.3), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))
                    }
                }

                // Global pending uncertainties list
                let pendingUncertainties = wf.pendingUncertainties
                if !pendingUncertainties.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "questionmark.diamond.fill")
                                .foregroundStyle(theme.warningAccent)
                            Text(lang.design.uncertaintyTitle)
                                .font(AppTheme.Typography.caption.weight(.semibold))
                            Spacer()
                            Text(lang.design.uncertaintyCountFormat(pendingUncertainties.count))
                                .font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundTertiary)
                        }
                        ForEach(pendingUncertainties) { uncertainty in
                            uncertaintyCard(uncertainty)
                                .id(uncertainty.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let relatedId = uncertainty.relatedItemId {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            vm.selectedItemId = relatedId
                                        }
                                    }
                                }
                        }
                    }
                }

                // Decision audit trail
                Divider()
                DisclosureGroup {
                    DecisionAuditView(
                        entries: vm.decisionHistory,
                        isLoading: vm.isLoadingHistory,
                        onSelectItem: { itemId in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                vm.selectedItemId = itemId
                            }
                        },
                        theme: theme,
                        lang: lang
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(AppTheme.Typography.caption).foregroundStyle(theme.accentPrimary)
                        Text(lang.design.decisionHistoryTitle)
                            .font(AppTheme.Typography.caption.weight(.semibold))
                        if !vm.decisionHistory.isEmpty {
                            Text(lang.design.decisionCountFormat(vm.decisionHistory.count))
                                .font(AppTheme.Typography.detail).foregroundStyle(theme.foregroundTertiary)
                        }
                    }
                }
                .onAppear {
                    if vm.decisionHistory.isEmpty && !vm.isLoadingHistory {
                        Task { await vm.loadDecisionHistory() }
                    }
                }
            }
        }
        .padding(16)
    }

    // MARK: - Inspector Helpers

    func statusBadge(_ status: DeliverableItemStatus) -> some View {
        let (label, color): (String, Color) = switch status {
        case .completed: (lang.design.statusCompleted, theme.positiveAccent)
        case .inProgress: (lang.design.statusInProgress, theme.accentPrimary)
        case .pending: (lang.design.statusPending, .secondary)
        case .needsRevision: (lang.design.statusNeedsRevision, theme.warningAccent)
        }
        return Text(label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    func relationLabel(_ type: String) -> String {
        switch type {
        case EdgeRelationType.dependsOn: return lang.design.relDependsOn
        case EdgeRelationType.navigatesTo: return lang.design.relNavigatesTo
        case EdgeRelationType.uses: return lang.design.relUses
        case EdgeRelationType.refines: return lang.design.relRefines
        case EdgeRelationType.replaces: return lang.design.relReplaces
        default: return type
        }
    }

    var planningHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist").font(.title2).foregroundStyle(theme.accentPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.design.planningHeadline).font(.headline)
                Text(lang.design.planningDescription).font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundSecondary)
                // Selected approach badge + sub-phase indicator
                HStack(spacing: 6) {
                    if let wf = vm.workflow,
                       let selectedId = wf.selectedApproachId,
                       let approach = wf.approachOptions?.first(where: { $0.id == selectedId }) {
                        Text(approach.label)
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(theme.accentPrimary)
                            .lineLimit(1)
                    }
                    if vm.isRefinePhase {
                        Text(lang.design.refinePhaseLabel)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(theme.warningAccent.opacity(0.12))
                            .foregroundStyle(theme.warningAccent)
                            .clipShape(Capsule())
                    } else if vm.isSpecifyPhase {
                        Text(lang.design.specifyPhaseLabel)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(theme.accentPrimary.opacity(0.12))
                            .foregroundStyle(theme.accentPrimary)
                            .clipShape(Capsule())
                    }
                }
            }

            // View mode toggle (canvas / list)
            HStack(spacing: 0) {
                ForEach(DesignWorkflowViewModel.PlanningViewMode.allCases, id: \.self) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { vm.planningViewMode = mode }
                    } label: {
                        Image(systemName: planningViewModeIcon(mode))
                            .frame(width: 28, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(vm.planningViewMode == mode
                                ? theme.accentPrimary.opacity(0.15)
                                : Color.clear)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))

            // Inspector toggle
            Button { withAnimation(.easeInOut(duration: 0.2)) { vm.inspectorVisible.toggle() } } label: {
                Image(systemName: "sidebar.right")
                    .foregroundStyle(vm.inspectorVisible ? theme.accentPrimary : theme.foregroundSecondary)
            }.buttonStyle(.bordered).controlSize(.small)

            Spacer()
            if let wf = vm.workflow {
                // Progress: confirmed / total
                Text(lang.design.progressItemsFormat(wf.confirmedItemCount, wf.activeItemCount))
                    .font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundSecondary)
                // Uncertainty questions awaiting user response
                let uncertaintyCount = wf.pendingUncertainties.count
                if uncertaintyCount > 0 {
                    Label(lang.design.uncertaintyCountFormat(uncertaintyCount),
                          systemImage: "questionmark.diamond")
                        .font(AppTheme.Typography.caption).foregroundStyle(theme.warningAccent)
                }
                // Blocking banner: spec issues only (progress & questions already visible above)
                let specBlocking = wf.readinessSummary.blockingCount
                if specBlocking > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle")
                            .font(AppTheme.Typography.detail)
                        Text(lang.design.specIssuesBlocking(specBlocking))
                            .font(AppTheme.Typography.detail)
                    }
                    .foregroundStyle(theme.warningAccent)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(theme.warningAccent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            Button { showReanalyzeConfirmation = true } label: {
                Label(lang.design.reanalyze, systemImage: "arrow.counterclockwise")
            }.buttonStyle(.bordered).tint(.secondary).controlSize(.small)
            if vm.isRefinePhase {
                // REFINE: approve structure before elaboration
                Button {
                    vm.requestStructureApproval()
                } label: {
                    Label(lang.design.approveStructure, systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .controlSize(.small)
                .disabled({
                    guard let wf = vm.workflow else { return true }
                    return !wf.blockingUncertainties.isEmpty || wf.pendingReviewCount > 0
                }())
            } else if vm.isSpecifyPhase && (vm.isPreElaboration || vm.hasIncompleteElaborationItems) {
                // SPECIFY (pre-elaboration or interrupted): start/resume detailed spec work
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showElaborationProgressOverlay = true
                    }
                    Task { await vm.elaborateAllPending() }
                } label: {
                    Label(lang.design.startDesignWork, systemImage: "hammer.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .controlSize(.small)
            } else if vm.isElaborating, let wf = vm.workflow {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(lang.design.elaborationProgressFormat(wf.completedItemCount, wf.totalItemCount))
                        .font(AppTheme.Typography.caption.weight(.medium))
                    ZStack {
                        Circle().stroke(theme.borderSubtle, lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: wf.totalItemCount > 0
                                ? Double(wf.completedItemCount) / Double(wf.totalItemCount) : 0)
                            .stroke(theme.accentPrimary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }.frame(width: 16, height: 16)
                }
                .foregroundStyle(theme.accentPrimary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(theme.accentPrimary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
            } else if vm.isSpecifyPhase,
                      let wf = vm.workflow,
                      wf.allItemsConfirmed,
                      vm.hasSubstantiveExport,
                      !vm.isFinishing,
                      vm.isElaborationFullyDone {
                // Items elaborated (initial run or restored from stuck session) — user
                // explicitly triggers finish via the finish-approval overlay.
                Button {
                    vm.requestFinishApproval()
                } label: {
                    Label(lang.design.export, systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .controlSize(.small)
            }
        }.padding(.horizontal, 20).padding(.vertical, 12)
        .sheet(isPresented: $showReanalyzeConfirmation) {
            ReanalyzeConfirmationSheet(
                onConfirm: { feedback in
                    showReanalyzeConfirmation = false
                    vm.reanalyzeWithFeedback(feedback)
                },
                onCancel: {
                    showReanalyzeConfirmation = false
                }
            )
        }
    }

    func taskDescriptionBanner(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "text.quote").font(AppTheme.Typography.caption).foregroundStyle(theme.accentPrimary)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(taskDescriptionExpanded ? nil : 4)
                    .animation(.easeInOut(duration: 0.2), value: taskDescriptionExpanded)
            }
            // Show expand/collapse button when text is likely truncated
            if description.count > 150 {
                Button {
                    taskDescriptionExpanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(taskDescriptionExpanded ? lang.design.showLess : lang.design.showMore)
                            .font(AppTheme.Typography.caption)
                        Image(systemName: taskDescriptionExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(theme.accentPrimary)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accentPrimary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
        .padding(.bottom, 12)
    }

}
