import SwiftUI

// MARK: - Elaboration Progress Overlay

/// [Purpose] 설계 elaborate(항목별 스펙 채우기) 단계 진행 표시. 항목별 status(queued → working → done/failed)와 전체 진행률 노출.
/// [Trigger] `showElaborationProgressOverlay == true` (사용자가 "설계 착수" 클릭 시 또는 interrupted 상태 감지로 자동).
/// [Sibling]
///   - `finishProgressOverlay`: elaborate 완료 후 finish 단계(일관성 검사/수정 적용/export) 진행 표시. 이 오버레이는 elaborate 단계 자체의 진행 표시.
/// [Flow] 사용자 "설계 착수" → Elaboration Progress(이 오버레이) → 모든 항목 완료 → 오버레이 dismiss → 사용자 "종료" → finishApproval → finishProgress → 완료.
struct ElaborationProgressOverlay: View {
    @Bindable var vm: DesignWorkflowViewModel
    let onDismiss: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang

    private var workflow: DesignWorkflow? { vm.workflow }

    private var allItems: [(section: DeliverableSection, item: DeliverableItem)] {
        guard let wf = workflow else { return [] }
        return wf.deliverables.flatMap { section in
            section.items
                .filter { $0.designVerdict != .excluded }
                .map { (section, $0) }
        }
    }

    private var totalCount: Int { allItems.count }
    private var completedCount: Int { allItems.filter { $0.item.status == .completed }.count }
    private var failedCount: Int { allItems.filter { $0.item.status == .needsRevision && !vm.activeItemWorks.keys.contains($0.item.id) }.count }
    /// Anchored on `isElaborationFullyDone` (not just `!isElaborating`) so the footer
    /// state does not flicker into "All complete" during the brief idle gap between
    /// parallel-elaboration groups.
    private var isAllDone: Bool { vm.isElaborationFullyDone && completedCount > 0 }

    private var hasExportable: Bool {
        workflow.map { !$0.deliverables.flatMap(\.exportableItems).isEmpty } ?? false
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { /* block tap-through */ }

            VStack(spacing: 0) {
                headerBar
                Divider()
                itemList
                Divider()
                footerBar
            }
            .frame(width: 480)
            .frame(minHeight: 300, maxHeight: 560)
            .background(theme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 8)
        }
        .transition(.opacity)
        .onChange(of: isAllDone) { _, done in
            guard done else { return }
            // Retry succeeded with no failures — auto-dismiss so the user returns to the
            // inspector where the morphed header "Export" button is now visible.
            if vm.isRetryElaboration && failedCount == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { onDismiss() }
                return
            }
            // Initial run: do NOT auto-chain into finishWorkflow. The user explicitly
            // triggers consistency check + export via the footer button or the header
            // "Export" slot, going through the finish-approval overlay (matching the
            // structure-approval pattern).
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.design.elaborationOverlayTitle)
                    .font(.headline)
                if vm.isPreparingElaboration {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(lang.design.elaborationPreparing)
                            .font(.subheadline)
                            .foregroundStyle(theme.foregroundSecondary)
                    }
                } else if vm.isElaborating {
                    Text(lang.design.elaborationOverlaySubtitle(totalCount))
                        .font(.subheadline)
                        .foregroundStyle(theme.foregroundSecondary)
                }
            }
            Spacer()

            // Progress ring
            if totalCount > 0 {
                ZStack {
                    Circle().stroke(theme.borderSubtle, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: Double(completedCount) / Double(totalCount))
                        .stroke(theme.accentPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(completedCount)/\(totalCount)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.foregroundPrimary)
                }
                .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Item List

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(allItems, id: \.item.id) { pair in
                    itemRow(pair.section, pair.item)
                }
            }
            .padding(16)
        }
    }

    private func itemRow(_ section: DeliverableSection, _ item: DeliverableItem) -> some View {
        let isWorking = vm.activeItemWorks[item.id] != nil
        let work = vm.activeItemWorks[item.id]

        return HStack(spacing: 10) {
            // Status indicator
            statusIcon(item, isWorking: isWorking)

            // Section icon + item name
            Image(systemName: sectionIcon(section.type))
                .font(.caption)
                .foregroundStyle(sectionColor(section.type))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.callout)
                    .foregroundStyle(theme.foregroundPrimary)
                    .lineLimit(1)

                if isWorking, let w = work, !w.streamOutput.isEmpty {
                    Text(w.streamOutput)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(theme.foregroundTertiary)
                        .lineLimit(1)
                } else if isWorking, let w = work {
                    Text(w.agentLabel)
                        .font(.caption2)
                        .foregroundStyle(theme.foregroundTertiary)
                }
            }

            Spacer()

            // Status label
            statusLabel(item, isWorking: isWorking)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.small)
                .fill(isWorking ? theme.accentPrimary.opacity(0.04) : Color.clear)
        )
    }

    @ViewBuilder
    private func statusIcon(_ item: DeliverableItem, isWorking: Bool) -> some View {
        if isWorking {
            ProgressView().controlSize(.mini)
                .frame(width: 16, height: 16)
        } else if item.status == .completed {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(theme.positiveAccent)
        } else if item.status == .needsRevision {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(theme.warningAccent)
        } else {
            Image(systemName: "circle")
                .font(.system(size: 14))
                .foregroundStyle(theme.borderSubtle)
        }
    }

    private func statusLabel(_ item: DeliverableItem, isWorking: Bool) -> some View {
        let (text, color): (String, Color) = {
            if isWorking {
                return (lang.design.elaborationItemWorking, theme.accentPrimary)
            }
            switch item.status {
            case .completed: return (lang.design.elaborationItemDone, theme.positiveAccent)
            case .needsRevision: return (lang.design.elaborationItemFailed, theme.warningAccent)
            case .inProgress: return (lang.design.elaborationItemWorking, theme.accentPrimary)
            case .pending: return (lang.design.elaborationItemPending, theme.foregroundTertiary)
            }
        }()
        return Text(text)
            .font(.caption)
            .foregroundStyle(color)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 12) {
            if let step = vm.finishingStep {
                // Finishing phase: consistency check, applying fixes, or export in progress
                ProgressView().controlSize(.small)
                Text(finishingStepLabel(step))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.accentPrimary)
                Spacer()
            } else if isAllDone && failedCount > 0 {
                // Some or all items failed — offer retry or proceed/dismiss
                Label(lang.design.elaborationFailed, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.warningAccent)
                Text("\(failedCount)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.warningAccent)
                Spacer()
                Button {
                    vm.elaborateRemainingItems()
                } label: {
                    Label(lang.design.retryElaboration, systemImage: "arrow.counterclockwise")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.bordered)
                .tint(theme.accentPrimary)
                .controlSize(.regular)
                if hasExportable {
                    Button {
                        vm.requestFinishApproval()
                    } label: {
                        Label(lang.design.export, systemImage: "square.and.arrow.up")
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.positiveAccent)
                    .controlSize(.regular)
                    .disabled(!vm.isElaborationFullyDone)
                } else {
                    Button { onDismiss() } label: {
                        Label(lang.common.dismiss, systemImage: "xmark")
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            } else if isAllDone {
                // All succeeded — invite the user to explicitly trigger finish.
                Label(lang.design.elaborationAllComplete, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.positiveAccent)
                Spacer()
                if hasExportable {
                    Button {
                        vm.requestFinishApproval()
                    } label: {
                        Label(lang.design.runFinishCTA, systemImage: "square.and.arrow.up")
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.positiveAccent)
                    .controlSize(.regular)
                    .disabled(!vm.isElaborationFullyDone)
                }
            } else {
                Spacer()
                if vm.isElaborating {
                    Button {
                        Task { await vm.gracefulStop() }
                        onDismiss()
                    } label: {
                        Label(lang.common.stop, systemImage: "stop.circle")
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.criticalAccent)
                    .controlSize(.regular)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private func sectionIcon(_ type: String) -> String {
        switch type {
        case "screen": return "rectangle.on.rectangle"
        case "api": return "arrow.left.arrow.right"
        case "dataModel": return "cylinder"
        case "userFlow": return "arrow.triangle.branch"
        default: return "doc"
        }
    }

    private func finishingStepLabel(_ step: DesignWorkflowViewModel.FinishingStep) -> String {
        switch step {
        case .consistencyCheck: return lang.design.elaborationConsistencyChecking
        case .applyingFixes: return lang.design.elaborationApplyingFixes
        case .exporting: return lang.design.elaborationExporting
        }
    }

    private func sectionColor(_ type: String) -> Color {
        switch type {
        case "screen": return theme.accentPrimary
        case "api": return .orange
        case "dataModel": return .purple
        case "userFlow": return .teal
        default: return theme.foregroundSecondary
        }
    }
}
