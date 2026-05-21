import LAODomain
import SwiftUI

// `GraphNode` and `GraphEdge` are explicitly module-qualified throughout this file
// because LAOApp/Features/Design/WorkGraphView.swift defines internal types of the
// same name for the v0.7 work graph visualization. Until v0.7 is retired we keep the
// two namespaces isolated by qualifying our v0.8 references.

/// v0.8 mindmap canvas — Phase 2 Step 2a (static).
///
/// Renders the seed (idea title) at center with 6 weak starter roots arranged radially.
/// Interaction (node expansion, AI conversation, drag) is intentionally out of scope here;
/// later sub-steps layer those on top of this static foundation.
struct NodeGraphWorkflowView: View {
    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang
    @State private var viewModel: NodeGraphWorkflowViewModel

    init(container: AppContainer, projectId: UUID, ideaId: UUID, ideaTitle: String) {
        _viewModel = State(wrappedValue: NodeGraphWorkflowViewModel(
            container: container,
            projectId: projectId,
            ideaId: ideaId,
            ideaTitle: ideaTitle
        ))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView(lang.ideaBoard.nodeGraphLoadingStatus)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let seed = viewModel.seedNode {
                canvas(seed: seed, starters: viewModel.starterNodes)
            } else {
                ContentUnavailableView(
                    lang.ideaBoard.designModeGraphPlaceholderTitle,
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
            }
        }
        .task { await viewModel.loadOrBootstrap() }
        .alert(
            viewModel.errorAlert?.title ?? "",
            isPresented: Binding(
                get: { viewModel.errorAlert != nil },
                set: { if !$0 { viewModel.errorAlert = nil } }
            ),
            presenting: viewModel.errorAlert
        ) { _ in
            Button(lang.common.confirm) { }
        } message: { item in
            Text(item.detail)
        }
    }

    // MARK: - Canvas

    @ViewBuilder
    private func canvas(seed: LAODomain.GraphNode, starters: [LAODomain.GraphNode]) -> some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let starterRadius = min(geo.size.width, geo.size.height) * 0.32
            let starterPositions = computeStarterPositions(
                count: starters.count,
                center: center,
                radius: starterRadius
            )

            ZStack {
                ForEach(Array(starterPositions.enumerated()), id: \.offset) { _, position in
                    edgeLine(from: center, to: position)
                }

                nodeChip(node: seed)
                    .position(center)

                ForEach(Array(starters.enumerated()), id: \.element.id) { idx, starter in
                    if idx < starterPositions.count {
                        nodeChip(node: starter)
                            .position(starterPositions[idx])
                    }
                }
            }
        }
    }

    /// Distributes `count` points evenly on a circle, starting at the top (12 o'clock)
    /// and proceeding clockwise.
    private func computeStarterPositions(count: Int, center: CGPoint, radius: Double) -> [CGPoint] {
        guard count > 0 else { return [] }
        let step = 2 * Double.pi / Double(count)
        return (0..<count).map { i in
            let angle = -Double.pi / 2 + step * Double(i)
            return CGPoint(
                x: center.x + CGFloat(cos(angle) * radius),
                y: center.y + CGFloat(sin(angle) * radius)
            )
        }
    }

    private func edgeLine(from: CGPoint, to: CGPoint) -> some View {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(theme.foregroundMuted.opacity(0.45), lineWidth: 1)
    }

    @ViewBuilder
    private func nodeChip(node: LAODomain.GraphNode) -> some View {
        let isSeed = node.kind == .seed
        Text(node.title)
            .font(isSeed ? AppTheme.Typography.heading : AppTheme.Typography.bodySecondary.weight(.medium))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 140)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                    .fill(isSeed ? theme.accentSoft : theme.surfaceSubtle)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                            .stroke(
                                isSeed ? theme.accentPrimary : theme.foregroundMuted.opacity(0.35),
                                lineWidth: isSeed ? 1.5 : 1
                            )
                    )
            )
            .foregroundStyle(isSeed ? theme.accentPrimary : theme.foregroundSecondary)
            .opacity(isSeed ? 1.0 : 0.85)
    }
}
