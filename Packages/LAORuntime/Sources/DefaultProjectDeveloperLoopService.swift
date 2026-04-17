import Darwin
import Foundation
import LAODomain
import LAOServices

public final class DefaultProjectDeveloperLoopService: ProjectDeveloperLoopService, @unchecked Sendable {
    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func suggestedPreset(for project: Project) async -> DeveloperLoopPreset? {
        detectPreset(rootPath: project.rootPath)
    }

    public func run(_ kind: DeveloperLoopCommandKind, for project: Project) async throws -> DeveloperLoopRunResult {
        guard let preset = detectPreset(rootPath: project.rootPath) else {
            throw DeveloperLoopServiceError.unsupportedProject
        }

        let command = command(for: kind, preset: preset)
        return try await runShell(
            command,
            kind: kind,
            rootPath: project.rootPath,
            artifactPath: artifactPath(for: kind, preset: preset)
        )
    }

    public func runLoop(for project: Project) async throws -> [DeveloperLoopRunResult] {
        let build = try await run(.build, for: project)
        guard build.succeeded else { return [build] }

        let launch = try await run(.launch, for: project)
        guard launch.succeeded else { return [build, launch] }

        let verify = try await run(.verify, for: project)
        return [build, launch, verify]
    }

    private func detectPreset(rootPath: String) -> DeveloperLoopPreset? {
        guard !rootPath.isEmpty else { return nil }

        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let packagePath = rootURL.appendingPathComponent("mac/Package.swift").path
        let xcodeprojPath = rootURL.appendingPathComponent("mac/LAO.xcodeproj").path

        guard fileManager.fileExists(atPath: packagePath),
              fileManager.fileExists(atPath: xcodeprojPath) else {
            return nil
        }

        return DeveloperLoopPreset(
            title: "LAO macOS App",
            summary: "Build, run, verify, and UI-check the registered LAO workspace without leaving the app.",
            buildCommand: "cd mac && swift build",
            launchCommand: "cd mac && pkill -x LAO >/dev/null 2>&1 || true && BUILD_BIN=$(swift build --show-bin-path) && mkdir -p ../.lao/logs && nohup \"$BUILD_BIN/LAO\" > ../.lao/logs/lao-dev-loop.log 2>&1 &",
            verifyCommand: "cd mac && swift test",
            uiCheckCommand: "cd mac && pkill -x LAO >/dev/null 2>&1 || true && rm -rf ../.lao/ui-snapshots/latest && mkdir -p ../.lao/ui-snapshots/latest && LAO_UI_SNAPSHOT_DIR=\"$PWD/../.lao/ui-snapshots/latest\" xcodebuild test -project LAO.xcodeproj -scheme LAO -destination 'platform=macOS' -only-testing:LAOUITests/LAOFounderModeSnapshotUITests/testCaptureFounderModeScreens",
            uiSnapshotDirectory: rootURL.appendingPathComponent(".lao/ui-snapshots/latest").path
        )
    }

    private func command(for kind: DeveloperLoopCommandKind, preset: DeveloperLoopPreset) -> String {
        switch kind {
        case .build:
            preset.buildCommand
        case .launch:
            preset.launchCommand
        case .verify:
            preset.verifyCommand
        case .uiCheck:
            preset.uiCheckCommand
        case .fullLoop:
            preset.buildCommand
        }
    }

    private func runShell(
        _ command: String,
        kind: DeveloperLoopCommandKind,
        rootPath: String,
        artifactPath: String?
    ) async throws -> DeveloperLoopRunResult {
        if !rootPath.isEmpty {
            SecurityScopedBookmarkStore.shared.startAccessing(path: rootPath)
        }

        return try await Task.detached(priority: .userInitiated) { [environment] in
            let startedAt = Date()
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = URL(fileURLWithPath: rootPath)
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var mergedEnvironment = environment
            mergedEnvironment["PATH"] = Self.normalizedExecutablePATH(current: mergedEnvironment["PATH"])
            process.environment = mergedEnvironment

            try process.run()
            process.waitUntilExit()

            let stdout = String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let combinedOutput = Self.trimmedOutput([stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n"))
            let finishedAt = Date()

            return DeveloperLoopRunResult(
                kind: kind,
                succeeded: process.terminationStatus == 0,
                command: command,
                exitCode: process.terminationStatus,
                output: combinedOutput,
                artifactPath: artifactPath,
                startedAt: startedAt,
                finishedAt: finishedAt
            )
        }.value
    }

    private func artifactPath(for kind: DeveloperLoopCommandKind, preset: DeveloperLoopPreset) -> String? {
        switch kind {
        case .uiCheck:
            return preset.uiSnapshotDirectory
        default:
            return nil
        }
    }

    private static func trimmedOutput(_ output: String) -> String {
        let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 20_000 else { return normalized }
        return String(normalized.suffix(20_000))
    }

    private static func normalizedExecutablePATH(current: String?) -> String {
        let sandboxHome = NSHomeDirectory()
        let realHome = ProcessInfo.processInfo.environment["HOME"]
            ?? (getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir) })
            ?? sandboxHome

        var defaults = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(realHome)/.local/bin",
        ]
        if sandboxHome != realHome {
            defaults.append("\(sandboxHome)/.local/bin")
        }

        var seen = Set<String>()
        var ordered: [String] = []

        for entry in (current ?? "").split(separator: ":").map(String.init) {
            guard !entry.isEmpty, !seen.contains(entry) else { continue }
            seen.insert(entry)
            ordered.append(entry)
        }

        for entry in defaults {
            guard !seen.contains(entry) else { continue }
            seen.insert(entry)
            ordered.append(entry)
        }

        return ordered.joined(separator: ":")
    }
}

private enum DeveloperLoopServiceError: LocalizedError {
    case unsupportedProject

    var errorDescription: String? {
        switch self {
        case .unsupportedProject:
            return "No developer loop preset is available for this project root yet."
        }
    }
}
