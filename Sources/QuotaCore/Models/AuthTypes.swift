public enum AuthStatus: Sendable, Equatable {
    case signedOut
    case signedIn(accountHint: String?)
    case expired
    case invalid
}

public enum AuthMethod: Sendable, Equatable {
    /// Manual session / cookie paste (Codex and fallbacks).
    case sessionToken(String)
    /// Read credentials from the installed vendor app (Cursor Desktop).
    case localApp
}

public struct AuthUnsupportedMethodError: Error, Sendable {}
