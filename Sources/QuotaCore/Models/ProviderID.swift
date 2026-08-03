public enum ProviderID: String, Codable, Sendable, CaseIterable, Identifiable {
    case cursor
    case codex
    case copilot

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cursor: "Cursor"
        case .codex: "ChatGPT"
        case .copilot: "Copilot"
        }
    }

    public var assetIconName: String {
        switch self {
        case .cursor: "CursorIcon"
        case .codex: "OpenAIIcon"
        case .copilot: "CopilotIcon"
        }
    }
}
