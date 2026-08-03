public enum ProviderHealth: Sendable, Equatable {
    case healthy
    case authRequired
    case networkError(String)
    case brokenParser(String)
    case keychainDenied
}
