public enum ProviderID: String, Codable, Sendable, CaseIterable, Identifiable {
    case cursor
    case codex

    public var id: String { rawValue }
}
