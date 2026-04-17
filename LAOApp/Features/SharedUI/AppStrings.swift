import Foundation

/// Compile-time safe, feature-namespaced string catalog for EN/KO localization.
/// Access via `@Environment(\.lang) var lang` then `lang.common.save`, `lang.design.title`, etc.
struct AppStrings: @unchecked Sendable {
    let common: Common
    let root: Root
    let design: Design
    let ideaBoard: IdeaBoard
    let designSession: DesignSession
    let settings: Settings
    let agents: Agents
    let skills: Skills

    // MARK: - Common (shared across features)

    struct Common {
        let save: String
        let cancel: String
        let close: String
        let delete_: String
        let retry: String
        let create: String
        let dismiss: String
        let stop: String
        let confirm: String
        let loading: String
        let search: String
        let skip: String
        let add: String
        let manage: String
        let reset: String
        let name: String
        let title_: String
        let bio: String
        let ready: String
        let missing: String
        let saved: String
        let documents: String
        let settings: String
        let design: String
        let fallback: String
        let stepAgent: String
        let plainText: String
        let markdown: String
        let copy: String
        let done: String
        let send: String
        let revealInFinder: String
        let unableToLoadPage: String
        let unableToReadFile: String
        let noAgentConfigured: String
        let noAgentConfiguredShort: String
        let back: String
        let failedToSaveIdeaFormat: (String) -> String
    }

    // MARK: - Root

    struct Root {
        let preparingWorkspace: String
        let loadingProjects: String
        let noProjectSelected: String
        let noProjectDescription: String
        let removeFromApp: String
        let addProjectHelp: String
        let projectNotFound: String
        let reSelectFolder: String
        let projectFolderMissingDescription: String
        let projects: String
        // Multi-window dialogs
        let activeWorkflowTitle: String
        let closeAnywayButton: String
        let workflowRunningCloseMessage: String
        let activeWorkflowsQuitTitle: String
        let activeWorkflowsQuitMessageFormat: (Int) -> String
        let quitButton: String
        // Project management
        let open: String
        let addProject: String
        let selectProjectFolder: String
        let selectFolder: String
        let folderAlreadyAdded: String
        let failedToAddProjectFormat: (String) -> String
        let failedToDeleteProjectFormat: (String) -> String
        let failedToUpdateFolderFormat: (String) -> String
        let workflowNeedsAttention: String
        let defaultBoardTitle: String
        let defaultBoardDescription: String
        // Menu commands
        let menuShowLauncher: String
        let menuSettings: String
    }

    // MARK: - Design

    struct Design {
        let panelTitle: String
        let loadingWorkflow: String
        let queued: String
        let queuedDescription: String
        let workInstruction: String
        let restartWorkflow: String
        let describeProject: String
        let inputDescription: String
        let analyzingHeadline: String
        let generatingSkeletonHeadline: String
        let analyzingRelationships: String
        let analyzingUncertainties: String
        let skeletonFailed: String
        let chatPlaceholder: String
        let noDeliverables: String
        let noDeliverablesHint: String
        let selectItem: String
        let pendingElaboration: String
        let complete: String
        let workflowCompleted: String
        let export: String
        let newWorkflow: String
        let backToList: String
        let workflowFailed: String
        let start: String
        let startOver: String
        let thinking: String
        let workingOn: (String) -> String
        let decisionHint: String
        let selectDocument: String
        let selectDocumentHint: String
        let workflowRestoreFailed: String
        let stoppedByUser: String
        let analysisFailedFormat: (String) -> String
        let responseParseFailed: String
        let chatFailedFormat: (String) -> String
        let workingPhaseGuide: String
        let elaborate: String
        let startAll: String
        let countdownFormat: (Int) -> String
        let startNow: String
        let pause: String
        let reanalyze: String

        let reviewHeadline: String
        let reviewDescription: String
        let approveAndStart: String

        let startSelected: String
        let selectAll: String
        let retryingFormat: (Int, Int) -> String

        let parallelWorkingFormat: (Int) -> String
        let progressItemsFormat: (Int, Int) -> String
        let queuePositionFormat: (Int) -> String
        let apiCallsFormat: (Int) -> String
        let tokensFormat: (String) -> String
        let completedSummaryFormat: (Int, Int) -> String

        // Review phase — inline actions & status
        let workGraph: String
        let specAvailable: String
        let allItemsApproved: String
        let reviewComplete: String
        let reviewCompleteMessage: String
        let reviewCompleteReadyMessage: String
        let generateDesignDoc: String
        let finishStepConsistencyCheck: String
        let finishStepApplyingFixes: String
        let finishStepExporting: String
        let pendingElaborationGuide: String
        let startElaborationAction: String
        let specIssuesBlocking: (Int) -> String
        let statusCompleted: String
        let statusInProgress: String
        let statusPending: String
        let statusNeedsRevision: String
        let actionApprove: String
        let actionRequestChanges: String
        let actionComment: String
        let chatPrefillRequestChanges: (String) -> String
        let chatPrefillComment: (String) -> String
        let chatFocusedPlaceholder: (String) -> String

        // Spec preview & dependency tray
        let noSpecYet: String
        let dependencyImpact: String
        let dependsOn: String
        let requiredBy: String
        let nMoreFormat: (Int) -> String
        let deferImpactFormat: (Int) -> String
        let specPurpose: String
        let specEntry: String
        let specExitTo: String
        let specComponents: String
        let specInteractions: String
        let specStates: String
        let specEdgeCases: String
        let specSuggestedRefinements: String
        let specRequestBody: String
        let specResponse: String
        let specErrorResponses: String
        let specParameters: String
        let specFields: String
        let specRelationships: String
        let specIndexes: String
        let specBusinessRules: String
        let specTrigger: String
        let specSteps: String
        let specDecisionPoints: String
        let specSuccessOutcome: String
        let specErrorPaths: String
        let specRelatedScreens: String

        // Context summary card
        let contextSummary: String
        let contextArrivesFrom: String
        let contextNavigatesTo: String
        let showMore: String
        let showLess: String
        let statesCountFormat: (Int) -> String
        let interactionCountFormat: (Int) -> String
        let fieldCountFormat: (Int) -> String
        let relationshipCountFormat: (Int) -> String
        let stepCountFormat: (Int) -> String

        // Graph — relation labels
        let relDependsOn: String
        let relNavigatesTo: String
        let relUses: String
        let relRefines: String
        let relReplaces: String
        let nRelationsFormat: (Int) -> String
        // Graph — legend group titles
        let legendSections: String
        let legendRelations: String
        let legendStatus: String

        // Planner verdict (legacy)
        let verdictUnreviewed: String
        let verdictApproved: String
        let verdictRejected: String
        let verdictOK: String
        let verdictRequestChange: String
        let unreviewedCountFormat: (Int) -> String

        // Design verdict (decision-maker facing)
        let verdictPending: String
        let verdictConfirmed: String
        let verdictConfirm: String
        let verdictNeedsRevision: String
        let verdictRequestRevision: String
        let verdictExcluded: String
        let verdictExclude: String
        let revisionNotePlaceholder: String
        let revisionNoteSubmit: String
        let pendingReviewCountFormat: (Int) -> String
        let readinessLabel: String
        let readinessIssueFormat: (String, String) -> String  // (key, itemName) -> localized hint
        let technicalDetail: String

        // Planning phase
        let planningHeadline: String
        let planningDescription: String
        let elaborationProgressFormat: (Int, Int) -> String
        let elaborationComplete: String
        let elaborationOverlayTitle: String
        let elaborationOverlaySubtitle: (Int) -> String
        let elaborationItemWorking: String
        let elaborationItemDone: String
        let elaborationItemFailed: String
        let elaborationItemPending: String
        let elaborationPreparing: String
        let elaborationAllComplete: String
        let elaborationConsistencyChecking: String
        let elaborationApplyingFixes: String
        let elaborationExporting: String
        let reviewGuide: (Int) -> String
        let reviewFirstPending: String
        let finishWorkflow: String
        let plannerQuestion: String
        let plannerNotes: String

        // Business-language summary labels (decision-maker facing)
        let componentListLabel: String
        let interactionListLabel: String
        let stateListLabel: String
        let fieldListLabel: String
        let businessRulesLabel: String
        let narrativeStepsLabel: String
        let moreItemsFormat: (Int) -> String
        let readinessReady: String
        let readinessIncomplete: String
        let readinessNotValidated: String

        // Canvas planning view
        let projectOverview: String
        let inspectorPendingDecisions: String
        let inspectorItemReview: String
        let connections: String
        let sharedResources: String
        let technicalStructure: String

        // Uncertainty escalation
        let uncertaintyTitle: String
        let uncertaintyEmpty: String
        let uncertaintyQuestion: String
        let uncertaintySuggestion: String
        let uncertaintyDiscussion: String
        let uncertaintyInfoGap: String
        let uncertaintyBlocking: String
        let uncertaintyImportant: String
        let uncertaintyAdvisory: String
        let uncertaintyResolve: String
        let uncertaintyApprove: String
        let uncertaintyDismiss: String
        let uncertaintyDiscuss: String
        let uncertaintyDiscussTitle: String
        let uncertaintyDiscussPlaceholder: String
        let uncertaintyProposedResolution: String
        let uncertaintyApproveResolution: String
        let uncertaintyAddComment: String
        let uncertaintyResolutionComplete: String
        let uncertaintyReopen: String
        let uncertaintyAutoResolved: String
        let uncertaintyResponsePlaceholder: String
        let uncertaintyCountFormat: (Int) -> String
        let axiomMultipleInterpretations: String
        let axiomMissingInput: String
        let axiomConflictsWithAgreement: String
        let axiomUngroundedAssumption: String
        let axiomNotVerifiable: String
        let axiomHighImpactIfWrong: String

        // Reanalyze confirmation
        let reanalyzeConfirmTitle: String
        let reanalyzeConfirmAction: String
        let reanalyzeConfirmMessage: String
        let reanalyzeFeedbackPlaceholder: String
        let reanalyzeFeedbackHint: String

        // Finish workflow confirmation
        let finishConfirmTitle: String
        let finishConfirmAction: String
        let finishConfirmMessage: String
        let aiRequestedCompletion: String
        let noExportableItems: String
        let consistencyCheckTitle: String
        let consistencyCheckFixIssues: String
        let consistencyCheckProceed: String

        // Consistency review overlay
        let consistencyReviewTitle: String
        let consistencyReviewSubtitle: (Int) -> String
        let consistencyIssueCritical: String
        let consistencyIssueWarning: String
        let consistencyIssueInfo: String
        let consistencyApproveFixes: String
        let consistencyApplyingFixes: String
        let consistencyReElaborating: String
        let consistencyFixesComplete: String
        let consistencyProceedExport: String
        let consistencyAddComment: String
        let consistencyDiscussPlaceholder: String
        let consistencyAutoRequest: String

        // Elaboration failure
        let elaborationFailed: String
        let retryElaboration: String

        // Approach selection (7-step reasoning)
        let approachSelectionTitle: String
        let approachSelectionSubtitle: String
        let recommendedApproach: String
        let approachPros: String
        let approachCons: String
        let approachRisks: String
        let approachRecommended: String
        let approachSelect: String
        let approachComplexity: String
        let approachComplexityLow: String
        let approachComplexityMedium: String
        let approachComplexityHigh: String
        let hiddenRequirementsTitle: String
        let hiddenRequirementsSubtitle: String

        // Approach reasoning & per-approach requirements
        let approachReasoningTitle: String
        let approachUniqueRequirement: String
        let approachConnectionsFormat: (Int) -> String

        // Design Freeze confirmation
        let designFreezeTitle: String
        let designFreezeMessage: String
        let designFreezeConfirm: String
        let designFreezeBack: String
        let designFreezeWarning: String
        let designFreezeDeliverables: String
        let designFreezeBlocker: String

        // Structure Approval (REFINE → SPECIFY gate)
        let refinePhaseLabel: String
        let specifyPhaseLabel: String
        let approveStructure: String
        let structureApprovalTitle: String
        let structureApprovalMessage: String
        let structureApprovalWarning: String
        let structureApprovalConfirm: String
        let structureApprovalBack: String

        // Finish Approval (elaboration complete → consistency check + export gate)
        let finishApprovalTitle: String
        let finishApprovalMessage: String
        let finishApprovalWarning: String
        let finishApprovalConfirm: String
        let finishApprovalBack: String
        let runFinishCTA: String

        // Cluster-level review
        let clusterConfirmAll: String
        let clusterScenarioSuffix: String
        let clusterMoreFormat: (Int) -> String

        // Decision audit trail
        let decisionHistoryTitle: String
        let decisionCountFormat: (Int) -> String

        // Export validation
        let exportValidationErrorsFormat: (Int) -> String
        let exportValidationWarning: String

        // Convergence monitoring
        let convergenceRateFormat: (Int) -> String
        let oscillationWarningFormat: (Int) -> String
        let oscillationItemHint: String
        let concurrencyReducedFormat: (Int) -> String

        // Error feedback
        let handoffLaunchFailed: (String) -> String
        let syncFailed: String

        // Completion blockers
        let blockerUnconfirmedItems: String
        let blockerSpecIssues: String
        let blockerNoExportable: String
        let completionBlockedTitle: String

        // Export action
        let viewItem: String

        // Start design work (planning header)
        let startDesignWork: String

        // Revision review overlay
        let revisionReviewTitle: String
        let revisionSubmitReview: String
        let revisionAddComment: String
        let revisionApprove: String
        let revisionProposedChanges: String
        let revisionApplyingChanges: String
        let revisionReElaborating: String
        let revisionComplete: String

        // Inspector status banner
        let bannerBlockingQuestions: (Int) -> String
        let bannerPendingReview: (Int) -> String
        let bannerAllConfirmedReady: String
        let bannerElaborating: (Int, Int) -> String
        let bannerExportReady: String

        // Tech stack editor
        let techStackTitle: String
        let techStackDescription: String
        let techStackLanguage: String
        let techStackFramework: String
        let techStackPlatform: String
        let techStackDatabase: String
        let techStackOther: String

        // Graph toolbar
        let fitToView: String
        let cancelLink: String
        let linkNodes: String
        let stepsCountLabel: (Int) -> String
        // Tech stack placeholders
        let techStackLanguagePlaceholder: String
        let techStackFrameworkPlaceholder: String
        let techStackPlatformPlaceholder: String
        let techStackDatabasePlaceholder: String
        let techStackOtherPlaceholder: String
        // Misc UI labels
        let openIn: String
        let readiness: String
        let blockingCountFormat: (Int) -> String
        let options: String
        let pending: String
    }

    // MARK: - IdeaBoard

    struct IdeaBoard {
        let boardTitle: String
        let newIdea: String
        let searchPlaceholder: String
        let noIdeasTitle: String
        let noIdeasDescription: String
        let newIdeaDefaultTitle: String
        let converted: String
        let designComplete: String
        let designFailed: String
        let createFailed: String
        let deleteFailed: String

        // Filters
        let filterAll: String
        let filterAnalyzed: String
        let filterConverted: String
        let filterDraft: String
        let filterDesigned: String
        let filterDesignFailed: String

        // Detail view
        let stepAgentNotConfigured: String
        let stepAgentSetupInstruction: String
        let answering: String
        let askQuestion: String
        let askExpertPlaceholder: String
        let designAnalysisFailed: String
        let reanalyze: String
        let designSynthesis: String
        let recommendedDirection: String
        let createScreenSpec: String
        let reviewBrief: String
        let generatingBrief: String
        let conversationSummary: String
        let urlDetectedHint: String
        let rearrangeReasonPlaceholder: String
        let rearrangeLabel: String
        let rearrangePanelHelp: String
        let attachFileHelp: String
        let describeIdeaPlaceholder: String
        let askExpertsPlaceholder: String
        let selectAttachment: String
        let reviewOtherDirections: String
        let decideDirection: String
        let briefAfterDiscussion: String
        let briefInitial: String
        let regenerateBrief: String
        let generateBriefButton: String
        let startDesign: String
        let confirmDesignStartTitle: String
        let confirmDesignStartMessage: String
        let compressionSuggestion: String
        let requestCompression: String
        // ViewModel status messages
        let designPlanningStatus: String
        let expertsAnalyzingStatus: String
        let keyScreensLabel: String
        let recommendedDirectionDefault: String
        let newExpertsAnalyzing: String
        let panelRearrangeFailedFormat: (String) -> String
        let compressingStatus: String
        let keyPointsLabel: String
        let compressionFailedFormat: (String) -> String
        let arrangingNewExperts: String
        let responseFailed: String
        let interruptedByRestart: String
        let analysisFailedFormat: (String) -> String
        let noExpertPanel: String
        let expertsAnalyzingProgressFormat: (Int, Int) -> String
        let failedToCreateRequestFormat: (String) -> String

        let conversationCountFormat: (Int) -> String
        let attachmentFormat: (String) -> String
        let callsFormat: (Int) -> String
        let tokensShortFormat: (String) -> String

        // BRD generation (after synthesis)
        let brdGenerating: String
        let brdReady: String
        let brdFailed: String
        let openDocument: String

        // BRD fields displayed in Brief overlay
        let brdProblemStatement: String
        let brdTargetUsers: String
        let brdBusinessObjectives: String
        let brdScope: String
        let brdInScope: String
        let brdOutOfScope: String
        let brdMvpBoundary: String
        let brdConstraints: String
        let brdAssumptions: String
        let designBriefTitle: String
        let designBriefMessage: String
        let designBriefDirection: String
        let designBriefExperts: String
        let designBriefMessages: String
        let designBriefEntities: String
        let designBriefBrdIncluded: String
        let designBriefStart: String
        let designBriefBack: String
        let designBriefKeyDecisions: String
        let designBriefInScope: String
        let designBriefOutOfScope: String
        let expertLimitations: String
        let designBriefExecutionContext: String

        // Reference phase
        let reference: String
        let referenceExplore: String
        let referenceSearching: String
        let referenceRetry: String
        let referenceSkip: String
        let referenceProceed: String
        let generateBriefDirectly: String
        // Reference phase detail
        let referenceSearchTooltip: String
        let referenceGuidance: String
        let referenceCategoryVisual: String
        let referenceCategoryExperience: String
        let referenceCategoryImplementation: String
        let referenceFeedbackPlaceholder: String
        let referenceRequestMessage: String
        // BRD error messages
        let jsonNotFoundError: String
        let jsonParseFailedFormat: (String) -> String
    }

    // MARK: - DesignSession

    struct DesignSession {
        let newSession: String
        let noSessionsTitle: String
        let noSessionsDescription: String
        let taskDescriptionLabel: String
        let newSessionTitle: String
        let apiCallsHelp: String
        let tokensHelp: String
        let filterAll: String
        let queuedFormat: (Int) -> String
        let statusPlanning: String
        let statusReviewing: String
        let statusExecuting: String
        let statusCompleted: String
        let statusFailed: String
    }

    // MARK: - Settings

    struct Settings {
        // Tabs
        let profile: String
        let general: String
        let agentsTab: String

        // Sections
        let advancedSection: String

        // Profile
        let aboutYou: String
        let profileDescription: String
        let namePlaceholder: String
        let titlePlaceholder: String
        let bioPlaceholder: String

        // Core AI Team
        let coreAITeam: String
        let coreAITeamDescription: String
        let openAdvanced: String
        let designDescription: String
        let fallbackDescription: String
        let stepAgentDescription: String

        // Language
        let languageTitle: String
        let languageDescription: String

        // CLI Timeouts
        let cliMaxRuntime: String
        let cliMaxRuntimeDescription: String
        let cliIdleTimeout: String
        let cliIdleTimeoutDescription: String
        let seconds: String
        let secondsUnit: String
        let minRuntimeWarning: String
        let streamInterruptWarning: String
        let minIdleTimeoutWarning: String
        let shortIdleWarning: String

        // Elaboration Concurrency
        let elaborationConcurrency: String
        let elaborationConcurrencyDescription: String
        let elaborationConcurrencyWarning: String
        let elaborationConcurrencyUnit: String

        // Reset
        let resetAgents: String
        let resetAgentsDescription: String
        let resetComplete: String
        let resetConfirmMessage: String

        let agentAddedFormat: (String) -> String
        let agentAddFailedFormat: (String) -> String
    }

    // MARK: - Agents

    struct Agents {
        let refreshModels: String
        let fetching: String
        let fetchingCatalog: String
        let addAgent: String
        let noAgentsTitle: String
        let noAgentsDescription: String
        let editAgent: String
        let newAgent: String
        let tier: String
        let provider: String
        let model: String
        let selectModel: String
        let instruction: String
        let instructionDescription: String
        let instructionPlaceholder: String
        let designTierDesc: String
        let fallbackTierDesc: String
        let stepTierDesc: String
        let createFailed: String
        let updateFailed: String
        let deleteFailed: String

        let agentCountFormat: (Int) -> String
        let validatingFormat: (String, Int, Int) -> String
    }

    // MARK: - Skills

    struct Skills {
        let addSkill: String
        let noSkillsTitle: String
        let noSkillsDescription: String
        let editSkill: String
        let newSkill: String
        let role: String
        let skillName: String
        let description_: String
        let createFailed: String
        let updateFailed: String
        let deleteFailed: String

        let skillCountFormat: (Int) -> String
    }
}

// MARK: - English

extension AppStrings {
    static let en = AppStrings(
        common: Common(
            save: "Save",
            cancel: "Cancel",
            close: "Close",
            delete_: "Delete",
            retry: "Retry",
            create: "Create",
            dismiss: "Dismiss",
            stop: "Stop",
            confirm: "Confirm",
            loading: "Loading...",
            search: "Search",
            skip: "Skip",
            add: "Add",
            manage: "Manage",
            reset: "Reset",
            name: "Name",
            title_: "Title",
            bio: "Bio",
            ready: "Ready",
            missing: "Missing",
            saved: "Saved",
            documents: "Documents",
            settings: "Settings",
            design: "Design",
            fallback: "Fallback",
            stepAgent: "Step Agent",
            plainText: "Plain text",
            markdown: "Markdown",
            copy: "Copy",
            done: "Done",
            send: "Send",
            revealInFinder: "Reveal in Finder",
            unableToLoadPage: "Unable to load page",
            unableToReadFile: "Unable to read file",
            noAgentConfigured: "No AI agent is configured. Go to Settings > Agents to set up a provider.",
            noAgentConfiguredShort: "No AI agent is configured.",
            back: "Back",
            failedToSaveIdeaFormat: { error in "Failed to save idea: \(error)" }
        ),
        root: Root(
            preparingWorkspace: "Preparing Workspace",
            loadingProjects: "Loading projects and demo data.",
            noProjectSelected: "No Project Selected",
            noProjectDescription: "Select or add a project folder to get started.",
            removeFromApp: "Remove from LAO",
            addProjectHelp: "Add project folder",
            projectNotFound: "Project folder not found",
            reSelectFolder: "Re-select Folder",
            projectFolderMissingDescription: "The project folder was not found at the saved path. Re-select the folder to continue.",
            projects: "Projects",
            activeWorkflowTitle: "Active Design",
            closeAnywayButton: "Close Anyway",
            workflowRunningCloseMessage: "A design is in progress for this project. It will continue in the background if you close.",
            activeWorkflowsQuitTitle: "Active Designs",
            activeWorkflowsQuitMessageFormat: { count in "\(count) design\(count == 1 ? " is" : "s are") still in progress. Quit anyway?" },
            quitButton: "Quit",
            open: "Open",
            addProject: "Add Project",
            selectProjectFolder: "Select a project folder to add",
            selectFolder: "Select Folder",
            folderAlreadyAdded: "This folder is already added as a project.",
            failedToAddProjectFormat: { error in "Failed to add project: \(error)" },
            failedToDeleteProjectFormat: { error in "Failed to delete project: \(error)" },
            failedToUpdateFolderFormat: { error in "Failed to update project folder: \(error)" },
            workflowNeedsAttention: "Design needs your attention",
            defaultBoardTitle: "General",
            defaultBoardDescription: "Default board",
            menuShowLauncher: "Show Project Launcher",
            menuSettings: "LAO Settings..."
        ),
        design: Design(
            panelTitle: "Design",
            loadingWorkflow: "Loading design...",
            queued: "Queued",
            queuedDescription: "Another design is in progress.\nIt will start automatically when finished.",
            workInstruction: "Work Instruction",
            restartWorkflow: "Restart Design",
            describeProject: "Describe your project",
            inputDescription: "The director will analyze your idea, create deliverables, and refine the design via conversation.",
            analyzingHeadline: "Analyzing...",
            generatingSkeletonHeadline: "Generating design skeleton...",
            analyzingRelationships: "Analyzing relationships",
            analyzingUncertainties: "Analyzing uncertainties",
            skeletonFailed: "Skeleton generation failed",
            chatPlaceholder: "Ask about the design...",
            noDeliverables: "No Deliverables",
            noDeliverablesHint: "Deliverables appear after analysis.",
            selectItem: "Select an item",
            pendingElaboration: "Pending elaboration",
            complete: "Complete",
            workflowCompleted: "Design Complete",
            export: "Export",
            newWorkflow: "New Design",
            backToList: "Back to List",
            workflowFailed: "Design Failed",
            start: "Start",
            startOver: "Start Over",
            thinking: "Director is reviewing…",
            workingOn: { name in "Working: \(name)" },
            decisionHint: "Use the conversation to respond to this decision.",
            selectDocument: "Select a Document",
            selectDocumentHint: "Choose a document from the sidebar.",
            workflowRestoreFailed: "Design data could not be fully restored.",
            stoppedByUser: "Stopped by user.",
            analysisFailedFormat: { error in "Director analysis failed: \(error)" },
            responseParseFailed: "The response could not be parsed into a valid structure.",
            chatFailedFormat: { error in "Chat failed: \(error)" },
            workingPhaseGuide: "Analysis complete. Send a message to start elaborating items — e.g. \"Start with all items\" or \"Elaborate the first section\".",
            elaborate: "Elaborate",
            startAll: "Start All",
            countdownFormat: { seconds in "Starting in \(seconds)s..." },
            startNow: "Start Now",
            pause: "Pause",
            reanalyze: "Re-analyze",
            reviewHeadline: "Review Project Structure",
            reviewDescription: "Check the deliverables and dependencies before starting work.",
            approveAndStart: "Approve & Start",
            startSelected: "Start Selected",
            selectAll: "Select All",
            retryingFormat: { attempt, total in "Retrying (\(attempt)/\(total))..." },
            parallelWorkingFormat: { count in "\(count) items working..." },
            progressItemsFormat: { completed, total in "\(completed)/\(total) confirmed" },
            queuePositionFormat: { pos in "Queue position: #\(pos)" },
            apiCallsFormat: { count in "\(count) calls" },
            tokensFormat: { tokens in "~\(tokens) tokens" },
            completedSummaryFormat: { sections, items in "\(sections) sections, \(items) items delivered." },
            workGraph: "Work Graph",
            specAvailable: "Spec available",
            allItemsApproved: "All items approved — proceed with Approve & Start.",
            reviewComplete: "Review Complete",
            reviewCompleteMessage: "All items confirmed.",
            reviewCompleteReadyMessage: "All items confirmed. Start design elaboration from the header.",
            generateDesignDoc: "Complete Design",
            finishStepConsistencyCheck: "Running consistency check…",
            finishStepApplyingFixes: "Applying fixes…",
            finishStepExporting: "Finalizing…",
            pendingElaborationGuide: "Some items have not been elaborated yet.",
            startElaborationAction: "Start Elaboration",
            specIssuesBlocking: { n in "\(n) spec issue\(n == 1 ? "" : "s") — AI tools need more detail" },
            statusCompleted: "Done",
            statusInProgress: "Working",
            statusPending: "Pending",
            statusNeedsRevision: "Needs Revision",
            actionApprove: "Approve",
            actionRequestChanges: "Request Changes",
            actionComment: "Comment",
            chatPrefillRequestChanges: { name in "[Request Changes] \(name): " },
            chatPrefillComment: { name in "[Comment] \(name): " },
            chatFocusedPlaceholder: { name in "Feedback on \(name)..." },
            noSpecYet: "No spec data yet",
            dependencyImpact: "Dependency Impact",
            dependsOn: "Depends on",
            requiredBy: "Required by",
            nMoreFormat: { n in "+\(n) more" },
            deferImpactFormat: { n in "Affects \(n) downstream \(n == 1 ? "item" : "items")" },
            specPurpose: "Purpose",
            specEntry: "Entry",
            specExitTo: "Exit To",
            specComponents: "Components",
            specInteractions: "Interactions",
            specStates: "States",
            specEdgeCases: "Edge Cases",
            specSuggestedRefinements: "Suggested Refinements",
            specRequestBody: "Request Body",
            specResponse: "Response",
            specErrorResponses: "Error Responses",
            specParameters: "Parameters",
            specFields: "Fields",
            specRelationships: "Relationships",
            specIndexes: "Indexes",
            specBusinessRules: "Business Rules",
            specTrigger: "Trigger",
            specSteps: "Steps",
            specDecisionPoints: "Decision Points",
            specSuccessOutcome: "Success Outcome",
            specErrorPaths: "Error Paths",
            specRelatedScreens: "Related Screens",
            contextSummary: "Summary",
            contextArrivesFrom: "Arrives from",
            contextNavigatesTo: "Navigates to",
            showMore: "Show more",
            showLess: "Show less",
            statesCountFormat: { n in "\(n) \(n == 1 ? "state" : "states")" },
            interactionCountFormat: { n in "\(n) \(n == 1 ? "interaction" : "interactions")" },
            fieldCountFormat: { n in "\(n) \(n == 1 ? "field" : "fields")" },
            relationshipCountFormat: { n in "\(n) \(n == 1 ? "relationship" : "relationships")" },
            stepCountFormat: { n in "\(n) \(n == 1 ? "step" : "steps")" },
            relDependsOn: "Depends on",
            relNavigatesTo: "Navigates to",
            relUses: "Uses",
            relRefines: "Refines",
            relReplaces: "Replaces",
            nRelationsFormat: { n in "\(n) relations" },
            legendSections: "Sections",
            legendRelations: "Relations",
            legendStatus: "Status",
            verdictUnreviewed: "Unreviewed",
            verdictApproved: "Approved",
            verdictRejected: "Rejected",
            verdictOK: "OK",
            verdictRequestChange: "Request Changes",
            unreviewedCountFormat: { n in "\(n) unreviewed" },
            verdictPending: "Pending Review",
            verdictConfirmed: "Confirmed",
            verdictConfirm: "Confirm",
            verdictNeedsRevision: "Needs Revision",
            verdictRequestRevision: "Request Revision",
            verdictExcluded: "Excluded",
            verdictExclude: "Exclude",
            revisionNotePlaceholder: "What needs to be changed?",
            revisionNoteSubmit: "Submit",
            pendingReviewCountFormat: { n in "\(n) pending review" },
            readinessLabel: "Design Readiness",
            readinessIssueFormat: { key, name in
                switch key {
                case "components_missing": return "「\(name)」 screen components not yet defined"
                case "fields_unnamed":     return "「\(name)」 data fields need names"
                case "fields_missing":     return "「\(name)」 data fields not yet defined"
                case "api_method_missing": return "「\(name)」 API method not yet set"
                case "steps_missing":      return "「\(name)」 flow steps not defined"
                case "spec_empty":         return "「\(name)」 details not yet written"
                default:                   return "「\(name)」 some details need completion"
                }
            },
            technicalDetail: "Technical Detail",
            planningHeadline: "Planning",
            planningDescription: "Review and judge each item.",
            elaborationProgressFormat: { c, t in "Elaborating \(c)/\(t)" },
            elaborationComplete: "Design complete.",
            elaborationOverlayTitle: "Design in Progress",
            elaborationOverlaySubtitle: { n in "Working on \(n) item\(n == 1 ? "" : "s")" },
            elaborationItemWorking: "Working",
            elaborationItemDone: "Done",
            elaborationItemFailed: "Failed",
            elaborationItemPending: "Queued",
            elaborationPreparing: "Assigning agents and preparing context…",
            elaborationAllComplete: "All items elaborated",
            elaborationConsistencyChecking: "Checking consistency…",
            elaborationApplyingFixes: "Applying fixes…",
            elaborationExporting: "Finalizing…",
            reviewGuide: { n in "\(n) items awaiting review. Select each to confirm, revise, or exclude." },
            reviewFirstPending: "Review First Pending",
            finishWorkflow: "Complete Design",
            plannerQuestion: "Review Point",
            plannerNotes: "Planner Notes",
            componentListLabel: "Components",
            interactionListLabel: "User actions",
            stateListLabel: "Screen states",
            fieldListLabel: "Stored items",
            businessRulesLabel: "Business rules",
            narrativeStepsLabel: "Flow",
            moreItemsFormat: { n in "+\(n) more" },
            readinessReady: "Spec ready",
            readinessIncomplete: "Needs refinement",
            readinessNotValidated: "Not yet validated",
            projectOverview: "Project Overview",
            inspectorPendingDecisions: "Pending Decisions",
            inspectorItemReview: "Item Review",
            connections: "Connections",
            sharedResources: "Shared Resources",
            technicalStructure: "Technical Structure",
            uncertaintyTitle: "Questions & Decisions",
            uncertaintyEmpty: "No pending questions",
            uncertaintyQuestion: "Question",
            uncertaintySuggestion: "Suggestion",
            uncertaintyDiscussion: "Discussion Needed",
            uncertaintyInfoGap: "Information Needed",
            uncertaintyBlocking: "Blocking",
            uncertaintyImportant: "Important",
            uncertaintyAdvisory: "Advisory",
            uncertaintyResolve: "Answer",
            uncertaintyApprove: "Approve",
            uncertaintyDismiss: "Dismiss",
            uncertaintyDiscuss: "Discuss",
            uncertaintyDiscussTitle: "Discuss Uncertainty",
            uncertaintyDiscussPlaceholder: "Ask about this uncertainty...",
            uncertaintyProposedResolution: "Proposed Resolution",
            uncertaintyApproveResolution: "Approve Resolution",
            uncertaintyAddComment: "Add Comment",
            uncertaintyResolutionComplete: "Uncertainty Resolved",
            uncertaintyReopen: "Reopen",
            uncertaintyAutoResolved: "Design resolved",
            uncertaintyResponsePlaceholder: "Type your answer...",
            uncertaintyCountFormat: { n in "\(n) questions" },
            axiomMultipleInterpretations: "Multiple interpretations",
            axiomMissingInput: "Missing input",
            axiomConflictsWithAgreement: "Conflicts with agreement",
            axiomUngroundedAssumption: "Ungrounded assumption",
            axiomNotVerifiable: "Not verifiable",
            axiomHighImpactIfWrong: "High impact if wrong",
            reanalyzeConfirmTitle: "Re-analyze?",
            reanalyzeConfirmAction: "Re-analyze",
            reanalyzeConfirmMessage: "This will discard all current deliverables and chat history, then start a fresh analysis. This cannot be undone.",
            reanalyzeFeedbackPlaceholder: "What should change? (optional)",
            reanalyzeFeedbackHint: "Scope, missing features, different approach…",
            finishConfirmTitle: "Complete Design?",
            finishConfirmAction: "Complete",
            finishConfirmMessage: "All confirmed items will be finalized.",
            aiRequestedCompletion: "Design is complete.",
            noExportableItems: "No completed design items. Please run design first.",
            consistencyCheckTitle: "Consistency Check Results",
            consistencyCheckFixIssues: "Fix Issues",
            consistencyCheckProceed: "Proceed",
            consistencyReviewTitle: "Consistency Review",
            consistencyReviewSubtitle: { n in "\(n) issues found" },
            consistencyIssueCritical: "Critical",
            consistencyIssueWarning: "Warning",
            consistencyIssueInfo: "Info",
            consistencyApproveFixes: "Approve Fixes",
            consistencyApplyingFixes: "Applying fixes…",
            consistencyReElaborating: "Re-elaborating…",
            consistencyFixesComplete: "All fixes applied",
            consistencyProceedExport: "Complete Design",
            consistencyAddComment: "Add Comment",
            consistencyDiscussPlaceholder: "Discuss issues with director…",
            consistencyAutoRequest: "Please review these issues and propose concrete fixes.",
            elaborationFailed: "Elaboration Failed",
            retryElaboration: "Retry",
            approachSelectionTitle: "Choose an Approach",
            approachSelectionSubtitle: "The Design identified multiple approaches. Compare and select one.",
            recommendedApproach: "Recommended Approach",
            approachPros: "Pros",
            approachCons: "Cons",
            approachRisks: "Risks",
            approachRecommended: "Recommended",
            approachSelect: "Select",
            approachComplexity: "Complexity",
            approachComplexityLow: "Low",
            approachComplexityMedium: "Medium",
            approachComplexityHigh: "High",
            hiddenRequirementsTitle: "Inferred Requirements",
            hiddenRequirementsSubtitle: "Requirements not explicitly stated but likely needed",
            approachReasoningTitle: "Why this approach",
            approachUniqueRequirement: "Unique to this approach",
            approachConnectionsFormat: { n in "\(n) connections" },
            designFreezeTitle: "Confirm Design Direction",
            designFreezeMessage: "Review the selected approach before proceeding.",
            designFreezeConfirm: "Confirm & Start Design",
            designFreezeBack: "Back",
            designFreezeWarning: "Once confirmed, fundamental direction changes will be costly.",
            designFreezeDeliverables: "Deliverables to generate",
            designFreezeBlocker: "Cannot proceed",
            refinePhaseLabel: "REFINE",
            specifyPhaseLabel: "SPECIFY",
            approveStructure: "Approve Structure",
            structureApprovalTitle: "Confirm Design Structure",
            structureApprovalMessage: "Review the structure before starting detailed specification.",
            structureApprovalWarning: "After approval, structural changes will require re-elaboration of affected items.",
            structureApprovalConfirm: "Approve & Start Specification",
            structureApprovalBack: "Back to Review",
            finishApprovalTitle: "Run Consistency Check & Export",
            finishApprovalMessage: "All design items have been elaborated. Run a cross-item consistency check and export the final spec?",
            finishApprovalWarning: "If issues are found, you'll be asked to review and apply fixes before export.",
            finishApprovalConfirm: "Run Consistency Check & Export",
            finishApprovalBack: "Back",
            runFinishCTA: "Run Consistency Check & Export",
            clusterConfirmAll: "Confirm All",
            clusterScenarioSuffix: "scenario",
            clusterMoreFormat: { n in "+ \(n) more" },
            decisionHistoryTitle: "Decision History",
            decisionCountFormat: { n in "\(n) decisions" },
            exportValidationErrorsFormat: { n in "\(n) validation issue\(n == 1 ? "" : "s")" },
            exportValidationWarning: "Design document has structural issues",
            convergenceRateFormat: { pct in "\(pct)% converged" },
            oscillationWarningFormat: { n in "\(n) item\(n == 1 ? "" : "s") oscillating" },
            oscillationItemHint: "Repeated revisions — consider clarifying requirements",
            concurrencyReducedFormat: { n in "Rate limited — concurrency reduced to \(n)" },
            handoffLaunchFailed: { tool in "Failed to launch \(tool). Check if it is installed." },
            syncFailed: "Failed to save design state.",
            blockerUnconfirmedItems: "Some items are not yet confirmed",
            blockerSpecIssues: "Blocking spec issues remain",
            blockerNoExportable: "No completed design items (run design and confirm first)",
            completionBlockedTitle: "Cannot complete yet",
            viewItem: "View Item",
            startDesignWork: "Start Design",
            revisionReviewTitle: "Revision Review",
            revisionSubmitReview: "Submit for Review",
            revisionAddComment: "Add Comment",
            revisionApprove: "Approve & Apply",
            revisionProposedChanges: "Proposed Changes",
            revisionApplyingChanges: "Applying changes…",
            revisionReElaborating: "Revising specification…",
            revisionComplete: "Revision complete",
            bannerBlockingQuestions: { n in "\(n) blocking — resolve now" },
            bannerPendingReview: { n in "\(n) items awaiting review" },
            bannerAllConfirmedReady: "All confirmed — ready to start",
            bannerElaborating: { c, t in "Elaborating \(c)/\(t)" },
            bannerExportReady: "Design complete",
            techStackTitle: "Tech Stack",
            techStackDescription: "AI agent generates specs tailored to your tech stack.",
            techStackLanguage: "Language",
            techStackFramework: "Framework",
            techStackPlatform: "Platform",
            techStackDatabase: "Database",
            techStackOther: "Other",
            fitToView: "Fit to View",
            cancelLink: "Cancel Link",
            linkNodes: "Link Nodes",
            stepsCountLabel: { n in "\(n) steps" },
            techStackLanguagePlaceholder: "e.g. Swift, TypeScript, Python",
            techStackFrameworkPlaceholder: "e.g. SwiftUI, React, FastAPI",
            techStackPlatformPlaceholder: "e.g. macOS, iOS, Web",
            techStackDatabasePlaceholder: "e.g. PostgreSQL, SQLite",
            techStackOtherPlaceholder: "e.g. Docker, Redis",
            openIn: "Open in",
            readiness: "Readiness",
            blockingCountFormat: { n in "\(n) blocking" },
            options: "Options:",
            pending: "Pending"
        ),
        ideaBoard: IdeaBoard(
            boardTitle: "Ideas",
            newIdea: "New Idea",
            searchPlaceholder: "Search ideas...",
            noIdeasTitle: "No Ideas Yet",
            noIdeasDescription: "Create an idea to brainstorm with AI expert panels.",
            newIdeaDefaultTitle: "New Idea",
            converted: "In Design",
            designComplete: "Design Complete",
            designFailed: "Design Failed",
            createFailed: "Failed to create idea",
            deleteFailed: "Failed to delete idea",
            filterAll: "All",
            filterAnalyzed: "Analyzed",
            filterConverted: "In Design",
            filterDraft: "Draft",
            filterDesigned: "Design Complete",
            filterDesignFailed: "Design Failed",
            stepAgentNotConfigured: "Step Agent is not configured.",
            stepAgentSetupInstruction: "Add a Step Agent in Settings > Agents, then try again.",
            answering: "Answering...",
            askQuestion: "Ask",
            askExpertPlaceholder: "Ask an expert...",
            designAnalysisFailed: "Analysis failed",
            reanalyze: "Re-analyze",
            designSynthesis: "Director Synthesis",
            recommendedDirection: "Recommended Direction",
            createScreenSpec: "Start Design Review",
            reviewBrief: "Review Design Brief",
            generatingBrief: "Generating Design Brief...",
            conversationSummary: "Conversation Summary",
            urlDetectedHint: "URL detected. The agent will read the content automatically.",
            rearrangeReasonPlaceholder: "Reason for rearranging (optional)...",
            rearrangeLabel: "Rearrange",
            rearrangePanelHelp: "Rearrange expert panel",
            attachFileHelp: "Attach file or image",
            describeIdeaPlaceholder: "Describe your idea...",
            askExpertsPlaceholder: "Ask the experts...",
            selectAttachment: "Select file to attach",
            reviewOtherDirections: "Regenerate Design Brief",
            decideDirection: "Generate Design Brief",
            briefAfterDiscussion: "Generate a new Design Brief reflecting the additional discussion.",
            briefInitial: "Generate a Design Brief from expert discussions. Type your preference in the input field to guide the output.",
            regenerateBrief: "Regenerate Brief",
            generateBriefButton: "Generate Brief",
            startDesign: "Start Design",
            confirmDesignStartTitle: "Start design?",
            confirmDesignStartMessage: "Once design begins, you cannot return to the exploration phase.",
            compressionSuggestion: "The conversation is getting long. Ask the Design to summarize?",
            requestCompression: "Request Summary",
            designPlanningStatus: "Design is planning...",
            expertsAnalyzingStatus: "Experts are analyzing...",
            keyScreensLabel: "Key Screens",
            recommendedDirectionDefault: "Recommended Direction",
            newExpertsAnalyzing: "New experts are analyzing...",
            panelRearrangeFailedFormat: { error in "Panel rearrangement failed: \(error)" },
            compressingStatus: "Design is summarizing the conversation...",
            keyPointsLabel: "Key Points",
            compressionFailedFormat: { error in "Context compression failed: \(error)" },
            arrangingNewExperts: "Design is arranging new experts...",
            responseFailed: "Failed to get response",
            interruptedByRestart: "Analysis interrupted — tap Retry",
            analysisFailedFormat: { error in "Analysis failed: \(error)" },
            noExpertPanel: "No expert panel found. Please run Analyze first.",
            expertsAnalyzingProgressFormat: { completed, total in "Experts are analyzing... (\(completed)/\(total))" },
            failedToCreateRequestFormat: { error in "Failed to create request: \(error)" },
            conversationCountFormat: { count in "\(count) messages" },
            attachmentFormat: { path in "[Attached: \(path)]" },
            callsFormat: { count in "\(count) calls" },
            tokensShortFormat: { tokens in "\(tokens) tokens" },
            brdGenerating: "Generating BRD...",
            brdReady: "BRD Ready",
            brdFailed: "BRD generation failed",
            openDocument: "Open",
            brdProblemStatement: "Problem Statement",
            brdTargetUsers: "Target Users",
            brdBusinessObjectives: "Business Objectives",
            brdScope: "Scope",
            brdInScope: "In Scope",
            brdOutOfScope: "Out of Scope",
            brdMvpBoundary: "MVP Boundary",
            brdConstraints: "Constraints",
            brdAssumptions: "Assumptions",
            designBriefTitle: "Design Brief",
            designBriefMessage: "The following will be sent to the design office.",
            designBriefDirection: "Direction",
            designBriefExperts: "Experts consulted",
            designBriefMessages: "Discussion messages",
            designBriefEntities: "Extracted entities",
            designBriefBrdIncluded: "BRD included",
            designBriefStart: "Start Design",
            designBriefBack: "Close",
            designBriefKeyDecisions: "Key Decisions",
            designBriefInScope: "In Scope",
            designBriefOutOfScope: "Out of Scope",
            expertLimitations: "AI Constraints",
            designBriefExecutionContext: "Execution Constraints",
            reference: "References",
            referenceExplore: "Explore References",
            referenceSearching: "Searching for references...",
            referenceRetry: "Search Again",
            referenceSkip: "Skip",
            referenceProceed: "Proceed with References",
            generateBriefDirectly: "Generate Brief Directly",
            referenceSearchTooltip: "Search on Google Images",
            referenceGuidance: "Explore references or generate a Brief directly",
            referenceCategoryVisual: "Visual",
            referenceCategoryExperience: "Experience",
            referenceCategoryImplementation: "Implementation",
            referenceFeedbackPlaceholder: "Enter feedback (e.g. 'Not this kind of feel...')",
            referenceRequestMessage: "Show me reference images.",
            jsonNotFoundError: "No JSON found in the response",
            jsonParseFailedFormat: { s in "JSON parse failed: \(s)…" }
        ),
        designSession: DesignSession(
            newSession: "New Design Session",
            noSessionsTitle: "No design sessions yet",
            noSessionsDescription: "Create a new design session to start.",
            taskDescriptionLabel: "Describe your work instruction",
            newSessionTitle: "New Design Session",
            apiCallsHelp: "API calls",
            tokensHelp: "Estimated tokens",
            filterAll: "All",
            queuedFormat: { pos in "Queued #\(pos)" },
            statusPlanning: "Planning",
            statusReviewing: "Reviewing",
            statusExecuting: "Executing",
            statusCompleted: "Completed",
            statusFailed: "Failed"
        ),
        settings: Settings(
            profile: "Profile",
            general: "General",
            agentsTab: "Agents",
            advancedSection: "Settings",
            aboutYou: "About You",
            profileDescription: "This information is used for AI collaboration context and owner representation.",
            namePlaceholder: "e.g. Mini",
            titlePlaceholder: "e.g. CEO, Founder, Product Lead",
            bioPlaceholder: "Background and work context for AI agents to understand",
            coreAITeam: "Core AI Team",
            coreAITeamDescription: "Start with a lean setup. You can adjust models, prompts, and extra roles later in Advanced.",
            openAdvanced: "Open Advanced",
            designDescription: "Plans, delegates, and coordinates design execution.",
            fallbackDescription: "Backup director when the primary is unavailable.",
            stepAgentDescription: "Executes individual steps assigned by the director.",
            languageTitle: "Language",
            languageDescription: "Choose the display language for the app interface.",
            cliMaxRuntime: "CLI Max Runtime",
            cliMaxRuntimeDescription: "Hard cap for a single AI agent run.",
            cliIdleTimeout: "CLI Idle Timeout",
            cliIdleTimeoutDescription: "Kill the CLI process if no new output is received for this many seconds.",
            seconds: "Seconds",
            secondsUnit: "seconds",
            minRuntimeWarning: "Minimum max runtime is 30 seconds.",
            streamInterruptWarning: "Values under 180 seconds can interrupt longer streaming runs.",
            minIdleTimeoutWarning: "Minimum idle timeout is 30 seconds.",
            shortIdleWarning: "Short idle timeouts may interrupt agents that pause to think.",
            elaborationConcurrency: "Elaboration Concurrency",
            elaborationConcurrencyDescription: "Maximum number of items elaborated simultaneously. Higher values speed up design but may trigger API rate limits.",
            elaborationConcurrencyWarning: "High values may trigger rate limits with some providers.",
            elaborationConcurrencyUnit: "items",
            resetAgents: "Reset Agents",
            resetAgentsDescription: "Delete all agents and re-create them from defaults.",
            resetComplete: "Reset complete",
            resetConfirmMessage: "All agents will be deleted and re-created from defaults. Continue?",
            agentAddedFormat: { name in "\(name) added to the core AI team" },
            agentAddFailedFormat: { name in "Failed to add \(name)" }
        ),
        agents: Agents(
            refreshModels: "Refresh Models",
            fetching: "Fetching...",
            fetchingCatalog: "Fetching catalog...",
            addAgent: "Add Agent",
            noAgentsTitle: "No agents configured",
            noAgentsDescription: "Add AI agents to collaborate in meetings.",
            editAgent: "Edit Agent",
            newAgent: "New Agent",
            tier: "Tier",
            provider: "Provider",
            model: "Model",
            selectModel: "Select model",
            instruction: "Instruction",
            instructionDescription: "Describe this agent's specialty. The director uses this to assign the best-fit agent for each task.",
            instructionPlaceholder: "e.g. Frontend specialist, strong at React UI and responsive design",
            designTierDesc: "Primary orchestrator that plans, delegates, and coordinates design.",
            fallbackTierDesc: "Backup director used when the primary director is unavailable.",
            stepTierDesc: "Executes individual design steps assigned by the director.",
            createFailed: "Failed to create agent",
            updateFailed: "Failed to update agent",
            deleteFailed: "Failed to delete agent",
            agentCountFormat: { count in "\(count) agents" },
            validatingFormat: { provider, current, total in "Validating \(provider) \(current)/\(total)" }
        ),
        skills: Skills(
            addSkill: "Add Skill",
            noSkillsTitle: "No skills configured",
            noSkillsDescription: "Skills will be auto-generated on first launch. Restart the app or add skills manually.",
            editSkill: "Edit Skill",
            newSkill: "New Skill",
            role: "Role",
            skillName: "Skill Name",
            description_: "Description",
            createFailed: "Failed to create skill",
            updateFailed: "Failed to update skill",
            deleteFailed: "Failed to delete skill",
            skillCountFormat: { count in "\(count) skills" }
        )
    )
}

// MARK: - Korean

extension AppStrings {
    static let ko = AppStrings(
        common: Common(
            save: "저장",
            cancel: "취소",
            close: "닫기",
            delete_: "삭제",
            retry: "다시 시도",
            create: "생성",
            dismiss: "닫기",
            stop: "중지",
            confirm: "확인",
            loading: "로딩 중...",
            search: "검색",
            skip: "건너뛰기",
            add: "추가",
            manage: "관리",
            reset: "초기화",
            name: "이름",
            title_: "직함",
            bio: "소개",
            ready: "준비됨",
            missing: "없음",
            saved: "저장됨",
            documents: "문서",
            settings: "설정",
            design: "디렉터",
            fallback: "폴백",
            stepAgent: "스텝 에이전트",
            plainText: "일반 텍스트",
            markdown: "마크다운",
            copy: "복사",
            done: "완료",
            send: "보내기",
            revealInFinder: "Finder에서 보기",
            unableToLoadPage: "페이지를 불러올 수 없음",
            unableToReadFile: "파일을 읽을 수 없음",
            noAgentConfigured: "AI 에이전트가 설정되지 않았습니다. 설정 > 에이전트에서 프로바이더를 설정하세요.",
            noAgentConfiguredShort: "AI 에이전트가 설정되지 않았습니다.",
            back: "뒤로",
            failedToSaveIdeaFormat: { error in "아이디어 저장 실패: \(error)" }
        ),
        root: Root(
            preparingWorkspace: "워크스페이스 준비 중",
            loadingProjects: "프로젝트 및 데모 데이터를 불러오는 중입니다.",
            noProjectSelected: "프로젝트 미선택",
            noProjectDescription: "시작하려면 프로젝트 폴더를 선택하거나 추가하세요.",
            removeFromApp: "LAO에서 제거",
            addProjectHelp: "프로젝트 폴더 추가",
            projectNotFound: "프로젝트 폴더를 찾을 수 없음",
            reSelectFolder: "폴더 재선택",
            projectFolderMissingDescription: "저장된 경로에서 프로젝트 폴더를 찾을 수 없습니다. 폴더를 다시 선택해 주세요.",
            projects: "프로젝트",
            activeWorkflowTitle: "진행 중인 설계",
            closeAnywayButton: "그래도 닫기",
            workflowRunningCloseMessage: "이 프로젝트의 설계가 진행 중입니다. 닫으면 백그라운드에서 계속 진행됩니다.",
            activeWorkflowsQuitTitle: "진행 중인 설계",
            activeWorkflowsQuitMessageFormat: { count in "설계 \(count)개가 아직 진행 중입니다. 그래도 종료할까요?" },
            quitButton: "종료",
            open: "열기",
            addProject: "프로젝트 추가",
            selectProjectFolder: "추가할 프로젝트 폴더를 선택하세요",
            selectFolder: "폴더 선택",
            folderAlreadyAdded: "이 폴더는 이미 프로젝트로 추가되어 있습니다.",
            failedToAddProjectFormat: { error in "프로젝트 추가 실패: \(error)" },
            failedToDeleteProjectFormat: { error in "프로젝트 삭제 실패: \(error)" },
            failedToUpdateFolderFormat: { error in "프로젝트 폴더 업데이트 실패: \(error)" },
            workflowNeedsAttention: "설계에 사용자 확인이 필요합니다",
            defaultBoardTitle: "General",
            defaultBoardDescription: "기본 보드",
            menuShowLauncher: "프로젝트 런처 열기",
            menuSettings: "LAO 설정..."
        ),
        design: Design(
            panelTitle: "설계",
            loadingWorkflow: "설계 로딩 중...",
            queued: "대기 중",
            queuedDescription: "다른 설계가 진행 중입니다.\n완료되면 자동으로 시작됩니다.",
            workInstruction: "작업 지시서",
            restartWorkflow: "설계 재시작",
            describeProject: "프로젝트를 설명하세요",
            inputDescription: "디렉터가 아이디어를 분석하고 산출물을 생성하며, 대화를 통해 설계를 구체화합니다.",
            analyzingHeadline: "분석 중...",
            generatingSkeletonHeadline: "설계 골격 생성 중...",
            analyzingRelationships: "관계 분석",
            analyzingUncertainties: "불확실성 탐색",
            skeletonFailed: "설계 골격 생성 실패",
            chatPlaceholder: "설계에 대해 질문하세요...",
            noDeliverables: "산출물 없음",
            noDeliverablesHint: "분석 후 산출물이 표시됩니다.",
            selectItem: "항목을 선택하세요",
            pendingElaboration: "상세화 대기 중",
            complete: "완료",
            workflowCompleted: "설계 완료",
            export: "내보내기",
            newWorkflow: "새 설계",
            backToList: "목록으로",
            workflowFailed: "설계 실패",
            start: "시작",
            startOver: "처음부터 다시",
            thinking: "디렉터가 검토 중…",
            workingOn: { name in "작업 중: \(name)" },
            decisionHint: "이 결정에 응답하려면 대화를 사용하세요.",
            selectDocument: "문서 선택",
            selectDocumentHint: "사이드바에서 문서를 선택하세요.",
            workflowRestoreFailed: "설계 데이터를 완전히 복원하지 못했습니다.",
            stoppedByUser: "사용자가 중지했습니다.",
            analysisFailedFormat: { error in "디렉터 분석 실패: \(error)" },
            responseParseFailed: "응답을 유효한 구조로 파싱할 수 없습니다.",
            chatFailedFormat: { error in "채팅 실패: \(error)" },
            workingPhaseGuide: "분석이 완료되었습니다. 채팅으로 작업을 지시하세요 — 예: \"모든 항목 시작\" 또는 \"첫 번째 섹션부터 작성해줘\".",
            elaborate: "작성",
            startAll: "전체 시작",
            countdownFormat: { seconds in "\(seconds)초 후 시작..." },
            startNow: "바로 시작",
            pause: "일시 중지",
            reanalyze: "다시 분석",
            reviewHeadline: "프로젝트 구조 검토",
            reviewDescription: "작업을 시작하기 전에 산출물과 의존 관계를 확인하세요.",
            approveAndStart: "승인 & 시작",
            startSelected: "선택 시작",
            selectAll: "전체 선택",
            retryingFormat: { attempt, total in "재시도 중 (\(attempt)/\(total))..." },
            parallelWorkingFormat: { count in "\(count)개 아이템 작업 중..." },
            progressItemsFormat: { completed, total in "\(completed)/\(total) 확인" },
            queuePositionFormat: { pos in "대기 순서: #\(pos)" },
            apiCallsFormat: { count in "\(count)회 호출" },
            tokensFormat: { tokens in "~\(tokens) 토큰" },
            completedSummaryFormat: { sections, items in "\(sections)개 섹션, \(items)개 항목 완료." },
            workGraph: "워크 그래프",
            specAvailable: "스펙 작성됨",
            allItemsApproved: "모든 항목이 승인됨 — 승인 & 시작으로 진행하세요.",
            reviewComplete: "검토 완료",
            reviewCompleteMessage: "모든 항목이 확인되었습니다.",
            reviewCompleteReadyMessage: "모든 항목이 확인되었습니다. 상단의 설계 착수 버튼으로 시작하세요.",
            generateDesignDoc: "설계 완료",
            finishStepConsistencyCheck: "일관성 검사 중…",
            finishStepApplyingFixes: "이슈 수정 중…",
            finishStepExporting: "설계 완료 처리 중…",
            pendingElaborationGuide: "작성이 완료되지 않은 항목이 있습니다.",
            startElaborationAction: "항목 작성 시작",
            specIssuesBlocking: { n in "\(n)개 스펙 문제 — AI 도구에 정보가 부족합니다" },
            statusCompleted: "완료",
            statusInProgress: "진행중",
            statusPending: "대기",
            statusNeedsRevision: "수정필요",
            actionApprove: "승인",
            actionRequestChanges: "수정요청",
            actionComment: "코멘트",
            chatPrefillRequestChanges: { name in "[수정요청] \(name): " },
            chatPrefillComment: { name in "[코멘트] \(name): " },
            chatFocusedPlaceholder: { name in "\(name)에 대한 피드백..." },
            noSpecYet: "스펙 데이터 없음",
            dependencyImpact: "의존 관계 영향",
            dependsOn: "의존 대상",
            requiredBy: "필요로 하는 항목",
            nMoreFormat: { n in "+\(n)개 더" },
            deferImpactFormat: { n in "하위 \(n)개 항목에 영향" },
            specPurpose: "목적",
            specEntry: "진입 조건",
            specExitTo: "이동 대상",
            specComponents: "컴포넌트",
            specInteractions: "인터랙션",
            specStates: "상태",
            specEdgeCases: "예외 상황",
            specSuggestedRefinements: "개선 제안",
            specRequestBody: "요청 본문",
            specResponse: "응답",
            specErrorResponses: "에러 응답",
            specParameters: "파라미터",
            specFields: "필드",
            specRelationships: "관계",
            specIndexes: "인덱스",
            specBusinessRules: "비즈니스 규칙",
            specTrigger: "트리거",
            specSteps: "단계",
            specDecisionPoints: "분기점",
            specSuccessOutcome: "성공 결과",
            specErrorPaths: "에러 경로",
            specRelatedScreens: "관련 화면",
            contextSummary: "요약",
            contextArrivesFrom: "진입 경로",
            contextNavigatesTo: "이동 대상",
            showMore: "더 보기",
            showLess: "접기",
            statesCountFormat: { n in "\(n)개 상태" },
            interactionCountFormat: { n in "인터랙션 \(n)개" },
            fieldCountFormat: { n in "필드 \(n)개" },
            relationshipCountFormat: { n in "관계 \(n)개" },
            stepCountFormat: { n in "\(n)단계" },
            relDependsOn: "의존",
            relNavigatesTo: "이동",
            relUses: "참조",
            relRefines: "개선",
            relReplaces: "대체",
            nRelationsFormat: { n in "\(n)개 관계" },
            legendSections: "섹션",
            legendRelations: "관계",
            legendStatus: "상태",
            verdictUnreviewed: "미검토",
            verdictApproved: "승인",
            verdictRejected: "제외",
            verdictOK: "OK",
            verdictRequestChange: "수정 요청",
            unreviewedCountFormat: { n in "미검토 \(n)개" },
            verdictPending: "검토 대기",
            verdictConfirmed: "확인됨",
            verdictConfirm: "확인",
            verdictNeedsRevision: "수정 요청",
            verdictRequestRevision: "수정 요청",
            verdictExcluded: "제외됨",
            verdictExclude: "제외",
            revisionNotePlaceholder: "수정이 필요한 이유를 입력하세요",
            revisionNoteSubmit: "제출",
            pendingReviewCountFormat: { n in "검토 대기 \(n)개" },
            readinessLabel: "설계 준비도",
            readinessIssueFormat: { key, name in
                switch key {
                case "components_missing": return "「\(name)」 화면 구성요소가 아직 정의되지 않았습니다"
                case "fields_unnamed":     return "「\(name)」 데이터 항목에 이름이 필요합니다"
                case "fields_missing":     return "「\(name)」 데이터 항목이 아직 정의되지 않았습니다"
                case "api_method_missing": return "「\(name)」 API 방식이 아직 정해지지 않았습니다"
                case "steps_missing":      return "「\(name)」 흐름 단계가 정의되지 않았습니다"
                case "spec_empty":         return "「\(name)」 상세 내용이 아직 작성되지 않았습니다"
                default:                   return "「\(name)」 일부 상세 내용이 보완 필요합니다"
                }
            },
            technicalDetail: "기술 상세",
            planningHeadline: "기획 판단",
            planningDescription: "항목을 검토하고 판단하세요.",
            elaborationProgressFormat: { c, t in "설계 진행중 \(c)/\(t)" },
            elaborationComplete: "설계 완료",
            elaborationOverlayTitle: "설계 진행 중",
            elaborationOverlaySubtitle: { n in "\(n)개 항목 작업 중" },
            elaborationItemWorking: "작업 중",
            elaborationItemDone: "완료",
            elaborationItemFailed: "실패",
            elaborationItemPending: "대기 중",
            elaborationPreparing: "에이전트를 배정하고 맥락을 준비하는 중…",
            elaborationAllComplete: "모든 항목 설계 완료",
            elaborationConsistencyChecking: "일관성 검수 중…",
            elaborationApplyingFixes: "이슈 수정 중…",
            elaborationExporting: "설계 완료 처리 중…",
            reviewGuide: { n in "\(n)개 항목이 검토 대기중입니다. 선택하여 확인/수정/제외를 결정해 주세요." },
            reviewFirstPending: "첫 번째 대기 항목 검토",
            finishWorkflow: "설계 완료",
            plannerQuestion: "검토 포인트",
            plannerNotes: "기획자 메모",
            componentListLabel: "구성 요소",
            interactionListLabel: "사용자 동작",
            stateListLabel: "화면 상태",
            fieldListLabel: "저장 항목",
            businessRulesLabel: "비즈니스 규칙",
            narrativeStepsLabel: "흐름",
            moreItemsFormat: { n in "외 \(n)건" },
            readinessReady: "설계 준비 완료",
            readinessIncomplete: "일부 보완 필요",
            readinessNotValidated: "아직 검증 전",
            projectOverview: "프로젝트 개요",
            inspectorPendingDecisions: "대기 중인 판단",
            inspectorItemReview: "항목 검토",
            connections: "연결",
            sharedResources: "공유 리소스",
            technicalStructure: "기술 구조",
            uncertaintyTitle: "질문 & 결정",
            uncertaintyEmpty: "대기 중인 질문 없음",
            uncertaintyQuestion: "질문",
            uncertaintySuggestion: "제안",
            uncertaintyDiscussion: "논의 필요",
            uncertaintyInfoGap: "정보 필요",
            uncertaintyBlocking: "진행 불가",
            uncertaintyImportant: "중요",
            uncertaintyAdvisory: "참고",
            uncertaintyResolve: "답변",
            uncertaintyApprove: "승인",
            uncertaintyDismiss: "무시",
            uncertaintyDiscuss: "논의하기",
            uncertaintyDiscussTitle: "불확실성 논의",
            uncertaintyDiscussPlaceholder: "이 불확실성에 대해 질문하세요...",
            uncertaintyProposedResolution: "제안된 해결안",
            uncertaintyApproveResolution: "해결안 승인",
            uncertaintyAddComment: "의견 추가",
            uncertaintyResolutionComplete: "불확실성 해결됨",
            uncertaintyReopen: "다시 열기",
            uncertaintyAutoResolved: "디렉터가 판단함",
            uncertaintyResponsePlaceholder: "답변을 입력하세요...",
            uncertaintyCountFormat: { n in "질문 \(n)건" },
            axiomMultipleInterpretations: "해석 분기",
            axiomMissingInput: "입력값 부재",
            axiomConflictsWithAgreement: "합의 충돌",
            axiomUngroundedAssumption: "근거 없는 추측",
            axiomNotVerifiable: "검증 불가",
            axiomHighImpactIfWrong: "고위험 판단",
            reanalyzeConfirmTitle: "다시 분석하시겠습니까?",
            reanalyzeConfirmAction: "재분석",
            reanalyzeConfirmMessage: "현재 산출물, 채팅 기록이 모두 삭제되고 새로 분석합니다. 되돌릴 수 없습니다.",
            reanalyzeFeedbackPlaceholder: "무엇을 변경할까요? (선택 사항)",
            reanalyzeFeedbackHint: "범위, 누락된 기능, 다른 접근 방식…",
            finishConfirmTitle: "설계를 완료하시겠습니까?",
            finishConfirmAction: "완료",
            finishConfirmMessage: "확인된 항목의 설계가 완료됩니다.",
            aiRequestedCompletion: "설계가 완료되었습니다.",
            noExportableItems: "완료된 설계 항목이 없습니다. 설계를 먼저 진행해 주세요.",
            consistencyCheckTitle: "일관성 검사 결과",
            consistencyCheckFixIssues: "이슈 수정",
            consistencyCheckProceed: "무시하고 진행",
            consistencyReviewTitle: "일관성 검토",
            consistencyReviewSubtitle: { n in "\(n)개 이슈 발견" },
            consistencyIssueCritical: "심각",
            consistencyIssueWarning: "경고",
            consistencyIssueInfo: "정보",
            consistencyApproveFixes: "수정 승인",
            consistencyApplyingFixes: "수정 적용 중…",
            consistencyReElaborating: "재작성 중…",
            consistencyFixesComplete: "모든 수정 완료",
            consistencyProceedExport: "설계 완료",
            consistencyAddComment: "의견 추가",
            consistencyDiscussPlaceholder: "디렉터와 이슈 논의…",
            consistencyAutoRequest: "이 이슈들을 검토하고 구체적인 수정안을 제안해 주세요.",
            elaborationFailed: "상세 작성 실패",
            retryElaboration: "재시도",
            approachSelectionTitle: "접근 방식 선택",
            approachSelectionSubtitle: "디렉터가 여러 접근 방식을 도출했습니다. 비교 후 선택해 주세요.",
            recommendedApproach: "추천 접근법",
            approachPros: "장점",
            approachCons: "단점",
            approachRisks: "리스크",
            approachRecommended: "추천",
            approachSelect: "선택",
            approachComplexity: "복잡도",
            approachComplexityLow: "낮음",
            approachComplexityMedium: "보통",
            approachComplexityHigh: "높음",
            hiddenRequirementsTitle: "추정된 요구사항",
            hiddenRequirementsSubtitle: "명시되지 않았지만 필요할 것으로 추정되는 요구사항",
            approachReasoningTitle: "이 접근 방식의 근거",
            approachUniqueRequirement: "이 접근 방식에만 해당",
            approachConnectionsFormat: { n in "\(n)개 연결" },
            designFreezeTitle: "설계 방향 확정",
            designFreezeMessage: "선택한 접근 방식을 확인한 뒤 진행합니다.",
            designFreezeConfirm: "확정 후 설계 시작",
            designFreezeBack: "돌아가기",
            designFreezeWarning: "확정 후에는 근본적인 방향 변경이 어렵습니다.",
            designFreezeDeliverables: "생성할 산출물",
            designFreezeBlocker: "진행 불가",
            refinePhaseLabel: "구조 검토",
            specifyPhaseLabel: "상세 사양",
            approveStructure: "구조 승인",
            structureApprovalTitle: "설계 구조 확정",
            structureApprovalMessage: "상세 사양 작성 전에 구조를 확인합니다.",
            structureApprovalWarning: "승인 후 구조 변경 시 관련 항목의 재작성이 필요합니다.",
            structureApprovalConfirm: "승인 후 사양 작성 시작",
            structureApprovalBack: "검토로 돌아가기",
            finishApprovalTitle: "일관성 검사 및 내보내기",
            finishApprovalMessage: "모든 설계 항목 작성이 완료되었습니다. 항목 간 일관성 검사를 실행하고 최종 사양을 내보낼까요?",
            finishApprovalWarning: "이슈가 발견되면 내보내기 전에 검토 후 수정 사항을 적용할 수 있습니다.",
            finishApprovalConfirm: "일관성 검사 및 내보내기",
            finishApprovalBack: "돌아가기",
            runFinishCTA: "일관성 검사 및 내보내기",
            clusterConfirmAll: "전체 확인",
            clusterScenarioSuffix: "시나리오",
            clusterMoreFormat: { n in "외 \(n)건" },
            decisionHistoryTitle: "결정 이력",
            decisionCountFormat: { n in "\(n)건 결정" },
            exportValidationErrorsFormat: { n in "검증 이슈 \(n)건" },
            exportValidationWarning: "설계 문서에 구조적 문제가 있습니다",
            convergenceRateFormat: { pct in "\(pct)% 수렴" },
            oscillationWarningFormat: { n in "\(n)개 항목 반복 수정 중" },
            oscillationItemHint: "반복 수정 — 요구사항 명확화를 권장합니다",
            concurrencyReducedFormat: { n in "속도 제한 — 동시 실행 수 \(n)으로 축소" },
            handoffLaunchFailed: { tool in "\(tool) 실행에 실패했습니다. 설치 여부를 확인해 주세요." },
            syncFailed: "설계 상태 저장에 실패했습니다.",
            blockerUnconfirmedItems: "아직 확인되지 않은 항목이 있습니다",
            blockerSpecIssues: "해결되지 않은 스펙 문제가 있습니다",
            blockerNoExportable: "완료된 설계 항목이 없습니다 (설계 후 확인해 주세요)",
            completionBlockedTitle: "아직 완료할 수 없습니다",
            viewItem: "항목 보기",
            startDesignWork: "설계 착수",
            revisionReviewTitle: "수정 검토",
            revisionSubmitReview: "검토 요청",
            revisionAddComment: "추가 의견",
            revisionApprove: "승인 후 반영",
            revisionProposedChanges: "제안 변경 사항",
            revisionApplyingChanges: "변경 사항 적용 중…",
            revisionReElaborating: "설계서 수정 중…",
            revisionComplete: "수정 완료",
            bannerBlockingQuestions: { n in "\(n)건 블로킹 질문 — 해결 필요" },
            bannerPendingReview: { n in "\(n)건 검토 대기" },
            bannerAllConfirmedReady: "모두 확인 완료 — 착수 가능",
            bannerElaborating: { c, t in "작성 중 \(c)/\(t)" },
            bannerExportReady: "설계 완료",
            techStackTitle: "Tech Stack",
            techStackDescription: "AI 에이전트가 기술 스택에 맞는 설계서를 생성합니다.",
            techStackLanguage: "Language",
            techStackFramework: "Framework",
            techStackPlatform: "Platform",
            techStackDatabase: "Database",
            techStackOther: "Other",
            fitToView: "전체 보기",
            cancelLink: "연결 취소",
            linkNodes: "노드 연결",
            stepsCountLabel: { n in "\(n)단계" },
            techStackLanguagePlaceholder: "예: Swift, TypeScript, Python",
            techStackFrameworkPlaceholder: "예: SwiftUI, React, FastAPI",
            techStackPlatformPlaceholder: "예: macOS, iOS, Web",
            techStackDatabasePlaceholder: "예: PostgreSQL, SQLite",
            techStackOtherPlaceholder: "예: Docker, Redis",
            openIn: "열기",
            readiness: "준비도",
            blockingCountFormat: { n in "\(n)개 차단 중" },
            options: "옵션:",
            pending: "대기 중"
        ),
        ideaBoard: IdeaBoard(
            boardTitle: "아이디어",
            newIdea: "새 아이디어",
            searchPlaceholder: "아이디어 검색...",
            noIdeasTitle: "아이디어 없음",
            noIdeasDescription: "아이디어를 생성하여 AI 전문가 패널과 브레인스토밍하세요.",
            newIdeaDefaultTitle: "새 아이디어",
            converted: "설계 중",
            designComplete: "설계 완료",
            designFailed: "설계 실패",
            createFailed: "아이디어 생성에 실패했습니다",
            deleteFailed: "아이디어 삭제에 실패했습니다",
            filterAll: "전체",
            filterAnalyzed: "분석됨",
            filterConverted: "설계 중",
            filterDraft: "초안",
            filterDesigned: "설계 완료",
            filterDesignFailed: "설계 실패",
            stepAgentNotConfigured: "Step Agent가 설정되지 않았습니다.",
            stepAgentSetupInstruction: "설정 > 에이전트에서 Step Agent를 추가한 후 다시 시도하세요.",
            answering: "답변 중...",
            askQuestion: "질문하기",
            askExpertPlaceholder: "전문가에게 질문하기...",
            designAnalysisFailed: "분석 실패",
            reanalyze: "다시 분석",
            designSynthesis: "디렉터 종합",
            recommendedDirection: "추천 방향",
            createScreenSpec: "설계 검토 시작",
            reviewBrief: "설계 의뢰서 확인",
            generatingBrief: "설계 의뢰서 생성 중...",
            conversationSummary: "대화 요약",
            urlDetectedHint: "URL이 포함되어 있어요. 에이전트가 자동으로 내용을 읽습니다.",
            rearrangeReasonPlaceholder: "재구성 이유 (선택사항)...",
            rearrangeLabel: "재구성",
            rearrangePanelHelp: "전문가 패널 재구성",
            attachFileHelp: "파일 또는 이미지 첨부",
            describeIdeaPlaceholder: "아이디어를 설명해주세요...",
            askExpertsPlaceholder: "전문가들에게 질문하기...",
            selectAttachment: "첨부할 파일 선택",
            reviewOtherDirections: "의뢰서를 다시 작성합니다",
            decideDirection: "설계 의뢰서를 작성합니다",
            briefAfterDiscussion: "추가 논의를 반영하여 새로운 설계 의뢰서를 작성합니다.",
            briefInitial: "전문가 논의를 종합하여 설계 의뢰서를 작성합니다. 입력창에 선호 방향을 적으면 반영됩니다.",
            regenerateBrief: "의뢰서 재작성",
            generateBriefButton: "의뢰서 작성",
            startDesign: "설계 시작",
            confirmDesignStartTitle: "설계를 시작하시겠습니까?",
            confirmDesignStartMessage: "설계가 시작되면 탐색 단계로 돌아갈 수 없습니다.",
            compressionSuggestion: "대화가 많아지고 있어요. Design에게 정리를 요청할까요?",
            requestCompression: "정리 요청",
            designPlanningStatus: "Design가 기획 중...",
            expertsAnalyzingStatus: "전문가들이 분석 중...",
            keyScreensLabel: "핵심 화면",
            recommendedDirectionDefault: "추천 방향",
            newExpertsAnalyzing: "새 전문가들이 분석 중...",
            panelRearrangeFailedFormat: { error in "패널 재구성 실패: \(error)" },
            compressingStatus: "Design가 대화를 정리하는 중...",
            keyPointsLabel: "핵심",
            compressionFailedFormat: { error in "컨텍스트 압축 실패: \(error)" },
            arrangingNewExperts: "Design가 새 전문가를 구성 중...",
            responseFailed: "응답을 받지 못했습니다",
            interruptedByRestart: "분석이 중단됨 — 재시도를 눌러주세요",
            analysisFailedFormat: { error in "분석 실패: \(error)" },
            noExpertPanel: "전문가 패널을 찾을 수 없습니다. 먼저 분석을 실행하세요.",
            expertsAnalyzingProgressFormat: { completed, total in "전문가들이 분석 중... (\(completed)/\(total))" },
            failedToCreateRequestFormat: { error in "요청 생성 실패: \(error)" },
            conversationCountFormat: { count in "\(count)개 대화" },
            attachmentFormat: { path in "[첨부: \(path)]" },
            callsFormat: { count in "\(count)회 호출" },
            tokensShortFormat: { tokens in "\(tokens) 토큰" },
            brdGenerating: "BRD 생성 중...",
            brdReady: "BRD 생성 완료",
            brdFailed: "BRD 생성 실패",
            openDocument: "열기",
            brdProblemStatement: "문제 정의",
            brdTargetUsers: "대상 사용자",
            brdBusinessObjectives: "비즈니스 목표",
            brdScope: "범위",
            brdInScope: "범위 내",
            brdOutOfScope: "범위 외",
            brdMvpBoundary: "MVP 경계",
            brdConstraints: "제약사항",
            brdAssumptions: "가정사항",
            designBriefTitle: "설계 의뢰서",
            designBriefMessage: "다음 내용으로 설계 사무소에 의뢰합니다.",
            designBriefDirection: "방향",
            designBriefExperts: "참여 전문가",
            designBriefMessages: "논의 메시지",
            designBriefEntities: "추출된 엔티티",
            designBriefBrdIncluded: "BRD 포함",
            designBriefStart: "설계 시작",
            designBriefBack: "닫기",
            designBriefKeyDecisions: "핵심 결정 사항",
            designBriefInScope: "범위 내",
            designBriefOutOfScope: "범위 외",
            expertLimitations: "AI 제약사항",
            designBriefExecutionContext: "실행 제약사항",
            reference: "레퍼런스",
            referenceExplore: "레퍼런스 탐색",
            referenceSearching: "레퍼런스를 찾고 있습니다...",
            referenceRetry: "다시 찾기",
            referenceSkip: "건너뛰기",
            referenceProceed: "이 레퍼런스로 진행",
            generateBriefDirectly: "바로 Brief 생성",
            referenceSearchTooltip: "Google Images에서 검색",
            referenceGuidance: "레퍼런스를 탐색하거나 바로 Brief를 생성하세요",
            referenceCategoryVisual: "비주얼",
            referenceCategoryExperience: "경험",
            referenceCategoryImplementation: "구현",
            referenceFeedbackPlaceholder: "피드백을 입력하세요 (예: '이런 느낌이 아니라...')",
            referenceRequestMessage: "레퍼런스 이미지를 보여주세요.",
            jsonNotFoundError: "응답에서 JSON을 찾을 수 없습니다",
            jsonParseFailedFormat: { s in "JSON 파싱 실패: \(s)…" }
        ),
        designSession: DesignSession(
            newSession: "새 설계 세션",
            noSessionsTitle: "설계 세션 없음",
            noSessionsDescription: "새 설계 세션을 생성하여 시작하세요.",
            taskDescriptionLabel: "작업 지시서를 설명하세요",
            newSessionTitle: "새 설계 세션",
            apiCallsHelp: "API 호출 수",
            tokensHelp: "예상 토큰",
            filterAll: "전체",
            queuedFormat: { pos in "대기 #\(pos)" },
            statusPlanning: "계획 중",
            statusReviewing: "검토 중",
            statusExecuting: "실행 중",
            statusCompleted: "완료",
            statusFailed: "실패"
        ),
        settings: Settings(
            profile: "프로필",
            general: "일반",
            agentsTab: "에이전트",
            advancedSection: "설정",
            aboutYou: "사용자 정보",
            profileDescription: "이 정보는 AI 협업 컨텍스트와 소유자 표시에 사용됩니다.",
            namePlaceholder: "예: 미니",
            titlePlaceholder: "예: CEO, 파운더, 프로덕트 리드",
            bioPlaceholder: "AI 에이전트가 이해할 수 있는 배경과 업무 맥락",
            coreAITeam: "핵심 AI 팀",
            coreAITeamDescription: "간단한 설정으로 시작하세요. 모델, 프롬프트, 추가 역할은 고급 설정에서 조정할 수 있습니다.",
            openAdvanced: "고급 설정 열기",
            designDescription: "설계 실행을 계획, 위임, 조율합니다.",
            fallbackDescription: "기본 디렉터가 사용 불가할 때 백업으로 사용됩니다.",
            stepAgentDescription: "디렉터가 할당한 개별 스텝을 실행합니다.",
            languageTitle: "언어",
            languageDescription: "앱 인터페이스의 표시 언어를 선택합니다.",
            cliMaxRuntime: "CLI 최대 실행 시간",
            cliMaxRuntimeDescription: "단일 AI 에이전트 실행의 최대 제한 시간.",
            cliIdleTimeout: "CLI 유휴 타임아웃",
            cliIdleTimeoutDescription: "이 시간(초) 동안 새로운 출력이 없으면 CLI 프로세스를 종료합니다.",
            seconds: "초",
            secondsUnit: "초",
            minRuntimeWarning: "최소 최대 실행 시간은 30초입니다.",
            streamInterruptWarning: "180초 미만 값은 긴 스트리밍 실행을 중단시킬 수 있습니다.",
            minIdleTimeoutWarning: "최소 유휴 타임아웃은 30초입니다.",
            shortIdleWarning: "짧은 유휴 타임아웃은 생각 중인 에이전트를 중단시킬 수 있습니다.",
            elaborationConcurrency: "동시 Elaboration 수",
            elaborationConcurrencyDescription: "동시에 상세화하는 최대 항목 수. 높을수록 빠르지만 API 속도 제한에 걸릴 수 있습니다.",
            elaborationConcurrencyWarning: "일부 프로바이더에서 속도 제한이 발생할 수 있습니다.",
            elaborationConcurrencyUnit: "개",
            resetAgents: "에이전트 초기화",
            resetAgentsDescription: "모든 에이전트를 삭제하고 기본값으로 다시 생성합니다.",
            resetComplete: "초기화 완료",
            resetConfirmMessage: "모든 에이전트가 삭제되고 기본값으로 다시 생성됩니다. 계속하시겠습니까?",
            agentAddedFormat: { name in "\(name)이(가) 핵심 AI 팀에 추가됨" },
            agentAddFailedFormat: { name in "\(name) 추가 실패" }
        ),
        agents: Agents(
            refreshModels: "모델 새로고침",
            fetching: "가져오는 중...",
            fetchingCatalog: "카탈로그 가져오는 중...",
            addAgent: "에이전트 추가",
            noAgentsTitle: "설정된 에이전트 없음",
            noAgentsDescription: "미팅에서 협업할 AI 에이전트를 추가하세요.",
            editAgent: "에이전트 편집",
            newAgent: "새 에이전트",
            tier: "등급",
            provider: "프로바이더",
            model: "모델",
            selectModel: "모델 선택",
            instruction: "지시사항",
            instructionDescription: "이 에이전트의 전문 분야를 설명하세요. 디렉터가 이를 참고하여 각 작업에 최적의 에이전트를 배정합니다.",
            instructionPlaceholder: "예: 프론트엔드 전문가, React UI와 반응형 디자인에 강함",
            designTierDesc: "설계를 계획, 위임, 조율하는 주 오케스트레이터.",
            fallbackTierDesc: "주 디렉터가 사용 불가할 때 사용되는 백업 디렉터.",
            stepTierDesc: "디렉터가 할당한 개별 설계 스텝을 실행.",
            createFailed: "에이전트 생성 실패",
            updateFailed: "에이전트 업데이트 실패",
            deleteFailed: "에이전트 삭제 실패",
            agentCountFormat: { count in "\(count)개 에이전트" },
            validatingFormat: { provider, current, total in "\(provider) 검증 중 \(current)/\(total)" }
        ),
        skills: Skills(
            addSkill: "스킬 추가",
            noSkillsTitle: "설정된 스킬 없음",
            noSkillsDescription: "스킬은 첫 실행 시 자동 생성됩니다. 앱을 재시작하거나 수동으로 추가하세요.",
            editSkill: "스킬 편집",
            newSkill: "새 스킬",
            role: "역할",
            skillName: "스킬 이름",
            description_: "설명",
            createFailed: "스킬 생성 실패",
            updateFailed: "스킬 업데이트 실패",
            deleteFailed: "스킬 삭제 실패",
            skillCountFormat: { count in "\(count)개 스킬" }
        )
    )
}
