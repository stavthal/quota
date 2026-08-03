public enum ProviderID: String, Codable, Sendable, CaseIterable, Identifiable {
    case cursor
    case codex
    case copilot
    case grok

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cursor: "Cursor"
        case .codex: "ChatGPT"
        case .copilot: "Copilot"
        case .grok: "Grok"
        }
    }

    public var assetIconName: String {
        switch self {
        case .cursor: "CursorIcon"
        case .codex: "OpenAIIcon"
        case .copilot: "CopilotIcon"
        case .grok: "GrokIcon"
        }
    }

    /// Official marks except Cursor are shown as white template icons on a dark plate.
    public var usesWhiteTintedIcon: Bool {
        switch self {
        case .cursor: false
        case .codex, .copilot, .grok: true
        }
    }
}
