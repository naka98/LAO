import SwiftUI

// MARK: - Work Graph Visualization

/// Canvas-based node-edge diagram for the Design work graph.
/// Uses dependency-aware column layout when depends_on edges exist,
/// falling back to Fruchterman-Reingold force-directed layout otherwise.
///
/// Nodes are rendered as readable card-style rectangles showing:
/// - Section icon + section label (Korean)
/// - Item name (up to 2 lines)
/// - Status accent bar on the left edge
/// - Status chip (localized)
struct WorkGraphView: View {
    let workflow: DesignWorkflow
    var selectedItemId: UUID?
    var isMinimapMode: Bool = false
    let onSelectItem: (UUID) -> Void
    var onAddEdge: ((UUID, UUID, String) -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang
    @State private var nodes: [GraphNode] = []
    @State private var graphEdges: [GraphEdge] = []
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @State private var hoveredNodeId: UUID?
    @State private var lastLayoutItemCount: Int = -1
    @State private var lastLayoutEdgeCount: Int = -1
    @State private var lastLayoutSize: CGSize = .zero
    @State private var layoutDebounceTask: Task<Void, Never>?
    @State private var criticalPathIds: Set<UUID> = []
    @State private var isStoryboardMode: Bool = false
    @State private var zoomPhase: ZoomPhase = .storyboard

    // Interactive editing state
    @State private var isDraggingNode: Bool = false
    @State private var dragStartPosition: CGPoint = .zero
    @State private var isLinkMode: Bool = false
    @State private var linkSourceId: UUID?
    @State private var showConvergenceDetail: Bool = false
    @State private var clusterRegions: [ClusterRegion] = []
    @State private var treeChildrenMap: [UUID: [UUID]] = [:]

    // MARK: - Card Dimensions

    /// Full-mode card size (readable text)
    private let cardSize = CGSize(width: 180, height: 72)
    /// Minimap-mode card size (compact overview)
    private let minimapCardSize = CGSize(width: 80, height: 30)

    /// Default card size reference for minimap/legacy rendering.
    private var defaultCardSize: CGSize { isMinimapMode ? minimapCardSize : cardSize }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if isMinimapMode {
                    minimapCanvas
                } else if isStoryboardMode {
                    // Storyboard mode: edges behind cards so lines don't cross card faces
                    storyboardEdgeCanvas
                        .allowsHitTesting(false)
                        .drawingGroup()

                    storyboardNodeLayer
                        .gesture(magnificationGesture.simultaneously(with: dragGesture))

                    VStack(alignment: .leading, spacing: 8) {
                        legendOverlay
                        fitButton
                    }
                } else {
                    // Graph mode: all node types as equal citizens
                    edgeCanvas
                        .allowsHitTesting(false)
                        .drawingGroup()

                    nodeLayer
                        .gesture(magnificationGesture.simultaneously(with: dragGesture))

                    VStack(alignment: .leading, spacing: 8) {
                        legendOverlay
                        HStack(spacing: 6) {
                            fitButton
                            linkModeButton
                        }
                    }
                }
            }
            // Convergence info shown via inspector banner + header bar; overlay removed to reduce redundancy
            .onAppear { scheduleLayout(in: geo.size, force: true) }
            .onChange(of: geo.size.width) { _, _ in handleResize(geo.size) }
            .onChange(of: geo.size.height) { _, _ in handleResize(geo.size) }
            .onChange(of: workflow.edges.count) { _, _ in scheduleLayout(in: geo.size) }
            .onChange(of: workflow.totalItemCount) { _, _ in scheduleLayout(in: geo.size, force: true) }
            .onChange(of: workflow.completedItemCount) { _, _ in scheduleLayout(in: geo.size, force: true) }
            .onChange(of: scale) { _, newScale in
                let newPhase = ZoomPhase(scale: newScale)
                if newPhase != zoomPhase {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        zoomPhase = newPhase
                    }
                }
            }
        }
        .background(theme.surfacePrimary)
    }

    // MARK: - Edge-Only Canvas (full mode)

    private var edgeCanvas: some View {
        Canvas { context, size in
            let transform = CGAffineTransform(translationX: offset.width, y: offset.height)
                .scaledBy(x: scale, y: scale)
            let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

            if scale >= 0.5 {
                drawDotGrid(context: &context, size: size, transform: transform)
            }

            // Cluster background regions
            for region in clusterRegions {
                let transformedRect = region.rect.applying(transform)
                let bgPath = RoundedRectangle(cornerRadius: 10 * scale).path(in: transformedRect)
                context.fill(bgPath, with: .color(region.color.opacity(0.04)))
                context.stroke(bgPath, with: .color(region.color.opacity(0.15)),
                               style: StrokeStyle(lineWidth: 1 * scale, dash: [4 * scale, 3 * scale]))

                // Cluster name is shown in the convergence panel and node popover;
                // the dashed region boundary is sufficient for canvas grouping.
            }

            for edge in graphEdges {
                let isHighlighted = selectedItemId != nil &&
                    (edge.sourceId == selectedItemId || edge.targetId == selectedItemId)
                let isCritical = criticalPathIds.contains(edge.sourceId) && criticalPathIds.contains(edge.targetId)
                drawEdge(context: &context, edge: edge, nodeMap: nodeMap, transform: transform, size: size, isHighlighted: isHighlighted, isCriticalPath: isCritical)
            }
        }
    }

    // MARK: - SwiftUI Node Layer (full mode)

    private var nodeLayer: some View {
        ZStack {
            // Transparent background for gesture capture on empty space
            Color.clear.contentShape(Rectangle())

            ForEach(nodes) { node in
                let isSelected = node.id == selectedItemId
                let isHovered = node.id == hoveredNodeId
                let isCritical = criticalPathIds.contains(node.id)
                let isLinkSource = isLinkMode && linkSourceId == node.id

                nodeCardView(for: node, isSelected: isSelected, isHovered: isHovered, isCritical: isCritical)
                    .frame(width: node.cardSize.width, height: node.cardSize.height)
                    .opacity(selectedItemId != nil && !isSelected && !isHovered ? 0.4 : 1.0)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .onHover { hovering in hoveredNodeId = hovering ? node.id : nil }
                    .scaleEffect(scale)
                    .position(transformedPosition(node.position))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor, lineWidth: 3)
                            .scaleEffect(scale)
                            .opacity(isLinkSource ? 1 : 0)
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !isMinimapMode, !isLinkMode else { return }
                                if !isDraggingNode {
                                    isDraggingNode = true
                                    dragStartPosition = node.position
                                }
                                if let idx = nodes.firstIndex(where: { $0.id == node.id }) {
                                    nodes[idx].position = CGPoint(
                                        x: dragStartPosition.x + value.translation.width / scale,
                                        y: dragStartPosition.y + value.translation.height / scale
                                    )
                                }
                            }
                            .onEnded { _ in
                                isDraggingNode = false
                            }
                    )
                    .onTapGesture {
                        if isLinkMode {
                            handleLinkTap(node.id)
                        } else {
                            onSelectItem(node.id)
                        }
                    }
            }
        }
    }

    /// Dispatches to the appropriate type-specific node card view.
    /// In storyboard mode, screen-spec cards switch between three semantic zoom levels.
    @ViewBuilder
    private func nodeCardView(for node: GraphNode, isSelected: Bool, isHovered: Bool, isCritical: Bool) -> some View {
        Group {
            if isStoryboardMode && node.isScreenSpec {
                switch zoomPhase {
                case .map:
                    MapModeScreenCard(node: node)
                case .storyboard:
                    StoryboardScreenCard(node: node)
                case .detail:
                    DetailModeScreenCard(node: node)
                }
            } else if node.spec.isEmpty {
                SkeletonNodeCard(node: node)
            } else {
                switch node.sectionType {
                case "screen-spec":  ScreenSpecNodeCard(node: node)
                case "data-model":   DataModelNodeCard(node: node)
                case "api-spec":     ApiSpecNodeCard(node: node)
                case "user-flow":    UserFlowNodeCard(node: node)
                default:             DefaultNodeCard(node: node)
                }
            }
        }
        .modifier(NodeCardChrome(node: node, isSelected: isSelected, isHovered: isHovered, isCritical: isCritical,
                                isStoryboardScreen: isStoryboardMode && node.isScreenSpec))
    }

    // MARK: - Storyboard Edge Canvas (navigates_to segues only)

    private var storyboardEdgeCanvas: some View {
        Canvas { context, size in
            let transform = CGAffineTransform(translationX: offset.width, y: offset.height)
                .scaledBy(x: scale, y: scale)
            let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

            if scale >= 0.5 {
                drawDotGrid(context: &context, size: size, transform: transform)
            }

            // Use layout tree (treeChildrenMap) for T-shaped connectors,
            // not graphEdges — because depth capping restructures parent-child relationships
            let nonTreeEdges = graphEdges.filter { $0.relationType != EdgeRelationType.navigatesTo }

            // Draw T-shaped tree connectors (parent → shared horizontal bar → children)
            for (parentId, childIds) in treeChildrenMap {
                let isHighlighted = selectedItemId == parentId || childIds.contains(where: { $0 == selectedItemId })
                drawTreeConnector(context: &context, parentId: parentId, childIds: childIds,
                                  nodeMap: nodeMap, transform: transform, isHighlighted: isHighlighted)
            }

            // Draw non-navigation edges individually
            for edge in nonTreeEdges {
                let isHighlighted = selectedItemId != nil &&
                    (edge.sourceId == selectedItemId || edge.targetId == selectedItemId)
                drawIndividualEdge(context: &context, edge: edge, nodeMap: nodeMap,
                                   transform: transform, isHighlighted: isHighlighted)
            }
        }
    }

    /// Total visual height of a node's VStack (card + badge tray).
    private func visualHeight(of node: GraphNode) -> CGFloat {
        let badgeTray = GraphNode.estimatedBadgeTrayHeight(
            subordinateCount: node.subordinates.count, cardWidth: node.cardSize.width)
        return node.cardSize.height + badgeTray
    }

    /// Y coordinate of the VStack bottom (below badge tray) for edge start points.
    /// Lines must exit below the entire node area (card + badges) to avoid overlapping badges.
    private func nodeBottomY(of node: GraphNode, center: CGPoint) -> CGFloat {
        let totalH = visualHeight(of: node)
        return center.y + totalH * scale / 2
    }

    /// Y coordinate of the card top edge within the VStack.
    private func cardTopY(of node: GraphNode, center: CGPoint) -> CGFloat {
        let totalH = visualHeight(of: node)
        return center.y - totalH * scale / 2
    }

    /// Draws a T-shaped tree connector: parent card bottom → vertical stem → shared horizontal bar → vertical drops to each child card top.
    private func drawTreeConnector(context: inout GraphicsContext, parentId: UUID, childIds: [UUID],
                                   nodeMap: [UUID: GraphNode], transform: CGAffineTransform,
                                   isHighlighted: Bool) {
        guard let parent = nodeMap[parentId] else { return }
        let parentCenter = parent.position.applying(transform)
        let parentBottom = CGPoint(x: parentCenter.x, y: nodeBottomY(of: parent, center: parentCenter))

        // Resolve child positions
        let children: [(center: CGPoint, topY: CGFloat)] = childIds.compactMap { id in
            guard let child = nodeMap[id] else { return nil }
            let center = child.position.applying(transform)
            let topY = cardTopY(of: child, center: center)
            return (center, topY)
        }
        guard !children.isEmpty else { return }

        let lineWidth: CGFloat = isHighlighted ? 2.0 * scale : 1.2 * scale
        let color: Color = isHighlighted ? Color.primary.opacity(0.5) : Color.primary.opacity(0.25)

        // midY: halfway between parent bottom and the top of the nearest child
        let minChildTopY = children.map(\.topY).min()!
        let midY = (parentBottom.y + minChildTopY) / 2

        var path = Path()

        // Vertical stem from parent bottom to midY
        path.move(to: parentBottom)
        path.addLine(to: CGPoint(x: parentBottom.x, y: midY))

        if children.count == 1 {
            // Single child: straight vertical line
            let child = children[0]
            path.addLine(to: CGPoint(x: child.center.x, y: midY))
            path.addLine(to: CGPoint(x: child.center.x, y: child.topY))
        } else {
            // Multiple children: horizontal bar spanning leftmost to rightmost child
            let sortedChildren = children.sorted { $0.center.x < $1.center.x }
            let leftX = sortedChildren.first!.center.x
            let rightX = sortedChildren.last!.center.x

            // Horizontal bar
            path.move(to: CGPoint(x: leftX, y: midY))
            path.addLine(to: CGPoint(x: rightX, y: midY))

            // Connect parent stem to the horizontal bar (already at midY, just ensure connection)
            path.move(to: CGPoint(x: parentBottom.x, y: midY))

            // Vertical drops from horizontal bar to each child
            for child in sortedChildren {
                path.move(to: CGPoint(x: child.center.x, y: midY))
                path.addLine(to: CGPoint(x: child.center.x, y: child.topY))
            }
        }

        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth))
    }

    /// Draws an individual orthogonal edge for non-navigation relationships.
    private func drawIndividualEdge(context: inout GraphicsContext, edge: GraphEdge,
                                    nodeMap: [UUID: GraphNode], transform: CGAffineTransform,
                                    isHighlighted: Bool) {
        guard let src = nodeMap[edge.sourceId], let tgt = nodeMap[edge.targetId] else { return }
        let srcCenter = src.position.applying(transform)
        let tgtCenter = tgt.position.applying(transform)

        let start = CGPoint(x: srcCenter.x, y: nodeBottomY(of: src, center: srcCenter))
        let end = CGPoint(x: tgtCenter.x, y: cardTopY(of: tgt, center: tgtCenter))
        let midY = (start.y + end.y) / 2

        var path = Path()
        path.move(to: start)
        path.addLine(to: CGPoint(x: start.x, y: midY))
        path.addLine(to: CGPoint(x: end.x, y: midY))
        path.addLine(to: end)

        let lineWidth: CGFloat = isHighlighted ? 2.0 * scale : 1.2 * scale
        let color: Color = isHighlighted ? Color.primary.opacity(0.5) : Color.primary.opacity(0.25)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth))

        // Show label for non-navigation edges
        if zoomPhase != .map, !edge.label.isEmpty {
            let mid = CGPoint(x: (start.x + end.x) / 2, y: midY)
            let labelText = Text(edge.label)
                .font(.system(size: 8 * scale, weight: .medium, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.5))
            let resolved = context.resolve(labelText)
            let labelSize = resolved.measure(in: CGSize(width: 200 * scale, height: 30 * scale))
            let bgRect = CGRect(x: mid.x - labelSize.width / 2 - 3 * scale,
                                y: mid.y - labelSize.height / 2 - 2 * scale,
                                width: labelSize.width + 6 * scale,
                                height: labelSize.height + 4 * scale)
            let bg = RoundedRectangle(cornerRadius: 3 * scale).path(in: bgRect)
            context.fill(bg, with: .color(.white.opacity(0.85)))
            context.draw(resolved, at: mid, anchor: .center)
        }
    }

    // MARK: - Storyboard Node Layer (screen-spec cards + subordinate badges)

    private var storyboardNodeLayer: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())

            // Cluster names are available in the node popover and convergence panel;
            // floating labels removed to avoid confusion with node cards.

            // Screen-spec cards with subordinate badge trays
            ForEach(nodes) { node in
                let isSelected = node.id == selectedItemId
                let isHovered = node.id == hoveredNodeId

                // Card anchored at node.position; badges hang below via overlay
                VStack(spacing: 6) {
                    nodeCardView(for: node, isSelected: isSelected, isHovered: isHovered, isCritical: false)
                        .frame(width: node.cardSize.width, height: node.cardSize.height)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelectItem(node.id) }

                    // Subordinate badges below the card (independently tappable)
                    if zoomPhase != .map && !node.subordinates.isEmpty {
                        SubordinateBadgeTray(
                            subordinates: node.subordinates,
                            selectedItemId: selectedItemId,
                            onSelect: onSelectItem
                        )
                        .frame(maxWidth: node.cardSize.width)
                    }
                }
                    .opacity(selectedItemId != nil && !isSelected && !isHovered ? 0.4 : 1.0)
                    .onHover { hovering in hoveredNodeId = hovering ? node.id : nil }
                    .scaleEffect(scale)
                    .position(transformedPosition(node.position))
            }

            // Technical orphan items are no longer rendered as canvas nodes.
            // They appear in the inspector panel when a connected primary node is selected.
        }
    }

    // MARK: - Minimap Canvas (retains full Canvas rendering)

    private var minimapCanvas: some View {
        Canvas { context, size in
            let transform = CGAffineTransform(translationX: offset.width, y: offset.height)
                .scaledBy(x: scale, y: scale)
            let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

            for edge in graphEdges {
                let isHighlighted = selectedItemId != nil &&
                    (edge.sourceId == selectedItemId || edge.targetId == selectedItemId)
                drawEdge(context: &context, edge: edge, nodeMap: nodeMap, transform: transform, size: size, isHighlighted: isHighlighted)
            }
            for node in nodes {
                let isSelected = node.id == selectedItemId
                let isCritical = criticalPathIds.contains(node.id)
                drawCardNode(context: &context, node: node, transform: transform, isHovered: hoveredNodeId == node.id, isSelected: isSelected, isCriticalPath: isCritical)
            }
        }
        .gesture(magnificationGesture.simultaneously(with: dragGesture))
        .overlay {
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): hoveredNodeId = nearestNode(to: location)?.id
                        case .ended: hoveredNodeId = nil
                        }
                    }
                    .onTapGesture { location in
                        if let nearest = nearestNode(to: location) { onSelectItem(nearest.id) }
                    }
            }
        }
    }

    // MARK: - Legend (Expanded: Sections + Relations + Status)

    private var legendOverlay: some View {
        let sectionTypes = uniqueSectionTypes
        return VStack(alignment: .leading, spacing: 8) {
            // Section types
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.design.legendSections)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(sectionTypes, id: \.type) { entry in
                    HStack(spacing: 5) {
                        Image(systemName: nodeIcon(for: entry.type))
                            .font(.system(size: 10))
                            .foregroundStyle(nodeColor(for: entry.type))
                        Text(entry.label).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }

            // Relation types
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.design.legendRelations)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                legendRelationRow(label: lang.design.relDependsOn, style: .solid, color: .primary.opacity(0.6), icon: "link")
                legendRelationRow(label: lang.design.relNavigatesTo, style: .dashed, color: .blue.opacity(0.6), icon: "arrow.right")
                legendRelationRow(label: lang.design.relUses, style: .dotted, color: .secondary.opacity(0.5), icon: "gearshape")
                legendRelationRow(label: lang.design.relRefines, style: .solid, color: .green.opacity(0.6), icon: "arrow.branch")
                legendRelationRow(label: lang.design.relReplaces, style: .dashed, color: .red.opacity(0.6), icon: "arrow.2.squarepath")
            }

            // Status
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.design.legendStatus)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                legendStatusRow(label: lang.design.statusCompleted, color: .green, icon: "checkmark.circle.fill")
                legendStatusRow(label: lang.design.statusInProgress, color: .blue, icon: "circle.dotted.circle")
                legendStatusRow(label: lang.design.statusPending, color: .secondary, icon: "circle.dashed")
                legendStatusRow(label: lang.design.statusNeedsRevision, color: .orange, icon: "exclamationmark.circle")
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(8)
    }

    private enum LegendLineStyle { case solid, dashed, dotted }

    private func legendRelationRow(label: String, style: LegendLineStyle, color: Color, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 10)
            }
            Canvas { ctx, size in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                let strokeStyle: StrokeStyle
                switch style {
                case .solid:  strokeStyle = StrokeStyle(lineWidth: 1.5)
                case .dashed: strokeStyle = StrokeStyle(lineWidth: 1.5, dash: [4, 2])
                case .dotted: strokeStyle = StrokeStyle(lineWidth: 1.5, dash: [1.5, 1.5])
                }
                ctx.stroke(path, with: .color(color), style: strokeStyle)
            }
            .frame(width: 14, height: 8)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func legendStatusRow(label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 10)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var fitButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                scale = 1.0
                lastScale = 1.0
                offset = .zero
                lastOffset = .zero
            }
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(6)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .help(lang.design.fitToView)
    }

    private var linkModeButton: some View {
        Button {
            isLinkMode.toggle()
            if !isLinkMode { linkSourceId = nil }
        } label: {
            Image(systemName: isLinkMode ? "xmark.circle.fill" : "link")
                .font(.system(size: 11))
                .foregroundStyle(isLinkMode ? .orange : .secondary)
                .padding(6)
                .background(isLinkMode ? Color.orange.opacity(0.15) : Color.clear)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(isLinkMode ? lang.design.cancelLink : lang.design.linkNodes)
        .onKeyPress(.escape) {
            if isLinkMode {
                isLinkMode = false
                linkSourceId = nil
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Convergence Overlay

    private var convergenceOverlay: some View {
        let rate = workflow.convergenceRate
        let confirmed = workflow.confirmedItemCount
        let active = workflow.activeItemCount
        let oscillating = workflow.oscillatingItemCount
        let ready = workflow.readyForCompletion

        return VStack(alignment: .trailing, spacing: 6) {
            // Compact convergence indicator
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showConvergenceDetail.toggle() }
            } label: {
                HStack(spacing: 6) {
                    // Circular progress
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 2.5)
                        Circle()
                            .trim(from: 0, to: CGFloat(rate))
                            .stroke(ready ? Color.green : Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        if ready {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(confirmed)/\(active)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(lang.design.statusCompleted)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    if oscillating > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(oscillating)")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // Expanded detail panel
            if showConvergenceDetail {
                convergenceDetailPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
    }

    private var convergenceDetailPanel: some View {
        let clusters = workflow.computeScenarioClusters(scenarioSuffix: lang.design.clusterScenarioSuffix, moreFormat: lang.design.clusterMoreFormat)
        let readiness = workflow.readinessSummary

        return VStack(alignment: .leading, spacing: 8) {
            // Per-cluster convergence
            if clusters.count > 1 {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lang.design.legendSections)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(clusters.prefix(5)) { cluster in
                        let confirmed = cluster.items.filter { $0.item.designVerdict == .confirmed }.count
                        let total = cluster.items.count
                        HStack(spacing: 4) {
                            Text(cluster.name)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .frame(maxWidth: 100, alignment: .leading)
                            Spacer()
                            Text("\(confirmed)/\(total)")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(confirmed == total ? .green : .secondary)
                        }
                    }
                }
            }

            // Oscillating items
            if workflow.hasOscillationWarning {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.orange)
                        Text(lang.design.statusNeedsRevision)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    let oscillatingItems = workflow.deliverables.flatMap(\.items)
                        .filter { $0.plannerVerdict != .rejected && $0.verdictFlipCount >= 2 }
                    ForEach(oscillatingItems.prefix(3), id: \.id) { item in
                        Text("• \(item.name)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            // Spec readiness
            HStack(spacing: 4) {
                Text(lang.design.readiness)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(readiness.percentage)%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(readiness.blockingCount > 0 ? .orange : .green)
            }
            if readiness.blockingCount > 0 {
                Text(lang.design.blockingCountFormat(readiness.blockingCount))
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .frame(width: 180)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Hover popover card showing item details and context.
    private func nodePopover(_ node: GraphNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: section + status
            HStack(spacing: 5) {
                Image(systemName: nodeIcon(for: node.sectionType))
                    .font(.system(size: 11))
                    .foregroundStyle(nodeColor(for: node.sectionType))
                Text(node.sectionLabel).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(statusLabel(node.status))
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(statusColor(node.status).opacity(0.15))
                    .foregroundStyle(statusColor(node.status))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Text(node.name).font(.caption.weight(.medium)).lineLimit(3)
            if let desc = node.briefDescription, !desc.isEmpty {
                Text(desc).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
            }

            // Context: cluster membership
            if let clusterName = node.clusterName {
                Divider()
                Text(clusterName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Context: downstream impact
            if node.downstreamImpact > 0 {
                let dependentEdges = workflow.edges.filter {
                    $0.targetId == node.id && $0.relationType == EdgeRelationType.dependsOn
                }
                let dependentNames = dependentEdges.prefix(3).compactMap { edge in
                    workflow.deliverables.flatMap(\.items).first { $0.id == edge.sourceId }?.name
                }
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Text(lang.design.nRelationsFormat(node.downstreamImpact))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
                if !dependentNames.isEmpty {
                    ForEach(dependentNames, id: \.self) { name in
                        Text("→ \(name)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            // Context: decision priority signals
            if node.uncertaintyCount > 0 || node.verdictFlipCount >= 2 {
                Divider()
                if node.verdictFlipCount >= 2 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.red)
                        Text(lang.design.statusNeedsRevision)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }
                if node.uncertaintyCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text("\(node.uncertaintyCount)")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(8)
        .frame(width: 220, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }

    private func statusLabel(_ status: DeliverableItemStatus) -> String {
        switch status {
        case .completed:     return lang.design.statusCompleted
        case .inProgress:    return lang.design.statusInProgress
        case .pending:       return lang.design.statusPending
        case .needsRevision: return lang.design.statusNeedsRevision
        }
    }

    private func statusColor(_ status: DeliverableItemStatus) -> Color {
        switch status {
        case .completed:     return .green
        case .inProgress:    return .blue
        case .pending:       return .secondary
        case .needsRevision: return .orange
        }
    }

    /// Localized label for relation types.
    private func relationLabel(for relationType: String) -> String {
        switch relationType {
        case EdgeRelationType.dependsOn:   return lang.design.relDependsOn
        case EdgeRelationType.navigatesTo: return lang.design.relNavigatesTo
        case EdgeRelationType.uses:        return lang.design.relUses
        case EdgeRelationType.refines:     return lang.design.relRefines
        case EdgeRelationType.replaces:    return lang.design.relReplaces
        default:                           return relationType
        }
    }

    private var uniqueSectionTypes: [(type: String, label: String)] {
        let visibleTypes = Set(nodes.map(\.sectionType))
        var seen = Set<String>()
        return workflow.deliverables.compactMap { section in
            guard visibleTypes.contains(section.type),
                  !seen.contains(section.type) else { return nil }
            seen.insert(section.type)
            return (section.type, section.label)
        }
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard !isMinimapMode else { return }
                scale = max(0.3, min(3.0, lastScale * value.magnification))
            }
            .onEnded { value in
                guard !isMinimapMode else { return }
                lastScale = max(0.3, min(3.0, lastScale * value.magnification))
                scale = lastScale
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isMinimapMode, !isDraggingNode else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { value in
                guard !isMinimapMode, !isDraggingNode else { return }
                lastOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = lastOffset
            }
    }

    // MARK: - Link Mode

    private func handleLinkTap(_ nodeId: UUID) {
        if let sourceId = linkSourceId {
            // Second tap — create edge
            if sourceId != nodeId {
                onAddEdge?(sourceId, nodeId, EdgeRelationType.dependsOn)
                // Rebuild edges for immediate visual feedback
                let newEdge = GraphEdge(
                    id: UUID(),
                    sourceId: sourceId,
                    targetId: nodeId,
                    relationType: EdgeRelationType.dependsOn
                )
                graphEdges.append(newEdge)
            }
            linkSourceId = nil
            isLinkMode = false
        } else {
            // First tap — set source
            linkSourceId = nodeId
        }
    }

    // MARK: - Transform

    private func transformedPosition(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * scale + offset.width,
            y: point.y * scale + offset.height
        )
    }

    /// Find the nearest node to a screen-space point (within hit area of card). Used for minimap mode.
    private func nearestNode(to point: CGPoint) -> GraphNode? {
        var closest: GraphNode?
        var closestDist: CGFloat = .greatestFiniteMagnitude
        for node in nodes {
            let scaledW = node.cardSize.width * scale / 2 + 8
            let scaledH = node.cardSize.height * scale / 2 + 8
            let pos = transformedPosition(node.position)
            let dx = abs(pos.x - point.x)
            let dy = abs(pos.y - point.y)
            // Rectangle hit test
            if dx < scaledW && dy < scaledH {
                let dist = sqrt(dx * dx + dy * dy)
                if dist < closestDist {
                    closestDist = dist
                    closest = node
                }
            }
        }
        return closest
    }

    // MARK: - Dot Grid Background

    /// Draws a Figma-style dot grid background for the infinite canvas feel.
    private func drawDotGrid(context: inout GraphicsContext, size: CGSize, transform: CGAffineTransform) {
        let gridSpacing: CGFloat = 20
        let dotRadius: CGFloat = 0.8
        let dotColor = Color.primary.opacity(0.06)

        // Calculate visible area in graph space
        let invScale = 1.0 / scale
        let startX = -offset.width * invScale
        let startY = -offset.height * invScale
        let endX = startX + size.width * invScale
        let endY = startY + size.height * invScale

        let gx0 = floor(startX / gridSpacing) * gridSpacing
        let gy0 = floor(startY / gridSpacing) * gridSpacing

        var x = gx0
        while x < endX {
            var y = gy0
            while y < endY {
                let screenPt = CGPoint(x: x, y: y).applying(transform)
                let r = CGRect(x: screenPt.x - dotRadius, y: screenPt.y - dotRadius,
                               width: dotRadius * 2, height: dotRadius * 2)
                context.fill(Ellipse().path(in: r), with: .color(dotColor))
                y += gridSpacing
            }
            x += gridSpacing
        }
    }

    // MARK: - Card Node Drawing

    /// Draws a card-style node: rounded rectangle with status accent bar, section icon, name, status chip.
    private func drawCardNode(context: inout GraphicsContext, node: GraphNode, transform: CGAffineTransform, isHovered: Bool, isSelected: Bool, isCriticalPath: Bool = false) {
        let center = node.position.applying(transform)
        let w = node.cardSize.width * scale
        let h = node.cardSize.height * scale
        let rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
        let cornerRadius = 8 * scale
        let sectionColor = nodeColor(for: node.sectionType)
        let stColor = statusColor(node.status)

        // --- Card background ---
        let cardPath = RoundedRectangle(cornerRadius: cornerRadius).path(in: rect)

        // Fill: section color tint at 8%, with verdict overlay
        let verdictTint: Color? = switch node.designVerdict {
        case .confirmed: Color.green.opacity(0.04)
        case .needsRevision: Color.orange.opacity(0.04)
        case .excluded: Color.secondary.opacity(0.04)
        case .pending: nil
        }
        context.fill(cardPath, with: .color(sectionColor.opacity(0.08)))
        if let verdictTint { context.fill(cardPath, with: .color(verdictTint)) }

        // Status-dependent border
        switch node.status {
        case .pending:
            // Dashed border for pending
            context.stroke(cardPath, with: .color(stColor.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 1.2 * scale, dash: [4 * scale, 3 * scale]))
        default:
            // Solid subtle border
            context.stroke(cardPath, with: .color(sectionColor.opacity(0.2)),
                           style: StrokeStyle(lineWidth: 0.8 * scale))
        }

        // --- Left accent bar (status color) ---
        let accentBarW = 4 * scale
        let barRect = CGRect(x: rect.minX, y: rect.minY + cornerRadius, width: accentBarW, height: rect.height - 2 * cornerRadius)
        let barPath = Rectangle().path(in: barRect)
        context.fill(barPath, with: .color(stColor))

        // --- Top row: section icon + sectionLabel ... status chip ---
        let topY = rect.minY + 4 * scale
        let leftX = rect.minX + accentBarW + 6 * scale
        let iconSize = max(6, 9 * scale)

        // Section icon
        let iconRect = CGRect(x: leftX, y: topY + 1 * scale, width: iconSize, height: iconSize)
        var iconCtx = context
        iconCtx.opacity = 0.7
        iconCtx.draw(Image(systemName: nodeIcon(for: node.sectionType)).resizable(), in: iconRect)

        // Section label text
        let labelFontSize = max(6, (isMinimapMode ? 7 : 9) * scale)
        let sectionText = Text(node.sectionLabel)
            .font(.system(size: labelFontSize, weight: .medium))
            .foregroundColor(sectionColor.opacity(0.8))
        context.draw(sectionText, at: CGPoint(x: leftX + iconSize + 3 * scale, y: topY + iconSize / 2 + 1 * scale), anchor: .leading)

        // Status chip (right-aligned)
        let chipFontSize = max(5, (isMinimapMode ? 6 : 8) * scale)
        let chipText: String
        let chipIcon: String?
        switch node.status {
        case .completed:     chipText = statusLabel(.completed); chipIcon = "checkmark"
        case .inProgress:    chipText = statusLabel(.inProgress); chipIcon = nil
        case .pending:       chipText = statusLabel(.pending); chipIcon = nil
        case .needsRevision: chipText = statusLabel(.needsRevision); chipIcon = "exclamationmark"
        }
        let statusText = Text(chipText)
            .font(.system(size: chipFontSize, weight: .medium))
            .foregroundColor(stColor)
        let chipX = rect.maxX - 6 * scale
        context.draw(statusText, at: CGPoint(x: chipX, y: topY + iconSize / 2 + 1 * scale), anchor: .trailing)

        // Status icon if applicable
        if let chipIcon {
            let chipIconSize = max(5, 7 * scale)
            let chipIconRect = CGRect(x: chipX - chipIconSize * 5.5, y: topY + 1 * scale, width: chipIconSize, height: chipIconSize)
            var chipCtx = context
            chipCtx.opacity = 0.8
            chipCtx.draw(Image(systemName: chipIcon).resizable(), in: chipIconRect)
        }

        // --- Bottom row: item name ---
        let nameY = topY + iconSize + 5 * scale
        let nameFontSize = max(7, (isMinimapMode ? 8 : 10.5) * scale)
        let nameWeight: Font.Weight = .semibold
        let maxNameWidth = w - accentBarW - 14 * scale
        let displayName: String
        // Estimate truncation: ~1 char per (fontSize * 0.6) points
        let approxCharsPerLine = max(4, Int(maxNameWidth / (nameFontSize * 0.55)))
        let maxChars = isMinimapMode ? approxCharsPerLine : approxCharsPerLine * 2
        if node.name.count > maxChars {
            displayName = String(node.name.prefix(maxChars - 1)) + "…"
        } else {
            displayName = node.name
        }
        let nameText = Text(displayName)
            .font(.system(size: nameFontSize, weight: nameWeight))
            .foregroundColor(.primary)
        context.draw(nameText, at: CGPoint(x: leftX, y: nameY), anchor: .topLeading)

        // --- Verdict badge (top-right corner) ---
        if node.designVerdict != .pending && !isMinimapMode {
            let badgeRadius = 5 * scale
            let badgeCenterX = rect.maxX - 8 * scale
            let badgeCenterY = rect.maxY - 10 * scale
            let badgeRect = CGRect(x: badgeCenterX - badgeRadius, y: badgeCenterY - badgeRadius,
                                   width: badgeRadius * 2, height: badgeRadius * 2)
            let badgePath = Circle().path(in: badgeRect)
            let badgeColor: Color = node.designVerdict == .confirmed ? .green : .orange
            context.fill(badgePath, with: .color(badgeColor))
            // Icon inside badge
            let iconSz = badgeRadius * 1.2
            let iconName = node.designVerdict == .confirmed ? "checkmark" : "pencil"
            let iconR = CGRect(x: badgeCenterX - iconSz / 2, y: badgeCenterY - iconSz / 2,
                               width: iconSz, height: iconSz)
            var badgeCtx = context
            badgeCtx.opacity = 1.0
            badgeCtx.draw(Image(systemName: iconName).resizable(), in: iconR, style: .init(antialiased: true))
        }

        // --- Selection / Hover highlights ---
        if isSelected {
            let selRect = rect.insetBy(dx: -3 * scale, dy: -3 * scale)
            let selPath = RoundedRectangle(cornerRadius: cornerRadius + 3 * scale).path(in: selRect)
            context.stroke(selPath, with: .color(sectionColor), lineWidth: 2.5 * scale)
            // Subtle shadow effect via wider, lower-opacity stroke
            let glowRect = rect.insetBy(dx: -6 * scale, dy: -6 * scale)
            let glowPath = RoundedRectangle(cornerRadius: cornerRadius + 6 * scale).path(in: glowRect)
            context.stroke(glowPath, with: .color(sectionColor.opacity(0.2)), lineWidth: 2 * scale)
        } else if isHovered {
            let hoverRect = rect.insetBy(dx: -2 * scale, dy: -2 * scale)
            let hoverPath = RoundedRectangle(cornerRadius: cornerRadius + 2 * scale).path(in: hoverRect)
            context.stroke(hoverPath, with: .color(sectionColor.opacity(0.5)), lineWidth: 1.5 * scale)
        }

        // Critical path glow (when not selected/hovered)
        if isCriticalPath && !isSelected && !isHovered {
            let critRect = rect.insetBy(dx: -4 * scale, dy: -4 * scale)
            let critPath = RoundedRectangle(cornerRadius: cornerRadius + 4 * scale).path(in: critRect)
            context.stroke(critPath, with: .color(Color.orange.opacity(0.4)), lineWidth: 1.5 * scale)
        }
    }

    // MARK: - Edge Drawing

    /// Compute the intersection point of a line from `center` to `targetPoint` with a rectangle of `size` centered at `center`.
    private func cardEdgePoint(center: CGPoint, size: CGSize, targetPoint: CGPoint) -> CGPoint {
        let halfW = size.width / 2
        let halfH = size.height / 2
        let dx = targetPoint.x - center.x
        let dy = targetPoint.y - center.y

        guard dx != 0 || dy != 0 else { return center }

        // Compute intersection with each edge and pick the closest valid one
        var t: CGFloat = .greatestFiniteMagnitude

        // Right edge (dx > 0)
        if dx > 0 {
            let tCandidate = halfW / dx
            let yAtEdge = dy * tCandidate
            if abs(yAtEdge) <= halfH { t = min(t, tCandidate) }
        }
        // Left edge (dx < 0)
        if dx < 0 {
            let tCandidate = -halfW / dx
            let yAtEdge = dy * tCandidate
            if abs(yAtEdge) <= halfH { t = min(t, tCandidate) }
        }
        // Bottom edge (dy > 0)
        if dy > 0 {
            let tCandidate = halfH / dy
            let xAtEdge = dx * tCandidate
            if abs(xAtEdge) <= halfW { t = min(t, tCandidate) }
        }
        // Top edge (dy < 0)
        if dy < 0 {
            let tCandidate = -halfH / dy
            let xAtEdge = dx * tCandidate
            if abs(xAtEdge) <= halfW { t = min(t, tCandidate) }
        }

        if t == .greatestFiniteMagnitude { return center }
        return CGPoint(x: center.x + dx * t, y: center.y + dy * t)
    }

    private func drawEdge(context: inout GraphicsContext, edge: GraphEdge, nodeMap: [UUID: GraphNode], transform: CGAffineTransform, size: CGSize, isHighlighted: Bool, isCriticalPath: Bool = false) {
        guard let srcNode = nodeMap[edge.sourceId],
              let tgtNode = nodeMap[edge.targetId] else { return }

        let src = srcNode.position.applying(transform)
        let tgt = tgtNode.position.applying(transform)

        // Per-node variable card sizes for edge connection points
        let srcSize = CGSize(width: srcNode.cardSize.width * scale, height: srcNode.cardSize.height * scale)
        let tgtSize = CGSize(width: tgtNode.cardSize.width * scale, height: tgtNode.cardSize.height * scale)
        let lineStart = cardEdgePoint(center: src, size: srcSize, targetPoint: tgt)
        let lineEnd = cardEdgePoint(center: tgt, size: tgtSize, targetPoint: src)

        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return }
        let nx = dx / dist
        let ny = dy / dist

        var (color, style, curveType, iconName) = edgeStyle(for: edge.relationType)

        // Boost opacity for edges connected to selected item
        if isHighlighted {
            color = color.opacity(1.0)
            style.lineWidth *= 1.5
        }
        // Critical path emphasis
        if isCriticalPath && !isHighlighted {
            color = Color.orange.opacity(0.7)
            style.lineWidth *= 1.3
        }

        // Draw edge path based on curve type
        var path = Path()
        path.move(to: lineStart)
        let midX = (lineStart.x + lineEnd.x) / 2
        let midY = (lineStart.y + lineEnd.y) / 2

        switch curveType {
        case .bezier:
            let ctrlOffset = max(dist * 0.35, 30 * scale)
            path.addCurve(
                to: lineEnd,
                control1: CGPoint(x: lineStart.x + nx * ctrlOffset, y: lineStart.y + ny * ctrlOffset - ctrlOffset * 0.3),
                control2: CGPoint(x: lineEnd.x - nx * ctrlOffset, y: lineEnd.y - ny * ctrlOffset - ctrlOffset * 0.3)
            )
        case .stepwise:
            // Right-angle step: horizontal then vertical
            let stepX = midX
            path.addLine(to: CGPoint(x: stepX, y: lineStart.y))
            path.addLine(to: CGPoint(x: stepX, y: lineEnd.y))
            path.addLine(to: lineEnd)
        case .straight:
            path.addLine(to: lineEnd)
        }
        context.stroke(path, with: .color(color), style: style)

        // Arrowhead for all relation types — smaller for auxiliary relations
        let arrowScale: CGFloat = (edge.relationType == EdgeRelationType.uses || edge.relationType == EdgeRelationType.refines) ? scale * 0.7 : scale
        drawArrowhead(context: &context, at: lineEnd, direction: CGPoint(x: nx, y: ny), color: color, scale: arrowScale)

        // Midpoint icon — visible at scale >= 0.5, not minimap
        if scale >= 0.5 && !isMinimapMode {
            let iconSize = max(8, 10 * scale)
            let iconText = Text(Image(systemName: iconName))
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(color)
            let bgSize = iconSize + 6 * scale
            let bgRect = CGRect(x: midX - bgSize / 2, y: midY - bgSize / 2, width: bgSize, height: bgSize)
            let bgPath = RoundedRectangle(cornerRadius: bgSize / 2).path(in: bgRect)
            context.fill(bgPath, with: .color(Color(.windowBackgroundColor).opacity(0.9)))
            context.stroke(bgPath, with: .color(color.opacity(0.3)), lineWidth: 0.5 * scale)
            context.draw(iconText, at: CGPoint(x: midX, y: midY), anchor: .center)
        }

        // Edge label — only for highlighted (selected node's) edges, not minimap
        if isHighlighted && !isMinimapMode {
            let labelText = relationLabel(for: edge.relationType)
            let fontSize = max(7, 9 * scale)
            let edgeLabelText = Text(labelText)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(color)

            // Draw label background pill — offset below midpoint icon
            let labelY = midY + 10 * scale
            let bgW = CGFloat(labelText.count) * fontSize * 0.65 + 8 * scale
            let bgH = fontSize + 6 * scale
            let bgRect = CGRect(x: midX - bgW / 2, y: labelY - bgH / 2, width: bgW, height: bgH)
            let bgPath = RoundedRectangle(cornerRadius: 3 * scale).path(in: bgRect)
            context.fill(bgPath, with: .color(Color(.windowBackgroundColor).opacity(0.85)))
            context.stroke(bgPath, with: .color(color.opacity(0.3)), lineWidth: 0.5 * scale)

            context.draw(edgeLabelText, at: CGPoint(x: midX, y: labelY), anchor: .center)
        }
    }

    private func drawArrowhead(context: inout GraphicsContext, at point: CGPoint, direction: CGPoint, color: Color, scale: CGFloat) {
        let arrowLength: CGFloat = 8 * scale
        let arrowWidth: CGFloat = 5 * scale

        let perpX = -direction.y
        let perpY = direction.x

        let tip = point
        let left = CGPoint(
            x: point.x - direction.x * arrowLength + perpX * arrowWidth,
            y: point.y - direction.y * arrowLength + perpY * arrowWidth
        )
        let right = CGPoint(
            x: point.x - direction.x * arrowLength - perpX * arrowWidth,
            y: point.y - direction.y * arrowLength - perpY * arrowWidth
        )

        var arrow = Path()
        arrow.move(to: tip)
        arrow.addLine(to: left)
        arrow.addLine(to: right)
        arrow.closeSubpath()

        context.fill(arrow, with: .color(color))
    }

    // MARK: - Styling

    private func nodeColor(for sectionType: String) -> Color { DeliverableSection.sectionColor(sectionType) }
    private func nodeIcon(for sectionType: String) -> String { DeliverableSection.sectionIcon(sectionType) }

    private func edgeStyle(for relationType: String) -> (Color, StrokeStyle, EdgeCurveType, String) {
        let w: CGFloat = 1.5 * scale
        switch relationType {
        case EdgeRelationType.dependsOn:
            return (.primary.opacity(0.6), StrokeStyle(lineWidth: w), .straight, "link")
        case EdgeRelationType.navigatesTo:
            return (.blue.opacity(0.5), StrokeStyle(lineWidth: w, dash: [6 * scale, 3 * scale]), .bezier, "arrow.right")
        case EdgeRelationType.uses:
            return (.secondary.opacity(0.4), StrokeStyle(lineWidth: w, dash: [2 * scale, 2 * scale]), .straight, "gearshape")
        case EdgeRelationType.refines:
            return (.green.opacity(0.5), StrokeStyle(lineWidth: w * 0.7), .stepwise, "arrow.branch")
        case EdgeRelationType.replaces:
            return (.red.opacity(0.5), StrokeStyle(lineWidth: w, dash: [4 * scale, 2 * scale]), .straight, "arrow.2.squarepath")
        default:
            return (.secondary.opacity(0.3), StrokeStyle(lineWidth: w), .straight, "link")
        }
    }

    // MARK: - Layout Scheduling

    /// Handle window resize by scaling existing positions proportionally (no full re-layout).
    private func handleResize(_ newSize: CGSize) {
        guard lastLayoutSize.width > 0, lastLayoutSize.height > 0, !nodes.isEmpty else {
            scheduleLayout(in: newSize, force: true)
            return
        }
        let sx = newSize.width / lastLayoutSize.width
        let sy = newSize.height / lastLayoutSize.height
        for i in nodes.indices {
            nodes[i].position.x *= sx
            nodes[i].position.y *= sy
        }
        lastLayoutSize = newSize
    }

    /// Debounced layout scheduling — avoids redundant recomputation on rapid changes.
    private func scheduleLayout(in size: CGSize, force: Bool = false) {
        layoutDebounceTask?.cancel()
        layoutDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            await computeLayout(in: size, force: force)
        }
    }

    // MARK: - Layout

    private func computeLayout(in size: CGSize, force: Bool = false) async {
        let hasScreenSpecs = workflow.deliverables.contains { $0.type == "screen-spec" && !$0.items.isEmpty }

        if hasScreenSpecs && !isMinimapMode {
            isStoryboardMode = true
            computeStoryboardLayout(in: size)
        } else {
            isStoryboardMode = false
            await computeGraphLayout(in: size, force: force)
        }
    }

    /// Graph layout — only screen-spec as primary canvas nodes;
    /// all other types (user-flow, data-model, api-spec) become subordinates.
    private func computeGraphLayout(in size: CGSize, force: Bool = false) async {
        let primaryTypes: Set<String> = ["screen-spec"]
        let technicalTypes: Set<String> = ["data-model", "api-spec", "user-flow"]

        // Partition items into primary (canvas nodes) and technical (subordinates)
        struct ItemEntry {
            let item: DeliverableItem; let sectionType: String; let sectionLabel: String
        }
        var primaryEntries: [ItemEntry] = []
        var technicalEntries: [ItemEntry] = []

        for section in workflow.deliverables {
            for item in section.items {
                let entry = ItemEntry(item: item, sectionType: section.type, sectionLabel: section.label)
                if primaryTypes.contains(section.type) {
                    primaryEntries.append(entry)
                } else if technicalTypes.contains(section.type) {
                    technicalEntries.append(entry)
                } else {
                    // Unknown types go to primary by default
                    primaryEntries.append(entry)
                }
            }
        }

        // If no primary items exist, fall back to showing all items
        if primaryEntries.isEmpty {
            primaryEntries = technicalEntries
            technicalEntries = []
        }

        let primaryIds = Set(primaryEntries.map(\.item.id))
        let techMap = Dictionary(uniqueKeysWithValues: technicalEntries.map { ($0.item.id, $0) })

        // Build subordinate map: primary → [SubordinateInfo] from edge connections
        var subordinateMap: [UUID: [SubordinateInfo]] = [:]
        var assignedTech: Set<UUID> = []

        for edge in workflow.edges {
            // primary → technical
            if primaryIds.contains(edge.sourceId), let tech = techMap[edge.targetId] {
                subordinateMap[edge.sourceId, default: []].append(
                    SubordinateInfo(id: tech.item.id, name: tech.item.name,
                                    sectionType: tech.sectionType, status: tech.item.status,
                                    relation: edge.relationType,
                                    businessLabel: SpecSummarizer.businessLabel(sectionType: tech.sectionType, spec: tech.item.spec)))
                assignedTech.insert(edge.targetId)
            }
            // technical → primary (reverse)
            if primaryIds.contains(edge.targetId), let tech = techMap[edge.sourceId] {
                subordinateMap[edge.targetId, default: []].append(
                    SubordinateInfo(id: tech.item.id, name: tech.item.name,
                                    sectionType: tech.sectionType, status: tech.item.status,
                                    relation: edge.relationType,
                                    businessLabel: SpecSummarizer.businessLabel(sectionType: tech.sectionType, spec: tech.item.spec)))
                assignedTech.insert(edge.sourceId)
            }
        }

        // Dedup: a tech item connected by multiple edges (e.g. bidirectional)
        // must appear at most once under each primary, otherwise SwiftUI ForEach
        // over SubordinateInfo by UUID logs "ID … occurs multiple times" warnings.
        for (key, list) in subordinateMap {
            var seen = Set<UUID>()
            subordinateMap[key] = list.filter { seen.insert($0.id).inserted }
        }

        // Unassigned technical items → attach to first primary (or skip)
        let unassigned = technicalEntries.filter { !assignedTech.contains($0.item.id) }
        if let firstPrimary = primaryEntries.first, !unassigned.isEmpty {
            for tech in unassigned {
                subordinateMap[firstPrimary.item.id, default: []].append(
                    SubordinateInfo(id: tech.item.id, name: tech.item.name,
                                    sectionType: tech.sectionType, status: tech.item.status,
                                    relation: "supports",
                                    businessLabel: SpecSummarizer.businessLabel(sectionType: tech.sectionType, spec: tech.item.spec)))
            }
        }

        // Pre-compute cluster name map for context display
        let clusters = workflow.computeScenarioClusters(scenarioSuffix: lang.design.clusterScenarioSuffix, moreFormat: lang.design.clusterMoreFormat)
        var clusterMap = [UUID: String]()
        for cluster in clusters where cluster.items.count >= 2 {
            for member in cluster.items { clusterMap[member.item.id] = cluster.name }
        }

        // Build GraphNodes for primaries
        let allItems: [GraphNode] = primaryEntries.map { entry in
            let itemId = entry.item.id
            var node = GraphNode(
                id: itemId, name: entry.item.name,
                sectionType: entry.sectionType, sectionLabel: entry.sectionLabel,
                status: entry.item.status,
                designVerdict: entry.item.designVerdict,
                briefDescription: entry.item.briefDescription,
                edgeCount: workflow.edges(for: itemId).count,
                spec: entry.item.spec,
                uncertaintyCount: workflow.pendingUncertainties(for: itemId).count,
                downstreamImpact: workflow.downstreamImpactCount(for: itemId),
                verdictFlipCount: entry.item.verdictFlipCount,
                clusterName: clusterMap[itemId],
                cardSize: GraphNode.cardSize(sectionType: entry.sectionType, spec: entry.item.spec, isMinimapMode: isMinimapMode),
                position: .zero
            )
            node.subordinates = subordinateMap[entry.item.id] ?? []
            return node
        }

        // Only include edges between primary nodes
        let edges = workflow.edges
            .filter { primaryIds.contains($0.sourceId) && primaryIds.contains($0.targetId) }
            .map { GraphEdge(id: $0.id, sourceId: $0.sourceId, targetId: $0.targetId, relationType: $0.relationType) }

        guard !allItems.isEmpty else { nodes = []; graphEdges = edges; return }

        let hasDependencies = edges.contains { $0.relationType == EdgeRelationType.dependsOn }
        let groups = hasDependencies ? workflow.computeParallelGroups() : [:]
        let positions: [CGPoint]
        if hasDependencies {
            positions = computeColumnLayout(items: allItems, groups: groups, in: size)
        } else {
            // Run expensive O(n² × iterations) force layout off the main thread
            let existingNodes = nodes
            let lastIC = lastLayoutItemCount
            let lastEC = lastLayoutEdgeCount
            positions = await Task.detached {
                Self.computeForceLayoutAsync(
                    items: allItems, edges: edges, in: size, force: force,
                    existingNodes: existingNodes, lastItemCount: lastIC, lastEdgeCount: lastEC
                )
            }.value
        }

        guard !Task.isCancelled else { return }
        nodes = zip(allItems, positions).map { var n = $0; n.position = $1; return n }
        graphEdges = edges
        lastLayoutItemCount = allItems.count
        lastLayoutEdgeCount = edges.count
        lastLayoutSize = size
        criticalPathIds = computeCriticalPath(groups: groups)
        clusterRegions = computeClusterRegions()
    }

    // MARK: - Storyboard Layout (Screen-Spec Centric)

    /// Positions screen-spec and user-flow as primary nodes in the main grid.
    /// data-model and api-spec become subordinates of connected primaries.
    private func computeStoryboardLayout(in size: CGSize) {
        // 1. Build item lookup for all deliverables
        struct ItemInfo {
            let id: UUID; let name: String; let sectionType: String; let sectionLabel: String
            let status: DeliverableItemStatus; let designVerdict: DesignVerdict
            let briefDescription: String?; let edgeCount: Int; let spec: [String: AnyCodable]
            let verdictFlipCount: Int
        }
        let primaryTypes: Set<String> = ["screen-spec"]
        var itemInfoMap: [UUID: ItemInfo] = [:]
        var primaryIds: [UUID] = []
        var screenIds: [UUID] = []
        var technicalIds: Set<UUID> = []

        for section in workflow.deliverables {
            for item in section.items {
                let info = ItemInfo(
                    id: item.id, name: item.name,
                    sectionType: section.type, sectionLabel: section.label,
                    status: item.status, designVerdict: item.designVerdict,
                    briefDescription: item.briefDescription,
                    edgeCount: workflow.edges(for: item.id).count, spec: item.spec,
                    verdictFlipCount: item.verdictFlipCount
                )
                itemInfoMap[info.id] = info
                if primaryTypes.contains(section.type) {
                    primaryIds.append(item.id)
                    if section.type == "screen-spec" { screenIds.append(item.id) }
                } else {
                    technicalIds.insert(item.id)
                }
            }
        }

        let primaryIdSet = Set(primaryIds)

        // 2. Build subordinate map: primaryId → [SubordinateInfo]
        var parentMap: [UUID: [SubordinateInfo]] = [:]
        var assignedTech: Set<UUID> = []

        for edge in workflow.edges {
            // primary → technical
            if primaryIdSet.contains(edge.sourceId) && technicalIds.contains(edge.targetId) {
                if let info = itemInfoMap[edge.targetId] {
                    parentMap[edge.sourceId, default: []].append(
                        SubordinateInfo(id: info.id, name: info.name, sectionType: info.sectionType,
                                        status: info.status, relation: edge.relationType,
                                        businessLabel: SpecSummarizer.businessLabel(sectionType: info.sectionType, spec: info.spec))
                    )
                    assignedTech.insert(edge.targetId)
                }
            }
            // technical → primary (reverse direction)
            if primaryIdSet.contains(edge.targetId) && technicalIds.contains(edge.sourceId) {
                if let info = itemInfoMap[edge.sourceId] {
                    parentMap[edge.targetId, default: []].append(
                        SubordinateInfo(id: info.id, name: info.name, sectionType: info.sectionType,
                                        status: info.status, relation: edge.relationType,
                                        businessLabel: SpecSummarizer.businessLabel(sectionType: info.sectionType, spec: info.spec))
                    )
                    assignedTech.insert(edge.sourceId)
                }
            }
        }

        // Dedup: same primary may be connected to the same technical via multiple
        // edges (e.g. bidirectional navigates_to). Keep first occurrence per primary.
        for (key, list) in parentMap {
            var seen = Set<UUID>()
            parentMap[key] = list.filter { seen.insert($0.id).inserted }
        }

        // Assign unconnected technical items to the first primary
        let unassignedTech = technicalIds.subtracting(assignedTech)
        if let firstPrimary = primaryIds.first, !unassignedTech.isEmpty {
            for techId in unassignedTech {
                if let info = itemInfoMap[techId] {
                    parentMap[firstPrimary, default: []].append(
                        SubordinateInfo(id: info.id, name: info.name, sectionType: info.sectionType,
                                        status: info.status, relation: "supports",
                                        businessLabel: SpecSummarizer.businessLabel(sectionType: info.sectionType, spec: info.spec))
                    )
                }
            }
        }

        // Pre-compute cluster name map
        let stClusters = workflow.computeScenarioClusters(scenarioSuffix: lang.design.clusterScenarioSuffix, moreFormat: lang.design.clusterMoreFormat)
        var stClusterMap = [UUID: String]()
        for cluster in stClusters where cluster.items.count >= 2 {
            for member in cluster.items { stClusterMap[member.item.id] = cluster.name }
        }

        // 3. Create primary GraphNodes with subordinates
        var primaryNodes: [GraphNode] = primaryIds.compactMap { id in
            guard let info = itemInfoMap[id] else { return nil }
            let isScreen = info.sectionType == "screen-spec"
            var node = GraphNode(
                id: info.id, name: info.name,
                sectionType: info.sectionType, sectionLabel: info.sectionLabel,
                status: info.status, designVerdict: info.designVerdict,
                briefDescription: info.briefDescription, edgeCount: info.edgeCount,
                spec: info.spec,
                uncertaintyCount: workflow.pendingUncertainties(for: info.id).count,
                downstreamImpact: workflow.downstreamImpactCount(for: info.id),
                verdictFlipCount: info.verdictFlipCount,
                clusterName: stClusterMap[info.id],
                cardSize: GraphNode.cardSize(sectionType: info.sectionType, spec: info.spec,
                                             isMinimapMode: false, isStoryboardMode: isScreen),
                position: .zero
            )
            node.subordinates = parentMap[id] ?? []
            return node
        }

        // 4. Build tree structure via navigates_to BFS (depth + children)
        let screenIdSet = Set(screenIds)
        let navEdges = workflow.edges.filter { $0.relationType == EdgeRelationType.navigatesTo
            && screenIdSet.contains($0.sourceId) && screenIdSet.contains($0.targetId) }
        let incomingScreens = Set(navEdges.map(\.targetId))
        let entryScreens = screenIds.filter { !incomingScreens.contains($0) }

        // BFS with depth and parent tracking — show actual navigation structure as-is
        var depthMap: [UUID: Int] = [:]
        var childrenMap: [UUID: [UUID]] = [:]
        var ordered: [UUID] = []
        var visited: Set<UUID> = []
        var bfsQueue = entryScreens.isEmpty ? [screenIds.first].compactMap { $0 } : entryScreens

        // Entry screens are depth 0
        for id in bfsQueue { depthMap[id] = 0 }

        while !bfsQueue.isEmpty {
            var nextQueue: [UUID] = []
            for id in bfsQueue where !visited.contains(id) {
                visited.insert(id)
                ordered.append(id)
                let parentDepth = depthMap[id] ?? 0
                let neighbors = navEdges.filter { $0.sourceId == id }.map(\.targetId)
                    .filter { !visited.contains($0) }
                for child in neighbors where depthMap[child] == nil {
                    depthMap[child] = parentDepth + 1
                    childrenMap[id, default: []].append(child)
                }
                nextQueue.append(contentsOf: neighbors)
            }
            bfsQueue = nextQueue
        }

        // Orphan screens (not reachable via navigation)
        var orphanScreens: [UUID] = []
        for id in screenIds where !visited.contains(id) {
            orphanScreens.append(id)
            ordered.append(id)
        }
        // Append user-flow nodes after screens
        for id in primaryIds where !screenIdSet.contains(id) { ordered.append(id) }

        // Reorder primaryNodes to match order
        let orderMap = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1, $0) })
        primaryNodes.sort { (orderMap[$0.id] ?? Int.max) < (orderMap[$1.id] ?? Int.max) }

        // 5. Position primaries in a top-down tree layout (variable card heights)
        let cardW: CGFloat = 195
        let horizontalGap: CGFloat = 140
        let verticalGap: CGFloat = 120
        let margin: CGFloat = 160
        let nodeMap = Dictionary(uniqueKeysWithValues: primaryNodes.enumerated().map { ($1.id, $0) })

        // Compute level-based max height for Y alignment (card + subordinate badge tray)
        var levelMaxHeight: [Int: CGFloat] = [:]
        for node in primaryNodes {
            let depth = depthMap[node.id] ?? 0
            let badgeTrayHeight = GraphNode.estimatedBadgeTrayHeight(
                subordinateCount: node.subordinates.count, cardWidth: node.cardSize.width)
            let totalHeight = node.cardSize.height + badgeTrayHeight
            levelMaxHeight[depth] = max(levelMaxHeight[depth] ?? 0, totalHeight)
        }
        // Also account for orphan screens (they have no depth entry yet)
        let defaultHeight: CGFloat = 120

        // Build cumulative Y positions per level
        let maxLevel = levelMaxHeight.keys.max() ?? 0
        var levelY: [Int: CGFloat] = [:]
        var curLevelY = margin
        for level in 0...max(maxLevel, 0) {
            let h = levelMaxHeight[level] ?? defaultHeight
            levelY[level] = curLevelY + h / 2
            curLevelY += h + verticalGap
        }

        // Recursive subtree width calculation (number of leaf descendants or 1 if leaf)
        func subtreeWidth(_ id: UUID) -> Int {
            let children = childrenMap[id] ?? []
            if children.isEmpty { return 1 }
            return children.reduce(0) { $0 + subtreeWidth($1) }
        }

        // Recursive tree positioning: assign X based on subtree span, Y from levelY
        func positionSubtree(_ id: UUID, centerX: CGFloat, depth: Int) {
            guard let idx = nodeMap[id] else { return }
            let y = levelY[depth] ?? (margin + CGFloat(depth) * 380)
            primaryNodes[idx].position = CGPoint(x: centerX, y: y)

            let children = childrenMap[id] ?? []
            guard !children.isEmpty else { return }

            let totalLeaves = children.reduce(0) { $0 + subtreeWidth($1) }
            let totalWidth = CGFloat(totalLeaves) * (cardW + horizontalGap) - horizontalGap
            var curX = centerX - totalWidth / 2

            for child in children {
                let childLeaves = subtreeWidth(child)
                let childWidth = CGFloat(childLeaves) * (cardW + horizontalGap) - horizontalGap
                let childCenterX = curX + childWidth / 2
                positionSubtree(child, centerX: childCenterX, depth: depth + 1)
                curX += childWidth + horizontalGap
            }
        }

        // Position each entry screen tree
        let entryIds = entryScreens.isEmpty ? [screenIds.first].compactMap { $0 } : entryScreens
        let treeTotalLeaves = entryIds.reduce(0) { $0 + subtreeWidth($1) }
        let treeTotalWidth = CGFloat(treeTotalLeaves) * (cardW + horizontalGap) - horizontalGap
        let treeStartX = margin + treeTotalWidth / 2

        if entryIds.count == 1 {
            positionSubtree(entryIds[0], centerX: treeStartX, depth: 0)
        } else {
            var curX = margin
            for entryId in entryIds {
                let leaves = subtreeWidth(entryId)
                let width = CGFloat(leaves) * (cardW + horizontalGap) - horizontalGap
                let centerX = curX + width / 2
                positionSubtree(entryId, centerX: centerX, depth: 0)
                curX += width + horizontalGap
            }
        }

        // Position orphan screens in a row below the deepest tree level
        if !orphanScreens.isEmpty {
            let orphanLevel = maxLevel + 1
            let orphanMaxH = orphanScreens.compactMap { id in nodeMap[id].map { primaryNodes[$0].cardSize.height } }.max() ?? defaultHeight
            let orphanY = curLevelY + orphanMaxH / 2
            for (i, orphanId) in orphanScreens.enumerated() {
                guard let idx = nodeMap[orphanId] else { continue }
                let x = margin + CGFloat(i) * (cardW + horizontalGap) + cardW / 2
                primaryNodes[idx].position = CGPoint(x: x, y: orphanY)
            }
            curLevelY += orphanMaxH + verticalGap
            _ = orphanLevel // suppress unused warning
        }

        // Position non-screen primary nodes (user-flows) in a row below orphans
        let nonScreenIds = primaryIds.filter { !screenIdSet.contains($0) }
        if !nonScreenIds.isEmpty {
            let flowMaxH = nonScreenIds.compactMap { id in nodeMap[id].map { primaryNodes[$0].cardSize.height } }.max() ?? defaultHeight
            let flowY = curLevelY + flowMaxH / 2
            for (i, flowId) in nonScreenIds.enumerated() {
                guard let idx = nodeMap[flowId] else { continue }
                let x = margin + CGFloat(i) * (cardW + horizontalGap) + cardW / 2
                primaryNodes[idx].position = CGPoint(x: x, y: flowY)
            }
        }

        // 6. Build edges between primary nodes only (navigates_to + other primary-to-primary edges)
        let segueEdges = workflow.edges
            .filter { primaryIdSet.contains($0.sourceId) && primaryIdSet.contains($0.targetId) }
            .map { GraphEdge(id: $0.id, sourceId: $0.sourceId, targetId: $0.targetId, relationType: $0.relationType) }

        nodes = primaryNodes
        graphEdges = segueEdges
        treeChildrenMap = childrenMap
        lastLayoutItemCount = primaryNodes.count
        lastLayoutEdgeCount = segueEdges.count
        lastLayoutSize = size
        criticalPathIds = []
        clusterRegions = computeClusterRegions()
    }

    // MARK: - Cluster Region Computation

    /// Compute bounding boxes for scenario clusters from positioned nodes.
    private func computeClusterRegions() -> [ClusterRegion] {
        let clusters = workflow.computeScenarioClusters(scenarioSuffix: lang.design.clusterScenarioSuffix, moreFormat: lang.design.clusterMoreFormat)
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let padding: CGFloat = 20

        return clusters.compactMap { cluster in
            guard cluster.items.count >= 2 else { return nil }
            let memberNodes = cluster.items.compactMap { nodeMap[$0.item.id] }
            guard memberNodes.count >= 2 else { return nil }

            let minX = memberNodes.map { $0.position.x - $0.cardSize.width / 2 }.min()! - padding
            let minY = memberNodes.map { $0.position.y - $0.cardSize.height / 2 }.min()! - padding
            let maxX = memberNodes.map { $0.position.x + $0.cardSize.width / 2 }.max()! + padding
            let maxY = memberNodes.map { $0.position.y + $0.cardSize.height / 2 }.max()! + padding

            // Color from the primary section type in the cluster
            let primaryType = cluster.items.first?.sectionType ?? "screen-spec"
            let color = DeliverableSection.sectionColor(primaryType)

            return ClusterRegion(
                id: cluster.id,
                name: cluster.name,
                rect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                color: color,
                itemCount: cluster.items.count
            )
        }
    }

    // MARK: - Column Layout (Dependency-Aware)

    /// Lays out nodes in columns based on parallelGroup (dependency depth).
    /// Left → right = group 0 → 1 → 2 → ... (work flows left to right).
    /// Spacing is enlarged to accommodate card-style nodes.
    private func computeColumnLayout(items: [GraphNode], groups: [UUID: Int], in size: CGSize) -> [CGPoint] {
        let margin: CGFloat = 80
        let horizontalGap: CGFloat = 60
        let verticalGap: CGFloat = 24

        // Group items by their parallel group, sorted by section type within each column
        var columns: [Int: [Int]] = [:]
        for (i, item) in items.enumerated() {
            let group = groups[item.id] ?? 0
            columns[group, default: []].append(i)
        }
        for (group, indices) in columns {
            columns[group] = indices.sorted { items[$0].sectionType < items[$1].sectionType }
        }

        let sortedGroups = columns.keys.sorted()
        let groupCount = max(sortedGroups.count, 1)

        // Compute max card width per column for horizontal spacing
        var columnMaxWidth: [CGFloat] = []
        for group in sortedGroups {
            let indices = columns[group] ?? []
            let maxW = indices.map { items[$0].cardSize.width }.max() ?? 180
            columnMaxWidth.append(maxW)
        }

        // Compute column X positions based on variable widths
        var columnX: [CGFloat] = []
        var curX = margin
        for (colIdx, maxW) in columnMaxWidth.enumerated() {
            if colIdx == 0 {
                columnX.append(curX + maxW / 2)
                curX += maxW + horizontalGap
            } else {
                columnX.append(curX + maxW / 2)
                curX += maxW + horizontalGap
            }
        }

        var positions = [CGPoint](repeating: .zero, count: items.count)

        for (colIdx, group) in sortedGroups.enumerated() {
            let indices = columns[group] ?? []
            let x = groupCount == 1 ? size.width / 2 : columnX[colIdx]

            // Compute total column height from variable card sizes
            let totalHeight = indices.enumerated().reduce(CGFloat(0)) { acc, pair in
                acc + items[pair.element].cardSize.height + (pair.offset < indices.count - 1 ? verticalGap : 0)
            }
            let startY = max(margin, (size.height - totalHeight) / 2)

            var curY = startY
            for itemIdx in indices {
                let h = items[itemIdx].cardSize.height
                positions[itemIdx] = CGPoint(x: x, y: curY + h / 2)
                curY += h + verticalGap
            }
        }
        return positions
    }

    // MARK: - Force-Directed Layout (Fruchterman-Reingold)

    /// Pure static version for background execution — no access to instance state.
    private nonisolated static func computeForceLayoutAsync(
        items: [GraphNode], edges: [GraphEdge], in size: CGSize, force: Bool,
        existingNodes: [GraphNode], lastItemCount: Int, lastEdgeCount: Int
    ) -> [CGPoint] {
        let itemCountChanged = items.count != lastItemCount
        let firstEdges = lastEdgeCount == 0 && !edges.isEmpty
        let isWarmRestart = !force && !itemCountChanged && !firstEdges && !existingNodes.isEmpty

        var positions: [CGPoint]
        if isWarmRestart {
            let existingPositions = Dictionary(uniqueKeysWithValues: existingNodes.map { ($0.id, $0.position) })
            positions = items.map { item in
                existingPositions[item.id] ?? CGPoint(x: size.width / 2, y: size.height / 2)
            }
        } else {
            positions = initializeClusteredPure(items: items, center: CGPoint(x: size.width / 2, y: size.height / 2), radius: min(size.width, size.height) * 0.35)
        }

        return runForceIterations(items: items, edges: edges, positions: &positions, size: size, isWarmRestart: isWarmRestart)
    }

    private func computeForceLayout(items: [GraphNode], edges: [GraphEdge], in size: CGSize, force: Bool) -> [CGPoint] {
        let itemCountChanged = items.count != lastLayoutItemCount
        let firstEdges = lastLayoutEdgeCount == 0 && !edges.isEmpty
        let isWarmRestart = !force && !itemCountChanged && !firstEdges && !nodes.isEmpty

        var positions: [CGPoint]
        if isWarmRestart {
            let existingPositions = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
            positions = items.map { item in
                existingPositions[item.id] ?? CGPoint(x: size.width / 2, y: size.height / 2)
            }
        } else {
            positions = initializeClustered(items: items, center: CGPoint(x: size.width / 2, y: size.height / 2), radius: min(size.width, size.height) * 0.35)
        }

        return Self.runForceIterations(items: items, edges: edges, positions: &positions, size: size, isWarmRestart: isWarmRestart)
    }

    /// Shared force iteration logic — pure computation, safe for background execution.
    private nonisolated static func runForceIterations(
        items: [GraphNode], edges: [GraphEdge],
        positions: inout [CGPoint], size: CGSize, isWarmRestart: Bool
    ) -> [CGPoint] {
        let k = sqrt(size.width * size.height / CGFloat(items.count)) * 1.8
        let iterations = isWarmRestart ? 30 : 120
        var temperature: CGFloat = isWarmRestart ? min(size.width, size.height) / 10 : min(size.width, size.height) / 3
        let cooling = temperature / CGFloat(iterations)
        let idToIndex = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, $0) })
        let margin: CGFloat = 80

        for _ in 0..<iterations {
            var displacements = [CGPoint](repeating: .zero, count: items.count)

            for i in 0..<items.count {
                for j in (i + 1)..<items.count {
                    let delta = CGPoint(x: positions[i].x - positions[j].x, y: positions[i].y - positions[j].y)
                    let dist = max(sqrt(delta.x * delta.x + delta.y * delta.y), 1)
                    let radiusI = hypot(items[i].cardSize.width, items[i].cardSize.height) / 2
                    let radiusJ = hypot(items[j].cardSize.width, items[j].cardSize.height) / 2
                    let minDist = radiusI + radiusJ + 20
                    let overlapForce = minDist > dist ? (minDist - dist) * 2 : 0
                    let force = k * k / dist + overlapForce
                    let normalized = CGPoint(x: delta.x / dist * force, y: delta.y / dist * force)
                    displacements[i].x += normalized.x
                    displacements[i].y += normalized.y
                    displacements[j].x -= normalized.x
                    displacements[j].y -= normalized.y
                }
            }

            for edge in edges {
                guard let si = idToIndex[edge.sourceId], let ti = idToIndex[edge.targetId] else { continue }
                let delta = CGPoint(x: positions[si].x - positions[ti].x, y: positions[si].y - positions[ti].y)
                let dist = max(sqrt(delta.x * delta.x + delta.y * delta.y), 1)
                let force = dist * dist / k
                let normalized = CGPoint(x: delta.x / dist * force, y: delta.y / dist * force)
                displacements[si].x -= normalized.x
                displacements[si].y -= normalized.y
                displacements[ti].x += normalized.x
                displacements[ti].y += normalized.y
            }

            for i in 0..<items.count {
                let disp = displacements[i]
                let dist = max(sqrt(disp.x * disp.x + disp.y * disp.y), 1)
                let cappedDist = min(dist, temperature)
                positions[i].x += disp.x / dist * cappedDist
                positions[i].y += disp.y / dist * cappedDist
                positions[i].x = max(margin, min(size.width - margin, positions[i].x))
                positions[i].y = max(margin, min(size.height - margin, positions[i].y))
            }
            temperature -= cooling
        }
        return positions
    }

    /// Pure static version of clustered initialization — no instance state access.
    private nonisolated static func initializeClusteredPure(items: [GraphNode], center: CGPoint, radius: CGFloat) -> [CGPoint] {
        var sectionOrder: [String] = []
        var sectionItems: [String: [Int]] = [:]
        for (i, item) in items.enumerated() {
            if sectionItems[item.sectionType] == nil {
                sectionOrder.append(item.sectionType)
            }
            sectionItems[item.sectionType, default: []].append(i)
        }

        var positions = [CGPoint](repeating: .zero, count: items.count)
        let sectionCount = sectionOrder.count
        let sectionArc = 2 * CGFloat.pi / CGFloat(max(sectionCount, 1))

        for (si, sType) in sectionOrder.enumerated() {
            let indices = sectionItems[sType] ?? []
            let sectionAngle = sectionArc * CGFloat(si) - .pi / 2
            for (ii, idx) in indices.enumerated() {
                let subAngle: CGFloat
                if indices.count == 1 {
                    subAngle = sectionAngle
                } else {
                    let spread = min(sectionArc * 0.7, .pi / 3)
                    subAngle = sectionAngle - spread / 2 + spread * CGFloat(ii) / CGFloat(indices.count - 1)
                }
                let itemRadius = radius + CGFloat(ii % 2) * radius * 0.15
                positions[idx] = CGPoint(
                    x: center.x + cos(subAngle) * itemRadius,
                    y: center.y + sin(subAngle) * itemRadius
                )
            }
        }
        return positions
    }

    /// Section-clustered initialization: group items by sectionType on the circle.
    private func initializeClustered(items: [GraphNode], center: CGPoint, radius: CGFloat) -> [CGPoint] {
        Self.initializeClusteredPure(items: items, center: center, radius: radius)
    }

    // MARK: - Critical Path

    /// Compute the longest dependency chain by backtracking from the deepest parallel group.
    private func computeCriticalPath(groups: [UUID: Int]) -> Set<UUID> {
        guard !groups.isEmpty else { return [] }

        let maxGroup = groups.values.max() ?? 0
        guard maxGroup > 0 else { return [] } // no chain if only one level

        // Build dependency map: source → [targets] (items that source depends on)
        // Edge semantics: sourceId depends_on targetId, so targetId is at a lower level
        var deps: [UUID: [UUID]] = [:]
        for edge in workflow.edges where edge.relationType == EdgeRelationType.dependsOn {
            deps[edge.sourceId, default: []].append(edge.targetId)
        }

        // Start from items in the deepest group, backtrack to their dependencies
        var path = Set<UUID>()
        var currentLevel = groups.filter { $0.value == maxGroup }.map(\.key)

        for level in stride(from: maxGroup, through: 0, by: -1) {
            for itemId in currentLevel {
                path.insert(itemId)
            }
            // Find dependencies at the previous level
            var nextLevel: [UUID] = []
            for itemId in currentLevel {
                for depId in deps[itemId] ?? [] {
                    if (groups[depId] ?? 0) == level - 1 {
                        nextLevel.append(depId)
                    }
                }
            }
            currentLevel = Array(Set(nextLevel)) // deduplicate
        }
        return path
    }
}

// MARK: - Graph Layout Models

/// Curve shape for edge rendering — differentiates relation types visually.
private enum EdgeCurveType { case straight, bezier, stepwise }

/// Cached bounding box for cluster visualization on the canvas.
struct ClusterRegion: Identifiable, Sendable {
    let id: UUID
    let name: String
    let rect: CGRect
    let color: Color
    let itemCount: Int
}

/// Semantic zoom phase: controls what level of detail each card shows.
enum ZoomPhase: Equatable {
    case map        // scale < 0.5 — lightweight colored rectangle + name only
    case storyboard // 0.5 ≤ scale ≤ 1.5 — iPhone frame with wireframe components
    case detail     // scale > 1.5 — iPhone frame + component attributes

    init(scale: CGFloat) {
        if scale < 0.5 { self = .map }
        else if scale > 1.5 { self = .detail }
        else { self = .storyboard }
    }
}

/// Lightweight info for non-screen items displayed as badges beneath their parent screen card.
struct SubordinateInfo: Identifiable, Sendable {
    let id: UUID
    let name: String
    let sectionType: String
    let status: DeliverableItemStatus
    let relation: String
    let businessLabel: String?
}

struct GraphNode: Identifiable, Equatable, @unchecked Sendable {
    let id: UUID
    let name: String
    let sectionType: String
    let sectionLabel: String
    let status: DeliverableItemStatus
    let designVerdict: DesignVerdict
    let briefDescription: String?
    let edgeCount: Int
    let spec: [String: AnyCodable]
    let uncertaintyCount: Int
    let downstreamImpact: Int
    let verdictFlipCount: Int
    let clusterName: String?
    var cardSize: CGSize
    var position: CGPoint
    var subordinates: [SubordinateInfo] = []

    var hasUncertainty: Bool { uncertaintyCount > 0 }
    var isScreenSpec: Bool { sectionType == "screen-spec" }

    static func == (lhs: GraphNode, rhs: GraphNode) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && lhs.designVerdict == rhs.designVerdict
            && lhs.position == rhs.position && lhs.cardSize == rhs.cardSize && lhs.name == rhs.name
            && lhs.subordinates.count == rhs.subordinates.count && lhs.uncertaintyCount == rhs.uncertaintyCount
            && lhs.downstreamImpact == rhs.downstreamImpact
    }

    /// Compute card size based on section type, spec availability, and layout mode.
    static func cardSize(sectionType: String, spec: [String: AnyCodable], isMinimapMode: Bool, isStoryboardMode: Bool = false) -> CGSize {
        if isMinimapMode {
            return sectionType == "screen-spec" ? CGSize(width: 45, height: 60) : CGSize(width: 80, height: 30)
        }
        if isStoryboardMode && sectionType == "screen-spec" {
            // Variable height based on component count (FlowMapp-style)
            let componentCount = (spec["components"]?.arrayValue as? [[String: Any]])?.count ?? 0
            let titleHeight: CGFloat = 24      // Screen name row
            let dividerHeight: CGFloat = 8     // Separator
            let rowHeight: CGFloat = 20        // Each component row
            let padding: CGFloat = 16          // Top + bottom padding
            let computed = titleHeight + dividerHeight + CGFloat(max(componentCount, 1)) * rowHeight + padding
            let height = max(computed, 120)    // Minimum 120
            return CGSize(width: 195, height: height)
        }
        guard !spec.isEmpty else { return CGSize(width: 180, height: 72) }
        switch sectionType {
        case "screen-spec":  return CGSize(width: 220, height: 90)
        case "data-model":   return CGSize(width: 220, height: 90)
        case "api-spec":     return CGSize(width: 220, height: 72)
        case "user-flow":    return CGSize(width: 200, height: 90)
        default:             return CGSize(width: 180, height: 72)
        }
    }

    /// Estimate subordinate badge tray height for layout spacing.
    /// Uses average badge width to approximate how many rows FlowLayout produces.
    static func estimatedBadgeTrayHeight(subordinateCount: Int, cardWidth: CGFloat) -> CGFloat {
        guard subordinateCount > 0 else { return 0 }
        let badgeHeight: CGFloat = 22   // graphDetail font + vertical padding
        let badgeAvgWidth: CGFloat = 90 // approximate average badge width
        let spacing: CGFloat = 4
        let trayWidth = max(cardWidth, 100)
        let badgesPerRow = max(1, Int(trayWidth / (badgeAvgWidth + spacing)))
        let rows = ceil(Double(subordinateCount) / Double(badgesPerRow))
        // 6pt gap between card and tray
        return 6 + CGFloat(rows) * badgeHeight + CGFloat(max(0, Int(rows) - 1)) * spacing
    }
}

struct GraphEdge: Identifiable, Sendable {
    let id: UUID
    let sourceId: UUID
    let targetId: UUID
    let relationType: String
    var label: String { relationType.replacingOccurrences(of: "_", with: " ") }
}
