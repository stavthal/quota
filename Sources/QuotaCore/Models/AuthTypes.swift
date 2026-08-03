public enum AuthStatus: Sendable, Equatable {
    case signedOut
    case signedIn(accountHint: String?)
    case expired
    case invalid
}

public enum AuthMethod: Sendable, Equatable {
    case sessionToken(String)
}
