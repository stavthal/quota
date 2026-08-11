public enum ProviderID: String, Codable, Sendable, CaseIterable, Identifiable {
    case cursor
    case codex
    case claude
    case copilot
    case grok
    case opencode
    case gemini

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cursor: "Cursor"
        case .codex: "ChatGPT"
        case .claude: "Claude Code"
        case .copilot: "Copilot"
        case .grok: "Grok"
        case .opencode: "OpenCode"
        case .gemini: "Gemini"
        }
    }

    public var assetIconName: String {
        switch self {
        case .cursor: "CursorIcon"
        case .codex: "OpenAIIcon"
        case .claude: "ClaudeIcon"
        case .copilot: "CopilotIcon"
        case .grok: "GrokIcon"
        case .opencode: "OpenCodeIcon"
        case .gemini: "GeminiIcon"
        }
    }

    /// Official marks except Cursor and Gemini are shown as white template icons on a dark plate.
    public var usesWhiteTintedIcon: Bool {
        switch self {
        case .cursor, .claude, .gemini: false
        case .codex, .copilot, .grok, .opencode: true
        }
    }
}
