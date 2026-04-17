import Foundation
import LAODomain

// MARK: - LAO MCP Server
//
// Stdio-based JSON-RPC 2.0 server implementing the Model Context Protocol.
// Serves DesignDocument data from .lao/docs/ to Claude Code, Codex, etc.
//
// Usage:
//   LAOMCPServer --project-root /path/to/project
//
// Or via Claude Code config (~/.claude.json):
//   { "mcpServers": { "lao": { "type": "stdio", "command": "/path/to/LAOMCPServer", "args": ["--project-root", "/path"] } } }

// MARK: - JSON-RPC Types

struct JSONRPCRequest: Decodable {
    let jsonrpc: String
    let id: JSONRPCId?
    let method: String
    let params: [String: JSONValue]?
}

enum JSONRPCId: Codable, Equatable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            self = .int(0)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let i): try container.encode(i)
        case .string(let s): try container.encode(s)
        }
    }
}

struct JSONRPCResponse: Encodable {
    let jsonrpc: String = "2.0"
    let id: JSONRPCId?
    let result: JSONValue?
    let error: JSONRPCError?

    static func success(id: JSONRPCId?, result: JSONValue) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: result, error: nil)
    }

    static func error(id: JSONRPCId?, code: Int, message: String) -> JSONRPCResponse {
        JSONRPCResponse(id: id, result: nil, error: JSONRPCError(code: code, message: message))
    }
}

struct JSONRPCError: Encodable {
    let code: Int
    let message: String
}

// MARK: - Design Document Store

final class DesignDocumentStore {
    let projectRoot: String
    private var cachedDoc: DesignDocument?
    private var cachedDocSet: ProjectDocumentSet?
    private var lastModified: Date?
    private(set) var bestDesignDir: String? // Directory containing the most recent design.json

    init(projectRoot: String) {
        self.projectRoot = projectRoot
    }

    /// Find and load the most recent design.json from .lao/docs/
    func load() -> DesignDocument? {
        if let cached = cachedDoc { return cached }
        return reload()
    }

    /// Load all available documents from the same directory as design.json
    func loadDocumentSet() -> ProjectDocumentSet? {
        if let cached = cachedDocSet { return cached }
        return reloadDocumentSet()
    }

    func reload() -> DesignDocument? {
        let laoDir = (projectRoot as NSString).appendingPathComponent(".lao")
        let fm = FileManager.default

        guard fm.fileExists(atPath: laoDir) else { return nil }

        // 2-level scan: .lao/{ideaId}/{requestId}/design.json
        var bestPath: String?
        var bestDate: Date?
        var bestDir: String?

        if let ideaDirs = try? fm.contentsOfDirectory(atPath: laoDir) {
            for ideaEntry in ideaDirs {
                guard !ideaEntry.hasPrefix(".") else { continue }
                let ideaDir = (laoDir as NSString).appendingPathComponent(ideaEntry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: ideaDir, isDirectory: &isDir), isDir.boolValue else { continue }

                if let requestDirs = try? fm.contentsOfDirectory(atPath: ideaDir) {
                    for reqEntry in requestDirs {
                        guard !reqEntry.hasPrefix(".") && reqEntry != "references" else { continue }
                        let reqDir = (ideaDir as NSString).appendingPathComponent(reqEntry)
                        let designPath = (reqDir as NSString).appendingPathComponent("design.json")
                        if fm.fileExists(atPath: designPath),
                           let attrs = try? fm.attributesOfItem(atPath: designPath),
                           let modified = attrs[.modificationDate] as? Date {
                            if bestDate == nil || modified > bestDate! {
                                bestPath = designPath
                                bestDate = modified
                                bestDir = reqDir
                            }
                        }
                    }
                }
            }
        }

        guard let path = bestPath,
              let data = fm.contents(atPath: path) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        cachedDoc = try? decoder.decode(DesignDocument.self, from: data)
        lastModified = bestDate
        bestDesignDir = bestDir
        cachedDocSet = nil // Invalidate document set cache
        return cachedDoc
    }

    func reloadDocumentSet() -> ProjectDocumentSet? {
        // Ensure design.json is loaded (which sets bestDesignDir)
        _ = reload()
        guard let dir = bestDesignDir else { return nil }

        let fm = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var brd: BusinessRequirementsDocument?
        var plan: ImplementationPlanDocument?
        var test: TestScenariosDocument?

        if let data = fm.contents(atPath: (dir as NSString).appendingPathComponent("brd.json")) {
            brd = try? decoder.decode(BusinessRequirementsDocument.self, from: data)
        }
        if let data = fm.contents(atPath: (dir as NSString).appendingPathComponent("plan.json")) {
            plan = try? decoder.decode(ImplementationPlanDocument.self, from: data)
        }
        if let data = fm.contents(atPath: (dir as NSString).appendingPathComponent("test.json")) {
            test = try? decoder.decode(TestScenariosDocument.self, from: data)
        }

        cachedDocSet = ProjectDocumentSet(
            brd: brd,
            design: cachedDoc,
            plan: plan,
            test: test
        )
        return cachedDocSet
    }
}

// MARK: - MCP Server

final class MCPServer {
    let store: DesignDocumentStore
    private let encoder: JSONEncoder

    init(store: DesignDocumentStore) {
        self.store = store
        self.encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    func run() {
        // Disable stdout buffering
        setbuf(stdout, nil)

        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }

            guard let data = line.data(using: .utf8) else { continue }

            let decoder = JSONDecoder()
            guard let request = try? decoder.decode(JSONRPCRequest.self, from: data) else {
                send(JSONRPCResponse.error(id: nil, code: -32700, message: "Parse error"))
                continue
            }

            // Notifications (no id) don't require responses
            if request.id == nil {
                handleNotification(request)
                continue
            }

            let response = handleRequest(request)
            send(response)
        }
    }

    // MARK: - Request Dispatch

    private func handleRequest(_ req: JSONRPCRequest) -> JSONRPCResponse {
        switch req.method {
        case "initialize":
            return handleInitialize(req)
        case "resources/list":
            return handleResourcesList(req)
        case "resources/read":
            return handleResourcesRead(req)
        case "tools/list":
            return handleToolsList(req)
        case "tools/call":
            return handleToolsCall(req)
        case "ping":
            return .success(id: req.id, result: .object([:]))
        default:
            return .error(id: req.id, code: -32601, message: "Method not found: \(req.method)")
        }
    }

    private func handleNotification(_ req: JSONRPCRequest) {
        // notifications/initialized — no action needed
        // notifications/cancelled — no action needed
    }

    // MARK: - initialize

    private func handleInitialize(_ req: JSONRPCRequest) -> JSONRPCResponse {
        let result: JSONValue = .object([
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .object([
                "resources": .object([
                    "subscribe": .bool(false),
                    "listChanged": .bool(false)
                ]),
                "tools": .object([
                    "listChanged": .bool(false)
                ])
            ]),
            "serverInfo": .object([
                "name": .string("lao-design"),
                "version": .string("1.0.0")
            ])
        ])
        return .success(id: req.id, result: result)
    }

    // MARK: - resources/list

    private func handleResourcesList(_ req: JSONRPCRequest) -> JSONRPCResponse {
        var resources = [JSONValue]()

        resources.append(makeResource(
            uri: "lao://schema",
            name: "Design Document Schema",
            description: "JSON Schema (Draft 2020-12) describing the design.json format",
            mimeType: "application/schema+json"
        ))
        resources.append(makeResource(
            uri: "lao://design",
            name: "Full Design Specification",
            description: "Complete design document with all screens, models, APIs, and flows",
            mimeType: "application/json"
        ))
        resources.append(makeResource(
            uri: "lao://design/markdown",
            name: "Design Specification (Markdown)",
            description: "Human-readable design document with cross-references",
            mimeType: "text/markdown"
        ))
        resources.append(makeResource(
            uri: "lao://tech-stack",
            name: "Project Tech Stack",
            description: "Technology stack configured for this project (language, framework, platform, database)",
            mimeType: "application/json"
        ))

        // Document set resources
        resources.append(makeResource(
            uri: "lao://brd",
            name: "Business Requirements Document",
            description: "Problem statement, target users, business objectives, scope, and non-functional requirements",
            mimeType: "application/json"
        ))
        resources.append(makeResource(
            uri: "lao://brd/markdown",
            name: "Business Requirements (Markdown)",
            description: "Human-readable business requirements document",
            mimeType: "text/markdown"
        ))
        resources.append(makeResource(
            uri: "lao://plan",
            name: "Implementation Plan",
            description: "Milestones, MVP scope, implementation phases, project standards, and infrastructure notes",
            mimeType: "application/json"
        ))
        resources.append(makeResource(
            uri: "lao://plan/markdown",
            name: "Implementation Plan (Markdown)",
            description: "Human-readable implementation plan with phases and standards",
            mimeType: "text/markdown"
        ))
        resources.append(makeResource(
            uri: "lao://test",
            name: "Test Scenarios",
            description: "All test scenarios derived from design specs (e2e, integration, unit, edge-case)",
            mimeType: "application/json"
        ))
        resources.append(makeResource(
            uri: "lao://test/markdown",
            name: "Test Scenarios (Markdown)",
            description: "Human-readable test scenario document grouped by priority",
            mimeType: "text/markdown"
        ))
        resources.append(makeResource(
            uri: "lao://documents",
            name: "Full Project Document Set",
            description: "All available project documents (BRD, design, plan, test) in a single response",
            mimeType: "application/json"
        ))

        if let doc = store.load() {
            for screen in doc.screens {
                resources.append(makeResource(
                    uri: "lao://screens/\(screen.id)",
                    name: "Screen: \(screen.name)",
                    description: screen.purpose,
                    mimeType: "application/json"
                ))
            }
            for model in doc.dataModels {
                resources.append(makeResource(
                    uri: "lao://models/\(model.id)",
                    name: "Model: \(model.name)",
                    description: model.description,
                    mimeType: "application/json"
                ))
            }
            for api in doc.apiEndpoints {
                resources.append(makeResource(
                    uri: "lao://apis/\(api.id)",
                    name: "API: \(api.name)",
                    description: "\(api.method) \(api.path)",
                    mimeType: "application/json"
                ))
            }
            for flow in doc.userFlows {
                resources.append(makeResource(
                    uri: "lao://flows/\(flow.id)",
                    name: "Flow: \(flow.name)",
                    description: flow.trigger,
                    mimeType: "application/json"
                ))
            }

            // Reference image resources
            if let refs = doc.meta.referenceAnchors, !refs.isEmpty {
                resources.append(makeResource(
                    uri: "lao://references",
                    name: "Reference Images",
                    description: "Visual reference images that define the project's art direction. Read before implementing.",
                    mimeType: "application/json"
                ))
                for ref in refs {
                    if let url = ref.searchURL {
                        resources.append(makeResource(
                            uri: url,
                            name: "\(ref.productName) — \(ref.category)",
                            description: ref.aspect,
                            mimeType: "text/html"
                        ))
                    }
                }
            }
        }

        // Individual test scenario resources
        if let docSet = store.loadDocumentSet(), let testDoc = docSet.test {
            for scenario in testDoc.scenarios {
                resources.append(makeResource(
                    uri: "lao://test/\(scenario.id)",
                    name: "Test: \(scenario.name)",
                    description: "[\(scenario.category)] \(scenario.expectedResult)",
                    mimeType: "application/json"
                ))
            }
        }

        return .success(id: req.id, result: .object([
            "resources": .array(resources)
        ]))
    }

    // MARK: - resources/read

    private func handleResourcesRead(_ req: JSONRPCRequest) -> JSONRPCResponse {
        guard let uri = req.params?["uri"]?.stringValue else {
            return .error(id: req.id, code: -32602, message: "Missing 'uri' parameter")
        }

        // Schema is always available, even without a loaded document
        if uri == "lao://schema" {
            return .success(id: req.id, result: .object([
                "contents": .array([
                    .object([
                        "uri": .string(uri),
                        "mimeType": .string("application/schema+json"),
                        "text": .string(DesignDocumentMarkdownRenderer.designDocumentSchema)
                    ])
                ])
            ]))
        }

        if uri == "lao://tech-stack" {
            if let doc = store.load(), let ts = doc.meta.techStack, !ts.isEmpty {
                let json = encodeToJSON(ts) ?? "{}"
                return .success(id: req.id, result: .object([
                    "contents": .array([
                        .object([
                            "uri": .string(uri),
                            "mimeType": .string("application/json"),
                            "text": .string(json)
                        ])
                    ])
                ]))
            } else {
                return .success(id: req.id, result: .object([
                    "contents": .array([
                        .object([
                            "uri": .string(uri),
                            "mimeType": .string("application/json"),
                            "text": .string("{}")
                        ])
                    ])
                ]))
            }
        }

        // Reference resources
        if uri == "lao://references" {
            if let doc = store.load(), let refs = doc.meta.referenceAnchors, !refs.isEmpty {
                let json = encodeToJSON(refs) ?? "[]"
                return .success(id: req.id, result: .object([
                    "contents": .array([
                        .object([
                            "uri": .string(uri),
                            "mimeType": .string("application/json"),
                            "text": .string(json)
                        ])
                    ])
                ]))
            } else {
                return .success(id: req.id, result: .object([
                    "contents": .array([
                        .object([
                            "uri": .string(uri),
                            "mimeType": .string("application/json"),
                            "text": .string("[]")
                        ])
                    ])
                ]))
            }
        }

        if uri.hasPrefix("lao://references/") {
            let fileName = String(uri.dropFirst("lao://references/".count))
            guard let dir = store.bestDesignDir else {
                return .error(id: req.id, code: -32002, message: "No design document directory found.")
            }
            let filePath = URL(fileURLWithPath: (dir as NSString).appendingPathComponent("references/\(fileName)"))
            if let data = try? Data(contentsOf: filePath) {
                return .success(id: req.id, result: .object([
                    "contents": .array([
                        .object([
                            "uri": .string(uri),
                            "mimeType": .string("image/png"),
                            "blob": .string(data.base64EncodedString())
                        ])
                    ])
                ]))
            } else {
                return .error(id: req.id, code: -32002, message: "Reference image not found: \(fileName)")
            }
        }

        // Document set resources (available even without design.json loaded)
        if let resolved = resolveDocumentSetResource(uri: uri) {
            return .success(id: req.id, result: .object([
                "contents": .array([
                    .object([
                        "uri": .string(uri),
                        "mimeType": .string(resolved.1),
                        "text": .string(resolved.0)
                    ])
                ])
            ]))
        }

        guard let doc = store.load() else {
            return .error(id: req.id, code: -32002, message: "No design document found. Run a Design workflow first.")
        }

        let content: (String, String)? // (text, mimeType)

        switch uri {
        case "lao://design":
            content = encodeToJSON(doc).map { ($0, "application/json") }

        case "lao://design/markdown":
            let md = DesignDocumentMarkdownRenderer.render(doc)
            content = (md, "text/markdown")

        default:
            content = resolveSpecResource(uri: uri, doc: doc)
        }

        guard let (text, mimeType) = content else {
            return .error(id: req.id, code: -32002, message: "Resource not found: \(uri)")
        }

        return .success(id: req.id, result: .object([
            "contents": .array([
                .object([
                    "uri": .string(uri),
                    "mimeType": .string(mimeType),
                    "text": .string(text)
                ])
            ])
        ]))
    }

    private func resolveSpecResource(uri: String, doc: DesignDocument) -> (String, String)? {
        let parts = uri.replacingOccurrences(of: "lao://", with: "").split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let category = String(parts[0])
        let specId = String(parts[1])

        switch category {
        case "screens":
            guard let screen = doc.screens.first(where: { $0.id == specId }) else { return nil }
            return encodeToJSON(screen).map { ($0, "application/json") }
        case "models":
            guard let model = doc.dataModels.first(where: { $0.id == specId }) else { return nil }
            return encodeToJSON(model).map { ($0, "application/json") }
        case "apis":
            guard let api = doc.apiEndpoints.first(where: { $0.id == specId }) else { return nil }
            return encodeToJSON(api).map { ($0, "application/json") }
        case "flows":
            guard let flow = doc.userFlows.first(where: { $0.id == specId }) else { return nil }
            return encodeToJSON(flow).map { ($0, "application/json") }
        default:
            return nil
        }
    }

    // MARK: - Document Set Resource Resolution

    private func resolveDocumentSetResource(uri: String) -> (String, String)? {
        let docSet = store.loadDocumentSet()

        switch uri {
        case "lao://brd":
            guard let brd = docSet?.brd else { return nil }
            return encodeToJSON(brd).map { ($0, "application/json") }
        case "lao://brd/markdown":
            guard let brd = docSet?.brd else { return nil }
            return (BRDMarkdownRenderer.render(brd), "text/markdown")
        case "lao://plan":
            guard let plan = docSet?.plan else { return nil }
            return encodeToJSON(plan).map { ($0, "application/json") }
        case "lao://plan/markdown":
            guard let plan = docSet?.plan else { return nil }
            return (PlanMarkdownRenderer.render(plan), "text/markdown")
        case "lao://test":
            guard let test = docSet?.test else { return nil }
            return encodeToJSON(test).map { ($0, "application/json") }
        case "lao://test/markdown":
            guard let test = docSet?.test else { return nil }
            return (TestMarkdownRenderer.render(test), "text/markdown")
        case "lao://documents":
            guard let set = docSet else { return nil }
            return encodeToJSON(set).map { ($0, "application/json") }
        default:
            // Check for individual test scenario: lao://test/{id}
            if uri.hasPrefix("lao://test/"), uri != "lao://test/markdown" {
                let testId = String(uri.dropFirst("lao://test/".count))
                guard let test = docSet?.test,
                      let scenario = test.scenarios.first(where: { $0.id == testId }) else { return nil }
                return encodeToJSON(scenario).map { ($0, "application/json") }
            }
            return nil
        }
    }

    // MARK: - tools/list

    private func handleToolsList(_ req: JSONRPCRequest) -> JSONRPCResponse {
        let tools: [JSONValue] = [
            .object([
                "name": .string("get_implementation_plan"),
                "description": .string("Get the recommended implementation order for building this project. Returns groups of spec IDs that can be built in parallel."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                    "required": .array([])
                ])
            ]),
            .object([
                "name": .string("get_related_specs"),
                "description": .string("Given a spec ID (e.g. screen-login, model-user), returns all related specs across all categories via cross-references."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "spec_id": .object([
                            "type": .string("string"),
                            "description": .string("The spec ID to find relations for (e.g. 'screen-login', 'model-user')")
                        ])
                    ]),
                    "required": .array([.string("spec_id")])
                ])
            ]),
            .object([
                "name": .string("search_specs"),
                "description": .string("Search across all specs (screens, models, APIs, flows) by keyword. Returns matching spec summaries."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Search keyword to match against spec names, descriptions, and content")
                        ])
                    ]),
                    "required": .array([.string("query")])
                ])
            ]),
            .object([
                "name": .string("get_implementation_context"),
                "description": .string("Get rich implementation context for a specific spec. Returns the spec itself, all related specs, tech stack, and implementation notes — everything needed to implement this item."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "spec_id": .object([
                            "type": .string("string"),
                            "description": .string("The spec ID to get context for (e.g. 'screen-login', 'model-user', 'api-get-posts')")
                        ])
                    ]),
                    "required": .array([.string("spec_id")])
                ])
            ]),
            .object([
                "name": .string("get_project_context"),
                "description": .string("Get high-level project context: BRD problem definition, tech stack, and MVP scope. Use before starting implementation to understand the big picture."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                    "required": .array([])
                ])
            ]),
            .object([
                "name": .string("get_test_scenarios"),
                "description": .string("Get test scenarios, optionally filtered by spec ID. Returns test cases derived from the design document."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "spec_id": .object([
                            "type": .string("string"),
                            "description": .string("Optional spec ID to filter scenarios (e.g. 'screen-login', 'api-get-users'). Omit for all scenarios.")
                        ])
                    ]),
                    "required": .array([])
                ])
            ]),
            .object([
                "name": .string("get_milestone_plan"),
                "description": .string("Get the implementation plan: milestones, phases, MVP scope, project standards, and infrastructure notes."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                    "required": .array([])
                ])
            ]),
            .object([
                "name": .string("reload_documents"),
                "description": .string("Reload all project documents (design, BRD, plan, test) from disk. Use after the Design workflow exports new specs."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                    "required": .array([])
                ])
            ]),
            .object([
                "name": .string("reload_design"),
                "description": .string("Reload the design document from disk. Use after the Design workflow exports new specs. (Alias for reload_documents)"),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object([:]),
                    "required": .array([])
                ])
            ])
        ]

        return .success(id: req.id, result: .object(["tools": .array(tools)]))
    }

    // MARK: - tools/call

    private func handleToolsCall(_ req: JSONRPCRequest) -> JSONRPCResponse {
        guard let toolName = req.params?["name"]?.stringValue else {
            return .error(id: req.id, code: -32602, message: "Missing 'name' parameter")
        }
        let arguments = req.params?["arguments"]

        switch toolName {
        case "get_implementation_plan":
            return toolGetImplementationPlan(id: req.id)
        case "get_related_specs":
            let specId: String
            if case .object(let args) = arguments, let id = args["spec_id"]?.stringValue {
                specId = id
            } else {
                return toolError(id: req.id, message: "Missing 'spec_id' argument")
            }
            return toolGetRelatedSpecs(id: req.id, specId: specId)
        case "search_specs":
            let query: String
            if case .object(let args) = arguments, let q = args["query"]?.stringValue {
                query = q
            } else {
                return toolError(id: req.id, message: "Missing 'query' argument")
            }
            return toolSearchSpecs(id: req.id, query: query)
        case "get_implementation_context":
            let specId: String
            if case .object(let args) = arguments, let id = args["spec_id"]?.stringValue {
                specId = id
            } else {
                return toolError(id: req.id, message: "Missing 'spec_id' argument")
            }
            return toolGetImplementationContext(id: req.id, specId: specId)
        case "get_project_context":
            return toolGetProjectContext(id: req.id)
        case "get_test_scenarios":
            let specId: String?
            if case .object(let args) = arguments, let id = args["spec_id"]?.stringValue {
                specId = id
            } else {
                specId = nil
            }
            return toolGetTestScenarios(id: req.id, specId: specId)
        case "get_milestone_plan":
            return toolGetMilestonePlan(id: req.id)
        case "reload_documents", "reload_design":
            return toolReloadDocuments(id: req.id)
        default:
            return toolError(id: req.id, message: "Unknown tool: \(toolName)")
        }
    }

    // MARK: - Tool Implementations

    private func toolGetImplementationPlan(id: JSONRPCId?) -> JSONRPCResponse {
        guard let doc = store.load() else {
            return toolError(id: id, message: "No design document loaded")
        }

        var text = "# Implementation Order\n\n"
        for (i, group) in doc.implementationOrder.enumerated() {
            text += "## Group \(i + 1) (parallel)\n"
            for specId in group {
                let label = specLabel(specId, doc: doc)
                text += "- \(specId): \(label)\n"
            }
            text += "\n"
        }

        return toolResult(id: id, text: text)
    }

    private func toolGetRelatedSpecs(id: JSONRPCId?, specId: String) -> JSONRPCResponse {
        guard let doc = store.load() else {
            return toolError(id: id, message: "No design document loaded")
        }

        let related = doc.crossReferences.filter { $0.sourceId == specId || $0.targetId == specId }

        if related.isEmpty {
            return toolResult(id: id, text: "No cross-references found for '\(specId)'")
        }

        var text = "# Related specs for \(specId)\n\n"
        for ref in related {
            let otherId = ref.sourceId == specId ? ref.targetId : ref.sourceId
            let direction = ref.sourceId == specId ? "→" : "←"
            let rel = ref.relationType.replacingOccurrences(of: "_", with: " ")
            let label = specLabel(otherId, doc: doc)
            text += "- \(direction) \(rel) **\(otherId)**: \(label)\n"
        }

        return toolResult(id: id, text: text)
    }

    private func toolSearchSpecs(id: JSONRPCId?, query: String) -> JSONRPCResponse {
        guard let doc = store.load() else {
            return toolError(id: id, message: "No design document loaded")
        }

        let q = query.lowercased()
        var results = [String]()

        for s in doc.screens where matches(s.name, s.purpose, s.id, query: q) {
            results.append("[\(s.id)] Screen: \(s.name) — \(s.purpose)")
        }
        for m in doc.dataModels where matches(m.name, m.description, m.id, query: q) {
            results.append("[\(m.id)] Model: \(m.name) — \(m.description)")
        }
        for a in doc.apiEndpoints where matches(a.name, a.description, a.id, a.path, query: q) {
            results.append("[\(a.id)] API: \(a.method) \(a.path) — \(a.name)")
        }
        for f in doc.userFlows where matches(f.name, f.trigger, f.id, query: q) {
            results.append("[\(f.id)] Flow: \(f.name) — \(f.trigger)")
        }

        // Search in document set
        let docSet = store.loadDocumentSet()
        if let brd = docSet?.brd {
            if brd.problemStatement.lowercased().contains(q) {
                results.append("[BRD] Problem: \(String(brd.problemStatement.prefix(100)))")
            }
            for obj in brd.businessObjectives where obj.lowercased().contains(q) {
                results.append("[BRD] Objective: \(obj)")
            }
            for user in brd.targetUsers where matches(user.name, user.description, query: q) {
                results.append("[BRD] Target User: \(user.name) — \(user.description)")
            }
        }
        if let test = docSet?.test {
            for scenario in test.scenarios where matches(scenario.name, scenario.expectedResult, scenario.id, query: q) {
                results.append("[Test:\(scenario.id)] \(scenario.name) — \(scenario.expectedResult)")
            }
        }

        if results.isEmpty {
            return toolResult(id: id, text: "No specs matching '\(query)'")
        }

        return toolResult(id: id, text: "# Search results for '\(query)'\n\n" + results.map { "- \($0)" }.joined(separator: "\n"))
    }

    private func toolGetImplementationContext(id: JSONRPCId?, specId: String) -> JSONRPCResponse {
        guard let doc = store.load() else {
            return toolError(id: id, message: "No design document loaded")
        }

        // 1. Find the spec itself
        var specJSON: String?
        var specType = ""
        var specName = ""
        if let s = doc.screens.first(where: { $0.id == specId }) {
            specJSON = encodeToJSON(s); specType = "Screen"; specName = s.name
        } else if let m = doc.dataModels.first(where: { $0.id == specId }) {
            specJSON = encodeToJSON(m); specType = "Data Model"; specName = m.name
        } else if let a = doc.apiEndpoints.first(where: { $0.id == specId }) {
            specJSON = encodeToJSON(a); specType = "API"; specName = a.name
        } else if let f = doc.userFlows.first(where: { $0.id == specId }) {
            specJSON = encodeToJSON(f); specType = "User Flow"; specName = f.name
        }

        guard let json = specJSON else {
            return toolError(id: id, message: "Spec not found: \(specId)")
        }

        var text = "# Implementation Context: \(specName) (\(specType))\n\n"

        // 2. Tech Stack
        if let ts = doc.meta.techStack, !ts.isEmpty {
            text += "## Tech Stack\n\n"
            for (key, value) in ts.sorted(by: { $0.key < $1.key }) {
                text += "- **\(key)**: \(value)\n"
            }
            text += "\n"
        }

        // 3. The spec itself
        text += "## Spec\n\n```json\n\(json)\n```\n\n"

        // 4. Related specs (cross-references)
        let related = doc.crossReferences.filter { $0.sourceId == specId || $0.targetId == specId }
        if !related.isEmpty {
            text += "## Related Specs\n\n"
            for ref in related {
                let otherId = ref.sourceId == specId ? ref.targetId : ref.sourceId
                let direction = ref.sourceId == specId ? "→" : "←"
                let rel = ref.relationType.replacingOccurrences(of: "_", with: " ")
                let label = specLabel(otherId, doc: doc)

                // Include the related spec's JSON for full context
                var relatedJSON: String?
                if let s = doc.screens.first(where: { $0.id == otherId }) { relatedJSON = encodeToJSON(s) }
                else if let m = doc.dataModels.first(where: { $0.id == otherId }) { relatedJSON = encodeToJSON(m) }
                else if let a = doc.apiEndpoints.first(where: { $0.id == otherId }) { relatedJSON = encodeToJSON(a) }
                else if let f = doc.userFlows.first(where: { $0.id == otherId }) { relatedJSON = encodeToJSON(f) }

                text += "### \(direction) \(rel): \(otherId) (\(label))\n\n"
                if let rJSON = relatedJSON {
                    text += "<details>\n<summary>Full spec</summary>\n\n```json\n\(rJSON)\n```\n</details>\n\n"
                }
            }
        }

        // 5. Implementation order position
        for (i, group) in doc.implementationOrder.enumerated() {
            if group.contains(specId) {
                text += "## Build Order\n\nGroup \(i + 1) of \(doc.implementationOrder.count)"
                if i > 0 {
                    let deps = doc.implementationOrder[0..<i].flatMap { $0 }
                    text += " (depends on: \(deps.joined(separator: ", ")))"
                }
                text += "\n\n"
                break
            }
        }

        return toolResult(id: id, text: text)
    }

    private func toolGetProjectContext(id: JSONRPCId?) -> JSONRPCResponse {
        let docSet = store.loadDocumentSet()
        let doc = store.load()

        guard doc != nil || docSet?.brd != nil else {
            return toolError(id: id, message: "No project documents found. Run a Design workflow first.")
        }

        var text = "# Project Context\n\n"

        // Tech stack
        if let ts = doc?.meta.techStack, !ts.isEmpty {
            text += "## Tech Stack\n\n"
            for (key, value) in ts.sorted(by: { $0.key < $1.key }) {
                text += "- **\(key)**: \(value)\n"
            }
            text += "\n"
        }

        // BRD: problem + objectives + scope
        if let brd = docSet?.brd {
            text += "## Problem Statement\n\n\(brd.problemStatement)\n\n"
            if !brd.businessObjectives.isEmpty {
                text += "## Business Objectives\n\n"
                for obj in brd.businessObjectives { text += "- \(obj)\n" }
                text += "\n"
            }
            text += "## Scope\n\n"
            if !brd.scope.inScope.isEmpty {
                text += "**In scope**: \(brd.scope.inScope.joined(separator: "; "))\n\n"
            }
            if !brd.scope.outOfScope.isEmpty {
                text += "**Out of scope**: \(brd.scope.outOfScope.joined(separator: "; "))\n\n"
            }
            if !brd.scope.mvpBoundary.isEmpty {
                text += "**MVP boundary**: \(brd.scope.mvpBoundary)\n\n"
            }
        }

        // MVP scope from plan
        if let plan = docSet?.plan {
            text += "## MVP Scope\n\n"
            if !plan.mvpScope.includedSpecIds.isEmpty {
                text += "**Included**: \(plan.mvpScope.includedSpecIds.joined(separator: ", "))\n\n"
            }
            if !plan.mvpScope.excludedSpecIds.isEmpty {
                text += "**Post-MVP**: \(plan.mvpScope.excludedSpecIds.joined(separator: ", "))\n\n"
            }
            if !plan.mvpScope.rationale.isEmpty {
                text += "**Rationale**: \(plan.mvpScope.rationale)\n\n"
            }
        }

        // Reference anchors
        if let refs = doc?.meta.referenceAnchors, !refs.isEmpty {
            text += "## Reference Anchors\n\n"
            text += "Visual references that define this project's art direction.\n\n"
            for ref in refs {
                text += "- **\(ref.productName)** (\(ref.category)): \(ref.aspect)"
                if let url = ref.searchURL {
                    text += " — search: \(url)"
                }
                text += "\n"
            }
            text += "\nDo NOT use emoji as visual elements. Follow visual_spec in screen specs.\n\n"
        }

        return toolResult(id: id, text: text)
    }

    private func toolGetTestScenarios(id: JSONRPCId?, specId: String?) -> JSONRPCResponse {
        guard let docSet = store.loadDocumentSet(), let testDoc = docSet.test else {
            return toolError(id: id, message: "No test scenarios document found. Run a Design workflow and export first.")
        }

        let scenarios: [TestScenario]
        if let specId = specId {
            scenarios = testDoc.scenarios.filter { $0.specId == specId }
            if scenarios.isEmpty {
                return toolResult(id: id, text: "No test scenarios found for spec '\(specId)'")
            }
        } else {
            scenarios = testDoc.scenarios
        }

        var text = "# Test Scenarios"
        if let specId = specId { text += " for \(specId)" }
        text += " (\(scenarios.count) total)\n\n"

        let grouped = Dictionary(grouping: scenarios, by: \.priority)
        for priority in ["critical", "important", "nice-to-have"] {
            guard let items = grouped[priority], !items.isEmpty else { continue }
            text += "## \(priority.capitalized) (\(items.count))\n\n"
            for s in items {
                text += "- **[\(s.id)]** \(s.name) [\(s.category)]\n"
                if !s.preconditions.isEmpty {
                    text += "  Preconditions: \(s.preconditions.joined(separator: "; "))\n"
                }
                text += "  Expected: \(s.expectedResult)\n"
            }
            text += "\n"
        }

        return toolResult(id: id, text: text)
    }

    private func toolGetMilestonePlan(id: JSONRPCId?) -> JSONRPCResponse {
        guard let docSet = store.loadDocumentSet(), let plan = docSet.plan else {
            return toolError(id: id, message: "No implementation plan found. Run a Design workflow and export first.")
        }

        let md = PlanMarkdownRenderer.render(plan)
        return toolResult(id: id, text: md)
    }

    private func toolReloadDocuments(id: JSONRPCId?) -> JSONRPCResponse {
        let docSet = store.reloadDocumentSet()
        let doc = store.load()

        if let doc = doc {
            let specCount = doc.screens.count + doc.dataModels.count + doc.apiEndpoints.count + doc.userFlows.count
            var parts = ["\(specCount) design specs (\(doc.screens.count) screens, \(doc.dataModels.count) models, \(doc.apiEndpoints.count) APIs, \(doc.userFlows.count) flows)"]
            if docSet?.brd != nil { parts.append("BRD") }
            if let test = docSet?.test { parts.append("\(test.scenarios.count) test scenarios") }
            if docSet?.plan != nil { parts.append("implementation plan") }
            return toolResult(id: id, text: "Reloaded: \(parts.joined(separator: ", "))")
        } else {
            return toolError(id: id, message: "No design.json found in \(store.projectRoot)/.lao/")
        }
    }

    // MARK: - Helpers

    private func send(_ response: JSONRPCResponse) {
        guard let data = try? encoder.encode(response),
              let json = String(data: data, encoding: .utf8) else { return }
        print(json)
        fflush(stdout)
    }

    private func makeResource(uri: String, name: String, description: String, mimeType: String) -> JSONValue {
        .object([
            "uri": .string(uri),
            "name": .string(name),
            "description": .string(description),
            "mimeType": .string(mimeType)
        ])
    }

    private func encodeToJSON<T: Encodable>(_ value: T) -> String? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func toolResult(id: JSONRPCId?, text: String) -> JSONRPCResponse {
        .success(id: id, result: .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(text)
                ])
            ]),
            "isError": .bool(false)
        ]))
    }

    private func toolError(id: JSONRPCId?, message: String) -> JSONRPCResponse {
        .success(id: id, result: .object([
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(message)
                ])
            ]),
            "isError": .bool(true)
        ]))
    }

    private func specLabel(_ specId: String, doc: DesignDocument) -> String {
        if let s = doc.screens.first(where: { $0.id == specId }) { return s.name }
        if let m = doc.dataModels.first(where: { $0.id == specId }) { return m.name }
        if let a = doc.apiEndpoints.first(where: { $0.id == specId }) { return "\(a.method) \(a.path)" }
        if let f = doc.userFlows.first(where: { $0.id == specId }) { return f.name }
        return specId
    }

    private func matches(_ values: String..., query q: String) -> Bool {
        values.contains { $0.lowercased().contains(q) }
    }
}

// MARK: - Markdown Renderer (standalone, no app dependency)

enum DesignDocumentMarkdownRenderer {
    static func render(_ doc: DesignDocument) -> String {
        var md = "# \(doc.meta.projectName) — Design Specification\n\n"
        md += "**Type**: \(doc.meta.projectType)  \n"
        md += "**Version**: \(doc.meta.version)\n\n"

        if let ts = doc.meta.techStack, !ts.isEmpty {
            md += "**Tech Stack**: \(ts.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }.joined(separator: " | "))\n\n"
        }

        if !doc.meta.summary.isEmpty {
            md += "## Overview\n\n\(doc.meta.summary)\n\n"
        }

        // Screens
        if !doc.screens.isEmpty {
            md += "---\n\n## Screens\n\n"
            for s in doc.screens {
                md += "### \(s.id): \(s.name)\n\n"
                if !s.purpose.isEmpty { md += "**Purpose**: \(s.purpose)\n\n" }
                if !s.entryCondition.isEmpty { md += "**Entry**: \(s.entryCondition)\n\n" }
                if !s.exitTo.isEmpty {
                    md += "**Navigates to**: \(s.exitTo.map { "[\($0)](#\($0))" }.joined(separator: ", "))\n\n"
                }
                if !s.states.isEmpty {
                    md += "**States**: \(s.states.keys.sorted().joined(separator: " | "))\n\n"
                }
                md += renderAdditionalProperties(s.additionalProperties)
            }
        }

        // Data Models
        if !doc.dataModels.isEmpty {
            md += "---\n\n## Data Models\n\n"
            for m in doc.dataModels {
                md += "### \(m.id): \(m.name)\n\n"
                if !m.description.isEmpty { md += "\(m.description)\n\n" }
                if !m.fields.isEmpty {
                    md += "| Field | Type | Required | Description |\n|------|------|----------|-------------|\n"
                    for f in m.fields {
                        md += "| \(f.name) | \(f.type) | \(f.required ? "Yes" : "No") | \(f.description) |\n"
                    }
                    md += "\n"
                }
                md += renderAdditionalProperties(m.additionalProperties)
            }
        }

        // API Endpoints
        if !doc.apiEndpoints.isEmpty {
            md += "---\n\n## API Endpoints\n\n"
            for a in doc.apiEndpoints {
                md += "### \(a.id): \(a.name)\n\n"
                if !a.method.isEmpty { md += "**Endpoint**: `\(a.method) \(a.path)`\n\n" }
                if !a.description.isEmpty { md += "\(a.description)\n\n" }
                if !a.auth.isEmpty { md += "**Auth**: \(a.auth)\n\n" }
                md += renderAdditionalProperties(a.additionalProperties)
            }
        }

        // User Flows
        if !doc.userFlows.isEmpty {
            md += "---\n\n## User Flows\n\n"
            for f in doc.userFlows {
                md += "### \(f.id): \(f.name)\n\n"
                if !f.trigger.isEmpty { md += "**Trigger**: \(f.trigger)\n\n" }
                if !f.steps.isEmpty {
                    for step in f.steps {
                        md += "\(step.order). [\(step.actor)] \(step.action)\n"
                    }
                    md += "\n"
                }
                if !f.successOutcome.isEmpty { md += "**Success**: \(f.successOutcome)\n\n" }
                md += renderAdditionalProperties(f.additionalProperties)
            }
        }

        // Cross References
        if !doc.crossReferences.isEmpty {
            md += "---\n\n## Cross References\n\n"
            md += "| Source | Relation | Target |\n|--------|----------|--------|\n"
            for ref in doc.crossReferences {
                let rel = ref.relationType.replacingOccurrences(of: "_", with: " ")
                md += "| [\(ref.sourceId)](#\(ref.sourceId)) | \(rel) | [\(ref.targetId)](#\(ref.targetId)) |\n"
            }
            md += "\n"
        }

        // Implementation Order
        if !doc.implementationOrder.isEmpty {
            md += "---\n\n## Implementation Order\n\n"
            for (i, group) in doc.implementationOrder.enumerated() {
                md += "\(i + 1). **Group \(i + 1)**: \(group.map { "[\($0)](#\($0))" }.joined(separator: ", "))\n"
            }
            md += "\n"
        }

        return md
    }

    // MARK: - Additional Properties Renderer

    /// Renders well-known additionalProperties keys as structured Markdown sections,
    /// and any remaining unknown keys as a JSON details block.
    private static func renderAdditionalProperties(_ props: [String: JSONValue]) -> String {
        guard !props.isEmpty else { return "" }
        var md = ""

        // Well-known keys rendered as dedicated sections
        let wellKnown: [(key: String, label: String)] = [
            ("implementation_notes", "Implementation Notes"),
            ("implementation_hints", "Implementation Hints"),
            ("api_calls", "API Calls"),
            ("state_management", "State Management"),
            ("access_patterns", "Access Patterns"),
            ("migration_notes", "Migration Notes"),
            ("pagination", "Pagination"),
            ("example_request", "Example Request"),
            ("example_response", "Example Response"),
            ("request_body_schema", "Request Body Schema"),
            ("response_schema", "Response Schema"),
        ]

        var renderedKeys = Set<String>()
        for (key, label) in wellKnown {
            guard let value = props[key] else { continue }
            renderedKeys.insert(key)
            md += "**\(label)**:\n"
            switch value {
            case .string(let s):
                md += "\(s)\n\n"
            case .object(let dict):
                for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                    md += "- **\(k)**: \(jsonValueToString(v))\n"
                }
                md += "\n"
            case .array(let arr):
                for item in arr {
                    md += "- \(jsonValueToString(item))\n"
                }
                md += "\n"
            default:
                md += "\(jsonValueToString(value))\n\n"
            }
        }

        // Remaining unknown keys as collapsed JSON
        let remaining = props.filter { !renderedKeys.contains($0.key) }
        if !remaining.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(remaining),
               let json = String(data: data, encoding: .utf8) {
                md += "<details>\n<summary>Additional properties</summary>\n\n```json\n\(json)\n```\n</details>\n\n"
            }
        }

        return md
    }

    private static func jsonValueToString(_ value: JSONValue) -> String {
        switch value {
        case .string(let s): return s
        case .number(let n):
            // Render integers without decimal point
            if n == n.rounded(.towardZero) && !n.isInfinite {
                return "\(Int(n))"
            }
            return "\(n)"
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .object, .array:
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            if let data = try? encoder.encode(value), let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "\(value)"
        }
    }

    // MARK: - Design Document Schema

    static let designDocumentSchema: String = {
        // Prefer bundled resource (kept in sync with docs/design-document.schema.json)
        if let url = Bundle.module.url(forResource: "design-document.schema", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        // Fallback: inline copy (for environments where Bundle.module is unavailable)
        return fallbackDesignDocumentSchema
    }()

    private static let fallbackDesignDocumentSchema: String = """
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "$id": "https://lao.leewaystudio.com/schemas/design-document/v1",
      "title": "LAO Design Document",
      "description": "Structured design document generated by LAO Design workflow, optimized for AI development tool consumption.",
      "type": "object",
      "required": ["meta", "screens", "dataModels", "apiEndpoints", "userFlows", "crossReferences", "implementationOrder"],
      "properties": {
        "meta": { "$ref": "#/$defs/DesignMeta" },
        "screens": { "type": "array", "items": { "$ref": "#/$defs/DesignScreenSpec" } },
        "dataModels": { "type": "array", "items": { "$ref": "#/$defs/DesignDataModelSpec" } },
        "apiEndpoints": { "type": "array", "items": { "$ref": "#/$defs/DesignAPISpec" } },
        "userFlows": { "type": "array", "items": { "$ref": "#/$defs/DesignUserFlowSpec" } },
        "crossReferences": { "type": "array", "items": { "$ref": "#/$defs/DesignCrossReference" } },
        "implementationOrder": { "type": "array", "description": "Groups of spec IDs that can be implemented in parallel. Earlier groups must complete before later ones.", "items": { "type": "array", "items": { "type": "string" } } }
      },
      "additionalProperties": false,
      "$defs": {
        "DesignMeta": {
          "type": "object",
          "required": ["version", "projectName", "projectType", "generatedAt", "sourceRequestId", "summary"],
          "properties": {
            "version": { "type": "string", "description": "Schema version", "default": "1.0" },
            "projectName": { "type": "string" },
            "projectType": { "type": "string", "description": "e.g. 'ios-app', 'web-app', 'api-server'" },
            "generatedAt": { "type": "string", "format": "date-time", "description": "ISO 8601 timestamp" },
            "sourceRequestId": { "type": "string", "description": "UUID of the originating workflow request" },
            "summary": { "type": "string", "description": "One-paragraph project summary" },
            "techStack": { "type": "object", "additionalProperties": { "type": "string" }, "description": "Optional tech stack info, e.g. { language, framework, platform, database, other }" }
          },
          "additionalProperties": false
        },
        "DesignScreenSpec": {
          "type": "object",
          "required": ["id", "name", "purpose", "entryCondition", "exitTo", "components", "interactions", "states", "edgeCases", "additionalProperties"],
          "properties": {
            "id": { "type": "string", "pattern": "^screen-", "description": "Slug identifier, e.g. 'screen-login'" },
            "name": { "type": "string" },
            "purpose": { "type": "string" },
            "entryCondition": { "type": "string", "description": "When/how the user arrives at this screen" },
            "exitTo": { "type": "array", "items": { "type": "string" }, "description": "Screen slugs this screen can navigate to" },
            "components": { "type": "array", "description": "Nested component tree" },
            "interactions": { "type": "array", "description": "User interaction definitions" },
            "states": { "type": "object", "additionalProperties": { "type": "string" }, "description": "State name to description mapping" },
            "edgeCases": { "type": "array", "items": { "type": "string" } },
            "additionalProperties": { "type": "object", "description": "Extension fields: api_calls (APIs this screen invokes), state_management (local/shared state), data_source on components, implementation_notes" }
          },
          "additionalProperties": false
        },
        "DesignFieldSpec": {
          "type": "object",
          "required": ["name", "type", "required", "description"],
          "properties": {
            "name": { "type": "string" },
            "type": { "type": "string", "description": "Data type, e.g. 'String', 'Int', 'UUID', 'Date'" },
            "required": { "type": "boolean", "default": false },
            "description": { "type": "string", "default": "" }
          },
          "additionalProperties": false
        },
        "DesignRelationshipSpec": {
          "type": "object",
          "required": ["targetEntity", "type", "description"],
          "properties": {
            "targetEntity": { "type": "string", "description": "Target model slug or name" },
            "type": { "type": "string", "enum": ["one-to-one", "one-to-many", "many-to-many"] },
            "description": { "type": "string", "default": "" }
          },
          "additionalProperties": false
        },
        "DesignDataModelSpec": {
          "type": "object",
          "required": ["id", "name", "description", "fields", "relationships", "indexes", "businessRules", "additionalProperties"],
          "properties": {
            "id": { "type": "string", "pattern": "^model-", "description": "Slug identifier, e.g. 'model-user'" },
            "name": { "type": "string" },
            "description": { "type": "string", "default": "" },
            "fields": { "type": "array", "items": { "$ref": "#/$defs/DesignFieldSpec" } },
            "relationships": { "type": "array", "items": { "$ref": "#/$defs/DesignRelationshipSpec" } },
            "indexes": { "type": "array", "description": "Index definitions" },
            "businessRules": { "type": "array", "items": { "type": "string" } },
            "additionalProperties": { "type": "object", "description": "Extension fields: access_patterns (query patterns), migration_notes, field-level default/validation, implementation_notes" }
          },
          "additionalProperties": false
        },
        "DesignParameterSpec": {
          "type": "object",
          "required": ["name", "in", "type", "required", "description"],
          "properties": {
            "name": { "type": "string" },
            "in": { "type": "string", "enum": ["path", "query", "header"], "description": "Parameter location" },
            "type": { "type": "string" },
            "required": { "type": "boolean", "default": false },
            "description": { "type": "string", "default": "" }
          },
          "additionalProperties": false
        },
        "DesignErrorResponseSpec": {
          "type": "object",
          "required": ["code", "message"],
          "properties": {
            "code": { "type": "integer", "description": "HTTP status code" },
            "message": { "type": "string" }
          },
          "additionalProperties": false
        },
        "DesignAPISpec": {
          "type": "object",
          "required": ["id", "name", "method", "path", "description", "parameters", "errorResponses", "auth", "additionalProperties"],
          "properties": {
            "id": { "type": "string", "pattern": "^api-", "description": "Slug identifier, e.g. 'api-get-users'" },
            "name": { "type": "string" },
            "method": { "type": "string", "enum": ["GET", "POST", "PUT", "PATCH", "DELETE", ""], "default": "" },
            "path": { "type": "string", "default": "" },
            "description": { "type": "string", "default": "" },
            "parameters": { "type": "array", "items": { "$ref": "#/$defs/DesignParameterSpec" } },
            "requestBody": { "description": "Request body schema (optional)" },
            "response": { "description": "Response schema (optional)" },
            "errorResponses": { "type": "array", "items": { "$ref": "#/$defs/DesignErrorResponseSpec" } },
            "auth": { "type": "string", "default": "", "description": "Authentication requirement, e.g. 'bearer', 'api-key'" },
            "additionalProperties": { "type": "object", "description": "Extension fields: request_body_schema, response_schema (typed schemas), pagination, example_request, example_response, implementation_hints, implementation_notes" }
          },
          "additionalProperties": false
        },
        "DesignFlowStep": {
          "type": "object",
          "required": ["order", "actor", "action"],
          "properties": {
            "order": { "type": "integer", "description": "Step sequence number (1-based)" },
            "actor": { "type": "string", "description": "Who performs this step, e.g. 'user', 'system'" },
            "action": { "type": "string", "description": "What the actor does" },
            "screenId": { "type": "string", "description": "Optional reference to a screen slug" }
          },
          "additionalProperties": false
        },
        "DesignDecisionPoint": {
          "type": "object",
          "required": ["condition", "yes", "no"],
          "properties": {
            "condition": { "type": "string" },
            "yes": { "type": "string", "description": "Outcome when condition is true" },
            "no": { "type": "string", "description": "Outcome when condition is false" }
          },
          "additionalProperties": false
        },
        "DesignErrorPath": {
          "type": "object",
          "required": ["atStep", "error", "handling"],
          "properties": {
            "atStep": { "type": "integer", "description": "Step number where error can occur" },
            "error": { "type": "string", "description": "Error condition" },
            "handling": { "type": "string", "description": "How the error is handled" }
          },
          "additionalProperties": false
        },
        "DesignUserFlowSpec": {
          "type": "object",
          "required": ["id", "name", "trigger", "steps", "decisionPoints", "successOutcome", "errorPaths", "relatedScreens", "relatedAPIs", "additionalProperties"],
          "properties": {
            "id": { "type": "string", "pattern": "^flow-", "description": "Slug identifier, e.g. 'flow-onboarding'" },
            "name": { "type": "string" },
            "trigger": { "type": "string", "default": "", "description": "What initiates this flow" },
            "steps": { "type": "array", "items": { "$ref": "#/$defs/DesignFlowStep" } },
            "decisionPoints": { "type": "array", "items": { "$ref": "#/$defs/DesignDecisionPoint" } },
            "successOutcome": { "type": "string", "default": "" },
            "errorPaths": { "type": "array", "items": { "$ref": "#/$defs/DesignErrorPath" } },
            "relatedScreens": { "type": "array", "items": { "type": "string" }, "description": "Screen slugs referenced by this flow" },
            "relatedAPIs": { "type": "array", "items": { "type": "string" }, "description": "API slugs referenced by this flow" },
            "additionalProperties": { "type": "object", "description": "Extension fields for flow-specific data" }
          },
          "additionalProperties": false
        },
        "DesignCrossReference": {
          "type": "object",
          "required": ["sourceId", "targetId", "relationType"],
          "properties": {
            "sourceId": { "type": "string", "description": "Spec slug of the source" },
            "targetId": { "type": "string", "description": "Spec slug of the target" },
            "relationType": { "type": "string", "enum": ["navigates_to", "depends_on", "uses", "calls"], "description": "Type of relationship" },
            "description": { "type": "string", "description": "Optional description of the relationship" }
          },
          "additionalProperties": false
        }
      }
    }
    """
}

// MARK: - BRD Markdown Renderer

enum BRDMarkdownRenderer {
    static func render(_ brd: BusinessRequirementsDocument) -> String {
        var md = "# \(brd.meta.projectName) — Business Requirements Document\n\n"
        md += "**Generated**: \(ISO8601DateFormatter().string(from: brd.meta.generatedAt))\n\n"

        md += "## Problem Statement\n\n\(brd.problemStatement)\n\n"

        if !brd.targetUsers.isEmpty {
            md += "---\n\n## Target Users\n\n"
            for user in brd.targetUsers {
                md += "### \(user.name)\n\n\(user.description)\n\n"
                if !user.needs.isEmpty {
                    md += "**Needs**: \(user.needs.joined(separator: "; "))\n\n"
                }
            }
        }

        if !brd.businessObjectives.isEmpty {
            md += "---\n\n## Business Objectives\n\n"
            for obj in brd.businessObjectives { md += "- \(obj)\n" }
            md += "\n"
        }

        if !brd.successMetrics.isEmpty {
            md += "---\n\n## Success Metrics\n\n"
            md += "| Metric | Target | Measurement |\n|--------|--------|-------------|\n"
            for m in brd.successMetrics {
                md += "| \(m.metric) | \(m.target) | \(m.measurement) |\n"
            }
            md += "\n"
        }

        md += "---\n\n## Scope\n\n"
        if !brd.scope.inScope.isEmpty {
            md += "**In Scope**:\n"
            for item in brd.scope.inScope { md += "- \(item)\n" }
            md += "\n"
        }
        if !brd.scope.outOfScope.isEmpty {
            md += "**Out of Scope**:\n"
            for item in brd.scope.outOfScope { md += "- \(item)\n" }
            md += "\n"
        }
        if !brd.scope.mvpBoundary.isEmpty {
            md += "**MVP Boundary**: \(brd.scope.mvpBoundary)\n\n"
        }

        if !brd.constraints.isEmpty {
            md += "---\n\n## Constraints\n\n"
            for c in brd.constraints { md += "- \(c)\n" }
            md += "\n"
        }
        if !brd.assumptions.isEmpty {
            md += "## Assumptions\n\n"
            for a in brd.assumptions { md += "- \(a)\n" }
            md += "\n"
        }

        let nfr = brd.nonFunctionalRequirements
        if !nfr.performance.isEmpty || !nfr.security.isEmpty || !nfr.accessibility.isEmpty || !nfr.scalability.isEmpty {
            md += "---\n\n## Non-Functional Requirements\n\n"
            if !nfr.performance.isEmpty {
                md += "### Performance\n\n"
                for p in nfr.performance { md += "- \(p)\n" }
                md += "\n"
            }
            if !nfr.security.isEmpty {
                md += "### Security\n\n"
                for s in nfr.security { md += "- \(s)\n" }
                md += "\n"
            }
            if !nfr.accessibility.isEmpty {
                md += "### Accessibility\n\n"
                for a in nfr.accessibility { md += "- \(a)\n" }
                md += "\n"
            }
            if !nfr.scalability.isEmpty {
                md += "### Scalability\n\n"
                for s in nfr.scalability { md += "- \(s)\n" }
                md += "\n"
            }
        }

        return md
    }
}

// MARK: - Plan Markdown Renderer

enum PlanMarkdownRenderer {
    static func render(_ plan: ImplementationPlanDocument) -> String {
        var md = "# \(plan.meta.projectName) — Implementation Plan\n\n"
        md += "**Generated**: \(ISO8601DateFormatter().string(from: plan.meta.generatedAt))\n\n"

        // MVP Scope
        md += "## MVP Scope\n\n"
        if !plan.mvpScope.includedSpecIds.isEmpty {
            md += "**Included**: \(plan.mvpScope.includedSpecIds.joined(separator: ", "))\n\n"
        }
        if !plan.mvpScope.excludedSpecIds.isEmpty {
            md += "**Post-MVP**: \(plan.mvpScope.excludedSpecIds.joined(separator: ", "))\n\n"
        }
        if !plan.mvpScope.rationale.isEmpty {
            md += "**Rationale**: \(plan.mvpScope.rationale)\n\n"
        }

        // Milestones
        if !plan.milestones.isEmpty {
            md += "---\n\n## Milestones\n\n"
            for (i, m) in plan.milestones.enumerated() {
                md += "### \(i + 1). \(m.name)\n\n"
                if !m.description.isEmpty { md += "\(m.description)\n\n" }
                if !m.specIds.isEmpty { md += "**Specs**: \(m.specIds.joined(separator: ", "))\n\n" }
            }
        }

        // Phases
        if !plan.phases.isEmpty {
            md += "---\n\n## Implementation Phases\n\n"
            for phase in plan.phases {
                md += "### \(phase.name)\n\n"
                md += "**Specs**: \(phase.specIds.joined(separator: ", "))\n\n"
                if !phase.dependencies.isEmpty {
                    md += "**Depends on**: \(phase.dependencies.joined(separator: ", "))\n\n"
                }
            }
        }

        // Project Standards
        md += "---\n\n## Project Standards\n\n"
        if !plan.projectStandards.directoryStructure.isEmpty {
            md += "**Directory Structure**: \(plan.projectStandards.directoryStructure)\n\n"
        }
        if !plan.projectStandards.namingConventions.isEmpty {
            md += "**Naming Conventions**: \(plan.projectStandards.namingConventions)\n\n"
        }
        if !plan.projectStandards.errorHandlingPattern.isEmpty {
            md += "**Error Handling**: \(plan.projectStandards.errorHandlingPattern)\n\n"
        }
        if !plan.projectStandards.codingStyle.isEmpty {
            md += "**Coding Style**: \(plan.projectStandards.codingStyle)\n\n"
        }

        // Infrastructure
        let infra = plan.infrastructureNotes
        if !infra.deployment.isEmpty || !infra.cicd.isEmpty || !infra.environment.isEmpty || !infra.migration.isEmpty {
            md += "---\n\n## Infrastructure\n\n"
            if !infra.deployment.isEmpty { md += "**Deployment**: \(infra.deployment)\n\n" }
            if !infra.cicd.isEmpty { md += "**CI/CD**: \(infra.cicd)\n\n" }
            if !infra.environment.isEmpty { md += "**Environment**: \(infra.environment)\n\n" }
            if !infra.migration.isEmpty { md += "**Migration**: \(infra.migration)\n\n" }
        }

        return md
    }
}

// MARK: - Test Markdown Renderer

enum TestMarkdownRenderer {
    static func render(_ doc: TestScenariosDocument) -> String {
        var md = "# \(doc.meta.projectName) — Test Scenarios\n\n"
        md += "**Generated**: \(ISO8601DateFormatter().string(from: doc.meta.generatedAt))\n"
        md += "**Total scenarios**: \(doc.scenarios.count)\n\n"

        let priorityOrder = ["critical", "important", "nice-to-have"]
        let grouped = Dictionary(grouping: doc.scenarios, by: \.priority)

        for priority in priorityOrder {
            guard let scenarios = grouped[priority], !scenarios.isEmpty else { continue }
            md += "---\n\n## \(priority.capitalized) (\(scenarios.count))\n\n"

            let byCategory = Dictionary(grouping: scenarios, by: \.category)
            for (category, items) in byCategory.sorted(by: { $0.key < $1.key }) {
                md += "### \(category) (\(items.count))\n\n"
                for scenario in items {
                    md += "#### \(scenario.name)\n\n"
                    md += "- **Spec**: `\(scenario.specId)`\n"
                    if !scenario.preconditions.isEmpty {
                        md += "- **Preconditions**: \(scenario.preconditions.joined(separator: "; "))\n"
                    }
                    if !scenario.steps.isEmpty {
                        md += "- **Steps**:\n"
                        for step in scenario.steps {
                            md += "  \(step.order). \(step.action)"
                            if !step.expectedOutcome.isEmpty { md += " → \(step.expectedOutcome)" }
                            md += "\n"
                        }
                    }
                    md += "- **Expected**: \(scenario.expectedResult)\n\n"
                }
            }
        }

        return md
    }
}

// MARK: - Entry Point

func main() {
    let args = CommandLine.arguments

    // Parse --project-root
    var projectRoot: String?
    for (i, arg) in args.enumerated() {
        if arg == "--project-root", i + 1 < args.count {
            projectRoot = args[i + 1]
        }
    }

    // Fallback: current directory
    let root = projectRoot ?? FileManager.default.currentDirectoryPath

    let store = DesignDocumentStore(projectRoot: root)
    let server = MCPServer(store: store)

    // Log to stderr (stdout is for JSON-RPC)
    fputs("[LAO MCP] Server started. Project root: \(root)\n", stderr)

    server.run()
}

main()
