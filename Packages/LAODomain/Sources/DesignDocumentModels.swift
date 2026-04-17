import Foundation

// MARK: - JSONValue (type-safe JSON primitive for domain layer)

/// Sendable-safe, Codable enum for arbitrary JSON values in design document specs.
public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b):   try container.encode(b)
        case .null:          try container.encodeNil()
        case .array(let a):  try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

// MARK: - DesignDocument

/// Structured design document optimized for AI development tool consumption.
/// Generated from a completed DesignWorkflow by DesignDocumentConverter.
public struct DesignDocument: Codable, Sendable {
    public let meta: DesignMeta
    public let screens: [DesignScreenSpec]
    public let dataModels: [DesignDataModelSpec]
    public let apiEndpoints: [DesignAPISpec]
    public let userFlows: [DesignUserFlowSpec]
    public let crossReferences: [DesignCrossReference]
    public let implementationOrder: [[String]]  // groups of spec IDs for parallel implementation
    public let globalStateDesign: GlobalStateDesign?

    public init(
        meta: DesignMeta,
        screens: [DesignScreenSpec],
        dataModels: [DesignDataModelSpec],
        apiEndpoints: [DesignAPISpec],
        userFlows: [DesignUserFlowSpec],
        crossReferences: [DesignCrossReference],
        implementationOrder: [[String]],
        globalStateDesign: GlobalStateDesign? = nil
    ) {
        self.meta = meta
        self.screens = screens
        self.dataModels = dataModels
        self.apiEndpoints = apiEndpoints
        self.userFlows = userFlows
        self.crossReferences = crossReferences
        self.implementationOrder = implementationOrder
        self.globalStateDesign = globalStateDesign
    }
}

// MARK: - DesignMeta

public struct DesignMeta: Codable, Sendable {
    public let version: String
    public let projectName: String
    public let projectType: String
    public let generatedAt: Date
    public let sourceRequestId: String
    public let summary: String
    /// Tech stack detected or configured for this project (e.g. language, framework, platform, database).
    public let techStack: [String: String]?
    /// Reference anchors from exploration — existing products whose visual/experiential patterns guide this project.
    public let referenceAnchors: [ReferenceAnchorOutput]?

    public init(
        version: String = "1.0",
        projectName: String,
        projectType: String,
        generatedAt: Date = Date(),
        sourceRequestId: String,
        summary: String,
        techStack: [String: String]? = nil,
        referenceAnchors: [ReferenceAnchorOutput]? = nil
    ) {
        self.version = version
        self.projectName = projectName
        self.projectType = projectType
        self.generatedAt = generatedAt
        self.sourceRequestId = sourceRequestId
        self.summary = summary
        self.techStack = techStack
        self.referenceAnchors = referenceAnchors
    }
}

// MARK: - ReferenceAnchorOutput

/// Reference anchor data included in design document output for MCP delivery.
public struct ReferenceAnchorOutput: Codable, Sendable {
    public let category: String
    public let productName: String
    public let aspect: String
    public let searchURL: String?

    public init(category: String, productName: String, aspect: String, searchURL: String? = nil) {
        self.category = category
        self.productName = productName
        self.aspect = aspect
        self.searchURL = searchURL
    }
}

// MARK: - DesignScreenSpec

public struct DesignScreenSpec: Codable, Sendable, Identifiable {
    public let id: String               // slug: "screen-login"
    public let name: String
    public let purpose: String
    public let entryCondition: String
    public let exitTo: [String]          // screen slugs
    public let components: [JSONValue]   // nested component tree
    public let interactions: [JSONValue]
    public let states: [String: String]  // state-name → description
    public let edgeCases: [String]
    public let additionalProperties: [String: JSONValue]

    public init(
        id: String, name: String, purpose: String = "", entryCondition: String = "",
        exitTo: [String] = [], components: [JSONValue] = [], interactions: [JSONValue] = [],
        states: [String: String] = [:], edgeCases: [String] = [],
        additionalProperties: [String: JSONValue] = [:]
    ) {
        self.id = id; self.name = name; self.purpose = purpose
        self.entryCondition = entryCondition; self.exitTo = exitTo
        self.components = components; self.interactions = interactions
        self.states = states; self.edgeCases = edgeCases
        self.additionalProperties = additionalProperties
    }
}

// MARK: - DesignDataModelSpec

public struct DesignFieldSpec: Codable, Sendable {
    public let name: String
    public let type: String
    public let required: Bool
    public let description: String

    public init(name: String, type: String, required: Bool = false, description: String = "") {
        self.name = name; self.type = type; self.required = required; self.description = description
    }
}

public struct DesignRelationshipSpec: Codable, Sendable {
    public let targetEntity: String
    public let type: String              // "one-to-one", "one-to-many", "many-to-many"
    public let description: String

    public init(targetEntity: String, type: String, description: String = "") {
        self.targetEntity = targetEntity; self.type = type; self.description = description
    }
}

public struct DesignDataModelSpec: Codable, Sendable, Identifiable {
    public let id: String               // slug: "model-user"
    public let name: String
    public let description: String
    public let fields: [DesignFieldSpec]
    public let relationships: [DesignRelationshipSpec]
    public let indexes: [JSONValue]
    public let businessRules: [String]
    public let additionalProperties: [String: JSONValue]

    public init(
        id: String, name: String, description: String = "",
        fields: [DesignFieldSpec] = [], relationships: [DesignRelationshipSpec] = [],
        indexes: [JSONValue] = [], businessRules: [String] = [],
        additionalProperties: [String: JSONValue] = [:]
    ) {
        self.id = id; self.name = name; self.description = description
        self.fields = fields; self.relationships = relationships
        self.indexes = indexes; self.businessRules = businessRules
        self.additionalProperties = additionalProperties
    }
}

// MARK: - DesignAPISpec

public struct DesignParameterSpec: Codable, Sendable {
    public let name: String
    public let location: String          // "path", "query", "header"
    public let type: String
    public let required: Bool
    public let description: String

    public init(name: String, location: String, type: String, required: Bool = false, description: String = "") {
        self.name = name; self.location = location; self.type = type
        self.required = required; self.description = description
    }

    private enum CodingKeys: String, CodingKey {
        case name, location = "in", type, required, description
    }
}

public struct DesignErrorResponseSpec: Codable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code; self.message = message
    }
}

public struct DesignAPISpec: Codable, Sendable, Identifiable {
    public let id: String               // slug: "api-get-user-posts"
    public let name: String
    public let method: String
    public let path: String
    public let description: String
    public let parameters: [DesignParameterSpec]
    public let requestBody: JSONValue?
    public let response: JSONValue?
    public let errorResponses: [DesignErrorResponseSpec]
    public let auth: String
    public let additionalProperties: [String: JSONValue]

    public init(
        id: String, name: String, method: String = "", path: String = "",
        description: String = "", parameters: [DesignParameterSpec] = [],
        requestBody: JSONValue? = nil, response: JSONValue? = nil,
        errorResponses: [DesignErrorResponseSpec] = [], auth: String = "",
        additionalProperties: [String: JSONValue] = [:]
    ) {
        self.id = id; self.name = name; self.method = method; self.path = path
        self.description = description; self.parameters = parameters
        self.requestBody = requestBody; self.response = response
        self.errorResponses = errorResponses; self.auth = auth
        self.additionalProperties = additionalProperties
    }
}

// MARK: - DesignUserFlowSpec

public struct DesignFlowStep: Codable, Sendable {
    public let order: Int
    public let actor: String
    public let action: String
    public let screenId: String?

    public init(order: Int, actor: String, action: String, screenId: String? = nil) {
        self.order = order; self.actor = actor; self.action = action; self.screenId = screenId
    }
}

public struct DesignDecisionPoint: Codable, Sendable {
    public let condition: String
    public let yes: String
    public let no: String

    public init(condition: String, yes: String, no: String) {
        self.condition = condition; self.yes = yes; self.no = no
    }
}

public struct DesignErrorPath: Codable, Sendable {
    public let atStep: Int
    public let error: String
    public let handling: String

    public init(atStep: Int, error: String, handling: String) {
        self.atStep = atStep; self.error = error; self.handling = handling
    }
}

public struct DesignUserFlowSpec: Codable, Sendable, Identifiable {
    public let id: String               // slug: "flow-onboarding"
    public let name: String
    public let trigger: String
    public let steps: [DesignFlowStep]
    public let decisionPoints: [DesignDecisionPoint]
    public let successOutcome: String
    public let errorPaths: [DesignErrorPath]
    public let relatedScreens: [String]  // screen slugs
    public let relatedAPIs: [String]     // API slugs
    public let additionalProperties: [String: JSONValue]

    public init(
        id: String, name: String, trigger: String = "",
        steps: [DesignFlowStep] = [], decisionPoints: [DesignDecisionPoint] = [],
        successOutcome: String = "", errorPaths: [DesignErrorPath] = [],
        relatedScreens: [String] = [], relatedAPIs: [String] = [],
        additionalProperties: [String: JSONValue] = [:]
    ) {
        self.id = id; self.name = name; self.trigger = trigger
        self.steps = steps; self.decisionPoints = decisionPoints
        self.successOutcome = successOutcome; self.errorPaths = errorPaths
        self.relatedScreens = relatedScreens; self.relatedAPIs = relatedAPIs
        self.additionalProperties = additionalProperties
    }
}

// MARK: - DesignCrossReference

public struct DesignCrossReference: Codable, Sendable {
    public let sourceId: String
    public let targetId: String
    public let relationType: String      // "navigates_to", "depends_on", "uses", "calls"
    public let description: String?

    public init(sourceId: String, targetId: String, relationType: String, description: String? = nil) {
        self.sourceId = sourceId; self.targetId = targetId
        self.relationType = relationType; self.description = description
    }
}

// MARK: - GlobalStateDesign

/// App-wide state management blueprint — the "electrical wiring diagram" for the entire building.
/// Individual screen `states` are room-level switches; this captures the building's main distribution board.
public struct GlobalStateDesign: Codable, Sendable {
    public let stateEntities: [StateEntity]
    public let stateTransitions: [StateTransition]
    public let screenStateMapping: [ScreenStateMapping]

    public init(
        stateEntities: [StateEntity] = [],
        stateTransitions: [StateTransition] = [],
        screenStateMapping: [ScreenStateMapping] = []
    ) {
        self.stateEntities = stateEntities
        self.stateTransitions = stateTransitions
        self.screenStateMapping = screenStateMapping
    }
}

public struct StateEntity: Codable, Sendable {
    public let name: String
    public let type: String              // "global", "feature", "shared"
    public let possibleValues: [String]
    public let persistenceStrategy: String
    public let description: String

    public init(name: String, type: String, possibleValues: [String] = [],
                persistenceStrategy: String = "memory", description: String = "") {
        self.name = name; self.type = type; self.possibleValues = possibleValues
        self.persistenceStrategy = persistenceStrategy; self.description = description
    }
}

public struct StateTransition: Codable, Sendable {
    public let fromState: String
    public let toState: String
    public let trigger: String
    public let sideEffects: [String]

    public init(fromState: String, toState: String, trigger: String, sideEffects: [String] = []) {
        self.fromState = fromState; self.toState = toState
        self.trigger = trigger; self.sideEffects = sideEffects
    }
}

public struct ScreenStateMapping: Codable, Sendable {
    public let screenId: String
    public let requiredStates: [String]
    public let stateEffects: [String]

    public init(screenId: String, requiredStates: [String] = [], stateEffects: [String] = []) {
        self.screenId = screenId; self.requiredStates = requiredStates; self.stateEffects = stateEffects
    }
}

// MARK: - DocumentMeta (shared across all document types)

public struct DocumentMeta: Codable, Sendable {
    public let documentType: String      // "brd", "cps", "design", "plan", "test"
    public let version: String
    public let projectName: String
    public let generatedAt: Date
    public let sourceRequestId: String

    public init(documentType: String, version: String = "1.0", projectName: String,
                generatedAt: Date = Date(), sourceRequestId: String) {
        self.documentType = documentType; self.version = version
        self.projectName = projectName; self.generatedAt = generatedAt
        self.sourceRequestId = sourceRequestId
    }
}

// MARK: - BusinessRequirementsDocument (brd.json)

public struct BusinessRequirementsDocument: Codable, Sendable {
    public let meta: DocumentMeta
    public let problemStatement: String
    public let targetUsers: [TargetUser]
    public let businessObjectives: [String]
    public let successMetrics: [SuccessMetric]
    public let scope: ProjectScope
    public let constraints: [String]
    public let assumptions: [String]
    public let nonFunctionalRequirements: NonFunctionalRequirements

    public init(meta: DocumentMeta, problemStatement: String, targetUsers: [TargetUser] = [],
                businessObjectives: [String] = [], successMetrics: [SuccessMetric] = [],
                scope: ProjectScope = ProjectScope(), constraints: [String] = [],
                assumptions: [String] = [],
                nonFunctionalRequirements: NonFunctionalRequirements = NonFunctionalRequirements()) {
        self.meta = meta; self.problemStatement = problemStatement
        self.targetUsers = targetUsers; self.businessObjectives = businessObjectives
        self.successMetrics = successMetrics; self.scope = scope
        self.constraints = constraints; self.assumptions = assumptions
        self.nonFunctionalRequirements = nonFunctionalRequirements
    }
}

public struct TargetUser: Codable, Sendable {
    public let name: String
    public let description: String
    public let needs: [String]

    public init(name: String, description: String = "", needs: [String] = []) {
        self.name = name; self.description = description; self.needs = needs
    }
}

public struct SuccessMetric: Codable, Sendable {
    public let metric: String
    public let target: String
    public let measurement: String

    public init(metric: String, target: String = "", measurement: String = "") {
        self.metric = metric; self.target = target; self.measurement = measurement
    }
}

public struct ProjectScope: Codable, Sendable {
    public let inScope: [String]
    public let outOfScope: [String]
    public let mvpBoundary: String

    public init(inScope: [String] = [], outOfScope: [String] = [], mvpBoundary: String = "") {
        self.inScope = inScope; self.outOfScope = outOfScope; self.mvpBoundary = mvpBoundary
    }
}

public struct NonFunctionalRequirements: Codable, Sendable {
    public let performance: [String]
    public let security: [String]
    public let accessibility: [String]
    public let scalability: [String]

    public init(performance: [String] = [], security: [String] = [],
                accessibility: [String] = [], scalability: [String] = []) {
        self.performance = performance; self.security = security
        self.accessibility = accessibility; self.scalability = scalability
    }
}

// MARK: - DesignBrief (exploration output — the "what and why" contract before design begins)

public struct DesignBrief: Codable, Sendable {
    public let brd: BusinessRequirementsDocument
    public let synthesisDirection: String
    public let synthesisRationale: String
    public let keyDecisions: [BriefDecisionRecord]
    public let explorationSummary: BriefExplorationSummary
    public let executionContext: ExecutionContext?

    public init(brd: BusinessRequirementsDocument, synthesisDirection: String,
                synthesisRationale: String, keyDecisions: [BriefDecisionRecord] = [],
                explorationSummary: BriefExplorationSummary = BriefExplorationSummary(),
                executionContext: ExecutionContext? = nil) {
        self.brd = brd; self.synthesisDirection = synthesisDirection
        self.synthesisRationale = synthesisRationale; self.keyDecisions = keyDecisions
        self.explorationSummary = explorationSummary
        self.executionContext = executionContext
    }
}

public struct BriefDecisionRecord: Codable, Sendable {
    public let topic: String
    public let chosen: String
    public let alternatives: [String]
    public let rationale: String

    public init(topic: String, chosen: String, alternatives: [String] = [], rationale: String = "") {
        self.topic = topic; self.chosen = chosen
        self.alternatives = alternatives; self.rationale = rationale
    }
}

public struct BriefExplorationSummary: Codable, Sendable {
    public let expertCount: Int
    public let discussionRounds: Int
    public let keyEntities: [String]
    public let referenceAnchorsCount: Int

    public init(expertCount: Int = 0, discussionRounds: Int = 0,
                keyEntities: [String] = [], referenceAnchorsCount: Int = 0) {
        self.expertCount = expertCount; self.discussionRounds = discussionRounds
        self.keyEntities = keyEntities; self.referenceAnchorsCount = referenceAnchorsCount
    }
}

public struct ExecutionLimitation: Codable, Sendable {
    public let area: String
    public let description: String
    public let workaroundHint: String?

    public init(area: String, description: String, workaroundHint: String? = nil) {
        self.area = area; self.description = description
        self.workaroundHint = workaroundHint
    }
}

public struct ExecutionContext: Codable, Sendable {
    public let currentLimitations: [ExecutionLimitation]

    public init(currentLimitations: [ExecutionLimitation] = []) {
        self.currentLimitations = currentLimitations
    }
}

// MARK: - ImplementationPlanDocument (plan.json)

public struct ImplementationPlanDocument: Codable, Sendable {
    public let meta: DocumentMeta
    public let milestones: [Milestone]
    public let mvpScope: MVPScope
    public let phases: [ImplementationPhase]
    public let projectStandards: ProjectStandards
    public let infrastructureNotes: InfrastructureNotes

    public init(meta: DocumentMeta, milestones: [Milestone] = [],
                mvpScope: MVPScope = MVPScope(), phases: [ImplementationPhase] = [],
                projectStandards: ProjectStandards = ProjectStandards(),
                infrastructureNotes: InfrastructureNotes = InfrastructureNotes()) {
        self.meta = meta; self.milestones = milestones; self.mvpScope = mvpScope
        self.phases = phases; self.projectStandards = projectStandards
        self.infrastructureNotes = infrastructureNotes
    }
}

public struct Milestone: Codable, Sendable {
    public let name: String
    public let description: String
    public let specIds: [String]
    public let acceptanceCriteria: [String]

    public init(name: String, description: String = "", specIds: [String] = [],
                acceptanceCriteria: [String] = []) {
        self.name = name; self.description = description
        self.specIds = specIds; self.acceptanceCriteria = acceptanceCriteria
    }
}

public struct MVPScope: Codable, Sendable {
    public let includedSpecIds: [String]
    public let excludedSpecIds: [String]
    public let rationale: String

    public init(includedSpecIds: [String] = [], excludedSpecIds: [String] = [], rationale: String = "") {
        self.includedSpecIds = includedSpecIds; self.excludedSpecIds = excludedSpecIds
        self.rationale = rationale
    }
}

public struct ImplementationPhase: Codable, Sendable {
    public let name: String
    public let specIds: [String]
    public let dependencies: [String]
    public let acceptanceCriteria: [String]

    public init(name: String, specIds: [String] = [], dependencies: [String] = [],
                acceptanceCriteria: [String] = []) {
        self.name = name; self.specIds = specIds
        self.dependencies = dependencies; self.acceptanceCriteria = acceptanceCriteria
    }
}

public struct ProjectStandards: Codable, Sendable {
    public let directoryStructure: String
    public let namingConventions: String
    public let errorHandlingPattern: String
    public let codingStyle: String

    public init(directoryStructure: String = "", namingConventions: String = "",
                errorHandlingPattern: String = "", codingStyle: String = "") {
        self.directoryStructure = directoryStructure; self.namingConventions = namingConventions
        self.errorHandlingPattern = errorHandlingPattern; self.codingStyle = codingStyle
    }
}

public struct InfrastructureNotes: Codable, Sendable {
    public let deployment: String
    public let cicd: String
    public let environment: String
    public let migration: String

    public init(deployment: String = "", cicd: String = "",
                environment: String = "", migration: String = "") {
        self.deployment = deployment; self.cicd = cicd
        self.environment = environment; self.migration = migration
    }
}

// MARK: - TestScenariosDocument (test.json)

public struct TestScenariosDocument: Codable, Sendable {
    public let meta: DocumentMeta
    public let scenarios: [TestScenario]

    public init(meta: DocumentMeta, scenarios: [TestScenario] = []) {
        self.meta = meta; self.scenarios = scenarios
    }
}

public struct TestScenario: Codable, Sendable, Identifiable {
    public let id: String
    public let specId: String            // links to design spec
    public let category: String          // "unit", "integration", "e2e", "edge-case"
    public let name: String
    public let preconditions: [String]
    public let steps: [TestStep]
    public let expectedResult: String
    public let priority: String          // "critical", "important", "nice-to-have"

    public init(id: String, specId: String, category: String, name: String,
                preconditions: [String] = [], steps: [TestStep] = [],
                expectedResult: String = "", priority: String = "important") {
        self.id = id; self.specId = specId; self.category = category; self.name = name
        self.preconditions = preconditions; self.steps = steps
        self.expectedResult = expectedResult; self.priority = priority
    }
}

public struct TestStep: Codable, Sendable {
    public let order: Int
    public let action: String
    public let expectedOutcome: String

    public init(order: Int, action: String, expectedOutcome: String = "") {
        self.order = order; self.action = action; self.expectedOutcome = expectedOutcome
    }
}

// MARK: - ProjectDocumentSet (container for MCP delivery)

/// Complete document set produced by LAO for development AI consumption.
/// All fields are optional — partial sets are valid (e.g. legacy sessions without BRD).
public struct ProjectDocumentSet: Codable, Sendable {
    public let brd: BusinessRequirementsDocument?
    public let design: DesignDocument?
    public let plan: ImplementationPlanDocument?
    public let test: TestScenariosDocument?

    public init(brd: BusinessRequirementsDocument? = nil,
                design: DesignDocument? = nil, plan: ImplementationPlanDocument? = nil,
                test: TestScenariosDocument? = nil) {
        self.brd = brd; self.design = design
        self.plan = plan; self.test = test
    }
}
