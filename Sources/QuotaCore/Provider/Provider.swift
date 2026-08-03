public protocol Provider: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }

    func authStatus() async -> AuthStatus
    func authenticate(using method: AuthMethod) async throws
    func clearAuth() async throws
    func fetchSnapshot() async throws -> UsageSnapshot
    func healthCheck() async -> ProviderHealth
}
