import LAODomain
import LAORuntime
import LAOServices
import SwiftUI

struct AgentsTabView: View {
    let container: AppContainer
    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang
    @State private var agents: [Agent] = []
    @State private var showingNewAgent = false
    @State private var editingAgent: Agent?
    @State private var isRefreshingModels = false
    @State private var validationStatus = ""
    @State private var modelEntries: [ProviderKey: [ModelCatalogService.ModelEntry]] = [:]
    @State private var errorAlert: ErrorAlert?

    // New agent form state
    @State private var newName = ""
    @State private var newTier: AgentTier = .step
    @State private var newProvider: ProviderKey = .claude
    @State private var newModel = ""
    @State private var newSystemPrompt = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    if !agents.isEmpty {
                        Text(lang.agents.agentCountFormat(agents.count))
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(theme.foregroundTertiary)
                    }

                    Spacer()

                    Button {
                        Task { await refreshModels() }
                    } label: {
                        Label(lang.agents.refreshModels, systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .disabled(isRefreshingModels)

                    if isRefreshingModels {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(validationStatus.isEmpty ? lang.agents.fetching : validationStatus)
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(theme.foregroundTertiary)
                        }
                    }

                    Button {
                        resetForm()
                        showingNewAgent = true
                    } label: {
                        Label(lang.agents.addAgent, systemImage: "plus")
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }

                if agents.isEmpty {
                    SurfaceCard {
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.clock")
                                .font(AppTheme.Typography.pageTitle)
                                .foregroundStyle(theme.foregroundMuted)
                            Text(lang.agents.noAgentsTitle)
                                .font(AppTheme.Typography.heading)
                            Text(lang.agents.noAgentsDescription)
                                .font(AppTheme.Typography.label)
                                .foregroundStyle(theme.foregroundSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else {
                    ForEach(AgentTier.allCases) { tier in
                        let tierAgents = agents.filter { $0.tier == tier }
                        if !tierAgents.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(tier.displayName)
                                    .font(AppTheme.Typography.label.weight(.semibold))
                                    .foregroundStyle(theme.foregroundTertiary)
                                ForEach(tierAgents) { agent in
                                    agentCard(agent)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .laoWindowBackground()
        .task {
            await loadAgents()
            loadCachedModels()
        }
        .sheet(isPresented: $showingNewAgent, onDismiss: resetForm) {
            agentFormSheet(editing: nil)
        }
        .sheet(item: $editingAgent, onDismiss: resetForm) { agent in
            agentFormSheet(editing: agent)
        }
        .alert(
            errorAlert?.title ?? "",
            isPresented: Binding(
                get: { errorAlert != nil },
                set: { if !$0 { errorAlert = nil } }
            ),
            presenting: errorAlert
        ) { _ in
            Button(lang.common.confirm) { }
        } message: { item in
            Text(item.detail)
        }
    }

    // MARK: - Agent Card

    private func agentCard(_ agent: Agent) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(agent.name)
                            .font(AppTheme.Typography.heading)
                        Text(agentTierDescription(agent.tier))
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(theme.foregroundSecondary)
                            .lineLimit(1)
                    }
                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { agent.isEnabled },
                        set: { newValue in
                            Task { await toggleAgent(agent, enabled: newValue) }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()

                    Button {
                        newName = agent.name
                        newTier = agent.tier
                        newProvider = agent.provider
                        newModel = agent.model
                        newSystemPrompt = agent.systemPrompt
                        editingAgent = agent
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    Button {
                        Task { await deleteAgent(id: agent.id) }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(theme.criticalAccent)
                    }
                    .buttonStyle(.borderless)
                }

                HStack(spacing: 8) {
                    BadgeView(title: agent.tier.displayName, tone: tierStatusTone(agent.tier))
                    BadgeView(title: agent.provider.rawValue.capitalized, tone: .neutral)
                    BadgeView(title: agent.model, tone: .green)
                }

                if !agent.systemPrompt.isEmpty {
                    Text(agent.systemPrompt.prefix(100))
                        .font(AppTheme.Typography.detail)
                        .foregroundStyle(theme.foregroundTertiary)
                        .lineLimit(1)
                }
            }
        }
        .opacity(agent.isEnabled ? 1.0 : 0.5)
    }

    // MARK: - Form Sheet

    private func agentFormSheet(editing agent: Agent?) -> some View {
        AgentFormSheetContent(
            agent: agent,
            newName: $newName,
            newTier: $newTier,
            newProvider: $newProvider,
            newModel: $newModel,
            newSystemPrompt: $newSystemPrompt,
            modelCatalog: container.modelCatalog,
            onCancel: {
                showingNewAgent = false
                editingAgent = nil
            },
            onSave: {
                Task {
                    if let agent {
                        await updateAgent(agent)
                    } else {
                        await createAgent()
                    }
                }
            }
        )
    }

    // MARK: - Model Catalog

    private func availableModels(for provider: ProviderKey) -> [ModelCatalogService.ModelEntry] {
        container.modelCatalog.models(for: provider)
    }

    private func loadCachedModels() {
        for provider in ProviderKey.allCases {
            modelEntries[provider] = container.modelCatalog.models(for: provider)
        }
    }

    private func refreshModels() async {
        isRefreshingModels = true
        validationStatus = lang.agents.fetchingCatalog
        defer {
            isRefreshingModels = false
            validationStatus = ""
        }

        container.modelCatalog.onValidationProgress = { provider, current, total in
            Task { @MainActor in
                validationStatus = lang.agents.validatingFormat(provider, current, total)
            }
        }

        await container.modelCatalog.refresh()

        container.modelCatalog.onValidationProgress = nil
        loadCachedModels()
    }

    // MARK: - Form Helpers

    private func resetForm() {
        newName = ""
        newTier = .step
        newProvider = .claude
        newModel = availableModels(for: .claude).first?.name ?? "opus"
        newSystemPrompt = ""
    }

    // MARK: - CRUD

    private func loadAgents() async {
        agents = await container.agentService.listAgents()
    }

    private func createAgent() async {
        let fallbackModel = availableModels(for: newProvider).first?.name ?? ""
        let agent = Agent(
            name: newName.trimmingCharacters(in: .whitespaces),
            tier: newTier,
            provider: newProvider,
            model: newModel.isEmpty ? fallbackModel : newModel,
            systemPrompt: newSystemPrompt
        )
        do {
            let created = try await container.agentService.createAgent(agent)
            agents.append(created)
            showingNewAgent = false
        } catch {
            errorAlert = ErrorAlert(title: lang.agents.createFailed, detail: error.localizedDescription)
        }
    }

    private func updateAgent(_ original: Agent) async {
        var updated = original
        updated.name = newName.trimmingCharacters(in: .whitespaces)
        updated.tier = newTier
        updated.provider = newProvider
        updated.model = newModel
        updated.systemPrompt = newSystemPrompt
        do {
            try await container.agentService.updateAgent(updated)
            if let idx = agents.firstIndex(where: { $0.id == original.id }) {
                agents[idx] = updated
            }
            editingAgent = nil
        } catch {
            errorAlert = ErrorAlert(title: lang.agents.updateFailed, detail: error.localizedDescription)
        }
    }

    private func deleteAgent(id: UUID) async {
        do {
            try await container.agentService.deleteAgent(id: id)
            agents.removeAll(where: { $0.id == id })
        } catch {
            errorAlert = ErrorAlert(title: lang.agents.deleteFailed, detail: error.localizedDescription)
        }
    }

    private func toggleAgent(_ agent: Agent, enabled: Bool) async {
        var updated = agent
        updated.isEnabled = enabled
        do {
            try await container.agentService.updateAgent(updated)
            if let idx = agents.firstIndex(where: { $0.id == agent.id }) {
                agents[idx] = updated
            }
        } catch {
            // Revert the toggle so UI matches actual DB state on failure.
            if let idx = agents.firstIndex(where: { $0.id == agent.id }) {
                agents[idx].isEnabled = !enabled
            }
            errorAlert = ErrorAlert(title: lang.agents.updateFailed, detail: error.localizedDescription)
        }
    }

    private func tierStatusTone(_ tier: AgentTier) -> StatusTone {
        switch tier {
        case .director: .blue
        case .directorFallback: .neutral
        case .step: .green
        }
    }

    private func agentTierDescription(_ tier: AgentTier) -> String {
        switch tier {
        case .director: lang.agents.designTierDesc
        case .directorFallback: lang.agents.fallbackTierDesc
        case .step: lang.agents.stepTierDesc
        }
    }
}

// MARK: - Agent Form (extracted so Model Picker re-evaluates when Provider changes)

private struct AgentFormSheetContent: View {
    let agent: Agent?
    @Binding var newName: String
    @Binding var newTier: AgentTier
    @Binding var newProvider: ProviderKey
    @Binding var newModel: String
    @Binding var newSystemPrompt: String
    let modelCatalog: ModelCatalogService
    let onCancel: () -> Void
    let onSave: () -> Void

    /// Models for the currently selected provider, re-computed on every body evaluation.
    private var models: [ModelCatalogService.ModelEntry] {
        let catalog = modelCatalog.models(for: newProvider)
        if !newModel.isEmpty, !catalog.contains(where: { $0.name == newModel }) {
            return [ModelCatalogService.ModelEntry(name: newModel, supportsReasoning: false)] + catalog
        }
        return catalog
    }

    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: agent != nil ? "pencil.circle.fill" : "person.badge.plus")
                    .font(AppTheme.Typography.sectionTitle)
                    .foregroundStyle(theme.accentPrimary)
                Text(agent != nil ? lang.agents.editAgent : lang.agents.newAgent)
                    .font(AppTheme.Typography.cardTitle.weight(.bold))
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField(lang.common.name, text: $newName)
                    .textFieldStyle(.roundedBorder)

                Picker(lang.agents.tier, selection: $newTier) {
                    ForEach(AgentTier.allCases) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }

                Picker(lang.agents.provider, selection: $newProvider) {
                    ForEach(ProviderKey.allCases) { provider in
                        Text(provider.rawValue.capitalized).tag(provider)
                    }
                }
                .onChange(of: newProvider) { _, newVal in
                    let providerModels = modelCatalog.models(for: newVal)
                    if !providerModels.contains(where: { $0.name == newModel }) {
                        newModel = providerModels.first?.name ?? ""
                    }
                }

                Picker(lang.agents.model, selection: $newModel) {
                    if newModel.isEmpty {
                        Text(lang.agents.selectModel).tag("")
                    }
                    ForEach(models, id: \.name) { entry in
                        Text(entry.name).tag(entry.name)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(lang.agents.instruction)
                        .font(AppTheme.Typography.label.weight(.medium))
                    Text(lang.agents.instructionDescription)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundSecondary)
                    TextField(lang.agents.instructionPlaceholder,
                              text: $newSystemPrompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
            }

            HStack {
                Button(lang.common.cancel) { onCancel() }
                    .buttonStyle(SecondaryActionButtonStyle())

                Button(agent != nil ? lang.common.save : lang.common.create) { onSave() }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: AppTheme.SheetWidth.standard)
    }
}
