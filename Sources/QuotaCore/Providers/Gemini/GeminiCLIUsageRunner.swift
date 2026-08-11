import Foundation

/// Runs Antigravity's own documented headless usage check (`agy -p "/usage" --output-format
/// json`) and returns its raw stdout. Never reads or exports any Antigravity credential —
/// authentication is entirely the installed `agy` binary's own concern.
public protocol GeminiCLIUsageRunning: Sendable {
    func fetchUsage() async throws -> Data
}

public struct GeminiCLIUsageRunner: GeminiCLIUsageRunning, Sendable {
    private let timeoutSeconds: Int

    public init(timeoutSeconds: Int = 20) {
        self.timeoutSeconds = timeoutSeconds
    }

    public func fetchUsage() async throws -> Data {
        let agy = try Self.resolveAgyPath()
        return try await Self.runAgy(agy, timeoutSeconds: timeoutSeconds)
    }

    private static func resolveAgyPath() throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/agy",
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to a PATH lookup, matching CopilotProvider's `gh` resolution.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "agy"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
            throw GeminiProviderError.cliMissing
        }
        return path
    }

    private static func runAgy(_ agy: String, timeoutSeconds: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: agy)
                process.arguments = [
                    "-p", "/usage",
                    "--output-format", "json",
                    "--print-timeout", "\(timeoutSeconds)s",
                ]
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: GeminiProviderError.cliMissing)
                    return
                }
                process.waitUntilExit()
                let out = stdout.fileHandleForReading.readDataToEndOfFile()
                let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if process.terminationStatus != 0 {
                    continuation.resume(
                        throwing: GeminiProviderError.cliFailed(
                            err.isEmpty ? "agy exited \(process.terminationStatus)" : err
                        )
                    )
                    return
                }
                continuation.resume(returning: out)
            }
        }
    }
}
