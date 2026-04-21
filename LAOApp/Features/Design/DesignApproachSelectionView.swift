import SwiftUI
import LAODomain

// MARK: - Approach Selection Phase (extracted from DesignWorkflowView)

extension DesignWorkflowView {

    var approachSelectionPhase: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xl) {
                // Title + Re-analyze
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lang.design.approachSelectionTitle)
                            .font(.title2.weight(.bold))
                        Text(lang.design.approachSelectionSubtitle)
                            .font(.subheadline).foregroundStyle(theme.foregroundSecondary)
                    }
                    Spacer()
                    Button { showReanalyzeConfirmation = true } label: {
                        Label(lang.design.reanalyze, systemImage: "arrow.counterclockwise")
                    }.buttonStyle(.bordered).tint(.secondary).controlSize(.small)
                }

                // Hidden requirements — shared across all approaches
                if let approaches = vm.workflow?.approachOptions, !approaches.isEmpty {
                    let allSets = approaches.map { Set($0.hiddenRequirements) }
                    let commonReqs = allSets.dropFirst().reduce(allSets.first ?? []) { $0.intersection($1) }
                    if !commonReqs.isEmpty {
                        SurfaceCard(title: lang.design.hiddenRequirementsTitle) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(lang.design.hiddenRequirementsSubtitle)
                                    .font(.caption).foregroundStyle(theme.foregroundSecondary)
                                ForEach(commonReqs.sorted(), id: \.self) { req in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "eye.trianglebadge.exclamationmark")
                                            .font(.caption).foregroundStyle(theme.warningAccent)
                                        Text(req).font(.callout)
                                    }
                                }
                            }
                        }
                    }
                } else if let reqs = vm.workflow?.hiddenRequirements, !reqs.isEmpty {
                    // Fallback: no approaches yet, show global requirements
                    SurfaceCard(title: lang.design.hiddenRequirementsTitle) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(lang.design.hiddenRequirementsSubtitle)
                                .font(.caption).foregroundStyle(theme.foregroundSecondary)
                            ForEach(reqs, id: \.self) { req in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "eye.trianglebadge.exclamationmark")
                                        .font(.caption).foregroundStyle(theme.warningAccent)
                                    Text(req).font(.callout)
                                }
                            }
                        }
                    }
                }

                // Approach cards (side-by-side)
                if let approaches = vm.workflow?.approachOptions, !approaches.isEmpty {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.l) {
                        ForEach(approaches) { approach in
                            approachCard(approach)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    func approachCard(_ approach: ApproachOption) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.m) {
            // Header
            HStack {
                Text(approach.label).font(.headline).lineLimit(2)
                Spacer()
                if approach.isRecommended {
                    BadgeView(title: lang.design.approachRecommended, tone: .blue)
                }
            }

            Text(approach.summary).font(AppTheme.Typography.bodySecondary).foregroundStyle(theme.foregroundPrimary)

            // Reasoning callout
            if !approach.reasoning.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption).foregroundStyle(theme.warningAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lang.design.approachReasoningTitle)
                            .font(AppTheme.Typography.bodySecondary.weight(.semibold)).foregroundStyle(theme.foregroundPrimary)
                        Text(approach.reasoning)
                            .font(AppTheme.Typography.bodySecondary).foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding(AppTheme.Spacing.s)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .fill(theme.surfaceSubtle)
                )
            }

            Divider()

            // Complexity
            HStack(spacing: 6) {
                Text(lang.design.approachComplexity).font(.caption).foregroundStyle(theme.foregroundSecondary)
                Text(localizedComplexity(approach.estimatedComplexity))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(complexityColor(approach.estimatedComplexity))
            }

            // Pros
            if !approach.pros.isEmpty {
                approachListSection(
                    title: lang.design.approachPros,
                    items: approach.pros,
                    icon: "checkmark.circle.fill",
                    color: theme.positiveAccent
                )
            }

            // Cons
            if !approach.cons.isEmpty {
                approachListSection(
                    title: lang.design.approachCons,
                    items: approach.cons,
                    icon: "xmark.circle.fill",
                    color: theme.criticalAccent
                )
            }

            // Risks
            if !approach.risks.isEmpty {
                approachListSection(
                    title: lang.design.approachRisks,
                    items: approach.risks,
                    icon: "exclamationmark.triangle.fill",
                    color: theme.warningAccent
                )
            }

            // Per-approach unique hidden requirements
            if let approaches = vm.workflow?.approachOptions, approaches.count > 1 {
                let allSets = approaches.map { Set($0.hiddenRequirements) }
                let commonReqs = allSets.dropFirst().reduce(allSets.first ?? []) { $0.intersection($1) }
                let uniqueReqs = approach.hiddenRequirements.filter { !commonReqs.contains($0) }
                if !uniqueReqs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.trianglebadge.exclamationmark")
                                .font(.system(size: 11)).foregroundStyle(theme.warningAccent)
                            Text(lang.design.approachUniqueRequirement)
                                .font(AppTheme.Typography.caption.weight(.medium)).foregroundStyle(theme.warningAccent)
                        }
                        ForEach(uniqueReqs, id: \.self) { req in
                            Text(req).font(AppTheme.Typography.caption).foregroundStyle(theme.foregroundSecondary)
                        }
                    }
                    .padding(AppTheme.Spacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                            .fill(theme.warningAccent.opacity(0.06))
                    )
                }
            }

            // Deliverable section pills
            if !approach.deliverables.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(approach.deliverables) { section in
                        HStack(spacing: 4) {
                            Image(systemName: sectionIcon(section.type))
                                .font(.system(size: 11))
                            Text("\(section.label) (\(section.items.count))")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(sectionColor(section.type).opacity(0.1))
                        )
                        .foregroundStyle(sectionColor(section.type))
                    }
                }
                if let rels = approach.relationships, !rels.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "link").font(.system(size: 11))
                        Text(lang.design.approachConnectionsFormat(rels.count))
                            .font(.caption2)
                    }
                    .foregroundStyle(theme.foregroundSecondary)
                }
            }

            Spacer()

            // Select button
            Button {
                vm.selectApproach(approach.id)
            } label: {
                Text(lang.design.approachSelect)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(approach.isRecommended ? theme.accentPrimary : nil)
        }
        .padding(AppTheme.Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .fill(theme.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                .stroke(approach.isRecommended ? theme.accentPrimary : theme.borderSubtle, lineWidth: approach.isRecommended ? 2 : 1)
        )
        .shadow(color: theme.shadowColor, radius: 4, y: 2)
    }

    func approachListSection(title: String, items: [String], icon: String, color: Color) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(AppTheme.Typography.bodySecondary.weight(.semibold)).foregroundStyle(theme.foregroundSecondary)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color)
                            .frame(width: 14, height: 14)
                        Text(item).font(AppTheme.Typography.bodySecondary)
                    }
                }
            }
            .padding(.leading, 8)
            .padding(.vertical, 6)
        }
        .padding(.trailing, 6)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                .fill(color.opacity(0.04))
        )
    }

    func planningViewModeIcon(_ mode: DesignWorkflowViewModel.PlanningViewMode) -> String {
        switch mode {
        case .canvas:    "rectangle.connected.to.line.below"
        case .list:      "list.bullet"
        }
    }

    func localizedComplexity(_ value: String) -> String {
        switch value {
        case "low": lang.design.approachComplexityLow
        case "high": lang.design.approachComplexityHigh
        default: lang.design.approachComplexityMedium
        }
    }

    func complexityColor(_ value: String) -> Color {
        switch value {
        case "low": theme.positiveAccent
        case "high": theme.criticalAccent
        default: theme.warningAccent
        }
    }

    // MARK: - Structure Approval Confirmation Overlay (REFINE → SPECIFY)

    /// [Purpose] 구조(skeleton) 생성 완료 후 사용자가 확정해 SPECIFY(설계 착수) phase로 넘어가기 전 승인받는 게이트.
    /// [Trigger] `vm.showStructureApproval == true`.
    /// [Sibling]
    ///   - `finishApprovalOverlay`: SPECIFY 완료 → 완료 phase 전환 승인 게이트.
    ///     이 오버레이는 REFINE → SPECIFY 전환 게이트. 두 오버레이 모두 phase 전환 승인용이지만 시점이 다름.
    /// [Flow] skeleton 생성 완료 → Structure Approval(이 오버레이) → 승인 → elaborate 시작 가능.
    var structureApprovalOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {}

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(theme.accentPrimary)
                    Text(lang.design.structureApprovalTitle)
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(lang.design.structureApprovalMessage)
                            .font(AppTheme.Typography.label)
                            .foregroundStyle(theme.foregroundSecondary)

                        // Structure summary — section pills with item counts
                        if let wf = vm.workflow, !wf.deliverables.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                FlowLayout(spacing: 6) {
                                    ForEach(wf.deliverables) { section in
                                        HStack(spacing: 4) {
                                            Image(systemName: sectionIcon(section.type))
                                                .font(.system(size: 11))
                                            Text("\(section.label) (\(section.activeItems.count))")
                                                .font(.caption2)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(sectionColor(section.type).opacity(0.1)))
                                        .foregroundStyle(sectionColor(section.type))
                                    }
                                }
                                Text("\(wf.activeItemCount) items · \(wf.deliverables.count) sections")
                                    .font(AppTheme.Typography.caption)
                                    .foregroundStyle(theme.foregroundSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(theme.accentPrimary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                        }

                        // Gate blockers
                        if let gate = vm.structureGateResult, !gate.blockers.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.octagon.fill")
                                        .font(.caption).foregroundStyle(theme.criticalAccent)
                                    Text(lang.design.designFreezeBlocker)
                                        .font(AppTheme.Typography.caption.weight(.semibold))
                                        .foregroundStyle(theme.criticalAccent)
                                }
                                ForEach(gate.blockers, id: \.self) { blocker in
                                    Text("• \(blocker)").font(.caption).foregroundStyle(theme.criticalAccent)
                                }
                            }
                            .padding(10)
                            .background(theme.criticalAccent.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                        }

                        // Gate warnings
                        if let gate = vm.structureGateResult, !gate.warnings.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption).foregroundStyle(theme.warningAccent)
                                    Text(gate.warnings.joined(separator: ", "))
                                        .font(AppTheme.Typography.caption)
                                        .foregroundStyle(theme.warningAccent)
                                }
                            }
                            .padding(10)
                            .background(theme.warningAccent.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                        }

                        // Warning
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(theme.warningAccent)
                            Text(lang.design.structureApprovalWarning)
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(theme.warningAccent)
                        }
                    }
                    .padding(24)
                }

                Divider()

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        vm.cancelStructureApproval()
                    } label: {
                        Text(lang.design.structureApprovalBack)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .controlSize(.large)

                    Button {
                        vm.confirmStructureApproval()
                    } label: {
                        Label(lang.design.structureApprovalConfirm, systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .controlSize(.large)
                    .disabled(vm.structureGateResult?.canProceed == false)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .frame(minWidth: 400, maxWidth: 520, minHeight: 300, maxHeight: 480)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 4)
        }
    }
}
