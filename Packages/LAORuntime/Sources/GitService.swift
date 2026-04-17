import Foundation

/// Wraps git CLI operations for Design workflow version control.
public final class GitService: @unchecked Sendable {

    public enum GitError: LocalizedError {
        case notAGitRepo
        case commandFailed(String)

        public var errorDescription: String? {
            switch self {
            case .notAGitRepo:
                "Not a git repository."
            case .commandFailed(let detail):
                "Git command failed: \(detail)"
            }
        }
    }

    public init() {}

    // MARK: - Query

    public func isGitRepo(rootPath: String) -> Bool {
        let result = runGit("rev-parse --is-inside-work-tree", in: rootPath)
        return result.exitCode == 0 && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    public func currentBranch(rootPath: String) -> String? {
        let result = runGit("rev-parse --abbrev-ref HEAD", in: rootPath)
        guard result.exitCode == 0 else { return nil }
        let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }

    public func status(rootPath: String) -> String {
        let result = runGit("status --short", in: rootPath)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func diffStat(rootPath: String) -> String {
        let result = runGit("diff --stat", in: rootPath)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func log(count: Int = 5, rootPath: String) -> String {
        let result = runGit("log --oneline -\(count)", in: rootPath)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func hasStagedOrUnstagedChanges(rootPath: String) -> Bool {
        let result = runGit("status --porcelain", in: rootPath)
        return !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Mutations

    public func createBranch(name: String, rootPath: String) throws {
        let result = runGit("checkout -b \(shellEscape(name))", in: rootPath)
        guard result.exitCode == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    public func checkout(branch: String, rootPath: String) throws {
        let result = runGit("checkout \(shellEscape(branch))", in: rootPath)
        guard result.exitCode == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    public func addAll(rootPath: String) throws {
        let result = runGit("add -A", in: rootPath)
        guard result.exitCode == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    /// Commits staged changes and returns the short commit hash.
    @discardableResult
    public func commit(message: String, rootPath: String) throws -> String {
        let result = runGit("commit -m \(shellEscape(message))", in: rootPath)
        guard result.exitCode == 0 else {
            throw GitError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        // Extract short hash from commit output
        let hashResult = runGit("rev-parse --short HEAD", in: rootPath)
        let hash = hashResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hashResult.exitCode == 0, !hash.isEmpty else {
            throw GitError.commandFailed("Commit succeeded but failed to read commit hash.")
        }
        return hash
    }

    // MARK: - Private

    private struct ShellResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Default timeout for git commands (30 seconds).
    private static let defaultTimeout: TimeInterval = 30

    private func runGit(_ args: String, in rootPath: String, timeout: TimeInterval = GitService.defaultTimeout) -> ShellResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args.components(separatedBy: " ").flatMap { component -> [String] in
            // Handle shell-escaped single-quoted arguments
            if component.hasPrefix("'") && component.hasSuffix("'") && component.count > 2 {
                return [String(component.dropFirst().dropLast())]
            }
            return [component]
        }
        process.currentDirectoryURL = URL(fileURLWithPath: rootPath)
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return ShellResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        // Read pipe data BEFORE waitUntilExit to avoid deadlock when output exceeds pipe buffer.
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        // Wait with timeout to prevent hanging on unresponsive processes.
        let didFinish = process.waitUntilExitWithTimeout(timeout)
        if !didFinish {
            process.terminate()
            return ShellResult(exitCode: -1, stdout: "", stderr: "Git command timed out after \(Int(timeout))s.")
        }

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }

    private func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - Process Timeout

private extension Process {
    /// Waits for the process to exit, returning `true` if it finished within the timeout.
    func waitUntilExitWithTimeout(_ timeout: TimeInterval) -> Bool {
        let sema = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            self.waitUntilExit()
            sema.signal()
        }
        return sema.wait(timeout: .now() + timeout) == .success
    }
}
