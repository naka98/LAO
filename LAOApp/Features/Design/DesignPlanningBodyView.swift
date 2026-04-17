import SwiftUI
import LAODomain

// MARK: - Summary Item List & Planning Helpers (extracted from DesignWorkflowView)

extension DesignWorkflowView {

    // MARK: - Summary Item List (flat, grouped by scenario)

    func summaryItemList(_ wf: DesignWorkflow) -> some View {
        let clusters = wf.computeScenarioClusters(scenarioSuffix: lang.design.clusterScenarioSuffix, moreFormat: lang.design.clusterMoreFormat)
        let blockingUncertainties = wf.pendingUncertainties.filter { $0.priority == .blocking }
        let nonBlockingUncertainties = wf.pendingUncertainties.filter { $0.priority != .blocking }
        return VStack(alignment: .leading, spacing: 4) {
            // Blocking uncertainties at the very top
            if !blockingUncertainties.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.warningAccent)
                    Text(lang.design.uncertaintyBlocking)
                        .font(.caption.weight(.semibold)).foregroundStyle(theme.foregroundSecondary)
                    Spacer()
                    Text(lang.design.uncertaintyCountFormat(blockingUncertainties.count))
                        .font(.caption2).foregroundStyle(theme.foregroundTertiary)
                }.padding(.horizontal, 4).padding(.top, 4).padding(.bottom, 2)

                ForEach(blockingUncertainties) { uncertainty in
                    listUncertaintyRow(uncertainty)
                }
                Divider().padding(.vertical, 8)
            }

            ForEach(clusters) { cluster in
                let pendingIds = cluster.items
                    .filter { $0.item.designVerdict != .confirmed && $0.item.designVerdict != .excluded }
                    .map(\.item.id)
                // Cluster header
                HStack(spacing: 6) {
                    ForEach(Array(cluster.sectionTypes.sorted()), id: \.self) { type in
                        Image(systemName: sectionIcon(type))
                            .font(AppTheme.Typography.graphCaption).foregroundStyle(sectionColor(type))
                    }
                    Text(cluster.name).font(.caption.weight(.semibold)).foregroundStyle(theme.foregroundSecondary)
                    Spacer()
                    if !pendingIds.isEmpty {
                        Button {
                            vm.setDesignVerdictBatch(pendingIds, .confirmed)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                Text(lang.design.clusterConfirmAll)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.positiveAccent)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("\(cluster.confirmedCount)/\(cluster.activeCount)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(cluster.confirmedCount == cluster.activeCount && cluster.activeCount > 0 ? theme.positiveAccent : theme.foregroundTertiary)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(theme.accentPrimary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.horizontal, 4).padding(.top, 8).padding(.bottom, 2)
                // Items in this cluster
                ForEach(Array(cluster.items.enumerated()), id: \.element.item.id) { _, entry in
                    summaryItemRow(entry.item, sectionType: entry.sectionType, workflow: wf)
                }
            }
            // Non-blocking uncertainties section — questions the AI escalated
            if !nonBlockingUncertainties.isEmpty {
                Divider().padding(.vertical, 8)
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.diamond.fill")
                        .foregroundStyle(theme.warningAccent)
                    Text(lang.design.uncertaintyTitle)
                        .font(.caption.weight(.semibold)).foregroundStyle(theme.foregroundSecondary)
                    Spacer()
                    Text(lang.design.uncertaintyCountFormat(nonBlockingUncertainties.count))
                        .font(.caption2).foregroundStyle(theme.foregroundTertiary)
                }.padding(.horizontal, 4).padding(.top, 4).padding(.bottom, 2)

                ForEach(nonBlockingUncertainties) { uncertainty in
                    listUncertaintyRow(uncertainty)
                }
            }
        }
    }

    /// Compact uncertainty row for the list view. Taps to select the related item in the inspector.
    func listUncertaintyRow(_ uncertainty: DesignDecision) -> some View {
        HStack(spacing: 8) {
            uncertaintyPriorityBadge(uncertainty.priority)
            VStack(alignment: .leading, spacing: 2) {
                Text(uncertainty.title).font(AppTheme.Typography.bodySecondary).lineLimit(2)
                Text(uncertainty.body).font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary).lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.foregroundMuted)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(theme.warningAccent.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                if let relatedId = uncertainty.relatedItemId {
                    vm.selectedItemId = relatedId
                } else {
                    vm.selectedItemId = nil
                }
                vm.inspectorVisible = true
                scrollToUncertaintyId = uncertainty.id
            }
        }
    }

    /// Single item row — name + brief description + quick actions + chevron.
    /// Tap selects item in the inspector panel for detailed review.
    func summaryItemRow(_ item: DeliverableItem, sectionType: String, workflow wf: DesignWorkflow) -> some View {
        let impactCount = wf.downstreamImpactCount(for: item.id)
        let itemUncertaintyCount = wf.pendingUncertainties(for: item.id).count
        let isSelected = vm.selectedItemId == item.id
        return HStack(spacing: 8) {
            designVerdictChip(item.designVerdict, compact: true).font(.system(size: 14))
            Image(systemName: sectionIcon(sectionType))
                .font(AppTheme.Typography.graphLabel).foregroundStyle(sectionColor(sectionType)).frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(AppTheme.Typography.bodySecondary).lineLimit(2)
                    .strikethrough(item.designVerdict == .excluded, color: .secondary)
                    .opacity(item.designVerdict == .excluded ? 0.4 : (item.designVerdict == .confirmed ? 0.6 : 1.0))
                if let d = item.briefDescription, !d.isEmpty {
                    Text(d).font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundSecondary).lineLimit(2)
                        .opacity(item.designVerdict == .excluded ? 0.4 : 1.0)
                }
            }
            if item.status == .inProgress {
                HStack(spacing: 3) {
                    ProgressView().controlSize(.mini)
                    Text(lang.design.statusInProgress).font(AppTheme.Typography.caption)
                }.foregroundStyle(theme.accentPrimary)
            }
            if item.verdictFlipCount >= 2 {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(AppTheme.Typography.graphLabel)
                    .foregroundStyle(.orange)
                    .help(lang.design.oscillationItemHint)
            }
            if itemUncertaintyCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "questionmark.diamond").font(AppTheme.Typography.graphCaption)
                    Text("\(itemUncertaintyCount)").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(theme.warningAccent)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(theme.warningAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Spacer()
            if impactCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.triangle.branch").font(AppTheme.Typography.graphCaption)
                    Text("\(impactCount)").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(theme.warningAccent)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(theme.warningAccent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? theme.accentPrimary : theme.foregroundMuted)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                vm.selectedItemId = item.id
                vm.inspectorVisible = true
            }
        }
        .background(
            isSelected
                ? theme.accentPrimary.opacity(0.08)
                : item.status == .inProgress ? theme.accentPrimary.opacity(0.04)
                : (item.designVerdict == .pending && item.status == .completed) ? theme.positiveAccent.opacity(0.04)
                : item.designVerdict == .excluded ? Color.secondary.opacity(0.06)
                : item.designVerdict == .needsRevision ? theme.warningAccent.opacity(0.06)
                : (item.designVerdict == .confirmed ? theme.positiveAccent.opacity(0.06) : Color.clear)
        )
        .overlay(alignment: .leading) {
            if item.status == .inProgress {
                RoundedRectangle(cornerRadius: 2).fill(theme.accentPrimary).frame(width: 4)
            } else if item.status == .completed && item.designVerdict == .pending {
                RoundedRectangle(cornerRadius: 2).fill(theme.positiveAccent).frame(width: 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
    }

    /// Design verdict chip — decision-maker-facing, 3 states.
    /// `compact: true` renders icon-only for list rows; `false` renders full label chip for inspector.
    @ViewBuilder func designVerdictChip(_ verdict: DesignVerdict, compact: Bool = false) -> some View {
        let (label, color, icon): (String, Color, String) = switch verdict {
        case .pending:       (lang.design.verdictPending, .secondary, "circle.dashed")
        case .confirmed:     (lang.design.verdictConfirmed, theme.positiveAccent, "checkmark.circle.fill")
        case .needsRevision: (lang.design.verdictNeedsRevision, theme.warningAccent, "pencil.circle.fill")
        case .excluded:      (lang.design.verdictExcluded, .secondary, "xmark.circle.fill")
        }
        if compact {
            Image(systemName: icon)
                .foregroundStyle(color)
        } else {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.12))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// Readiness percentage indicator for decision-maker inspector.
    @ViewBuilder func readinessIndicator(_ item: DeliverableItem) -> some View {
        let color: Color = switch item.specReadiness {
        case .ready: .green
        case .incomplete: .orange
        case .notValidated: .secondary
        }
        Circle().fill(color).frame(width: 6, height: 6)
    }

    func readinessLabelText(_ readiness: SpecReadiness) -> String {
        switch readiness {
        case .ready: return lang.design.readinessReady
        case .incomplete: return lang.design.readinessIncomplete
        case .notValidated: return lang.design.readinessNotValidated
        }
    }


    // MARK: - Section Styling Helpers (delegates to shared DeliverableSection statics)

    func sectionColor(_ type: String) -> Color { DeliverableSection.sectionColor(type) }
    func sectionIcon(_ type: String) -> String { DeliverableSection.sectionIcon(type) }
}
