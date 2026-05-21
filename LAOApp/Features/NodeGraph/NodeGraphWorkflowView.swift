import LAODomain
import SwiftUI

// `GraphNode` and `GraphEdge` are explicitly module-qualified throughout this file
// because LAOApp/Features/Design/WorkGraphView.swift defines internal types of the
// same name for the v0.7 work graph visualization. Until v0.7 is retired we keep the
// two namespaces isolated by qualifying our v0.8 references.

/// v0.8 mindmap canvas — Phase 2 Step 2b.
///
/// Renders the seed (idea title) at center with 6 weak starter roots arranged radially.
/// Nodes fade in sequentially on first appearance and expand in place when tapped,
/// revealing a stub conversation surface (AI wiring lands in Step 3).
struct NodeGraphWorkflowView: View {
    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang
    @State private var viewModel: NodeGraphWorkflowViewModel
    @State private var visibleNodeIds: Set<UUID> = []
    @State private var expandedNodeId: UUID?

    private static let seedRevealDelay: Duration = .milliseconds(200)
    private static let starterRevealGap: Duration = .milliseconds(280)

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
        .task {
            await viewModel.loadOrBootstrap()
            await runFadeInSequence()
        }
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
                ForEach(Array(starterPositions.enumerated()), id: \.offset) { idx, position in
                    let starterId = idx < starters.count ? starters[idx].id : nil
                    edgeLine(from: center, to: position)
                        .opacity(starterId.map { visibleNodeIds.contains($0) } == true ? 1 : 0)
                        .animation(.easeInOut(duration: 0.5), value: visibleNodeIds)
                }

                if expandedNodeId != nil {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { expandedNodeId = nil }
                        .zIndex(5)
                }

                nodeChip(node: seed)
                    .position(center)
                    .zIndex(expandedNodeId == seed.id ? 10 : 1)

                ForEach(Array(starters.enumerated()), id: \.element.id) { idx, starter in
                    if idx < starterPositions.count {
                        nodeChip(node: starter)
                            .position(starterPositions[idx])
                            .zIndex(expandedNodeId == starter.id ? 10 : 1)
                    }
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: expandedNodeId)
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
        let isExpanded = expandedNodeId == node.id
        let isSeed = node.kind == .seed

        VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
            HStack(spacing: 8) {
                Text(node.title)
                    .font(isExpanded
                          ? AppTheme.Typography.heading
                          : (isSeed
                             ? AppTheme.Typography.heading
                             : AppTheme.Typography.bodySecondary.weight(.medium)))
                    .lineLimit(isExpanded ? nil : 2)
                    .multilineTextAlignment(isExpanded ? .leading : .center)
                    .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
                if isExpanded {
                    Button {
                        expandedNodeId = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(theme.foregroundMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(lang.ideaBoard.nodeGraphExpandedClose)
                }
            }

            if isExpanded {
                Divider()
                if node.body.isEmpty {
                    Text(lang.ideaBoard.nodeGraphExpandedEmptyBody)
                        .font(AppTheme.Typography.bodySecondary)
                        .foregroundStyle(theme.foregroundMuted)
                } else {
                    Text(node.body)
                        .font(AppTheme.Typography.bodySecondary)
                        .foregroundStyle(theme.foregroundSecondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(lang.ideaBoard.nodeGraphExpandedConversationTitle)
                        .font(AppTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(theme.foregroundSecondary)
                    Text(lang.ideaBoard.nodeGraphExpandedConversationHint)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundMuted)
                }
            }
        }
        .padding(.horizontal, isExpanded ? 16 : 14)
        .padding(.vertical, isExpanded ? 14 : 10)
        .frame(
            maxWidth: isExpanded ? 300 : 140,
            minHeight: isExpanded ? 220 : nil,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                .fill(chipFill(isSeed: isSeed, isExpanded: isExpanded))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                        .stroke(
                            chipStroke(isSeed: isSeed, isExpanded: isExpanded),
                            lineWidth: (isSeed || isExpanded) ? 1.5 : 1
                        )
                )
                .shadow(
                    color: isExpanded ? Color.black.opacity(0.18) : .clear,
                    radius: isExpanded ? 12 : 0,
                    x: 0,
                    y: isExpanded ? 4 : 0
                )
        )
        .foregroundStyle(isSeed ? theme.accentPrimary : theme.foregroundSecondary)
        .opacity(chipOpacity(node: node, isExpanded: isExpanded))
        .animation(.easeIn(duration: 0.5), value: visibleNodeIds)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isExpanded {
                expandedNodeId = node.id
            }
        }
    }

    private func chipFill(isSeed: Bool, isExpanded: Bool) -> Color {
        if isExpanded { return theme.surfaceSubtle }
        return isSeed ? theme.accentSoft : theme.surfaceSubtle
    }

    private func chipStroke(isSeed: Bool, isExpanded: Bool) -> Color {
        if isExpanded { return theme.accentPrimary.opacity(0.5) }
        return isSeed ? theme.accentPrimary : theme.foregroundMuted.opacity(0.35)
    }

    /// Visible nodes are fully opaque; starters that haven't been revealed yet are 0;
    /// non-seed nodes also receive a small fade-down when another node is expanded
    /// so the expanded card stands out.
    private func chipOpacity(node: LAODomain.GraphNode, isExpanded: Bool) -> Double {
        guard visibleNodeIds.contains(node.id) else { return 0 }
        if isExpanded { return 1.0 }
        if let activeId = expandedNodeId, activeId != node.id {
            return 0.55
        }
        return node.kind == .seed ? 1.0 : 0.9
    }

    // MARK: - Fade-in sequence

    /// Reveal seed first after a short beat, then starters at a steady cadence.
    /// Bails out if the view is dismissed mid-sequence (Task cancellation).
    private func runFadeInSequence() async {
        if let seed = viewModel.seedNode {
            try? await Task.sleep(for: Self.seedRevealDelay)
            guard !Task.isCancelled else { return }
            visibleNodeIds.insert(seed.id)
        }
        for starter in viewModel.starterNodes {
            try? await Task.sleep(for: Self.starterRevealGap)
            guard !Task.isCancelled else { return }
            visibleNodeIds.insert(starter.id)
        }
    }
}
