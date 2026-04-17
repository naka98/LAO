import SwiftUI
import LAODomain

// MARK: - Finishing Overlay, Completed Phase, Failed Phase (extracted from DesignWorkflowView)

extension DesignWorkflowView {

    @ViewBuilder func finishingOverlay(step: DesignWorkflowViewModel.FinishingStep) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { /* block tap-through */ }
            VStack(spacing: 20) {
                ProgressView()
                    .controlSize(.large)
                Text(finishingStepLabel(step))
                    .font(.headline)
                    .foregroundStyle(theme.foregroundPrimary)
            }
            .padding(40)
            .background(theme.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 8)
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    var completedPhase: some View {
        VStack { Spacer()
            VStack(spacing: AppTheme.Spacing.l) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(theme.positiveAccent)
                Text(lang.design.workflowCompleted).font(.title2.weight(.bold))
                if let wf = vm.workflow {
                    // Per-section breakdown: "화면 설계 6, 데이터 모델 8, 사용자 플로우 7"
                    Text(wf.deliverables.map { "\($0.label) \($0.completedCount)" }.joined(separator: ", "))
                        .font(.subheadline).foregroundStyle(theme.foregroundSecondary)
                    if vm.totalApiCallCount > 0 {
                        HStack(spacing: 4) {
                            Text(lang.design.apiCallsFormat(vm.totalApiCallCount)).font(.caption.monospaced())
                            Text(lang.design.tokensFormat(formattedTokens(vm.totalEstimatedTokens))).font(.caption.monospaced())
                        }.foregroundStyle(theme.foregroundTertiary)
                    }
                }
                HStack(spacing: 12) {
                    Button { openDocumentOverlay() } label: { Label(lang.common.documents, systemImage: "doc.text") }
                        .buttonStyle(SecondaryActionButtonStyle())
                    Button { onClose?() } label: { Label(lang.design.backToList, systemImage: "chevron.left") }
                        .buttonStyle(PrimaryActionButtonStyle())
                }
                if vm.hasExportedDeliverables && vm.hasSubstantiveExport {
                    HStack(spacing: 8) {
                        Text(lang.design.openIn).font(.caption).foregroundStyle(theme.foregroundSecondary)
                        ForEach(DesignWorkflowViewModel.AITool.allCases, id: \.self) { tool in
                            Button { vm.openInAITool(tool) } label: {
                                Label(tool.rawValue, systemImage: tool.icon)
                            }.buttonStyle(SecondaryActionButtonStyle())
                        }
                    }
                    if !vm.exportValidationIssues.isEmpty {
                        let errorCount = vm.exportValidationIssues.filter { $0.severity == .error }.count
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(vm.exportValidationIssues.enumerated()), id: \.offset) { _, issue in
                                    Label {
                                        Text(issue.message).font(.caption)
                                    } icon: {
                                        Image(systemName: issue.severity == .error ? "xmark.circle" : "exclamationmark.triangle")
                                            .foregroundStyle(issue.severity == .error ? theme.criticalAccent : theme.warningAccent)
                                    }
                                }
                            }
                        } label: {
                            Label(
                                lang.design.exportValidationErrorsFormat(vm.exportValidationIssues.count),
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(errorCount > 0 ? theme.criticalAccent : theme.warningAccent)
                        }
                        .frame(maxWidth: 400)
                    }
                }
            }; Spacer()
        }.frame(maxWidth: .infinity)
    }

    var failedPhase: some View {
        VStack { Spacer()
            VStack(spacing: AppTheme.Spacing.l) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 48)).foregroundStyle(theme.criticalAccent)
                Text(lang.design.workflowFailed).font(.title2.weight(.bold))
                if let e = vm.errorMessage {
                    Text(e).font(.subheadline).foregroundStyle(theme.foregroundSecondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 400)
                }
                Button { vm.restartWorkflow() } label: { Label(lang.common.retry, systemImage: "arrow.counterclockwise") }
                    .buttonStyle(PrimaryActionButtonStyle())
            }; Spacer()
        }.frame(maxWidth: .infinity)
    }

    private func finishingStepLabel(_ step: DesignWorkflowViewModel.FinishingStep) -> String {
        switch step {
        case .consistencyCheck: return lang.design.finishStepConsistencyCheck
        case .applyingFixes: return lang.design.finishStepApplyingFixes
        case .exporting: return lang.design.finishStepExporting
        }
    }
}
