import AppKit
import Foundation
import LAODomain

public final class OpenPanelDirectoryPicker {
    public init() {}

    @MainActor
    public func pickDirectory(prompt: String = "Select Directory") async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }

        // Persist a security-scoped bookmark so the app retains access after restart.
        SecurityScopedBookmarkStore.shared.saveBookmark(for: url)

        return url
    }
}

// MARK: - Security-Scoped Bookmark Store

/// Manages security-scoped bookmarks for user-selected directories.
/// When the app is sandboxed, macOS revokes access to user-selected folders after restart.
/// Bookmarks allow the app to regain access without re-prompting.
public final class SecurityScopedBookmarkStore: @unchecked Sendable {
    public static let shared = SecurityScopedBookmarkStore()

    private let lock = NSLock()
    /// URLs that are currently access-started (must be stopped on app termination).
    private var activeURLs: [String: URL] = [:]

    private static let bookmarksKey = "LAO_SecurityScopedBookmarks"

    private init() {}

    // MARK: - Save

    /// Create and persist a security-scoped bookmark for the given URL.
    public func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var bookmarks = loadAllBookmarkData()
            bookmarks[url.path] = data
            UserDefaults.standard.set(bookmarks, forKey: Self.bookmarksKey)
        } catch {
            // Bookmark creation may fail outside sandbox; silently ignore.
        }
    }

    // MARK: - Restore

    /// Restore access to all previously bookmarked directories.
    /// Call this once at app launch.
    public func restoreAllBookmarks() {
        let bookmarks = loadAllBookmarkData()
        for (path, data) in bookmarks {
            restoreBookmark(data: data, path: path)
        }
    }

    /// Restore access to a specific path if a bookmark exists.
    /// Returns `true` if access was successfully started.
    @discardableResult
    public func restoreBookmark(forPath path: String) -> Bool {
        let bookmarks = loadAllBookmarkData()
        guard let data = bookmarks[path] else { return false }
        return restoreBookmark(data: data, path: path)
    }

    // MARK: - Access Control

    /// Start accessing a security-scoped resource for a given path.
    /// The caller should pair this with `stopAccessing(path:)` when done,
    /// though for project directories we typically keep them active.
    @discardableResult
    public func startAccessing(path: String) -> Bool {
        // Read the active URL while holding the lock, then release BEFORE
        // calling restoreBookmark — which also acquires the lock internally.
        // NSLock is not reentrant, so holding it across the call would deadlock.
        lock.lock()
        let existingURL = activeURLs[path]
        lock.unlock()

        if let url = existingURL {
            _ = url.startAccessingSecurityScopedResource()
            return true
        }
        return restoreBookmark(forPath: path)
    }

    /// Stop accessing a security-scoped resource.
    public func stopAccessing(path: String) {
        lock.lock()
        defer { lock.unlock() }
        if let url = activeURLs.removeValue(forKey: path) {
            url.stopAccessingSecurityScopedResource()
        }
    }

    /// Stop accessing all active resources. Call on app termination.
    public func stopAll() {
        lock.lock()
        let urls = activeURLs
        activeURLs.removeAll()
        lock.unlock()

        for (_, url) in urls {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Private

    private func loadAllBookmarkData() -> [String: Data] {
        (UserDefaults.standard.dictionary(forKey: Self.bookmarksKey) as? [String: Data]) ?? [:]
    }

    @discardableResult
    private func restoreBookmark(data: Data, path: String) -> Bool {
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Re-save the bookmark if it became stale
                saveBookmark(for: url)
            }

            if url.startAccessingSecurityScopedResource() {
                lock.lock()
                activeURLs[path] = url
                lock.unlock()
                return true
            }
        } catch {
            // Stale or invalid bookmark; user will need to re-select
        }
        return false
    }
}
