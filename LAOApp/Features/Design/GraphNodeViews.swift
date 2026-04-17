import SwiftUI
import LAODomain

// MARK: - Node Card Chrome (Shared ViewModifier)

/// Wraps any node card content with consistent chrome: rounded background, left accent bar,
/// selection/hover border, and verdict badge.
struct NodeCardChrome: ViewModifier {
    let node: GraphNode
    let isSelected: Bool
    let isHovered: Bool
    let isCritical: Bool
    var isStoryboardScreen: Bool = false
    @Environment(\.theme) private var theme

    private var sectionColor: Color { DeliverableSection.sectionColor(node.sectionType) }

    private var statusColor: Color {
        switch node.status {
        case .completed:     return .green
        case .inProgress:    return .blue
        case .pending:       return .secondary
        case .needsRevision: return .orange
        }
    }

    func body(content: Content) -> some View {
        content
            .padding(.leading, isStoryboardScreen ? 0 : 6)
            .padding(isStoryboardScreen ? 0 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isStoryboardScreen ? .center : .topLeading)
            .background {
                if isStoryboardScreen {
                    // Opaque background so edge lines behind the card don't show through
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.windowBackgroundColor))
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(isSelected ? 0.06 : 0.02))
                        if node.designVerdict == .confirmed {
                            RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.04))
                        } else if node.designVerdict == .needsRevision {
                            RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.04))
                        }
                    }
                } else {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(sectionColor.opacity(isSelected ? 0.15 : 0.08))
                        // Verdict tint overlay
                        if node.designVerdict == .confirmed {
                            RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.04))
                        } else if node.designVerdict == .needsRevision {
                            RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.04))
                        }
                        // Left accent bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(statusColor)
                            .frame(width: 4)
                            .padding(.vertical, 8)
                    }
                }
            }
            .overlay {
                if isStoryboardScreen {
                    // Thin neutral border for storyboard thumbnail cards
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(isSelected ? 0.3 : 0.15), lineWidth: isSelected ? 0 : 0.8)
                } else if node.status == .pending {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(statusColor.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(sectionColor.opacity(0.2), lineWidth: 0.8)
                }
            }
            // Clip content before selection overlay so the border isn't clipped
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                // Downstream impact glow ring — visual weight for high-impact nodes
                if !isSelected && !isHovered && node.downstreamImpact >= 1 {
                    let (ringWidth, ringOpacity): (CGFloat, Double) = node.downstreamImpact >= 5
                        ? (3, 0.4) : node.downstreamImpact >= 3 ? (2, 0.25) : (1.2, 0.12)
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(Color.orange.opacity(ringOpacity), lineWidth: ringWidth)
                        .padding(-5)
                }
            }
            .overlay {
                // Selection / hover highlight (outside clip so stroke is visible)
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(sectionColor, lineWidth: 2.5)
                        .padding(-3)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(sectionColor.opacity(0.5), lineWidth: 1.5)
                        .padding(-2)
                } else if isCritical {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1.5)
                        .padding(-4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if node.designVerdict != .pending {
                    verdictBadge.padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if node.uncertaintyCount > 0 {
                    let isBlocking = node.verdictFlipCount >= 2
                    let badgeColor: Color = isBlocking ? .red : .orange
                    let iconName = isBlocking ? "exclamationmark" : "questionmark"
                    ZStack {
                        Circle().fill(badgeColor).frame(width: 14, height: 14)
                        Image(systemName: iconName)
                            .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                    }
                    .overlay(alignment: .topTrailing) {
                        if node.uncertaintyCount >= 2 {
                            Text("\(node.uncertaintyCount)")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 2)
                                .background(Capsule().fill(badgeColor))
                                .offset(x: 4, y: -4)
                        }
                    }
                    .padding(4)
                }
            }
    }

    @ViewBuilder private var verdictBadge: some View {
        let badgeColor: Color = node.designVerdict == .confirmed ? .green : .orange
        let iconName = node.designVerdict == .confirmed ? "checkmark" : "pencil"
        ZStack {
            Circle().fill(badgeColor).frame(width: 14, height: 14)
            Image(systemName: iconName).font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
        }
    }
}

// MARK: - Node Card Header (shared top row)

/// Reusable header row: section icon + label ... status chip
struct NodeCardHeader: View {
    let sectionType: String
    let sectionLabel: String
    let status: DeliverableItemStatus
    @Environment(\.lang) private var lang

    private var sectionColor: Color { DeliverableSection.sectionColor(sectionType) }
    private var sectionIcon: String { DeliverableSection.sectionIcon(sectionType) }

    private var statusLabel: String {
        switch status {
        case .completed: lang.design.statusCompleted
        case .inProgress: lang.design.statusInProgress
        case .pending: lang.design.statusPending
        case .needsRevision: lang.design.statusNeedsRevision
        }
    }

    private var statusColor: Color {
        switch status {
        case .completed: .green
        case .inProgress: .blue
        case .pending: .secondary
        case .needsRevision: .orange
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: sectionIcon).font(AppTheme.Typography.graphCaption).foregroundStyle(sectionColor)
            Text(sectionLabel).font(.system(size: 10, weight: .medium)).foregroundStyle(sectionColor.opacity(0.8))
            Spacer()
            Text(statusLabel).font(AppTheme.Typography.graphDetail).foregroundStyle(statusColor)
            if status == .completed {
                Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(statusColor)
            }
        }
    }
}

// MARK: - Skeleton Node Card (spec empty, 180×72)

struct SkeletonNodeCard: View {
    let node: GraphNode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NodeCardHeader(sectionType: node.sectionType, sectionLabel: node.sectionLabel, status: node.status)
            Text(node.name).font(.system(size: 11, weight: .semibold)).lineLimit(2)
            if let desc = node.briefDescription, !desc.isEmpty {
                Text(desc).font(AppTheme.Typography.graphDetail).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Screen Spec Node Card (220×90)

struct ScreenSpecNodeCard: View {
    let node: GraphNode

    private var componentCount: Int {
        node.spec["components"]?.arrayValue?.count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NodeCardHeader(sectionType: node.sectionType, sectionLabel: node.sectionLabel, status: node.status)
            Text(node.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)

            if let purpose = node.screenPurposeText {
                Text(purpose).font(AppTheme.Typography.graphCaption).foregroundStyle(.secondary).lineLimit(2)
            }

            HStack(spacing: 8) {
                if componentCount > 0 {
                    Label("\(componentCount)", systemImage: "rectangle.3.group")
                        .font(AppTheme.Typography.graphDetail).foregroundStyle(.tertiary)
                }
                let stateNames = SpecSummarizer.stateNames(node.spec)
                if !stateNames.isEmpty {
                    Label(stateNames, systemImage: "arrow.triangle.branch")
                        .font(AppTheme.Typography.graphDetail).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Screen Card Shared Helpers

/// Shared computed properties for screen-spec node rendering.
/// Used by StoryboardScreenCard, DetailModeScreenCard, and MapModeScreenCard.
extension GraphNode {
    /// Raw components array from spec.
    var screenComponents: [[String: Any]] {
        (spec["components"]?.arrayValue as? [[String: Any]]) ?? []
    }

    /// Components excluding nav/tab bars — the "content" area.
    var screenContentComponents: [[String: Any]] {
        screenComponents.filter { comp in
            let type = ((comp["type"] as? String) ?? "").lowercased()
            return !type.contains("navigationbar") && !type.contains("navbar")
                && !type.contains("tabbar") && !type.contains("tabview")
        }
    }

    /// Purpose text from spec or briefDescription fallback.
    var screenPurposeText: String? {
        if let p = spec["purpose"]?.stringValue, !p.isEmpty { return p }
        if let d = briefDescription, !d.isEmpty { return d }
        return nil
    }

    /// Maps lowercased component names to their interaction action descriptions.
    var screenInteractionMap: [String: String] {
        guard let interactions = spec["interactions"]?.arrayValue as? [[String: Any]] else { return [:] }
        var map: [String: String] = [:]
        for inter in interactions {
            guard let trigger = inter["trigger"] as? String,
                  let action = inter["action"] as? String else { continue }
            let triggerLower = trigger.lowercased()
            for comp in screenComponents {
                if let name = comp["name"] as? String,
                   triggerLower.contains(name.lowercased()) {
                    map[name.lowercased()] = action
                }
            }
        }
        return map
    }

    /// Navigation bar title extracted from NavigationBar component or falls back to node name.
    var screenNavBarTitle: String {
        for comp in screenComponents {
            let type = ((comp["type"] as? String) ?? "").lowercased()
            if type.contains("navigationbar") || type.contains("navbar") {
                if let title = comp["title"] as? String { return title }
                if let children = comp["children"] as? [[String: Any]] {
                    for child in children {
                        let cType = ((child["type"] as? String) ?? "").lowercased()
                        if cType.contains("title") || cType.contains("text") {
                            if let name = child["name"] as? String { return name }
                        }
                    }
                }
            }
        }
        return name
    }

    /// Whether the screen has a tab bar component.
    var screenHasTabBar: Bool {
        screenComponents.contains { comp in
            let type = ((comp["type"] as? String) ?? "").lowercased()
            return type.contains("tabbar") || type.contains("tabview")
        }
    }

    /// Tab bar item names (up to 5).
    var screenTabBarItems: [String] {
        for comp in screenComponents {
            let type = ((comp["type"] as? String) ?? "").lowercased()
            if type.contains("tabbar") || type.contains("tabview") {
                if let children = comp["children"] as? [[String: Any]] {
                    return children.prefix(5).compactMap { $0["name"] as? String }
                }
                if let items = comp["items"] as? [String] {
                    return Array(items.prefix(5))
                }
            }
        }
        return []
    }
}

/// Shared static helpers for screen card UI rendering.
enum ScreenCardHelper {
    /// Semantic color for UI state names (normal, loading, error, empty, disabled, etc.).
    static func stateColor(_ state: String) -> Color {
        let s = state.lowercased()
        if s.contains("normal") || s.contains("default") || s.contains("success") { return .green }
        if s.contains("loading") || s.contains("progress") || s.contains("fetching") { return .blue }
        if s.contains("error") || s.contains("fail") || s.contains("invalid") { return .red }
        if s.contains("empty") || s.contains("no_data") || s.contains("placeholder") { return .gray }
        if s.contains("disabled") || s.contains("locked") { return .orange }
        return .secondary
    }

    /// SF Symbol for a component type.
    static func componentIcon(for type: String) -> String? {
        if type.contains("textfield") || type.contains("search") { return "magnifyingglass" }
        if type.contains("securefield") { return "lock" }
        if type.contains("button") { return "hand.tap" }
        if type.contains("image") { return "photo" }
        if type.contains("map") { return "map" }
        if type.contains("list") || type.contains("scroll") { return "list.bullet" }
        if type.contains("form") { return "doc.plaintext" }
        return nil
    }

    /// Background fill color for a component type.
    static func componentFill(for type: String) -> Color {
        if type.contains("button") { return Color.blue.opacity(0.06) }
        if type.contains("textfield") || type.contains("securefield") || type.contains("search") { return Color.primary.opacity(0.05) }
        if type.contains("image") || type.contains("map") { return Color.purple.opacity(0.04) }
        return Color.primary.opacity(0.03)
    }

    /// Default tab bar icon for a given index.
    static func tabIcon(for index: Int) -> String {
        let icons = ["house.fill", "magnifyingglass", "plus.circle", "bell", "person"]
        return icons[index % icons.count]
    }
}

// MARK: - Wireframe Block (component type → geometric shape)

/// Renders a single UI component as a wireframe geometric shape (sized for 195×260 card thumbnail).
struct WireframeBlock: View {
    let componentType: String

    var body: some View {
        Group {
            switch classifyType(componentType) {
            case .textField:
                // Rounded rect with placeholder line
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: 28)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.18))
                            .frame(width: 50, height: 5)
                            .padding(.leading, 10)
                    }

            case .button:
                // Centered pill shape, blue tint
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.15))
                    .frame(height: 28)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)

            case .list:
                // 3 rows (thumbnail square + line)
                VStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.12))
                                .frame(width: 16, height: 10)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.10))
                                .frame(height: 5)
                        }
                    }
                }

            case .image:
                // Rect with diagonal cross and mountain icon
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.purple.opacity(0.08))
                    .frame(height: 50)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.primary.opacity(0.15))
                    }

            case .card:
                // Rounded rect with inner lines
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 36)
                    .overlay(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.15))
                                .frame(width: 60, height: 5)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.10))
                                .frame(width: 80, height: 4)
                        }
                        .padding(.leading, 10)
                    }

            case .form:
                // Label + field pairs
                VStack(spacing: 5) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.15))
                                .frame(width: 36, height: 5)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 16)
                        }
                    }
                }

            case .label:
                // Placeholder text line
                HStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 70, height: 6)
                    Spacer()
                }

            case .generic:
                // Default: simple rounded rect
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 24)
            }
        }
    }

    // MARK: - Type Classification

    private enum BlockKind {
        case textField, button, list, image, card, form, label, generic
    }

    private func classifyType(_ raw: String) -> BlockKind {
        let t = raw.lowercased()
        if t.contains("textfield") || t.contains("searchbar") || t.contains("search") || t.contains("securefield") { return .textField }
        if t.contains("button") { return .button }
        if t.contains("list") || t.contains("scroll") || t.contains("table") { return .list }
        if t.contains("image") || t.contains("map") || t.contains("photo") { return .image }
        if t.contains("card") { return .card }
        if t.contains("form") { return .form }
        if t.contains("label") || t.contains("text") { return .label }
        return .generic
    }
}

// MARK: - Storyboard Screen Card (195×260, visual sitemap thumbnail)

/// Renders a screen-spec as a VisualSitemaps-style thumbnail card.
/// Title is rendered OUTSIDE (below) by storyboardNodeLayer; this view is the thumbnail only.
struct StoryboardScreenCard: View {
    let node: GraphNode
    @Environment(\.lang) private var lang

    var body: some View {
        if node.spec.isEmpty {
            skeletonThumbnail
        } else {
            componentListView
        }
    }

    // MARK: - Skeleton (no spec yet)
    private var skeletonThumbnail: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)
            Text(lang.design.pending)
                .font(AppTheme.Typography.graphLabel)
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Component List (FlowMapp-style: name + type for each component)
    private var componentListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Screen name at top (FlowMapp pattern)
            Text(node.name)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(2)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Divider().padding(.horizontal, 8)

            // All components listed by name
            let comps = node.screenComponents
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(comps.enumerated()), id: \.offset) { _, comp in
                    let type = ((comp["type"] as? String) ?? "").lowercased()
                    let name = (comp["name"] as? String) ?? (comp["type"] as? String) ?? "Component"
                    let icon = ScreenCardHelper.componentIcon(for: type) ?? "square"
                    HStack(spacing: 5) {
                        Image(systemName: icon)
                            .font(AppTheme.Typography.graphDetail)
                            .foregroundStyle(.tertiary)
                            .frame(width: 14)
                        Text(name)
                            .font(AppTheme.Typography.graphLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(height: 20)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Map Mode Screen Card (semantic zoom: scale < 0.5)

/// Lightweight colored card showing only name + status. Used when zoomed out
/// so the storyboard flow and segue arrows are the focus.
struct MapModeScreenCard: View {
    let node: GraphNode
    @Environment(\.lang) private var lang

    private var statusColor: Color {
        switch node.status {
        case .completed:     return .green
        case .inProgress:    return .blue
        case .pending:       return .secondary
        case .needsRevision: return .orange
        }
    }

    private var statusLabel: String {
        switch node.status {
        case .completed:     return lang.design.statusCompleted
        case .inProgress:    return lang.design.statusInProgress
        case .pending:       return lang.design.statusPending
        case .needsRevision: return lang.design.statusNeedsRevision
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "iphone")
                .font(.system(size: 24))
                .foregroundStyle(statusColor.opacity(0.6))
            Text(node.name)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            // Purpose line — visible even when zoomed out
            if let purpose = node.spec["purpose"]?.stringValue ?? node.briefDescription, !purpose.isEmpty {
                Text(purpose)
                    .font(AppTheme.Typography.graphLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 4) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusLabel).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if node.designVerdict == .confirmed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.green)
            } else if node.designVerdict == .needsRevision {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Detail Mode Screen Card (semantic zoom: scale > 1.5)

/// When zoomed in, reuses StoryboardScreenCard. Detail inspection happens in the inspector panel.
struct DetailModeScreenCard: View {
    let node: GraphNode

    var body: some View {
        StoryboardScreenCard(node: node)
    }
}

// MARK: - Data Model Node Card (220×90)

struct DataModelNodeCard: View {
    let node: GraphNode

    private var fieldCount: Int { node.spec["fields"]?.arrayValue?.count ?? 0 }
    private var relCount: Int { node.spec["relationships"]?.arrayValue?.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NodeCardHeader(sectionType: node.sectionType, sectionLabel: node.sectionLabel, status: node.status)
            Text(node.name).font(.system(size: 12, weight: .bold))
                .foregroundStyle(DeliverableSection.sectionColor(node.sectionType)).lineLimit(1)

            let summary = SpecSummarizer.dataModelSummary(node.spec)
            if !summary.isEmpty {
                Text(summary).font(AppTheme.Typography.graphCaption).foregroundStyle(.secondary).lineLimit(2)
            }

            HStack(spacing: 8) {
                if fieldCount > 0 {
                    Label("\(fieldCount)", systemImage: "list.bullet")
                        .font(AppTheme.Typography.graphDetail).foregroundStyle(.tertiary)
                }
                if relCount > 0 {
                    Label("\(relCount)", systemImage: "arrow.triangle.branch")
                        .font(AppTheme.Typography.graphDetail).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - API Spec Node Card (240×72)

struct ApiSpecNodeCard: View {
    let node: GraphNode

    private var method: String { node.spec["method"]?.stringValue ?? "GET" }
    private var path: String { node.spec["path"]?.stringValue ?? node.spec["endpoint"]?.stringValue ?? "/?" }
    private var desc: String? { node.spec["description"]?.stringValue ?? node.briefDescription }

    private var methodColor: Color {
        switch method.uppercased() {
        case "GET":    return .blue
        case "POST":   return .green
        case "PUT":    return .orange
        case "PATCH":  return .orange
        case "DELETE": return .red
        default:       return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: DeliverableSection.sectionIcon("api-spec"))
                    .font(AppTheme.Typography.graphLabel)
                    .foregroundStyle(DeliverableSection.sectionColor("api-spec"))
                // Prefer human-readable description over method+path
                if let d = desc, !d.isEmpty {
                    Text(d).font(.system(size: 11, weight: .medium)).lineLimit(1)
                } else {
                    Text(node.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                }
                Spacer()
                if node.status == .completed {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.green)
                }
            }
            // Show method+path as a secondary hint
            HStack(spacing: 4) {
                Text(method.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(methodColor.opacity(0.12))
                    .foregroundStyle(methodColor)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                Text(path).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - User Flow Node Card (200×90)

struct UserFlowNodeCard: View {
    @Environment(\.lang) private var lang
    let node: GraphNode

    private var trigger: String? { node.spec["trigger"]?.stringValue }
    private var stepCount: Int { node.spec["steps"]?.arrayValue?.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NodeCardHeader(sectionType: node.sectionType, sectionLabel: node.sectionLabel, status: node.status)
            Text(node.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)

            if let trigger {
                HStack(spacing: 3) {
                    Image(systemName: "play.fill").font(.system(size: 8)).foregroundStyle(.green)
                    Text(trigger).font(AppTheme.Typography.graphDetail).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            if stepCount > 0 {
                Label(lang.design.stepsCountLabel(stepCount), systemImage: "arrow.right.circle")
                    .font(AppTheme.Typography.graphDetail).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Default Node Card (180×72, component and unknown types)

struct DefaultNodeCard: View {
    let node: GraphNode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NodeCardHeader(sectionType: node.sectionType, sectionLabel: node.sectionLabel, status: node.status)
            Text(node.name).font(.system(size: 11, weight: .semibold)).lineLimit(2)
            if let desc = node.briefDescription, !desc.isEmpty {
                Text(desc).font(AppTheme.Typography.graphDetail).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Subordinate Badge (small capsule for non-screen items under a screen card)

struct SubordinateBadgeView: View {
    let info: SubordinateInfo
    let isSelected: Bool
    let onSelect: (UUID) -> Void

    private var sectionColor: Color { DeliverableSection.sectionColor(info.sectionType) }
    private var sectionIcon: String { DeliverableSection.sectionIcon(info.sectionType) }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: sectionIcon)
                .font(AppTheme.Typography.graphDetail)
                .foregroundStyle(sectionColor)
            Text(info.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(1)
            if info.status == .completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(sectionColor.opacity(isSelected ? 0.2 : 0.08))
        .clipShape(Capsule())
        .overlay {
            if isSelected {
                Capsule().stroke(sectionColor, lineWidth: 1.5)
            }
        }
        .onTapGesture { onSelect(info.id) }
    }
}

// MARK: - Subordinate Badge Tray (flow layout beneath a screen card)

struct SubordinateBadgeTray: View {
    let subordinates: [SubordinateInfo]
    let selectedItemId: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(subordinates) { sub in
                SubordinateBadgeView(
                    info: sub,
                    isSelected: sub.id == selectedItemId,
                    onSelect: onSelect
                )
            }
        }
    }
}

// FlowLayout is defined in SharedUI/FlowLayout.swift and reused here.
