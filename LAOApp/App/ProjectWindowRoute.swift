import Foundation

/// Route value for opening a per-project workspace window.
struct ProjectWindowRoute: Hashable, Codable, Sendable {
    let projectId: UUID
}

/// Scoped deep-link payload that includes the project ID so each workspace
/// window can filter notifications relevant to its own project.
struct DeepLinkPayload {
    let projectId: UUID
    let requestId: UUID
}
