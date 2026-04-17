import Foundation

public enum LAODocumentFileWriter {
    /// Writes content as a `.md` file under `{rootPath}/.lao/docs/` and returns the relative path.
    /// - Parameters:
    ///   - title: Document title (used to generate the filename slug)
    ///   - content: Markdown content to write
    ///   - rootPath: Project root path (where `.lao/docs/` will be created)
    /// - Returns: Relative file path from rootPath (e.g. `.lao/docs/2026-03-11_summary-meeting.md`)
    public static func write(title: String, content: String, rootPath: String) throws -> String {
        let docsDir = (rootPath as NSString).appendingPathComponent(".lao/docs")

        // Ensure directory exists
        try FileManager.default.createDirectory(
            atPath: docsDir,
            withIntermediateDirectories: true
        )

        // Build filename: {date}_{title-slug}.md
        let dateStr = Self.dateString()
        let slug = Self.slugify(title)
        let filename = "\(dateStr)_\(slug).md"
        let fullPath = (docsDir as NSString).appendingPathComponent(filename)

        // Avoid overwriting: append counter if file exists
        var finalPath = fullPath
        var counter = 2
        while FileManager.default.fileExists(atPath: finalPath) {
            let numberedFilename = "\(dateStr)_\(slug)_\(counter).md"
            finalPath = (docsDir as NSString).appendingPathComponent(numberedFilename)
            counter += 1
        }

        try content.write(toFile: finalPath, atomically: true, encoding: .utf8)

        // Return relative path from rootPath
        let relativePath = ".lao/docs/" + (finalPath as NSString).lastPathComponent
        return relativePath
    }

    /// Writes content under `{rootPath}/.lao/{ideaId}/{requestId}/{filename}.md`.
    /// Creates the idea/request subfolder if it doesn't exist.
    /// - Parameters:
    ///   - title: Document title (used to generate the filename slug)
    ///   - content: Markdown content to write
    ///   - rootPath: Project root path
    ///   - ideaId: The idea ID used as the parent subfolder name
    ///   - requestId: The workflow request ID used as the subfolder name
    /// - Returns: Relative file path from rootPath (e.g. `.lao/{ideaId}/{requestId}/2026-03-14_design.md`)
    public static func writeForIdea(
        title: String,
        content: String,
        rootPath: String,
        ideaId: String,
        requestId: String
    ) throws -> String {
        let docsDir = (rootPath as NSString)
            .appendingPathComponent(".lao/\(ideaId)/\(requestId)")

        try FileManager.default.createDirectory(
            atPath: docsDir,
            withIntermediateDirectories: true
        )

        let dateStr = Self.dateString()
        let slug = Self.slugify(title)
        let filename = "\(dateStr)_\(slug).md"
        let fullPath = (docsDir as NSString).appendingPathComponent(filename)

        // Avoid overwriting
        var finalPath = fullPath
        var counter = 2
        while FileManager.default.fileExists(atPath: finalPath) {
            let numberedFilename = "\(dateStr)_\(slug)_\(counter).md"
            finalPath = (docsDir as NSString).appendingPathComponent(numberedFilename)
            counter += 1
        }

        try content.write(toFile: finalPath, atomically: true, encoding: .utf8)

        let relativePath = ".lao/\(ideaId)/\(requestId)/" + (finalPath as NSString).lastPathComponent
        return relativePath
    }

    // MARK: - Private

    private static func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func slugify(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let slug = text
            .lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        // Limit length
        let maxLen = 60
        if slug.count > maxLen {
            return String(slug.prefix(maxLen))
        }
        return slug.isEmpty ? "document" : slug
    }
}
