import Foundation

// MARK: - Idea Message Thread Models

enum IdeaMessageRole: String, Codable {
    case user
    case design = "director"
}

struct IdeaMessage: Identifiable, Codable {
    let id: UUID
    var role: IdeaMessageRole
    var content: String
    var experts: [IdeaExpert]?
    var summary: String?
    var modelName: String?
    var fallbackInfo: String?
    var createdAt: Date
    /// Design 컨텍스트 압축 요약 — nil이면 일반 메시지, 값이 있으면 압축 요약 메시지
    var contextSummary: String?
    /// Synthesis에서 추출된 Work Graph 엔티티+관계 JSON — convertToRequest 시 Design에 전달
    var graphJSON: String?
    /// Unified reference anchors JSON (from the reference phase, not per-expert)
    var unifiedReferencesJSON: String?
    /// User feedback that triggered this reference regeneration
    var referenceFeedback: String?

    init(
        id: UUID = UUID(),
        role: IdeaMessageRole,
        content: String,
        experts: [IdeaExpert]? = nil,
        summary: String? = nil,
        modelName: String? = nil,
        fallbackInfo: String? = nil,
        createdAt: Date = Date(),
        contextSummary: String? = nil,
        graphJSON: String? = nil,
        unifiedReferencesJSON: String? = nil,
        referenceFeedback: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.experts = experts
        self.summary = summary
        self.modelName = modelName
        self.fallbackInfo = fallbackInfo
        self.createdAt = createdAt
        self.contextSummary = contextSummary
        self.graphJSON = graphJSON
        self.unifiedReferencesJSON = unifiedReferencesJSON
        self.referenceFeedback = referenceFeedback
    }
}

struct IdeaExpert: Identifiable, Codable {
    let id: UUID
    var name: String
    var role: String
    var opinion: String
    var modelName: String?
    var agentId: String?
    var fallbackInfo: String?
    var isLoading: Bool
    var errorMessage: String?
    var focus: String?
    var followUpMessages: [IdeaExpertFollowUp]?
    /// 스트리밍 중 누적 텍스트 — 완료되면 nil로 초기화됨
    var partialOpinion: String?
    /// Expert가 초기 분석에서 제안한 entity JSON (SynthesisEntity 배열) — Work Graph progressive building용
    var entitiesJSON: String?
    /// Expert가 초기 분석에서 제안한 reference anchors JSON (ParsedReference 배열)
    var referencesJSON: String?
    /// AI execution limitations identified by this expert (JSON array)
    var limitationsJSON: String?

    init(
        id: UUID = UUID(),
        name: String,
        role: String,
        opinion: String,
        modelName: String? = nil,
        agentId: String? = nil,
        fallbackInfo: String? = nil,
        isLoading: Bool = false,
        errorMessage: String? = nil,
        focus: String? = nil,
        followUpMessages: [IdeaExpertFollowUp]? = nil,
        partialOpinion: String? = nil,
        entitiesJSON: String? = nil,
        referencesJSON: String? = nil,
        limitationsJSON: String? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.opinion = opinion
        self.modelName = modelName
        self.agentId = agentId
        self.fallbackInfo = fallbackInfo
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.focus = focus
        self.followUpMessages = followUpMessages
        self.partialOpinion = partialOpinion
        self.entitiesJSON = entitiesJSON
        self.referencesJSON = referencesJSON
        self.limitationsJSON = limitationsJSON
    }
}

// MARK: - Expert Follow-up Conversation

enum ExpertFollowUpRole: String, Codable {
    case user
    case expert
}

struct IdeaExpertFollowUp: Identifiable, Codable {
    let id: UUID
    var role: ExpertFollowUpRole
    var content: String
    var createdAt: Date
    /// Model used to generate this reply (nil for user messages or legacy data)
    var modelName: String?

    init(
        id: UUID = UUID(),
        role: ExpertFollowUpRole,
        content: String,
        modelName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.modelName = modelName
        self.createdAt = createdAt
    }
}

// MARK: - LLM Response Parsing

// MARK: - Synthesis Work Graph Extraction

struct SynthesisEntity: Codable {
    let name: String
    let type: String       // "screen", "data-model", "api", "flow", "component"
    let description: String
}

struct SynthesisRelationship: Codable {
    let sourceName: String
    let targetName: String
    let relationType: String  // depends_on, navigates_to, uses, refines, replaces
}

struct SynthesisReferenceAnchor: Codable {
    let category: String       // "visual", "experience", "implementation"
    let productName: String
    let aspect: String
}

// MARK: - Reference Image Models

enum ReferenceCategory: String, Codable, CaseIterable {
    case visual, experience, implementation
}

enum ReferencePhase: String, Codable {
    case exploration
    case elaboration
}

struct ReferenceImage: Identifiable, Codable {
    let id: UUID
    var category: ReferenceCategory
    var productName: String
    var aspect: String
    var searchURL: String?
    var searchQuery: String?
    var isConfirmed: Bool
    var addedDuring: ReferencePhase

    init(
        id: UUID = UUID(),
        category: ReferenceCategory,
        productName: String,
        aspect: String,
        searchURL: String? = nil,
        searchQuery: String? = nil,
        isConfirmed: Bool = true,
        addedDuring: ReferencePhase = .exploration
    ) {
        self.id = id
        self.category = category
        self.productName = productName
        self.aspect = aspect
        self.searchURL = searchURL
        self.searchQuery = searchQuery
        self.isConfirmed = isConfirmed
        self.addedDuring = addedDuring
    }
}

/// Design planning response: assigns expert roles without opinions.
/// The actual expert opinions are generated by Step Agents in parallel.
struct IdeaPlanningResponse: Codable {
    let content: String
    let experts: [ExpertAssignment]

    struct ExpertAssignment: Codable {
        let name: String
        let role: String
        let focus: String
        let agentId: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            role = try c.decode(String.self, forKey: .role)
            focus = try c.decode(String.self, forKey: .focus)
            agentId = try c.decodeIfPresent(String.self, forKey: .agentId)
        }
    }
}
