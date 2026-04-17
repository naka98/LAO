import Foundation
import LAODomain
import LAOPersistence
import LAOProviders
import LAORuntime
import LAOServices

@MainActor
struct AppContainer {
    let projectService: ProjectService
    let agentService: AgentService
    let providerRegistryService: ProviderRegistryService
    let cliAgentRunner: CLIAgentRunner
    let skillService: SkillService
    let userProfileService: UserProfileService
    let agentSeeder: DefaultAgentSeeder
    let skillSeeder: DefaultSkillSeeder
    let modelCatalog: ModelCatalogService

    let appSettingsService: AppSettingsService

    // v5 services
    let boardService: BoardService
    let projectAgentMembershipService: ProjectAgentMembershipService

    // v6 services
    let designSessionService: DesignSessionService
    let activeWorkflowCoordinator: ActiveWorkflowCoordinator

    // v7 services
    let ideaService: IdeaService

    // v8 services
    let designEventService: DesignEventService

    static let liveOrPreview: AppContainer = {
        do {
            let location = try LAOStoreLocationResolver.defaultLocation()
            let store = try SeededSQLiteStore(location: location)

            let projectService = SQLiteProjectService(store: store)
            let agentService = SQLiteAgentService(store: store)
            let providerRegistry = SQLiteProviderRegistryService(store: store)
            let appSettingsService = SQLiteAppSettingsService(store: store)
            let cliAgentRunner = ProviderBackedCLIAgentRunner(
                providerRegistryService: providerRegistry,
                appSettingsService: appSettingsService
            )

            let skillService = SQLiteSkillService(store: store)
            let userProfileService = SQLiteUserProfileService(store: store)
            let agentSeeder = DefaultAgentSeeder(agentService: agentService)
            let skillSeeder = DefaultSkillSeeder(skillService: skillService)
            let modelCatalog = ModelCatalogService()

            let boardService = SQLiteBoardService(store: store)
            let projectAgentMembershipService = SQLiteProjectAgentMembershipService(store: store)

            // v6 services
            let designSessionService = SQLiteDesignSessionService(store: store)

            // v7 services
            let ideaService = SQLiteIdeaService(store: store)

            // v8 services
            let designEventService = SQLiteDesignEventService(store: store)

            return AppContainer(
                projectService: projectService,
                agentService: agentService,
                providerRegistryService: providerRegistry,
                cliAgentRunner: cliAgentRunner,
                skillService: skillService,
                userProfileService: userProfileService,
                agentSeeder: agentSeeder,
                skillSeeder: skillSeeder,
                modelCatalog: modelCatalog,
                appSettingsService: appSettingsService,
                boardService: boardService,
                projectAgentMembershipService: projectAgentMembershipService,
                designSessionService: designSessionService,
                activeWorkflowCoordinator: ActiveWorkflowCoordinator(),
                ideaService: ideaService,
                designEventService: designEventService
            )
        } catch {
            fatalError("Failed to initialize LAO store: \(error)")
        }
    }()
}
