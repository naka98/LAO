import Foundation

/// Detects project type and runs build/test commands for Design workflow verification.
public final class DesignTestExecutionService: @unchecked Sendable {

    public enum ProjectType: String {
        case swiftPackage
        case xcodeProject
        case nodeJS
        case python
        case unknown
    }

    public struct TestResult: Sendable {
        public let buildExitCode: Int32
        public let buildOutput: String
        public let testExitCode: Int32?
        public let testOutput: String?
        public let overallPassed: Bool
        public let failureSummary: String
    }

    public init() {}

    // MARK: - Project Type Detection

    public func detectProjectType(rootPath: String) -> ProjectType {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: rootPath)) ?? []

        if contents.contains("Package.swift") { return .swiftPackage }
        if contents.contains(where: { $0.hasSuffix(".xcodeproj") }) { return .xcodeProject }
        if contents.contains("package.json") { return .nodeJS }
        if contents.contains("pyproject.toml") || contents.contains("setup.py") || contents.contains("requirements.txt") {
            return .python
        }
        return .unknown
    }

    // MARK: - Build & Test

    public func runBuildAndTest(rootPath: String, projectType: ProjectType) async -> TestResult {
        switch projectType {
        case .swiftPackage:
            return await runSwiftBuildAndTest(rootPath: rootPath)
        case .xcodeProject:
            return await runXcodeBuildAndTest(rootPath: rootPath)
        case .nodeJS:
            return await runNodeBuildAndTest(rootPath: rootPath)
        case .python:
            return await runPythonTest(rootPath: rootPath)
        case .unknown:
            return TestResult(
                buildExitCode: 0,
                buildOutput: "Unknown project type — skipped verification.",
                testExitCode: nil,
                testOutput: nil,
                overallPassed: true,
                failureSummary: ""
            )
        }
    }

    // MARK: - Swift Package

    private func runSwiftBuildAndTest(rootPath: String) async -> TestResult {
        let build = runShell("swift build 2>&1", in: rootPath)
        guard build.exitCode == 0 else {
            return TestResult(
                buildExitCode: build.exitCode,
                buildOutput: String(build.output.suffix(2000)),
                testExitCode: nil,
                testOutput: nil,
                overallPassed: false,
                failureSummary: extractFailureSummary(from: build.output, prefix: "Swift build")
            )
        }

        let test = runShell("swift test 2>&1", in: rootPath)
        return TestResult(
            buildExitCode: build.exitCode,
            buildOutput: String(build.output.suffix(1000)),
            testExitCode: test.exitCode,
            testOutput: String(test.output.suffix(2000)),
            overallPassed: test.exitCode == 0,
            failureSummary: test.exitCode == 0 ? "" : extractFailureSummary(from: test.output, prefix: "Swift test")
        )
    }

    // MARK: - Xcode Project

    private func runXcodeBuildAndTest(rootPath: String) async -> TestResult {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: rootPath)) ?? []
        guard let proj = contents.first(where: { $0.hasSuffix(".xcodeproj") }) else {
            return TestResult(
                buildExitCode: -1,
                buildOutput: "No .xcodeproj found.",
                testExitCode: nil,
                testOutput: nil,
                overallPassed: false,
                failureSummary: "No Xcode project found in directory."
            )
        }

        let projName = (proj as NSString).deletingPathExtension
        let build = runShell("xcodebuild -project \(shellEscape(proj)) -scheme \(shellEscape(projName)) build 2>&1 | tail -20", in: rootPath)
        return TestResult(
            buildExitCode: build.exitCode,
            buildOutput: String(build.output.suffix(2000)),
            testExitCode: nil,
            testOutput: nil,
            overallPassed: build.exitCode == 0,
            failureSummary: build.exitCode == 0 ? "" : extractFailureSummary(from: build.output, prefix: "Xcode build")
        )
    }

    // MARK: - Node.js

    private func runNodeBuildAndTest(rootPath: String) async -> TestResult {
        let hasNodeModules = FileManager.default.fileExists(atPath: (rootPath as NSString).appendingPathComponent("node_modules"))
        if !hasNodeModules {
            let install = runShell("npm install 2>&1", in: rootPath)
            guard install.exitCode == 0 else {
                return TestResult(
                    buildExitCode: install.exitCode,
                    buildOutput: String(install.output.suffix(2000)),
                    testExitCode: nil,
                    testOutput: nil,
                    overallPassed: false,
                    failureSummary: extractFailureSummary(from: install.output, prefix: "npm install")
                )
            }
        }

        let build = runShell("npm run build --if-present 2>&1", in: rootPath)
        guard build.exitCode == 0 else {
            return TestResult(
                buildExitCode: build.exitCode,
                buildOutput: String(build.output.suffix(2000)),
                testExitCode: nil,
                testOutput: nil,
                overallPassed: false,
                failureSummary: extractFailureSummary(from: build.output, prefix: "npm build")
            )
        }

        let test = runShell("npm test --if-present 2>&1", in: rootPath)
        return TestResult(
            buildExitCode: build.exitCode,
            buildOutput: String(build.output.suffix(1000)),
            testExitCode: test.exitCode,
            testOutput: String(test.output.suffix(2000)),
            overallPassed: test.exitCode == 0,
            failureSummary: test.exitCode == 0 ? "" : extractFailureSummary(from: test.output, prefix: "npm test")
        )
    }

    // MARK: - Python

    private func runPythonTest(rootPath: String) async -> TestResult {
        let test = runShell("python3 -m pytest --tb=short 2>&1 || python3 -m unittest discover -s . 2>&1", in: rootPath)
        return TestResult(
            buildExitCode: 0,
            buildOutput: "Python — no build step.",
            testExitCode: test.exitCode,
            testOutput: String(test.output.suffix(2000)),
            overallPassed: test.exitCode == 0,
            failureSummary: test.exitCode == 0 ? "" : extractFailureSummary(from: test.output, prefix: "Python test")
        )
    }

    // MARK: - Helpers

    private struct ShellOutput {
        let exitCode: Int32
        let output: String
    }

    /// Default timeout for build/test commands (5 minutes).
    private static let defaultTimeout: TimeInterval = 300

    private func runShell(_ command: String, in rootPath: String, timeout: TimeInterval = DesignTestExecutionService.defaultTimeout) -> ShellOutput {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: rootPath)
        process.standardOutput = pipe
        process.standardError = pipe

        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin"]
        let current = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extra + [current]).joined(separator: ":")
        process.environment = env

        do {
            try process.run()
        } catch {
            return ShellOutput(exitCode: -1, output: error.localizedDescription)
        }

        // Read pipe data BEFORE waitUntilExit to avoid deadlock when output exceeds pipe buffer.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        // Wait with timeout to prevent hanging on unresponsive builds/tests.
        let sema = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            process.waitUntilExit()
            sema.signal()
        }
        let didFinish = sema.wait(timeout: .now() + timeout) == .success
        if !didFinish {
            process.terminate()
            return ShellOutput(exitCode: -1, output: String(decoding: data, as: UTF8.self) + "\n[Timed out after \(Int(timeout))s]")
        }

        return ShellOutput(
            exitCode: process.terminationStatus,
            output: String(decoding: data, as: UTF8.self)
        )
    }

    private func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func extractFailureSummary(from output: String, prefix: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        let summary = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.suffix(5).joined(separator: "\n")
        return "\(prefix) failed:\n\(summary)"
    }
}
