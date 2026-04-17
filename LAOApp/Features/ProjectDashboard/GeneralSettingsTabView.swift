import LAODomain
import LAOServices
import SwiftUI

struct GeneralSettingsTabView: View {
    let container: AppContainer
    var onClose: (() -> Void)? = nil
    @Environment(\.theme) private var theme
    @Environment(\.lang) private var lang
    @State private var selectedLanguage: AppLanguage = .en
    @State private var selectedDestination: SettingsDestination? = .profile
    @State private var quickAgents: [Agent] = []
    @State private var profile = UserProfile()
    @State private var nameText = ""
    @State private var titleText = ""
    @State private var bioText = ""
    @State private var settings = AppSettings()
    @State private var timeoutText = "600"
    @State private var idleTimeoutText = "300"
    @State private var concurrencyText = "5"
    @State private var isSaving = false
    @State private var showSaved = false
    @State private var isSavingProfile = false
    @State private var showProfileSaved = false
    @State private var isResetting = false
    @State private var showResetConfirm = false
    @State private var showResetDone = false

    private enum SettingsDestination: String, CaseIterable, Identifiable {
        case profile
        case general
        case agents

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .profile: return "person.crop.circle"
            case .general: return "gearshape"
            case .agents: return "person.2"
            }
        }
    }

    private func destinationTitle(_ dest: SettingsDestination) -> String {
        switch dest {
        case .profile: return lang.settings.profile
        case .general: return lang.settings.general
        case .agents: return lang.settings.agentsTab
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            VStack(spacing: 0) {
                contentHeader
                currentSectionView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .laoWindowBackground()
        .accessibilityIdentifier("settings-view")
        .task {
            profile = await container.userProfileService.getProfile()
            nameText = profile.name
            titleText = profile.title
            bioText = profile.bio
            quickAgents = await container.agentService.listAgents()

            settings = await container.appSettingsService.getSettings()
            timeoutText = String(settings.cliTimeoutSeconds)
            idleTimeoutText = String(settings.cliIdleTimeoutSeconds)
            concurrencyText = String(settings.elaborationConcurrency)
            selectedLanguage = AppLanguage(rawValue: settings.language) ?? .en
        }
    }

    private var settingsSidebar: some View {
        List(selection: $selectedDestination) {
            Section(lang.settings.advancedSection) {
                ForEach([SettingsDestination.profile, .general, .agents]) { dest in
                    Label(destinationTitle(dest), systemImage: dest.icon)
                        .tag(dest)
                        .accessibilityIdentifier("settings-nav-\(destinationIdentifier(dest))")
                }
            }
        }
        .listStyle(.sidebar)
        .frame(width: 220)
        .accessibilityIdentifier("settings-sidebar")
    }

    private func destinationIdentifier(_ destination: SettingsDestination) -> String {
        switch destination {
        case .profile: return "profile"
        case .general: return "general"
        case .agents: return "agents"
        }
    }

    private var contentHeader: some View {
        HStack(spacing: 12) {
            Text(destinationTitle(selectedDestination ?? .profile))
                .font(AppTheme.Typography.sectionTitle.weight(.semibold))

            Spacer()

            settingsPrimaryAction

            if let onClose {
                Button(lang.common.close) {
                    onClose()
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var currentSectionView: some View {
        switch selectedDestination ?? .profile {
        case .profile:
            profileTab
        case .general:
            generalTab
        case .agents:
            AgentsTabView(container: container)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var profileTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                profileSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                languageSection
                runtimeSection
                resetSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private var languageSection: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(lang.settings.languageTitle)
                    .font(AppTheme.Typography.label.weight(.semibold))

                Text(lang.settings.languageDescription)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(theme.foregroundSecondary)

                Picker(lang.settings.languageTitle, selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedLanguage) { _, newValue in
                    settings.language = newValue.rawValue
                    UserDefaults.standard.set(newValue.rawValue, forKey: AppLanguage.userDefaultsKey)
                    Task {
                        try? await container.appSettingsService.updateSettings(settings)
                    }
                    NotificationCenter.default.post(name: .laoLanguageChanged, object: newValue.rawValue)
                }
            }
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(lang.settings.aboutYou)
                        .font(AppTheme.Typography.label.weight(.semibold))

                    Text(lang.settings.profileDescription)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundSecondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(lang.common.name)
                            .font(AppTheme.Typography.caption.weight(.medium))
                            .foregroundStyle(theme.foregroundTertiary)
                        TextField(lang.settings.namePlaceholder, text: $nameText)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(lang.common.title_)
                            .font(AppTheme.Typography.caption.weight(.medium))
                            .foregroundStyle(theme.foregroundTertiary)
                        TextField(lang.settings.titlePlaceholder, text: $titleText)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(lang.common.bio)
                            .font(AppTheme.Typography.caption.weight(.medium))
                            .foregroundStyle(theme.foregroundTertiary)
                        TextField(lang.settings.bioPlaceholder, text: $bioText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(4...8)
                    }
                }
            }
        }
    }


    // MARK: - Runtime

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(lang.settings.cliMaxRuntime)
                        .font(AppTheme.Typography.label.weight(.semibold))

                    Text(lang.settings.cliMaxRuntimeDescription)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundSecondary)

                    timeoutInputRow
                    timeoutWarning
                }
            }

            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(lang.settings.cliIdleTimeout)
                        .font(AppTheme.Typography.label.weight(.semibold))

                    Text(lang.settings.cliIdleTimeoutDescription)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundSecondary)

                    idleTimeoutInputRow
                    idleTimeoutWarning
                }
            }

            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(lang.settings.elaborationConcurrency)
                        .font(AppTheme.Typography.label.weight(.semibold))

                    Text(lang.settings.elaborationConcurrencyDescription)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundSecondary)

                    concurrencyInputRow
                    concurrencyWarning
                }
            }
        }
    }

    private var concurrencyInputRow: some View {
        HStack(spacing: 12) {
            TextField("1–10", text: $concurrencyText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .onChange(of: concurrencyText) { _, newValue in
                    let filtered = newValue.filter(\.isNumber)
                    if filtered != newValue {
                        Task { @MainActor in concurrencyText = filtered }
                    }
                }

            Text(lang.settings.elaborationConcurrencyUnit)
                .font(AppTheme.Typography.label)
                .foregroundStyle(theme.foregroundTertiary)

            Spacer()

            concurrencyPresetButton(3)
            concurrencyPresetButton(5)
            concurrencyPresetButton(8)
        }
    }

    private func concurrencyPresetButton(_ value: Int) -> some View {
        Button("\(value)") {
            concurrencyText = String(value)
        }
        .buttonStyle(SecondaryActionButtonStyle())
        .controlSize(.small)
        .opacity(Int(concurrencyText) == value ? 1.0 : 0.6)
    }

    @ViewBuilder
    private var concurrencyWarning: some View {
        if let value = Int(concurrencyText), value > 5 {
            Text(lang.settings.elaborationConcurrencyWarning)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(theme.warningAccent)
        }
    }

    private var timeoutInputRow: some View {
        HStack(spacing: 12) {
            TextField(lang.settings.seconds, text: $timeoutText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .onChange(of: timeoutText) { _, newValue in
                    let filtered = newValue.filter(\.isNumber)
                    if filtered != newValue {
                        Task { @MainActor in timeoutText = filtered }
                    }
                }

            Text(lang.settings.secondsUnit)
                .font(AppTheme.Typography.label)
                .foregroundStyle(theme.foregroundTertiary)

            Spacer()

            presetButton(300)
            presetButton(600)
            presetButton(900)
        }
    }

    private func presetButton(_ value: Int) -> some View {
        Button("\(value)s") {
            timeoutText = String(value)
        }
        .buttonStyle(SecondaryActionButtonStyle())
        .controlSize(.small)
        .opacity(Int(timeoutText) == value ? 1.0 : 0.6)
    }

    @ViewBuilder
    private var timeoutWarning: some View {
        if let seconds = Int(timeoutText), seconds < 30 {
            Text(lang.settings.minRuntimeWarning)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(theme.criticalAccent)
        } else if let seconds = Int(timeoutText), seconds < 180 {
            Text(lang.settings.streamInterruptWarning)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(theme.warningAccent)
        }
    }

    private var idleTimeoutInputRow: some View {
        HStack(spacing: 12) {
            TextField(lang.settings.seconds, text: $idleTimeoutText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .onChange(of: idleTimeoutText) { _, newValue in
                    let filtered = newValue.filter(\.isNumber)
                    if filtered != newValue {
                        Task { @MainActor in idleTimeoutText = filtered }
                    }
                }

            Text(lang.settings.secondsUnit)
                .font(AppTheme.Typography.label)
                .foregroundStyle(theme.foregroundTertiary)

            Spacer()

            idlePresetButton(120)
            idlePresetButton(300)
            idlePresetButton(600)
        }
    }

    private func idlePresetButton(_ value: Int) -> some View {
        Button("\(value)s") {
            idleTimeoutText = String(value)
        }
        .buttonStyle(SecondaryActionButtonStyle())
        .controlSize(.small)
        .opacity(Int(idleTimeoutText) == value ? 1.0 : 0.6)
    }

    @ViewBuilder
    private var idleTimeoutWarning: some View {
        if let seconds = Int(idleTimeoutText), seconds < 30 {
            Text(lang.settings.minIdleTimeoutWarning)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(theme.criticalAccent)
        } else if let seconds = Int(idleTimeoutText), seconds < 60 {
            Text(lang.settings.shortIdleWarning)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(theme.warningAccent)
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(lang.settings.resetAgents)
                        .font(AppTheme.Typography.label.weight(.semibold))

                    Text(lang.settings.resetAgentsDescription)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundSecondary)

                    HStack {
                        Button(lang.common.reset) {
                            showResetConfirm = true
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .disabled(isResetting)

                        if isResetting {
                            ProgressView()
                                .controlSize(.small)
                        }

                        if showResetDone {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(theme.positiveAccent)
                                Text(lang.settings.resetComplete)
                                    .font(AppTheme.Typography.label)
                                    .foregroundStyle(theme.foregroundTertiary)
                            }
                        }

                        Spacer()
                    }
                }
            }
        }
        .alert(lang.settings.resetAgents, isPresented: $showResetConfirm) {
            Button(lang.common.cancel, role: .cancel) {}
            Button(lang.common.reset, role: .destructive) {
                Task { await resetAgents() }
            }
        } message: {
            Text(lang.settings.resetConfirmMessage)
        }
    }

    private func resetAgents() async {
        isResetting = true
        defer { isResetting = false }

        // Delete all existing agents
        let agents = await container.agentService.listAgents()
        for agent in agents {
            try? await container.agentService.deleteAgent(id: agent.id)
        }

        // Re-seed defaults
        _ = try? await container.agentSeeder.seedDefaultAgents()

        // Refresh quick agents list
        quickAgents = await container.agentService.listAgents()

        withAnimation { showResetDone = true }
        try? await Task.sleep(for: .seconds(2))
        withAnimation { showResetDone = false }
    }

    // MARK: - Save

    private var settingsPrimaryAction: some View {
        HStack(spacing: 10) {
            if showSaved || showProfileSaved {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.positiveAccent)
                    Text(lang.common.saved)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(theme.foregroundTertiary)
                }
            }

            switch selectedDestination ?? .profile {
            case .profile:
                Button(lang.common.save) {
                    Task { await saveProfile() }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(isSavingProfile)
            case .general:
                Button(lang.common.save) {
                    Task { await saveSettings() }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(isSaving || !isValid)
            case .agents:
                EmptyView()
            }
        }
    }

    // MARK: - Logic

    private var isValid: Bool {
        guard let seconds = Int(timeoutText), seconds >= 30 else { return false }
        guard let idle = Int(idleTimeoutText), idle >= 30 else { return false }
        guard let concurrency = Int(concurrencyText), concurrency >= 1, concurrency <= 10 else { return false }
        return true
    }

    private func saveSettings() async {
        guard let seconds = Int(timeoutText), seconds >= 30,
              let idleSeconds = Int(idleTimeoutText), idleSeconds >= 30,
              let concurrency = Int(concurrencyText), concurrency >= 1, concurrency <= 10 else { return }
        isSaving = true
        defer { isSaving = false }

        settings.cliTimeoutSeconds = seconds
        settings.cliIdleTimeoutSeconds = idleSeconds
        settings.elaborationConcurrency = concurrency
        try? await container.appSettingsService.updateSettings(settings)

        withAnimation { showSaved = true }
        try? await Task.sleep(for: .seconds(2))
        withAnimation { showSaved = false }
    }

    private func saveProfile() async {
        isSavingProfile = true
        defer { isSavingProfile = false }

        profile.name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.bio = bioText.trimmingCharacters(in: .whitespacesAndNewlines)

        try? await container.userProfileService.updateProfile(profile)

        withAnimation { showProfileSaved = true }
        try? await Task.sleep(for: .seconds(2))
        withAnimation { showProfileSaved = false }
    }

}
