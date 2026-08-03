import Foundation

/// Live Copilot provider. Uses the logged-in GitHub CLI (`gh api /copilot_internal/user`) — no Keychain copy.
public actor CopilotProvider: Provider {
    public nonisolated let id: ProviderID = .copilot
    public nonisolated let displayName = "Copilot"

    private var trackingEnabled: Bool

    public init(trackingEnabled: Bool) {
        self.trackingEnabled = trackingEnabled
    }

    public func authStatus() async -> AuthStatus {
        guard trackingEnabled else { return .signedOut }
        do {
            let dto = try await fetchDTO()
            return .signedIn(accountHint: dto.login ?? dto.copilotPlan ?? "Copilot")
        } catch {
            return .signedOut
        }
    }

    public func authenticate(using method: AuthMethod) async throws {
        _ = method
        _ = try await fetchDTO()
        trackingEnabled = true
    }

    public func clearAuth() async throws {
        trackingEnabled = false
    }

    public func fetchSnapshot() async throws -> UsageSnapshot {
        guard trackingEnabled else { throw CopilotProviderError.notAuthenticated }
        let dto = try await fetchDTO()
        return try CopilotUsageParser.snapshot(from: dto)
    }

    public func healthCheck() async -> ProviderHealth {
        switch await authStatus() {
        case .signedOut, .expired, .invalid:
            return .authRequired
        case .signedIn:
            return .healthy
        }
    }

    private func fetchDTO() async throws -> CopilotUsageDTO {
        let gh = try Self.resolveGHPath()
        let data = try await Self.runGH(gh, arguments: ["api", "/copilot_internal/user"])
        do {
            return try JSONDecoder().decode(CopilotUsageDTO.self, from: data)
        } catch {
            let preview = String(data: data.prefix(160), encoding: .utf8) ?? "non-utf8"
            throw CopilotProviderError.ghFailed("Decode failed: \(error.localizedDescription) · \(preview)")
        }
    }

    private static func resolveGHPath() throws -> String {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to PATH lookup.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "gh"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
            throw CopilotProviderError.ghMissing
        }
        return path
    }

    private static func runGH(_ gh: String, arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: gh)
                    process.arguments = arguments
                    let stdout = Pipe()
                    let stderr = Pipe()
                    process.standardOutput = stdout
                    process.standardError = stderr
                    try process.run()
                    process.waitUntilExit()
                    let out = stdout.fileHandleForReading.readDataToEndOfFile()
                    let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    if process.terminationStatus != 0 {
                        continuation.resume(
                            throwing: CopilotProviderError.ghFailed(
                                err.isEmpty ? "gh exited \(process.terminationStatus)" : err
                            )
                        )
                        return
                    }
                    continuation.resume(returning: out)
                } catch {
                    continuation.resume(throwing: CopilotProviderError.ghFailed(error.localizedDescription))
                }
            }
        }
    }
}
